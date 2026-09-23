"""Build tankmech slot parts matched to the Standard Core Structure (frame_body_01).

Anchor model: assets/models/mech_cockpit_tub.glb (raw bounds x +-0.402,
y +-0.56, z -0.805..0.75). It renders inside the body FrameMesh container
(WORLD_SCALE 1.68) at raw*1.68 in mecha-local units, so all parts here are
authored in MECHA-LOCAL units (1 unit = 1 mecha_base.tscn local meter,
x1.15 world via the MechaBase root scale) — the same units PartMeshManager's
INV_WORLD_SCALE counter-scale normalizes custom armor scenes to.

Rig anchors (mecha_base.tscn locals — body node y=3.841, sole at local 0):
  tub local y +-0.941, x +-0.675, z -1.352..1.260
  head pivot (0, 4.377, -0.16)
  arm pivots (+-1.1424, 4.261, 0) ; elbow local (0, -0.6384, 0)
  hip pivots (+-0.6384, 3.001, 0) ; knee local (0, -1.34, 0)
                                    ankle local (0, -1.291) below the knee
                                    -> leg spans 3.001 local hip-to-sole

Runtime routing (part_mesh_manager._attach_custom_mesh_scene) MOVES nodes whose
name contains forearm/shin/knee/calf to the elbow/knee container and
foot/ankle/toe to the ankle container. Routed meshes are therefore authored
JOINT-LOCAL (elbow/knee/ankle pivot = origin) with an identity node transform:
after the reparent the geometry lands exactly on its rig position. Keep the
routing keywords in the node names.

Output: scenes/mecha/parts/<slot>/tankmech_<slot>.glb
Follow with: Godot --headless --script res://tools/convert_tankmech_to_tscn.gd
"""
import pathlib
import numpy as np
import trimesh

PROJ = pathlib.Path(__file__).resolve().parents[1]
OUT = PROJ / 'scenes' / 'mecha' / 'parts'

# Kitbash palette (image reference): blue-gray plates, dark frame, black joints
ARMOR = (66, 84, 118, 255)     # blue-gray main plate
ARMOR_D = (48, 58, 84, 255)    # darker blue plate
TRIM = (36, 39, 47, 255)       # dark frame
JOINT = (28, 29, 33, 255)      # black joint / inner frame
SENSOR = (230, 70, 60, 255)    # red visor


def box(name, size, center, color):
    m = trimesh.creation.box(extents=np.asarray(size, dtype=float))
    m.apply_translation(np.asarray(center, dtype=float))
    m.visual = trimesh.visual.ColorVisuals(
        vertex_colors=np.tile(np.asarray(color, dtype=np.uint8), (len(m.vertices), 1)))
    return name, m


def build_body():
    """Armor plates hugging the cockpit tub (local y +-0.941, x +-0.675,
    z -1.352..1.260)."""
    return [
        box('body_chest', (1.40, 1.70, 0.14), (0, 0.06, -1.42), ARMOR),
        box('body_chest_core', (0.90, 0.80, 0.18), (0, 0.28, -1.50), ARMOR_D),
        box('body_chest_vent_l', (0.22, 0.34, 0.10), (-0.48, -0.18, -1.44), JOINT),
        box('body_chest_vent_r', (0.22, 0.34, 0.10), (0.48, -0.18, -1.44), JOINT),
        box('body_side_l', (0.12, 1.60, 2.40), (-0.74, 0.06, -0.05), ARMOR),
        box('body_side_r', (0.12, 1.60, 2.40), (0.74, 0.06, -0.05), ARMOR),
        box('body_skirt', (1.44, 0.42, 2.20), (0, -0.98, -0.08), ARMOR_D),
        box('body_rear', (1.30, 1.50, 0.14), (0, 0.10, 1.33), TRIM),
        box('body_thruster_l', (0.34, 0.70, 0.30), (-0.30, 0.20, 1.42), JOINT),
        box('body_thruster_r', (0.34, 0.70, 0.30), (0.30, 0.20, 1.42), JOINT),
        box('body_collar', (0.80, 0.26, 0.80), (0, 1.02, -0.10), TRIM),
    ]


def build_head():
    """Tiny head buried between the oversized pauldrons (pivot at local
    4.377) — exaggerated kitbash proportion: total height ~0.54, width 0.34."""
    return [
        box('head_helm', (0.34, 0.28, 0.34), (0, 0.12, 0.0), ARMOR),
        box('head_face', (0.26, 0.10, 0.08), (0, 0.08, -0.20), JOINT),
        box('head_visor', (0.22, 0.04, 0.04), (0, 0.10, -0.26), SENSOR),
        box('head_crest', (0.06, 0.14, 0.26), (0, 0.31, 0.02), TRIM),
        box('head_antenna', (0.04, 0.16, 0.04), (0.12, 0.33, 0.08), TRIM),
        box('head_neck', (0.24, 0.12, 0.24), (0, -0.07, 0.0), JOINT),
    ]


