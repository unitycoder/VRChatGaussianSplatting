#include "RadixSort/Utils.cginc"

Texture2D _GS_Positions, _GS_Scales, _GS_Rotations, _GS_Colors;
Texture2DArray<float> _GS_RenderOrder;
float4 _GS_Positions_TexelSize;
float4 _GS_RenderOrder_TexelSize;
float _VRChatCameraMode;
float _SplatScale;
float _Log2MinScale;
float _AlphaCutoff;

struct SplatData {
    float3 mean;
    float3 scale;
    float4 quat;
    float4 color;
};

SplatData LoadSplatData(uint id) {
    uint2 coord = uint2(id % _GS_Positions_TexelSize.z, id / _GS_Positions_TexelSize.z);

    SplatData o;
    o.mean = _GS_Positions[coord].xyz;
    // Without a low pass filter some splats can look too "thin", so we try to correct for this.
    // Only necessary if splats are trained without mip-splatting.
    o.scale = max(exp2(_Log2MinScale), _GS_Scales[coord].xyz);
    o.quat = normalize(_GS_Rotations[coord]);
    o.color = _GS_Colors[coord];
    return o;
}

SplatData LoadSplatDataRenderOrder(uint id) {
    if(_GS_RenderOrder_TexelSize.z >= _GS_Positions_TexelSize.z) { // if valid order texture
        uint2 coord1 = IndexToUV(id);
        uint slice = _VRChatCameraMode > 0;
        id = _GS_RenderOrder[uint3(coord1, slice)];
    }
    return LoadSplatData(id);
}