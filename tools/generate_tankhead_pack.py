"""
Generates the "Tankhead Heavy Iron" modular armor pack for Godot_Project_rogue_mech.
Modeled based on the concept art: tank-angular-blockylegs_00001_.png

Fixed and refined:
- Head: Encases the entire skull and neck base from all sides (front, back, left, right, top).
- Body: Raised heavy armored collar and upper glacis extending up to Z = +0.92m,
        completely wrapping the upper spine and neck base.
- Blender coordinates:
    +X: Right, -X: Left
    +Y: Forward (maps directly to Godot -Z Forward)
    -Y: Back (maps directly to Godot +Z Back)
    +Z: Up (maps directly to Godot +Y Up)
    -Z: Down (maps directly to Godot -Y Down)
- All parts apply location=True so mesh origin is strictly (0, 0, 0) matching Godot joint pivots.
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
    # 1. Main Pale Industrial Off-White / Concrete Primer Grey Armor
    mat_armor = bpy.data.materials.new("Tankhead_Armor")
    mat_armor.use_nodes = True
    bsdf = mat_armor.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.76, 0.75, 0.73, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.12
    bsdf.inputs["Roughness"].default_value = 0.58

    # 2. Dark Industrial Undersuit / Mechanical
    mat_dark = bpy.data.materials.new("Tankhead_Dark")
    mat_dark.use_nodes = True
    bsdf2 = mat_dark.node_tree.nodes["Principled BSDF"]
    bsdf2.inputs["Base Color"].default_value = (0.12, 0.13, 0.15, 1.0)
    bsdf2.inputs["Metallic"].default_value = 0.35
    bsdf2.inputs["Roughness"].default_value = 0.65

    # 3. Bronze / Orange Accent & Sensor
    mat_accent = bpy.data.materials.new("Tankhead_Sensor")
    mat_accent.use_nodes = True
    bsdf3 = mat_accent.node_tree.nodes["Principled BSDF"]
    bsdf3.inputs["Base Color"].default_value = (0.96, 0.52, 0.10, 1.0)
    bsdf3.inputs["Metallic"].default_value = 0.10
    bsdf3.inputs["Roughness"].default_value = 0.30
    bsdf3.inputs["Emission Color"].default_value = (0.96, 0.52, 0.10, 1.0)
    bsdf3.inputs["Emission Strength"].default_value = 2.5

    return mat_armor, mat_dark, mat_accent

def clean_scene():
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
    # Apply all transforms into vertex data so origin stays at (0, 0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
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
    # Ensure final origin is strictly at (0, 0, 0)
    main.location = (0, 0, 0)
    return main

def mirror_part_x(obj, name):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.duplicate()
    mir = bpy.context.view_layer.objects.active
    mir.name = name
    
    # Mirror across X
    mir.scale.x = -1.0
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
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
    
    # Standard Blender glTF exporter automatically transforms:
    # Blender +X -> glTF +X (Right)
    # Blender +Y -> glTF -Z (Forward)
    # Blender +Z -> glTF +Y (Up)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_materials='EXPORT',
        export_normals=True
    )
    print(f"EXPORTED: {filepath} | Size: {os.path.getsize(filepath)} bytes")


# ==============================================================================
# BUILDERS FOR TANKHEAD MODULAR ARMOR
# ==============================================================================

def build_tankhead_head(mat_armor, mat_dark, mat_accent):
    """
    Head: Pivot at neck base (0, 0, 0).
    Encases the procedural skull (width ±0.20m, depth ±0.24m, height 0.0 to 0.25m).
    Blender coords: +Y = Forward, +Z = Up, +X = Right.
    """
    objs = []
    # 1. Helmet Main Shell / Dome (Solid block encasing the whole skull)
    dome = create_box("head_dome", (0, 0.0, 0.16), (0.50, 0.58, 0.38), mat=mat_armor)
    objs.append(dome)
    
    # 2. Sloped Front Brow / Forehead Armor
    brow = create_box("head_brow", (0, 0.22, 0.26), (0.46, 0.18, 0.14), rot=(math.radians(-25), 0, 0), mat=mat_armor)
    objs.append(brow)
    
    # 3. Recessed Glowing Visor Sensor
    visor = create_box("head_visor", (0, 0.28, 0.16), (0.34, 0.06, 0.08), mat=mat_accent)
    objs.append(visor)
    
    # 4. Cheeks & Ear Pod Armor (left & right)
    cheek_l = create_box("head_cheek_l", (-0.26, 0.04, 0.12), (0.08, 0.44, 0.26), mat=mat_armor)
    cheek_r = create_box("head_cheek_r", (0.26, 0.04, 0.12), (0.08, 0.44, 0.26), mat=mat_armor)
    objs.extend([cheek_l, cheek_r])
    
    # 5. Chin / Throat Armor Plate
    chin = create_box("head_chin", (0, 0.22, 0.04), (0.26, 0.18, 0.10), mat=mat_dark)
    objs.append(chin)
    
    # 6. Rear Helmet Shell (protects back of head)
    back_helmet = create_box("head_back", (0, -0.28, 0.16), (0.44, 0.10, 0.30), mat=mat_armor)
    objs.append(back_helmet)
    
    # 7. Reinforced Neck Collar Rim (encases neck pivot)
    collar = create_box("head_collar", (0, 0.0, -0.04), (0.42, 0.46, 0.12), mat=mat_dark)
    objs.append(collar)
    
    # 8. Antenna Fin / Sensor Mast on Top
    antenna = create_box("head_antenna", (0, -0.06, 0.38), (0.06, 0.28, 0.16), rot=(math.radians(-15), 0, 0), mat=mat_accent)
    objs.append(antenna)
    
    # 9. Twin Angled Ear Antenna Fins (from concept art)
    ear_l = create_box("head_ear_l", (-0.26, -0.04, 0.40), (0.05, 0.22, 0.28), rot=(0, math.radians(-18), math.radians(-8)), mat=mat_armor)
    ear_r = create_box("head_ear_r", (0.26, -0.04, 0.40), (0.05, 0.22, 0.28), rot=(0, math.radians(18), math.radians(8)), mat=mat_armor)
    ear_accent = create_box("head_ear_accent", (-0.28, -0.02, 0.42), (0.02, 0.10, 0.14), rot=(0, math.radians(-18), math.radians(-8)), mat=mat_accent)
    objs.extend([ear_l, ear_r, ear_accent])
    
    head = join_objects(objs, "tankhead_head")
    apply_bevel_and_edgesplit(head, bevel_w=0.014)
    return head


def build_tankhead_body(mat_armor, mat_dark, mat_accent):
    """
    Body: Pivot at spine core (0, 0, 0).
    Heavy angular tank chassis with raised collar that reaches up to Z = +0.92m,
    completely wrapping and protecting the upper spine and neck base.
    """
    objs = []
    # 1. Central Torso Core
    torso = create_box("body_torso", (0, 0.0, 0.20), (0.96, 0.66, 0.90), mat=mat_armor)
    objs.append(torso)
    
    # 2. Sloped Front Glacis Chest Armor
    chest_glacis = create_box("body_glacis", (0, 0.26, 0.38), (0.92, 0.22, 0.52), rot=(math.radians(-24), 0, 0), mat=mat_armor)
    objs.append(chest_glacis)
    
    # 3. Applique Reactive Armor Slabs (Tri-Segment Front Chest Blocks from concept art)
    slab_mid = create_box("body_slab_mid", (0, 0.38, 0.40), (0.36, 0.12, 0.28), rot=(math.radians(-24), 0, 0), mat=mat_armor)
    slab_l = create_box("body_slab_l", (-0.28, 0.35, 0.42), (0.26, 0.10, 0.28), rot=(math.radians(-24), 0, 0), mat=mat_armor)
    slab_r = create_box("body_slab_r", (0.28, 0.35, 0.42), (0.26, 0.10, 0.28), rot=(math.radians(-24), 0, 0), mat=mat_armor)
    objs.extend([slab_mid, slab_l, slab_r])
    
    # 4. HIGH RAISED ARMOR COLLAR (Fully encases the upper spine and neck base up to +0.92m)
    collar_l = create_box("body_collar_l", (-0.28, 0.04, 0.74), (0.14, 0.46, 0.36), rot=(0, math.radians(10), 0), mat=mat_armor)
    collar_r = create_box("body_collar_r", (0.28, 0.04, 0.74), (0.14, 0.46, 0.36), rot=(0, math.radians(-10), 0), mat=mat_armor)
    collar_front = create_box("body_collar_front", (0, 0.26, 0.70), (0.44, 0.12, 0.26), rot=(math.radians(-15), 0, 0), mat=mat_armor)
    collar_back = create_box("body_collar_back", (0, -0.18, 0.78), (0.66, 0.12, 0.34), mat=mat_armor)
    objs.extend([collar_l, collar_r, collar_front, collar_back])
    
    # 5. Side Torso Sponsons / Heavy Shoulder Sockets (Bridges outward to shoulder pivot at X = ±0.78m)
    side_l = create_box("body_side_l", (-0.64, 0.0, 0.26), (0.36, 0.54, 0.64), mat=mat_dark)
    side_r = create_box("body_side_r", (0.64, 0.0, 0.26), (0.36, 0.54, 0.64), mat=mat_dark)
    cowl_l = create_box("body_cowl_l", (-0.68, 0.04, 0.38), (0.30, 0.42, 0.22), mat=mat_armor)
    cowl_r = create_box("body_cowl_r", (0.68, 0.04, 0.38), (0.30, 0.42, 0.22), mat=mat_armor)
    objs.extend([side_l, side_r, cowl_l, cowl_r])
    
    # 6. Segmented Abdomen / Groin Armor & Pelvis Hip Girdle
    ab_mid = create_box("body_ab_mid", (0, 0.20, -0.14), (0.60, 0.20, 0.24), mat=mat_armor)
    ab_low = create_box("body_ab_low", (0, 0.16, -0.32), (0.52, 0.22, 0.22), mat=mat_armor)
    pelvis = create_box("body_pelvis", (0, 0.08, -0.48), (0.42, 0.36, 0.20), rot=(math.radians(-18), 0, 0), mat=mat_dark)
    
    # Transverse Pelvis Chassis / Hip Cross-Member (bridges waist to leg hips at X = ±0.53m, Z = -0.52m)
    pelvis_chassis = create_box("body_pelvis_chassis", (0, 0.0, -0.48), (1.12, 0.46, 0.28), mat=mat_dark)
    # Left & Right Articulated Hip Skirts
    skirt_l = create_box("body_skirt_l", (-0.56, 0.02, -0.48), (0.12, 0.50, 0.36), rot=(0, math.radians(-12), 0), mat=mat_armor)
    skirt_r = create_box("body_skirt_r", (0.56, 0.02, -0.48), (0.12, 0.50, 0.36), rot=(0, math.radians(12), 0), mat=mat_armor)
    objs.extend([ab_mid, ab_low, pelvis, pelvis_chassis, skirt_l, skirt_r])
    
    # 7. Rear Powerpack / Reactor Housing & Cowls
    reactor = create_box("body_reactor", (0, -0.36, 0.22), (0.76, 0.34, 0.72), mat=mat_dark)
    exhaust_l = create_box("body_exhaust_l", (-0.26, -0.48, 0.52), (0.16, 0.14, 0.22), rot=(math.radians(20), 0, 0), mat=mat_accent)
    exhaust_r = create_box("body_exhaust_r", (0.26, -0.48, 0.52), (0.16, 0.14, 0.22), rot=(math.radians(20), 0, 0), mat=mat_accent)
    objs.extend([reactor, exhaust_l, exhaust_r])
    
    body = join_objects(objs, "tankhead_body")
    apply_bevel_and_edgesplit(body, bevel_w=0.018)
    return body


def build_tankhead_arm_upper(mat_armor, mat_dark, mat_accent):
    """
    Arm Upper: Pivot at Shoulder (0, 0, 0).
    Extends DOWN along -Z to ~ -0.66m.
    Massive blocky shoulder pauldron with layered applique armor.
    """
    objs = []
    # Main Shoulder Pauldron Block
    pauldron = create_box("arm_pauldron", (0, 0, -0.12), (0.52, 0.52, 0.34), mat=mat_armor)
    objs.append(pauldron)
    
    # Inner Inset Flange (Bridges inward towards torso)
    inner_flange = create_box("arm_inner_flange", (0.16, 0, -0.06), (0.24, 0.44, 0.26), mat=mat_dark)
    objs.append(inner_flange)
    
    # Outer Applique Shoulder Armor Slab
    outer_slab = create_box("arm_outer_slab", (-0.28, 0, -0.12), (0.08, 0.48, 0.36), mat=mat_accent)
    objs.append(outer_slab)
    
    # Upper Arm Bicep Sleeve
    sleeve = create_box("arm_sleeve", (0, 0, -0.36), (0.34, 0.34, 0.38), mat=mat_dark)
    objs.append(sleeve)
    
    # Elbow Joint Cup
    elbow_cup = create_box("arm_elbow_cup", (0, -0.10, -0.58), (0.24, 0.16, 0.16), mat=mat_armor)
    objs.append(elbow_cup)
    
    arm_up = join_objects(objs, "tankhead_arm_left_upper")
    apply_bevel_and_edgesplit(arm_up, bevel_w=0.015)
    return arm_up


def build_tankhead_arm_lower(mat_armor, mat_dark, mat_accent):
    """
    Arm Lower: Pivot at Elbow (0, 0, 0).
    Extends DOWN along -Z to ~ -0.67m.
    Thick angular forearm casing with defensive side ridge and armored knuckle.
    """
    objs = []
    # Elbow Guard Cap
    elbow = create_box("arm_elbow", (0, -0.12, 0.02), (0.26, 0.18, 0.18), rot=(math.radians(20), 0, 0), mat=mat_dark)
    objs.append(elbow)
    
    # Main Forearm Casing
    forearm = create_box("arm_forearm", (0, 0.02, -0.28), (0.36, 0.38, 0.46), mat=mat_armor)
    objs.append(forearm)
    
    # Outer Defensive Shield Ridge
    ridge = create_box("arm_ridge", (-0.20, 0.02, -0.26), (0.10, 0.34, 0.42), mat=mat_accent)
    objs.append(ridge)
    
    # Armored Heavy Knuckle / Wrist Socket
    knuckle = create_box("arm_knuckle", (0, 0.06, -0.56), (0.26, 0.26, 0.22), mat=mat_dark)
    objs.append(knuckle)
    
    arm_lo = join_objects(objs, "tankhead_arm_left_lower")
    apply_bevel_and_edgesplit(arm_lo, bevel_w=0.015)
    return arm_lo


def build_tankhead_leg_upper(mat_armor, mat_dark, mat_accent):
    """
    Leg Upper: Pivot at Hip (0, 0, 0).
    Extends DOWN along -Z to ~ -0.75m.
    "Angular Blockylegs" — massive angular blocky thighs with heavy chamfered edges.
    """
    objs = []
    # Hip Joint Armor Socket
    hip_cap = create_box("leg_hip_cap", (0, 0, -0.08), (0.50, 0.50, 0.24), mat=mat_dark)
    objs.append(hip_cap)
    
    # Massive Angular Blocky Thigh Armor (Monolithic square slabs from concept art)
    thigh_block = create_box("leg_thigh_block", (0, 0.02, -0.42), (0.72, 0.68, 0.68), mat=mat_armor)
    objs.append(thigh_block)
    
    # Front Reactive Armor Slanted Plate
    front_plate = create_box("leg_front_plate", (0, 0.35, -0.40), (0.58, 0.10, 0.58), rot=(math.radians(-12), 0, 0), mat=mat_armor)
    objs.append(front_plate)
    
    # Outer Side Armor Slab
    side_plate = create_box("leg_side_plate", (-0.36, 0.02, -0.42), (0.08, 0.56, 0.60), mat=mat_dark)
    objs.append(side_plate)
    
    leg_up = join_objects(objs, "tankhead_leg_left_upper")
    apply_bevel_and_edgesplit(leg_up, bevel_w=0.022)
    return leg_up


def build_tankhead_leg_lower(mat_armor, mat_dark, mat_accent):
    """
    Leg Lower: Pivot at Knee (0, 0, 0).
    Extends DOWN along -Z to foot sole at ~ -1.16m.
    Angular knee guard, heavy angular shin shield with side vents, and blocky stabilizer tank foot.
    """
    objs = []
    # Angular Knee Deflector Plate
    knee = create_box("leg_knee", (0, 0.24, 0.06), (0.38, 0.22, 0.30), rot=(math.radians(-25), 0, 0), mat=mat_accent)
    objs.append(knee)
    
    # Knee Joint Core
    knee_core = create_box("leg_knee_core", (0, 0, 0.0), (0.42, 0.38, 0.24), mat=mat_dark)
    objs.append(knee_core)
    
    # Heavy Angular Front Shin Armor
    shin = create_box("leg_shin", (0, 0.08, -0.46), (0.54, 0.52, 0.74), mat=mat_armor)
    objs.append(shin)
    
    # Front Shin Armor Ridge
    shin_ridge = create_box("leg_shin_ridge", (0, 0.32, -0.42), (0.34, 0.12, 0.62), rot=(math.radians(-12), 0, 0), mat=mat_accent)
    objs.append(shin_ridge)
    
    # Rear Calf Armor Thruster Box
    calf = create_box("leg_calf", (0, -0.22, -0.46), (0.46, 0.26, 0.56), mat=mat_dark)
    objs.append(calf)
    
    # Ankle Cuff
    cuff = create_box("leg_cuff", (0, 0, -0.88), (0.46, 0.46, 0.20), mat=mat_dark)
    objs.append(cuff)
    
    # Heavy Blocky Stabilizer Tank Foot with Track Treads
    foot_heel = create_box("leg_foot_heel", (0, -0.16, -1.05), (0.46, 0.34, 0.20), mat=mat_dark)
    foot_main = create_box("leg_foot_main", (0, 0.16, -1.05), (0.50, 0.46, 0.22), mat=mat_armor)
    foot_claw = create_box("leg_foot_claw", (0, 0.38, -1.06), (0.42, 0.16, 0.16), rot=(math.radians(-18), 0, 0), mat=mat_accent)
    # Tank-tread sole ribs
    tread_1 = create_box("leg_tread_1", (0, 0.30, -1.15), (0.52, 0.06, 0.03), mat=mat_dark)
    tread_2 = create_box("leg_tread_2", (0, 0.10, -1.15), (0.52, 0.06, 0.03), mat=mat_dark)
    tread_3 = create_box("leg_tread_3", (0, -0.10, -1.15), (0.52, 0.06, 0.03), mat=mat_dark)
    tread_4 = create_box("leg_tread_4", (0, -0.28, -1.15), (0.52, 0.06, 0.03), mat=mat_dark)
    objs.extend([foot_heel, foot_main, foot_claw, tread_1, tread_2, tread_3, tread_4])
    
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
