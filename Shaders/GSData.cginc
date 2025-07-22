#include "../RadixSort/Utils.cginc"

Texture2D _GS_Positions, _GS_Scales, _GS_Rotations, _GS_Colors;
Texture2DArray<float> _GS_RenderOrder;
Texture2DArray<float> _GS_RenderOrderPrecomputed;
Texture2D<float> _GS_RenderOrderMirror;
float4 _GS_Positions_TexelSize;
float4 _GS_RenderOrder_TexelSize;
float4 _GS_RenderOrderPrecomputed_TexelSize;
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
float2 _MinMaxSortDistance;
int _SplatCount;
int _ActualSplatCount;
int _SplatOffset;

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

int GetPrecomputedRenderOrderIndex(uint id, float3 cam_dir) {
    float3 dirs[10] = {
        float3(0.57735027, 0.57735027, 0.57735027), float3(0.57735027, 0.57735027, -0.57735027), float3(0.57735027, -0.57735027, 0.57735027),
        float3(0.57735027, -0.57735027, -0.57735027), float3(0.00000000, 0.35682209, 0.93417236), float3(0.00000000, 0.35682209, -0.93417236),
        float3(0.35682209, 0.93417236, 0.00000000), float3(0.35682209, -0.93417236, 0.00000000), float3(0.93417236, 0.00000000, 0.35682209),
        float3(0.93417236, 0.00000000, -0.35682209)
    };
    float3 cam_dir_normalized = normalize(cam_dir);
    float best_dot = 0.0;
    int best_index = 0;
    [unroll] for(int i = 0; i < 10; i++) {
        float dot_product = dot(dirs[i], cam_dir_normalized);
        if(abs(dot_product) > abs(best_dot)) {
            best_dot = dot_product;
            best_index = i;
        }
    }
    if(best_dot > 0.0) {
        id = _ActualSplatCount - id - 1; // flip the order for positive directions
    }
    uint2 coord = uint2(id % uint(_GS_RenderOrderPrecomputed_TexelSize.z), id / uint(_GS_RenderOrderPrecomputed_TexelSize.z));
    return _GS_RenderOrderPrecomputed[int3(coord, best_index)];
}

SplatData LoadSplatDataRenderOrder(uint id) {
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
        reordered_id = pcg(reordered_id) % _ActualSplatCount; // randomize order for alpha blending to somewhat work
    }
    SplatData data = LoadSplatData(reordered_id);
    data.id = reordered_id; // store the original ID for debugging purposes
    data.valid = valid;
    return data;
}

SplatData LoadSplatDataPrecomputedOrder(uint id, float3 cam_dir) {
    int precomputedIndex = GetPrecomputedRenderOrderIndex(id, cam_dir);
    SplatData data = LoadSplatData(precomputedIndex);
    data.id = precomputedIndex; // store the original ID for debugging purposes
    data.valid = true; // precomputed order is always valid
    return data;
}