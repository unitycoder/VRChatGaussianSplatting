using UdonSharp;
using UnityEngine;
using VRC.SDKBase;
using VRC.Udon;

[UdonBehaviourSyncMode(BehaviourSyncMode.None)]
public class RadixSort : UdonSharpBehaviour
{
    [SerializeField] public Material computeKeyValues;
    [SerializeField] public Material radixSort;

    [SerializeField] public RenderTexture keyValues0;
    [SerializeField] public RenderTexture keyValues1;
    [SerializeField] public RenderTexture prefixSums;

    [HideInInspector] [SerializeField] public int maxKeyBits = 16;
    [HideInInspector] [SerializeField] public int elementCount = 1024 * 1024;

    private const int bitsPerPass = 4;
    private const int groupSizeLog2 = 4;

    public void Sort()
    {
        // Runtime uniforms that vary each frame
        setStaticUniforms();

        // 1. Evaluate key values
        VRCGraphics.Blit(null, keyValues0, computeKeyValues);

        radixSort.SetTexture("_PrefixSums", prefixSums);

        // 2. Radix passes
        for (int bit = 0; bit < maxKeyBits; bit += bitsPerPass)
        {
            radixSort.SetTexture("_KeyValues", keyValues0);
            radixSort.SetInt("_CurrentBit", bit);

            VRCGraphics.Blit(null, prefixSums, radixSort, 0);
            VRCGraphics.Blit(null, keyValues1, radixSort, 1);

            // Ping-pong the buffers
            RenderTexture temp = keyValues0;
            keyValues0 = keyValues1;
            keyValues1 = temp;
        }
    }

    private void setStaticUniforms()
    {
        int _OptimalPOT = Mathf.NextPowerOfTwo(Mathf.CeilToInt(elementCount));
        int _OptimalPOTLog2 = Mathf.CeilToInt(Mathf.Log(_OptimalPOT, 2));
        int _OptimalImageSizeLog2Y = _OptimalPOTLog2 / 2;
        int _OptimalImageSizeLog2X = _OptimalImageSizeLog2Y + _OptimalPOTLog2 % 2;
        int _OptimalImageSizeX = 1 << _OptimalImageSizeLog2X;
        int _OptimalImageSizeY = 1 << _OptimalImageSizeLog2Y;

        if(keyValues0 == null || keyValues0.width < _OptimalImageSizeLog2X || keyValues0.height < _OptimalImageSizeLog2Y) {
            Debug.LogError($"RadixSort: Texture size ({keyValues0.width}x{keyValues0.height}) is smaller than required ({_OptimalImageSizeX}x{_OptimalImageSizeY}). Please resize the textures.");
            return;
        }

        Vector2 scale = new Vector2((float)_OptimalImageSizeX / keyValues0.width, (float)_OptimalImageSizeY / keyValues0.height);

        computeKeyValues.SetInt("_BitsPerStep", bitsPerPass);
        computeKeyValues.SetInt("_GroupSize", groupSizeLog2);
        computeKeyValues.SetInt("_ElementCount", elementCount);
        computeKeyValues.SetInt("_ImageSizeLog2X", _OptimalImageSizeLog2X);
        computeKeyValues.SetInt("_ImageSizeLog2Y", _OptimalImageSizeLog2Y);
        computeKeyValues.SetInt("_ImageElementsLog2", _OptimalPOTLog2);
        computeKeyValues.SetVector("_Scale", scale);

        radixSort.SetInt("_BitsPerStep", bitsPerPass);
        radixSort.SetInt("_GroupSize", groupSizeLog2);
        radixSort.SetInt("_ElementCount", elementCount);
        radixSort.SetInt("_ImageSizeLog2X", _OptimalImageSizeLog2X);
        radixSort.SetInt("_ImageSizeLog2Y", _OptimalImageSizeLog2Y);
        radixSort.SetInt("_ImageElementsLog2", _OptimalPOTLog2);
        radixSort.SetVector("_Scale", scale);
    }
}
