extends Node
## WEAPON ACTION GATE VERIFY - "Can it happen right now?" contract.
##
## Covers (deterministic, no production wiring exists yet):
##  GATE-01 valid capability + live runtime → allowed (shape preserved).
##  GATE-02 capability denials flow through with reasons verbatim.
##  GATE-03 operator absent → disabled.
##  GATE-04 destroyed mech → dead for FIRE/MELEE/AIM/GUARD.
##  GATE-05 in-flight attack does not block (restart owned by execution).
##  GATE-06 guard state is not tracked (toggle owned by execution).
##  GATE-07 destroyed acting arm denial flows through.
##  GATE-08 destroyed support arm stays Option B end-to-end.
##  GATE-09 100 queries → identical results, zero mutations.
##  Defaults: missing runtime keys = alive/present; missing capability = denied.

const WM = preload("res://scripts/mecha/weapon_manager.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ACTIONGATE OK: " + name)
	else:
		_fails += 1
		printerr("ACTIONGATE FAIL: " + name)


func _mk_weapon(overrides: Dictionary = {}) -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_name = str(overrides.get("weapon_name", "Test Gun"))
	w.weapon_type = int(overrides.get("weapon_type", WeaponPart.WeaponType.BEAM_RIFLE))
	w.two_handed = bool(overrides.get("two_handed", false))
	w.power_required = float(overrides.get("power_required", 0.0))
	w.arm_load = float(overrides.get("arm_load", 0.0))
	return w


func _powers(arm: float, leg: float, destroyed: bool = false) -> Dictionary:
	return {"arm_power": arm, "leg_power": leg, "mech_power": 12.0,
		"recoil_resistance": 0.0, "arm_destroyed": destroyed}


