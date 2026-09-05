"""
Generates the "Hero3 Vanguard" modular armor pack for Godot_Project_rogue_mech.
Modeled on concept art: tank-angular-blockylegs_00003_.png (hero: yellow visor,
red chest light, antenna fin, column blocky legs, blocky feet).

Blender coordinates (same convention as generate_tankhead_pack.py):
    +X: Right, -X: Left
    +Y: Forward (maps to Godot -Z Forward)
    -Y: Back (maps to Godot +Z Back)
    +Z: Up (maps to Godot +Y Up)
All parts apply location so mesh origin is (0,0,0) matching Godot joint pivots.
"""

import bpy
import os
import math

BASE_DIR = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
PARTS_DIR = os.path.join(BASE_DIR, "scenes", "mecha", "parts")


def get_materials():
    mat_armor = bpy.data.materials.new("Hero3_Armor")
    mat_armor.use_nodes = True
    bsdf = mat_armor.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.82, 0.81, 0.79, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.12
    bsdf.inputs["Roughness"].default_value = 0.58

    mat_dark = bpy.data.materials.new("Hero3_Dark")
    mat_dark.use_nodes = True
    bsdf2 = mat_dark.node_tree.nodes["Principled BSDF"]
    bsdf2.inputs["Base Color"].default_value = (0.25, 0.26, 0.29, 1.0)
    bsdf2.inputs["Metallic"].default_value = 0.35
    bsdf2.inputs["Roughness"].default_value = 0.65

    mat_visor = bpy.data.materials.new("Hero3_Visor")
    mat_visor.use_nodes = True
    bsdf3 = mat_visor.node_tree.nodes["Principled BSDF"]
    bsdf3.inputs["Base Color"].default_value = (0.78, 1.0, 0.22, 1.0)
    bsdf3.inputs["Metallic"].default_value = 0.10
    bsdf3.inputs["Roughness"].default_value = 0.30
    bsdf3.inputs["Emission Color"].default_value = (0.78, 1.0, 0.22, 1.0)
    bsdf3.inputs["Emission Strength"].default_value = 2.5

    mat_red = bpy.data.materials.new("Hero3_Red")
    mat_red.use_nodes = True
    bsdf4 = mat_red.node_tree.nodes["Principled BSDF"]
    bsdf4.inputs["Base Color"].default_value = (1.0, 0.16, 0.10, 1.0)
    bsdf4.inputs["Metallic"].default_value = 0.10
    bsdf4.inputs["Roughness"].default_value = 0.35
    bsdf4.inputs["Emission Color"].default_value = (1.0, 0.16, 0.10, 1.0)
    bsdf4.inputs["Emission Strength"].default_value = 2.0

    return mat_armor, mat_dark, mat_visor, mat_red


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
    main.location = (0, 0, 0)
    return main


def mirror_part_x(obj, name):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.duplicate()
    mir = bpy.context.view_layer.objects.active
    mir.name = name

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
# BUILDERS FOR HERO3 VANGUARD ARMOR (pivot-local, +Y = forward)
# ==============================================================================

def build_head(M):
    ma, md, mv, mr = M
    o = []
    o.append(create_box("h_dome", (0, 0.02, 0.08), (0.58, 0.52, 0.40), mat=ma))
    o.append(create_box("h_brow", (0, 0.24, 0.16), (0.50, 0.16, 0.14),
                        rot=(math.radians(-20), 0, 0), mat=ma))
    o.append(create_box("h_visor", (0, 0.285, 0.06), (0.36, 0.05, 0.09), mat=mv))
    o.append(create_box("h_cheek_l", (-0.30, 0.04, 0.02), (0.12, 0.44, 0.30), mat=ma))
    o.append(create_box("h_cheek_r", (0.30, 0.04, 0.02), (0.12, 0.44, 0.30), mat=ma))
    o.append(create_box("h_chin", (0, 0.22, -0.14), (0.34, 0.20, 0.18), mat=md))
    o.append(create_box("h_back", (0, -0.24, 0.06), (0.52, 0.16, 0.34), mat=ma))
    o.append(create_box("h_collar", (0, 0.0, -0.20), (0.50, 0.50, 0.16), mat=md))
    o.append(create_box("h_fin_r", (0.20, -0.04, 0.32), (0.05, 0.18, 0.36),
                        rot=(0, math.radians(12), 0), mat=ma))
    o.append(create_box("h_fin_tip", (0.20, 0.03, 0.44), (0.055, 0.10, 0.08),
                        rot=(0, math.radians(12), 0), mat=mv))
    o.append(create_box("h_antenna_l", (-0.20, 0.02, 0.30), (0.025, 0.025, 0.45), mat=md))
    head = join_objects(o, "hero3_head")
    apply_bevel_and_edgesplit(head, bevel_w=0.014)
    return head


