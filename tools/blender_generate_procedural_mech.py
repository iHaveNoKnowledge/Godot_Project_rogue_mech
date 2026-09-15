# Blender Procedural Mech Generator — Rogue-Mech hybrid pipeline.
# Run inside Blender (Text Editor > Run Script) or via Blender MCP execute.
#
# What it does:
#   Rebuilds the Godot procedural armor shapes (scripts/mecha/part_mesh_manager.gd
#   _build_procedural_outer_armor) as real Blender meshes, one .glb per joint:
#     head_upper, body_upper,
#     arm_left_upper/lower, arm_right_upper/lower,
#     leg_left_upper/lower, leg_right_upper/lower
#
# Conventions (AGENTS.md — CRITICAL):
#   - Blender forward = +Y (chest/visor/face toward +Y).
#   - Rear (backpack/bulkhead) = -Y.
#   - Units = meters, scale 1.0, origin/pivot AT THE JOINT (shoulder/elbow/hip/knee).
#   - Export with export_yup=True so Blender +Y -> Godot -Z (forward).
#
# After export, in Godot:
#   1. Copy exports/blender_procedural/*.glb -> scenes/mecha/parts/{slot}/
#   2. Create .tscn wrapper per file (Node3D root + Model instance, see body_001.tscn).
#   3. Point ArmorPart .tres mesh_scene / mesh_scene_lower at the .tscn.
#   4. Slots with NO mesh_scene assigned keep showing procedural automatically
#      (PartMeshManager hybrid fallback — _attach_custom_mesh_scene returns false
#      -> _build_procedural_outer_armor).
#
# Usage (Blender Text Editor):
#   1. Open this file, set EXPORT_DIR below if needed, press Run Script.
#   2. Check console for "EXPORTED:" lines.

import bpy
import os
import math

# Output dir — absolute so it works from Blender MCP too.
# Default: <project>/exports/blender_procedural (override as needed).
EXPORT_DIR = os.path.join(
    os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.expanduser("~"),
    "blender_procedural_out",
)
# If running from the project repo, prefer the repo exports folder when it exists.
_REPO_CANDIDATE = r"C:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech\exports\blender_procedural"
if os.path.isdir(os.path.dirname(_REPO_CANDIDATE)):
    EXPORT_DIR = _REPO_CANDIDATE

FORWARD_Y = 1.0  # reminder: front features at +Y


def _ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def clear_scene() -> None:
    # Delete all mesh/armature objects, keep cameras/lights.
    for obj in list(bpy.data.objects):
        if obj.type in ("MESH", "ARMATURE", "CURVE", "SURFACE", "META", "FONT"):
            bpy.data.objects.remove(obj, do_unlink=True)


def _mat(name: str, base_color, metallic: float = 0.1, roughness: float = 0.65):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
    # Set Principled BSDF by TYPE (node names are localized on non-English UI).
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        try:
            bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
            if "Metallic" in bsdf.inputs:
                bsdf.inputs["Metallic"].default_value = metallic
            if "Roughness" in bsdf.inputs:
                bsdf.inputs["Roughness"].default_value = roughness
        except Exception:
            pass
    return mat


MAT_ARMOR = None
MAT_TRIM = None


def init_mats() -> None:
    global MAT_ARMOR, MAT_TRIM
    MAT_ARMOR = _mat("ProcArmor", (0.32, 0.36, 0.42), 0.08, 0.68)
    MAT_TRIM = _mat("ProcTrim", (0.12, 0.14, 0.18), 0.12, 0.72)


def add_box(name: str, size_xyz, loc_xyz, rot_deg=None, mat=None, collection=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc_xyz)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = size_xyz
    # Re-apply location (dimensions assignment can shift object in some versions).
    obj.location = loc_xyz
    if rot_deg:
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = (math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2]))
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    # Flat shading -> faceted armor plates (matches MECH_MODEL_GUIDE §4.1b).
    for poly in obj.data.polygons:
        poly.use_smooth = False
    if collection is not None:
        # Move from master collection into slot collection.
        for coll in obj.users_collection:
            coll.objects.unlink(obj)
        collection.objects.link(obj)
    return obj


def add_cyl(name: str, radius: float, height: float, loc_xyz, rot_deg=None, mat=None, collection=None, vertices: int = 24):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=height, location=loc_xyz, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    if rot_deg:
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = (math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2]))
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    if collection is not None:
        for coll in obj.users_collection:
            coll.objects.unlink(obj)
        collection.objects.link(obj)
    return obj


def _slot_collection(slot_file: str):
    coll = bpy.data.collections.get(slot_file)
    if coll is None:
        coll = bpy.data.collections.new(slot_file)
        bpy.context.scene.collection.children.link(coll)
    return coll


def _export_slot(slot_file: str, objects) -> str:
    _ensure_dir(EXPORT_DIR)
    # Select only this slot's objects.
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0] if objects else None
    out = os.path.join(EXPORT_DIR, slot_file + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=True,
        export_yup=True,  # Blender +Y -> Godot -Z (forward). DO NOT turn off.
        export_apply=True,
        export_materials="EXPORT",
    )
    print("EXPORTED:", out)
    return out


# ---------------------------------------------------------------------------
# Slot builders — Blender space: X right, +Y forward, Z up. Origin = joint.
# Proportions mirror part_mesh_manager.gd procedural sizes (meters).
# ---------------------------------------------------------------------------

