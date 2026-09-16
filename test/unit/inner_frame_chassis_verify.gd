extends Node
## INNER FRAME CHASSIS VERIFY (structural skeleton pass)
##
## The cockpit is a HARD CONSTRAINT: a human-occupiable volume for a
## 150-200 cm pilot. The chassis (all CH_* meshes) must wrap AROUND it and
## never intersect it. Layering: cockpit tub -> structural cage -> primary
## chassis -> armor hardpoints -> outer armor (separate layer, untouched).
##
## All clearance math runs in Body FrameMesh container-local space.
##
## Covers:
##  1. No CH_* chassis mesh intersects any pilot clearance volume.
##  2. Key structural members exist by name (spine rails, ribs, chest frame,
##     braces, trapezius beams, hip suspension, conduits, hardpoints).
##  3. Chassis complexity: enough structural members, no single giant box.
##  4. Cockpit layer intact: tub, floor, seat, console, holo, pilot seat zone.
##  5. Outer armor layer separate and unchanged (chest plate dims).
##  6. Limb joint-housing details exist without changing limb envelopes.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CHASSIS OK: " + name)
	else:
		_fails += 1
		printerr("CHASSIS FAIL: " + name)


# Pilot clearance volumes (Body FrameMesh container-local AABBs).
# Derived from the cockpit tub interior + seated 150-200 cm pilot mannequin.
func _clearance_boxes() -> Array:
	return [
		# Head (true mannequin bounds + margin).
		AABB(Vector3(-0.11, 0.21, 0.17), Vector3(0.22, 0.22, 0.22)),
		# Torso / shoulders.
		AABB(Vector3(-0.20, -0.28, -0.18), Vector3(0.40, 0.60, 0.40)),
		# Arms (usable side space).
		AABB(Vector3(-0.28, -0.17, -0.22), Vector3(0.16, 0.30, 0.40)),
		AABB(Vector3(0.12, -0.17, -0.22), Vector3(0.16, 0.30, 0.40)),
		# Hips / seat zone.
		AABB(Vector3(-0.17, -0.225, -0.20), Vector3(0.34, 0.25, 0.40)),
		# Knees / lower legs.
		AABB(Vector3(-0.19, -0.50, -0.425), Vector3(0.14, 0.30, 0.45)),
		AABB(Vector3(0.05, -0.50, -0.425), Vector3(0.14, 0.30, 0.45)),
		# Feet / footwell.
		AABB(Vector3(-0.15, -0.625, -0.35), Vector3(0.30, 0.15, 0.40)),
	]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loads")
	_make_ground()
	var mecha: Node3D = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists")
	if pmm == null:
		get_tree().quit(1)
		return

	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var part := ArmorPart.new()
		part.slot_id = slot
		# Empty frame_data forces the procedural cockpit tub (instead of the
		# catalog's Blender tub asset), so this test pins the tub geometry
		# the chassis was designed around.
		var frame_data = {} if slot == "body" else null
		pmm.initialize_slot(slot, part, false, frame_data)
	await get_tree().process_frame

	_test_clearance(pmm)
	_test_structure(pmm)
	_test_layers(pmm)
	_test_limbs(pmm)

	print("INNER_FRAME_CHASSIS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("INNER_FRAME_CHASSIS_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_INNER_FRAME_CHASSIS_TESTS_PASSED")
		get_tree().quit(0)


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.14)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)


func _chassis_meshes(frame: Node3D) -> Array:
	var out: Array = []
	_collect_ch(frame, out)
	return out


