extends Node3D
## TEMPORARY runtime audit for a908e97 (DELETE AFTER VERIFICATION).
## Exercises live mech + live WeaponManager: grip, holster, recoil impulse,
## frame comparison, shoulder mounts, animator, locomotion, aim range.

const WM = preload("res://scripts/mecha/weapon_manager.gd")

var _fails := 0
var _checks := 0
var _mech: Node = null
var _wm: Node = null


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RTAUDIT OK: " + name)
	else:
		_fails += 1
		printerr("RTAUDIT FAIL: " + name)


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _mk(overrides: Dictionary) -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_name = str(overrides.get("weapon_name", "Audit Gun"))
	w.weapon_type = int(overrides.get("weapon_type", WeaponPart.WeaponType.BEAM_RIFLE))
	w.weight = float(overrides.get("weight", 5.0))
	w.recoil_force = float(overrides.get("recoil_force", 0.0))
	w.two_handed = bool(overrides.get("two_handed", false))
	w.power_required = float(overrides.get("power_required", 0.0))
	w.arm_load = float(overrides.get("arm_load", 0.0))
	w.stability_requirement = float(overrides.get("stability_requirement", 0.0))
	return w


func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.5, 6)
	add_child(cam)
	cam.current = true
	cam.look_at(Vector3(0, 1.5, 0))

	var pack: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_mech = pack.instantiate()
	add_child(_mech)
	_wm = WM.new()
	_wm.name = "WeaponManager"
	_mech.add_child(_wm)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var anim = _mech.get_node_or_null("MechaAnimation")
	var combat = _mech.get_node_or_null("MechaCombat")
	_check(anim != null and combat != null, "live mech has MechaAnimation + MechaCombat")

	# TEST A — light weapon ------------------------------------------------
	var light := _mk({})
	_wm.left_hand = light
	var ha: Dictionary = _wm.get_handling("left")
	_check(str(ha.get("grip_mode")) == "ONE_HAND", "A: light weapon live grip ONE_HAND")
	var mlight = WeaponVisualFactory.mount_hand(_mech, "left", light, "AuditLight")
	_check(mlight != null and mlight.get_parent() == _mech.get_node("ArmLeft/ForearmLeft"), "A: light mount parented under ForearmLeft")
	var muz = WeaponVisualFactory.find_muzzle_node(mlight)
	_check(muz != null and _finite(muz.global_position), "A: muzzle exists + finite")
	_check(_finite(mlight.global_transform.origin), "A: mount transform finite")

	# TEST B — heavy weapon holsters support hand ---------------------------
	var heavy := _mk({"weapon_name": "Audit Anchor", "arm_load": 99999.0})
	var pea := _mk({"weapon_name": "Audit Pea"})
	_wm.left_hand = heavy
	_wm.right_hand = pea
	_wm.carry.clear()
	_check(_wm.weapon_needs_both_hands(heavy, "left"), "B: heavy live grip needs both hands")
	_wm._enforce_two_hand_grip()
	_check(_wm.right_hand == null and _wm.carry.size() == 1, "B: support hand holstered to carry (capability-driven)")
	_wm.left_hand = light
	_wm.right_hand = null
	_wm.carry.clear()

	# TEST D — same weapon, different frame capability ----------------------
	var mid := _mk({"weapon_name": "Audit Mid", "arm_load": 20.0})
	_wm.left_hand = mid
	var p0: float = GlobalData.get_arm_power("left")
	var g0: String = str((_wm.get_handling("left") as Dictionary).get("grip_mode"))
	GlobalData.weapons.equipped_frames["arm_left"] = {"carry_bonus": 30.0}
	var p1: float = GlobalData.get_arm_power("left")
	var g1: String = str((_wm.get_handling("left") as Dictionary).get("grip_mode"))
	_check(p1 > p0, "D: injected frame raises arm power (%.1f → %.1f)" % [p0, p1])
	_check(g0 == "TWO_HAND" and g1 == "ONE_HAND", "D: same weapon flips TWO_HAND → ONE_HAND (got %s → %s)" % [g0, g1])
	GlobalData.weapons.equipped_frames.erase("arm_left")

	# TEST C — live recoil impulse vs resistance -----------------------------
	_check(absf(FrameSystem.get_total_recoil_resistance()) < 0.0001, "C: baseline resistance is 0")
	var rail := _mk({"weapon_name": "Audit Rail", "weapon_type": WeaponPart.WeaponType.RAILGUN, "recoil_force": 22.0})
	_mech.set("recoil_vector", Vector3.ZERO)
	_wm._apply_recoil(rail)
	var l0: float = (_mech.get("recoil_vector") as Vector3).length()
	_check(l0 > 1.0, "C: live railgun impulse visible (len=%.2f)" % l0)
	GlobalData.weapons.equipped_frames["arm_left"] = {"carry_bonus": 0.0, "recoil_resistance": 0.5}
	GlobalData.weapons.equipped_frames["arm_right"] = {"carry_bonus": 0.0, "recoil_resistance": 0.5}
	_check(absf(FrameSystem.get_total_recoil_resistance() - 0.5) < 0.0001, "C: injected resistance reads 0.5")
	_mech.set("recoil_vector", Vector3.ZERO)
	_wm._apply_recoil(rail)
	var l1: float = (_mech.get("recoil_vector") as Vector3).length()
	var ratio: float = l1 / maxf(l0, 0.001)
	_check(l1 < l0 and absf(ratio - 0.5) < 0.08, "C: impulse halves with 0.5 resistance (ratio=%.2f)" % ratio)
	_check(mlight != null and is_instance_valid(mlight) and mlight.get_parent() == _mech.get_node("ArmLeft/ForearmLeft"), "C: weapon stays attached through recoil")
	GlobalData.weapons.equipped_frames.erase("arm_left")
	GlobalData.weapons.equipped_frames.erase("arm_right")
	_mech.set("recoil_vector", Vector3.ZERO)

	# TEST F/H — shoulder mount ------------------------------------------------
	var pod := _mk({"weapon_name": "Audit Pod", "weapon_type": WeaponPart.WeaponType.MISSILE})
	var sm = WeaponVisualFactory.mount_shoulder(_mech, "left", pod, "AuditPod")
	_check(sm != null and sm.get_parent() == _mech.get_node("ArmLeft"), "F: shoulder mount parents under ArmLeft (inherited anim, as designed)")
	var smuz = WeaponVisualFactory.find_muzzle_node(sm)
	_check(smuz != null and _finite(smuz.global_position), "F: shoulder muzzle finite (firing origin intact)")
	_check(_finite(sm.global_transform.origin), "H: shoulder mount transform finite, no drift source")

	# TEST I — live animator ----------------------------------------------------
	_check(anim.get_script() != null, "I: MechaAnimation script loaded (tree health gate)")
	var aa = anim.get("action_animator")
	_check(aa != null, "I: live action_animator present")
	var played: bool = bool(aa.play_af_melee("right", 1)) if aa != null else false
	_check(played and bool(aa.get("is_active")), "I: live AF melee starts on real mech")

	# TEST J — locomotion owns legs ----------------------------------------------
	var leg = _mech.get_node("LegLeft")
	var leg_vals: Array = []
	for i in range(60):
		await get_tree().physics_frame
		leg_vals.append(leg.rotation.x)
		if i == 30:
			_wm.get_handling("left")
			_wm.get_handling("shoulder_left")
	var lo: float = leg_vals[0]
	var hi: float = leg_vals[0]
	for v in leg_vals:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_check((hi - lo) > deg_to_rad(1.0), "J: legs animate under locomotion (range=%.2f deg)" % rad_to_deg(hi - lo))
	var snap_pos: Vector3 = leg.position
	var snap_parent: Node = leg.get_parent()
	for i in range(10):
		_wm.get_handling("left")
		_wm.get_handling("shoulder_left")
	_check(leg.position == snap_pos and leg.get_parent() == snap_parent, "J: handling queries are scene-pure (no teleport/reparent)")
	_check(snap_parent == _mech, "J: leg still owned by mech root hierarchy")

	# TEST K — aim range ------------------------------------------------------------
	_wm.right_hand = _mk({"weapon_name": "Audit Rifle"})
	_wm.fire_right_holding = true
	var arm_r = _mech.get_node("ArmRight")
	var fore_r = _mech.get_node("ArmRight/ForearmRight")
	var all_finite := true
	var raised := false
	var base: Vector3 = _mech.global_position
	for pt in [base + Vector3(0, 1.5, -10), base + Vector3(0, 15, -10), base + Vector3(0, -8, -10), base + Vector3(0, 30, -5), base + Vector3(0, -20, -5)]:
		combat.set("current_aim_point", pt)
		for k in range(12):
			anim._update_aim_arms(0.05)
		if not (_finite(arm_r.rotation) and _finite(fore_r.rotation)):
			all_finite = false
		if pt == base + Vector3(0, 1.5, -10) and arm_r.rotation.x > 0.3:
			raised = true
	_check(all_finite, "K: arms finite across aim pitches (level/up/down/steep)")
	_check(raised, "K: level aim raises gun arm (x=%.2f)" % arm_r.rotation.x)
	_wm.fire_right_holding = false

	# TEST E — mobility resolver output (debug only, no gate) ------------------
	var hmob: Dictionary = _wm.get_handling("left")
	_check(hmob.has("mobility_fire_mode"), "E: mobility_fire_mode present (value=%s, no runtime gate by design)" % str(hmob.get("mobility_fire_mode")))

	# TEST L — integrated heavy run ----------------------------------------
	var stock_rail = load("res://resources/mech/stock/weapon_railgun.tres") as WeaponPart
	_wm.left_hand = stock_rail
	_wm.right_hand = _mk({"weapon_name": "Audit Pea2"})
	_wm.carry.clear()
	_wm._enforce_two_hand_grip()
	_check(_wm.right_hand == null, "L: stock railgun holsters support hand on live mech")
	combat.set("current_aim_point", base + Vector3(0, 1.5, -10))
	_wm.fire_left_holding = true
	for k in range(12):
		anim._update_aim_arms(0.05)
	_mech.set("recoil_vector", Vector3.ZERO)
	_wm._apply_recoil(stock_rail)
	_check((_mech.get("recoil_vector") as Vector3).length() > 1.0, "L: heavy fire kicks live mech")
	var lvals: Array = []
	var lpos0: Vector3 = leg.position
	for i in range(30):
		await get_tree().physics_frame
		lvals.append(leg.rotation.x)
	var llo: float = lvals[0]
	var lhi: float = lvals[0]
	for v in lvals:
		llo = minf(llo, v)
		lhi = maxf(lhi, v)
	# Idle stance holds still while aiming: legs must be STABLE (no jitter,
	# teleport, or reparent) — swing range is covered by TEST J locomotion.
	_check(rad_to_deg(lhi - llo) < 5.0 and leg.position == lpos0 and leg.get_parent() == snap_parent, "L: legs stable during heavy aim+recoil (range=%.2f deg, no teleport)" % rad_to_deg(lhi - llo))
	_check(_finite(arm_r.rotation) and _finite((_mech.get_node("ArmLeft") as Node3D).rotation), "L: both arms coherent, no ownership fight")
	_wm.fire_left_holding = false

	print("RTAUDIT: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("RTAUDIT_FAILED")
		get_tree().quit(1)
	else:
		print("RTAUDIT_PASSED")
		get_tree().quit(0)
