extends Node
## WEAPON LOCOMOTION LAYER VERIFY (shared locomotion + weapon upper body)
##
## Proves the pose separation on real pivots:
##  A. Empty-hand sprint: swing preserved, handling applies nothing.
##  B. Rifle sprint: same base, arms pinned to hold, legs untouched,
##     handling idempotent (no double-transform), gun stable across frames.
##  C. Heavy (pile bunker): both arms braced, legs untouched.
##  D. Frame x Weapon: standard/heavy/extended share handling source.
##  E. Extended mount follows variant forearm with handling active.
##  F. Priority: handling -> melee swing owns -> handling reasserts.

const JSON_CLIP := "res://tools/kimodo/samples/valkren_sprint_run.json"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("WPNLAYER OK: " + name)
	else:
		_fails += 1
		printerr("WPNLAYER FAIL: " + name)


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_freeze(c)


func _build_mech(scene: PackedScene, vid: String = "") -> Node3D:
	var mech: Node3D = scene.instantiate()
	if vid != "":
		FrameVariantResolver.apply_variant(mech, vid)
	_freeze(mech)
	add_child(mech)
	_freeze(mech)
	return mech


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


func _rifle() -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	return w


func _blade() -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_type = WeaponPart.WeaponType.MELEE
	return w


func _pile() -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_type = WeaponPart.WeaponType.MELEE
	w.weapon_name = "Pile Bunker"
	return w


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(scene != null and scene.can_instantiate(), "mecha_base.tscn loads")
	var clip: MechaJsonClip = MechaJsonClip.load_file(JSON_CLIP)
	_check(clip.is_loaded(), "sprint JSON clip loads")

	await _test_empty_hand(scene, clip)
	await _test_rifle(scene, clip)
	await _test_heavy(scene, clip)
	await _test_frame_weapon_composition(scene, clip)
	await _test_priority_chain(scene, clip)

	print("WEAPON_LOCOMOTION_LAYER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("WEAPON_LOCOMOTION_LAYER_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_WEAPON_LOCOMOTION_LAYER_TESTS_PASSED")
		get_tree().quit(0)


# --- A. empty-hand sprint -------------------------------------------------------
func _test_empty_hand(scene: PackedScene, clip: MechaJsonClip) -> void:
	var mech := _build_mech(scene)
	await get_tree().process_frame
	var ma = mech.get_node_or_null("MechaAnimation")
	var j := _joints(mech)
	var peak := 0.0
	for f in [0, 10, 20, 30, 40]:
		clip.cursor = float(f)
		clip.apply_to_joints(j, _bases(j))
		peak = maxf(peak, absf(((j["arm_left"] as Node3D).rotation as Vector3).x))
	await get_tree().process_frame
	_check(peak > 0.05, "empty sprint swings arms (peak %.3f rad)" % peak)
	clip.cursor = 20.0
	clip.apply_to_joints(j, _bases(j))
	var swing_l: Vector3 = (j["arm_left"] as Node3D).rotation
	ma._apply_handling(10.0, null, null)
	await get_tree().process_frame
	_check(((j["arm_left"] as Node3D).rotation as Vector3).is_equal_approx(swing_l), "empty handling applies nothing (swing preserved)")
	_check(absf(float(ma.get("_handling_l"))) < 0.001 and absf(float(ma.get("_handling_r"))) < 0.001, "empty handling weights stay zero")
	mech.queue_free()
	await get_tree().process_frame


# --- B. rifle sprint --------------------------------------------------------------
func _test_rifle(scene: PackedScene, clip: MechaJsonClip) -> void:
	var mech := _build_mech(scene)
	await get_tree().process_frame
	var ma = mech.get_node_or_null("MechaAnimation")
	var j := _joints(mech)
	var rifle := _rifle()
	# Same base frame as the empty run: legs must match it exactly.
	clip.cursor = 20.0
	clip.apply_to_joints(j, _bases(j))
	await get_tree().process_frame
	var base_legs := [(j["leg_left"] as Node3D).rotation, (j["leg_right"] as Node3D).rotation]
	ma._apply_handling(10.0, null, rifle)
	await get_tree().process_frame
	var ar: Vector3 = (j["arm_right"] as Node3D).rotation
	var fr: Vector3 = (j["forearm_right"] as Node3D).rotation
	var al: Vector3 = (j["arm_left"] as Node3D).rotation
	var fl: Vector3 = (j["forearm_left"] as Node3D).rotation
	_check(absf(rad_to_deg(ar.x) - 57.0) < 2.0 and absf(rad_to_deg(fr.x) - 23.0) < 2.0, "rifle right arm aims (%.1f/%.1f deg)" % [rad_to_deg(ar.x), rad_to_deg(fr.x)])
	_check(absf(rad_to_deg(al.x) - 38.0) < 2.0 and absf(rad_to_deg(fl.x) - 75.0) < 2.0, "rifle left arm braces (%.1f/%.1f deg)" % [rad_to_deg(al.x), rad_to_deg(fl.x)])
	_check(((j["leg_left"] as Node3D).rotation as Vector3).is_equal_approx(base_legs[0]) and ((j["leg_right"] as Node3D).rotation as Vector3).is_equal_approx(base_legs[1]), "rifle handling leaves legs on base locomotion")
	# Idempotence: re-applying handling changes nothing (no double-transform).
	var before := [ar, fr, al, fl]
	ma._apply_handling(10.0, null, rifle)
	await get_tree().process_frame
	_check(((j["arm_right"] as Node3D).rotation as Vector3).is_equal_approx(before[0]), "handling re-apply is idempotent")
	# Gun stability across sprint frames: forearm holds while legs cycle.
	var gun_vals: Array = []
	var leg_vals: Array = []
	for f in [0, 10, 20, 30, 40]:
		clip.cursor = float(f)
		clip.apply_to_joints(j, _bases(j))
		ma._apply_handling(10.0, null, rifle)
		await get_tree().process_frame
		gun_vals.append(((j["forearm_right"] as Node3D).rotation as Vector3).x)
		leg_vals.append(((j["leg_left"] as Node3D).rotation as Vector3).x)
		print("WPNLAYER pose f=%d gunForearm=%.3f legL=%.3f" % [f, gun_vals[-1], leg_vals[-1]])
	var gun_range: float = gun_vals.max() - gun_vals.min()
	var leg_range: float = leg_vals.max() - leg_vals.min()
	_check(gun_range < 0.02, "rifle forearm stable across sprint (range %.4f)" % gun_range)
	_check(leg_range > 0.10, "legs still cycle under rifle hold (range %.3f)" % leg_range)
	mech.queue_free()
	await get_tree().process_frame


# --- C. heavy weapon sprint ----------------------------------------------------------
func _test_heavy(scene: PackedScene, clip: MechaJsonClip) -> void:
	var mech := _build_mech(scene)
	await get_tree().process_frame
	var ma = mech.get_node_or_null("MechaAnimation")
	var j := _joints(mech)
	clip.cursor = 20.0
	clip.apply_to_joints(j, _bases(j))
	await get_tree().process_frame
	var base_body: Vector3 = (j["body"] as Node3D).rotation
	var base_leg: Vector3 = (j["leg_left"] as Node3D).rotation
	ma._apply_handling(10.0, null, _pile())
	await get_tree().process_frame
	var ar: Vector3 = (j["arm_right"] as Node3D).rotation
	var fr: Vector3 = (j["forearm_right"] as Node3D).rotation
	var al: Vector3 = (j["arm_left"] as Node3D).rotation
	_check(absf(rad_to_deg(ar.x) - 40.0) < 2.0 and absf(rad_to_deg(fr.x) - 55.0) < 2.0, "heavy braces right arm (%.1f/%.1f)" % [rad_to_deg(ar.x), rad_to_deg(fr.x)])
	_check(absf(rad_to_deg(al.x) - 40.0) < 2.0, "heavy braces left arm (%.1f)" % rad_to_deg(al.x))
	_check(((j["body"] as Node3D).rotation as Vector3).is_equal_approx(base_body), "heavy handling leaves torso on locomotion")
	_check(((j["leg_left"] as Node3D).rotation as Vector3).is_equal_approx(base_leg), "heavy handling leaves legs on locomotion")
	mech.queue_free()
	await get_tree().process_frame


# --- D. frame x weapon composition ------------------------------------------------------
func _test_frame_weapon_composition(scene: PackedScene, clip: MechaJsonClip) -> void:
	var mechs := {}
	for vid in ["standard", "heavy", "extended"]:
		mechs[vid] = _build_mech(scene, vid)
	await get_tree().process_frame
	await get_tree().process_frame
	var rifle := _rifle()
	var arm_pose := {}
	for vid in ["standard", "heavy", "extended"]:
		var m: Node3D = mechs[vid]
		var ma = m.get_node_or_null("MechaAnimation")
		var j := _joints(m)
		clip.cursor = 20.0
		clip.apply_to_joints(j, _bases(j))
		ma._apply_handling(10.0, null, rifle)
		await get_tree().process_frame
		arm_pose[vid] = [(j["arm_right"] as Node3D).rotation, (j["forearm_right"] as Node3D).rotation, (j["arm_left"] as Node3D).rotation]
	_check((arm_pose["heavy"][0] as Vector3).is_equal_approx(arm_pose["standard"][0]), "heavy shares rifle arm pose with standard")
	_check((arm_pose["extended"][1] as Vector3).is_equal_approx(arm_pose["standard"][1]), "extended shares rifle forearm pose with standard")
	# Mounts still follow their own variant pivots (variant-aware, not hardcoded).
	var w := WeaponPart.new()
	var mounts := {}
	for vid in ["standard", "heavy", "extended"]:
		mounts[vid] = WeaponVisualFactory.mount_hand(mechs[vid], "left", w, "CompMount")
	_check(not (mounts["heavy"] as Node3D).global_position.is_equal_approx((mounts["standard"] as Node3D).global_position), "heavy mount follows heavy pivot (not standard position)")
	_check(((mounts["extended"] as Node3D).get_parent() as Node3D).name == "ForearmLeft", "extended mount stays pivot-parented")
	for vid in ["standard", "heavy", "extended"]:
		(mechs[vid] as Node3D).queue_free()
	await get_tree().process_frame


# --- F. priority chain: handling -> melee swing owns -> handling reasserts ----------
func _test_priority_chain(scene: PackedScene, clip: MechaJsonClip) -> void:
	var mech := _build_mech(scene)
	await get_tree().process_frame
	var ma = mech.get_node_or_null("MechaAnimation")
	var j := _joints(mech)
	var rifle := _rifle()
	clip.cursor = 20.0
	clip.apply_to_joints(j, _bases(j))
	ma._apply_handling(10.0, null, rifle)
	await get_tree().process_frame
	var hold: Vector3 = (j["arm_right"] as Node3D).rotation
	_check(absf(rad_to_deg(hold.x) - 57.0) < 2.0, "chain starts at rifle hold")
	# Melee swing begins: handling must yield, animator owns the arm.
	var animator = ma.get("action_animator")
	_check(animator != null and animator.play_af_melee("right", 1), "melee swing starts")
	ma._apply_handling(10.0, null, rifle)
	await get_tree().process_frame
	_check(absf(float(ma.get("_handling_r"))) < 0.01, "handling yields during melee swing")
	animator.update(0.25)
	animator.apply_to_joints(ma._build_joints_dict())
	await get_tree().process_frame
	var swing: Vector3 = (j["arm_right"] as Node3D).rotation
	_check((swing - hold).length() > 0.09, "melee swing owns the arm (moved %.3f rad off hold)" % (swing - hold).length())
	# Swing ends: handling reasserts the hold.
	animator.anim_time = animator.anim_length
	animator.update(0.5)
	_check(not animator.is_melee_active(), "swing completes")
	ma._apply_handling(10.0, null, rifle)
	await get_tree().process_frame
	var back: Vector3 = (j["arm_right"] as Node3D).rotation
	_check((back - hold).length() < 0.06, "rifle hold reasserts after swing")
	mech.queue_free()
	await get_tree().process_frame
