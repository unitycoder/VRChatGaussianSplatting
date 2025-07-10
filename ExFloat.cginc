// Extended float operations for double precision in shaders
// https://andrewthall.org/papers/df64_qf128.pdf

static const float SPLIT = 4097.0;

float _HACK_UNIFORM;
#define ONE _HACK_UNIFORM
#define COMPILER_HACK // This is a workaround because the compiler optimizes out the actual double precision operations

// Split single-precision float into high and low parts
float2 split(float a)
{
#ifdef COMPILER_HACK
    float t = a * SPLIT;
    float a_hi = t * ONE - (t - a);
    float a_lo = a * ONE - a_hi;
#else
    float t = a * SPLIT;
    float a_hi = t - (t - a);
    float a_lo = a - a_hi;
#endif
    return float2(a_hi, a_lo);
}

// Re-split when high part overflows
float2 split2(float2 a)
{
    float2 b = split(a.x);
    b.y += a.y;
    return b;
}

// Quick sum assuming |a| >= |b|
float2 quickTwoSum(float a, float b)
{
#ifdef COMPILER_HACK
    float sum = (a + b) * ONE;
    float err = b - (sum - a) * ONE;
#else
    float sum = a + b;
    float err = b - (sum - a);
#endif
    return float2(sum, err);
}

// Accurate sum
float2 twoSum(float a, float b)
{
    float s = a + b;
#ifdef COMPILER_HACK
    float v = (s * ONE - a) * ONE;
    float err = (a - (s - v) * ONE) * ONE * ONE * ONE + (b - v);
#else
    float v = s - a;
    float err = (a - (s - v)) + (b - v);
#endif
    return float2(s, err);
}

// Accurate subtraction
float2 twoSub(float a, float b)
{
    float s = a - b;
#ifdef COMPILER_HACK
    float v = (s * ONE - a) * ONE;
    float err = (a - (s - v) * ONE) * ONE * ONE * ONE - (b + v);
#else
    float v = s - a;
    float err = (a - (s - v)) - (b + v);
#endif
    return float2(s, err);
}

// Accurate square
float2 twoSqr(float a)
{
    float prod = a * a;
    float2 a_fp64 = split(a);
#ifdef COMPILER_HACK
    float err = ((a_fp64.x * a_fp64.x - prod) * ONE + 2.0 * a_fp64.x * a_fp64.y * ONE * ONE) +
                a_fp64.y * a_fp64.y * ONE * ONE * ONE;
#else
    float err = ((a_fp64.x * a_fp64.x - prod) + 2.0 * a_fp64.x * a_fp64.y) +
                a_fp64.y * a_fp64.y;
#endif
    return float2(prod, err);
}

// Accurate product
float2 twoProd(float a, float b)
{
    float prod = a * b;
    float2 a_fp64 = split(a);
    float2 b_fp64 = split(b);
    float err = ((a_fp64.x * b_fp64.x - prod) + a_fp64.x * b_fp64.y + a_fp64.y * b_fp64.x) +
                a_fp64.y * b_fp64.y;
    return float2(prod, err);
}

// fp64 addition
float2 df64_add(float2 a, float2 b)
{
    float2 s = twoSum(a.x, b.x);
    float2 t = twoSum(a.y, b.y);
    s.y += t.x;
    s = quickTwoSum(s.x, s.y);
    s.y += t.y;
    s = quickTwoSum(s.x, s.y);
    return s;
}

// fp64 subtraction
float2 df64_sub(float2 a, float2 b)
{
    float2 s = twoSub(a.x, b.x);
    float2 t = twoSub(a.y, b.y);
    s.y += t.x;
    s = quickTwoSum(s.x, s.y);
    s.y += t.y;
    s = quickTwoSum(s.x, s.y);
    return s;
}

// fp64 multiplication
float2 df64_mul(float2 a, float2 b)
{
    float2 prod = twoProd(a.x, b.x);
    prod.y += a.x * b.y;
#ifdef LUMA_FP64_HIGH_BITS_OVERFLOW_WORKAROUND
    prod = split2(prod);
#endif
    prod = quickTwoSum(prod.x, prod.y);
    prod.y += a.y * b.x;
#ifdef LUMA_FP64_HIGH_BITS_OVERFLOW_WORKAROUND
    prod = split2(prod);
#endif
    prod = quickTwoSum(prod.x, prod.y);
    return prod;
}

