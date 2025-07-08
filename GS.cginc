#define UNITY_SHADER_NO_UPGRADE 1 
#pragma target 5.0
#pragma exclude_renderers gles
#pragma vertex vert
#pragma fragment frag
#pragma geometry geo

#include "UnityCG.cginc"
#include "SH.cginc"
Texture2D _GS_Positions, _GS_Scales, _GS_Rotations, _GS_Colors;
float4 _GS_Positions_TexelSize;
float _VRChatCameraMode, _AlphaCutoff, _Log2MinScale;
float _SplatScale;

#ifdef _ALPHA_BLENDING_ON
Texture2DArray<float> _TexOrder;
#include "MichaelSort/SortUtils.cginc"
#endif

struct SplatData
{
    float3 mean;
    float3 scale;
    float4 quat;
    float4 color;
    uint shN;
};

SplatData LoadSplatData(uint id)
{
    #ifdef _ALPHA_BLENDING_ON
    uint2 coord1 = IdToUV(id);
    uint slice = _VRChatCameraMode > 0;
    id = ASUINT_NO_DENORM(_TexOrder[uint3(coord1, slice)]);
    #endif
    uint2 coord = uint2(id % _GS_Positions_TexelSize.z, id / _GS_Positions_TexelSize.z);
    float4 means_raw = _GS_Positions[coord];
    float3 scale_raw = _GS_Scales[coord].xyz;
    // Without a low pass filter some splats can look too "thin", so we try to correct for this.
    // Only necessary if splats are trained without mip-splatting.
    scale_raw = max(_Log2MinScale, scale_raw);
    SplatData o;
    o.mean = means_raw.xyz;
    o.scale = scale_raw;
    o.quat = normalize(_GS_Rotations[coord]);
    o.color = _GS_Colors[coord];
    o.shN = f32tof16(means_raw.w);
    return o;
}

struct appdata
{
    float4 vertex : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2g
{
    float4 vertex : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

struct g2f
{
    float4 position: SV_POSITION;
    float3 world_pos: TEXCOORD0;
    nointerpolation float4 color: TEXCOORD1;
    nointerpolation float3 pos: TEXCOORD2;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2g vert(appdata v)
{
    UNITY_SETUP_INSTANCE_ID(v);
    v2g o;
    UNITY_INITIALIZE_OUTPUT(v2g, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    return o;
}

// rotate vector v by quaternion q
float3 q_rotate(float3 v, float4 q) {
    float3 t  = 2.0f * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}

float4 conj_q(float4 q) {
    return float4(-q.xyz, q.w);  // conjugate of quaternion
}

float3 unit_space_to_model(float3 p, float3 pos, float4 rot, float3 rad) {
    return q_rotate(p * rad, rot) + pos;  // rotate and scale position
}

#define BOX_SCALE 1.5

float3 GetAxis(int i) {
     return (i == 0) ? float3(BOX_SCALE,0,0) : (i == 1) ? float3(0,BOX_SCALE,0) : float3(0,0,BOX_SCALE); 
}
float2 GetUV(int i) { 
    return float2((i & 1), (i >> 1)); 
} 

[maxvertexcount(14)]
[instance(32)]
void geo(point v2g input[1], inout TriangleStream<g2f> triStream, uint instanceID : SV_GSInstanceID, uint geoPrimID : SV_PrimitiveID)
{
    UNITY_SETUP_INSTANCE_ID(input[0]);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input[0]);
    g2f o;
    UNITY_INITIALIZE_OUTPUT(g2f, o);
    UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(input[0], o);

    uint splatCount = uint(_GS_Positions_TexelSize.z) * uint(_GS_Positions_TexelSize.w);
    uint id = geoPrimID * 32 + instanceID;

    if (id >= splatCount) return;

    SplatData splat = LoadSplatData(id);
    if (splat.color.a < _AlphaCutoff) return; // skip splats with low alpha

    float4 splatClipPos = mul(UNITY_MATRIX_MVP, float4(splat.mean, 1));
    if (splatClipPos.w <= 0) return; // behind camera

    float3 objCameraPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;
    o.color = float4(GammaToLinearSpace(splat.color), splat.color.a);
    float3 rad = 1.0 / max(1e-6,splat.scale);
    o.pos = q_rotate(objCameraPos - splat.mean, conj_q(splat.quat)) * rad;

    float scale = clamp(sqrt(2.0 * (_SplatScale + log2(splat.color.a))), 0.1, 4.0);
    if(scale < 0.5) return; // skip splats that are too small

    // 8 cube corners in unit space
    static const float3 corner[8] = {
        float3(-1,-1,+1), float3(+1,-1,+1), float3(+1,+1,+1), float3(-1,+1,+1),
        float3(-1,-1,-1), float3(+1,-1,-1), float3(+1,+1,-1), float3(-1,+1,-1)
    };

    // 14-index strip that covers the cube (12 triangles)
    static const uint idx[14] = {0,1,3,2,6,1,5,0,4,3,7,6,4,5};

    [unroll] for (uint i = 0; i < 14; ++i)
    {
        uint k = idx[i];
        float3 local = corner[k]*scale;
        float3 model = unit_space_to_model(local, splat.mean, splat.quat, splat.scale);

        o.position = UnityObjectToClipPos(float4(model,1));
        o.world_pos = normalize(q_rotate(model - objCameraPos, conj_q(splat.quat)) * rad);
        triStream.Append(o);
    }
}

float4 frag(g2f input) : SV_Target
{
    float3 ro = input.pos;
    float3 rd = input.world_pos;
    float dt = dot(rd, -ro) / dot(rd, rd);  // time to intersection
    float3 splat_pos = ro + rd * dt; 
    float rho = exp(-dot(splat_pos,splat_pos)*0.5) * input.color.a;
    if (rho < 0.01) discard;  // skip regions with low density
    return float4(input.color.rgb, rho);
}