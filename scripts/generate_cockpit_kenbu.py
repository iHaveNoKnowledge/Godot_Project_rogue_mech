import bpy
import bmesh
import math
import os
from mathutils import Vector, Euler, Matrix

# Reset Blender
bpy.ops.wm.read_factory_settings(use_empty=True)

# Helper for materials (Pure Industrial Metal - no exterior paint!)
def get_or_create_mat(name, base_color, metallic=0.9, roughness=0.25, emission_color=(0,0,0,1), emission_strength=0.0):
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

mat_dark_frame = get_or_create_mat("DarkFrameSteel", (0.05, 0.06, 0.08, 1.0), metallic=0.92, roughness=0.22)
mat_chrome = get_or_create_mat("ChromeHydraulic", (0.88, 0.92, 0.96, 1.0), metallic=0.98, roughness=0.08)
mat_seat_fabric = get_or_create_mat("SeatFabric", (0.08, 0.08, 0.10, 1.0), metallic=0.1, roughness=0.7)
mat_seat_cushion = get_or_create_mat("SeatCushion", (0.15, 0.16, 0.18, 1.0), metallic=0.2, roughness=0.6)
mat_accent_brass = get_or_create_mat("AccentBrass", (0.85, 0.65, 0.2, 1.0), metallic=0.85, roughness=0.25)
mat_hud_cyan = get_or_create_mat("HoloHUD", (0.1, 0.85, 1.0, 1.0), metallic=0.0, roughness=0.1, emission_color=(0.1, 0.85, 1.0, 1.0), emission_strength=3.5)

# Root Assembly
root_obj = bpy.data.objects.new("CockpitAssembly", None)
root_obj.empty_display_type = 'PLAIN_AXES'
bpy.context.scene.collection.objects.link(root_obj)

# ==============================================================================
# 1. 3-STAGE DOUBLE-JOINT WAIST CORE (Located Underneath Pelvis Chassis)
# ==============================================================================
waist_core = bpy.data.objects.new("WaistCore", None)
waist_core.empty_display_type = 'ARROWS'
waist_core.parent = root_obj
bpy.context.scene.collection.objects.link(waist_core)

# --- Stage 1: Bottom Yaw Turntable Base (Flush to Pelvis, rotates Z-axis in Blender) ---
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.28, depth=0.08, location=(0, 0, -0.46))
yaw_base = bpy.context.active_object
yaw_base.name = "WaistYawBase"
yaw_base.parent = waist_core
yaw_base.data.materials.append(mat_dark_frame)

# Yaw Bearing Collar Ring
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.24, depth=0.03, location=(0, 0, -0.41))
yaw_ring = bpy.context.active_object
yaw_ring.name = "WaistYawRing"
yaw_ring.parent = waist_core
yaw_ring.data.materials.append(mat_chrome)

# --- Stage 2: Middle Semicircular Pitch Arch (Rotates X-axis in Blender for Pitch: ก้ม-เงย) ---
pitch_joint = bpy.data.objects.new("WaistPitchJoint", None)
pitch_joint.location = (0, 0, -0.34)
pitch_joint.parent = waist_core
bpy.context.scene.collection.objects.link(pitch_joint)

# Semicircular Arch Bracket
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.22, depth=0.22, location=(0, 0, 0))
arch_mesh = bpy.context.active_object
arch_mesh.name = "WaistArchBracket"
arch_mesh.parent = pitch_joint
arch_mesh.rotation_euler = (0, math.radians(90), 0)
bpy.ops.object.transform_apply(rotation=True)
arch_mesh.data.materials.append(mat_dark_frame)

# Transverse Horizontal Pitch Axle Pin
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.06, depth=0.28, location=(0, 0, 0))
pitch_pin = bpy.context.active_object
pitch_pin.name = "WaistPitchPin"
pitch_pin.parent = pitch_joint
pitch_pin.rotation_euler = (0, math.radians(90), 0)
bpy.ops.object.transform_apply(rotation=True)
pitch_pin.data.materials.append(mat_chrome)