def build_arm(sign):
    """sign -1 = left, +1 = right. Shoulder-frame origin; elbow sits 0.6384
    below the pivot. Huge pauldrons (1.15x1.20x1.35) tower over the tiny head
    and overhang the tub like the reference photo.
    Forearm pieces are authored elbow-local (elbow pivot = origin)."""
    side = 'L' if sign < 0 else 'R'
    return [
        box(f'arm{side}_pauldron', (1.15, 1.20, 1.35), (sign * 0.85, 0.08, -0.05), ARMOR),
        box(f'arm{side}_pauldron_skirt', (0.72, 0.68, 0.86), (sign * 1.02, -0.30, 0.0), ARMOR_D),
        box(f'arm{side}_upper', (0.34, 0.78, 0.36), (0, -0.36, 0.0), JOINT),
        box(f'arm{side}_elbow_cap', (0.42, 0.22, 0.42), (0, -0.64, 0.0), TRIM),
        # elbow container pieces (routed by the "forearm" keyword, elbow-local)
        box(f'arm{side}_forearm', (0.46, 0.80, 0.50), (0, -0.40, 0.0), ARMOR),
        box(f'arm{side}_forearm_plate', (0.52, 0.30, 0.56), (0, -0.60, 0.0), ARMOR_D),
        box(f'arm{side}_forearm_fist', (0.30, 0.36, 0.34), (0, -0.96, 0.0), JOINT),
    ]


def build_leg(sign):
    """sign -1 = left, +1 = right. Hip-frame origin; knee 1.34 below the hip,
    ankle 1.291 further down (sole 0.37 below the ankle pivot = local 0).
    Knee pieces are authored knee-local, foot pieces ankle-local."""
    side = 'L' if sign < 0 else 'R'
    return [
        box(f'leg{side}_hip_cap', (0.56, 0.36, 0.58), (0, -0.15, 0.0), ARMOR_D),
        box(f'leg{side}_thigh', (0.50, 1.30, 0.54), (0, -0.87, 0.0), ARMOR),
        # knee container pieces (routed by "knee"/"shin" keywords, knee-local)
        box(f'leg{side}_knee', (0.50, 0.40, 0.50), (0, 0.0, -0.02), TRIM),
        box(f'leg{side}_knee_plate', (0.44, 0.50, 0.14), (0, 0.0, -0.32), ARMOR),
        box(f'leg{side}_shin_upper', (0.46, 0.90, 0.50), (0, -0.45, 0.02), ARMOR),
        box(f'leg{side}_shin_lower', (0.40, 0.85, 0.44), (0, -1.10, 0.02), ARMOR_D),
        box(f'leg{side}_shin_guard', (0.34, 1.30, 0.12), (0, -0.75, -0.29), ARMOR),
        # ankle container pieces (routed by "foot" keyword, ankle-local)
        box(f'leg{side}_foot_ankle', (0.30, 0.26, 0.30), (0, -0.12, 0.0), JOINT),
        box(f'leg{side}_foot', (0.50, 0.24, 0.85), (0, -0.25, -0.08), TRIM),
        box(f'leg{side}_foot_toe', (0.44, 0.18, 0.24), (0, -0.28, -0.48), ARMOR_D),
    ]


SLOTS = {
    'body': build_body,
    'head': build_head,
    'arm_left': lambda: build_arm(-1),
    'arm_right': lambda: build_arm(+1),
    'leg_left': lambda: build_leg(-1),
    'leg_right': lambda: build_leg(+1),
}


def main():
    for slot, builder in SLOTS.items():
        out_dir = OUT / slot
        out_dir.mkdir(parents=True, exist_ok=True)
        scene = trimesh.Scene()
        mins = np.full(3, np.inf)
        maxs = np.full(3, -np.inf)
        for name, mesh in builder():
            scene.add_geometry(mesh, node_name=name, geom_name=name)
            mins = np.minimum(mins, mesh.bounds[0])
            maxs = np.maximum(maxs, mesh.bounds[1])
        glb = out_dir / f'tankmech_{slot}.glb'
        scene.export(str(glb))
        print(f'[OK] {slot}: geoms={len(scene.geometry)} '
              f'y[{mins[1]:+.3f},{maxs[1]:+.3f}] z[{mins[2]:+.3f},{maxs[2]:+.3f}] '
              f'-> {glb.relative_to(PROJ)}')


if __name__ == '__main__':
    main()
