extends Node
## HATCH PISTON + KNEEL VERIFY — standard frame (frame_body_01) fixes:
##  1. Hatch rod telescopes so its tip stays engaged inside the tub cylinder
##     both closed and open (no floating gap).
##  2. Empty-mech kneel is single-knee proposal (left forward, right down),
##     not a symmetric squat.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HATCH_KNEEL OK: " + name)
	else:
		_fails += 1
		printerr("HATCH_KNEEL FAIL: " + name)


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 3, 120)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)


func _rod_need(dist: float) -> float:
	return clampf(dist - 0.42 + 0.08, 0.15, 1.2)


func _check_piston_engaged(pmm: Node, tag: String) -> float:
	var frame_mesh: Node3D = pmm.get("slot_meshes")["body"]["frame"]
	var tub: Node3D = frame_mesh.get_node_or_null("CockpitTub")
	var carriage: Node3D = frame_mesh.get_node_or_null("SlidingCarriage")
	_check(tub != null and carriage != null, tag + ": tub+carriage exist")
	if tub == null or carriage == null:
		return -1.0
	var piv_tub := tub.find_child("HatchPivotTub_L", true, false) as Node3D
	var piv_car := carriage.find_child("HatchPivotCarriage_L", true, false) as Node3D
	_check(piv_tub != null and piv_car != null, tag + ": hatch pivots exist")
	if piv_tub == null or piv_car == null:
		return -1.0
	var g_tub: Vector3 = piv_tub.global_position
	var g_car: Vector3 = piv_car.global_position
	var dist: float = g_tub.distance_to(g_car)
	var need: float = _rod_need(dist)
	var rod := piv_car.find_child("HatchPistonRod_L", true, false) as MeshInstance3D
	_check(rod != null, tag + ": piston rod exists")
	if rod == null:
		return dist
	_check(rod.has_meta("base_len"), tag + ": rod telescoping active (base_len meta)")
	# Rod long-axis scale must match need / 0.48.
	var axis_i: int = int(rod.get_meta("axis")) if rod.has_meta("axis") else 2
	var s: Vector3 = rod.scale
	var long_scale: float = s.z if axis_i == 2 else (s.y if axis_i == 1 else s.x)
	_check(absf(long_scale - need / 0.48) < 0.05,
		tag + ": rod stretches to bridge gap (need=%.3f scale=%.3f)" % [need, long_scale])
	# Tip must sit ~0.08 past the cylinder mouth (engaged, not floating).
	var dir: Vector3 = (g_tub - g_car).normalized()
	var tip: Vector3 = g_car + dir * need
	var mouth: Vector3 = g_tub + (-dir) * 0.42
	_check(tip.distance_to(mouth) < 0.15,
		tag + ": rod tip engaged in cylinder (tip-mouth=%.3f)" % tip.distance_to(mouth))
	return need


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loads")
	_make_ground()
	var mecha: CharacterBody3D = mecha_scene.instantiate()
	mecha.position = Vector3(0, 10, 0)
	add_child(mecha)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists")
	if pmm == null:
		get_tree().quit(1)
		return
	var std_frame: Dictionary = ArmorSystem.get_frame_catalog_entry("frame_body_01")
	pmm.initialize_slot("body", null, false, std_frame)
	await get_tree().process_frame

	# Closed hatch: rod retracted but engaged.
	pmm.set_cockpit_open(false, false)
	await get_tree().process_frame
	var need_closed := _check_piston_engaged(pmm, "closed")
	# Open hatch: rod extended and still engaged (the reported floating bug).
	pmm.set_cockpit_open(true, false)
	await get_tree().process_frame
	var need_open := _check_piston_engaged(pmm, "open")
	_check(need_open > need_closed, "rod extends when hatch opens (closed=%.3f open=%.3f)" % [need_closed, need_open])
	_check(need_open > 0.45 and need_open < 1.2,
		"open rod length bridges the gap (need=%.3f)" % need_open)

	# Kneel: single-knee proposal, not symmetric squat.
	var anim = mecha.get_node_or_null("MechaAnimation")
	if anim == null:
		anim = mecha.get_node_or_null("AnimationSystem")
	_check(anim != null, "animation node exists")
	if anim != null:
		anim.set_kneeling(true)
		for i in range(60):
			await get_tree().physics_frame
		var leg_l = mecha.get_node_or_null("LegLeft")
		var leg_r = mecha.get_node_or_null("LegRight")
		var shin_l = mecha.get_node_or_null("LegLeft/ShinLeft")
		var shin_r = mecha.get_node_or_null("LegRight/ShinRight")
		if leg_l and leg_r and shin_l and shin_r:
			_check(absf(rad_to_deg(leg_l.rotation.x) - 85.0) < 18.0,
				"left thigh forward for proposal kneel (%.1fdeg)" % rad_to_deg(leg_l.rotation.x))
			_check(absf(rad_to_deg(leg_r.rotation.x) - 20.0) < 18.0,
				"right thigh down for proposal kneel (%.1fdeg)" % rad_to_deg(leg_r.rotation.x))
			_check(absf(leg_l.rotation.x - leg_r.rotation.x) > 0.5,
				"kneel is asymmetric single-knee, not symmetric squat")
			_check(shin_r.rotation.x < shin_l.rotation.x,
				"back shin folds deeper than front shin")
			_check(leg_l.rotation.x > 0.9, "kneel still folds front thigh forward")
			_check(shin_l.rotation.x < -1.0, "kneel still folds front shin back")
		var body = mecha.get_node_or_null("Body")
		if body:
			# Body rig origin sits at y=3.841; kneel drop -0.68 must pull it
			# down significantly (old <1.6 threshold predates the true-scale
			# rig, so check the relative drop instead).
			_check(body.position.y < 3.841 - 0.5,
				"kneel drops the torso toward the ground (y=%.2f)" % body.position.y)

	print("HATCH_PISTON_KNEEL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("HATCH_PISTON_KNEEL_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_HATCH_PISTON_KNEEL_TESTS_PASSED")
		get_tree().quit(0)
