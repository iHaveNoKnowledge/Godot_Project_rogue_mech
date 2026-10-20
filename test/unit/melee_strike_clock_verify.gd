extends Node
## MELEE STRIKE CLOCK VERIFY (Gate 5C-A) — player melee strike lifecycle.
##
## Drives the REAL MechaActionAnimator headless with explicit fixed-dt
## stepping (no wall clock, no scene): strike-time sanity per combo step,
## exactly-once strike/completion delivery, multi-strike single-update
## handling, and previous-swing retirement on restart.
## Covers: AF sword combo steps 1-3 and legacy Mech_00 swing (assets verified
## present in this repo). Run: godot --headless --path . res://test/unit/melee_strike_clock_verify.tscn

const DT := 1.0 / 60.0

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("STRIKE-CLOCK OK: " + name)
	else:
		_fails += 1
		printerr("STRIKE-CLOCK FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not MechaActionAnimator.has_af_clips():
		printerr("STRIKE-CLOCK FAIL: AF sword clips missing, cannot exercise strike clock")
		get_tree().quit(1)
		return
	_test_step_strike_sanity()
	_test_exactly_once_delivery()
	_test_multi_strike_single_update()
	_test_restart_retires_previous()
	_test_dt_granularity_independence()
	print("MELEE_STRIKE_CLOCK_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MELEE_STRIKE_CLOCK_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MELEE_STRIKE_CLOCK_TESTS_PASSED")
		get_tree().quit(0)


func _new_animator() -> MechaActionAnimator:
	var a := MechaActionAnimator.new()
	add_child(a)
	return a


func _run_to_end(a: MechaActionAnimator, dt: float) -> int:
	# Advances the live swing to completion, returning strikes fired.
	var fired := 0
	var guard := 0
	while a.is_active and guard < 20000:
		a.update(dt)
		while a.poll_strike():
			fired += 1
		guard += 1
	return fired


func _strike_times_sane(a: MechaActionAnimator, label: String) -> void:
	var st: Array = a.strike_times
	_check(not st.is_empty(), label + ": strike_times non-empty")
	var ordered := true
	var prev := -1.0
	for t in st:
		var f := float(t)
		if not is_finite(f) or f < 0.0 or f > a.anim_length or f <= prev:
			ordered = false
		prev = f
	_check(ordered, label + ": strike times finite, ordered, within clip")


# --- 1. Per-step strike sanity (forced steps: no wall-clock combo state). ---
func _test_step_strike_sanity() -> void:
	for step in [1, 2, 3]:
		var a := _new_animator()
		_check(a.play_af_melee("right", step), "step %d: swing starts" % step)
		_strike_times_sane(a, "step %d" % step)
		a.queue_free()
	# Legacy Mech_00 swing (FBX present in repo).
	var b := _new_animator()
	b.play_melee("right", 1)
	_strike_times_sane(b, "legacy step 1")
	b.queue_free()


# --- 2. Each strike fires exactly once; completion fires exactly once. ---
func _test_exactly_once_delivery() -> void:
	var a := _new_animator()
	a.play_af_melee("right", 1)
	var expect: int = (a.strike_times as Array).size()
	var fired := _run_to_end(a, DT)
	_check(fired == expect, "step 1: each strike fired exactly once (%d/%d)" % [fired, expect])
	_check(a.poll_attack_complete(), "step 1: completion fires once")
	_check(not a.poll_attack_complete(), "step 1: completion does not repeat")
	_check(not a.poll_strike(), "step 1: no strikes after completion")
	a.queue_free()


# --- 3. Several strikes crossed in ONE update all fire (combo clip). ---
func _test_multi_strike_single_update() -> void:
	var a := _new_animator()
	a.play_af_melee("right", 1)
	# Jump the whole clip in a single update: every strike moment is crossed.
	a.update(a.anim_length + 1.0)
	var fired := 0
	while a.poll_strike():
		fired += 1
	_check(fired == (a.strike_times as Array).size(),
		"single giant update fires all strikes (%d)" % fired)
	a.queue_free()


# --- 4. Restarting retires the previous swing's pending strikes. ---
func _test_restart_retires_previous() -> void:
	var a := _new_animator()
	a.play_af_melee("right", 1)
	# Advance a little: before the step-1 strike (0.55 clip-s @1.7x).
	a.update(0.1)
	_check(not a.poll_strike(), "pre-restart: step-1 strike not yet crossed")
	# Restart with step 2: the step-1 swing (and its unfired strike) retires.
	a.play_af_melee("right", 2)
	_check(not a.poll_strike(), "post-restart: old pending strike gone")
	var fired := _run_to_end(a, DT)
	var expect: int = (a.strike_times as Array).size()
	_check(fired == expect, "only the new swing's strikes fire (%d/%d)" % [fired, expect])
	a.queue_free()


# --- 5. Delivery is wall-clock independent (dt granularity invariant). ---
func _test_dt_granularity_independence() -> void:
	var counts := []
	for dt in [1.0 / 60.0, 1.0 / 240.0]:
		var a := _new_animator()
		a.play_af_melee("right", 3)
		counts.append(_run_to_end(a, dt))
		a.queue_free()
	_check(int(counts[0]) == int(counts[1]) and int(counts[0]) == 1,
		"step 3: identical delivery at 60Hz and 240Hz (%s)" % str(counts))
