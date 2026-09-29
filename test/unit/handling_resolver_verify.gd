extends Node
## HANDLING RESOLVER VERIFY - Frame Capability → Weapon Handling truth tables.
##
## Covers (all deterministic, explicit powers dicts unless stated):
##  1. Grip from capability, not category (low/high arm power, explicit flag).
##  2. Recoil: zero resistance = baseline ×1.0; resistance reduces.
##  3. Mobility tiers + category independence.
##  4. Mounts: fixed bypasses arm load, arm-assisted consumes it, bad mount rejected.
##  5. Melee size/greatsword grip + layer-profile mapping.
##  6. WeaponManager integration (grip enforcement + recoil path intact).
##  7. Legacy baseline preserved (requires_two_hand, stock railgun flag).

const WM = preload("res://scripts/mecha/weapon_manager.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HANDLING OK: " + name)
	else:
		_fails += 1
		printerr("HANDLING FAIL: " + name)


func _mk_weapon(overrides: Dictionary = {}) -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_name = str(overrides.get("weapon_name", "Test Gun"))
	w.weapon_type = int(overrides.get("weapon_type", WeaponPart.WeaponType.BEAM_RIFLE))
	w.weight = float(overrides.get("weight", 5.0))
	w.recoil_force = float(overrides.get("recoil_force", 0.0))
	w.two_handed = bool(overrides.get("two_handed", false))
	w.power_required = float(overrides.get("power_required", 0.0))
	w.arm_load = float(overrides.get("arm_load", 0.0))
	w.stability_requirement = float(overrides.get("stability_requirement", 0.0))
	w.size_class = int(overrides.get("size_class", 0))
	var compat: Array = overrides.get("mount_compatibility", ["hand"])
	var arr: Array[String] = []
	for e in compat:
		arr.append(str(e))
	w.mount_compatibility = arr
	return w