def build_head(coll):
    objs = []
    # Helmet cowl (compact turret). Front visor side toward +Y.
    objs.append(add_box("Helmet", (0.24, 0.24, 0.14), (0, 0.02, 0.05), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("Cheek_L", (0.04, 0.18, 0.10), (-0.13, 0.04, 0.03), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Cheek_R", (0.04, 0.18, 0.10), (0.13, 0.04, 0.03), mat=MAT_TRIM, collection=coll))
    # Brow wedge (rotated slab leaning back).
    objs.append(add_box("Brow", (0.18, 0.16, 0.10), (0, 0.06, 0.10), rot_deg=(-25, 0, 0), mat=MAT_ARMOR, collection=coll))
    # Neck collar ring.
    objs.append(add_cyl("Collar", 0.13, 0.06, (0, 0, -0.05), mat=MAT_TRIM, collection=coll))
    return objs


def build_body(coll):
    objs = []
    # Chest plate — wide slab, front face +Y.
    objs.append(add_box("Chest", (0.95, 0.48, 0.65), (0, 0.14, 0.12), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("Vent_L", (0.14, 0.25, 0.35), (-0.42, 0.08, 0.15), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Vent_R", (0.14, 0.25, 0.35), (0.42, 0.08, 0.15), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("CenterTrim", (0.44, 0.05, 0.08), (0, 0.36, 0.02), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("AbPlate", (0.58, 0.26, 0.35), (0, 0.10, -0.28), mat=MAT_ARMOR, collection=coll))
    objs.append(add_cyl("NeckCowl", 0.21, 0.14, (0, 0.04, 0.28), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("ShoulderCowl_L", (0.34, 0.38, 0.28), (-0.58, 0.02, 0.22), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("ShoulderCowl_R", (0.34, 0.38, 0.28), (0.58, 0.02, 0.22), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Pelvis", (0.68, 0.36, 0.24), (0, 0.04, -0.48), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Skirt_L", (0.12, 0.38, 0.34), (-0.50, 0.02, -0.48), rot_deg=(0, 0, -12), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("Skirt_R", (0.12, 0.38, 0.34), (0.50, 0.02, -0.48), rot_deg=(0, 0, 12), mat=MAT_ARMOR, collection=coll))
    return objs


def build_arm_upper(coll, mirror: float):
    objs = []
    objs.append(add_box("Pauldron", (0.48, 0.48, 0.34), (mirror * 0.08, 0, 0.04), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("PauldronTrim", (0.52, 0.52, 0.10), (mirror * 0.08, 0, 0.16), mat=MAT_TRIM, collection=coll))
    return objs


def build_arm_lower(coll):
    objs = []
    objs.append(add_box("ForearmGuard", (0.34, 0.34, 0.46), (0, 0, -0.225), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("ElbowCap", (0.26, 0.12, 0.16), (0, -0.14, 0.0), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Knuckle", (0.18, 0.18, 0.06), (0, 0.02, -0.45), mat=MAT_ARMOR, collection=coll))
    return objs


def build_leg_upper(coll):
    objs = []
    objs.append(add_box("ThighGuard", (0.36, 0.36, 0.44), (0, 0, -0.275), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("ThighSide_L", (0.06, 0.28, 0.38), (-0.19, 0, -0.275), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("ThighSide_R", (0.06, 0.28, 0.38), (0.19, 0, -0.275), mat=MAT_TRIM, collection=coll))
    return objs


def build_leg_lower(coll):
    objs = []
    objs.append(add_box("KneeCap", (0.30, 0.24, 0.26), (0, -0.15, 0.0), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("ShinGuard", (0.36, 0.34, 0.48), (0, -0.04, -0.275), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("Calf_L", (0.06, 0.24, 0.36), (-0.19, -0.02, -0.275), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Calf_R", (0.06, 0.24, 0.36), (0.19, -0.02, -0.275), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("FootCap", (0.32, 0.42, 0.10), (0, 0.04, -0.56), mat=MAT_ARMOR, collection=coll))
    objs.append(add_box("Skid_L", (0.05, 0.46, 0.08), (-0.17, 0.04, -0.56), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("Skid_R", (0.05, 0.46, 0.08), (0.17, 0.04, -0.56), mat=MAT_TRIM, collection=coll))
    objs.append(add_box("ToeDeflector", (0.28, 0.14, 0.07), (0, 0.24, -0.57), rot_deg=(-15, 0, 0), mat=MAT_TRIM, collection=coll))
    return objs


def build_all(export: bool = True):
    init_mats()
    clear_scene()
    plan = [
        ("procedural_head_upper", build_head, {}),
        ("procedural_body_upper", build_body, {}),
        ("procedural_arm_left_upper", build_arm_upper, {"mirror": -1.0}),
        ("procedural_arm_left_lower", build_arm_lower, {}),
        ("procedural_arm_right_upper", build_arm_upper, {"mirror": 1.0}),
        ("procedural_arm_right_lower", build_arm_lower, {}),
        ("procedural_leg_left_upper", build_leg_upper, {}),
        ("procedural_leg_left_lower", build_leg_lower, {}),
        ("procedural_leg_right_upper", build_leg_upper, {}),
        ("procedural_leg_right_lower", build_leg_lower, {}),
    ]
    results = []
    for slot_file, builder, kwargs in plan:
        coll = _slot_collection(slot_file)
        objs = builder(coll, **kwargs) if kwargs else builder(coll)
        if export:
            results.append(_export_slot(slot_file, objs))
    print("DONE. Files:", len(results))
    return results


if __name__ == "__main__":
    build_all(export=True)
