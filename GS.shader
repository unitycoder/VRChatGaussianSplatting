Shader "VRChatGaussianSplatting/GaussianSplatting"
{
    Properties
    {
        [HideInInspector] _GS_Positions ("Means", 2D) = "" {}
        [HideInInspector] _GS_Scales ("Scales", 2D) = "" {}
        [HideInInspector] _GS_Rotations ("Quats", 2D) = "" {}
        [HideInInspector] _GS_Colors ("Colors", 2D) = "" {}
        [HideInInspector] _GS_RenderOrder ("Rendering Orders", 2DArray) = "" {}
        [HideInInspector] _MirrorCameraPos ("Mirror Camera Position", Vector) = (0, 0, 0, 0)
        
        _SplatScale ("Splat Scale", Range(0, 8)) = 4.5
        _GaussianScale ("Gaussian Scale", Range(0, 8)) = 1.0
        _ThinnessThreshold ("Thinness Threshold", Range(0, 1)) = 0.025
        _DistanceScaleThreshold ("Distance Scale Threshold", Range(0, 5.0)) = 1.25
        _Log2MinScale ("Log2 Min Scale", Range(-20, 10)) = -12.0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.045
        _Exposure ("Exposure", Range(0, 10)) = 1.0
        _Opacity ("Opacity", Range(0, 10)) = 1.0

        [HideInInspector] _HACK_UNIFORM ("hack", Float) = 1.0 // HACK to avoid compiler optimizing out double precision
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" }

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off
            ZWrite Off
            CGPROGRAM
        	#include "GS.cginc"
            ENDCG
        }
    }
}