// fp64 division
float2 df64_div(float2 a, float2 b)
{
    float xn = 1.0 / b.x;
#ifdef LUMA_FP64_HIGH_BITS_OVERFLOW_WORKAROUND
    float2 yn = df64_mul(a, float2(xn, 0));
#else
    float2 yn = a * xn;
#endif
    float diff = df64_sub(a, df64_mul(b, yn)).x;
    float2 prod = twoProd(xn, diff);
    return df64_add(yn, prod);
}

// fp64 square root
float2 df64_sqrt(float2 a)
{
    if (a.x == 0.0 && a.y == 0.0) return float2(0, 0);
    if (a.x < 0.0) return float2(asfloat(0.0/0.0), asfloat(0.0/0.0));

    float x = rsqrt(a.x);
    float yn = a.x * x;
#ifdef COMPILER_HACK
    float2 yn_sqr = twoSqr(yn) * ONE;
#else
    float2 yn_sqr = twoSqr(yn);
#endif
    float diff = df64_sub(a, yn_sqr).x;
    float2 prod2 = twoProd(x * 0.5, diff);
    return df64_add(split(yn), prod2);
}

struct double_4x4
{
    float2 m[4][4];  
};

// -----------------------------------------------------------------------------
// 2.  Converting a float4x4 into double_4x4
// -----------------------------------------------------------------------------
double_4x4 to_dmat(float4x4 f)
{
    double_4x4 D;
    [unroll] for (uint i = 0; i < 4; ++i)
    {
        [unroll] for (uint j = 0; j < 4; ++j)
        {
            // hi = float value, lo = 0
            D.m[i][j] = float2(f[i][j], 0.0);
        }
    }
    return D;
}

// -----------------------------------------------------------------------------
// 3.  Element-wise addition & subtraction
// -----------------------------------------------------------------------------
double_4x4 dmat_add(double_4x4 A, double_4x4 B)
{
    double_4x4 R;
    [unroll] for (uint i = 0; i < 4; ++i)
    {
        [unroll] for (uint j = 0; j < 4; ++j)
            R.m[i][j] = df64_add(A.m[i][j], B.m[i][j]);
    }
    return R;
}

double_4x4 dmat_sub(double_4x4 A, double_4x4 B)
{
    double_4x4 R;
    [unroll] for (uint i = 0; i < 4; ++i)
    {
        [unroll] for (uint j = 0; j < 4; ++j)
            R.m[i][j] = df64_sub(A.m[i][j], B.m[i][j]);
    }
    return R;
}

// -----------------------------------------------------------------------------
// 4.  Matrix product  R = A × B   (extended precision)
// -----------------------------------------------------------------------------
double_4x4 dmat_mul(double_4x4 A, double_4x4 B)
{
    double_4x4 R;

    [unroll] for (uint i = 0; i < 4; ++i)           // rows of A
    {
        [unroll] for (uint j = 0; j < 4; ++j)       // cols of B
        {
            // start with zero in df64
            float2 acc = float2(0.0, 0.0);

            [unroll] for (uint k = 0; k < 4; ++k)   // dot-product
            {
                float2 prod = df64_mul(A.m[i][k], B.m[k][j]);
                acc = df64_add(acc, prod);          // K-fold compensated sum
            }
            R.m[i][j] = acc;
        }
    }
    return R;
}

double_4x4 transpose(double_4x4 A)
{
    double_4x4 R;
    [unroll] for (uint i = 0; i < 4; ++i)
    {
        [unroll] for (uint j = 0; j < 4; ++j)
            R.m[j][i] = A.m[i][j];
    }
    return R;
}

// -----------------------------------------------------------------------------
// 5.  (Optional) Fast cast back to float4x4 (drops the low part)
// -----------------------------------------------------------------------------
float4x4 to_float(double_4x4 D)
{
    float4x4 F;
    [unroll] for (uint i = 0; i < 4; ++i)
    {
        [unroll] for (uint j = 0; j < 4; ++j)
            F[i][j] = D.m[i][j].x;   // keep only the hi word
    }
    return F;
}