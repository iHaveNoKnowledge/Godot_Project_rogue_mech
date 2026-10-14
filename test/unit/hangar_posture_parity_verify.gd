extends Node
## HANGAR POSTURE PARITY VERIFY (Phase E2-F1: Hangar Posture Consistency &
## Unit-Space Audit Fix)
##
## Pins the verified contracts through the REAL application paths (no literal
## duplication of pose tables):
##  1. HEAD PARITY: the Hangar head target (HangarGaragePanel.
##     apply_tactical_idle_pose) and the combat_crouch idle target
##     (MechaAnimation._update_combat_idle_posture via _apply_pose) converge
##     to the SAME head rotation: torso(-4°) + approved +2° relative
##     counter-tilt = -2° absolute in mecha-local space.
##  2. UNIT SPACE: HANGAR_POSE entries are consumed as MECHA-LOCAL pivot
##     positions (direct assignment, no conversion); root scale applies once.
##  3. NO DOUBLE SCALE: world == local * root scale (1.15), never squared.
##  4. COMBAT UNCHANGED: hip drop (-0.03 rest-relative), zero leg drops,
##     FootIK defaults intact, gameplay keeps REST foot X (hangar spread is
##     showroom-only and must not leak into gameplay).
##  5. REST INTACT: FrameVariantData.STANDARD_REST still matches the
##     production tscn pivots.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HANGAR-PARITY OK: " + name)
	else:
		_fails += 1
		printerr("HANGAR-PARITY FAIL: " + name)


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_freeze(c)


