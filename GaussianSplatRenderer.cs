using UnityEngine;
using UdonSharp;
using VRC.SDKBase;
using VRC.SDK3.Rendering;

[UdonBehaviourSyncMode(BehaviourSyncMode.None)]
public class GaussianSplatRenderer : UdonSharpBehaviour
{
    public Material mat;
    private Vector3 _prevPhotoCameraPos; 

    void Start()
    {
       
    }

    void Update()
    {
        // Sort(VRCCameraSettings.ScreenCamera.Position, 0);

        // VRCCameraSettings photoCam = VRCCameraSettings.PhotoCamera;
        // if (photoCam != null && photoCam.Active && photoCam.Position != _prevPhotoCameraPos)
        // {
        //     _prevPhotoCameraPos = photoCam.Position;
        //     Sort(photoCam.Position, 1);
        // }
    }
}
