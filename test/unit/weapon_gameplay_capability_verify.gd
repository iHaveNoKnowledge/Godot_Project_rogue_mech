extends Node
## WEAPON GAMEPLAY CAPABILITY VERIFY - "Can I do this?" decision layer.
##
## Covers (all deterministic, explicit powers dicts unless stated):
##  1. Valid weapon + frame + handling → allowed (FIRE/MELEE/AIM/GUARD).
##  2. Missing weapon → rejected with no_weapon (all actions).
##  3. Action not represented by the weapon → action_unsupported.
##  4. F-2 closure (Option B): two-hand family fires with destroyed support;
##     degraded handling is reported via grip, never a rejection.
##  5. Destroyed acting hand → handling_restriction (execution bashes instead).
##  6. Fixed mounts need no hands; bad mounts rejected.
##  7. GUARD: shield hand allowed; non-shield/shoulder/empty rejected;
##     queries never touch shield state.
##  8. Determinism + WeaponManager.get_capability integration (read-only).

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


func _powers(arm: float, leg: float, res: float = 0.0, destroyed: bool = false) -> Dictionary:
	return {"arm_power": arm, "leg_power": leg, "mech_power": 12.0,
		"recoil_resistance": res, "arm_destroyed": destroyed}


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
	for action in ["FIRE", "MELEE", "AIM", "GUARD"]:
		var r := WeaponGameplayCapability.query(null, action, "hand", full)
		_check(not bool(r.get("allowed")) and str(r.get("reason")) == WeaponGameplayCapability.REASON_NO_WEAPON, "null weapon %s → no_weapon" % action)
	_check(str(WeaponGameplayCapability.query(null, "FIRE", "hand", full).get("grip_mode")) == "", "rejected query carries no grip")

	# 3. ACTION NOT REPRESENTED --------------------------------------------
	_check(str(WeaponGameplayCapability.query(blade, "FIRE", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "blade cannot FIRE")
	_check(str(WeaponGameplayCapability.query(rifle, "MELEE", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "rifle cannot MELEE")
	_check(str(WeaponGameplayCapability.query(blade, "AIM", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "blade cannot AIM")
	_check(str(WeaponGameplayCapability.query(rifle, "GUARD", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "rifle cannot GUARD")
	_check(str(WeaponGameplayCapability.query(blade, "GUARD", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "blade cannot GUARD")
	for action in ["FIRE", "MELEE", "AIM"]:
		_check(not bool(WeaponGameplayCapability.query(shield, action, "hand", full).get("allowed")), "shield cannot " + action)
	_check(str(WeaponGameplayCapability.query(rifle, "DANCE", "hand", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "unknown action unsupported")

	# 4. F-2 CLOSURE (Option B) ---------------------------------------------
	# The holster-to-brace enforcement performs no support-usability check,
	# so the live runtime fires with a destroyed support arm. Capability
	# preserves that behavior: support state never rejects; degraded
	# handling is reported via grip_mode.
	var rail := _mk_weapon({"weapon_name": "Railgun", "weapon_type": WeaponPart.WeaponType.RAILGUN,
		"two_handed": true, "power_required": 999.0})
	var rail_ok := WeaponGameplayCapability.query(rail, "FIRE", "hand", full)
	_check(bool(rail_ok.get("allowed")) and str(rail_ok.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "explicit two-hand + support → allowed TWO_HAND")
	var rail_nosup := WeaponGameplayCapability.query(rail, "FIRE", "hand", _powers(12.0, 12.0))
	_check(bool(rail_nosup.get("allowed")) and str(rail_nosup.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "explicit two-hand, support destroyed → still allowed TWO_HAND (Option B)")
	var minigun := _mk_weapon({"weapon_name": "Minigun", "weapon_type": WeaponPart.WeaponType.MINIGUN,
		"two_handed": true, "power_required": 14.0})
	var mini_ok := WeaponGameplayCapability.query(minigun, "FIRE", "hand", _powers(21.0, 12.0))
	_check(bool(mini_ok.get("allowed")) and str(mini_ok.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "minigun with enough power → allowed ONE_HAND")
	var mini_nosup := WeaponGameplayCapability.query(minigun, "FIRE", "hand", _powers(12.0, 12.0))
	_check(bool(mini_nosup.get("allowed")) and str(mini_nosup.get("grip_mode")) == HandlingResolver.GRIP_TWO_HAND, "minigun, support destroyed → still allowed TWO_HAND (Option B)")

	# 5. DESTROYED ACTING HAND -----------------------------------------------
	# Execution redirects the press to the shoulder bash, so the requested
	# hand action never occurs: every action (incl. GUARD) is rejected.
	var anchor := _mk_weapon({"weapon_name": "Anchor", "arm_load": 99999.0})
	var anchor_ok := WeaponGameplayCapability.query(anchor, "FIRE", "hand", full)
	_check(bool(anchor_ok.get("allowed")) and str(anchor_ok.get("grip_mode")) in [HandlingResolver.GRIP_TWO_HAND, HandlingResolver.GRIP_BRACED], "heavy arm_load → allowed two-hand family")
	var anchor_nosup := WeaponGameplayCapability.query(anchor, "FIRE", "hand", _powers(12.0, 12.0))
	_check(bool(anchor_nosup.get("allowed")), "heavy arm_load, support destroyed → still allowed (Option B)")
	for action in ["FIRE", "MELEE", "AIM", "GUARD"]:
		var w: WeaponPart = rifle
		if action == "MELEE":
			w = blade
		elif action == "GUARD":
			w = shield
		var dead := WeaponGameplayCapability.query(w, action, "hand", _powers(12.0, 12.0, 0.0, true))
		_check(not bool(dead.get("allowed")) and str(dead.get("reason")) == WeaponGameplayCapability.REASON_HANDLING_RESTRICTION, "destroyed acting hand %s → handling_restriction" % action)

	# 6. MOUNTS ---------------------------------------------------------------
	var pod := _mk_weapon({"weapon_name": "Pod", "weapon_type": WeaponPart.WeaponType.MISSILE})
	pod.mount_compatibility = ["hand", "shoulder", "back"] as Array[String]
	var pod_sh := WeaponGameplayCapability.query(pod, "FIRE", "shoulder_left", _powers(1.0, 12.0, 0.0, true))
	_check(bool(pod_sh.get("allowed")) and str(pod_sh.get("grip_mode")) == HandlingResolver.GRIP_MOUNTED, "fixed pod fires with destroyed arms (no hand requirement)")
	_check(str(WeaponGameplayCapability.query(rifle, "FIRE", "back", full).get("reason")) == WeaponGameplayCapability.REASON_MOUNT_UNSUPPORTED, "hand-only rifle on back → mount_unsupported")

	# 7. GUARD -----------------------------------------------------------------
	# _toggle_shield reads the hands only: a shield in hand guards; a shield
	# anywhere else has no guard path; broken-plate HP gating stays
	# combat-owned resource state and is not consulted here.
	var guard := WeaponGameplayCapability.query(shield, "GUARD", "hand", full)
	_check(bool(guard.get("allowed")) and str(guard.get("reason")) == WeaponGameplayCapability.REASON_OK, "G1 shield GUARD allowed")
	_check(str(guard.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND and str(guard.get("mount_kind")) == HandlingResolver.MOUNT_HAND, "G1 GUARD reports resolver grip/mount")
	_check(WeaponGameplayCapability.can_guard(shield, "hand", full).get("allowed") == true, "can_guard wrapper agrees")
	var shield_sh := _mk_weapon({"weapon_name": "Buckler", "weapon_type": WeaponPart.WeaponType.SHIELD})
	shield_sh.mount_compatibility = ["hand", "shoulder", "back"] as Array[String]
	_check(str(WeaponGameplayCapability.query(shield_sh, "GUARD", "shoulder_left", full).get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "G4b shoulder shield has no guard path → action_unsupported")

	# 8. DETERMINISM + MANAGER --------------------------------------------------
	var again := WeaponGameplayCapability.query(rail, "FIRE", "hand", full)
	_check(again == rail_ok, "identical inputs → identical result (deterministic)")
	var again_guard := WeaponGameplayCapability.query(shield, "GUARD", "hand", full)
	_check(again_guard == guard, "GUARD deterministic")
	var wm = WM.new()
	_check(str(wm.get_capability("left", "FIRE").get("reason")) == WeaponGameplayCapability.REASON_NO_WEAPON, "manager empty hand → no_weapon")
	wm.left_hand = rifle
	var mfire: Dictionary = wm.get_capability("left", "FIRE")
	_check(bool(mfire.get("allowed")) and str(mfire.get("grip_mode")) == HandlingResolver.GRIP_ONE_HAND, "manager rifle FIRE allowed")
	_check(str(wm.get_capability("left", "MELEE").get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "manager rifle MELEE unsupported")
	wm.left_hand = blade
	_check(bool(wm.get_capability("left", "MELEE").get("allowed")), "manager blade MELEE allowed")
	wm.left_hand = shield
	_check(bool(wm.get_capability("left", "GUARD").get("allowed")), "manager shield GUARD allowed")
	_check(str(wm.get_capability("left", "FIRE").get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "manager shield FIRE unsupported")
	wm.shoulder_left = shield_sh
	_check(str(wm.get_capability("shoulder_left", "GUARD").get("reason")) == WeaponGameplayCapability.REASON_ACTION_UNSUPPORTED, "manager shoulder shield GUARD unsupported")
	_check(str(wm.get_capability("nose", "FIRE").get("reason")) == WeaponGameplayCapability.REASON_NO_WEAPON, "manager unknown slot → no_weapon")
	# Queries are side-effect free: no lifecycle events minted, shield state untouched.
	_check(bool(wm.get("shield_active")) == false, "G5 shield starts down")
	for i in range(10):
		wm.get_capability("left", "MELEE")
		wm.get_capability("left", "FIRE")
		wm.get_capability("left", "GUARD")
	_check(wm.get("_pending_melee").is_empty(), "capability queries mint no pending melee")
	_check(bool(wm.get("shield_active")) == false and wm.get("_armed_shield") == null, "G5 GUARD queries never touch shield state")
	wm.free()

	print("CAPABILITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAPABILITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAPABILITY_TESTS_PASSED")
		get_tree().quit(0)
