#define UNITY_SHADER_NO_UPGRADE 1 
#pragma target 5.0
//#pragma shader_feature_local _EditorMode
#pragma exclude_renderers gles
#pragma vertex vert
#pragma fragment frag
#pragma geometry geo

#include "UnityCG.cginc"
#include "GSData.cginc"
#include "GSMath.cginc"

float _EditorMode; // 1 if in editor mode, 0 otherwise

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
    float4 splat_pos: TEXCOORD0;
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

    if (id >= splatCount || (id >= _DisplayFirstNSplats && _DisplayFirstNSplats > 0)) {
        return; // skip if out of bounds or beyond the display limit
    }

    g2f o;
    UNITY_SETUP_INSTANCE_ID(input[0]);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input[0]);
    UNITY_INITIALIZE_OUTPUT(g2f, o);
    UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

    float3 objCameraPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;
    SplatData splat = LoadSplatDataRenderOrder(id, objCameraPos);
    if (splat.color.a < _AlphaCutoff) return; // skip splats with low alpha
    if (any(splat.scale > _ScaleCutoff)) return; // skip splats with too large scale

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
    // All this clamping is required to avoid numerical instability of the ellipsoid projection
    float scale = _SplatScale * sqrt(2);//*sqrt( -log2(splat.color.a));
    float scale_max = max(splat.scale.x, max(splat.scale.y, splat.scale.z));
    float3 clamped_scale = clamp(splat.scale, scale_max * _ThinThreshold, scale_max);

    // Project the ellipsoid onto the screen
    Ellipse ell = GetProjectedEllipsoid(splat.mean, scale * 2.0 * clamped_scale, splat.quat);

    if(any(ell.size > 1.75)) {
        return;
    }

    float minDist = _AntiAliasing / min(_ScreenParams.x, _ScreenParams.y);
    float area = ell.size.x * ell.size.y;
    ell.size = max(ell.size, minDist); // ensure minimum size
    float areaPost = ell.size.x * ell.size.y;
    float areaScale = area / areaPost;
    o.color.a *= areaScale; // scale alpha by area ratio

    if (o.color.a < _AlphaCutoff || isnan(o.color.a)) {
        return; // skip splats with too small area or invalid alpha
    }

    [unroll] for (uint vtxID = 0; vtxID < 4; vtxID ++)
    {
        float2 quadPos = (float2(vtxID & 1, (vtxID >> 1) & 1) * 2.0 - 1.0);
        float2x2 rot = float2x2(ell.axis.x, -ell.axis.y, ell.axis.y, ell.axis.x);
        float2 ndc = ell.center + mul(rot, quadPos * ell.size);
        o.position = float4(ndc, splatClipPos.z, 1.0);
        o.splat_pos = float4(scale * quadPos / _GaussianScale, quadPos);
        triStream.Append(o);
    }
}

float4 frag(g2f input) : SV_Target {
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    float2 steps = smoothstep(1.0, 0.85, abs(input.splat_pos.zw)); //make quad edges softer
    float rho = steps.x * steps.y * input.color.a * exp(-dot(input.splat_pos,input.splat_pos));
    if (rho < 0.01) discard;  // skip regions with low density
    bool validOrder = _GS_RenderOrder_TexelSize.z >= _GS_Positions_TexelSize.z;
    if(!validOrder) return float4(0.5 * input.color.rgb * rho, 0.0);
    return float4(input.color.rgb * rho, rho);
}