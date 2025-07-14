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
        [HideInInspector] _HACK_UNIFORM ("hack", Float) = 1.0 // HACK to avoid compiler optimizing out double precision
        [HideInInspector] _MinMaxSortDistance ("Min Max Distance", Vector) = (0, 0, 0, 0)
        //[HideInInspector] [Toggle] _EditorMode ("Editor Mode", Float) = 1.0

        _SplatScale ("Quad Scale", Range(0, 2)) = 0.75
        _GaussianScale ("Gaussian Scale", Range(0, 2)) = 1.2
        _ThinThreshold ("Thinness Threshold", Range(0, 1)) = 0.005
        _AntiAliasing ("Antialiasing", Range(0, 5.0)) = 1.0
        _Log2MinScale ("Log2 of Minimum Scale", Range(-20, 10)) = -12.0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.03
        _ScaleCutoff ("Scale Cutoff", Range(0, 100)) = 100.0
        _Exposure ("Exposure", Range(0, 5)) = 1.0
        _Opacity ("Opacity", Range(0, 5)) = 1.0
        _DisplayFirstNSplats ("Display First N Splats", Int) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+500" }

        Pass
        {
            //Blend One OneMinusSrcAlpha //Back to front blending
            Blend OneMinusDstAlpha One //Front to back blending
            Cull Off
            ZWrite Off
            CGPROGRAM
        	#include "GS.cginc"
            ENDCG
        }
    }
}