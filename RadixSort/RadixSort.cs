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
        int _ImageSize = keyValues0.width;
        int _ImageSizeLog2 = Mathf.CeilToInt(Mathf.Log(_ImageSize, 2));

        if(_ImageSize*_ImageSize < elementCount)  {
            Debug.LogError("RadixSort: Element count exceeds texture size. Increase resolution of the sorting textures (must be a power of 2 size!)");
        }

        computeKeyValues.SetInt("_BitsPerStep", bitsPerPass);
        computeKeyValues.SetInt("_GroupSize", groupSizeLog2);
        computeKeyValues.SetInt("_ElementCount", elementCount);
        computeKeyValues.SetInt("_ImageSizeLog2", _ImageSizeLog2);

        radixSort.SetInt("_BitsPerStep", bitsPerPass);
        radixSort.SetInt("_GroupSize", groupSizeLog2);
        radixSort.SetInt("_ElementCount", elementCount);
        radixSort.SetInt("_ImageSizeLog2", _ImageSizeLog2);
    }
}