func _powers(arm: float, leg: float, res: float = 0.0) -> Dictionary:
	return {"arm_power": arm, "leg_power": leg, "mech_power": 12.0,
		"recoil_resistance": res, "arm_destroyed": false}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. GRIP ---------------------------------------------------------------
	var heavy := _mk_weapon({"weapon_name": "Heavy Cannon", "arm_load": 30.0})
	var r_low := HandlingResolver.resolve(heavy, "hand", _powers(12.0, 12.0))
	_check(str(r_low.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "low arm power + heavy arm_load → TWO_HAND")
	var r_high := HandlingResolver.resolve(heavy, "hand", _powers(40.0, 12.0))
	_check(str(r_high.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "sufficient arm power → ONE_HAND")
	var plain := _mk_weapon({})
	var r_plain := HandlingResolver.resolve(plain, "hand", _powers(1.0, 1.0))
	_check(str(r_plain.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "default weapon → ONE_HAND even on weak frame")
	var explicit := _mk_weapon({"two_handed": true, "power_required": 999.0})
	var r_exp := HandlingResolver.resolve(explicit, "hand", _powers(12.0, 12.0))
	_check(str(r_exp.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "explicit two_handed flag → TWO_HAND")
	var explicit_ok := _mk_weapon({"two_handed": true, "power_required": 5.0})
	var r_exp_ok := HandlingResolver.resolve(explicit_ok, "hand", _powers(12.0, 12.0))
	_check(str(r_exp_ok.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "explicit flag + enough power → ONE_HAND")
	# Same requirements, different category → same grip (no category hardcode).
	var as_rail := _mk_weapon({"weapon_type": WeaponPart.WeaponType.RAILGUN, "arm_load": 30.0})
	var r_cat := HandlingResolver.resolve(as_rail, "hand", _powers(12.0, 12.0))
	_check(str(r_cat.get("grip_mode")) == str(r_low.get("grip_mode")), "grip identical across weapon categories")

	# 2. RECOIL --------------------------------------------------------------
	_check(absf(HandlingResolver.recoil_multiplier(0.0) - 1.0) < 0.0001, "zero resistance → ×1.0 baseline")
	_check(absf(HandlingResolver.recoil_multiplier(0.25) - 0.75) < 0.0001, "0.25 resistance → ×0.75")
	_check(absf(HandlingResolver.recoil_multiplier(99.0) - 0.4) < 0.0001, "resistance floored at ×0.4")
	var rail := _mk_weapon({"recoil_force": 22.0})
	var r_rail := HandlingResolver.resolve(rail, "hand", _powers(12.0, 12.0))
	_check(str(r_rail.get("recoil_level")) == HandlingResolver.RECOIL_EXTREME, "railgun recoil → EXTREME")
	_check(str(r_plain.get("recoil_level")) == HandlingResolver.RECOIL_MINIMAL, "recoilless weapon → MINIMAL")
	var braced := _mk_weapon({"arm_load": 30.0, "recoil_force": 22.0})
	var r_braced := HandlingResolver.resolve(braced, "hand", _powers(12.0, 12.0))
	_check(str(r_braced.get("grip_mode")) == HandlingResolver.GRIP_BRACED, "two-hand + extreme recoil → BRACED")

	# 3. MOBILITY -------------------------------------------------------------
	_check(str(r_plain.get("mobility_fire_mode")) == HandlingResolver.MOBILITY_SPRINT, "no-requirement weapon → SPRINT (today's unrestricted behavior)")
	var strain := _mk_weapon({"recoil_force": 22.0, "stability_requirement": 5.0})
	var r_stat := HandlingResolver.resolve(strain, "hand", _powers(12.0, 8.0))
	_check(str(r_stat.get("mobility_fire_mode")) == HandlingResolver.MOBILITY_STATIONARY, "low leg + heavy recoil → STATIONARY")
	var r_run := HandlingResolver.resolve(strain, "hand", _powers(12.0, 25.0, 0.5))
	_check(str(r_run.get("mobility_fire_mode")) == HandlingResolver.MOBILITY_SPRINT, "extreme leg + resistance → SPRINT")
	var mid := _mk_weapon({"recoil_force": 4.0, "stability_requirement": 2.0})
	var r_mid := HandlingResolver.resolve(mid, "hand", _powers(12.0, 12.0))
	_check(str(r_mid.get("mobility_fire_mode")) == HandlingResolver.MOBILITY_WALK, "medium strain → WALK (score 8.0)")
	var as_beam := _mk_weapon({"weapon_type": WeaponPart.WeaponType.BEAM_RIFLE, "recoil_force": 4.0, "stability_requirement": 2.0})
	var r_beam := HandlingResolver.resolve(as_beam, "hand", _powers(12.0, 12.0))
	_check(str(r_beam.get("mobility_fire_mode")) == str(r_mid.get("mobility_fire_mode")), "mobility identical across categories")

	# 4. MOUNTS ----------------------------------------------------------------
	var pod := _mk_weapon({"weapon_type": WeaponPart.WeaponType.MISSILE, "arm_load": 999.0})
	var r_pod := HandlingResolver.resolve(pod, "shoulder_left", _powers(1.0, 12.0))
	_check(str(r_pod.get("mount_kind")) == HandlingResolver.MOUNT_FIXED, "missile pod on shoulder → FIXED_MOUNT")
	_check(str(r_pod.get("grip_mode")) == HandlingResolver.GRIP_MOUNTED, "fixed mount bypasses arm load → MOUNTED")
	var blade := _mk_weapon({"weapon_type": WeaponPart.WeaponType.MELEE, "arm_load": 999.0})
	var r_blade_sh := HandlingResolver.resolve(blade, "shoulder_left", _powers(12.0, 12.0))
	_check(str(r_blade_sh.get("mount_kind")) == HandlingResolver.MOUNT_ARM_ASSISTED, "non-missile on shoulder → ARM_ASSISTED")
	_check(str(r_blade_sh.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "arm-assisted mount consumes arm capability")
	var r_hand := HandlingResolver.resolve(plain, "left", _powers(12.0, 12.0))
	_check(bool(r_hand.get("supported")), "hand slot always supported")
	var r_back := HandlingResolver.resolve(plain, "back", _powers(12.0, 12.0))
	_check(not bool(r_back.get("supported")) and str(r_back.get("reason")) == "mount_incompatible", "default weapon on back → rejected")
	var pod_back := _mk_weapon({"weapon_type": WeaponPart.WeaponType.MISSILE})
	pod_back.mount_compatibility = ["hand", "shoulder", "back"] as Array[String]
	var r_pod_back := HandlingResolver.resolve(pod_back, "back", _powers(12.0, 12.0))
	_check(bool(r_pod_back.get("supported")), "compatible pod on back → supported")

	# 5. MELEE + LAYER MAPPING --------------------------------------------------
	var great := _mk_weapon({"weapon_name": "Greatsword", "weapon_type": WeaponPart.WeaponType.MELEE,
		"size_class": HandlingResolver.SIZE_GREATSWORD, "arm_load": 20.0})
	var r_great_low := HandlingResolver.resolve(great, "hand", _powers(12.0, 12.0))
	_check(str(r_great_low.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "greatsword low power → TWO_HAND")
	var r_great_high := HandlingResolver.resolve(great, "hand", _powers(40.0, 12.0))
	_check(str(r_great_high.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "greatsword extreme power → ONE_HAND")
	_check(HandlingResolver.layer_profile(great, HandlingResolver.GRIP_TWO_HAND) == MechaWeaponLayer.WEAPON_SWORD, "melee maps to sword profile")
	var shield := _mk_weapon({"weapon_type": WeaponPart.WeaponType.SHIELD})
	_check(HandlingResolver.layer_profile(shield, HandlingResolver.GRIP_ONE_HAND) == MechaWeaponLayer.WEAPON_NONE, "shield maps to none profile")
	_check(HandlingResolver.layer_profile(plain, HandlingResolver.GRIP_ONE_HAND) == "rifle-primary", "one-hand maps to rifle-primary")
	_check(HandlingResolver.layer_profile(plain, HandlingResolver.GRIP_TWO_HAND) == MechaWeaponLayer.WEAPON_RIFLE, "two-hand maps to rifle")
	_check(HandlingResolver.layer_profile(plain, HandlingResolver.GRIP_BRACED) == MechaWeaponLayer.WEAPON_HEAVY, "braced maps to heavy")

	# 6. MANAGER INTEGRATION ------------------------------------------------------
	var wm = WM.new()
	var anchor := _mk_weapon({"weapon_name": "Anchor", "arm_load": 99999.0})
	wm.left_hand = anchor
	_check(wm.weapon_needs_both_hands(anchor, "left"), "manager enforces capability grip (arm_load 99999 → both hands)")
	var pea := _mk_weapon({"weapon_name": "Pea"})
	wm.left_hand = pea
	_check(not wm.weapon_needs_both_hands(pea, "left"), "manager default weapon → no two-hand grip")
	var h := wm.get_handling("left")
	_check(h is Dictionary and str(h.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "get_handling returns resolved state")
	_check(wm.get_handling("shoulder_left").is_empty(), "get_handling empty shoulder → {}")
	wm.free()

	# 7. LEGACY BASELINE ------------------------------------------------------------
	var stock_rail := load("res://resources/mech/stock/weapon_railgun.tres") as WeaponPart
	_check(stock_rail != null and stock_rail.two_handed, "stock railgun keeps two_handed flag")
	if stock_rail != null:
		_check(stock_rail.requires_two_hand(5.0) and not stock_rail.requires_two_hand(99.0), "requires_two_hand baseline unchanged")
		var r_stock := HandlingResolver.resolve(stock_rail, "hand", _powers(12.0, 12.0))
		_check(str(r_stock.get("grip_mode")) in [HandlingResolver.GRIP_TWO_HAND, HandlingResolver.GRIP_BRACED], "stock railgun on standard frame → two-hand family (as today, braced by EXTREME recoil)")

	print("HANDLING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("HANDLING_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_HANDLING_TESTS_PASSED")
		get_tree().quit(0)
