"""
Generates the "Tankhead Heavy Iron" modular armor pack for Godot_Project_rogue_mech.
Modeled based on the concept art: tank-angular-blockylegs_00001_.png

Features:
- Head: Low-profile angular armored helmet with recessed horizontal glowing visor and antenna fin.
- Body: Massive industrial tank chassis with heavy angled front glacis, applique reactive plates,
        raised neck collar, side vent sponsons, and rear reactor block.
- Arms: Heavy rectangular shoulder pauldrons with reinforced applique plates and blocky forearm shields.
- Legs: "Angular Blockylegs" - ultra-heavy angular beveled blocky thighs, angular knee deflector,
        heavy plated shin shield, and blocky industrial stabilizer foot.

Pivots (in Godot meters, Forward = -Z, Up = +Y):
- Head: Pivot at neck base (0, 0, 0)
- Body: Pivot at spine core (0, 0, 0)
- Arm Upper: Pivot at shoulder (0, 0, 0), hangs down -Y
- Arm Lower: Pivot at elbow (0, 0, 0), hangs down -Y
- Leg Upper: Pivot at hip (0, 0, 0), hangs down -Y
- Leg Lower: Pivot at knee (0, 0, 0), hangs down -Y
"""

import bpy
import bmesh
import os
import math
from mathutils import Vector, Matrix

BASE_DIR = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
PARTS_DIR = os.path.join(BASE_DIR, "scenes", "mecha", "parts")

# Materials
def get_materials():
    # 1. Main Slate Grey Armor
    mat_armor = bpy.data.materials.new("Tankhead_Armor")
    mat_armor.use_nodes = True
    bsdf = mat_armor.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.28, 0.31, 0.35, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.15
    bsdf.inputs["Roughness"].default_value = 0.65

    # 2. Dark Industrial Undersuit / Mechanical
    mat_dark = bpy.data.materials.new("Tankhead_Dark")
    mat_dark.use_nodes = True
    bsdf2 = mat_dark.node_tree.nodes["Principled BSDF"]
    bsdf2.inputs["Base Color"].default_value = (0.12, 0.13, 0.15, 1.0)
    bsdf2.inputs["Metallic"].default_value = 0.30
    bsdf2.inputs["Roughness"].default_value = 0.70

    # 3. Bronze / Orange Accent & Sensor
    mat_accent = bpy.data.materials.new("Tankhead_Sensor")
    mat_accent.use_nodes = True
    bsdf3 = mat_accent.node_tree.nodes["Principled BSDF"]
    bsdf3.inputs["Base Color"].default_value = (0.95, 0.48, 0.12, 1.0)
    bsdf3.inputs["Metallic"].default_value = 0.10
    bsdf3.inputs["Roughness"].default_value = 0.30
    # Emissive for sensor visor
    bsdf3.inputs["Emission Color"].default_value = (0.95, 0.48, 0.12, 1.0)
    bsdf3.inputs["Emission Strength"].default_value = 2.5

    return mat_armor, mat_dark, mat_accent

def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat, do_unlink=True)

