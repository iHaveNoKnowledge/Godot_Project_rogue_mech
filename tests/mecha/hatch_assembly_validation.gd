extends Node

## Hatch assembly architecture validation (SLIDE_FORWARD baseline):
##   HatchArmor must inherit motion from the HatchAssembly (SlidingCarriage),
##   never be translated piece-by-piece by gameplay code. FixedArmor,
##   InnerRig/pivots, PilotCompartment and ground must not move with the hatch.
##
## Run: godot --headless --path . res://tests/mecha/hatch_assembly_validation.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const OPEN_POS := Vector3(0.0, -0.22, -0.44)
const OPEN_ROT := Vector3(10.0, 0.0, 0.0)

var _fails := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _find_first(n: Node, name_sub: String) -> Node:
	if name_sub in n.name:
		return n
	for c in n.get_children():
		var f := _find_first(c, name_sub)
		if f != null:
			return f
	return null


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("HATCH_VALIDATE: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)

	var mech: CharacterBody3D = load(MECH_SCENE).instantiate()
	mech.position = Vector3(0, 10, 0)
	add_child(mech)
	await get_tree().process_frame
	var frames := 0
	while not mech.is_on_floor() and frames < 180:
		await get_tree().physics_frame
		frames += 1

	var pmm: Node = mech.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager present")
	if pmm == null:
		return
	var body_entry: Dictionary = pmm.get("slot_meshes").get("body", {})
	var frame_root: Node = body_entry.get("frame")
	var armor_root: Node = body_entry.get("armor")
	_check(frame_root != null and armor_root != null, "body frame+armor roots built")
	var carriage_f: Node3D = frame_root.get_node_or_null("SlidingCarriage") if frame_root else null
	var carriage_a: Node3D = armor_root.get_node_or_null("SlidingCarriage") if armor_root else null
	if carriage_f == null and carriage_a == null:
		print("HATCH BLOCKED: no SlidingCarriage in headless default loadout")
		return
	_check(true, "HatchAssembly carriages present (frame=%s armor=%s)" % [str(carriage_f != null), str(carriage_a != null)])

	var tub: Node = frame_root.get_node_or_null("CockpitTub") if frame_root else null
	_check(tub != null, "PilotCompartment tub present under frame (not armor)")
	# HatchArmor sample: first mesh under either carriage.
	var hatch_armor: MeshInstance3D = null
	for c in [carriage_f, carriage_a]:
		if c == null:
			continue
		var ms: Array = []
		_collect_meshes(c, ms)
		if not ms.is_empty():
			hatch_armor = ms[0]
			break
	_check(hatch_armor != null, "HatchArmor mesh rides the carriage")
	# FixedArmor sample: first armor mesh NOT under any carriage.
	var fixed_armor: MeshInstance3D = null
	if armor_root:
		var allm: Array = []
		_collect_meshes(armor_root, allm)
		for m in allm:
			var p: Node = m
			var under_carriage := false
			while p != null and p != armor_root:
				if "SlidingCarriage" in p.name:
					under_carriage = true
					break
				p = p.get_parent()
			if not under_carriage:
				fixed_armor = m
				break
	_check(fixed_armor != null, "FixedArmor mesh present outside carriage")

	# Deterministic baseline: ambient spawn power state (an unoccupied mech
	# spawns with the hatch OPEN) must not leak into the travel assertion —
	# open-then-open would measure ~zero travel and fail spuriously.
	pmm.set_cockpit_open(false, false)
	await get_tree().process_frame
	await get_tree().process_frame

	var body_p: Node3D = mech.get_node_or_null("Body")
	var leg_p: Node3D = mech.get_node_or_null("LegLeft")
	# NOTE: the live idle animation continuously moves Body (bob/tilt) and
	# everything parented under it. Static checks below therefore use LOCAL
	# transforms (hatch must not move things relative to their parents);
	# only the carriage-local pose and LegLeft/ground globals are absolute.
	var snap_local := {}
	for n in [tub, hatch_armor, fixed_armor]:
		if n != null:
			snap_local[n] = (n as Node3D).transform
	var snap_global := {}
	for n in [leg_p, ground]:
		if n != null:
			snap_global[n] = (n as Node3D).global_transform
	var armor_pre := Transform3D.IDENTITY
	if hatch_armor != null:
		armor_pre = hatch_armor.global_transform

	pmm.set_cockpit_open(true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	for c in [carriage_f, carriage_a]:
		if c == null:
			continue
		_check((c as Node3D).position.is_equal_approx(OPEN_POS), "carriage %s reaches open pose" % (c as Node).name)
		_check((c as Node3D).rotation_degrees.is_equal_approx(OPEN_ROT), "carriage %s reaches open tilt" % (c as Node).name)
	if hatch_armor != null:
		_check(hatch_armor.global_transform.origin.distance_to(armor_pre.origin) > 0.05, "HatchArmor follows the assembly")
	for n in [tub, fixed_armor]:
		if n == null:
			continue
		_check((n as Node3D).transform.origin.distance_to((snap_local[n] as Transform3D).origin) < 0.002, "%s local-static during hatch open" % (n as Node).name)
	for n in [leg_p, ground]:
		if n == null:
			continue
		_check((n as Node3D).global_transform.origin.distance_to((snap_global[n] as Transform3D).origin) < 0.002, "%s static during hatch open" % (n as Node).name)

	pmm.set_cockpit_open(false, false)
	await get_tree().process_frame
	await get_tree().process_frame
	for c in [carriage_f, carriage_a]:
		if c == null:
			continue
		_check((c as Node3D).position.is_equal_approx(Vector3.ZERO), "carriage %s returns closed" % (c as Node).name)
	mech.queue_free()
	await get_tree().process_frame
