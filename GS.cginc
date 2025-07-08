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

#ifdef _ALPHA_BLENDING_ON
Texture2DArray<float> _TexOrder;
#include "MichaelSort/SortUtils.cginc"
#endif

#ifdef UNITY_REVERSED_Z
#define MIN_CLIP_Z_VALUE 0.f
#define DEPTH_SEMANTICS SV_DepthLessEqual
#else
#define MIN_CLIP_Z_VALUE UNITY_NEAR_CLIP_VALUE
#define DEPTH_SEMANTICS SV_Depth
#endif

#if !defined(_ALPHA_BLENDING_ON)
#define _WRITE_DEPTH_ON
#define QUADPOS_Z 1 // should be -1 for OpenGL, except SV_DepthGreaterEqual doesn't work on my machine
#else
#define QUADPOS_Z 0
#endif

#define MIN_ALPHA_THRESHOLD_RCP 54.5981500331f // 2√2 sigma
#define MAX_CUTOFF2 (2 * log(MIN_ALPHA_THRESHOLD_RCP))
#define MIN_ALPHA_THRESHOLD (1 / MIN_ALPHA_THRESHOLD_RCP)

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

float3x3 RotationMatrixFromQuaternion(float4 quat)
{
    float x = quat.x;
    float y = quat.y;
    float z = quat.z;
    float w = quat.w;
    return float3x3(
        1-2*(y*y + z*z),   2*(x*y - w*z),   2*(x*z + w*y),
          2*(x*y + w*z), 1-2*(x*x + z*z),   2*(y*z - w*x),
          2*(x*z - w*y),   2*(y*z + w*x), 1-2*(x*x + y*y)
    );
}