def create_box(name, loc, size, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if mat:
        obj.data.materials.append(mat)
    return obj

def apply_bevel_and_edgesplit(obj, bevel_w=0.015, split_angle=30.0):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    
    if bevel_w > 0:
        bev = obj.modifiers.new("Bevel", 'BEVEL')
        bev.width = bevel_w
        bev.segments = 1
        bev.limit_method = 'ANGLE'
        bev.angle_limit = math.radians(40)
        bpy.ops.object.modifier_apply(modifier="Bevel")
        
    for poly in obj.data.polygons:
        poly.use_smooth = False
        
    es = obj.modifiers.new("EdgeSplit", 'EDGE_SPLIT')
    es.split_angle = math.radians(split_angle)
    bpy.ops.object.modifier_apply(modifier="EdgeSplit")
    
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')

def join_objects(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    main = bpy.context.view_layer.objects.active
    main.name = name
    return main

def mirror_part_x(obj, name):
    # Duplicate and mirror across X=0
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.duplicate()
    mir = bpy.context.view_layer.objects.active
    mir.name = name
    
    # Scale X by -1
    mir.scale.x = -1.0
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    
    # Recalculate normals
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return mir

def export_glb(obj, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    
    # In Blender: glTF exporter expects Blender coords (+Z up, +Y forward by gltf standard)
    # When exporting with export_scene.gltf:
    # Blender +Z becomes glTF +Y (Up)
    # Blender +Y becomes glTF -Z (Forward)
    # Blender +X becomes glTF +X (Right)
    # We build our models directly in Godot coordinates:
    # Godot: Up = +Y, Forward = -Z, Right = +X.
    # To export correctly to Godot without exporter transforming coordinates unexpectedly:
    # We author in Blender Z-up or apply the conversion.
    # Specifically, if authored where:
    # Blender X = Godot X
    # Blender Y = Godot Z (so Blender -Y is Godot Forward)
    # Blender Z = Godot Y (so Blender +Z is Godot Up)
    # Let's ensure standard Godot orientation by rotating (RotX -90) prior to export,
    # OR exporting with glTF default export which converts Blender (+Z up, +Y forward) to glTF (+Y up, -Z forward).
    # Since glTF 2.0 standard is +Y Up, -Z Forward:
    # If we author in Godot coordinates: +Y Up, -Z Forward:
    # We can rotate around X by +90 so Blender sees it as Z-up, then export!
    
    obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_materials='EXPORT',
        export_normals=True
    )
    # Revert rotation for further operations if needed
    obj.rotation_euler = (math.radians(-90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    print(f"EXPORTED: {filepath} | Size: {os.path.getsize(filepath)} bytes")


# ==============================================================================
# BUILDERS FOR TANKHEAD MODULAR ARMOR
# ==============================================================================

def build_tankhead_head(mat_armor, mat_dark, mat_accent):
    """
    Head: Pivot at neck base (0, 0, 0).
    Height ~ 0.50m. Low profile, angular tank helmet.
    """
    objs = []
    # Helmet Main Dome (angular block)
    dome = create_box("head_dome", (0, 0.18, 0.02), (0.42, 0.24, 0.44), mat=mat_armor)
    objs.append(dome)
    
    # Sloped Brow
    brow = create_box("head_brow", (0, 0.24, -0.16), (0.38, 0.12, 0.18), rot=(math.radians(-25), 0, 0), mat=mat_armor)
    objs.append(brow)
    
    # Recessed Visor (Glowing Sensor)
    visor = create_box("head_visor", (0, 0.16, -0.22), (0.28, 0.06, 0.05), mat=mat_accent)
    objs.append(visor)
    
    # Cheeks
    cheek_l = create_box("head_cheek_l", (-0.20, 0.10, -0.06), (0.08, 0.20, 0.32), rot=(0, math.radians(15), 0), mat=mat_armor)
    cheek_r = create_box("head_cheek_r", (0.20, 0.10, -0.06), (0.08, 0.20, 0.32), rot=(0, math.radians(-15), 0), mat=mat_armor)
    objs.extend([cheek_l, cheek_r])
    
    # Chin / Jaw
    chin = create_box("head_chin", (0, 0.04, -0.16), (0.18, 0.08, 0.14), mat=mat_dark)
    objs.append(chin)
    
    # Antenna / Sensor Mast on Top
    antenna = create_box("head_antenna", (0, 0.34, 0.06), (0.04, 0.14, 0.22), rot=(math.radians(15), 0, 0), mat=mat_accent)
    objs.append(antenna)
    
    # Neck Collar Rim
    collar = create_box("head_collar", (0, 0.02, 0), (0.34, 0.06, 0.36), mat=mat_dark)
    objs.append(collar)
    
    head = join_objects(objs, "tankhead_head")
    apply_bevel_and_edgesplit(head, bevel_w=0.012)
    return head


def build_tankhead_body(mat_armor, mat_dark, mat_accent):
    """
    Body: Pivot at spine core (0, 0, 0).
    Heavy angular tank chassis with front applique armor, side sponsons, rear powerpack.
    """
    objs = []
    # Central Torso Core
    torso = create_box("body_torso", (0, 0.08, 0.02), (0.76, 0.72, 0.54), mat=mat_armor)
    objs.append(torso)
    
    # Sloped Front Glacis Chest Armor
    chest_glacis = create_box("body_glacis", (0, 0.18, -0.26), (0.84, 0.46, 0.18), rot=(math.radians(28), 0, 0), mat=mat_armor)
    objs.append(chest_glacis)
    
    # Applique Reactive Armor Plates (Dual Slabs)
    slab_l = create_box("body_slab_l", (-0.24, 0.22, -0.34), (0.28, 0.24, 0.06), rot=(math.radians(28), 0, 0), mat=mat_accent)
    slab_r = create_box("body_slab_r", (0.24, 0.22, -0.34), (0.28, 0.24, 0.06), rot=(math.radians(28), 0, 0), mat=mat_accent)
    objs.extend([slab_l, slab_r])
    
    # High Neck Collar Shield (protects head)
    collar_l = create_box("body_collar_l", (-0.26, 0.44, -0.04), (0.10, 0.16, 0.36), mat=mat_armor)
    collar_r = create_box("body_collar_r", (0.26, 0.44, -0.04), (0.10, 0.16, 0.36), mat=mat_armor)
    collar_back = create_box("body_collar_back", (0, 0.46, 0.14), (0.58, 0.18, 0.08), mat=mat_armor)
    objs.extend([collar_l, collar_r, collar_back])
    
    # Side Torso Sponsons / Air Intakes
    side_l = create_box("body_side_l", (-0.46, 0.06, -0.02), (0.20, 0.54, 0.46), mat=mat_dark)
    side_r = create_box("body_side_r", (0.46, 0.06, -0.02), (0.20, 0.54, 0.46), mat=mat_dark)
    objs.extend([side_l, side_r])
    
    # Segmented Abdomen / Groin Plate
    ab_upper = create_box("body_ab_upper", (0, -0.16, -0.22), (0.52, 0.20, 0.18), mat=mat_armor)
    ab_lower = create_box("body_ab_lower", (0, -0.34, -0.18), (0.46, 0.22, 0.22), mat=mat_armor)
    pelvis_groin = create_box("body_pelvis", (0, -0.48, -0.08), (0.38, 0.18, 0.32), rot=(math.radians(15), 0, 0), mat=mat_dark)
    objs.extend([ab_upper, ab_lower, pelvis_groin])
    
    # Rear Powerpack / Reactor Housing
    reactor = create_box("body_reactor", (0, 0.12, 0.34), (0.64, 0.58, 0.28), mat=mat_dark)
    exhaust_l = create_box("body_exhaust_l", (-0.22, 0.36, 0.46), (0.14, 0.18, 0.12), rot=(math.radians(-20), 0, 0), mat=mat_accent)
    exhaust_r = create_box("body_exhaust_r", (0.22, 0.36, 0.46), (0.14, 0.18, 0.12), rot=(math.radians(-20), 0, 0), mat=mat_accent)
    objs.extend([reactor, exhaust_l, exhaust_r])
    
    body = join_objects(objs, "tankhead_body")
    apply_bevel_and_edgesplit(body, bevel_w=0.018)
    return body


def build_tankhead_arm_upper(mat_armor, mat_dark, mat_accent):
    """
    Arm Upper: Pivot at Shoulder (0, 0, 0).
    Extends DOWN along -Y to ~ -0.62m.
    Massive blocky shoulder pauldron with layered applique armor.
    """
    objs = []
    # Main Shoulder Pauldron Block
    pauldron = create_box("arm_pauldron", (0, 0.04, 0), (0.52, 0.38, 0.52), mat=mat_armor)
    objs.append(pauldron)
    
    # Outer Applique Shoulder Armor Slab (slanted outwards)
    outer_slab = create_box("arm_outer_slab", (-0.26, 0.06, 0), (0.08, 0.34, 0.48), mat=mat_accent)
    objs.append(outer_slab)
    
    # Upper Arm Sleeve Guard
    sleeve = create_box("arm_sleeve", (0, -0.32, 0), (0.34, 0.40, 0.34), mat=mat_dark)
    objs.append(sleeve)
    
    # Front Bicep Armor Plate
    bicep_plate = create_box("arm_bicep_plate", (0, -0.32, -0.16), (0.28, 0.36, 0.08), mat=mat_armor)
    objs.append(bicep_plate)
    
    arm_up = join_objects(objs, "tankhead_arm_left_upper")
    apply_bevel_and_edgesplit(arm_up, bevel_w=0.015)
    return arm_up


def build_tankhead_arm_lower(mat_armor, mat_dark, mat_accent):
    """
    Arm Lower: Pivot at Elbow (0, 0, 0).
    Extends DOWN along -Y to ~ -0.75m.
    Thick angular forearm casing with defensive side ridge and armored knuckle.
    """
    objs = []
    # Elbow Guard Cap
    elbow = create_box("arm_elbow", (0, 0.02, 0.12), (0.26, 0.20, 0.18), rot=(math.radians(25), 0, 0), mat=mat_dark)
    objs.append(elbow)
    
    # Main Forearm Casing
    forearm = create_box("arm_forearm", (0, -0.28, 0), (0.36, 0.46, 0.36), mat=mat_armor)
    objs.append(forearm)
    
    # Outer Defensive Shield Ridge
    ridge = create_box("arm_ridge", (-0.18, -0.26, 0), (0.10, 0.42, 0.32), mat=mat_accent)
    objs.append(ridge)
    
    # Armored Heavy Fist / Knuckle
    knuckle = create_box("arm_knuckle", (0, -0.58, -0.04), (0.24, 0.22, 0.26), mat=mat_dark)
    objs.append(knuckle)
    
    arm_lo = join_objects(objs, "tankhead_arm_left_lower")
    apply_bevel_and_edgesplit(arm_lo, bevel_w=0.015)
    return arm_lo


def build_tankhead_leg_upper(mat_armor, mat_dark, mat_accent):
    """
    Leg Upper: Pivot at Hip (0, 0, 0).
    Extends DOWN along -Y to ~ -0.88m.
    THE SIGNATURE: "Angular Blockylegs" — massive angular blocky thighs with heavy chamfered edges.
    """
    objs = []
    # Hip Joint Armor Socket
    hip_cap = create_box("leg_hip_cap", (0, 0.04, 0), (0.50, 0.24, 0.50), mat=mat_dark)
    objs.append(hip_cap)
    
    # Massive Angular Blocky Thigh Armor
    thigh_block = create_box("leg_thigh_block", (0, -0.42, 0), (0.64, 0.72, 0.62), mat=mat_armor)
    objs.append(thigh_block)
    
    # Front Reactive Armor Slanted Plate
    front_plate = create_box("leg_front_plate", (0, -0.40, -0.30), (0.52, 0.60, 0.10), rot=(math.radians(12), 0, 0), mat=mat_accent)
    objs.append(front_plate)
    
    # Outer Side Armor Slab
    side_plate = create_box("leg_side_plate", (-0.32, -0.42, 0), (0.08, 0.58, 0.50), mat=mat_dark)
    objs.append(side_plate)
    
    leg_up = join_objects(objs, "tankhead_leg_left_upper")
    apply_bevel_and_edgesplit(leg_up, bevel_w=0.024)
    return leg_up


def build_tankhead_leg_lower(mat_armor, mat_dark, mat_accent):
    """
    Leg Lower: Pivot at Knee (0, 0, 0).
    Extends DOWN along -Y to foot sole at ~ -1.15m.
    Angular knee guard, heavy angular shin shield with side vents, and blocky stabilizer tank foot.
    """
    objs = []
    # Angular Knee Deflector Plate
    knee = create_box("leg_knee", (0, 0.08, -0.20), (0.38, 0.32, 0.22), rot=(math.radians(35), 0, 0), mat=mat_accent)
    objs.append(knee)
    
    # Knee Joint Casing
    knee_core = create_box("leg_knee_core", (0, 0.02, 0), (0.42, 0.22, 0.38), mat=mat_dark)
    objs.append(knee_core)
    
    # Heavy Angular Front Shin Armor
    shin = create_box("leg_shin", (0, -0.44, -0.06), (0.54, 0.76, 0.50), mat=mat_armor)
    objs.append(shin)
    
    # Front Shin Armor Ridge
    shin_ridge = create_box("leg_shin_ridge", (0, -0.40, -0.28), (0.34, 0.62, 0.12), rot=(math.radians(15), 0, 0), mat=mat_accent)
    objs.append(shin_ridge)
    
    # Calf Armor & Rear Thruster Box
    calf = create_box("leg_calf", (0, -0.46, 0.20), (0.46, 0.58, 0.26), mat=mat_dark)
    objs.append(calf)
    
    # Ankle Cuff
    cuff = create_box("leg_cuff", (0, -0.88, 0), (0.44, 0.18, 0.46), mat=mat_dark)
    objs.append(cuff)
    
    # Heavy Blocky Stabilizer Foot
    foot_heel = create_box("leg_foot_heel", (0, -1.05, 0.16), (0.46, 0.18, 0.32), mat=mat_dark)
    foot_main = create_box("leg_foot_main", (0, -1.05, -0.16), (0.50, 0.20, 0.44), mat=mat_armor)
    foot_claw = create_box("leg_foot_claw", (0, -1.06, -0.38), (0.42, 0.14, 0.18), rot=(math.radians(18), 0, 0), mat=mat_accent)
    objs.extend([foot_heel, foot_main, foot_claw])
    
    leg_lo = join_objects(objs, "tankhead_leg_left_lower")
    apply_bevel_and_edgesplit(leg_lo, bevel_w=0.020)
    return leg_lo


def generate_all():
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    
    print("=== Generating Tankhead Heavy Iron Pack ===")
    
    # 1. Head
    head = build_tankhead_head(mat_armor, mat_dark, mat_sensor)
    export_glb(head, os.path.join(PARTS_DIR, "head", "tankhead_head.glb"))
    
    # 2. Body
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    body = build_tankhead_body(mat_armor, mat_dark, mat_sensor)
    export_glb(body, os.path.join(PARTS_DIR, "body", "tankhead_body.glb"))
    
    # 3. Arm Left Upper & Lower
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    arm_l_up = build_tankhead_arm_upper(mat_armor, mat_dark, mat_sensor)
    export_glb(arm_l_up, os.path.join(PARTS_DIR, "arm_left", "tankhead_arm_left_upper.glb"))
    
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    arm_l_lo = build_tankhead_arm_lower(mat_armor, mat_dark, mat_sensor)
    export_glb(arm_l_lo, os.path.join(PARTS_DIR, "arm_left", "tankhead_arm_left_lower.glb"))
    
    # 4. Arm Right Upper & Lower (mirrored)
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    arm_l_up = build_tankhead_arm_upper(mat_armor, mat_dark, mat_sensor)
    arm_r_up = mirror_part_x(arm_l_up, "tankhead_arm_right_upper")
    export_glb(arm_r_up, os.path.join(PARTS_DIR, "arm_right", "tankhead_arm_right_upper.glb"))
    
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    arm_l_lo = build_tankhead_arm_lower(mat_armor, mat_dark, mat_sensor)
    arm_r_lo = mirror_part_x(arm_l_lo, "tankhead_arm_right_lower")
    export_glb(arm_r_lo, os.path.join(PARTS_DIR, "arm_right", "tankhead_arm_right_lower.glb"))
    
    # 5. Leg Left Upper & Lower ("Angular Blockylegs")
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    leg_l_up = build_tankhead_leg_upper(mat_armor, mat_dark, mat_sensor)
    export_glb(leg_l_up, os.path.join(PARTS_DIR, "leg_left", "tankhead_leg_left_upper.glb"))
    
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    leg_l_lo = build_tankhead_leg_lower(mat_armor, mat_dark, mat_sensor)
    export_glb(leg_l_lo, os.path.join(PARTS_DIR, "leg_left", "tankhead_leg_left_lower.glb"))
    
    # 6. Leg Right Upper & Lower (mirrored)
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    leg_l_up = build_tankhead_leg_upper(mat_armor, mat_dark, mat_sensor)
    leg_r_up = mirror_part_x(leg_l_up, "tankhead_leg_right_upper")
    export_glb(leg_r_up, os.path.join(PARTS_DIR, "leg_right", "tankhead_leg_right_upper.glb"))
    
    clean_scene()
    mat_armor, mat_dark, mat_sensor = get_materials()
    leg_l_lo = build_tankhead_leg_lower(mat_armor, mat_dark, mat_sensor)
    leg_r_lo = mirror_part_x(leg_l_lo, "tankhead_leg_right_lower")
    export_glb(leg_r_lo, os.path.join(PARTS_DIR, "leg_right", "tankhead_leg_right_lower.glb"))

    print("=== All Tankhead Heavy Iron parts generated successfully! ===")

if __name__ == "__main__":
    generate_all()
