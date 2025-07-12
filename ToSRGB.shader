Shader "VRChatGaussianSplatting/ToSRGB"
{
    SubShader
    {
        Tags { "Queue" = "Transparent+499" }
        
        GrabPass
        {
            "_LinearBackground"
        }

        Pass
        {
            ZWrite Off
            ZTest Always
            Cull Off
            CGPROGRAM
            #include "FullscreenCommon.cginc"
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_LinearBackground); 
            float4 frag(v2f i) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float4 clipPos = SVPositionToClipPos(i.pos);
                float4 uv = ComputeScreenPos(clipPos);
                fixed4 col = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_LinearBackground, uv.xy / uv.w); 
                col.rgb = LinearToGammaSpace(col.rgb); 
                return col;
            }
            ENDCG
        }
    }

    FallBack Off
}
