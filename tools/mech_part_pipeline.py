"""
Pipeline to extract, align, clean, scale, and export modular mech parts from Mech_00 FBX to Godot GLB parts.
Compatible with Godot 4.6.2 and Godot_Project_rogue_mech PartMeshManager convention.
"""
import bpy
import os
import math
import mathutils

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_part_export(fbx_path, ref_glb_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    # 1. Inspect Reference Inner Frame Joints
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=ref_glb_path)
    ref_joints = {}
    for obj in bpy.context.scene.objects:
        if obj.name.startswith("JNT_"):
            ref_joints[obj.name] = obj.matrix_world.translation.copy()
    print("Loaded reference joints:", ref_joints)

    # Reference joint positions in Godot coords (Y-up, Z-forward, in meters):
    # JNT_Head: (0.0, 0.0, 2.55) -> (0, 2.55, 0) in Godot
    # JNT_Body: (0.0, 0.0, 1.80)
    # JNT_ArmLeft: (-0.75, 0.0, 2.20)
    # JNT_ForearmLeft: (-0.75, 0.0, 1.82)
    # JNT_LegLeft: (-0.38, 0.0, 1.30)
    # JNT_ShinLeft: (-0.38, 0.0, 0.75)

    # 2. Extract Parts from Mech_00 FBX
    # We will build modular armor packs:
    # Pack S (Light / Scout), Pack M (Standard / Line), Pack L (Heavy / Vanguard)
    
    packs = {
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

    # Execute conversion for all packs
    for pack_key, parts_dict in packs.items():
        print(f"=== Processing Pack: {pack_key} ===")
        for slot_type, mesh_names in parts_dict.items():
            export_single_slot(fbx_path, pack_key, slot_type, mesh_names, output_dir)

def export_single_slot(fbx_path, pack_key, slot_type, mesh_names, output_dir):
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    
    armature = bpy.data.objects.get("Char_Mech")
    
    # Calculate bone head positions in world space (FBX scale: units are ~cm / 100)
    # Target bone anchors:
    bone_anchors = {
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
    
    target_bone_name = bone_anchors[slot_type]
    bone = armature.data.bones.get(target_bone_name)
    
    # World matrix of the target bone head
    bone_world_matrix = armature.matrix_world @ mathutils.Matrix.Translation(bone.head_local)
    bone_world_pos = bone_world_matrix.to_translation()
    
    # Separate and gather target mesh objects
    selected_meshes = []
    
    # In FBX, meshes might have modifiers or symmetry (L/R)
    # If right side is requested for arm/leg, we filter or bisect
    is_left = "left" in slot_type or slot_type in ["head", "body"]
    is_right = "right" in slot_type
    
    for name in mesh_names:
        obj = bpy.data.objects.get(name)
        if not obj:
            continue
            
        # Duplicate mesh so we don't destroy original
        new_obj = obj.copy()
        new_obj.data = obj.data.copy()
        bpy.context.collection.objects.link(new_obj)
        
        # Apply armature modifier if needed or apply transform
        # For FBX skinned parts, apply visual transform
        bpy.context.view_layer.objects.active = new_obj
        new_obj.select_set(True)
        
        # Unparent and keep transform
        matrixcopy = new_obj.matrix_world.copy()
        new_obj.parent = None
        new_obj.matrix_world = matrixcopy
        
        # If object contains both left and right (e.g. Arms, Thighs, Legs), bisect at X=0
        if is_left and not is_right and ("arm" in slot_type or "leg" in slot_type):
            if not (".L" in name or ".R" in name):
                # Cut and keep X > 0 in Blender space (Left side is positive X in this armature)
                bisect_mesh(new_obj, keep_positive_x=True)
        elif is_right and ("arm" in slot_type or "leg" in slot_type):
            if not (".L" in name or ".R" in name):
                # Cut and keep X < 0 in Blender space (Right side is negative X)
                bisect_mesh(new_obj, keep_positive_x=False)
                
        selected_meshes.append(new_obj)
        
    if not selected_meshes:
        print(f"Warning: No meshes found for {pack_key} {slot_type}")
        return

    # Join all meshes for this slot into one
    clear_selection()
    for o in selected_meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = selected_meshes[0]
    bpy.ops.object.join()
    joined_obj = bpy.context.view_layer.objects.active
    
    # Clean up other objects
    for o in list(bpy.context.scene.objects):
        if o != joined_obj:
            bpy.data.objects.remove(o, do_unlink=True)
            
    # Apply all transforms
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # 3. Pivot Alignment & Scaling
    # Move object so that target bone head is at (0, 0, 0)
    joined_obj.location = -bone_world_pos
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    
    # Scale: Mech_00 FBX height is ~355 cm (3.55m). Godot True height is 4.73m.
    # Scale factor = 4.73 / 3.55 ~= 1.3324 * 0.01 (cm to m) = ~0.013324
    # Let's inspect FBX world units: bone.head_local was ~353.0 units for head.
    # In meters: 353 units = 3.53m. So scale = 4.73 / 3.53 = 1.34 / 100 = 0.0134
    scale_factor = (4.73 / 3.53) * 0.01
    joined_obj.scale = (scale_factor, scale_factor, scale_factor)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    
    # Orientation: Ensure Forward is -Z, Up is +Y (Blender is Z-up, Y-forward)
    # Rotate -90 on X so Z-up becomes Y-up
    joined_obj.rotation_euler = (math.radians(-90), 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    
    # Hard-surface Polish: Shade Flat / Auto Smooth & Edge Split
    for poly in joined_obj.data.polygons:
        poly.use_smooth = False
    
    mod = joined_obj.modifiers.new(name="EdgeSplit", type='EDGE_SPLIT')
    mod.split_angle = math.radians(32)
    bpy.ops.object.modifier_apply(modifier="EdgeSplit")
    
    # Recalculate Normals Outside
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Slot Folder mapping
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
    
    target_slot = slot_folder_map[slot_type]
    slot_dir = os.path.join(output_dir, target_slot)
    os.makedirs(slot_dir, exist_ok=True)
    
    filename = f"{pack_key}_{slot_type}.glb"
    export_path = os.path.join(slot_dir, filename)
    
    # Export GLB
    bpy.ops.export_scene.gltf(
        filepath=export_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True
    )
    print(f"Exported: {export_path}")

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

def clear_selection():
    for o in bpy.context.selected_objects:
        o.select_set(False)

if __name__ == "__main__":
    fbx_file = r"c:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/download/Mech_00/Char_Mesh/Mech_Char_Mesh.fbx"
    ref_glb = r"c:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/exports/procedural_innerframe_local.glb"
    out_dir = r"c:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/scenes/mecha/parts"
    setup_part_export(fbx_file, ref_glb, out_dir)
