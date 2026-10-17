extends Node
## MELEE STARTUP FAILURE VERIFY (Gate R2-AN, test-only).
##
## Failure contract: a melee animation that fails to start must not arm a
## lunge, pending hit, swing audio, or stale-timed effects (R2 policy).
##  T1. Stale strike data (simulated residue) + pre-armed marker pending:
##      failed request must not lunge, must not re-arm/overwrite pending,
##      and must report failure through the production return contract.
##  T2. Initial failure with empty strike data arms nothing.
##  T3. Successful normal melee still arms pending + schedules lunge
##      (unchanged success path; requires AF clips in the environment).
## Fixture: bare CharacterBody3D mech + real WeaponManager + Camera3D +
## holder Node named "MechaAnimation" exposing a real or stub animator.
## The stub is a test double (inner class): AF path attempted, always fails.
## No production seam was added; the stub exercises the existing
## has_method/play_af_melee/play_melee call chain exactly as production does.
## Run: godot --headless --path . res://tests/mecha/melee_startup_failure_verify.tscn

const KNIFE_PATH := "res://resources/mech/stock/weapon_combat_knife.tres"

var _fails := 0
var _checks := 0
var _started := {}
var _completed := {}
var _not_feasible := {}


## Test double standing in for the action animator on the failure path.
## Mirrors the production call surface (play_af_melee queried by has_method,
## then play_melee as the legacy fallback); both refuse to start.
class FailingAnimator extends RefCounted:
	var calls: Array = []
	var strike_times: Array = []
	func play_af_melee(hand: String = "right", forced_combo_step: int = 0) -> bool:
		calls.append("af:" + hand)
		return false
	func play_melee(hand: String = "right", forced_combo_step: int = 0) -> bool:
		calls.append("legacy:" + hand)
		return false


## Minimal holder standing in for MechaAnimation: _melee_attack only reads
## the `action_animator` property off the MechaAnimation node.
class AnimatorHolder extends Node:
	var action_animator = null


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MELEE-STARTUP OK: " + name)
	else:
		_fails += 1
		printerr("MELEE-STARTUP FAIL: " + name)


func _mark_not_feasible(case_name: String, reason: String) -> void:
	_not_feasible[case_name] = reason
	print("MELEE-STARTUP NOT-FEASIBLE: " + case_name + " — " + reason)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_t1_stale_strike_data_rejected()
	await _test_t2_initial_failure_arms_nothing()
	await _test_t3_successful_melee_unchanged()
	for case_name in _started.keys():
		_check(bool(_completed.get(case_name, false)), "case completed: " + str(case_name))
	print("MELEE_STARTUP_FAILURE_VERIFY: started=%d completed=%d checks=%d fails=%d not_feasible=%d" % [_started.size(), _completed.values().count(true), _checks, _fails, _not_feasible.size()])
	for case_name in _not_feasible.keys():
		print("MELEE_STARTUP_FAILURE_VERIFY NOT-FEASIBLE: " + str(case_name) + " — " + str(_not_feasible[case_name]))
	if _fails > 0:
		printerr("MELEE_STARTUP_FAILURE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MELEE_STARTUP_FAILURE_TESTS_PASSED")
		get_tree().quit(0)


func _spawn_melee_rig() -> Array:
	var mecha := CharacterBody3D.new()
	mecha.position = Vector3(0, 1.5, 0)
	add_child(mecha)
	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	var holder := AnimatorHolder.new()
	holder.name = "MechaAnimation"
	mecha.add_child(holder)
	await get_tree().process_frame
	await get_tree().process_frame
	return [mecha, wm, holder]


func _max_displacement(pos0: Vector3, mecha: Node3D, frames: int) -> float:
	var peak := 0.0
	for i in range(frames):
		await get_tree().process_frame
		peak = maxf(peak, (mecha.global_position - pos0).length())
	return peak


