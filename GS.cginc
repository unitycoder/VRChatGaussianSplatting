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

float4x4 inverse(float4x4 m) {
    float a00 = m._11, a01 = m._12, a02 = m._13, a03 = m._14;
    float a10 = m._21, a11 = m._22, a12 = m._23, a13 = m._24;
    float a20 = m._31, a21 = m._32, a22 = m._33, a23 = m._34;
    float a30 = m._41, a31 = m._42, a32 = m._43, a33 = m._44;

    float b00 = a00 * a11 - a01 * a10;
    float b01 = a00 * a12 - a02 * a10;
    float b02 = a00 * a13 - a03 * a10;
    float b03 = a01 * a12 - a02 * a11;
    float b04 = a01 * a13 - a03 * a11;
    float b05 = a02 * a13 - a03 * a12;
    float b06 = a20 * a31 - a21 * a30;
    float b07 = a20 * a32 - a22 * a30;
    float b08 = a20 * a33 - a23 * a30;
    float b09 = a21 * a32 - a22 * a31;
    float b10 = a21 * a33 - a23 * a31;
    float b11 = a22 * a33 - a23 * a32;

    float det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    float invD = 1.0 / det;

    float4x4 inv;
    inv._11 = (a11 * b11 - a12 * b10 + a13 * b09) * invD;
    inv._12 = (-a01 * b11 + a02 * b10 - a03 * b09) * invD;
    inv._13 = (a31 * b05 - a32 * b04 + a33 * b03) * invD;
    inv._14 = (-a21 * b05 + a22 * b04 - a23 * b03) * invD;

    inv._21 = (-a10 * b11 + a12 * b08 - a13 * b07) * invD;
    inv._22 = (a00 * b11 - a02 * b08 + a03 * b07) * invD;
    inv._23 = (-a30 * b05 + a32 * b02 - a33 * b01) * invD;
    inv._24 = (a20 * b05 - a22 * b02 + a23 * b01) * invD;

    inv._31 = (a10 * b10 - a11 * b08 + a13 * b06) * invD;
    inv._32 = (-a00 * b10 + a01 * b08 - a03 * b06) * invD;
    inv._33 = (a30 * b04 - a31 * b02 + a33 * b00) * invD;
    inv._34 = (-a20 * b04 + a21 * b02 - a23 * b00) * invD;

    inv._41 = (-a10 * b09 + a11 * b07 - a12 * b06) * invD;
    inv._42 = (a00 * b09 - a01 * b07 + a02 * b06) * invD;
    inv._43 = (-a30 * b03 + a31 * b01 - a32 * b00) * invD;
    inv._44 = (a20 * b03 - a21 * b01 + a22 * b00) * invD;

    return inv;
}

float safe_divide(float a, float b) {
    return (abs(b) > 1e-6) ? a / b : 0.0;
}

struct Ellipse {
    float2 center;
    float2 axis;
    float2 size;
};

Ellipse extractEllipse(float a, float b, float c, float d, float e, float f) {
    float delta = c * c - 4.0 * a * b;
    float h = safe_divide(2.0 * b * d - c * e, delta);
    float k = safe_divide(2.0 * a * e - c * d, delta);

    float Fp = a * h * h + b * k * k + c * h * k + d * h + e * k + f;

    float diff_ba = b - a;
    float sum_ba  = b + a;
    float J = sqrt(diff_ba * diff_ba + c * c);

    float lambda1 = (sum_ba + J) * 0.5;
    float lambda2 = (sum_ba - J) * 0.5;

    float r = safe_divide(diff_ba, c);
    float ca = 0.5 * sign(c) / sqrt(1.0 + r * r);
    float ch = sqrt(0.5 + ca) * sqrt(0.5);
    float sh = sqrt(0.5 - ca) * sqrt(0.5) * sign(diff_ba);
    float cos_theta = ch - sh;
    float sin_theta = ch + sh;

    float a1 = sqrt(-safe_divide(Fp, lambda1));
    float a2 = sqrt(-safe_divide(Fp, lambda2));

    Ellipse ellipse;
    ellipse.center = float2(h, k);
    ellipse.axis   = float2(cos_theta, sin_theta);
    ellipse.size   = float2(a1, a2);
    return ellipse;
}

float3x3 outerProduct(float3 a, float3 b) {
    return float3x3(a * b.x, a * b.y, a * b.z);
}

float3x3 unit(float a) {
    return float3x3(a, 0, 0, 0, a, 0, 0, 0, a);
}

float3x3 q2m(float4 q) {
    float3 a = float3(-1, 1, 1);
    float3 u = q.zyz * a * q.w, v = q.xyx * a.xxy * q.w;
    float3x3 m = float3x3(0, u.x, u.y, u.z, 0, v.x, v.y, v.z, 0) + unit(0.5) + outerProduct(q.xyz, q.xyz) * (1.0 - unit(1.0));
    q *= q;
    m -= float3x3(q.y + q.z, 0, 0, 0, q.x + q.z, 0, 0, 0, q.x + q.y);
    return m * 2.0;
}
    
