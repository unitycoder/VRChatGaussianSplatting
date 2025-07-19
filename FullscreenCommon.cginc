#pragma vertex vert
#pragma fragment frag
#include "UnityCG.cginc"

struct appdata
{
    uint id : SV_VertexID;
#if defined(UNITY_VERTEX_INPUT_INSTANCE_ID)
    UNITY_VERTEX_INPUT_INSTANCE_ID
#endif
};

struct v2f
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2f vert (appdata v) {
    v2f o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2f, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    if(v.id == 0) {
        o.pos = float4(-1, -1, 1, 1);
    } else if(v.id == 1) {
        o.pos = float4(3, -1, 1, 1);
    } else {
        o.pos = float4(-1, 3, 1, 1);
    } 
    o.uv = ComputeScreenPos(o.pos).xy;
    return o;
}