import bpy
import bmesh
import math
import os
from mathutils import Vector, Euler, Matrix

# Clear all existing data
bpy.ops.wm.read_factory_settings(use_empty=True)

# Helper for materials
def get_or_create_mat(name, base_color, metallic=0.8, roughness=0.3, emission_color=(0,0,0,1), emission_strength=0.0):
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = base_color
            bsdf.inputs["Metallic"].default_value = metallic
            bsdf.inputs["Roughness"].default_value = roughness
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = emission_color
                bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat

mat_dark_steel = get_or_create_mat("DarkSteel", (0.06, 0.07, 0.09, 1.0), metallic=0.88, roughness=0.28)
mat_chrome = get_or_create_mat("ChromeHydraulic", (0.88, 0.92, 0.96, 1.0), metallic=0.98, roughness=0.08)
mat_accent_orange = get_or_create_mat("AccentOrange", (0.92, 0.32, 0.05, 1.0), metallic=0.25, roughness=0.35)
mat_armor_white = get_or_create_mat("ArmorWhite", (0.85, 0.88, 0.92, 1.0), metallic=0.45, roughness=0.3)
mat_seat_cushion = get_or_create_mat("SeatFabric", (0.04, 0.04, 0.05, 1.0), metallic=0.05, roughness=0.85)
mat_hud_cyan = get_or_create_mat("HoloHUD", (0.1, 0.85, 1.0, 1.0), metallic=0.0, roughness=0.1, emission_color=(0.1, 0.85, 1.0, 1.0), emission_strength=3.5)

# Root Empty
root_obj = bpy.data.objects.new("CockpitAssembly", None)
root_obj.empty_display_type = 'PLAIN_AXES'
bpy.context.scene.collection.objects.link(root_obj)

# -------------------------------------------------------------
# 1. WaistCore (Independent Articulated Hemispherical Sub-Node)
# Centered at Z = -0.28 linking cockpit tub to pelvis
# -------------------------------------------------------------
waist_core = bpy.data.objects.new("WaistCore", None)
waist_core.empty_display_type = 'ARROWS'
waist_core.parent = root_obj
bpy.context.scene.collection.objects.link(waist_core)

# 1.1 Hemispherical Ball Joint (Mailes Kenbu style articulated waist ball)
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=0.20, location=(0, 0, -0.22))
waist_ball = bpy.context.active_object
waist_ball.name = "WaistHemisphere"
waist_ball.parent = waist_core
waist_ball.data.materials.append(mat_dark_steel)

# Flatten bottom half of the ball to make it a distinct hemisphere core
bm = bmesh.new()
bm.from_mesh(waist_ball.data)
for v in bm.verts:
    if v.co.z < -0.26:
        v.co.z = -0.26
bm.to_mesh(waist_ball.data)
bm.free()

# 1.2 Waist Pelvis Collar Ring (Heavy flange ring resting on pelvis)
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.24, depth=0.08, location=(0, 0, -0.34))
waist_ring = bpy.context.active_object
waist_ring.name = "WaistCollarRing"
waist_ring.parent = waist_core
waist_ring.data.materials.append(mat_dark_steel)

# 1.3 Articulated Hydraulic Dampers (4 angled piston struts)
angles = [math.radians(45), math.radians(135), math.radians(225), math.radians(315)]
for i, ang in enumerate(angles):
    bx = 0.18 * math.cos(ang)
    by = 0.18 * math.sin(ang)
    bz = -0.34
    
    tx = 0.13 * math.cos(ang)
    ty = 0.13 * math.sin(ang)
    tz = -0.18
    
    delta = Vector((tx - bx, ty - by, tz - bz))
    length = delta.length
    rot = delta.to_track_quat('Z', 'Y').to_euler()
    
    # Outer barrel
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.024, depth=length * 0.55, location=(bx + delta.x * 0.28, by + delta.y * 0.28, bz + delta.z * 0.28))
    cyl = bpy.context.active_object
    cyl.name = f"WaistHydraulicCylinder_{i}"
    cyl.parent = waist_core
    cyl.rotation_euler = rot
    cyl.data.materials.append(mat_dark_steel)
    
    # Chrome sliding rod
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.015, depth=length * 0.65, location=(bx + delta.x * 0.68, by + delta.y * 0.68, bz + delta.z * 0.68))
    rod = bpy.context.active_object
    rod.name = f"WaistHydraulicRod_{i}"
    rod.parent = waist_core
    rod.rotation_euler = rot
    rod.data.materials.append(mat_chrome)

