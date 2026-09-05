"""
Robust pipeline to extract and orient modular armor parts from Mech_00 FBX to match
Godot_Project_rogue_mech's PartMeshManager and Procedural Inner Frame.

Rules:
1. Clear all Blender default scene objects (no default Cube/Camera/Light).
2. Orientation in Godot:
   - Forward: -Z, Up: +Y
   - For Head: Center at neck/eye level (0, 0, 0)
   - For Body: Center at spine core (0, 0, 0)
   - For Upper Arm: Pivot at Shoulder (0, 0, 0), extends DOWN along -Y axis
   - For Lower Arm: Pivot at Elbow (0, 0, 0), extends DOWN along -Y axis
   - For Upper Leg: Pivot at Hip (0, 0, 0), extends DOWN along -Y axis
   - For Lower Leg: Pivot at Knee (0, 0, 0), extends DOWN along -Y axis
3. Scale:
   In part_mesh_manager.gd:
   Container scale = WORLD_SCALE (1.68).
   Custom mesh instantiation scales by INV_WORLD_SCALE (1/1.68).
   To perfectly envelope the procedural frame, the authored GLB dimensions must be
   matching the true meter frame with ~1.15x armor casing factor.
"""

import bpy
import os
import math
import mathutils

BASE_DIR = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
FBX_PATH = os.path.join(BASE_DIR, "download", "Mech_00", "Char_Mesh", "Mech_Char_Mesh.fbx")
OUTPUT_DIR = os.path.join(BASE_DIR, "scenes", "mecha", "parts")

PACK_DEFS = {
    "scout": {
        "head": ["Core_Head"],
        "body": ["Base_S_Torso", "Base_S_Pelvis", "Core_Neck", "Core_NeckJoint", "Core_BackJoint"],
        "arm_left_upper": ["Base_S_Shoulder", "Base_S_Arm", "Core_ShoulderJoint"],
        "arm_left_lower": ["Base_S_Forearm.L", "Core_Elbow", "Core_Palm.L"],
        "arm_right_upper": ["Base_S_Shoulder", "Base_S_Arm", "Core_ShoulderJoint"],
        "arm_right_lower": ["Base_S_Forearm.R", "Core_Elbow", "Core_Palm.R"],
        "leg_left_upper": ["Base_S_Thigh", "Core_ThighJoint"],
        "leg_left_lower": ["Base_S_Leg", "Core_Knee", "Core_Feet"],
        "leg_right_upper": ["Base_S_Thigh", "Core_ThighJoint"],
        "leg_right_lower": ["Base_S_Leg", "Core_Knee", "Core_Feet"],
    },
    "line": {
        "head": ["Core_Head"],
        "body": ["Base_M_Torso", "Base_M_Pelvis", "Core_Neck", "Core_NeckJoint", "Core_BackJoint"],
        "arm_left_upper": ["Base_M_Shoulder", "Base_M_Arm", "Core_ShoulderJoint"],
        "arm_left_lower": ["Base_M_Forearm.L", "Core_Elbow", "Core_Palm.L"],
        "arm_right_upper": ["Base_M_Shoulder", "Base_M_Arm", "Core_ShoulderJoint"],
        "arm_right_lower": ["Base_M_Forearm.R", "Core_Elbow", "Core_Palm.R"],
        "leg_left_upper": ["Base_M_Thigh", "Core_ThighJoint"],
        "leg_left_lower": ["Base_M_Leg", "Core_Knee", "Core_Feet"],
        "leg_right_upper": ["Base_M_Thigh", "Core_ThighJoint"],
        "leg_right_lower": ["Base_M_Leg", "Core_Knee", "Core_Feet"],
    },
    "vanguard": {
        "head": ["Core_Head"],
        "body": ["Base_L_Torso", "Base_L_Pelvis", "Core_Neck", "Core_NeckJoint", "Core_BackJoint"],
        "arm_left_upper": ["Base_L_Shoulder", "Base_L_Arm", "Core_ShoulderJoint"],
        "arm_left_lower": ["Base_L_Forearm.L", "Base_L_LimbGun.L", "Core_Elbow", "Core_Palm.L"],
        "arm_right_upper": ["Base_L_Shoulder", "Base_L_Arm", "Core_ShoulderJoint"],
        "arm_right_lower": ["Base_L_Forearm.R", "Base_L_LimbGun.R", "Core_Elbow", "Core_Palm.R"],
        "leg_left_upper": ["Base_L_Thigh", "Core_ThighJoint"],
        "leg_left_lower": ["Base_L_Leg", "Core_Knee", "Core_Feet"],
        "leg_right_upper": ["Base_L_Thigh", "Core_ThighJoint"],
        "leg_right_lower": ["Base_L_Leg", "Core_Knee", "Core_Feet"],
    }
}