def build_body(M):
    ma, md, mv, mr = M
    o = []
    o.append(create_box("b_torso", (0, 0, 0.02), (1.30, 0.92, 1.30), mat=ma))
    o.append(create_box("b_chest", (0, 0.30, 0.42), (1.20, 0.30, 0.55),
                        rot=(math.radians(-18), 0, 0), mat=ma))
    o.append(create_box("b_slab_l", (-0.36, 0.40, 0.44), (0.34, 0.14, 0.32),
                        rot=(math.radians(-18), 0, 0), mat=ma))
    o.append(create_box("b_slab_r", (0.36, 0.40, 0.44), (0.34, 0.14, 0.32),
                        rot=(math.radians(-18), 0, 0), mat=ma))
    o.append(create_box("b_redlight", (-0.48, 0.47, 0.05), (0.13, 0.04, 0.18), mat=mr))
    o.append(create_box("b_collar_l", (-0.38, 0.02, 0.72), (0.16, 0.52, 0.30), mat=ma))
    o.append(create_box("b_collar_r", (0.38, 0.02, 0.72), (0.16, 0.52, 0.30), mat=ma))
    o.append(create_box("b_collar_b", (0, -0.24, 0.74), (0.72, 0.16, 0.30), mat=ma))
    o.append(create_box("b_side_l", (-0.70, 0, 0.10), (0.36, 0.60, 0.70), mat=md))
    o.append(create_box("b_side_r", (0.70, 0, 0.10), (0.36, 0.60, 0.70), mat=md))
    o.append(create_box("b_ab", (0, 0.16, -0.55), (0.62, 0.30, 0.40), mat=ma))
    o.append(create_box("b_pelvis", (0, 0, -0.72), (1.20, 0.52, 0.30), mat=md))
    o.append(create_box("b_skirt_l", (-0.60, 0.02, -0.72), (0.16, 0.54, 0.36),
                        rot=(0, math.radians(-10), 0), mat=ma))
    o.append(create_box("b_skirt_r", (0.60, 0.02, -0.72), (0.16, 0.54, 0.36),
                        rot=(0, math.radians(10), 0), mat=ma))
    o.append(create_box("b_pack", (0, -0.56, 0.15), (1.00, 0.34, 0.72), mat=md))
    o.append(create_box("b_exh_l", (-0.28, -0.68, 0.42), (0.18, 0.14, 0.22),
                        rot=(math.radians(15), 0, 0), mat=mv))
    o.append(create_box("b_exh_r", (0.28, -0.68, 0.42), (0.18, 0.14, 0.22),
                        rot=(math.radians(15), 0, 0), mat=mv))
    body = join_objects(o, "hero3_body")
    apply_bevel_and_edgesplit(body, bevel_w=0.018)
    return body


def build_arm_upper(M):
    ma, md, mv, mr = M
    o = []
    o.append(create_box("au_pauldron", (0, 0, 0.02), (0.58, 0.58, 0.38), mat=ma))
    o.append(create_box("au_top", (0, 0, 0.24), (0.44, 0.44, 0.12), mat=ma))
    o.append(create_box("au_inner", (0.18, 0, 0.0), (0.24, 0.46, 0.26), mat=md))
    o.append(create_box("au_outer", (-0.30, 0, 0.02), (0.10, 0.50, 0.36), mat=ma))
    o.append(create_box("au_sleeve", (0, 0, -0.38), (0.36, 0.36, 0.38), mat=md))
    o.append(create_box("au_elbowcup", (0, -0.08, -0.60), (0.26, 0.18, 0.16), mat=ma))
    arm = join_objects(o, "hero3_arm_left_upper")
    apply_bevel_and_edgesplit(arm, bevel_w=0.015)
    return arm


def build_arm_lower(M):
    ma, md, mv, mr = M
    o = []
    o.append(create_box("al_elbow", (0, -0.10, 0.0), (0.28, 0.20, 0.20),
                        rot=(math.radians(20), 0, 0), mat=md))
    o.append(create_box("al_fore", (0, 0.02, -0.28), (0.38, 0.40, 0.46), mat=ma))
    o.append(create_box("al_ridge", (-0.21, 0.02, -0.26), (0.12, 0.36, 0.42), mat=ma))
    o.append(create_box("al_knuckle", (0, 0.05, -0.55), (0.27, 0.27, 0.22), mat=md))
    arm = join_objects(o, "hero3_arm_left_lower")
    apply_bevel_and_edgesplit(arm, bevel_w=0.015)
    return arm


