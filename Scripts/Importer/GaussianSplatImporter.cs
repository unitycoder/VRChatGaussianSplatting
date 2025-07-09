
#if UNITY_EDITOR && !COMPILER_UDONSHARP
using System;
using System.IO;
using Unity.Collections;
using UnityEngine;
using UnityEditor;
using GaussianSplatting.Editor.Utils;

namespace GaussianSplatting
{
    /// <summary>
    /// Parses a Gaussian‑splat *.ply (or .spz) file and packs the attributes into five square
    /// textures ready for GPU upload. Only UnityEngine types are referenced so this class can
    /// also be used at runtime. Editor‑only helpers are wrapped in UNITY_EDITOR guards.
    /// </summary>
    public static class PlySplatImporter
    {
        public struct Output
        {
            public Texture2D xyz;
            public Texture2D colorDc;
            public Texture2D rotation;
            public Texture2D scale;
            public Material splatMaterial;
        }

        /// <summary>
        /// Reads <paramref name="plyFile"/> and creates textures that are optionally saved to
        /// <paramref name="outputFolder"/> (editor only). Returns the in‑memory textures either way.
        /// </summary>
        public static Output Import(string plyFile, string outputFolder = null)
        {
            if (!File.Exists(plyFile))
                throw new FileNotFoundException(plyFile);

            // Read header to learn how many splats we need to allocate for.
            int count = GaussianFileReader.ReadFileHeader(plyFile);
            if (count == 0)
                throw new Exception("Empty or unsupported splat file");

            GaussianFileReader.ReadFile(plyFile, out NativeArray<InputSplatData> splats);
            try
            {
                int side = Mathf.CeilToInt(Mathf.Sqrt(count));

                Debug.Log($"Importing {count} splats into {side}x{side} textures");

                Texture2D xyzTex     = NewTexture(side, TextureFormat.RGBAFloat, "XYZ");
                Texture2D colDcTex   = NewTexture(side, TextureFormat.RGBAHalf, "ColorDC");
                Texture2D rotTex     = NewTexture(side, TextureFormat.RGBAHalf, "Rotation");
                Texture2D scaleTex   = NewTexture(side, TextureFormat.RGBAHalf, "Scale");
                Material splatMat = new Material(Shader.Find("VRChatGaussianSplatting/GaussianSplatting"));

                var xyzPixels   = new Color[side * side];
                var colPixels   = new Color[side * side];
                var rotPixels   = new Color[side * side];
                var scalePixels = new Color[side * side];

                for (int i = 0; i < splats.Length; ++i)
                {
                    var s = splats[i];

                    xyzPixels[i]   = new Color(s.pos.x,   s.pos.y,   s.pos.z,   0f);
                    colPixels[i]   = new Color(s.dc0.x,   s.dc0.y,   s.dc0.z,   s.opacity);
                    rotPixels[i]   = new Color(s.rot.x,   s.rot.y,   s.rot.z,   s.rot.w);
                    scalePixels[i] = new Color(s.scale.x, s.scale.y, s.scale.z, 0f);
                }

                xyzTex.SetPixels(xyzPixels);
                colDcTex.SetPixels(colPixels);
                rotTex.SetPixels(rotPixels);
                scaleTex.SetPixels(scalePixels);

                xyzTex.Apply(false, true);
                colDcTex.Apply(false, true);
                rotTex.Apply(false, true);
                scaleTex.Apply(false, true);

                if (!string.IsNullOrEmpty(outputFolder))
                {
                    Directory.CreateDirectory(outputFolder);
                    SaveTextureAsset(xyzTex,     outputFolder, "xyz");
                    SaveTextureAsset(colDcTex,   outputFolder, "color_dc");
                    SaveTextureAsset(rotTex,     outputFolder, "rotation");
                    SaveTextureAsset(scaleTex,   outputFolder, "scale");
                    
                    splatMat.name = "GaussianSplatMaterial";
                    splatMat.SetTexture("_GS_Positions", xyzTex);
                    splatMat.SetTexture("_GS_Colors", colDcTex);
                    splatMat.SetTexture("_GS_Rotations", rotTex);
                    splatMat.SetTexture("_GS_Scales", scaleTex);

                    string matPath = Path.Combine(outputFolder, "GaussianSplatMaterial.mat");
                    matPath = AssetDatabase.GenerateUniqueAssetPath(matPath);
                    AssetDatabase.CreateAsset(splatMat, matPath);
                    AssetDatabase.SaveAssets();
                }


                return new Output
                {
                    xyz      = xyzTex,
                    colorDc  = colDcTex,
                    rotation = rotTex,
                    scale    = scaleTex,
                    splatMaterial = splatMat
                };
            }
            finally
            {
                if (splats.IsCreated)
                    splats.Dispose();
            }
        }

