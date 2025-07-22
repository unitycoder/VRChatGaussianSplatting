#!/usr/bin/env python3
"""
Strip higher‑order spherical harmonic channels from a Gaussian‑splats PLY,
keeping f_dc_* and everything else (position, scale, rot, opacity …).
Useful to reduce size of PLY down below 2GB for the importer to work.
"""
import re, sys, numpy as np
from plyfile import PlyData, PlyElement

# Remove anything that starts with f_rest_ or sh_
REMOVE = re.compile(r"^(f_rest_|sh_)", re.I)

def strip_sh(in_ply, out_ply, regex=REMOVE):
    ply = PlyData.read(in_ply)
    v = ply["vertex"]

    keep = [p.name for p in v.properties if not regex.match(p.name)]
    if len(keep) == len(v.properties):
        raise RuntimeError("No SH channels matched; regex too strict?")

    dtype = [(n, v[n].dtype) for n in keep]
    new_data = np.empty(len(v), dtype=dtype)
    for n in keep:
        new_data[n] = v[n]

    PlyData([PlyElement.describe(new_data, "vertex")],
            text=ply.text, byte_order=ply.byte_order).write(out_ply)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: strip_sh.py in.ply out.ply"); sys.exit(1)
    strip_sh(sys.argv[1], sys.argv[2])