func _collect_ch(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("CH_"):
			out.append(c)
		_collect_ch(c, out)


func _ch_by_name(frame: Node3D, pname: String) -> MeshInstance3D:
	if frame == null:
		return null
	return _find_ch(frame, pname)


func _find_ch(n: Node, pname: String) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D and String(c.name) == pname:
			return c
		var sub := _find_ch(c, pname)
		if sub != null:
			return sub
	return null


# --- 1. cockpit clearance: the hard constraint -------------------------------

func _test_clearance(pmm: Node) -> void:
	var entry: Dictionary = pmm.slot_meshes.get("body", {})
	var frame: Node3D = entry.get("frame")
	_check(frame != null, "body frame container exists")
	if frame == null:
		return
	var members := _chassis_meshes(frame)
	_check(members.size() >= 40, "chassis has >= 40 structural members (got %d)" % members.size())
	var boxes := _clearance_boxes()
	var intrusions := 0
	for mi in members:
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		# AABB in container-local space (members are direct children).
		var local_aabb: AABB = (mi as MeshInstance3D).transform * mesh.get_aabb()
		for box in boxes:
			if local_aabb.intersects(box):
				intrusions += 1
				printerr("CHASSIS INTRUSION: %s into pilot volume %s" % [mi.name, str(box)])
	_check(intrusions == 0, "no chassis member enters the pilot clearance volume")


# --- 2. structural members exist ----------------------------------------------

func _test_structure(pmm: Node) -> void:
	var entry: Dictionary = pmm.slot_meshes.get("body", {})
	var frame: Node3D = entry.get("frame")
	var required := [
		"CH_SpineRailL1", "CH_SpineRailL2", "CH_SpineRailL3",
		"CH_SpineRailR1", "CH_SpineRailR2", "CH_SpineRailR3",
		"CH_SpinePin", "CH_RollBar",
		"CH_RibL1", "CH_RibL2", "CH_RibL3",
		"CH_RibR1", "CH_RibR2", "CH_RibR3",
		"CH_ChestPostL", "CH_ChestPostR", "CH_ChestBeamFront",
		"CH_BraceFrontL", "CH_BraceFrontR",
		"CH_SidePlateUpperL", "CH_SidePlateLowerL",
		"CH_SidePlateUpperR", "CH_SidePlateLowerR",
		"CH_TrapeziusL", "CH_TrapeziusR",
		"CH_ShoulderBracketL", "CH_ShoulderBracketR",
		"CH_HipSpringL", "CH_HipSpringR", "CH_HipPistonL", "CH_HipPistonR",
		"CH_HipActuatorL", "CH_HipActuatorR", "CH_HipPlateL", "CH_HipPlateR",
		"CH_ConduitL", "CH_ConduitR", "CH_ConduitRear",
		"CH_HardpointFL", "CH_HardpointFR", "CH_HardBoltFL", "CH_HardBoltFR",
		"CH_ServiceL", "CH_ServiceR", "CH_WaistSideL", "CH_WaistSideR",
		"CH_WaistFront",
	]
	var missing := 0
	for pname in required:
		if _ch_by_name(frame, pname) == null:
			missing += 1
			printerr("CHASSIS MISSING MEMBER: " + pname)
	_check(missing == 0, "all %d primary structural members present" % required.size())
	# No single giant box: every chassis BoxMesh stays a beam/plate member.
	var oversized := 0
	for mi in _chassis_meshes(frame):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh is BoxMesh:
			var s: Vector3 = (mesh as BoxMesh).size
			if s.x * s.y * s.z > 0.02 or (s.x > 0.70 and s.y > 0.70):
				oversized += 1
				printerr("CHASSIS OVERSIZED MEMBER: %s size %s" % [mi.name, str(s)])
	_check(oversized == 0, "no torso-sized boxes in the chassis (members only)")


# --- 3. cockpit + armor layers intact ------------------------------------------

func _test_layers(pmm: Node) -> void:
	var entry: Dictionary = pmm.slot_meshes.get("body", {})
	var frame: Node3D = entry.get("frame")
	var tub = frame.get_node_or_null("CockpitTub") if frame != null else null
	_check(tub != null, "cockpit tub layer exists")
	if tub != null:
		var floor_ok := false
		var seat_ok := false
		var console_ok := false
		var holo_ok := false
		for c in tub.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
				var s: Vector3 = ((c as MeshInstance3D).mesh as BoxMesh).size
				var p: Vector3 = (c as Node3D).position
				if s.is_equal_approx(Vector3(0.48, 0.04, 0.44)) and p.is_equal_approx(Vector3(0, -0.08, -0.05)):
					floor_ok = true
				if s.is_equal_approx(Vector3(0.26, 0.08, 0.24)) and p.is_equal_approx(Vector3(0, -0.02, 0.04)):
					seat_ok = true
				if s.is_equal_approx(Vector3(0.36, 0.05, 0.12)) and p.is_equal_approx(Vector3(0, 0.08, -0.22)):
					console_ok = true
			if String(c.name) == "HoloHUD_Display":
				holo_ok = true
		_check(floor_ok, "cockpit floor dimensions/position unchanged")
		_check(seat_ok, "pilot seat unchanged")
		_check(console_ok, "control console unchanged")
		_check(holo_ok, "holo HUD present")
	# Outer armor stays a separate, unchanged layer.
	var armor: Node3D = entry.get("armor")
	_check(armor != null and armor.visible, "outer armor layer renders separately")
	var chest_ok := false
	if armor != null:
		var stack: Array = [armor]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh is PrismMesh:
				var s: Vector3 = ((n as MeshInstance3D).mesh as PrismMesh).size
				if s.is_equal_approx(Vector3(0.95, 0.65, 0.48)):
					chest_ok = true
			for c in n.get_children():
				stack.append(c)
	_check(chest_ok, "outer chest armor unchanged (separate layer)")


# --- 4. limb joint housings without envelope change ----------------------------

func _test_limbs(pmm: Node) -> void:
	for slot in ["arm_left", "arm_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		_check(_ch_by_name(entry.get("frame"), "CH_UpperActuator") != null, slot + " shoulder actuator present")
		_check(_ch_by_name(entry.get("frame_lower"), "CH_ElbowConduit") != null, slot + " elbow conduit present")
		_check(_ch_by_name(entry.get("frame_lower"), "CH_WristCollar") != null, slot + " wrist collar present")
		var upper: MeshInstance3D = null
		for c in (entry.get("frame") as Node3D).get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
				var s: Vector3 = ((c as MeshInstance3D).mesh as BoxMesh).size
				if absf(s.y - 0.40) < 0.001:
					upper = c
		_check(upper != null and ((upper as MeshInstance3D).mesh as BoxMesh).size.is_equal_approx(Vector3(0.30, 0.40, 0.30)), slot + " upper-arm envelope unchanged")
	for slot in ["leg_left", "leg_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		_check(_ch_by_name(entry.get("frame"), "CH_HipBracket") != null, slot + " hip bracket present")
		_check(_ch_by_name(entry.get("frame"), "CH_ThighConduit") != null, slot + " thigh conduit present")
		var bolts := 0
		for c in (entry.get("frame_lower") as Node3D).get_children():
			if c is MeshInstance3D and String(c.name).begins_with("CH_KneeBolt"):
				bolts += 1
		_check(bolts == 2, slot + " knee bolt caps present both faces")