        // ---------------------------------------------------------------------
        static Texture2D NewTexture(int size, TextureFormat format, string name)
        {
            var tex = new Texture2D(size, size, format, mipChain: false, linear: true)
            {
                name       = name,
                wrapMode   = TextureWrapMode.Clamp,
                filterMode = FilterMode.Point
            };
            return tex;
        }

        static void SaveTextureAsset(Texture2D tex, string folder, string suffix)
        {
            string path = Path.Combine(folder, $"{tex.name}_{suffix}.asset");
            path = AssetDatabase.GenerateUniqueAssetPath(path);
            AssetDatabase.CreateAsset(tex, path);
        }
    }
}

namespace GaussianSplatting.Editor.Importers
{
    using UnityEditor;
    using UnityEngine;

    /// <summary>
    /// Minimal wizard exposed via *Gaussian Splatting ▸ Import PLY Splat…* that wraps
    /// <see cref="PlySplatImporter.Import"/> and writes the produced textures to disk.
    /// </summary>
    public class PlyImportWizard : EditorWindow
    {
        string _plyPath;
        string _outputFolder = "Assets";

        [MenuItem("Gaussian Splatting/Import PLY Splat…")]
        static void ShowWindow()
        {
            var win = GetWindow<PlyImportWizard>(utility: true, title: "PLY Splat Importer");
            win.minSize = new Vector2(460, 140);
        }

        void OnGUI()
        {
            EditorGUILayout.LabelField("PLY file", EditorStyles.boldLabel);
            DrawPathField(ref _plyPath, "ply");

            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Output folder", EditorStyles.boldLabel);
            DrawFolderField(ref _outputFolder);

            GUILayout.FlexibleSpace();

            using (new EditorGUI.DisabledScope(string.IsNullOrEmpty(_plyPath)))
            {
                if (GUILayout.Button("Import", GUILayout.Height(30)))
                    Import();
            }
        }

        static void DrawPathField(ref string path, string extension)
        {
            EditorGUILayout.BeginHorizontal();
            path = EditorGUILayout.TextField(path);
            if (GUILayout.Button("…", GUILayout.Width(30)))
                path = EditorUtility.OpenFilePanel("Select file", Application.dataPath, extension);
            EditorGUILayout.EndHorizontal();
        }

        static void DrawFolderField(ref string folder)
        {
            EditorGUILayout.BeginHorizontal();
            folder = EditorGUILayout.TextField(folder);
            if (GUILayout.Button("…", GUILayout.Width(30)))
                folder = EditorUtility.OpenFolderPanel("Select folder", folder, string.Empty);
            EditorGUILayout.EndHorizontal();
        }

        void Import()
        {
            try
            {
                EditorUtility.DisplayProgressBar("PLY Import", "Reading and packing splats…", 0f);
                PlySplatImporter.Import(_plyPath, _outputFolder);
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();
                EditorUtility.DisplayDialog("PLY Import", "Import completed successfully.", "OK");
            }
            catch (Exception e)
            {
                Debug.LogException(e);
                EditorUtility.DisplayDialog("PLY Import Failed", e.Message, "OK");
            }
            finally
            {
                EditorUtility.ClearProgressBar();
            }
        }
    }
}
#endif