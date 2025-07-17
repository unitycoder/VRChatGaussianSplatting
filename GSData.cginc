#include "RadixSort/Utils.cginc"

Texture2D _GS_Positions, _GS_Scales, _GS_Rotations, _GS_Colors;
Texture2DArray<float> _GS_RenderOrder;
Texture2D<float> _GS_RenderOrderMirror;
float4 _GS_Positions_TexelSize;
float4 _GS_RenderOrder_TexelSize;
float _VRChatCameraMode;
float _VRChatMirrorMode;
float3 _MirrorCameraPos, _VRChatMirrorCameraPos;
float _QuadScale;
float _GaussianMul;
float _ThinThreshold;
float _AntiAliasing;
float _Log2MinScale;
float _AlphaCutoff;
float _Exposure;
float _Opacity;
float _ScaleCutoff;
int _DisplayFirstNSplats;
float2 _MinMaxSortDistance;

struct SplatData {
    float3 mean;
    float3 scale;
    float4 quat;
    float4 color;
    uint id; // for debugging purposes
    bool valid;
};

SplatData LoadSplatData(uint id) {
    uint2 coord = uint2(id % uint(_GS_Positions_TexelSize.z), id / uint(_GS_Positions_TexelSize.z));

    SplatData o;
    o.mean = _GS_Positions[coord].xyz;
    // Without a low pass filter some splats can look too "thin", so we try to correct for this.
    // Only necessary if splats are trained without mip-splatting.
    o.scale = max(exp2(_Log2MinScale), _GS_Scales[coord].xyz);
    o.quat = normalize(lerp(-1.0, 1.0, _GS_Rotations[coord]));
    o.color = _GS_Colors[coord]; // convert to linear space
    o.color.rgb *= _Exposure;
    o.color.a *= _Opacity;
    return o;
}

SplatData LoadSplatDataRenderOrder(uint id, float3 camPos) {
    bool validOrder = _GS_RenderOrder_TexelSize.z >= _GS_Positions_TexelSize.z;
    uint reordered_id = id;
    bool valid = true;
    if(validOrder) { // if valid order texture
        uint2 coord1 = IndexToUV(id);
        bool inMirror = false;//_VRChatMirrorMode > 0 && all(abs(_VRChatMirrorCameraPos - _MirrorCameraPos) < 1e-4);
        if(inMirror) {
            valid = false;
            //reordered_id = _GS_RenderOrderMirror[coord1];
        } else {
            uint slice = (_VRChatCameraMode > 0);
            reordered_id = _GS_RenderOrder[uint3(coord1, slice)];
        }
    } else {
        uint splatCount = uint(_GS_Positions_TexelSize.z) * uint(_GS_Positions_TexelSize.w);
        reordered_id = pcg(reordered_id) % splatCount; // randomize order for alpha blending to somewhat work
    }
    SplatData data = LoadSplatData(reordered_id);
    data.id = reordered_id; // store the original ID for debugging purposes
    data.valid = valid;
    return data;
}