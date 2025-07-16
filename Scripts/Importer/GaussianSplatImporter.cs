
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
        static uint Morton3D(float nx, float ny, float nz)
        {
            // Clamp & convert to 10-bit ints (0-1023)
            uint x = (uint)Mathf.Clamp(Mathf.RoundToInt(nx * 1023f), 0, 1023);
            uint y = (uint)Mathf.Clamp(Mathf.RoundToInt(ny * 1023f), 0, 1023);
            uint z = (uint)Mathf.Clamp(Mathf.RoundToInt(nz * 1023f), 0, 1023);

            static uint Part1By2(uint v)          // expands 10 bits → 30 with 00 in-between
            {
                v = (v | (v << 16)) & 0x030000FF;
                v = (v | (v <<  8)) & 0x0300F00F;
                v = (v | (v <<  4)) & 0x030C30C3;
                v = (v | (v <<  2)) & 0x09249249;
                return v;
            }

            return Part1By2(x) | (Part1By2(y) << 1) | (Part1By2(z) << 2);
        }

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
        public static Output Import(string plyFile, string outputMaterialPath)
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

                InputSplatData[] data = splats.ToArray();          // managed copy – easier to sort
                int n = data.Length;

                // Compute BBOX
                Vector3 min = new(float.MaxValue, float.MaxValue, float.MaxValue);
                Vector3 max = new(float.MinValue, float.MinValue, float.MinValue);
                for (int i = 0; i < n; ++i)
                {
                    min = Vector3.Min(min, data[i].pos);
                    max = Vector3.Max(max, data[i].pos);
                }
                Vector3 size = max - min;
                if (size.x == 0) size.x = 1e-6f;
                if (size.y == 0) size.y = 1e-6f;
                if (size.z == 0) size.z = 1e-6f;

                // Prepare Morton keys
                var keys = new uint[n];
                for (int i = 0; i < n; ++i)
                {
                    Vector3 np = (data[i].pos - min);
                    np.x /= size.x; np.y /= size.y; np.z /= size.z;
                    keys[i] = Morton3D(np.x, np.y, np.z);
                }

                // Sort splats by Morton key – in-place for data[]
                Array.Sort(keys, data);

                Texture2D xyzTex     = NewTexture(side, TextureFormat.RGBAFloat, "XYZ");
                Texture2D colDcTex   = NewTexture(side, TextureFormat.RGBA32, "ColorDC");
                Texture2D rotTex     = NewTexture(side, TextureFormat.RGBA32, "Rotation");
                Texture2D scaleTex   = NewTexture(side, TextureFormat.RGB9e5Float, "Scale");
                Material splatMat = new Material(Shader.Find("VRChatGaussianSplatting/GaussianSplatting"));

                var xyzPixels   = new Color[side * side];
                var colPixels   = new Color[side * side];
                var rotPixels   = new Color[side * side];
                var scalePixels = new Color[side * side];

                for (int i = 0; i < data.Length; ++i) {
                    var s = data[i];                      
                    xyzPixels[i]   = new Color(s.pos.x,   s.pos.y,   s.pos.z,   0f);
                    colPixels[i]   = new Color(s.dc0.x,   s.dc0.y,   s.dc0.z,   s.opacity);
                    rotPixels[i]   = new Color(0.5f + 0.5f * s.rot.x, 
                                                0.5f + 0.5f * s.rot.y, 
                                                0.5f + 0.5f * s.rot.z, 
                                                0.5f + 0.5f * s.rot.w);
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

                // Get output folder from the material path
                string outputFolder = Path.GetDirectoryName(outputMaterialPath);
                // Get name of the material from the path
                string materialName = Path.GetFileNameWithoutExtension(outputMaterialPath);

                SaveTextureAsset(xyzTex, outputFolder, materialName + "_xyz");
                SaveTextureAsset(colDcTex, outputFolder, materialName + "_color_dc");
                SaveTextureAsset(rotTex, outputFolder, materialName + "_rotation");
                SaveTextureAsset(scaleTex, outputFolder, materialName + "_scale");
                splatMat.name = materialName;
                splatMat.SetTexture("_GS_Positions", xyzTex);
                splatMat.SetTexture("_GS_Colors", colDcTex);
                splatMat.SetTexture("_GS_Rotations", rotTex);
                splatMat.SetTexture("_GS_Scales", scaleTex);
                AssetDatabase.CreateAsset(splatMat, outputMaterialPath);
                AssetDatabase.SaveAssets();

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

        static void SaveTextureAsset(Texture2D tex, string folder, string name)
        {
            string path = Path.Combine(folder, $"{name}.asset");
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
        string _outputMatPath;

        [MenuItem("Gaussian Splatting/Import PLY Splat…")]
        static void Init()
        {
            PlyImportWizard window = (PlyImportWizard)EditorWindow.GetWindow(typeof(PlyImportWizard));
            window.Show();
        }

        void OnGUI()
        {
            EditorGUILayout.LabelField("PLY file", EditorStyles.boldLabel);
            DrawPathField(ref _plyPath, "ply");

            GUILayout.FlexibleSpace();

            if (GUILayout.Button("Import Gaussian Splat"))
            {
                //query user for output material path
                _outputMatPath = EditorUtility.SaveFilePanelInProject("Save Gaussian Splat", "GaussianSplat.mat", "mat", "Save Gaussian Splat", "Assets");
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

        void Import()
        {
            try
            {
                EditorUtility.DisplayProgressBar("PLY Import", "Reading and packing splats…", 0f);
                PlySplatImporter.Import(_plyPath, _outputMatPath);
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