extends Node
## FRAME VARIANT RESOLVER VERIFY (audit follow-up implementation)
##
## Proves the data-driven variant layer without touching Standard behavior:
##  A. Standard parity: variant data reproduces production constants/pivots.
##  B. Heavy: same JSON clip -> identical rotations, own rest, mounts follow.
##  C. Extended: +20% limbs, same clip -> identical rotations, hand follows.
##  D. Lifecycle: pre-tree variant rest survives live driver initialization.
##  E. Aux joint: unmapped joints idle rigidly while animation runs.

const JSON_CLIP := "res://tools/kimodo/samples/valkren_sprint_run.json"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("VARIANT OK: " + name)
	else:
		_fails += 1
		printerr("VARIANT FAIL: " + name)


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_freeze(c)


func _joints(mecha: Node3D) -> Dictionary:
	return {
		"body": mecha.get_node_or_null("Body"),
		"head": mecha.get_node_or_null("Head"),
		"arm_left": mecha.get_node_or_null("ArmLeft"),
		"arm_right": mecha.get_node_or_null("ArmRight"),
		"forearm_left": mecha.get_node_or_null("ArmLeft/ForearmLeft"),
		"forearm_right": mecha.get_node_or_null("ArmRight/ForearmRight"),
		"leg_left": mecha.get_node_or_null("LegLeft"),
		"leg_right": mecha.get_node_or_null("LegRight"),
		"shin_left": mecha.get_node_or_null("LegLeft/ShinLeft"),
		"shin_right": mecha.get_node_or_null("LegRight/ShinRight"),
	}


func _bases(j: Dictionary) -> Dictionary:
	return {
		"body_y": (j["body"] as Node3D).position.y,
		"leg_l_y": (j["leg_left"] as Node3D).position.y,
		"leg_r_y": (j["leg_right"] as Node3D).position.y,
	}


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.14)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)


func _ready() -> void:
	await get_tree().process_frame
	_make_ground()
	var scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(scene != null and scene.can_instantiate(), "mecha_base.tscn loads")

	_test_standard_parity(scene)
	await _test_heavy(scene)
	await _test_extended(scene)
	await _test_lifecycle(scene)
	await _test_aux_joint(scene)

	print("FRAME_VARIANT_RESOLVER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FRAME_VARIANT_RESOLVER_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FRAME_VARIANT_RESOLVER_TESTS_PASSED")
		get_tree().quit(0)


# --- A. Standard parity -------------------------------------------------------
func _test_standard_parity(scene: PackedScene) -> void:
	var std := FrameVariantData.get_variant("standard")
	_check(std["id"] == "standard", "standard variant resolves")
	# Rest reproduces the production tscn pivots exactly.
	var mech: Node3D = scene.instantiate()
	_freeze(mech)
	add_child(mech)
	_freeze(mech) # catch _ready-spawned drivers before any frame
	await get_tree().process_frame
	var rest: Dictionary = std["rest"]
	var match_all := true
	for path in rest:
		var n := mech.get_node_or_null(String(path)) as Node3D
		if n == null or not (n.position as Vector3).is_equal_approx(rest[path]):
			match_all = false
			print("VARIANT rest-mismatch %s live=%s data=%s" % [String(path), str(n.position) if n != null else "NULL", str(rest[path])])
	_check(match_all, "standard rest == production tscn pivots")
	# Mount defaults reproduce the factory constants.
	_check(FrameVariantResolver.hand_mount_local_for(mech).is_equal_approx(WeaponVisualFactory.HAND_FOREARM_POS), "standard hand mount == HAND_FOREARM_POS")
	_check(FrameVariantResolver.shoulder_mount_local_for(mech).is_equal_approx(WeaponVisualFactory.SHOULDER_ARM_POS), "standard shoulder mount == SHOULDER_ARM_POS")
	# FootIK / locomotion / collar defaults reproduce production constants.
	var fk = mech.get_node_or_null("FootIKSystem")
	_check(fk != null and absf(float(fk.get("foot_spacing_x")) - 0.38) < 0.0001 and absf(float(fk.get("ray_height")) - 2.4) < 0.0001 and absf(float(fk.get("ray_length")) - 3.3) < 0.0001, "standard footik == 0.38/2.4/3.3")
	_check(absf(FrameVariantResolver.natural_speed_for(mech) - MechaClipRetarget.NATURAL_SPEED) < 0.0001, "standard natural_speed == 8.5")
	_check(FrameVariantResolver.head_collar_for(mech).is_equal_approx(MechaRig.HEAD_COLLAR_LOCAL), "standard collar == HEAD_COLLAR_LOCAL")
	_check(absf(FrameVariantResolver.lift_scale_for(mech) - 1.0) < 0.0001, "standard lift_scale == 1.0")
	# Hangar derivation reproduces the hardcoded table exactly.
	var hp := FrameVariantResolver.hangar_pose_for("standard")
	var hp_match := true
	for k in MechaScaleSystem.HANGAR_POSE:
		if not (hp.get(k, Vector3.ZERO) as Vector3).is_equal_approx(MechaScaleSystem.HANGAR_POSE[k]):
			hp_match = false
	_check(hp_match, "standard hangar pose == HANGAR_POSE")
	# Real mounts land on the constants.
	var w := WeaponPart.new()
	var mh = WeaponVisualFactory.mount_hand(mech, "left", w, "ParityHand")
	var ms = WeaponVisualFactory.mount_shoulder(mech, "left", w, "ParityShoulder")
	_check((mh as Node3D).position.is_equal_approx(WeaponVisualFactory.HAND_FOREARM_POS), "mounted hand at HAND_FOREARM_POS")
	_check((ms as Node3D).position.is_equal_approx(WeaponVisualFactory.SHOULDER_ARM_POS), "mounted shoulder at SHOULDER_ARM_POS")
	mech.queue_free()
	await get_tree().process_frame