Ellipse GetProjectedEllipsoid(float3 pos, float3 scale, float4 rotation)
{
    float3x3 R = q2m(rotation);
    float4x4 splat = float4x4(R[0]*scale, pos.x, R[1]*scale, pos.y, R[2]*scale, pos.z, 0, 0, 0, 1);
    float4x4 model = mul(unity_ObjectToWorld, splat);
    float4x4 clipM = mul(UNITY_MATRIX_VP, model);
    float4x4 inv   = inverse(clipM);
    float4x4 Q0 = float4x4(1,0,0,0,
                           0,1,0,0,
                           0,0,1,0,
                           0,0,0,-1);
    float4x4 Q = mul(transpose(inv), mul(Q0, inv));

    float A = Q[2][2];
    float3 B = float3(Q[0][2], Q[1][2], Q[3][2]);
    float3x3 C = float3x3(Q[0][0], Q[0][1], Q[0][3],
                          Q[1][0], Q[1][1], Q[1][3],
                          Q[3][0], Q[3][1], Q[3][3]);
    float3x3 C2 = outerProduct(B, B) - A * C;

    float _a = C2[0][0]; 
    float _b = 2.0 * C2[0][1];
    float _c = C2[1][1];
    float _d = 2.0 * C2[0][2];
    float _e = 2.0 * C2[1][2];
    float _f = C2[2][2];

    return extractEllipse(_a, _c, _b, _d, _e, _f);
}

[maxvertexcount(4)]
[instance(32)]
void geo(point v2g input[1], inout TriangleStream<g2f> triStream, uint instanceID : SV_GSInstanceID, uint geoPrimID : SV_PrimitiveID) {
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
    splatClipPos.xyz /= splatClipPos.w; // perspective divide
    if (splatClipPos.z <= 0) return; // behind camera
    if (all(splatClipPos.xy < -1.0) || all(splatClipPos.xy > 1.0)) return; // outside of view frustum

    float3 objCameraPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;
    o.color = float4(GammaToLinearSpace(splat.color), splat.color.a);
    float3 rad = 1.0 / max(1e-6,splat.scale);
    o.pos = q_rotate(objCameraPos - splat.mean, conj_q(splat.quat)) * rad;

    float scale = clamp(sqrt(2.0 * (_SplatScale + log2(splat.color.a))), 0.1, 4.0);
    if(scale < 0.5) return; // skip splats that are too small

    // // 8 cube corners in unit space
    // static const float3 corner[8] = {
    //     float3(-1,-1,+1), float3(+1,-1,+1), float3(+1,+1,+1), float3(-1,+1,+1),
    //     float3(-1,-1,-1), float3(+1,-1,-1), float3(+1,+1,-1), float3(-1,+1,-1)
    // };

    // // 14-index strip that covers the cube (12 triangles)
    // static const uint idx[14] = {0,1,3,2,6,1,5,0,4,3,7,6,4,5};

    // [unroll] for (uint i = 0; i < 14; ++i)
    // {
    //     uint k = idx[i];
    //     float3 local = corner[k]*scale;
    //     float3 model = unit_space_to_model(local, splat.mean, splat.quat, splat.scale);

    //     o.position = UnityObjectToClipPos(float4(model,1));
    //     o.world_pos = q_rotate(normalize(model - objCameraPos), conj_q(splat.quat)) * rad;
    //     triStream.Append(o);
    // }
    float scale_max = max(0.00001, max(splat.scale.x, max(splat.scale.y, splat.scale.z)));
    Ellipse ell = GetProjectedEllipsoid(splat.mean, 4.0 * clamp(splat.scale, scale_max * 0.1, scale_max), splat.quat);

    if(any(scale * ell.size > 2.0)) return;

    [unroll] for (uint vtxID = 0; vtxID < 4; vtxID ++)
    {
        float2 quadPos = (float2(vtxID & 1, (vtxID >> 1) & 1) * 2.0 - 1.0);
        float2x2 rot = float2x2(ell.axis.x, -ell.axis.y, ell.axis.y, ell.axis.x);
        float2 ndc = ell.center + mul(rot, 0.25 * scale * quadPos*ell.size); // expand 0‑1 quad to full NDC
        o.position = float4(ndc, splatClipPos.z, 1.0);
        o.world_pos = float3(2.75*quadPos, 0.0);//q_rotate(normalize(model - objCameraPos), conj_q(splat.quat)) * rad;
        triStream.Append(o);
    }
}

float4 frag(g2f input) : SV_Target
{
    // float3 ro = input.pos;
    // float3 rd = input.world_pos;
    // float dt = dot(rd, -ro) / dot(rd, rd);  // time to intersection
    // float3 splat_pos = ro + rd * dt; 
    float rho = input.color.a * exp(-dot(input.world_pos,input.world_pos)*0.5);
    if (rho < 0.01) discard;  // skip regions with low density
    return float4(input.color.rgb, rho);
}