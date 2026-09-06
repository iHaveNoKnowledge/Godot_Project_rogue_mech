"""Split tankmech_full.glb (single AI mesh, ~2m, feet at y=-1) into 6 slot parts.

Convention (per MECH_MODEL_GUIDE.md + mecha_base.tscn):
- feet -> y=0, uniform scale 2.4 (4.74m tall, matches 4.73m rig)
- each part translated so its joint lands on the slot node position
- vertex colors preserved, overlapping bands hide seams
Usage: python tools/split_tankmech_fullbody.py
Output: scenes/mecha/parts/{slot}/tankmech_{slot}.glb + .tscn wrappers
"""
import pathlib
import numpy as np
import trimesh

PROJ = pathlib.Path(__file__).resolve().parents[1]
SRC = PROJ / 'assets' / 'models' / 'tankmech_full.glb'
SCALE = 2.4
Y0 = -1.0  # feet

# slot: (y_min, y_max, x_min, x_max, joint_mesh_xyz, slot_node_xyz)
SLOTS = {
    'head':      (0.52, 99.0, -99.0, 99.0, (0.0, 0.55, 0.0),   (0.0, 3.864, -0.0672)),
    'body':      (-0.12, 0.70, -0.44, 0.44, (0.0, 0.28, 0.0),   (0.0, 3.024, 0.0)),
    'arm_left':  (-0.60, 0.70, -99.0, -0.36, (-0.40, 0.38, 0.0), (-1.1424, 3.444, 0.0)),
    'arm_right': (-0.60, 0.70, 0.36, 99.0,  (0.40, 0.38, 0.0),  (1.1424, 3.444, 0.0)),
    'leg_left':  (-99.0, -0.04, -99.0, 0.0, (-0.22, -0.09, 0.0), (-0.6384, 2.184, 0.0)),
    'leg_right': (-99.0, -0.04, 0.0, 99.0,  (0.22, -0.09, 0.0),  (0.6384, 2.184, 0.0)),
}
GODOT_SLOT = {'head': 'head', 'body': 'body', 'arm_left': 'arm_left',
              'arm_right': 'arm_right', 'leg_left': 'leg_left', 'leg_right': 'leg_right'}


def extract(mesh, v, f, colors, ymin, ymax, xmin, xmax):
    inside = ((v[:, 1] >= ymin - 1e-6) & (v[:, 1] <= ymax + 1e-6)
              & (v[:, 0] >= xmin - 1e-6) & (v[:, 0] <= xmax + 1e-6))
    keep = inside[f].all(axis=1)
    if not keep.any():
        return None
    faces = f[keep]
    used = np.unique(faces)
    remap = np.full(len(v), -1)
    remap[used] = np.arange(len(used))
    sub = trimesh.Trimesh(vertices=v[used], faces=remap[faces], process=False)
    if colors is not None:
        assert len(sub.vertices) == len(used)
        sub.visual = trimesh.visual.ColorVisuals(vertex_colors=colors[used])
    return sub


def main():
    mesh = trimesh.load(str(SRC), force='mesh')
    v = np.asarray(mesh.vertices)
    f = np.asarray(mesh.faces)
    colors = None
    try:
        c = np.asarray(mesh.visual.vertex_colors)
        if c.shape[0] == len(v):
            colors = c
    except Exception:
        pass
    print(f'src verts={len(v)} faces={len(f)} colors={colors is not None}')
    for slot, (ymin, ymax, xmin, xmax, joint, node) in SLOTS.items():
        sub = extract(mesh, v, f, colors, ymin, ymax, xmin, xmax)
        if sub is None:
            print(f'[Skip] {slot} empty')
            continue
        # feet->0, scale, joint->node
        sub.apply_translation([0.0, -Y0, 0.0])
        sub.apply_scale(SCALE)
        j = (np.array(joint) + np.array([0.0, -Y0, 0.0])) * SCALE
        sub.apply_translation(np.array(node) - j)
        out_dir = PROJ / 'scenes' / 'mecha' / 'parts' / GODOT_SLOT[slot]
        out_dir.mkdir(parents=True, exist_ok=True)
        glb = out_dir / f'tankmech_{slot}.glb'
        sub.export(str(glb))
        tscn = out_dir / f'tankmech_{slot}.tscn'
        tscn.write_text(
            '[gd_scene format=3]\n'
            f'[ext_resource type="PackedScene" path="res://scenes/mecha/parts/{GODOT_SLOT[slot]}/tankmech_{slot}.glb" id="1"]\n'
            f'[node name="tankmech_{slot}" type="Node3D"]\n'
            '[node name="Model" parent="." instance=ExtResource("1")]\n',
            encoding='utf-8')
        sv = np.asarray(sub.vertices)
        print(f'[OK] {slot}: verts={len(sv)} faces={len(sub.faces)} '
              f'y[{sv[:,1].min():.2f},{sv[:,1].max():.2f}] -> {glb.name}')


if __name__ == '__main__':
    main()