# End caps on transverse axle pin
for side_x in [-0.15, 0.15]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.075, depth=0.025, location=(side_x, 0, 0))
    pin_cap = bpy.context.active_object
    pin_cap.name = f"WaistPitchPinCap_{'L' if side_x < 0 else 'R'}"
    pin_cap.parent = pitch_joint
    pin_cap.rotation_euler = (0, math.radians(90), 0)
    pin_cap.data.materials.append(mat_accent_brass)

# Dual Heavy Flanking Dampers
for side_x in [-0.20, 0.20]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.03, depth=0.16, location=(side_x, 0.02, -0.40))
    d_cyl = bpy.context.active_object
    d_cyl.name = f"WaistDamperCylinder_{'L' if side_x < 0 else 'R'}"
    d_cyl.parent = waist_core
    d_cyl.data.materials.append(mat_dark_frame)

    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.018, depth=0.16, location=(side_x, 0.02, -0.30))
    d_rod = bpy.context.active_object
    d_rod.name = f"WaistDamperRod_{'L' if side_x < 0 else 'R'}"
    d_rod.parent = waist_core
    d_rod.data.materials.append(mat_chrome)

# --- Stage 3: Upper Angled Roll Pivot (Rotates Y-axis for lateral roll: เอียงตัวซ้าย-ขวา) ---
roll_joint = bpy.data.objects.new("WaistRollJoint", None)
roll_joint.location = (0, -0.05, 0.12)
roll_joint.rotation_euler = (math.radians(-20), 0, 0)
roll_joint.parent = pitch_joint
bpy.context.scene.collection.objects.link(roll_joint)

bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.045, depth=0.18, location=(0, 0, 0))
roll_spindle = bpy.context.active_object
roll_spindle.name = "WaistRollSpindle"
roll_spindle.parent = roll_joint
roll_spindle.data.materials.append(mat_chrome)

bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.075, depth=0.09, location=(0, 0, 0.06))
roll_socket = bpy.context.active_object
roll_socket.name = "WaistRollSocket"
roll_socket.parent = roll_joint
roll_socket.data.materials.append(mat_dark_frame)

# ==============================================================================
# 2. EXPANDED 1:1 HUMAN SCALE HOLLOW COCKPIT TUB (FITS 155cm - 200cm PILOTS)
# Dimensions: Length 1.38m, Width 0.72m (interior 0.62m), Height 0.58m
# ==============================================================================
cockpit_tub = bpy.data.objects.new("CockpitTub", None)
cockpit_tub.parent = root_obj
bpy.context.scene.collection.objects.link(cockpit_tub)

# 2.1 Hollow Cockpit Chassis Structure
# Floor Plate (Sunken to Z=-0.22m)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.08, -0.22))
tub_floor = bpy.context.active_object
tub_floor.name = "CockpitFloor"
tub_floor.parent = cockpit_tub
tub_floor.scale = (0.70, 1.36, 0.04)
bpy.ops.object.transform_apply(scale=True)
tub_floor.data.materials.append(mat_dark_frame)

# Left & Right Armored Side Walls (X = ±0.35m, Height = 0.52m)
for side_x in [-0.35, 0.35]:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side_x, 0.08, 0.06))
    wall = bpy.context.active_object
    wall.name = f"CockpitWall_{'L' if side_x < 0 else 'R'}"
    wall.parent = cockpit_tub
    wall.scale = (0.04, 1.36, 0.52)
    bpy.ops.object.transform_apply(scale=True)
    wall.data.materials.append(mat_dark_frame)

    # Side Guide Slide Rails on top rim (Z = +0.32m)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.020, depth=1.30, location=(side_x, 0.08, 0.32))
    rail = bpy.context.active_object
    rail.name = f"CockpitRail_{'L' if side_x < 0 else 'R'}"
    rail.parent = cockpit_tub
    rail.rotation_euler = (math.radians(90), 0, 0)
    rail.data.materials.append(mat_chrome)

# Rear Armored Bulkhead (behind pilot head at Y = -0.58m)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.58, 0.10))
bulkhead = bpy.context.active_object
bulkhead.name = "CockpitBulkhead"
bulkhead.parent = cockpit_tub
bulkhead.scale = (0.70, 0.06, 0.60)
bpy.ops.object.transform_apply(scale=True)
bulkhead.data.materials.append(mat_dark_frame)

# Rear Spine Pack Mount
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.63, 0.10))
rear_spine = bpy.context.active_object
rear_spine.name = "RearSpineMount"
rear_spine.parent = cockpit_tub
rear_spine.scale = (0.42, 0.06, 0.60)
bpy.ops.object.transform_apply(scale=True)
rear_spine.data.materials.append(mat_dark_frame)

# Roll Cage Overhead H-Bar
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.022, depth=0.68, location=(0, -0.45, 0.33))
hbar = bpy.context.active_object
hbar.name = "RollCageHBar"
hbar.parent = cockpit_tub
hbar.rotation_euler = (0, math.radians(90), 0)
hbar.data.materials.append(mat_dark_frame)

# ------------------------------------------------------------------------------
# 2.2 HIGH-DETAIL PILOT BUCKET SEAT (52° MAILES KENBU / F1 LAYBACK POSE)
# Accommodates 155cm - 200cm pilots with complete head and leg clearance
# ------------------------------------------------------------------------------
seat_base = bpy.data.objects.new("PilotSeatBase", None)
seat_base.location = (0, -0.18, -0.16)
seat_base.parent = cockpit_tub
bpy.context.scene.collection.objects.link(seat_base)

# Seat Steel Mounting Frame
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.04, 0.01))
seat_frame = bpy.context.active_object
seat_frame.name = "SeatFrameBase"
seat_frame.parent = seat_base
seat_frame.scale = (0.44, 0.34, 0.04)
bpy.ops.object.transform_apply(scale=True)
seat_frame.data.materials.append(mat_dark_frame)

# Seat Bottom Cushion (Sunken, padded butt support)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.05, 0.03))
seat_butt = bpy.context.active_object
seat_butt.name = "SeatCushionButt"
seat_butt.parent = seat_base
seat_butt.scale = (0.42, 0.30, 0.07)
seat_butt.rotation_euler = (math.radians(-12), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
seat_butt.data.materials.append(mat_seat_cushion)

# Side Thigh Bolsters (Left & Right)
for side_x in [-0.21, 0.21]:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side_x, 0.05, 0.08))
    bolster = bpy.context.active_object
    bolster.name = f"ThighBolster_{'L' if side_x < 0 else 'R'}"
    bolster.parent = seat_base
    bolster.scale = (0.05, 0.30, 0.08)
    bolster.rotation_euler = (math.radians(-12), 0, math.radians(-15 if side_x < 0 else 15))
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    bolster.data.materials.append(mat_seat_fabric)

# Ergonomic Backrest (52° Layback Recline toward -Y)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.16, 0.20))
seat_back = bpy.context.active_object
seat_back.name = "SeatBackrest"
seat_back.parent = seat_base
seat_back.scale = (0.40, 0.06, 0.48)
seat_back.rotation_euler = (math.radians(-52), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
seat_back.data.materials.append(mat_seat_cushion)

# Side Rib Bolsters on Backrest
for side_x in [-0.20, 0.20]:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side_x, -0.15, 0.20))
    rib_b = bpy.context.active_object
    rib_b.name = f"RibBolster_{'L' if side_x < 0 else 'R'}"
    rib_b.parent = seat_base
    rib_b.scale = (0.05, 0.10, 0.44)
    rib_b.rotation_euler = (math.radians(-52), 0, math.radians(-20 if side_x < 0 else 20))
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    rib_b.data.materials.append(mat_seat_fabric)

