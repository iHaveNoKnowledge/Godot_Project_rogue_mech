"""Clean Hunyuan3D per-part GLB: keep main shell, bisect+mirror for symmetry,
flat-shade (unmerge), normalize scale, set joint pivot. Usage:
  python tools/clean_hy_part.py <in.glb> <slot:head|body|arm|leg> <out.glb>
"""
import sys
import numpy as np
import trimesh

TARGET = {"head": 0.55, "body": 1.50, "arm": 1.70, "leg": 2.30}
# pivot: fraction of height where joint sits (0=bottom,1=top). head->neck bottom,
# body->center, arm->shoulder top, leg->hip top.
PIVOT = {"head": 0.0, "body": 0.5, "arm": 1.0, "leg": 1.0}


def main() -> None:
    src, slot, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    scene = trimesh.load(src, force="scene")
    geoms = [g for g in scene.dump(concatenate=False)]
    mesh = max(geoms, key=lambda g: g.area)
    # drop tiny floating speckles: keep components >=1% of main area
    comps = mesh.split(only_watertight=False)
    big = [c for c in comps if c.area >= 0.01 * mesh.area]
    mesh = trimesh.util.concatenate(big) if big else mesh
    # bisect: keep x>=0 half, mirror across X, merge
    v = mesh.vertices
    keep_v = v[:, 0] >= 0.0
    faces = np.asarray(mesh.faces)
    keep_f = keep_v[faces].all(axis=1)
    half = trimesh.Trimesh(vertices=v, faces=faces[keep_f], process=True)
    mir = half.copy()
    mir.vertices[:, 0] *= -1.0
    mir.faces = mir.faces[:, ::-1]  # fix winding after mirror
    mesh = trimesh.util.concatenate([half, mir])
    mesh.merge_vertices()
    # PCA: stand the part upright (principal axis -> +Y), wider end up
    vv = np.asarray(mesh.vertices)
    _c = vv.mean(axis=0)
    _u, _s, _vt = np.linalg.svd(vv - _c, full_matrices=False)
    v1 = _vt[0] / np.linalg.norm(_vt[0])
    if v1[1] < 0.0:
        v1 = -v1
    ang = float(np.arccos(np.clip(v1[1], -1.0, 1.0)))
    if ang > np.radians(15.0):
        k = np.cross(v1, np.array([0.0, 1.0, 0.0]))
        k = k / (np.linalg.norm(k) + 1e-12)
        mesh.apply_transform(trimesh.transformations.rotation_matrix(ang, k))
    if slot in ("arm", "leg", "body"):
        vv = np.asarray(mesh.vertices)
        yy = vv[:, 1]
        lo, hi = np.percentile(yy, [5.0, 95.0])
        top = vv[yy >= hi][:, [0, 2]]
        bot = vv[yy <= lo][:, [0, 2]]
        if bot.std() > top.std():
            mesh.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [1, 0, 0]))
    # flat shading: unmerge so every face has its own normals (in-place)
    mesh.unmerge_vertices()
    # normalize: longest axis -> target meters
    ext = mesh.extents
    mesh.apply_scale(TARGET[slot] / float(ext.max()))
    # center XZ, put pivot height at origin
    b = mesh.bounds
    mesh.apply_translation([-(b[0][0] + b[1][0]) / 2.0, 0.0, -(b[0][2] + b[1][2]) / 2.0])
    b = mesh.bounds
    joint_y = b[0][1] + (b[1][1] - b[0][1]) * PIVOT[slot]
    mesh.apply_translation([0.0, -joint_y, 0.0])
    mesh.export(dst)
    print(f"cleaned {slot}: ext={np.round(mesh.extents,3)} m -> {dst}")


if __name__ == "__main__":
    main()
