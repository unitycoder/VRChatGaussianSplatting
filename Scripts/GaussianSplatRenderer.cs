using UnityEngine;
using UdonSharp;
using VRC.SDKBase;
using VRC.SDK3.Rendering;

[UdonBehaviourSyncMode(BehaviourSyncMode.None)]
public class GaussianSplatRenderer : UdonSharpBehaviour
{
    private Vector3 _prevPhotoCameraPos; 
    private RadixSort _radixSort;
    private MeshRenderer _meshRenderer;
    private Material keyValueMat;
    public RenderTexture splatRenderOrder;

    [SerializeField] float minSortDistance = 0.01f;
    [SerializeField] float maxSortDistance = 20.0f;

    void Start()
    {
        _radixSort = (RadixSort)GetComponent<RadixSort>();
        _meshRenderer = GetComponent<MeshRenderer>();
        _prevPhotoCameraPos.x = float.MaxValue; // Initialize to a large value to ensure first update runs

        UpdateMaterials();
    }

    void UpdateMaterials()
    {
        Material splatMat = _meshRenderer.material;
        splatMat.SetTexture("_GS_RenderOrder", splatRenderOrder);
        Texture positions = splatMat.GetTexture("_GS_Positions");
        _radixSort.elementCount = positions.width * positions.height;
        keyValueMat = _radixSort.computeKeyValues;
        keyValueMat.SetTexture("_GS_Positions", positions);
        keyValueMat.SetVector("_MinMaxSortDistance", new Vector4(minSortDistance, maxSortDistance, 0, 0));
    }

    void UpdateCameraPosition(Vector3 cameraPos)
    {
        keyValueMat.SetVector("_CameraPos", cameraPos);
        keyValueMat.SetMatrix("_SplatToWorld", transform.localToWorldMatrix);
    }

    void SortCamera(Vector3 cameraPos, int slice)
    {
        UpdateCameraPosition(cameraPos);
        _radixSort.Sort();
        VRCGraphics.Blit(_radixSort.keyValues0, splatRenderOrder, 0, slice);
    }

    void Update()
    {
        SortCamera(VRCCameraSettings.ScreenCamera.Position, 0);

        VRCCameraSettings photoCam = VRCCameraSettings.PhotoCamera;
        if (photoCam != null && photoCam.Active && photoCam.Position != _prevPhotoCameraPos)
        {
            _prevPhotoCameraPos = photoCam.Position;
            SortCamera(photoCam.Position, 1);
        }
    }
}