# -------------------------------------------------------------
# 2. CockpitTub (Stationary Lengthened Cockpit Chassis)
# -------------------------------------------------------------
cockpit_tub = bpy.data.objects.new("CockpitTub", None)
cockpit_tub.parent = root_obj
bpy.context.scene.collection.objects.link(cockpit_tub)

# 2.1 Tub Chassis (Low profile, extended along Y: -0.38 to +0.38)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.03))
tub_mesh = bpy.context.active_object
tub_mesh.name = "TubChassis"
tub_mesh.parent = cockpit_tub
tub_mesh.scale = (0.52, 0.76, 0.40)
bpy.ops.object.transform_apply(scale=True)
tub_mesh.data.materials.append(mat_dark_steel)

# Bevel edges for industrial chamfer look
bm = bmesh.new()
bm.from_mesh(tub_mesh.data)
bmesh.ops.bevel(bm, geom=bm.edges, offset=0.04, segments=2)
bm.to_mesh(tub_mesh.data)
bm.free()

# 2.2 Armor / Spine Rear Pack Mount
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.38, 0.05))
rear_spine = bpy.context.active_object
rear_spine.name = "RearSpineMount"
rear_spine.parent = cockpit_tub
rear_spine.scale = (0.34, 0.08, 0.38)
bpy.ops.object.transform_apply(scale=True)
rear_spine.data.materials.append(mat_armor_white)

# 2.3 Roll Cage Pillars & Overhead Cross-bar
pillar_coords = [(-0.24, -0.25), (0.24, -0.25), (-0.24, 0.15), (0.24, 0.15)]
for i, (px, py) in enumerate(pillar_coords):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.018, depth=0.36, location=(px, py, 0.06))
    pil = bpy.context.active_object
    pil.name = f"RollCagePillar_{i}"
    pil.parent = cockpit_tub
    pil.data.materials.append(mat_dark_steel)

bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.018, depth=0.48, location=(0, -0.25, 0.23))
hbar = bpy.context.active_object
hbar.name = "RollCageHBar"
hbar.parent = cockpit_tub
hbar.rotation_euler = (0, math.radians(90), 0)
hbar.data.materials.append(mat_dark_steel)

# -------------------------------------------------------------
# 2.4 Pilot Reclined Bucket Seat (38° Lean Back toward -Y)
# -------------------------------------------------------------
seat_obj = bpy.data.objects.new("PilotSeatBase", None)
seat_obj.location = (0, -0.06, -0.08)
seat_obj.parent = cockpit_tub
bpy.context.scene.collection.objects.link(seat_obj)