def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)

def bisect_mesh(obj, keep_positive_x=True):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.bisect(
        plane_co=(0, 0, 0),
        plane_no=(1, 0, 0),
        clear_inner=not keep_positive_x,
        clear_outer=keep_positive_x
    )
    bpy.ops.object.mode_set(mode='OBJECT')

def process_and_export_part(pack_key, part_type, mesh_names):
    clean_scene()
    bpy.ops.import_scene.fbx(filepath=FBX_PATH)
    
    armature = bpy.data.objects.get("Char_Mech")
    
    # 1. Target bone head position in FBX space
    bone_targets = {
        "head": "head.x",
        "body": "spine_01.x",
        "arm_left_upper": "shoulder.l",
        "arm_left_lower": "forearm_stretch.l",
        "arm_right_upper": "shoulder.r",
        "arm_right_lower": "forearm_stretch.r",
        "leg_left_upper": "thigh_stretch.l",
        "leg_left_lower": "leg_stretch.l",
        "leg_right_upper": "thigh_stretch.r",
        "leg_right_lower": "leg_stretch.r",
    }
    
    bone_name = bone_targets[part_type]
    pose_bone = armature.pose.bones.get(bone_name)
    bone_pivot = (armature.matrix_world @ pose_bone.head).copy()
    
    is_left = "left" in part_type
    is_right = "right" in part_type
    
    extracted_meshes = []
    
    for mname in mesh_names:
        o = bpy.data.objects.get(mname)
        if not o or o.type != 'MESH':
            continue
            
        dup = o.copy()
        dup.data = o.data.copy()
        bpy.context.collection.objects.link(dup)
        
        # Bake transform
        mat = dup.matrix_world.copy()
        dup.parent = None
        dup.matrix_world = mat
        
        # Symmetric meshes (Arm, Thigh, Leg, Shoulder) need bisecting
        if is_left and not (".L" in mname or ".R" in mname):
            # Left side is positive X in FBX
            bisect_mesh(dup, keep_positive_x=True)
        elif is_right and not (".L" in mname or ".R" in mname):
            # Right side is negative X in FBX
            bisect_mesh(dup, keep_positive_x=False)
            
        extracted_meshes.append(dup)
        
    if not extracted_meshes:
        print(f"ERROR: No mesh found for {pack_key} {part_type}")
        return

    # Delete all other objects (including armature and unused meshes)
    for o in list(bpy.context.scene.objects):
        if o not in extracted_meshes:
            bpy.data.objects.remove(o, do_unlink=True)
            
    # Join extracted meshes
    bpy.ops.object.select_all(action='DESELECT')
    for o in extracted_meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = extracted_meshes[0]
    bpy.ops.object.join()
    main_obj = bpy.context.view_layer.objects.active
    
    # 2. Apply all transforms
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # 3. Pivot Alignment: Move object so bone_pivot is at (0, 0, 0)
    main_obj.location = -bone_pivot
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    
    # 4. Orient to Godot coordinate system and limb extension
    # FBX space: T-pose has arms stretching along X axis (+X for Left, -X for Right).
    # Legs stretch down along Z axis (FBX is Z-up in Blender import).
    # Godot space:
    # Upper/Lower limbs must extend DOWN along -Y axis.
    # Forward is -Z, Up is +Y.
    
    if "arm_left" in part_type:
        # Arm extends +X in FBX.
        # We need it to rotate so that +X becomes -Y (down) in Godot.
        # In Blender (Z-up), rotation around Y by -90: +X becomes -Z.
        # Let's rotate so arm points DOWN along -Z in Blender, then rotate Blender Z-up to Godot Y-up.
        # Specifically: Rotate around Y by -90 deg -> +X becomes -Z (down).
        main_obj.rotation_euler = (0, math.radians(-90), 0)
        bpy.ops.object.transform_apply(rotation=True)
        # Then rotate around X by -90 to convert Blender Z-up to Godot Y-up:
        main_obj.rotation_euler = (math.radians(-90), 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        
    elif "arm_right" in part_type:
        # Arm extends -X in FBX.
        # Rotate around Y by +90 deg -> -X becomes -Z (down).
        main_obj.rotation_euler = (0, math.radians(90), 0)
        bpy.ops.object.transform_apply(rotation=True)
        # Convert Blender Z-up to Godot Y-up:
        main_obj.rotation_euler = (math.radians(-90), 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        
    elif "leg" in part_type:
        # Legs extend down along -Z in FBX.
        # Just convert Blender Z-up to Godot Y-up:
        # Rot X -90 makes -Z become -Y (down)!
        main_obj.rotation_euler = (math.radians(-90), 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        
    elif "head" in part_type or "body" in part_type:
        # Convert Blender Z-up to Godot Y-up:
        main_obj.rotation_euler = (math.radians(-90), 0, 0)
        bpy.ops.object.transform_apply(rotation=True)

    # 5. Scale Adjustment
    # The FBX character height is ~3.55m. Godot True Height is ~4.86m.
    # Scale factor = 4.86 / 3.55 = ~1.37
    # Furthermore, armor casing should be ~1.15x frame thickness to envelop inner frame.
    # Total scale = 1.37 * 1.15 = ~1.575
    target_scale = 1.55
    main_obj.scale = (target_scale, target_scale, target_scale)
    bpy.ops.object.transform_apply(scale=True)
    
    # 6. Hard-surface Shading & Edge Split
    for poly in main_obj.data.polygons:
        poly.use_smooth = False
        
    mod = main_obj.modifiers.new(name="EdgeSplit", type='EDGE_SPLIT')
    mod.split_angle = math.radians(30)
    bpy.ops.object.modifier_apply(modifier="EdgeSplit")
    
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')

    # 7. Slot folder mapping & Export
    slot_folder_map = {
        "head": "head",
        "body": "body",
        "arm_left_upper": "arm_left",
        "arm_left_lower": "arm_left",
        "arm_right_upper": "arm_right",
        "arm_right_lower": "arm_right",
        "leg_left_upper": "leg_left",
        "leg_left_lower": "leg_left",
        "leg_right_upper": "leg_right",
        "leg_right_lower": "leg_right",
    }
    target_folder = os.path.join(OUTPUT_DIR, slot_folder_map[part_type])
    os.makedirs(target_folder, exist_ok=True)
    
    export_path = os.path.join(target_folder, f"{pack_key}_{part_type}.glb")
    
    bpy.ops.export_scene.gltf(
        filepath=export_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True
    )
    print(f"SUCCESS: Exported {export_path} | Dims: {main_obj.dimensions}")

def run():
    for pack_key, parts_dict in PACK_DEFS.items():
        print(f"Processing pack: {pack_key}")
        for part_type, mesh_names in parts_dict.items():
            process_and_export_part(pack_key, part_type, mesh_names)

if __name__ == "__main__":
    run()
