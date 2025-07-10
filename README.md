# VRChat Gaussian Splatting
Gaussian splatting implementation in VRChat
## Usage
1. Import unitypackage from [releases](https://github.com/MichaelMoroz/VRChatGaussianSplatting/releases) 
2. Optionally you can just clone this repo instead (might have more up to date features)
3. Import a .ply file using the built-in importer in the top main menu bar `Gaussian Splatting / Import .PLY Splat...`
4. Select output folder for the imported data
5. Replace the material of the `splat` game object in the example scene with the imported one and click play

> [!TIP]
> When using this in VRChat it is recommended for you to turn off MSAA, as it reduces the performance drastically and makes no visual difference for the splats

> [!TIP]
> Ideally you should change the size of the sorting textures to the nearest fitting power of two size for your target splat count. If you have less than 1M splats, then the textures can be 1024^2, if less than 4M then 2048^2, if more then 4096^2 (not recommended)
> The textures are located in `Radix Sort / RTs /`

> [!TIP]
> Performance can be gained by reducing the `Splat Scale` parameter in the splat material, this will introduce more artifacts, but it can be much faster

## Credits
* .PLY importer stolen from [aras-p's UnityGaussianSplatting](https://github.com/aras-p/UnityGaussianSplatting)  
* This repository is a heavily modified version of [lambdalemon's gaussian splats](https://github.com/lambdalemon/vrcsplat)  
* The Radix Sort uses [d4rkpl4y3r's mipmap prefix sum trick](https://github.com/d4rkc0d3r/CompactSparseTextureDemo)  

## Implementation details 

### Cursed Radix Sort
As this is VRChat, we only have access to the normal rasterization pipeline without write textures/buffers/atomics/etc, so the only way to implement sorting is avoid doing all that. You could easily use Bitonic sort here, but it would be unfortunately extremely slow.
Turned out there was a really cheap way to compute [prefix sums using mipmap's](https://github.com/d4rkc0d3r/CompactSparseTextureDemo) which initiated the idea of using those to implement a radix sort.
For a radix sort you only need to compute the prefix sum over all the sorted digit occurrences, and then to get the sorted sequence of elements you can do a binary search over the prefix sum.
This was optimized even further by using 4 bit digits (16 possible values) and grouping into 16-element chunks, this keeps the size of the mipmapped texture the same but now sorts 4x faster than normal bit by bit radix sort.

I suspect it is possible to optimize this further by packing the relevant digit key data into a separate texture and using larger chunks with more bits per digit.

This radix sort could potentially be used for other rendering/simulation applications in VRChat in the future.

### Ellipsoid screen projection
In VRChat the only way to render splats is by drawing them as quad billboards, which introduces significant overdraw especially if the quad is not optimally tight around the splat. To try to optimize this as much as possible I wrote an Ellipsoid to Ellipse projector, which finds the actual projected outline of a given gaussian splat isosurface (some code taken from https://www.shadertoy.com/view/Nl2Szm and some help from ChatGPT figuring out how to use the projection matrix).

Since you get an ellipse on the screen you can just use it to compute a gaussian on the screen with the same shape, this is slightly less accurate than [perspective correct gaussian splatting](https://fhahlbohm.github.io/htgs/), but its much faster and still has perspective correct outlines.
There is a large drawback however - it's very numerically unstable for thin ellipsoids, which requires lots of clever clamping to avoid these cases. 

## TODO

* Spherical harmonics support
* Better image compression 
* Animated / Multiple gaussian splats in scene?