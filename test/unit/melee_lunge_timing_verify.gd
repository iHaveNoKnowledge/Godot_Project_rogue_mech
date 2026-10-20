extends Node
## MELEE LUNGE TIMING VERIFY (Gate 5C-B) — lunge-duration derivation contract.
##
## Calls the REAL WeaponManager._perform_pile_bunker_lunge_anim with a dummy
## in-tree Node3D and reads the created tween's total time. This pins ONLY
## the duration-derivation rule (strike-derived, clamped, legacy fallback):
## it does NOT prove physical movement syncs with the visible strike.
## Expectations below are hand-derived from the production rule
## (base 0.24s; strike_t > 0.06 -> clamp(strike_t, 0.22, 0.38)).
## Run: godot --headless --path . res://test/unit/melee_lunge_timing_verify.tscn

const WEAPON_MANAGER_PATH := "res://scripts/mecha/weapon_manager.gd"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LUNGE-TIMING OK: " + name)
	else:
		_fails += 1
		printerr("LUNGE-TIMING FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Runtime load (not const preload): matches the fist_punch_verify seam and
	# surfaces a clean diagnostic if the manager's dependency chain is unloadable.
	var wm_script: Script = load(WEAPON_MANAGER_PATH) as Script
	if wm_script == null or not wm_script.can_instantiate():
		printerr("LUNGE-TIMING BLOCKED: WeaponManager script unloadable in this environment; lunge-duration seam unavailable without production refactor")
		get_tree().quit(1)
		return
	var wm: Node3D = (Node3D.new() as Node)
	wm.set_script(wm_script)
	add_child(wm)
	var mecha := Node3D.new()
	add_child(mecha)
	await get_tree().process_frame
	# strike_t -> expected thrust duration (hand-derived, see header).
	var cases := [
		[-1.0, 0.24], # unknown strike: legacy fallback
		[0.0, 0.24], # degenerate strike: fallback
		[0.05, 0.24], # at/below threshold: fallback
		[0.06, 0.24], # boundary is strict (> 0.06 required)
		[0.07, 0.22], # just above threshold, clamped to minimum
		[0.10, 0.22], # clamped to minimum
		[0.22, 0.22], # minimum edge
		[0.30, 0.30], # in-range strike passes through
		[0.38, 0.38], # maximum edge
		[0.50, 0.38], # clamped to maximum
		[2.00, 0.38], # far clamp to maximum
	]
	for c in cases:
		var strike_t := float(c[0])
		var expect := float(c[1])
		mecha.global_position = Vector3.ZERO
		wm._perform_pile_bunker_lunge_anim(mecha, Vector3(0, 0, -1), null, strike_t)
		var tw: Tween = wm.get("_lunge_tween")
		_check(tw != null and is_instance_valid(tw), "strike_t=%.2f: tween created" % strike_t)
		if tw == null or not is_instance_valid(tw):
			continue
		# Tween duration is measured deterministically: step the REAL tween's
		# virtual clock synchronously (no frames advance, no wall time) until
		# it reports finished. Total stepped time equals the thrust duration.
		_check(tw.has_method("custom_step") and tw.has_method("is_running"),
			"strike_t=%.2f: tween exposes manual stepping" % strike_t)
		var total := 0.0
		var guard := 0
		while tw.is_running() and guard < 200:
			tw.custom_step(0.05)
			total += 0.05
			guard += 1
		_check(total >= expect and total < expect + 0.06,
			"strike_t=%.2f: thrust duration %.2f (stepped %.2f)" % [strike_t, expect, total])
		# Stepping the tween drives the dummy along the attack direction to
		# the null-weapon lunge distance (2.9); this also proves the tween
		# moves the combat root it was bound to. Reset per case.
		tw.kill()
		_check(mecha.global_position.is_equal_approx(Vector3(0, 0, -2.9)),
			"strike_t=%.2f: tween drives root along dir to 2.9 (got %s)" % [strike_t, str(mecha.global_position)])
		mecha.global_position = Vector3.ZERO
	wm.queue_free()
	mecha.queue_free()
	print("MELEE_LUNGE_TIMING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MELEE_LUNGE_TIMING_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MELEE_LUNGE_TIMING_TESTS_PASSED")
		get_tree().quit(0)
