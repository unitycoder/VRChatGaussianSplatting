
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;
using VRC.Udon;

namespace GaussianSplatting
{

[UdonBehaviourSyncMode(BehaviourSyncMode.None)]
public class QualityToggle : UdonSharpBehaviour 
{   
    [Range(0.0f, 2.0f)] [SerializeField] public float quadScale = 1.0f; // The size of the quad to be used for the splat object
    [Range(0.0f, 2.0f)] [SerializeField] public float gaussianScale = 1.0f; // The size of the Gaussian splat
    [Tooltip("The Gaussian Splat Renderer that will use the enabled object as the splat object.")]
    public GaussianSplatRenderer gaussianSplatRenderer;

    public override void Interact()
    {
        gaussianSplatRenderer.overrideMaterialProperties = true; // Enable override of material properties
        gaussianSplatRenderer.quadScale = quadScale; // Set the quad scale
        gaussianSplatRenderer.gaussianScale = gaussianScale; // Set the Gaussian scale
    }
}

}