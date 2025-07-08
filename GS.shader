Shader "VRChatGaussianSplatting/GaussianSplatting"
{
    Properties
    {
        [Toggle] _PERSPECTIVE_CORRECT ("Perspective Correct", Float) = 1
        _AlphaCutoff ("Alpha Cutoff", Float) = 0.06
        _Log2MinScale ("Log2(MinScale), if trained with mip-splatting set this to -100", Float) = -12
        [Toggle] _ONLY_SH ("Only SH", Float) = 0
        [KeywordEnum(0th, 1st, 2nd, 3rd)] _SH_ORDER ("SH Order", Float) = 3
        _GS_Positions ("Means", 2D) = "" {}
        _GS_Scales ("Scales", 2D) = "" {}
        _GS_Rotations ("Quats", 2D) = "" {}
        _GS_Colors ("Colors", 2D) = "" {}
        
        _TexShCentroids ("SH Centroids", 2D) = "" {}
        _ShMin ("SH Min", Float) = 0
        _ShMax ("SH Max", Float) = 0
        _TexOrder ("Splat Order", 2DArray) = "" {}
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" }

        Pass
        {
			Cull Off
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            CGPROGRAM
            #define _ALPHA_BLENDING_ON
        	#include "GS.cginc"
            ENDCG
        }
    }
}