func _rt(destroyed: bool = false, absent: bool = false) -> Dictionary:
	return {"mech_destroyed": destroyed, "operator_absent": absent}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var rifle := _mk_weapon({})
	var blade := _mk_weapon({"weapon_name": "Blade", "weapon_type": WeaponPart.WeaponType.MELEE})
	var shield := _mk_weapon({"weapon_name": "Buckler", "weapon_type": WeaponPart.WeaponType.SHIELD})
	var rail := _mk_weapon({"weapon_name": "Railgun", "weapon_type": WeaponPart.WeaponType.RAILGUN,
		"two_handed": true, "power_required": 999.0})
	var full := _powers(12.0, 12.0)
	var alive := _rt(false, false)

	# GATE-01 valid capability + live runtime → allowed, shape preserved.
	var cap_fire: Dictionary = WeaponGameplayCapability.query(rifle, "FIRE", "hand", full)
	var g1: Dictionary = WeaponActionGate.query(cap_fire, alive)
	_check(bool(g1.get("allowed")) and str(g1.get("reason")) == WeaponActionGate.REASON_OK, "GATE-01 rifle FIRE allowed")
	_check(str(g1.get("action")) == "FIRE" and str(g1.get("grip_mode")) == "ONE_HAND" and str(g1.get("mount_kind")) == "HAND", "GATE-01 result shape preserved")

	# GATE-02 capability denials flow through verbatim.
	var denials := [
		WeaponGameplayCapability.query(null, "FIRE", "hand", full),
		WeaponGameplayCapability.query(rifle, "MELEE", "hand", full),
		WeaponGameplayCapability.query(rifle, "FIRE", "hand", _powers(12.0, 12.0, true)),
		WeaponGameplayCapability.query(rifle, "FIRE", "back", full),
	]
	for d in denials:
		var g: Dictionary = WeaponActionGate.query(d, alive)
		_check(not bool(g.get("allowed")) and str(g.get("reason")) == str(d.get("reason")), "GATE-02 denial flows through (%s)" % str(d.get("reason")))
		_check(str(g.get("grip_mode")) == str(d.get("grip_mode")), "GATE-02 grip preserved on denial")

	# GATE-03 operator absent → disabled (FIRE + GUARD).
	for action in ["FIRE", "GUARD"]:
		var w: WeaponPart = shield if action == "GUARD" else rifle
		var c: Dictionary = WeaponGameplayCapability.query(w, action, "hand", full)
		var g: Dictionary = WeaponActionGate.query(c, _rt(false, true))
		_check(not bool(g.get("allowed")) and str(g.get("reason")) == WeaponActionGate.REASON_DISABLED, "GATE-03 %s disabled while ejected" % action)

	# GATE-04 destroyed mech → dead for every action.
	var live_caps := {
		"FIRE": WeaponGameplayCapability.query(rifle, "FIRE", "hand", full),
		"MELEE": WeaponGameplayCapability.query(blade, "MELEE", "hand", full),
		"AIM": WeaponGameplayCapability.query(rifle, "AIM", "hand", full),
		"GUARD": WeaponGameplayCapability.query(shield, "GUARD", "hand", full),
	}
	for action in live_caps.keys():
		var g: Dictionary = WeaponActionGate.query(live_caps[action], _rt(true, false))
		_check(not bool(g.get("allowed")) and str(g.get("reason")) == WeaponActionGate.REASON_DEAD, "GATE-04 %s dead while destroyed" % action)

	# GATE-05 in-flight attack does not block: the Gate has no lifecycle
	# opinion (restarts/combos are execution-owned); alive runtime allows.
	var cap_melee: Dictionary = WeaponGameplayCapability.query(blade, "MELEE", "hand", full)
	_check(bool(WeaponActionGate.query(cap_melee, alive).get("allowed")), "GATE-05 MELEE allowed while another swing may be active")

	# GATE-06 guard up/down is not tracked: toggle owned by execution.
	var cap_guard: Dictionary = WeaponGameplayCapability.query(shield, "GUARD", "hand", full)
	_check(bool(WeaponActionGate.query(cap_guard, alive).get("allowed")), "GATE-06 GUARD allowed regardless of guard state")

	# GATE-07 destroyed acting arm denial flows through.
	var dead_hand: Dictionary = WeaponGameplayCapability.query(rifle, "FIRE", "hand", _powers(12.0, 12.0, true))
	var g7: Dictionary = WeaponActionGate.query(dead_hand, alive)
	_check(not bool(g7.get("allowed")) and str(g7.get("reason")) == "handling_restriction", "GATE-07 acting-arm denial flows through")

	# GATE-08 destroyed support stays Option B end-to-end: capability allows
	# the two-hand grip (no support input exists anymore), so the Gate allows.
	var cap_rail: Dictionary = WeaponGameplayCapability.query(rail, "FIRE", "hand", full)
	_check(bool(cap_rail.get("allowed")) and str(cap_rail.get("grip_mode")) == "TWO_HAND", "GATE-08 railgun capability allows TWO_HAND")
	var g8: Dictionary = WeaponActionGate.query(cap_rail, alive)
	_check(bool(g8.get("allowed")) and str(g8.get("grip_mode")) == "TWO_HAND", "GATE-08 Gate allows destroyed-support two-hand")

	# Defaults: missing runtime keys = alive/present; missing capability = denied.
	var g_def: Dictionary = WeaponActionGate.query(cap_fire, {})
	_check(bool(g_def.get("allowed")), "runtime defaults to alive/present")
	var g_nocap: Dictionary = WeaponActionGate.query({}, alive)
	_check(not bool(g_nocap.get("allowed")), "missing capability denies")

	# GATE-09 100 queries → identical results, zero mutations on live objects.
	var wm = WM.new()
	add_child(wm)
	var animator := MechaActionAnimator.new()
	add_child(animator)
	var id0: int = animator.attack_id
	var first: Dictionary = WeaponActionGate.query(cap_fire, alive)
	var stable := true
	for i in range(100):
		var c: Dictionary = WeaponGameplayCapability.query(rifle, "FIRE", "hand", full)
		var g: Dictionary = WeaponActionGate.query(c, alive)
		var gg: Dictionary = WeaponActionGate.query(cap_guard, alive)
		if g != first or not bool(gg.get("allowed")):
			stable = false
	_check(stable, "GATE-09 100 queries deterministic")
	_check(animator.attack_id == id0 and wm.get("_pending_melee").is_empty() and bool(wm.get("shield_active")) == false, "GATE-09 zero gameplay mutation")
	animator.queue_free()
	wm.free()

	print("ACTIONGATE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("ACTIONGATE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_ACTIONGATE_TESTS_PASSED")
		get_tree().quit(0)
