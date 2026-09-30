extends Node
## GATE INTEGRATION VERIFY - request wiring without behavior change.
##
## Proves the production gate points decide through the real stack
## (WeaponManager._request_gate → Capability → Gate) and change nothing
## when the verdict is ALLOW; DENY paths return before any side effect.
## Destroyed/ejected dispatch is covered live (runtime harness); here the
## free-standing manager (no parent → alive, operator present) proves the
## allow-path and every capability-denial flow-through.

const WM = preload("res://scripts/mecha/weapon_manager.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GATEINT OK: " + name)
	else:
		_fails += 1
		printerr("GATEINT FAIL: " + name)


func _mk_weapon(overrides: Dictionary = {}) -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_name = str(overrides.get("weapon_name", "Test Gun"))
	w.weapon_type = int(overrides.get("weapon_type", WeaponPart.WeaponType.BEAM_RIFLE))
	w.two_handed = bool(overrides.get("two_handed", false))
	w.power_required = float(overrides.get("power_required", 0.0))
	w.arm_load = float(overrides.get("arm_load", 0.0))
	return w


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var wm = WM.new()
	add_child(wm)
	var rifle := _mk_weapon({})
	var blade := _mk_weapon({"weapon_name": "Blade", "weapon_type": WeaponPart.WeaponType.MELEE})
	var shield := _mk_weapon({"weapon_name": "Buckler", "weapon_type": WeaponPart.WeaponType.SHIELD})
	var rail := _mk_weapon({"weapon_name": "Railgun", "weapon_type": WeaponPart.WeaponType.RAILGUN,
		"two_handed": true, "power_required": 999.0})
	var mini := _mk_weapon({"weapon_name": "Minigun", "weapon_type": WeaponPart.WeaponType.MINIGUN,
		"two_handed": true, "power_required": 14.0})

	# ALLOW paths decide through the wired helper (no execution here).
	wm.right_hand = rifle
	var g_fire: Dictionary = wm._request_gate("right", "FIRE")
	_check(bool(g_fire.get("allowed")) and str(g_fire.get("grip_mode")) == "ONE_HAND", "wired rifle FIRE allowed ONE_HAND")
	wm.right_hand = blade
	_check(bool(wm._request_gate("right", "MELEE").get("allowed")), "wired blade MELEE allowed")
	wm.left_hand = shield
	_check(bool(wm._request_gate("left", "GUARD").get("allowed")), "wired shield GUARD allowed")
	wm.left_hand = rail
	var g_rail: Dictionary = wm._request_gate("left", "FIRE")
	_check(bool(g_rail.get("allowed")) and str(g_rail.get("grip_mode")) == "TWO_HAND", "wired railgun FIRE allowed TWO_HAND")
	wm.left_hand = mini
	_check(bool(wm._request_gate("left", "FIRE").get("allowed")), "wired minigun FIRE allowed (Option B support not consulted)")

	# DENY paths preserve capability reasons through the wiring.
	wm.right_hand = blade
	var g_deny: Dictionary = wm._request_gate("right", "FIRE")
	_check(not bool(g_deny.get("allowed")) and str(g_deny.get("reason")) == "action_unsupported", "wired blade FIRE denied action_unsupported")
	wm.right_hand = null
	var g_empty: Dictionary = wm._request_gate("right", "FIRE")
	_check(not bool(g_empty.get("allowed")) and str(g_empty.get("reason")) == "no_weapon", "wired empty hand denied no_weapon")
	var g_noslot: Dictionary = wm._request_gate("nose", "FIRE")
	_check(not bool(g_noslot.get("allowed")), "wired unknown slot denied")

	# The wired gate is side-effect free: 20 mixed decisions change nothing.
	wm.right_hand = rifle
	wm.left_hand = shield
	for i in range(20):
		wm._request_gate("right", "FIRE")
		wm._request_gate("right", "MELEE")
		wm._request_gate("left", "GUARD")
		wm._request_gate("left", "FIRE")
	_check(wm.get("_pending_melee").is_empty() and bool(wm.get("shield_active")) == false, "20 wired decisions mutate nothing")
	wm.free()

	print("GATEINT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("GATEINT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_GATEINT_TESTS_PASSED")
		get_tree().quit(0)
