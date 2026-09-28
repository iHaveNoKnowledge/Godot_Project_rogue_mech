extends Node
## AF SWORD MELEE VERIFY - ActionForge one-handed sword clips drive melee.
##
## Covers:
##  1. AF clips load (sword_attack ~1.53s, sword_regular_combo ~3.0s).
##  2. Track maps cover all major joints (arms, forearms, body, head, legs, shins).
##  3. play_af_melee: step 1 -> single slash, step 2/3 -> combo clip.
##  4. play_enemy_af_melee: wind-up pacing spans the telegraph, strike is fast.
##  5. Legacy Mech_00 melee still intact (fallback preserved).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("AF_SWORD OK: " + name)
	else:
		_fails += 1
		printerr("AF_SWORD FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var animator = MechaActionAnimator.new()
	add_child(animator)
	await get_tree().process_frame

	# 1. Clips present with sane lengths.
	_check(MechaActionAnimator.has_af_clips(), "AF sword clips cached")
	var atk: Animation = MechaActionAnimator._cached_anim_library.get(MechaActionAnimator.AF_SWORD_ATTACK, null)
	var combo: Animation = MechaActionAnimator._cached_anim_library.get(MechaActionAnimator.AF_SWORD_COMBO, null)
	_check(atk != null, "AF_SwordAttack cached")
	_check(combo != null, "AF_SwordCombo cached")
	if atk != null:
		_check(atk.length > 1.2 and atk.length < 1.9, "single slash length sane (%.2fs)" % atk.length)
	if combo != null:
		_check(combo.length > 2.5 and combo.length < 3.5, "combo length sane (%.2fs)" % combo.length)

	# 2. Track maps drive every major joint.
	var tmap: Dictionary = MechaActionAnimator._cached_track_maps.get(MechaActionAnimator.AF_SWORD_ATTACK, {})
	for key in ["arm_left", "arm_right", "forearm_left", "forearm_right", "body", "head", "leg_left", "leg_right", "shin_left", "shin_right"]:
		_check(tmap.has(key), "AF track map has " + key)
	var tmap_combo: Dictionary = MechaActionAnimator._cached_track_maps.get(MechaActionAnimator.AF_SWORD_COMBO, {})
	_check(not tmap_combo.is_empty(), "combo track map non-empty")

	# 3. Player one-handed combo sequencing.
	var ok1 := animator.play_af_melee("right", 1)
	_check(ok1, "play_af_melee step 1 returns true")
	_check(animator.current_anim_name == MechaActionAnimator.AF_SWORD_ATTACK, "step 1 plays single slash")
	_check(animator.is_active, "animator active after step 1")
	var ok2 := animator.play_af_melee("right", 2)
	_check(ok2, "play_af_melee step 2 returns true")
	_check(animator.current_anim_name == MechaActionAnimator.AF_SWORD_COMBO, "step 2 plays combo clip")
	var ok3 := animator.play_af_melee("right", 3)
	_check(ok3 and animator.current_anim_name == MechaActionAnimator.AF_SWORD_COMBO, "step 3 stays on combo clip")

	# Combo timing window: chained calls advance the combo index.
	animator.play_af_melee("right", 1)
	animator.play_af_melee("right")
	_check(animator.current_anim_name == MechaActionAnimator.AF_SWORD_COMBO, "chained swing advances to combo")

	# 4. Enemy wind-up (ง้าง) then strike pacing.
	var enemy_anim := MechaActionAnimator.new()
	add_child(enemy_anim)
	var played := enemy_anim.play_enemy_af_melee("right", 0.6)
	_check(played, "play_enemy_af_melee returns true")
	_check(enemy_anim.is_custom_pacing, "enemy AF uses custom wind-up pacing")
	_check(absf(enemy_anim.windup_fraction - 0.40) < 0.001, "wind-up fraction 0.40")
	_check(absf(enemy_anim.strike_speed - 2.40) < 0.001, "strike speed 2.40")
	var expected_windup: float = enemy_anim.anim_length * 0.40 / 0.6
	_check(absf(enemy_anim.windup_speed - expected_windup) < 0.05,
		"wind-up spans telegraph (speed=%.2f expected=%.2f)" % [enemy_anim.windup_speed, expected_windup])
	# Advance a little: during wind-up the clip time moves slowly.
	var t0: float = enemy_anim.anim_time
	enemy_anim.update(0.1)
	var windup_step: float = enemy_anim.anim_time - t0
	_check(windup_step < 0.1 * 1.5, "wind-up advances slowly (step=%.3f)" % windup_step)
	# Jump past the wind-up point: the strike must advance fast.
	enemy_anim.anim_time = enemy_anim.anim_length * 0.41
	enemy_anim.update(0.1)
	var strike_step: float = enemy_anim.anim_time - enemy_anim.anim_length * 0.41
	_check(strike_step > 0.15, "strike accelerates (step=%.3f)" % strike_step)

	# 5. AF clip actually moves the joints (not frozen).
	var joints := _make_joints()
	animator.play_af_melee("right", 1)
	var arm_vals: Array = []
	var body_vals: Array = []
	for i in range(120):
		animator.update(1.0 / 60.0)
		animator.apply_to_joints(joints, 1.0)
		arm_vals.append((joints["arm_right"] as Node3D).rotation.x)
		body_vals.append((joints["body"] as Node3D).rotation.x)
	_check(_range_of(arm_vals) > deg_to_rad(5.0), "sword swing moves right arm (range=%.1f deg)" % rad_to_deg(_range_of(arm_vals)))
	_check(_range_of(body_vals) > deg_to_rad(2.0), "sword swing moves torso (range=%.1f deg)" % rad_to_deg(_range_of(body_vals)))

	# 6. Legacy fallback preserved.
	var legacy := MechaActionAnimator.new()
	add_child(legacy)
	legacy.play_melee("right", 1)
	_check(legacy.current_anim_name == "Mech_Attack1_R", "legacy play_melee still plays Mech_Attack1_R")
	legacy.play_enemy_melee("right", 0.6)
	_check(legacy.current_anim_name == "Mech_Attack1_R", "legacy play_enemy_melee still plays Mech_Attack1_R")

	print("AF_SWORD_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("AF_SWORD_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_AF_SWORD_TESTS_PASSED")
		get_tree().quit(0)


func _make_joints() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var j: Dictionary = {}
	for key in ["head", "body", "arm_left", "arm_right", "forearm_left", "forearm_right",
			"leg_left", "leg_right", "shin_left", "shin_right", "foot_left", "foot_right"]:
		var n := Node3D.new()
		n.name = key
		root.add_child(n)
		j[key] = n
	(j["body"] as Node3D).position.y = 3.0
	return j


func _range_of(a: Array) -> float:
	var lo: float = a[0]
	var hi: float = a[0]
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo
