extends RefCounted
## VALKREN INNER FRAME REFERENCE BUILDER (spec 2026-10-03)
##
## Builds the unarmored mechanical-skeleton reference as a Godot scene from the
## authoritative dimension table below (meters, Godot axes: Up +Y, Forward -Z).
## Layer order: Pilot -> Cockpit -> Inner Frame -> Joint Hardware -> (armor is
## a separate faint clearance envelope, never geometry that moves joints).
##
## Connection map (each joint overlaps its neighbours by >= 5 mm):
##   foot_sole (Y=0.00) <-> foot_block (0.00..0.18)        sits on ground
##   ankle_axle (Y=0.25) <-> shin_column (0.18..1.77)       overlap 0.07 on Y
##   shin_column        <-> knee_drum (Y=1.70)              overlap 0.07 on Y
##   knee_drum          <-> thigh_spine (1.63..2.92)        overlap 0.07 on Y
##   thigh_spine        <-> hip_sphere (Y=2.85)             overlap 0.07 on Y
##   hip_sphere         <-> pelvis_core (2.70..3.00)        overlap 0.07 on Y
##   pelvis_core        <-> spine_column (2.95..4.55)       overlap 0.05 on Y
##   spine_column       <-> neck_post (4.45..4.62)          overlap 0.05 on Y
##   neck_post          <-> sensor_head (4.55..4.95)        sits/overlap 0.07
##   shoulder_line (Y=4.40) <-> clavicle_axle (X +-0.55..0.98) overlap 0.13 on X
##   clavicle_axle      <-> shoulder_sphere (X=+-0.85)      overlap 0.13 on X
##   shoulder_sphere    <-> upperarm_beam (3.38..4.47)      overlap 0.07 on Y
##   upperarm_beam      <-> elbow_drum (Y=3.45)             overlap 0.07 on Y
##   elbow_drum         <-> forearm_beam (2.23..3.52)       overlap 0.07 on Y
##   forearm_beam       <-> wrist_block (Y=2.30)            overlap 0.07 on Y
##   wrist_block        <-> hand_block (1.90..2.37)         overlap 0.07 on Y
##   cage_posts         <-> tub_floor / cage_arch          overlap 0.05 on Y
##   seat_base          <-> tub_floor                      sits (contact 0.00+)

class_name ValkrenInnerFrameReference

## Authoritative dimension table (meters). The single source of truth.
const DIMS := {
	"overall_height": 4.95,
	"ankle_y": 0.25,
	"knee_y": 1.70,
	"hip_y": 2.85,
	"hip_span": 1.10,
	"neck_y": 4.55,
	"head_height": 0.40,
	"head_width": 0.35,
	"torso_hip_neck": 1.70,
	"chest_width": 1.60,
	"shoulder_y": 4.40,
	"shoulder_span": 1.70,
	"upper_arm": 0.95,
	"forearm": 1.15,
	"hand": 0.40,
	"thigh": 1.15,
	"shin": 1.45,
	"foot_len": 0.90,
	"foot_w": 0.55,
	"pilot_height": 1.80,
}


static func steel_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.31, 0.33)
	m.metallic = 0.45
	m.roughness = 0.55
	return m


static func chrome_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.77, 0.80)
	m.metallic = 0.9
	m.roughness = 0.28
	return m


static func joint_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.42, 0.10)
	m.metallic = 0.55
	m.roughness = 0.4
	return m


static func pilot_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.45, 0.55)
	m.metallic = 0.05
	m.roughness = 0.8
	return m


