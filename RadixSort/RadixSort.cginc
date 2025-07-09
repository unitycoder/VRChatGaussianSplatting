#include "BlitBase.cginc"
#include "Utils.cginc"

Texture2D<float2> _KeyValues;
Texture2D<float> _PrefixSums;
float4 _KeyValues_TexelSize;
float4 _PrefixSums_TexelSize;
int _ElementCount;
int _CurrentBit;
int _BitsPerStep;
int _GroupSize;
int _ImageSizeLog2;