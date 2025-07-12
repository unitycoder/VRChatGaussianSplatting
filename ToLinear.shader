Shader "VRChatGaussianSplatting/ToLinear"
{
    SubShader
    {
        Tags { "Queue" = "Transparent+501" }
        
        GrabPass
        {
            "_SRGBBackground"
        }

        Pass
        {
            ZWrite Off
            ZTest Always
            Cull Off
            CGPROGRAM
            #include "FullscreenCommon.cginc"
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_SRGBBackground); 
            float4 frag(v2f i) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float4 clipPos = SVPositionToClipPos(i.pos);
                float4 uv = ComputeScreenPos(clipPos);
                fixed4 col = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_SRGBBackground, uv.xy / uv.w); 
                col.rgb = GammaToLinearSpace(col.rgb);
                return col;
            }
            ENDCG
        }
    }

    FallBack Off
}
