import bpy
import math
import os

bpy.ops.wm.read_factory_settings(use_empty=True)

glb_path = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech\assets\models\mech_cockpit_tub.glb"
bpy.ops.import_scene.gltf(filepath=glb_path)

def create_mat(name, color, roughness=0.35, metallic=0.1):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes.get("Principled BSDF")
    if b:
        b.inputs["Base Color"].default_value = color
        b.inputs["Roughness"].default_value = roughness
        b.inputs["Metallic"].default_value = metallic
    return mat

mat_p200 = create_mat("Pilot200_Orange", (0.95, 0.45, 0.1, 1.0))
mat_p155 = create_mat("Pilot155_Green", (0.15, 0.75, 0.35, 1.0))
mat_visor = create_mat("VisorMat", (0.05, 0.08, 0.12, 1.0), roughness=0.05, metallic=0.9)

# Build 24° combat seated pilot
def build_fitted_pilot(height_m, name, mat_suit, offset_x=0.0):
    scale_fac = height_m / 1.75
    head_r = 0.10 * scale_fac
    neck_h = 0.05 * scale_fac
    torso_w = 0.32 * scale_fac
    torso_d = 0.20 * scale_fac
    torso_h = 0.46 * scale_fac
    thigh_len = 0.44 * scale_fac
    thigh_r = 0.07 * scale_fac
    shin_len = 0.42 * scale_fac
    shin_r = 0.055 * scale_fac
    foot_len = 0.25 * scale_fac

    root = bpy.data.objects.new(f"{name}_Root", None)
    root.location = (offset_x, 0, 0)
    bpy.context.scene.collection.objects.link(root)

    pelvis_y = -0.10
    pelvis_z = -0.25
    recline_deg = 24.0

    # Pelvis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(offset_x, pelvis_y, pelvis_z))
    p = bpy.context.active_object
    p.parent = root
    p.scale = (torso_w * 0.85, torso_d * 0.9, 0.11 * scale_fac)
    bpy.ops.object.transform_apply(scale=True)
    p.data.materials.append(mat_suit)

    # Torso
    t_dist = torso_h * 0.5
    t_y = pelvis_y - (t_dist * math.sin(math.radians(recline_deg)))
    t_z = pelvis_z + (t_dist * math.cos(math.radians(recline_deg)))
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(offset_x, t_y, t_z))
    t = bpy.context.active_object
    t.parent = root
    t.scale = (torso_w, torso_d, torso_h)
    t.rotation_euler = (math.radians(-recline_deg), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    t.data.materials.append(mat_suit)

    # Head
    h_dist = torso_h + neck_h + head_r
    h_y = pelvis_y - (h_dist * math.sin(math.radians(recline_deg)))
    h_z = pelvis_z + (h_dist * math.cos(math.radians(recline_deg)))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=head_r, location=(offset_x, h_y, h_z))
    h = bpy.context.active_object
    h.name = f"{name}_Head"
    h.parent = root
    h.data.materials.append(mat_suit)

    # Visor
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(offset_x, h_y + head_r * 0.55, h_z + head_r * 0.12))
    v = bpy.context.active_object
    v.parent = root
    v.scale = (head_r * 1.3, head_r * 0.55, head_r * 0.45)
    v.rotation_euler = (math.radians(-recline_deg), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    v.data.materials.append(mat_visor)

    # Legs: thighs forward-flat (+4 deg), knees bent at 82 deg, shins dropping into footwell
    for sx in [-torso_w * 0.28, torso_w * 0.28]:
        # Thigh
        th_y = pelvis_y + (thigh_len * 0.5 * math.cos(math.radians(4)))
        th_z = pelvis_z + (thigh_len * 0.5 * math.sin(math.radians(4)))
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=thigh_r, depth=thigh_len, location=(offset_x + sx, th_y, th_z))
        th = bpy.context.active_object
        th.parent = root
        th.rotation_euler = (math.radians(86), 0, 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        th.data.materials.append(mat_suit)

        # Knee
        kn_y = pelvis_y + (thigh_len * math.cos(math.radians(4)))
        kn_z = pelvis_z + (thigh_len * math.sin(math.radians(4)))

        # Shin
        sh_y = kn_y + (shin_len * 0.5 * math.cos(math.radians(78)))
        sh_z = kn_z - (shin_len * 0.5 * math.sin(math.radians(78)))
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=shin_r, depth=shin_len, location=(offset_x + sx, sh_y, sh_z))
        sh = bpy.context.active_object
        sh.parent = root
        sh.rotation_euler = (math.radians(-12), 0, 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        sh.data.materials.append(mat_suit)

        # Foot resting on pedal
        ft_y = kn_y + (shin_len * math.cos(math.radians(78))) + foot_len * 0.15
        ft_z = kn_z - (shin_len * math.sin(math.radians(78)))
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(offset_x + sx, ft_y, ft_z))
        ft = bpy.context.active_object
        ft.parent = root
        ft.scale = (shin_r * 1.8, foot_len, shin_r * 1.1)
        bpy.ops.object.transform_apply(scale=True)
        ft.data.materials.append(mat_suit)

    rear_y = h_y - head_r
    bulk_y = -0.66
    clear_rear = abs(bulk_y - rear_y)
    front_y = ft_y + foot_len * 0.5
    front_wall = 0.72
    clear_front = front_wall - front_y
    top_z = h_z + head_r
    roof_z = 0.58
    clear_top = roof_z - top_z
    print(f"[{name} TALL COMPACT MECHA REPORT]")
    print(f"  Head Rear Y: {rear_y:.3f}m | Bulkhead Y: {bulk_y:.3f}m | Clearance Behind Head: {clear_rear*100:.1f} cm")
    print(f"  Foot Front Y: {front_y:.3f}m | Front Face Y: {front_wall:.3f}m | Clearance In Front: {clear_front*100:.1f} cm")
    print(f"  Head Top Z: {top_z:.3f}m | Canopy Top Z: {roof_z:.3f}m | Clearance Above Head: {clear_top*100:.1f} cm")

