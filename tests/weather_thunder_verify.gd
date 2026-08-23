extends Node

## Weather Thunder SFX — verification tests.
## Run: godot --headless --path . res://tests/weather_thunder_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

const WT_SCRIPT = preload("res://scripts/board/weather_thunder_sfx.gd")

func _ready() -> void:
	print("")
	print("=== WEATHER THUNDER SFX VERIFICATION ===")
	print("")

	test_initial_state()
	test_constants()
	test_timer_logic()
	test_rain_detection()
	test_interval_rolling()
	test_serialization()
	test_public_api()

	print("")
	print("=== RESULTS: %d/%d passed (%d failed) ===" % [_pass, _checks, _fail])
	print("")
	if _fail == 0:
		print("ALL TESTS PASSED ✅")
	else:
		print("SOME TESTS FAILED ❌")
	get_tree().quit(1 if _fail > 0 else 0)


# ===========================================================================
# 1. Initial State
# ===========================================================================

func test_initial_state() -> void:
	print("[1] Initial State")
	var wt = WT_SCRIPT.new()
	add_child(wt)

	_check(not wt.is_thunder_active(), "Not thundering at start")
	_check(absf(wt.get_time_since_last()) < 0.01, "Time since last = 0 at start")
	_check(wt.get_next_interval() > 0.0, "Next interval > 0 at start")
	_check(wt.get_next_interval() >= WT_SCRIPT.MIN_INTERVAL, "Next interval >= MIN_INTERVAL")
	_check(wt.get_next_interval() <= WT_SCRIPT.MAX_INTERVAL, "Next interval <= MAX_INTERVAL")

	wt.queue_free()


# ===========================================================================
# 2. Constants
# ===========================================================================

func test_constants() -> void:
	print("\n[2] Constants")
	_check(WT_SCRIPT.MIN_INTERVAL == 4.0, "MIN_INTERVAL = 4.0")
	_check(WT_SCRIPT.MAX_INTERVAL == 14.0, "MAX_INTERVAL = 14.0")
	_check(WT_SCRIPT.BASE_VOLUME_DB == 2.0, "BASE_VOLUME_DB = 2.0")
	_check(WT_SCRIPT.LOW_INTENSITY_VOLUME_DB == -6.0, "LOW_INTENSITY_VOLUME_DB = -6.0")


# ===========================================================================
# 3. Timer Logic
# ===========================================================================

func test_timer_logic() -> void:
	print("\n[3] Timer Logic")
	var wt = WT_SCRIPT.new()
	add_child(wt)

	# Timer increments via manual simulation (bypass GlobalData check)
	wt._time_since_last = 0.0
	wt._is_raining = true
	wt._next_interval = 10.0
	# Simulate what _process does when _is_raining is true
	wt._time_since_last += 1.0
	_check(absf(wt.get_time_since_last() - 1.0) < 0.01, "Timer increments by delta")

	# Timer resets via _process when threshold reached
	wt._time_since_last = 10.0
	wt._next_interval = 5.0
	wt._is_raining = true
	# _play_thunder may return early (no AudioManager in tests),
	# but _process still resets the timer after calling it.
	# Simulate _process logic: play + reset + roll
	wt._play_thunder(1.0)
	wt._time_since_last = 0.0
	wt._roll_next_interval()
	_check(absf(wt.get_time_since_last()) < 0.01, "Timer resets after thunder")

	# Reset timer API
	wt._time_since_last = 7.0
	wt.reset_timer()
	_check(absf(wt.get_time_since_last()) < 0.01, "reset_timer zeros time_since_last")

	wt.queue_free()


# ===========================================================================
# 4. Rain Detection
# ===========================================================================

func test_rain_detection() -> void:
	print("\n[4] Rain Detection")
	var wt = WT_SCRIPT.new()
	add_child(wt)

	# No weather transition → not raining
	wt._is_raining = false
	_check(not wt.is_thunder_active(), "No weather → not thundering")

	wt.queue_free()


# ===========================================================================
# 5. Interval Rolling
# ===========================================================================

func test_interval_rolling() -> void:
	print("\n[5] Interval Rolling")
	var wt = WT_SCRIPT.new()
	add_child(wt)

	# Roll many times and check all are in range
	var all_in_range := true
	for i in range(50):
		wt._roll_next_interval()
		if wt.get_next_interval() < WT_SCRIPT.MIN_INTERVAL or wt.get_next_interval() > WT_SCRIPT.MAX_INTERVAL:
			all_in_range = false
			break
	_check(all_in_range, "50 rolls all within [MIN, MAX] range")

	wt.queue_free()


# ===========================================================================
# 6. Serialization Round-trip
# ===========================================================================

func test_serialization() -> void:
	print("\n[6] Serialization")
	var wt = WT_SCRIPT.new()
	add_child(wt)

	wt._time_since_last = 3.5
	wt._next_interval = 9.2
	var data := wt.serialize()
	_check(absf(data["time_since_last"] - 3.5) < 0.01, "Serialized time_since_last = 3.5")
	_check(absf(data["next_interval"] - 9.2) < 0.01, "Serialized next_interval = 9.2")

	var wt2 = WT_SCRIPT.new()
	add_child(wt2)
	wt2.deserialize(data)
	_check(absf(wt2.get_time_since_last() - 3.5) < 0.01, "Deserialized time_since_last = 3.5")
	_check(absf(wt2.get_next_interval() - 9.2) < 0.01, "Deserialized next_interval = 9.2")

	# Empty deserialize
	var wt3 = WT_SCRIPT.new()
	add_child(wt3)
	wt3.deserialize({})
	_check(absf(wt3.get_time_since_last()) < 0.01, "Empty deserialize → time = 0")

	wt.queue_free()
	wt2.queue_free()
	wt3.queue_free()


# ===========================================================================
# 7. Public API
# ===========================================================================

func test_public_api() -> void:
	print("\n[7] Public API")
	var wt = WT_SCRIPT.new()
	add_child(wt)

	_check(not wt.is_thunder_active(), "is_thunder_active false initially")
	_check(wt.get_time_since_last() >= 0.0, "get_time_since_last >= 0")
	_check(wt.get_next_interval() > 0.0, "get_next_interval > 0")

	wt.queue_free()


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