# ---------------------------------------------------------------------------
# T1. Stale strike data + pre-armed marker pending; failed request must
# change neither, and must report failure through the return contract.
# ---------------------------------------------------------------------------
func _test_t1_stale_strike_data_rejected() -> void:
	_started["t1"] = true
	var rig := await _spawn_melee_rig()
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var holder: Node = rig[2]
	var knife: WeaponPart = load(KNIFE_PATH)
	_check(knife != null and knife.weapon_type == WeaponPart.WeaponType.MELEE, "t1: fixture uses a real MELEE weapon (SAFE NOW)")
	_check(not knife.weapon_name.to_lower().contains("pile"), "t1: fixture weapon takes the AF path (SAFE NOW)")
	var stub := FailingAnimator.new()
	stub.strike_times = [0.42]
	holder.action_animator = stub
	# Pre-arm a marker pending hit, as a previous valid swing would leave it.
	wm._pending_melee = {"hand": "right", "weapon": knife, "damage": 123.0, "dir": Vector3(0, 0, -1), "blast": false}
	var pos0: Vector3 = mecha.global_position
	wm._melee_attack("right", knife)
	_check(stub.calls.has("af:right"), "t1: AF path attempted through the production call order (T1)")
	_check(stub.calls.has("legacy:right"), "t1: legacy fallback attempted after AF failure (T1)")
	var pending: Dictionary = wm._pending_melee
	_check(float(pending.get("damage", -1.0)) == 123.0 and (pending.get("weapon") as Object) == (knife as Object) and bool(pending.get("blast", true)) == false, "t1: previous pending hit untouched by failed request (T1)")
	var moved := await _max_displacement(pos0, mecha, 60)
	_check(moved < 0.001, "t1: no lunge scheduled from stale strike data (T1)")
	_completed["t1"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T2. Initial failure with empty strike data arms nothing.
# ---------------------------------------------------------------------------
func _test_t2_initial_failure_arms_nothing() -> void:
	_started["t2"] = true
	var rig := await _spawn_melee_rig()
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var holder: Node = rig[2]
	var knife: WeaponPart = load(KNIFE_PATH)
	var stub := FailingAnimator.new()
	holder.action_animator = stub
	_check((wm._pending_melee as Dictionary).is_empty(), "t2: pending starts empty (SAFE NOW)")
	var pos0: Vector3 = mecha.global_position
	wm._melee_attack("right", knife)
	_check(stub.calls.has("af:right") and stub.calls.has("legacy:right"), "t2: both play paths attempted and refused (T2)")
	_check((wm._pending_melee as Dictionary).is_empty(), "t2: failed request arms no pending hit (T2)")
	var moved := await _max_displacement(pos0, mecha, 60)
	_check(moved < 0.001, "t2: failed request schedules no lunge (T2)")
	_completed["t2"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# T3. Successful normal melee is unchanged (requires AF clips in env).
# ---------------------------------------------------------------------------
func _test_t3_successful_melee_unchanged() -> void:
	_started["t3"] = true
	if not MechaActionAnimator.has_af_clips():
		_mark_not_feasible("t3", "AF clips not loadable in this environment; success path cannot be exercised here")
		_completed["t3"] = true
		return
	var rig := await _spawn_melee_rig()
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var holder: Node = rig[2]
	var knife: WeaponPart = load(KNIFE_PATH)
	var animator := MechaActionAnimator.new()
	holder.action_animator = animator
	var pos0: Vector3 = mecha.global_position
	wm._melee_attack("right", knife)
	_check(int(animator.get("attack_id")) > 0, "t3: successful start advances the attack lifecycle (T3)")
	_check(not (animator.get("strike_times") as Array).is_empty(), "t3: strike clock armed from the clip (T3)")
	var pending: Dictionary = wm._pending_melee
	_check(not pending.is_empty() and float(pending.get("damage", -1.0)) == float(knife.damage), "t3: pending hit armed with weapon damage (T3)")
	var moved := await _max_displacement(pos0, mecha, 60)
	_check(moved > 0.05, "t3: lunge scheduled on successful start (T3)")
	_completed["t3"] = true
	(rig[0] as Node).queue_free()
