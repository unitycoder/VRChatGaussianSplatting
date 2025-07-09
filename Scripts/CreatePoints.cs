#if UNITY_EDITOR
using UnityEngine;
using UnityEditor;

// https://github.com/cnlohr/shadertrixx?tab=readme-ov-file#triangles-from-points-examples
public class CreatePoints : MonoBehaviour
{
	[MenuItem("Gaussian Splatting/Create Points")]
	static void CreateMesh_()
	{
		int vertices = 1024 * 256;
		Mesh mesh = new Mesh();
		mesh.vertices = new Vector3[1];
		mesh.bounds = new Bounds(new Vector3(0, 0, 0), new Vector3(1000, 1000, 1000));
		mesh.SetIndices(new int[vertices], MeshTopology.Points, 0, false, 0);
		AssetDatabase.CreateAsset(mesh, "Assets/VRChatGaussianSplatting/points_" + vertices + ".asset");
	}
}
#endif