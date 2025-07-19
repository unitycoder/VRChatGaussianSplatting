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
    float4 position : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2g {
    float4 position : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

struct g2f {
    float4 position: SV_POSITION;
    float2 quadPos: TEXCOORD0;
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
    uint id = geoPrimID * 32 + instanceID;

    if (id >= _SplatCount)  return;

    id += _SplatOffset; // offset for the current batch
    
    g2f o;
    UNITY_SETUP_INSTANCE_ID(input[0]);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input[0]);
    UNITY_INITIALIZE_OUTPUT(g2f, o);
    UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

    SplatData splat = LoadSplatDataRenderOrder(id);

    if (!splat.valid || (splat.color.a < _AlphaCutoff) || any(splat.scale > _ScaleCutoff)) return; 

    float3 splatWorldPos = mul(unity_ObjectToWorld, float4(splat.mean, 1)).xyz;
    float cameraDistance = length(splatWorldPos - _WorldSpaceCameraPos);
    if (_MinMaxSortDistance.x != _MinMaxSortDistance.y  && (cameraDistance < _MinMaxSortDistance.x || cameraDistance > _MinMaxSortDistance.y)) {
        return; // skip splats outside of the sorting distance range
    }

    float4 splatClipPos = mul(UNITY_MATRIX_VP, float4(splatWorldPos, 1));
    if (splatClipPos.w <= 0) return; // behind camera
    splatClipPos.xyz /= splatClipPos.w; // perspective divide
    if (all(splatClipPos.xy < -1.0) || all(splatClipPos.xy > 1.0)) return; // outside of view frustum

    o.color = splat.color;
    float scale_max = max(splat.scale.x, max(splat.scale.y, splat.scale.z));
    float3 clamped_scale = clamp(splat.scale, scale_max * _ThinThreshold, scale_max);

    // Project the ellipsoid onto the screen
    Ellipse ell = GetProjectedEllipsoid(splat.mean, 2.0 * clamped_scale, splat.quat);

    if(any(ell.size > 1.75)) {
        return;
    }

    float area = ell.size.x * ell.size.y;
    ell.size = max(ell.size * _ScreenParams, 1.75 * _AntiAliasing) / _ScreenParams; // ensure minimum size
    float areaPost = ell.size.x * ell.size.y;
    float areaScale = area / areaPost;
    o.color.a *= areaScale; // scale alpha by area ratio

    if (o.color.a < _AlphaCutoff || isnan(o.color.a)) {
        return; // skip splats with too small area or invalid alpha
    }

    [unroll] for (uint vtxID = 0; vtxID < 4; vtxID ++)
    {
        o.quadPos = float2(vtxID & 1, (vtxID >> 1) & 1) * 2.0 - 1.0;
        float2x2 rot = float2x2(ell.axis.x, -ell.axis.y, ell.axis.y, ell.axis.x);
        float2 ndc = ell.center + mul(rot, _QuadScale * o.quadPos * ell.size);
        o.position = float4(ndc, splatClipPos.z, 1.0);
        triStream.Append(o);
    }
}

#define SMOOTHSTEP_0 0.98
#define SMOOTHSTEP_1 1.02

//#define DEBUG_OUTLINES

float4 frag(g2f input) : SV_Target {
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    float dist2 = dot(input.quadPos, input.quadPos);
#ifdef DEBUG_OUTLINES
    return (dist2 < 1.0) ? float4(1, 0, 0, 1) : float4(0, 0, 0, 1); // red outline for debugging
#endif
    if (dist2 > SMOOTHSTEP_1) discard;  // skip outside of the ellipse
    float rho0 = exp(- 2.0 * dist2 * _GaussianMul * (_QuadScale * _QuadScale));
    float rho1 = smoothstep(SMOOTHSTEP_1, SMOOTHSTEP_0, dist2);
    float rho = input.color.a * rho1 * rho0;
    if (rho < 0.01) discard;  // skip regions with low density
    return float4(input.color.rgb * rho, rho);
}