# Butt cushion
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
seat_butt = bpy.context.active_object
seat_butt.name = "SeatCushionButt"
seat_butt.parent = seat_obj
seat_butt.scale = (0.28, 0.22, 0.06)
seat_butt.rotation_euler = (math.radians(-10), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
seat_butt.data.materials.append(mat_seat_cushion)

# Backrest (38° recline backwards toward -Y)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.16, 0.10))
seat_back = bpy.context.active_object
seat_back.name = "SeatBackrest"
seat_back.parent = seat_obj
seat_back.scale = (0.26, 0.06, 0.32)
seat_back.rotation_euler = (math.radians(-38), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
seat_back.data.materials.append(mat_seat_cushion)

# Headrest (sitting low at Z=0.18, well below canopy top Z=0.23)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.26, 0.19))
seat_head = bpy.context.active_object
seat_head.name = "SeatHeadrest"
seat_head.parent = seat_obj
seat_head.scale = (0.16, 0.06, 0.10)
seat_head.rotation_euler = (math.radians(-38), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
seat_head.data.materials.append(mat_seat_cushion)

# Extended Footwell & Pedals (+Y forward)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.28, -0.12))
footwell = bpy.context.active_object
footwell.name = "CockpitFootwell"
footwell.parent = cockpit_tub
footwell.scale = (0.24, 0.18, 0.05)
footwell.rotation_euler = (math.radians(25), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
footwell.data.materials.append(mat_dark_steel)

# Dual HOTAS Flight Control Sticks
for side, sx in [("Left", -0.15), ("Right", 0.15)]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.012, depth=0.12, location=(sx, 0.04, -0.02))
    stick = bpy.context.active_object
    stick.name = f"ControlStick_{side}"
    stick.parent = cockpit_tub
    stick.data.materials.append(mat_dark_steel)
    
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0.04, 0.04))
    grip = bpy.context.active_object
    grip.name = f"ControlGrip_{side}"
    grip.parent = cockpit_tub
    grip.scale = (0.025, 0.04, 0.06)
    grip.rotation_euler = (math.radians(15), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    grip.data.materials.append(mat_accent_orange)

# Holographic HUD Display Rim & Projector
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.14, 0.06))
hud_frame = bpy.context.active_object
hud_frame.name = "HoloHUD_Display"
hud_frame.parent = cockpit_tub
hud_frame.scale = (0.26, 0.02, 0.14)
hud_frame.rotation_euler = (math.radians(-25), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
hud_frame.data.materials.append(mat_hud_cyan)

# -------------------------------------------------------------
# 3. SlidingCarriage (Hatch Door, Authored at (0, 0, 0) Rest State)
# All children placed at their closed forward positions.
# When sliding forward in Godot (-Z), carriage.position shifts forward!
# -------------------------------------------------------------
sliding_carriage = bpy.data.objects.new("SlidingCarriage", None)
sliding_carriage.location = (0, 0, 0)
sliding_carriage.parent = root_obj
bpy.context.scene.collection.objects.link(sliding_carriage)

# 3.1 Front Chest Armor Cowl (Kenbu-style angular chest plate)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.34, 0.05))
front_chest = bpy.context.active_object
front_chest.name = "FrontChestArmor"
front_chest.parent = sliding_carriage
front_chest.scale = (0.50, 0.14, 0.36)
bpy.ops.object.transform_apply(scale=True)
front_chest.data.materials.append(mat_armor_white)

# 3.2 Core Heat Exchanger Block (Center Red / Accent)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.42, 0.08))
core_chest_red = bpy.context.active_object
core_chest_red.name = "CoreChestBlock"
core_chest_red.parent = sliding_carriage
core_chest_red.scale = (0.24, 0.08, 0.20)
bpy.ops.object.transform_apply(scale=True)
core_chest_red.data.materials.append(mat_accent_orange)

# Air Intake Vents
for vy in [0.11, 0.05]:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.46, vy))
    vent = bpy.context.active_object
    vent.name = f"ChestVent_{vy}"
    vent.parent = sliding_carriage
    vent.scale = (0.16, 0.02, 0.025)
    bpy.ops.object.transform_apply(scale=True)
    vent.data.materials.append(mat_dark_steel)

# 3.3 Canopy Top Lip (Seals cockpit tub over pilot)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.22, 0.22))
canopy_lip = bpy.context.active_object
canopy_lip.name = "CanopyTopLip"
canopy_lip.parent = sliding_carriage
canopy_lip.scale = (0.46, 0.16, 0.04)
bpy.ops.object.transform_apply(scale=True)
canopy_lip.data.materials.append(mat_dark_steel)

# 3.4 Lower Abdominal Armor Flap
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.32, -0.13))
ab_plate = bpy.context.active_object
ab_plate.name = "AbdominalFlap"
ab_plate.parent = sliding_carriage
ab_plate.scale = (0.36, 0.10, 0.10)
ab_plate.rotation_euler = (math.radians(-20), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
ab_plate.data.materials.append(mat_dark_steel)

# 3.5 Dual Sliding Rails
for sx in [-0.20, 0.20]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.016, depth=0.40, location=(sx, 0.20, 0.01))
    rail = bpy.context.active_object
    rail.name = f"SlideRail_{'L' if sx < 0 else 'R'}"
    rail.parent = sliding_carriage
    rail.rotation_euler = (math.radians(90), 0, 0)
    rail.data.materials.append(mat_chrome)

# -------------------------------------------------------------
# Export to glTF/GLB
# -------------------------------------------------------------
out_path = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech\assets\models\mech_cockpit_tub.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)

for obj in bpy.context.scene.objects:
    obj.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_yup=True,
    export_apply=False
)

print(f"SUCCESS: Exported Kenbu cockpit GLB with WaistCore to {out_path}")
