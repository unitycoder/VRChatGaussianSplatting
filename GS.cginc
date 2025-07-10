#define UNITY_SHADER_NO_UPGRADE 1 
#pragma target 5.0
#pragma exclude_renderers gles
#pragma vertex vert
#pragma fragment frag
#pragma geometry geo

#include "UnityCG.cginc"
#include "GSData.cginc"
#include "GSMath.cginc"

struct appdata {
    float4 vertex : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2g {
    float4 vertex : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

struct g2f {
    float4 position: SV_POSITION;
    float2 splat_pos: TEXCOORD0;
    nointerpolation float4 color: TEXCOORD1;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2g vert(appdata v) {
    v2g o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2g, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    return o;
}

[maxvertexcount(4)]
[instance(32)]
void geo(point v2g input[1], inout TriangleStream<g2f> triStream, uint instanceID : SV_GSInstanceID, uint geoPrimID : SV_PrimitiveID) {
    uint splatCount = uint(_GS_Positions_TexelSize.z) * uint(_GS_Positions_TexelSize.w);
    uint id = geoPrimID * 32 + instanceID;

    if (id >= splatCount) return;

    g2f o;
    UNITY_SETUP_INSTANCE_ID(input[0]);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input[0]);
    UNITY_INITIALIZE_OUTPUT(g2f, o);
    UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

    SplatData splat = LoadSplatDataRenderOrder(id);
    if (splat.color.a < _AlphaCutoff) return; // skip splats with low alpha

    float4 splatClipPos = mul(UNITY_MATRIX_MVP, float4(splat.mean, 1));
    splatClipPos.xyz /= splatClipPos.w; // perspective divide
    if (splatClipPos.z <= 0) return; // behind camera
    if (all(splatClipPos.xy < -1.0) || all(splatClipPos.xy > 1.0)) return; // outside of view frustum

    float3 objCameraPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;
    o.color = float4(GammaToLinearSpace(splat.color), splat.color.a);
    float3 rad = 1.0 / max(1e-6,splat.scale);

    // All this clamping is required to avoid numerical instability of the ellipsoid projection
    float scale = clamp(sqrt(2.0 * (_SplatScale + log2(splat.color.a))), 0.1, 4.0);
    float scale_max = max(0.005, max(splat.scale.x, max(splat.scale.y, splat.scale.z)));
    float distance = length(splat.mean - objCameraPos);
    float3 clamped_scale = max(scale * clamp(splat.scale, scale_max * _ThinnessThreshold, scale_max), distance * _DistanceScaleThreshold * 0.8e-3);
    float ratio = length(scale * splat.scale / clamped_scale) / length(float3(1,1,1));
    o.color.a *= ratio * ratio; // fade splats that are too thin

    // Project the ellipsoid onto the screen
    Ellipse ell = GetProjectedEllipsoid(splat.mean, clamped_scale, splat.quat);

    if(any(ell.size > 1.75) || o.color.a < _AlphaCutoff) {
        // If the splat is too large or has low alpha, we skip it.
        return;
    }

    [unroll] for (uint vtxID = 0; vtxID < 4; vtxID ++)
    {
        float2 quadPos = (float2(vtxID & 1, (vtxID >> 1) & 1) * 2.0 - 1.0);
        float2x2 rot = float2x2(ell.axis.x, -ell.axis.y, ell.axis.y, ell.axis.x);
        float2 ndc = ell.center + mul(rot, quadPos * ell.size);
        o.position = float4(ndc, splatClipPos.z, 1.0);
        o.splat_pos = 0.5 * quadPos * _SplatScale / _GaussianScale;
        triStream.Append(o);
    }
}

float4 frag(g2f input) : SV_Target {
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    float rho = input.color.a * exp(-dot(input.splat_pos,input.splat_pos)*0.5);
    if (rho < 0.01) discard;  // skip regions with low density
    return float4(input.color.rgb, rho);
}