// invert function from https://answers.unity.com/questions/218333/shader-inversefloat4x4-function.html, thank you d4rk
float4x4 inverse(float4x4 input)
{
    #define minor(a,b,c) determinant(float3x3(input.a, input.b, input.c))
    //determinant(float3x3(input._22_23_23, input._32_33_34, input._42_43_44))

    float4x4 cofactors = float4x4(
        minor(_22_23_24, _32_33_34, _42_43_44),
        -minor(_21_23_24, _31_33_34, _41_43_44),
        minor(_21_22_24, _31_32_34, _41_42_44),
        -minor(_21_22_23, _31_32_33, _41_42_43),

        -minor(_12_13_14, _32_33_34, _42_43_44),
        minor(_11_13_14, _31_33_34, _41_43_44),
        -minor(_11_12_14, _31_32_34, _41_42_44),
        minor(_11_12_13, _31_32_33, _41_42_43),

        minor(_12_13_14, _22_23_24, _42_43_44),
        -minor(_11_13_14, _21_23_24, _41_43_44),
        minor(_11_12_14, _21_22_24, _41_42_44),
        -minor(_11_12_13, _21_22_23, _41_42_43),

        -minor(_12_13_14, _22_23_24, _32_33_34),
        minor(_11_13_14, _21_23_24, _31_33_34),
        -minor(_11_12_14, _21_22_24, _31_32_34),
        minor(_11_12_13, _21_22_23, _31_32_33)
    );
    #undef minor
    return transpose(cofactors) / determinant(input);
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
    float4 position : SV_POSITION;
    // float4 planeX : TEXCOORD0;
    // float4 planeY : TEXCOORD1;

    float3 world_pos : TEXCOORD0;
    nointerpolation float4 color  : TEXCOORD1;
    nointerpolation float4 rotation : TEXCOORD2;
    nointerpolation float3 pos : TEXCOORD3;
    nointerpolation float3 scale : TEXCOORD4;

    #ifdef _WRITE_DEPTH_ON
    float4 MT3 : TEXCOORD5;
    #endif
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

float compute_splat_rho(float3 ro, float3 rd, float3 pos, float4 rot, float3 rad) {
    ro = q_rotate(ro - pos, conj_q(rot)) * rad;  // rotate and scale position
    rd = q_rotate(rd, conj_q(rot)) * rad;  // rotate and scale direction
    float dt = dot(rd, -ro) / dot(rd, rd);  // time to intersection
    return length(ro + rd * dt); 
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

[maxvertexcount(24)]
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
    // Low opacity splats look kind of sus:
    // - Opaque: It's obvious why
    // - Alpha : We should be doing alpha blending in sRGB space, but VRC uses linear, 
    //           causing splats to look more opaque than they really are.
    if (splat.color.a < _AlphaCutoff) return;

    float4 splatClipPos = mul(UNITY_MATRIX_MVP, float4(splat.mean, 1));
    if (splatClipPos.w <= 0) return;


    float3 objCameraPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;
    o.color = float4(GammaToLinearSpace(splat.color), splat.color.a);
    o.rotation = splat.quat;
    o.pos = splat.mean - objCameraPos;
    o.scale = 1.0 / max(1e-6,splat.scale);

    // 3 orthogonal axes in unit-box space
    [unroll]
    for (int k = 0; k < 3; k++) {
        float3 axU =  GetAxis(k);
        float3 axV =  GetAxis((k + 1) % 3);    // next axis
        float3 axW =  GetAxis((k + 2) % 3);    // normal of the face pair

        [unroll]
        for (int i = 0; i < 4; i++) {
            float2 coord  = GetUV(i) * 2.0 - 1.0;          // map (0,1) → (-1,1)
            float3 local  = coord.x * axU + coord.y * axV + axW;
            float3 model  = unit_space_to_model(local, splat.mean, splat.quat, splat.scale);
            o.position   = UnityObjectToClipPos(float4(model,1));
            o.world_pos  = model - objCameraPos;                          // if you need it later
            triStream.Append(o);
        }
        triStream.RestartStrip();
    }

    // float3 objViewDir = normalize(input[0].objCameraPos.xyz - splat.mean);
    // #if _SH_ORDER > 0
    // splat.color.rgb = ShadeSH(splat.color, objViewDir, splat.shN);
    // #endif
    // o.color = float4(GammaToLinearSpace(splat.color), splat.color.a);

    // float3x3 rot = RotationMatrixFromQuaternion(splat.quat);
    // float3x3 rotScale = float3x3(
    //     rot[0] * splat.scale,
    //     rot[1] * splat.scale,
    //     rot[2] * splat.scale
    // );

    // // Perspective-correct splatting from https://github.com/fhahlbohm/depthtested-gaussian-raytracing-webgl
    // // MIT License, Copyright (c) 2025 Florian Hahlbohm
    // float4x4 T = float4x4(
    //     rotScale[0], splat.mean.x,
    //     rotScale[1], splat.mean.y,
    //     rotScale[2], splat.mean.z,
    //     0,0,0,1
    // );
    // float4x4 PMT = mul(UNITY_MATRIX_MVP, T);

    // float rho_cutoff = 2 * log(splat.color.a * MIN_ALPHA_THRESHOLD_RCP);
    // float4 t = float4(rho_cutoff, rho_cutoff, rho_cutoff, -1);
    // float4 center = mul(PMT, PMT[3] * t);
    // float d = center.w;
    // if (d == 0) return;
    // center /= d;
    // float4 extent = sqrt(max(center * center - mul(PMT * PMT, t / d), 0));
    // if (center.z - extent.z <= MIN_CLIP_Z_VALUE || center.z + extent.z >= 1) return;
    // #ifdef _WRITE_DEPTH_ON
    // o.MT3 = mul(UNITY_MATRIX_MV[2], T);
    // #endif

    // [unroll] for (uint vtxID = 0; vtxID < 4; vtxID ++)
    // {
    //     float2 quadPos = float2(vtxID & 1, (vtxID >> 1) & 1) * 2.0 - 1.0;
    //     o.vertex = center + extent * float4(quadPos, QUADPOS_Z, 0);
    //     o.planeX = PMT[0] - PMT[3] * o.vertex.x;
    //     o.planeY = PMT[1] - PMT[3] * o.vertex.y;
    //     triStream.Append(o);
    // }
}


// // inverse of LinearEyeDepth
// float EyeDepthToZBufferDepth(float z){
//     return (1. - z * _ZBufferParams.w) / (z * _ZBufferParams.z);
// }

// float4 frag(g2f i
// #ifdef _WRITE_DEPTH_ON
// , out float outDepth : DEPTH_SEMANTICS
// #endif
// ) : SV_Target
// {
//     UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

//     float3 m = i.planeX.w * i.planeY.xyz - i.planeX.xyz * i.planeY.w;
//     float3 d = cross(i.planeX.xyz, i.planeY.xyz);
//     float numerator = dot(m, m);
//     float denominator = dot(d, d);
//     if (numerator > MAX_CUTOFF2 * denominator) discard;
//     float alpha = exp(-0.5 * numerator / denominator) * abs(i.color.a);

//     #ifdef _WRITE_DEPTH_ON
//     float4 eval_point_diag = float4(cross(d, m) / denominator, 1);
//     float z = dot(i.MT3, eval_point_diag);
//     outDepth = EyeDepthToZBufferDepth(-z); // -Z forward viewspace
//     #endif

//     float4 color = float4(i.color.rgb, 1);
//     #ifdef _ALPHA_BLENDING_ON
//     color.a = alpha;
//     #endif
//     return color;
// }

float4 frag(g2f input) : SV_Target
{
    if (_ProjectionParams.z <= 2) discard;

    float3 ro = 0.0;//mul(unity_WorldToObject, float4(_WorldSpaceCameraPos.xyz, 1.0)).xyz;
    float3 rd = normalize(input.world_pos);

    float dist = compute_splat_rho(ro, rd, input.pos, input.rotation, input.scale);
    float rho = smoothstep(3.0, 0.0, dist);
    //if (rho < MAX_CUTOFF2) discard;
    return float4(input.color.rgb, rho * input.color.a);
}