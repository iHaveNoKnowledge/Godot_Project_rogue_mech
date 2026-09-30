extends Node
## WEAPON GAMEPLAY CAPABILITY VERIFY - "Can I do this?" decision layer.
##
## Covers (all deterministic, explicit powers dicts unless stated):
##  1. Valid weapon + frame + handling → allowed (FIRE/MELEE/AIM).
##  2. Missing weapon → rejected with no_weapon (all three actions).
##  3. Action not represented by the weapon → action_unsupported.
##  4. Explicit power requirement + no support → frame_insufficient.
##  5. Capability grip + no support / destroyed acting hand → handling_restriction.
##  6. Fixed mounts need no hands; bad mounts rejected.
##  7. Determinism + WeaponManager.get_capability integration (read-only).

const WM = preload("res://scripts/mecha/weapon_manager.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CAPABILITY OK: " + name)
	else:
		_fails += 1
		printerr("CAPABILITY FAIL: " + name)


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
	return w


func _powers(arm: float, leg: float, res: float = 0.0, destroyed: bool = false, support: bool = true) -> Dictionary:
	return {"arm_power": arm, "leg_power": leg, "mech_power": 12.0,
		"recoil_resistance": res, "arm_destroyed": destroyed, "support_usable": support}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var rifle := _mk_weapon({})
	var blade := _mk_weapon({"weapon_name": "Heat Blade", "weapon_type": WeaponPart.WeaponType.MELEE})
	var shield := _mk_weapon({"weapon_name": "Buckler", "weapon_type": WeaponPart.WeaponType.SHIELD})
	var full := _powers(12.0, 12.0)

	# 1. VALID ------------------------------------------------------------
	var fire := WeaponGameplayCapability.query(rifle, "FIRE", "hand", full)
	_check(bool(fire.get("allowed")) and str(fire.get("reason")) == WeaponGameplayCapability.REASON_OK, "rifle FIRE allowed")
	_check(str(fire.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "allowed FIRE reports resolver grip")
	_check(str(fire.get("mount_kind")) == HandlingResolver.MOUNT_HAND, "allowed FIRE reports resolver mount")
	var melee := WeaponGameplayCapability.query(blade, "MELEE", "hand", full)
	_check(bool(melee.get("allowed")) and str(melee.get("reason")) == WeaponGameplayCapability.REASON_OK, "blade MELEE allowed")
	var aim := WeaponGameplayCapability.query(rifle, "AIM", "hand", full)
	_check(bool(aim.get("allowed")) and str(aim.get("reason")) == WeaponGameplayCapability.REASON_OK, "rifle AIM allowed")
	_check(WeaponGameplayCapability.can_fire(rifle, "hand", full).get("allowed") == true, "can_fire wrapper agrees")
	_check(WeaponGameplayCapability.can_melee(blade, "hand", full).get("allowed") == true, "can_melee wrapper agrees")
	_check(WeaponGameplayCapability.can_aim(rifle, "hand", full).get("allowed") == true, "can_aim wrapper agrees")

	# 2. MISSING WEAPON ----------------------------------------------------
	for action in ["FIRE", "MELEE", "AIM"]:
		var r := WeaponGameplayCapability.query(null, action, "hand", full)
		_check(not bool(r.get("allowed")) and str(r.get("reason")) == WeaponGameplayCapability.REASON_NO_WEAPON, "null weapon %s → no_weapon" % action)
	_check(str(WeaponGameplayCapability.query(null, "FIRE", "hand", full).get("grip_mode")) == "", "rejected query carries no grip")

	# 3. ACTION NOT REPRESENTED --------------------------------------------
	_check(str(WeaponGameplayCapability.query(blade, "FIRE", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "blade cannot FIRE")
	_check(str(WeaponGameplayCapability.query(rifle, "MELEE", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "rifle cannot MELEE")
	_check(str(WeaponGameplayCapability.query(blade, "AIM", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "blade cannot AIM")
	for action in ["FIRE", "MELEE", "AIM"]:
		_check(not bool(WeaponGameplayCapability.query(shield, action, "hand", full).get("allowed")), "shield cannot " + action)
	_check(str(WeaponGameplayCapability.query(rifle, "DANCE", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "unknown action unsupported")

	# 4. EXPLICIT FRAME REQUIREMENT -----------------------------------------
	var rail := _mk_weapon({"weapon_name": "Railgun", "weapon_type": WeaponPart.WeaponType.RAILGUN,
		"two_handed": true, "power_required": 999.0})
	var rail_ok := WeaponGameplayCapability.query(rail, "FIRE", "hand", full)
	_check(bool(rail_ok.get("allowed")) and str(rail_ok.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "explicit two-hand + support → allowed TWO_HAND")
	var rail_nosup := WeaponGameplayCapability.query(rail, "FIRE", "hand", _powers(12.0, 12.0, 0.0, false, false))
	_check(not bool(rail_nosup.get("allowed")) and str(rail_nosup.get("reason")) == WeaponGameplayCapability.REASON_FRAME_INSUFFICIENT, "explicit two-hand, support destroyed → frame_insufficient")

	# 5. CAPABILITY GRIP RESTRICTION -----------------------------------------
	var anchor := _mk_weapon({"weapon_name": "Anchor", "arm_load": 99999.0})
	var anchor_ok := WeaponGameplayCapability.query(anchor, "FIRE", "hand", full)
	_check(bool(anchor_ok.get("allowed")) and str(anchor_ok.get("grip_mode")) in [HandlingResolver.GRIP_TWO_HAND, HandlingResolver.GRIP_BRACED], "heavy arm_load + support → allowed two-hand family")
	var anchor_nosup := WeaponGameplayCapability.query(anchor, "FIRE", "hand", _powers(12.0, 12.0, 0.0, false, false))
	_check(not bool(anchor_nosup.get("allowed")) and str(anchor_nosup.get("reason")) == WeaponGameplayCapability.REASON_HANDLING_RESTRICTION, "heavy arm_load, support destroyed → handling_restriction")
	var dead_hand := WeaponGameplayCapability.query(rifle, "FIRE", "hand", _powers(12.0, 12.0, 0.0, true, true))
	_check(not bool(dead_hand.get("allowed")) and str(dead_hand.get("reason")) == WeaponGameplayCapability.REASON_HANDLING_RESTRICTION, "destroyed acting hand → handling_restriction")

	# 6. MOUNTS ---------------------------------------------------------------
	var pod := _mk_weapon({"weapon_name": "Pod", "weapon_type": WeaponPart.WeaponType.MISSILE})
	pod.mount_compatibility = ["hand", "shoulder", "back"] as Array[String]
	var pod_sh := WeaponGameplayCapability.query(pod, "FIRE", "shoulder_left", _powers(1.0, 12.0, 0.0, true, false))
	_check(bool(pod_sh.get("allowed")) and str(pod_sh.get("grip_mode")) == HandlingResolver.GRIP_MOUNTED, "fixed pod fires with destroyed arms (no hand requirement)")
	_check(str(WeaponGameplayCapability.query(rifle, "FIRE", "back", full).get("reason")) == WeaponGameplayCapability.REASON_MOUNT_UNSUPPORTED, "hand-only rifle on back → mount_unsupported")

	# 7. DETERMINISM + MANAGER --------------------------------------------------
	var again := WeaponGameplayCapability.query(rail, "FIRE", "hand", full)
	_check(again == rail_ok, "identical inputs → identical result (deterministic)")
	var wm = WM.new()
	_check(str(wm.get_capability("left", "FIRE").get("reason")) == WeaponGameplayCapability.REASON_NO_WEAPON, "manager empty hand → no_weapon")
	wm.left_hand = rifle
	var mfire: Dictionary = wm.get_capability("left", "FIRE")
	_check(bool(mfire.get("allowed")) and str(mfire.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "manager rifle FIRE allowed")
	_check(str(wm.get_capability("left", "MELEE").get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "manager rifle MELEE unsupported")
	wm.left_hand = blade
	_check(bool(wm.get_capability("left", "MELEE").get("allowed")), "manager blade MELEE allowed")
	_check(str(wm.get_capability("nose", "FIRE").get("reason")) == WeaponGameplayCapability.REASON_NO_WEAPON, "manager unknown slot → no_weapon")
	# Queries are side-effect free: no lifecycle events minted.
	for i in range(10):
		wm.get_capability("left", "MELEE")
		wm.get_capability("left", "FIRE")
	_check(wm.get("_pending_melee").is_empty(), "capability queries mint no pending melee")
	wm.free()

	print("CAPABILITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAPABILITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAPABILITY_TESTS_PASSED")
		get_tree().quit(0)