static func envelope_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.30, 0.75, 0.95, 0.10)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _box(parent: Node3D, pname: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, pname: String, r_top: float, r_bot: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = height
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Cylinder with its long axis along X (axles, drums). Built by rotating a
## Y-cylinder exactly +-90 deg about Z only (no arbitrary Euler chains).
static func _axle_x(parent: Node3D, pname: String, radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := _cyl(parent, pname, radius, radius, length, pos, mat)
	mi.rotation_degrees = Vector3(0, 0, 90)
	return mi


static func _sphere(parent: Node3D, pname: String, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _joint(parent: Node3D, jname: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = jname
	j.position = pos
	parent.add_child(j)
	return j


static func _label(parent: Node3D, text: String, pos: Vector3, align_right: bool = false) -> Label3D:
	# Small annotation-column text: always drawn on top (engineering overlay
	# style) so callouts stay legible from every ortho camera angle.
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = 40
	l.pixel_size = 0.0022
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(0.10, 0.13, 0.18)
	l.outline_size = 12
	l.outline_modulate = Color(0.96, 0.97, 0.98)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(l)
	return l


## Builds the full reference rig under a new root and returns it (not in tree).
static func build() -> Node3D:
	var steel := steel_mat()
	var chrome := chrome_mat()
	var joint := joint_mat()
	var pilotm := pilot_mat()
	var env := envelope_mat()

	var root := Node3D.new()
	root.name = "ValkrenInnerFrameReference"

	var frame := Node3D.new()
	frame.name = "InnerFrame"
	root.add_child(frame)

	var ankle_y: float = DIMS["ankle_y"]
	var knee_y: float = DIMS["knee_y"]
	var hip_y: float = DIMS["hip_y"]
	var neck_y: float = DIMS["neck_y"]
	var shoulder_y: float = DIMS["shoulder_y"]

	# ---- pelvis core + hip axle -------------------------------------------
	_box(frame, "PelvisCore", Vector3(0.78, 0.30, 0.52), Vector3(0, hip_y, 0), steel)
	_axle_x(frame, "HipAxle", 0.10, 1.10, Vector3(0, hip_y, 0), chrome)
	_joint(frame, "JNT_Pelvis", Vector3(0, hip_y, 0))

	# ---- legs (mirrored) ----------------------------------------------------
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		var hx: float = side * float(DIMS["hip_span"]) * 0.5
		_sphere(frame, "HipSphere" + tag, 0.14, Vector3(hx, hip_y, 0), joint)
		_joint(frame, "JNT_Hip" + tag, Vector3(hx, hip_y, 0))
		# thigh spine: knee..hip plus overlap into both joints
		var thigh_c := (knee_y + hip_y) * 0.5
		_box(frame, "ThighSpine" + tag, Vector3(0.26, float(DIMS["thigh"]) + 0.14, 0.30), Vector3(hx, thigh_c, 0), steel)
		# thigh hydraulic piston (front face)
		_cyl(frame, "ThighPiston" + tag, 0.045, 0.045, 0.95, Vector3(hx, thigh_c, -0.20), chrome)
		# knee drum (axis X) + bolt caps
		_axle_x(frame, "KneeDrum" + tag, 0.13, 0.24, Vector3(hx, knee_y, 0), joint)
		_joint(frame, "JNT_Knee" + tag, Vector3(hx, knee_y, 0))
		# shin column: ankle..knee plus overlap
		var shin_c := (ankle_y + knee_y) * 0.5
		_box(frame, "ShinColumn" + tag, Vector3(0.24, float(DIMS["shin"]) + 0.14, 0.26), Vector3(hx, shin_c, 0), steel)
		# shin damper pair (rear face)
		for dx in [-0.07, 0.07]:
			_cyl(frame, "ShinDamper%s%s" % [tag, "A" if dx < 0.0 else "B"], 0.035, 0.035, 1.10, Vector3(hx + dx, shin_c, 0.17), chrome)
		# ankle axle + foot
		_axle_x(frame, "AnkleAxle" + tag, 0.11, 0.22, Vector3(hx, ankle_y, 0), joint)
		_joint(frame, "JNT_Ankle" + tag, Vector3(hx, ankle_y, 0))
		var foot := _box(frame, "FootBlock" + tag, Vector3(float(DIMS["foot_w"]), 0.18, float(DIMS["foot_len"])), Vector3(hx, 0.09, -0.30), steel)
		# toe cap (front overhang) + heel block
		_box(frame, "ToeCap" + tag, Vector3(0.45, 0.10, 0.22), Vector3(hx, 0.05, -0.72), steel)
		_box(frame, "HeelBlock" + tag, Vector3(0.40, 0.12, 0.20), Vector3(hx, 0.06, 0.10), steel)
		# limb clearance sleeves (armor envelope, faint)
		_box(frame, "ClearThigh" + tag, Vector3(0.56, float(DIMS["thigh"]) + 0.20, 0.60), Vector3(hx, thigh_c, 0), env)
		_box(frame, "ClearShin" + tag, Vector3(0.54, float(DIMS["shin"]) + 0.20, 0.56), Vector3(hx, shin_c, 0), env)

	# ---- spine + roll cage ---------------------------------------------------
	_box(frame, "SpineColumn", Vector3(0.34, 1.75, 0.40), Vector3(0, (hip_y + neck_y) * 0.5, 0.28), steel)
	_box(frame, "WaistRing", Vector3(0.90, 0.18, 0.70), Vector3(0, hip_y + 0.28, 0.05), steel)
	_box(frame, "ChestBeam", Vector3(float(DIMS["chest_width"]), 0.22, 0.55), Vector3(0, shoulder_y + 0.12, 0.05), steel)
	# roll-cage posts (outboard of the cockpit, never through pilot volume)
	for side in [-1.0, 1.0]:
		_box(frame, "CagePost%s" % ("L" if side < 0.0 else "R"), Vector3(0.12, 1.70, 0.14), Vector3(side * 0.62, 3.75, -0.10), steel)
		_box(frame, "CageRear%s" % ("L" if side < 0.0 else "R"), Vector3(0.12, 1.70, 0.14), Vector3(side * 0.62, 3.75, 0.45), steel)
	_box(frame, "CageArchTop", Vector3(1.36, 0.12, 0.70), Vector3(0, 4.62, 0.17), steel)
	_joint(frame, "JNT_Neck", Vector3(0, neck_y, 0))
	# torso clearance envelope
	_box(frame, "ClearTorso", Vector3(1.90, 2.00, 1.20), Vector3(0, 3.70, 0.0), env)

	# ---- cockpit tub + seat + controls ---------------------------------------
	var cockpit := Node3D.new()
	cockpit.name = "Cockpit"
	frame.add_child(cockpit)
	# Rear tub floor (under the seat) + sunken front footwell (boots rest ON
	# the footwell floor, never through it). Footwell sides tie the walls down.
	_box(cockpit, "TubFloor", Vector3(0.95, 0.06, 0.50), Vector3(0, 3.02, 0.125), steel)
	_box(cockpit, "FootwellFloor", Vector3(0.95, 0.06, 0.50), Vector3(0, 2.70, -0.35), steel)
	_box(cockpit, "TubWallL", Vector3(0.06, 0.55, 0.95), Vector3(-0.475, 3.30, -0.10), steel)
	_box(cockpit, "TubWallR", Vector3(0.06, 0.55, 0.95), Vector3(0.475, 3.30, -0.10), steel)
	_box(cockpit, "FootwellSideL", Vector3(0.06, 0.38, 0.50), Vector3(-0.475, 2.89, -0.35), steel)
	_box(cockpit, "FootwellSideR", Vector3(0.06, 0.38, 0.50), Vector3(0.475, 2.89, -0.35), steel)
	_box(cockpit, "FootwellFrontBeam", Vector3(1.07, 0.12, 0.12), Vector3(0, 2.85, -0.575), steel)
	_box(cockpit, "TubRear", Vector3(0.95, 0.75, 0.08), Vector3(0, 3.40, 0.38), steel)
	_box(cockpit, "SeatBase", Vector3(0.50, 0.10, 0.48), Vector3(0, 3.12, 0.10), steel)
	var seat_back := _box(cockpit, "SeatBack", Vector3(0.50, 0.62, 0.10), Vector3(0, 3.48, 0.32), steel)
	seat_back.rotation_degrees = Vector3(-8, 0, 0)
	_box(cockpit, "Headrest", Vector3(0.30, 0.18, 0.12), Vector3(0, 3.86, 0.36), steel)
	_box(cockpit, "ConsoleDeck", Vector3(0.60, 0.06, 0.30), Vector3(0, 3.28, -0.50), steel)
	for side in [-1.0, 1.0]:
		_cyl(cockpit, "Stick%s" % ("L" if side < 0.0 else "R"), 0.025, 0.025, 0.22, Vector3(side * 0.28, 3.20, -0.28), chrome)
		# Pedals ride on the footwell floor (top 2.73); boots sit on the pedals.
		_box(cockpit, "Pedal%s" % ("L" if side < 0.0 else "R"), Vector3(0.16, 0.05, 0.30), Vector3(side * 0.20, 2.76, -0.52), joint)

	# ---- seated 180 cm pilot (true meters, fits tub, never rescaled) ---------
	var seated := Node3D.new()
	seated.name = "SeatedPilot180"
	cockpit.add_child(seated)
	_box(seated, "PilotTorso", Vector3(0.42, 0.60, 0.26), Vector3(0, 3.52, 0.10), pilotm)
	_sphere(seated, "PilotHead", 0.12, Vector3(0, 4.02, 0.08), pilotm)
	_box(seated, "PilotVisor", Vector3(0.20, 0.06, 0.05), Vector3(0, 4.02, -0.03), joint)
	for side in [-1.0, 1.0]:
		_box(seated, "PilotUpperArm%s" % ("L" if side < 0.0 else "R"), Vector3(0.11, 0.32, 0.11), Vector3(side * 0.28, 3.60, 0.05), pilotm)
		_box(seated, "PilotForearm%s" % ("L" if side < 0.0 else "R"), Vector3(0.10, 0.30, 0.10), Vector3(side * 0.28, 3.36, -0.12), pilotm)
		_box(seated, "PilotThigh%s" % ("L" if side < 0.0 else "R"), Vector3(0.15, 0.15, 0.45), Vector3(side * 0.16, 3.18, -0.12), pilotm)
		_box(seated, "PilotShin%s" % ("L" if side < 0.0 else "R"), Vector3(0.13, 0.42, 0.13), Vector3(side * 0.16, 3.10, -0.30), pilotm)
		_box(seated, "PilotBoot%s" % ("L" if side < 0.0 else "R"), Vector3(0.14, 0.10, 0.28), Vector3(side * 0.16, 2.84, -0.40), pilotm)
	_joint(seated, "JNT_PilotSeat", Vector3(0, 3.17, 0.10))

	# ---- neck + sensor head ---------------------------------------------------
	_cyl(frame, "NeckPost", 0.13, 0.15, 0.20, Vector3(0, neck_y - 0.03, 0), chrome)
	_box(frame, "SensorHead", Vector3(float(DIMS["head_width"]), float(DIMS["head_height"]), 0.34), Vector3(0, neck_y + float(DIMS["head_height"]) * 0.5, -0.02), steel)
	_box(frame, "SensorVisor", Vector3(0.26, 0.08, 0.03), Vector3(0, neck_y + 0.24, -0.20), joint)
	_joint(frame, "JNT_Head", Vector3(0, neck_y + 0.10, 0))

	# ---- shoulder line + arms (mirrored) --------------------------------------
	_axle_x(frame, "ClavicleAxle", 0.09, 1.70, Vector3(0, shoulder_y, 0), chrome)
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		var sx: float = side * float(DIMS["shoulder_span"]) * 0.5
		_sphere(frame, "ShoulderSphere" + tag, 0.13, Vector3(sx, shoulder_y, 0), joint)
		_joint(frame, "JNT_Shoulder" + tag, Vector3(sx, shoulder_y, 0))
		var elbow_y := shoulder_y - float(DIMS["upper_arm"])
		var wrist_y := elbow_y - float(DIMS["forearm"])
		var ua_c := (shoulder_y + elbow_y) * 0.5
		_box(frame, "UpperArmBeam" + tag, Vector3(0.22, float(DIMS["upper_arm"]) + 0.14, 0.24), Vector3(sx, ua_c, 0), steel)
		_cyl(frame, "UpperArmPiston" + tag, 0.04, 0.04, 0.80, Vector3(sx, ua_c, 0.15), chrome)
		_axle_x(frame, "ElbowDrum" + tag, 0.11, 0.20, Vector3(sx, elbow_y, 0), joint)
		_joint(frame, "JNT_Elbow" + tag, Vector3(sx, elbow_y, 0))
		var fa_c := (elbow_y + wrist_y) * 0.5
		_box(frame, "ForearmBeam" + tag, Vector3(0.20, float(DIMS["forearm"]) + 0.14, 0.22), Vector3(sx, fa_c, 0), steel)
		_box(frame, "WristBlock" + tag, Vector3(0.18, 0.14, 0.18), Vector3(sx, wrist_y, 0), chrome)
		_joint(frame, "JNT_Wrist" + tag, Vector3(sx, wrist_y, 0))
		_box(frame, "HandBlock" + tag, Vector3(0.16, float(DIMS["hand"]), 0.20), Vector3(sx, wrist_y - float(DIMS["hand"]) * 0.5 + 0.03, 0), steel)
		_box(frame, "ClearUpperArm" + tag, Vector3(0.52, float(DIMS["upper_arm"]) + 0.20, 0.54), Vector3(sx, ua_c, 0), env)
		_box(frame, "ClearForearm" + tag, Vector3(0.50, float(DIMS["forearm"]) + 0.20, 0.52), Vector3(sx, fa_c, 0), env)

	# ---- standing 180 cm pilot reference (beside the frame) --------------------
	var stand := Node3D.new()
	stand.name = "StandingPilot180"
	stand.position = Vector3(1.70, 0, 0.30)
	root.add_child(stand)
	_cyl(stand, "BodyCapsule", 0.16, 0.16, 1.48, Vector3(0, 0.90, 0), pilotm)
	_sphere(stand, "Head", 0.12, Vector3(0, 1.68, 0), pilotm)
	_joint(stand, "JNT_PilotTop", Vector3(0, 1.80, 0))

	# ---- dimension callouts: two annotation columns clear of the profile -----
	var notes := Node3D.new()
	notes.name = "DimensionCallouts"
	root.add_child(notes)
	# Left column (text extends left, away from the frame).
	_label(notes, "HEAD 0.40 m", Vector3(-2.50, 4.78, 0), true)
	_label(notes, "TORSO HIP-NECK 1.70 m", Vector3(-2.50, 3.70, 0), true)
	_label(notes, "THIGH 1.15 m", Vector3(-2.50, 2.28, 0), true)
	_label(notes, "SHIN 1.45 m", Vector3(-2.50, 0.98, 0), true)
	_label(notes, "FOOT 0.90 x 0.55 m", Vector3(-2.50, 0.32, 0), true)
	_label(notes, "OVERALL 4.95 m", Vector3(-2.50, 0.02, 0), true)
	# Right column (text extends right, away from the frame).
	_label(notes, "SHOULDER SPAN 1.70 m", Vector3(2.50, 4.98, 0))
	_label(notes, "CHEST 1.60 m", Vector3(2.50, 4.52, 0))
	_label(notes, "UPPER ARM 0.95 m", Vector3(2.50, 3.95, 0))
	_label(notes, "FOREARM 1.15 m", Vector3(2.50, 2.90, 0))
	_label(notes, "HIP SPAN 1.10 m", Vector3(2.50, 2.50, 0))
	_label(notes, "HAND 0.40 m", Vector3(2.50, 2.10, 0))
	_label(notes, "PILOT 1.80 m", Vector3(2.50, 1.55, 0))

	# ---- orthographic reference cameras ---------------------------------------
	_add_ortho_cam(root, "CamFront", Vector3(0, 2.50, -9), Vector3(0, 2.50, 0))
	_add_ortho_cam(root, "CamSide", Vector3(9, 2.50, 0), Vector3(0, 2.50, 0))
	_add_ortho_cam(root, "CamRear", Vector3(0, 2.50, 9), Vector3(0, 2.50, 0))

	return root


static func _add_ortho_cam(parent: Node3D, cname: String, pos: Vector3, look: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = cname
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 7.0
	cam.position = pos
	# Explicit facing (build() runs outside the tree, so look_at() is illegal):
	# default camera faces -Z; front faces +Z, rear faces -Z, side faces -X.
	if cname == "CamFront":
		cam.rotation_degrees = Vector3(0, 180, 0)
	elif cname == "CamSide":
		cam.rotation_degrees = Vector3(0, 90, 0)
	parent.add_child(cam)
	return cam


## Ownership pass: nodes built in code have owner=null and PackedScene.pack()
## would silently drop them. Every descendant must be owned by the root.
static func _own_recursive(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own_recursive(c, root)


## Saves the built reference as a scene asset. Returns the saved path.
static func save_scene(path: String = "res://scenes/mecha/valkren_innerframe_reference.tscn") -> String:
	var root := build()
	_own_recursive(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("[InnerFrameRef] pack failed: %s" % err)
		return ""
	root.queue_free()
	var werr := ResourceSaver.save(packed, path)
	if werr != OK:
		push_error("[InnerFrameRef] save failed: %s" % werr)
		return ""
	return path
