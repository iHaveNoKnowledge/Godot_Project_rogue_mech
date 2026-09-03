"""Split a cleaned upright part GLB into upper/lower at a height fraction.
Pivots: upper keeps top-joint pivot; lower pivot = split plane (elbow/knee).
Usage: python tools/split_part.py <clean.glb> <frac_from_top> <upper.glb> <lower.glb>
"""
import sys
import numpy as np
import trimesh


def clip(mesh: trimesh.Trimesh, y_min: float, y_max: float) -> trimesh.Trimesh:
    v = np.asarray(mesh.vertices)
    f = np.asarray(mesh.faces)
    inside = (v[:, 1] >= y_min - 1e-6) & (v[:, 1] <= y_max + 1e-6)
    keep = inside[f].all(axis=1)
    sub = trimesh.Trimesh(vertices=v, faces=f[keep], process=True)
    sub.remove_unreferenced_vertices()
    return sub


def main() -> None:
    src, frac, upper_path, lower_path = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
    mesh = trimesh.load(src, force="mesh")
    b = mesh.bounds
    cut = b[1][1] - (b[1][1] - b[0][1]) * frac
    upper = clip(mesh, cut, b[1][1] + 1e-6)
    lower = clip(mesh, b[0][1] - 1e-6, cut)
    # lower pivot: move so split plane sits at local y=0 (elbow/knee joint)
    lower.apply_translation([0.0, -cut, 0.0])
    upper.export(upper_path)
    lower.export(lower_path)
    print(f"split @{frac}: upper ext={np.round(upper.extents,3)} lower ext={np.round(lower.extents,3)}")


if __name__ == "__main__":
    main()
