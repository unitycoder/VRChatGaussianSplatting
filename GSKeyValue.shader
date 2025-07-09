Shader "VRChatGaussianSplatting/ComputeKeyValue" {
    Properties {
        [HideInInspector] _GS_Positions ("Means", 2D) = "" {}
        [HideInInspector] _CameraPos ("Camera Position", Vector) = (0, 0, 0, 0)
        [HideInInspector] _MinMaxSortDistance ("Min Max Sort Distance", Vector) = (0, 0, 0, 0)
        [HideInInspector] _ElementCount ("Element Count", Int) = 0
    }
    SubShader {
        Tags { "RenderType"="Opaque" "Queue"="Overlay" }
        Pass {
            ZTest Always
            Cull Off
            ZWrite Off

            CGPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #include "RadixSort/BlitBase.cginc"
            #include "GSData.cginc"

            float4x4 _SplatToWorld;
            float3 _CameraPos;
            float2 _MinMaxSortDistance;
            int _ElementCount;

            uint float2fixed16(float v) {
                return round(clamp(v, 0.0, 1.0) * 65535.0);
            }

            uint ComputeD(uint id) {
                SplatData splat = LoadSplatData(id);
                float3 splat_pos = mul(_SplatToWorld, float4(splat.mean, 1.0)).xyz;
                float dist = length(_CameraPos - splat_pos);
                float dist_inv = dist;
                float2 dist_inv_maxmin = _MinMaxSortDistance.xy;
                float dist_inv_norm = (dist_inv - dist_inv_maxmin.x) / (dist_inv_maxmin.y - dist_inv_maxmin.x);
                return float2fixed16(1.0 - dist_inv_norm);
            }

            float2 frag (v2f i) : SV_Target {
                uint2 pixel = floor(i.pos.xy);
                uint index = UVToIndex(pixel);
                if (index >= _ElementCount) discard;
                return float2(index, ComputeD(index));
            }
            ENDCG
        }
    }
    Fallback Off
}