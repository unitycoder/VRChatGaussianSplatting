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

float3x3 outer_product(float3 a, float3 b) {
    return float3x3(a * b.x, a * b.y, a * b.z);
}

float3x3 unit(float a) {
    return float3x3(a, 0, 0, 0, a, 0, 0, 0, a);
}

float safe_divide(float a, float b) {
    return (abs(b) > 1e-6) ? a / b : 0.0;
}

float3x3 quat_to_mat(float4 q) {
    float3 a = float3(-1, 1, 1);
    float3 u = q.zyz * a * q.w, v = q.xyx * a.xxy * q.w;
    float3x3 m = float3x3(0, u.x, u.y, u.z, 0, v.x, v.y, v.z, 0) + unit(0.5) + outer_product(q.xyz, q.xyz) * (1.0 - unit(1.0));
    q *= q;
    m -= float3x3(q.y + q.z, 0, 0, 0, q.x + q.z, 0, 0, 0, q.x + q.y);
    return m * 2.0;
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
    
Ellipse GetProjectedEllipsoid(float3 pos, float3 scale, float4 rotation) {
    float3x3 R = quat_to_mat(rotation);
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
    float3x3 C2 = outer_product(B, B) - A * C;

    float _a = C2[0][0]; 
    float _b = 2.0 * C2[0][1];
    float _c = C2[1][1];
    float _d = 2.0 * C2[0][2];
    float _e = 2.0 * C2[1][2];
    float _f = C2[2][2];

    return extractEllipse(_a, _c, _b, _d, _e, _f);
}