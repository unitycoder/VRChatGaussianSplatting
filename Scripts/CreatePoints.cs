#if UNITY_EDITOR
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using Unity.Mathematics;

//a static class that creates a mesh with the given point count
static public class PointsMesh
{
    static public Mesh GetMesh(int splat_count)
    {
		int vertices = splat_count / 32; //32 instances in GS
		Mesh mesh = new Mesh();
		mesh.vertices = new Vector3[1];
		mesh.bounds = new Bounds(new Vector3(0, 0, 0), new Vector3(1000, 1000, 1000));
		mesh.SetIndices(new int[vertices], MeshTopology.Points, 0, false, 0);
        return mesh;
    }
}

public class CreateSplatMesh : EditorWindow
{
    int size = 1024 * 1024; //default to 1M splats

    [MenuItem("Gaussian Splatting/Create Splat Mesh")]
    static void Init()
    {
        CreateSplatMesh window = (CreateSplatMesh)EditorWindow.GetWindow(typeof(CreateSplatMesh));
        window.Show();
    }

    void OnGUI()
    {
        GUILayout.Label("Max Splat Count", EditorStyles.boldLabel);
        size = EditorGUILayout.IntField("Max Splat Count", size);

        if (GUILayout.Button("Create Mesh"))
        {
            Mesh mesh = PointsMesh.GetMesh(size);

            //query user for path
            string path = EditorUtility.SaveFilePanelInProject("Save Mesh", size + "_splats.asset", "asset", "Save Mesh", "Assets");

            AssetDatabase.CreateAsset(mesh, path);
            EditorGUIUtility.PingObject(mesh);
        }
    }
}
#endif