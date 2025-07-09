Shader "VRChatGaussianSplatting/GaussianSplatting"
{
    Properties
    {
        [HideInInspector] _GS_Positions ("Means", 2D) = "" {}
        [HideInInspector] _GS_Scales ("Scales", 2D) = "" {}
        [HideInInspector] _GS_Rotations ("Quats", 2D) = "" {}
        [HideInInspector] _GS_Colors ("Colors", 2D) = "" {}
        [HideInInspector] _TexOrder ("Splat Order", 2DArray) = "" {}
        
        _SplatScale ("Splat Scale", Range(0, 8)) = 5.0
        _Log2MinScale ("Log2 Min Scale", Range(-20, 10)) = -5.0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.01
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" }

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            CGPROGRAM
        	#include "GS.cginc"
            ENDCG
        }
    }
}