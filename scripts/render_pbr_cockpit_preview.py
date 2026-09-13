import bpy
import math
import os

# Clean slate
bpy.ops.wm.read_factory_settings(use_empty=True)

glb_path = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech\assets\models\mech_cockpit_tub.glb"
bpy.ops.import_scene.gltf(filepath=glb_path)

# PBR Textures from Poly Haven
tex_dir = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech\resources\textures\mech\pbr"
diff_path = os.path.join(tex_dir, "metal_plate_diff.png")
nor_path = os.path.join(tex_dir, "metal_plate_nor_gl.png")
rough_path = os.path.join(tex_dir, "metal_plate_rough.png")

def create_polyhaven_pbr_mat(name, tint_color=(0.88, 0.86, 0.82, 1.0), metallic=0.15):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    # Output node
    node_out = nodes.new(type='ShaderNodeOutputMaterial')
    node_out.location = (600, 0)

    # Principled BSDF
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (250, 0)
    bsdf.inputs['Metallic'].default_value = metallic

    links.new(bsdf.outputs['BSDF'], node_out.inputs['Surface'])

    # Mapping & TexCoord
    tex_coord = nodes.new(type='ShaderNodeTexCoord')
    tex_coord.location = (-600, 0)

    mapping = nodes.new(type='ShaderNodeMapping')
    mapping.location = (-400, 0)
    mapping.inputs['Scale'].default_value = (3.0, 3.0, 3.0)
    links.new(tex_coord.outputs['Object'], mapping.inputs['Vector'])

    # Diffuse / Albedo
    if os.path.exists(diff_path):
        img_diff = bpy.data.images.load(diff_path)
        node_diff = nodes.new(type='ShaderNodeTexImage')
        node_diff.image = img_diff
        node_diff.location = (-150, 200)
        links.new(mapping.outputs['Vector'], node_diff.inputs['Vector'])

        # Color tint multiply
        node_mix = nodes.new(type='ShaderNodeMix')
        node_mix.data_type = 'RGBA'
        node_mix.blend_type = 'MULTIPLY'
        node_mix.inputs['Factor'].default_value = 0.85
        node_mix.inputs[6].default_value = tint_color
        node_mix.location = (50, 200)
        links.new(node_diff.outputs['Color'], node_mix.inputs[7])
        links.new(node_mix.outputs[2], bsdf.inputs['Base Color'])
    else:
        bsdf.inputs['Base Color'].default_value = tint_color

    # Roughness
    if os.path.exists(rough_path):
        img_rough = bpy.data.images.load(rough_path)
        img_rough.colorspace_settings.name = 'Non-Color'
        node_rough = nodes.new(type='ShaderNodeTexImage')
        node_rough.image = img_rough
        node_rough.location = (-150, -50)
        links.new(mapping.outputs['Vector'], node_rough.inputs['Vector'])
        links.new(node_rough.outputs['Color'], bsdf.inputs['Roughness'])

    # Normal Map
    if os.path.exists(nor_path):
        img_nor = bpy.data.images.load(nor_path)
        img_nor.colorspace_settings.name = 'Non-Color'
        node_nor_tex = nodes.new(type='ShaderNodeTexImage')
        node_nor_tex.image = img_nor
        node_nor_tex.location = (-150, -300)
        links.new(mapping.outputs['Vector'], node_nor_tex.inputs['Vector'])

        node_norm_map = nodes.new(type='ShaderNodeNormalMap')
        node_norm_map.inputs['Strength'].default_value = 0.75
        node_norm_map.location = (50, -300)
        links.new(node_nor_tex.outputs['Color'], node_norm_map.inputs['Color'])
        links.new(node_norm_map.outputs['Normal'], bsdf.inputs['Normal'])

    return mat

mat_pbr_armor = create_polyhaven_pbr_mat("PBR_MechaArmor_White", (0.85, 0.84, 0.82, 1.0), metallic=0.08)
mat_pbr_frame = create_polyhaven_pbr_mat("PBR_MechaFrame_Dark", (0.16, 0.17, 0.20, 1.0), metallic=0.35)

# Assign PBR materials across imported objects
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        name_l = obj.name.lower()
        if any(w in name_l for w in ["cowl", "lip", "roof", "armor", "ab_plate", "chest"]):
            obj.data.materials.clear()
            obj.data.materials.append(mat_pbr_armor)
        elif any(w in name_l for w in ["spine", "bulkhead", "wall", "floor", "waist", "arch", "yaw"]):
            obj.data.materials.clear()
            obj.data.materials.append(mat_pbr_frame)

# Studio World & Environment
world = bpy.data.worlds.new("StudioWorld")
bpy.context.scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
if bg:
    bg.inputs["Color"].default_value = (0.07, 0.08, 0.10, 1.0)

# Key Light
bpy.ops.object.light_add(type='SUN', location=(3.0, 3.5, 4.0))
sun = bpy.context.active_object
sun.data.energy = 5.0
sun.rotation_euler = (math.radians(35), math.radians(20), math.radians(-35))

# Fill Light
bpy.ops.object.light_add(type='AREA', location=(-2.5, 1.5, 2.5))
fill = bpy.context.active_object
fill.data.energy = 350.0
fill.data.size = 3.0

# Rim Light from above-rear
bpy.ops.object.light_add(type='POINT', location=(0.0, -2.5, 2.5))
rim = bpy.context.active_object
rim.data.energy = 250.0

# Camera (Hero 3/4 perspective focusing on beveled front armor & chest cowl)
cam_data = bpy.data.cameras.new("CamPBR")
cam_data.lens = 42.0
cam_obj = bpy.data.objects.new("CamPBR", cam_data)
bpy.context.scene.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj
cam_obj.location = (1.5, 2.3, 0.65)

# Target point at center of front chest cowl
target_empty = bpy.data.objects.new("CamTarget", None)
target_empty.location = (0.0, 0.65, 0.15)
bpy.context.scene.collection.objects.link(target_empty)

tt = cam_obj.constraints.new(type='TRACK_TO')
tt.target = target_empty
tt.track_axis = 'TRACK_NEGATIVE_Z'
tt.up_axis = 'UP_Y'

bpy.context.scene.render.resolution_x = 1280
bpy.context.scene.render.resolution_y = 720
bpy.context.scene.render.engine = 'BLENDER_EEVEE'



out_img = r"C:\Users\hackd\.gemini\antigravity-ide\brain\bf3b05a4-f495-4afc-a908-879adb0da03d\cockpit_pbr_beveled_preview.png"
bpy.context.scene.render.filepath = out_img
bpy.ops.render.render(write_still=True)

print(f"RENDER COMPLETE: {out_img}")