# Armored Headrest (sitting low at Z=0.36m, head height of 200cm pilot is 0.28m)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.36, 0.36))
seat_head = bpy.context.active_object
seat_head.name = "SeatHeadrest"
seat_head.parent = seat_base
seat_head.scale = (0.24, 0.06, 0.16)
seat_head.rotation_euler = (math.radians(-52), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
seat_head.data.materials.append(mat_seat_cushion)

# Footwell & Rudder Pedals (+Y forward at Y=0.58m to Y=0.62m)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.58, -0.16))
footwell = bpy.context.active_object
footwell.name = "CockpitFootwell"
footwell.parent = cockpit_tub
footwell.scale = (0.44, 0.28, 0.06)
footwell.rotation_euler = (math.radians(28), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
footwell.data.materials.append(mat_dark_frame)

for ped_x in [-0.12, 0.12]:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ped_x, 0.62, -0.13))
    pedal = bpy.context.active_object
    pedal.name = f"RudderPedal_{'L' if ped_x < 0 else 'R'}"
    pedal.parent = cockpit_tub
    pedal.scale = (0.08, 0.10, 0.025)
    pedal.rotation_euler = (math.radians(38), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    pedal.data.materials.append(mat_chrome)

# Dual HOTAS Flight Control Sticks
for side, sx in [("Left", -0.22), ("Right", 0.22)]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.016, depth=0.14, location=(sx, 0.08, -0.04))
    stick = bpy.context.active_object
    stick.name = f"ControlStick_{side}"
    stick.parent = cockpit_tub
    stick.data.materials.append(mat_dark_frame)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0.08, 0.04))
    grip = bpy.context.active_object
    grip.name = f"ControlGrip_{side}"
    grip.parent = cockpit_tub
    grip.scale = (0.035, 0.05, 0.08)
    grip.rotation_euler = (math.radians(15), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    grip.data.materials.append(mat_accent_brass)

# Forward Console Deck & Holographic HUD Screen
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.25, 0.04))
console = bpy.context.active_object
console.name = "ConsoleDeck"
console.parent = cockpit_tub
console.scale = (0.48, 0.08, 0.14)
console.rotation_euler = (math.radians(-25), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
console.data.materials.append(mat_dark_frame)

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.24, 0.13))
hud_frame = bpy.context.active_object
hud_frame.name = "HoloHUD_Display"
hud_frame.parent = cockpit_tub
hud_frame.scale = (0.36, 0.02, 0.18)
hud_frame.rotation_euler = (math.radians(-25), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
hud_frame.data.materials.append(mat_hud_cyan)

# ==============================================================================
# 2.3 ARTICULATED HATCH HYDRAULIC PISTON BASES (ON STATIONARY COCKPIT TUB)
# Rotating clevis brackets and cylinder barrels that dynamically track the hatch!
# ==============================================================================
# Tub Pivot Anchors located on front upper rim of tub walls: (±0.35, 0.22, 0.32)
for side, sx in [("L", -0.35), ("R", 0.35)]:
    # Clevis pin bracket on tub rim
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0.22, 0.32))
    clevis = bpy.context.active_object
    clevis.name = f"HatchClevisTub_{side}"
    clevis.parent = cockpit_tub
    clevis.scale = (0.05, 0.06, 0.06)
    bpy.ops.object.transform_apply(scale=True)
    clevis.data.materials.append(mat_dark_frame)

    # Rotating Pivot Node for Cylinder
    piv_tub = bpy.data.objects.new(f"HatchPivotTub_{side}", None)
    piv_tub.location = (sx, 0.22, 0.32)
    piv_tub.parent = cockpit_tub
    bpy.context.scene.collection.objects.link(piv_tub)

    # Transverse Clevis Pin
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.012, depth=0.07, location=(0, 0, 0))
    c_pin = bpy.context.active_object
    c_pin.name = f"HatchClevisPinTub_{side}"
    c_pin.parent = piv_tub
    c_pin.rotation_euler = (0, math.radians(90), 0)
    c_pin.data.materials.append(mat_chrome)

    # Hydraulic Cylinder Barrel (extends along local +Y from pivot origin)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.026, depth=0.55, location=(0, 0.275, 0))
    cyl = bpy.context.active_object
    cyl.name = f"HatchCylinder_{side}"
    cyl.parent = piv_tub
    cyl.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    cyl.data.materials.append(mat_dark_frame)

    # Polished Cylinder Collar Ring at the opening
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.031, depth=0.04, location=(0, 0.54, 0))
    collar = bpy.context.active_object
    collar.name = f"HatchCylinderCollar_{side}"
    collar.parent = piv_tub
    collar.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    collar.data.materials.append(mat_chrome)