build_fitted_pilot(2.00, "Pilot_200cm", mat_p200, offset_x=0.0)

# Studio Lights
world = bpy.data.worlds.new("StudioWorld")
bpy.context.scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
if bg:
    bg.inputs["Color"].default_value = (0.06, 0.07, 0.09, 1.0)

bpy.ops.object.light_add(type='SUN', location=(3.0, 3.5, 4.0))
sun = bpy.context.active_object
sun.data.energy = 4.5
sun.rotation_euler = (math.radians(35), math.radians(20), math.radians(-35))

bpy.ops.object.light_add(type='AREA', location=(-2.5, 1.5, 2.5))
fill = bpy.context.active_object
fill.data.energy = 300.0
fill.data.size = 3.0

bpy.context.scene.render.resolution_x = 1280
bpy.context.scene.render.resolution_y = 720

# ------------------------------------------------------------------------------
# RENDER 1: Side Cutaway (Hide CockpitWall_L)
# ------------------------------------------------------------------------------
for obj in bpy.data.objects:
    if "CockpitWall_L" in obj.name or "SlideRail_L" in obj.name:
        obj.hide_render = True

cam1_data = bpy.data.cameras.new("SideCutawayCam")
cam1_data.type = 'ORTHO'
cam1_data.ortho_scale = 2.0
cam1_obj = bpy.data.objects.new("SideCutawayCam", cam1_data)
bpy.context.scene.collection.objects.link(cam1_obj)
bpy.context.scene.camera = cam1_obj
cam1_obj.location = (-3.5, 0.03, 0.04)
cam1_obj.rotation_euler = (math.radians(90), 0, math.radians(-90))

out_img1 = r"C:\Users\hackd\.gemini\antigravity-ide\brain\bf3b05a4-f495-4afc-a908-879adb0da03d\cockpit_heroic_tall_cutaway.png"
bpy.context.scene.render.filepath = out_img1
bpy.ops.render.render(write_still=True)
print(f"RENDER 1 COMPLETE: {out_img1}")

# ------------------------------------------------------------------------------
# RENDER 2: 3/4 Perspective View (Hatch Open & Pistons Articulated)
# ------------------------------------------------------------------------------
for obj in bpy.data.objects:
    if "CockpitWall_L" in obj.name or "SlideRail_L" in obj.name:
        obj.hide_render = False

carriage = bpy.data.objects.get("SlidingCarriage")
if carriage:
    carriage.location = (0.0, 0.44, -0.22)
    carriage.rotation_euler = (math.radians(10), 0, 0)

# Aim pistons
for side in ["L", "R"]:
    piv_t = bpy.data.objects.get(f"HatchPivotTub_{side}")
    piv_c = bpy.data.objects.get(f"HatchPivotCarriage_{side}")
    if piv_t and piv_c:
        direction_t = piv_c.matrix_world.translation - piv_t.matrix_world.translation
        piv_t.rotation_euler = direction_t.to_track_quat('Y', 'Z').to_euler()
        direction_c = piv_t.matrix_world.translation - piv_c.matrix_world.translation
        piv_c.rotation_euler = direction_c.to_track_quat('-Y', 'Z').to_euler()

cam2_data = bpy.data.cameras.new("IsoPerspectiveCam")
cam2_data.lens = 45
cam2_obj = bpy.data.objects.new("IsoPerspectiveCam", cam2_data)
bpy.context.scene.collection.objects.link(cam2_obj)
bpy.context.scene.camera = cam2_obj
cam2_obj.location = (-1.8, 1.8, 1.2)
cam2_obj.rotation_euler = (math.radians(64), 0, math.radians(-135))

out_img2 = r"C:\Users\hackd\.gemini\antigravity-ide\brain\bf3b05a4-f495-4afc-a908-879adb0da03d\cockpit_heroic_tall_perspective_open.png"
bpy.context.scene.render.filepath = out_img2
bpy.ops.render.render(write_still=True)
print(f"RENDER 2 COMPLETE: {out_img2}")