# --- B. Heavy ------------------------------------------------------------------
func _test_heavy(scene: PackedScene) -> void:
	var std_m: Node3D = scene.instantiate()
	_freeze(std_m)
	add_child(std_m)
	_freeze(std_m)
	var hvy_m: Node3D = scene.instantiate()
	FrameVariantResolver.apply_variant(hvy_m, "heavy")
	_freeze(hvy_m)
	add_child(hvy_m)
	_freeze(hvy_m)
	await get_tree().process_frame
	await get_tree().process_frame
	var js := _joints(std_m)
	var jh := _joints(hvy_m)
	# Rest differs per data.
	_check(absf((jh["arm_left"] as Node3D).position.x + 1.30) < 0.0001, "heavy shoulders wider (-1.30)")
	_check(absf((jh["leg_left"] as Node3D).position.y - 3.30) < 0.0001, "heavy hips raised (3.30)")
	# Same JSON clip -> identical rotations on every joint, own bases.
	var clip: MechaJsonClip = MechaJsonClip.load_file(JSON_CLIP)
	_check(clip.is_loaded(), "sprint JSON clip loads")
	var w := WeaponPart.new()
	var ms = WeaponVisualFactory.mount_hand(std_m, "left", w, "HeavyStd")
	var mh = WeaponVisualFactory.mount_hand(hvy_m, "left", w, "HeavyHvy")
	_check((mh as Node3D).position.is_equal_approx(Vector3(0, -0.80, 0)), "heavy hand mount local == variant offset")
	for f in [0, 15, 30, 43]:
		clip.cursor = float(f)
		clip.apply_to_joints(js, _bases(js))
		clip.apply_to_joints(jh, _bases(jh))
		await get_tree().process_frame
		var same := true
		for k in js:
			if not ((js[k] as Node3D).rotation as Vector3).is_equal_approx((jh[k] as Node3D).rotation):
				same = false
		_check(same, "heavy frame %d: same clip -> identical rotations" % f)
	_check(not (ms as Node3D).global_position.is_equal_approx((mh as Node3D).global_position), "heavy mount world follows variant pivot")
	# FootIK + collision resolved per variant; shape edit does not leak.
	var fk = hvy_m.get_node_or_null("FootIKSystem")
	_check(fk != null and absf(float(fk.get("foot_spacing_x")) - 0.45) < 0.0001, "heavy footik spacing 0.45")
	var col_s := std_m.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var col_h := hvy_m.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_check(absf((col_h.shape as CapsuleShape3D).height - 5.9) < 0.0001 and absf((col_h.shape as CapsuleShape3D).radius - 1.15) < 0.0001, "heavy capsule 5.9/1.15")
	_check(absf((col_s.shape as CapsuleShape3D).height - 5.5) < 0.0001, "standard capsule untouched (shape duplicated)")
	_check(absf(FrameVariantResolver.natural_speed_for(hvy_m) - 7.0) < 0.0001, "heavy natural_speed 7.0")
	std_m.queue_free()
	hvy_m.queue_free()
	await get_tree().process_frame