func _ready() -> void:
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(scene != null and scene.can_instantiate(), "mecha_base.tscn loads")

	await _test_head_parity(scene)
	await _test_hangar_unit_space(scene)
	await _test_combat_unchanged(scene)
	await _test_rest_intact(scene)

	print("HANGAR_POSTURE_PARITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("HANGAR_POSTURE_PARITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_HANGAR_POSTURE_PARITY_TESTS_PASSED")
		get_tree().quit(0)


# --- 1. head-pivot parity through both real paths -----------------------------
func _test_head_parity(scene: PackedScene) -> void:
	# Hangar path: the REAL showroom function on a frozen mannequin.
	var hangar_m: Node3D = scene.instantiate()
	_freeze(hangar_m)
	add_child(hangar_m)
	_freeze(hangar_m)
	await get_tree().process_frame
	var panel := HangarGaragePanel.new()
	panel.apply_tactical_idle_pose(hangar_m)
	var h_head := hangar_m.get_node_or_null("Head") as Node3D
	var h_body := hangar_m.get_node_or_null("Body") as Node3D
	_check(h_head != null and h_body != null, "hangar pivots exist")
	# Torso target untouched by this phase.
	_check(absf(h_body.rotation.x + deg_to_rad(4.0)) < 0.0005, "hangar torso target still -4° (got %.4f°)" % rad_to_deg(h_body.rotation.x))
	# Hangar head carries the approved +2° RELATIVE target (not absolute +2°).
	_check(absf(h_head.rotation.x - (h_body.rotation.x + deg_to_rad(2.0))) < 0.0005, "hangar head == torso + 2° relative (got %.4f°)" % rad_to_deg(h_head.rotation.x))
	_check(absf(h_head.rotation.x + deg_to_rad(2.0)) < 0.0005, "hangar head absolute -2° (got %.4f°)" % rad_to_deg(h_head.rotation.x))

	# Combat path: the REAL idle driver, converged deterministically.
	var combat_m: Node3D = scene.instantiate()
	add_child(combat_m) # live _ready captures rest originals
	await get_tree().process_frame
	_freeze(combat_m) # stop per-frame drivers; direct calls below are exact
	var anim = combat_m.get_node_or_null("MechaAnimation")
	_check(anim != null and anim.has_method("_update_combat_idle_posture"), "MechaAnimation idle driver present")
	anim.set("stance_mode", "combat_crouch")
	for i in range(20):
		anim._update_combat_idle_posture(0.1) # weight 0.6/step, no overshoot
	var c_head := combat_m.get_node_or_null("Head") as Node3D
	var c_body := combat_m.get_node_or_null("Body") as Node3D
	_check(absf(c_body.rotation.x + deg_to_rad(4.0)) < 0.002, "combat torso converges to -4° (got %.4f°)" % rad_to_deg(c_body.rotation.x))
	_check(absf(c_head.rotation.x + deg_to_rad(2.0)) < 0.002, "combat head converges to -2° absolute (got %.4f°)" % rad_to_deg(c_head.rotation.x))
	# Parity across the two real paths (rotation only: head ANCHOR positions
	# intentionally differ — collar-follow in combat vs static in hangar).
	_check(absf(h_head.rotation.x - c_head.rotation.x) < 0.002, "hangar/combat head parity (Δ=%.4f°)" % rad_to_deg(h_head.rotation.x - c_head.rotation.x))
	# Full limb-rotation parity: hangar hero pose == combat_crouch dict.
	for pname in ["ArmLeft", "ArmLeft/ForearmLeft", "ArmRight", "ArmRight/ForearmRight", "LegLeft", "LegLeft/ShinLeft", "LegRight", "LegRight/ShinRight"]:
		var hn := hangar_m.get_node_or_null(pname) as Node3D
		var cn := combat_m.get_node_or_null(pname) as Node3D
		var same := hn != null and cn != null and (hn.rotation as Vector3).distance_to(cn.rotation) < 0.003
		_check(same, "limb rotation parity %s" % pname)
	hangar_m.queue_free()
	combat_m.queue_free()
	await get_tree().process_frame


# --- 2+3. HANGAR_POSE unit space: direct local assignment, single scale ------
func _test_hangar_unit_space(scene: PackedScene) -> void:
	var mech: Node3D = scene.instantiate()
	_freeze(mech)
	add_child(mech)
	_freeze(mech)
	await get_tree().process_frame
	HangarGaragePanel.new().apply_tactical_idle_pose(mech)
	var root_s: float = mech.scale.x
	_check(absf(root_s - 1.15) < 0.0001, "mannequin root scale is 1.15 (single authority)")
	# Every resolver-mapped key lands EXACTLY on the table value in LOCAL space
	# (direct assignment: no inv-scale, no WORLD_SCALE, no conversion).
	var all_direct := true
	for key in FrameVariantResolver.HANGAR_PIVOT_PATHS:
		var path: String = FrameVariantResolver.HANGAR_PIVOT_PATHS[key]
		var n := mech.get_node_or_null(path) as Node3D
		var want := MechaScaleSystem.HANGAR_POSE.get(key, Vector3.ZERO) as Vector3
		if n == null or not (n.position as Vector3).is_equal_approx(want):
			all_direct = false
			print("HANGAR-PARITY unit-mismatch %s local=%s table=%s" % [path, str(n.position) if n != null else "NULL", str(want)])
	_check(all_direct, "HANGAR_POSE consumed as mecha-local positions (no conversion)")
	# Root-level pivots: world == local * root scale exactly once.
	var single := true
	for path in ["Head", "Body", "ArmLeft", "ArmRight", "LegLeft", "LegRight"]:
		var n := mech.get_node_or_null(path) as Node3D
		var expect: Vector3 = (n.position as Vector3) * root_s
		if not (n.global_position as Vector3).is_equal_approx(expect):
			single = false
			print("HANGAR-PARITY scale-mismatch %s world=%s expect=%s" % [path, str(n.global_position), str(expect)])
		# Guard against a "helpful" double-scale: world must NOT equal local*1.15^2.
		var doubled: Vector3 = (n.position as Vector3) * root_s * root_s
		if (n.global_position as Vector3).is_equal_approx(doubled) and not (n.position as Vector3).is_zero_approx():
			single = false
			print("HANGAR-PARITY double-scale detected at %s" % path)
	_check(single, "root scale applied exactly once (world == local * 1.15)")
	# Feet are not in HANGAR_POSE: hangar must leave them at rest.
	var rest: Dictionary = FrameVariantData.STANDARD_REST
	var feet_ok := true
	for path in ["LegLeft/ShinLeft/FootLeft", "LegRight/ShinRight/FootRight"]:
		var n := mech.get_node_or_null(path) as Node3D
		if n == null or not (n.position as Vector3).is_equal_approx(rest[path]):
			feet_ok = false
	_check(feet_ok, "hangar leaves feet at rest (no HANGAR_POSE foot keys)")
	mech.queue_free()
	await get_tree().process_frame


# --- 4. combat idle side effects unchanged ------------------------------------
func _test_combat_unchanged(scene: PackedScene) -> void:
	var mech: Node3D = scene.instantiate()
	add_child(mech)
	await get_tree().process_frame
	_freeze(mech)
	var anim = mech.get_node_or_null("MechaAnimation")
	anim.set("stance_mode", "combat_crouch")
	for i in range(20):
		anim._update_combat_idle_posture(0.1)
	var rest: Dictionary = FrameVariantData.STANDARD_REST
	var body := mech.get_node_or_null("Body") as Node3D
	_check(absf(body.position.y - ((rest["Body"] as Vector3).y - 0.03)) < 0.002, "combat hip drop still -0.03 rest-relative (got %.4f)" % (body.position.y - (rest["Body"] as Vector3).y))
	var legs_ok := true
	for path in ["LegLeft", "LegRight"]:
		var n := mech.get_node_or_null(path) as Node3D
		if not (n.position as Vector3).is_equal_approx(rest[path]):
			legs_ok = false
	_check(legs_ok, "combat leg drops still zero (positions at rest)")
	# Gameplay keeps REST foot spacing: hangar showroom spread must not leak.
	var lL := mech.get_node_or_null("LegLeft") as Node3D
	_check(absf(absf(lL.position.x) - 0.6384) < 0.0001, "gameplay foot X still rest ±0.6384 (not hangar ±0.88872)")
	# FootIK contract untouched.
	var fk = mech.get_node_or_null("FootIKSystem")
	_check(fk != null and absf(float(fk.get("foot_spacing_x")) - 0.38) < 0.0001 and absf(float(fk.get("ray_height")) - 2.4) < 0.0001 and absf(float(fk.get("ray_length")) - 3.3) < 0.0001, "FootIK defaults intact (0.38/2.4/3.3)")
	mech.queue_free()
	await get_tree().process_frame


# --- 5. rest-pose invariants intact -------------------------------------------
func _test_rest_intact(scene: PackedScene) -> void:
	var mech: Node3D = scene.instantiate()
	_freeze(mech)
	add_child(mech)
	_freeze(mech)
	await get_tree().process_frame
	var rest: Dictionary = FrameVariantData.STANDARD_REST
	var match_all := true
	for path in rest:
		var n := mech.get_node_or_null(String(path)) as Node3D
		if n == null or not (n.position as Vector3).is_equal_approx(rest[path]):
			match_all = false
			print("HANGAR-PARITY rest-mismatch %s live=%s data=%s" % [String(path), str(n.position) if n != null else "NULL", str(rest[path])])
	_check(match_all, "STANDARD_REST == production tscn pivots (untouched)")
	mech.queue_free()
	await get_tree().process_frame
