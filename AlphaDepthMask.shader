Shader "VRChatGaussianSplatting/AlphaDepthMask"
{
    SubShader
    {
        Tags { "Queue" = "Transparent+500" }
        
        GrabPass {}
        Pass
        {
            ZWrite On
            ZTest Always
            Cull Off
            CGPROGRAM
            #include "FullscreenCommon.cginc"
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_GrabTexture)
            float4 frag(v2f i, out float depth : SV_Depth) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                fixed4 col = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, i.uv.xy); 
                if(col.a > 0.99) {
                    depth = 1.0; // Set depth to far plane for fully opaque pixels to cull everything behind them
                    col.a = 1.0;
                } else {
                    discard;
                }
                return col;
            }
            ENDCG
        }
    }

    FallBack Off
}