# --- C. Extended ---------------------------------------------------------------
func _test_extended(scene: PackedScene) -> void:
	var std_m: Node3D = scene.instantiate()
	_freeze(std_m)
	add_child(std_m)
	_freeze(std_m)
	var ext_m: Node3D = scene.instantiate()
	FrameVariantResolver.apply_variant(ext_m, "extended")
	_freeze(ext_m)
	add_child(ext_m)
	_freeze(ext_m)
	await get_tree().process_frame
	await get_tree().process_frame
	var js := _joints(std_m)
	var je := _joints(ext_m)
	_check(absf((je["forearm_left"] as Node3D).position.y + 0.7661) < 0.0001, "extended forearm +20% (-0.7661)")
	_check(absf((je["shin_left"] as Node3D).position.y + 1.608) < 0.0001, "extended shin +20% (-1.608)")
	_check(absf(absf((je["arm_left"] as Node3D).position.x) - 1.1424) < 0.0001, "extended keeps standard width")
	var clip: MechaJsonClip = MechaJsonClip.load_file(JSON_CLIP)
	var w := WeaponPart.new()
	var me = WeaponVisualFactory.mount_hand(ext_m, "left", w, "ExtHand")
	_check((me as Node3D).position.is_equal_approx(Vector3(0, -0.864, 0)), "extended hand mount local == (0,-0.864,0)")
	_check(((me as Node3D).get_parent() as Node3D).name == "ForearmLeft", "extended weapon stays pivot-parented (no root anchoring)")
	for f in [5, 25, 43]:
		clip.cursor = float(f)
		clip.apply_to_joints(js, _bases(js))
		clip.apply_to_joints(je, _bases(je))
		await get_tree().process_frame
		var same := true
		for k in js:
			if not ((js[k] as Node3D).rotation as Vector3).is_equal_approx((je[k] as Node3D).rotation):
				same = false
		_check(same, "extended frame %d: same clip -> identical rotations" % f)
	# Mount world differs by construction: raised hips (+0.526 local) outweigh
	# the longer arm (-0.272 local); analytic world delta = +0.292 m.
	var std_w: Vector3 = (WeaponVisualFactory.mount_hand(std_m, "left", w, "ExtStd") as Node3D).global_position
	var ext_w: Vector3 = (me as Node3D).global_position
	_check(absf((ext_w.y - std_w.y) - 0.292) < 0.08, "extended hand weapon offset by construction (+0.292, got %.3f)" % (ext_w.y - std_w.y))
	std_m.queue_free()
	ext_m.queue_free()
	await get_tree().process_frame


# --- D. Lifecycle: pre-tree rest survives live drivers --------------------------
func _test_lifecycle(scene: PackedScene) -> void:
	var std_m: Node3D = scene.instantiate()
	add_child(std_m) # live drivers, grounded idle
	var hvy_m: Node3D = scene.instantiate()
	FrameVariantResolver.apply_variant(hvy_m, "heavy")
	add_child(hvy_m) # live drivers capture VARIANT rest at their _ready
	for i in range(90):
		await get_tree().physics_frame
	var s_arm: float = (std_m.get_node_or_null("ArmLeft") as Node3D).position.x
	var h_arm: float = (hvy_m.get_node_or_null("ArmLeft") as Node3D).position.x
	var s_leg: float = (std_m.get_node_or_null("LegLeft") as Node3D).position.y
	var h_leg: float = (hvy_m.get_node_or_null("LegLeft") as Node3D).position.y
	print("VARIANT lifecycle std arm=%.4f leg=%.4f | hvy arm=%.4f leg=%.4f" % [s_arm, s_leg, h_arm, h_leg])
	_check(absf(h_arm + 1.30) < 0.001, "heavy shoulder rest intact after 90 live frames")
	_check(absf((h_leg - s_leg) - 0.299) < 0.06, "heavy leg keeps +0.299 differential (no pullback to standard)")
	_check(absf(h_arm - (s_arm - 0.1576)) < 0.02, "heavy arm keeps width differential under live drivers")
	# Drivers actually ran (not a frozen null test): idle posture rotates limbs.
	var moved := ((hvy_m.get_node_or_null("ArmLeft") as Node3D).rotation as Vector3).length() > 0.01
	_check(moved, "live drivers posed the variant (rotations active, positions stable)")
	std_m.queue_free()
	hvy_m.queue_free()
	await get_tree().process_frame


# --- E. Auxiliary joint ----------------------------------------------------------
func _test_aux_joint(scene: PackedScene) -> void:
	var mech: Node3D = scene.instantiate()
	FrameVariantResolver.apply_variant(mech, "heavy")
	add_child(mech) # live drivers
	await get_tree().process_frame
	var elbow := mech.get_node_or_null("ArmLeft/ForearmLeft") as Node3D
	var aux := Node3D.new()
	aux.name = "HydraulicSupportJoint"
	aux.position = Vector3(0, -0.30, 0.15)
	elbow.add_child(aux)
	var rest_pos: Vector3 = aux.position
	var clip: MechaJsonClip = MechaJsonClip.load_file(JSON_CLIP)
	var j := _joints(mech)
	for f in range(0, 44, 4):
		clip.cursor = float(f)
		clip.apply_to_joints(j, _bases(j))
		await get_tree().physics_frame
	_check((aux.position as Vector3).is_equal_approx(rest_pos), "unmapped aux joint keeps rest (no driver writes it)")
	_check((aux.rotation as Vector3).is_equal_approx(Vector3.ZERO), "unmapped aux joint never rotates")
	_check(aux.global_position.distance_to((elbow as Node3D).global_position) > 0.01, "aux joint rides its parent rigidly")
	mech.queue_free()
	await get_tree().process_frame