def build_leg_upper(M):
    ma, md, mv, mr = M
    o = []
    o.append(create_box("lu_hip", (0, 0, -0.06), (0.60, 0.60, 0.24), mat=md))
    o.append(create_box("lu_thigh", (0, 0.02, -0.46), (0.72, 0.78, 0.80), mat=ma))
    o.append(create_box("lu_front", (0, 0.42, -0.44), (0.62, 0.14, 0.66),
                        rot=(math.radians(-8), 0, 0), mat=ma))
    o.append(create_box("lu_inner", (0.36, 0.02, -0.46), (0.24, 0.64, 0.70), mat=md))
    o.append(create_box("lu_side", (-0.40, 0.02, -0.46), (0.14, 0.68, 0.72), mat=md))
    leg = join_objects(o, "hero3_leg_left_upper")
    apply_bevel_and_edgesplit(leg, bevel_w=0.022)
    return leg


def build_leg_lower(M):
    ma, md, mv, mr = M
    o = []
    o.append(create_box("ll_knee", (0, 0.30, 0.02), (0.56, 0.28, 0.40),
                        rot=(math.radians(-20), 0, 0), mat=ma))
    o.append(create_box("ll_kneecore", (0, 0, -0.02), (0.50, 0.46, 0.26), mat=md))
    o.append(create_box("ll_shin", (0, 0.08, -0.55), (0.62, 0.66, 0.75), mat=ma))
    o.append(create_box("ll_ridge", (0, 0.42, -0.52), (0.44, 0.18, 0.62),
                        rot=(math.radians(-10), 0, 0), mat=ma))
    o.append(create_box("ll_calf", (0, -0.30, -0.55), (0.54, 0.30, 0.60), mat=md))
    o.append(create_box("ll_cuff", (0, 0, -0.96), (0.56, 0.56, 0.22), mat=md))
    o.append(create_box("ll_foot", (0, 0.16, -1.12), (0.58, 0.62, 0.24), mat=ma))
    o.append(create_box("ll_heel", (0, -0.24, -1.12), (0.54, 0.30, 0.24), mat=md))
    o.append(create_box("ll_toe", (0, 0.48, -1.10), (0.50, 0.14, 0.20),
                        rot=(math.radians(-15), 0, 0), mat=ma))
    leg = join_objects(o, "hero3_leg_left_lower")
    apply_bevel_and_edgesplit(leg, bevel_w=0.020)
    return leg


def fresh_materials():
    clean_scene()
    return get_materials()


def generate_all():
    print("=== Generating Hero3 Vanguard Pack ===")

    M = fresh_materials()
    export_glb(build_head(M), os.path.join(PARTS_DIR, "head", "hero3_head.glb"))

    M = fresh_materials()
    export_glb(build_body(M), os.path.join(PARTS_DIR, "body", "hero3_body.glb"))

    M = fresh_materials()
    export_glb(build_arm_upper(M), os.path.join(PARTS_DIR, "arm_left", "hero3_arm_left_upper.glb"))

    M = fresh_materials()
    export_glb(build_arm_lower(M), os.path.join(PARTS_DIR, "arm_left", "hero3_arm_left_lower.glb"))

    M = fresh_materials()
    arm_r_up = mirror_part_x(build_arm_upper(M), "hero3_arm_right_upper")
    export_glb(arm_r_up, os.path.join(PARTS_DIR, "arm_right", "hero3_arm_right_upper.glb"))

    M = fresh_materials()
    arm_r_lo = mirror_part_x(build_arm_lower(M), "hero3_arm_right_lower")
    export_glb(arm_r_lo, os.path.join(PARTS_DIR, "arm_right", "hero3_arm_right_lower.glb"))

    M = fresh_materials()
    export_glb(build_leg_upper(M), os.path.join(PARTS_DIR, "leg_left", "hero3_leg_left_upper.glb"))

    M = fresh_materials()
    export_glb(build_leg_lower(M), os.path.join(PARTS_DIR, "leg_left", "hero3_leg_left_lower.glb"))

    M = fresh_materials()
    leg_r_up = mirror_part_x(build_leg_upper(M), "hero3_leg_right_upper")
    export_glb(leg_r_up, os.path.join(PARTS_DIR, "leg_right", "hero3_leg_right_upper.glb"))

    M = fresh_materials()
    leg_r_lo = mirror_part_x(build_leg_lower(M), "hero3_leg_right_lower")
    export_glb(leg_r_lo, os.path.join(PARTS_DIR, "leg_right", "hero3_leg_right_lower.glb"))

    print("=== All Hero3 Vanguard parts generated successfully! ===")


if __name__ == "__main__":
    generate_all()