# ==============================================================================
# 3. SLIDING CARRIAGE (FRONT HATCH DOOR & MOVING PISTON RODS)
# ==============================================================================
sliding_carriage = bpy.data.objects.new("SlidingCarriage", None)
sliding_carriage.location = (0, 0, 0)
sliding_carriage.parent = root_obj
bpy.context.scene.collection.objects.link(sliding_carriage)

# 3.1 Front Chest Armor Cowl (Expanded to width 0.72m, height 0.50m)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.70, 0.08))
front_chest = bpy.context.active_object
front_chest.name = "FrontChestArmor"
front_chest.parent = sliding_carriage
front_chest.scale = (0.72, 0.10, 0.50)
bpy.ops.object.transform_apply(scale=True)
front_chest.data.materials.append(mat_dark_frame)

# 3.2 Front Mechanical Inset Vent
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.76, 0.08))
chest_vent = bpy.context.active_object
chest_vent.name = "ChestVentInset"
chest_vent.parent = sliding_carriage
chest_vent.scale = (0.44, 0.05, 0.14)
bpy.ops.object.transform_apply(scale=True)
chest_vent.data.materials.append(mat_dark_frame)

# 3.3 Canopy Top Seal Lip (Seals overhead roof when hatch closes at Z=+0.35m)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.40, 0.35))
canopy_lip = bpy.context.active_object
canopy_lip.name = "CanopyTopLip"
canopy_lip.parent = sliding_carriage
canopy_lip.scale = (0.68, 0.42, 0.05)
bpy.ops.object.transform_apply(scale=True)
canopy_lip.data.materials.append(mat_dark_frame)

# 3.4 Lower Abdominal Armor Flap
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.64, -0.22))
ab_plate = bpy.context.active_object
ab_plate.name = "AbdominalFlap"
ab_plate.parent = sliding_carriage
ab_plate.scale = (0.50, 0.12, 0.14)
ab_plate.rotation_euler = (math.radians(-20), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
ab_plate.data.materials.append(mat_dark_frame)

# 3.5 Dual Chrome Sliding Runners (slide along cockpit side rails)
for sx in [-0.35, 0.35]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.026, depth=0.52, location=(sx, 0.40, 0.32))
    rail = bpy.context.active_object
    rail.name = f"SlideRail_{'L' if sx < 0 else 'R'}"
    rail.parent = sliding_carriage
    rail.rotation_euler = (math.radians(90), 0, 0)
    rail.data.materials.append(mat_chrome)

# 3.6 Piston Rod Clevis Pivots on Sliding Carriage
for side, sx in [("L", -0.35), ("R", 0.35)]:
    # Clevis pin bracket on carriage
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0.66, 0.18))
    clevis_c = bpy.context.active_object
    clevis_c.name = f"HatchClevisCarriage_{side}"
    clevis_c.parent = sliding_carriage
    clevis_c.scale = (0.048, 0.055, 0.055)
    bpy.ops.object.transform_apply(scale=True)
    clevis_c.data.materials.append(mat_dark_frame)

    # Rotating Pivot Node for Piston Rod
    piv_c = bpy.data.objects.new(f"HatchPivotCarriage_{side}", None)
    piv_c.location = (sx, 0.66, 0.18)
    piv_c.parent = sliding_carriage
    bpy.context.scene.collection.objects.link(piv_c)

    # Transverse Pin
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.010, depth=0.065, location=(0, 0, 0))
    c_pin_c = bpy.context.active_object
    c_pin_c.name = f"HatchClevisPinCarriage_{side}"
    c_pin_c.parent = piv_c
    c_pin_c.rotation_euler = (0, math.radians(90), 0)
    c_pin_c.data.materials.append(mat_chrome)

    # Chrome Piston Rod (extends along local -Y toward tub from pivot origin)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.016, depth=0.65, location=(0, -0.325, 0))
    rod = bpy.context.active_object
    rod.name = f"HatchPistonRod_{side}"
    rod.parent = piv_c
    rod.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    rod.data.materials.append(mat_chrome)

# ==============================================================================
# EXPORT GLB
# ==============================================================================
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

print(f"SUCCESS: Exported Expanded Cockpit (155-200cm) with Articulated Hydraulic Hatch Pistons to {out_path}")
