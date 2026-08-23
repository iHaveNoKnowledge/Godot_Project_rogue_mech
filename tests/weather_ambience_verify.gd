extends Node

## Weather Ambience — verification tests.
## Run: godot --headless --path . res://tests/weather_ambience_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

const WA_SCRIPT = preload("res://scripts/board/weather_ambience.gd")

func _ready() -> void:
	print("")
	print("=== WEATHER AMBIENCE VERIFICATION ===")
	print("")

	test_player_creation()
	test_initial_state()
	test_target_volumes()
	test_volume_constants()
	test_serialization()
	test_stop_all()
	test_api()
	test_wind_pitch_constants()

	print("")
	print("=== RESULTS: %d/%d passed (%d failed) ===" % [_pass, _checks, _fail])
	print("")
	if _fail == 0:
		print("ALL TESTS PASSED ✅")
	else:
		print("SOME TESTS FAILED ❌")
	get_tree().quit(1 if _fail > 0 else 0)


# ===========================================================================
# 1. Player Creation
# ===========================================================================

func test_player_creation() -> void:
	print("[1] Player Creation")
	var wa = WA_SCRIPT.new()
	add_child(wa)

	_check(wa.has_node("Weather_rain"), "Weather_rain node exists")
	_check(wa.has_node("Weather_wind"), "Weather_wind node exists")
	_check(wa.has_node("Weather_sandstorm"), "Weather_sandstorm node exists")
	_check(wa.has_node("Weather_fog"), "Weather_fog node exists")

	# All start silent
	var rain: AudioStreamPlayer = wa.get_node("Weather_rain")
	_check(not rain.playing, "Rain starts not playing")
	_check(rain.bus == "SFX", "Rain on SFX bus")

	wa.queue_free()


# ===========================================================================
# 2. Initial State
# ===========================================================================

func test_initial_state() -> void:
	print("\n[2] Initial State")
	var wa = WA_SCRIPT.new()
	add_child(wa)

	_check(wa.get_active_weather() == "", "No active weather at start")
	_check(not wa.is_any_playing(), "No ambience playing at start")

	wa.queue_free()


# ===========================================================================
# 3. Target Volumes
# ===========================================================================

func test_target_volumes() -> void:
	print("\n[3] Target Volumes")
	var wa = WA_SCRIPT.new()
	add_child(wa)

	# No weather → all targets zero
	wa._update_target_volumes("", 1.0)
	_check(wa._target_volumes["rain"] == 0.0, "Rain target = 0 when no weather")
	_check(wa._target_volumes["wind"] == 0.0, "Wind target = 0 when no weather")

	# Rain at full progress
	wa._update_target_volumes("rain", 1.0)
	_check(absf(wa._target_volumes["rain"] - 0.40) < 0.01, "Rain target = 0.40 at full")
	_check(absf(wa._target_volumes["wind"] - 0.08) < 0.01, "Wind bed = 0.08 during rain")

	# Sandstorm at half progress → wind bed kicks in
	wa._update_target_volumes("sandstorm", 0.5)
	_check(absf(wa._target_volumes["sandstorm"] - 0.275) < 0.01, "Sandstorm target = 0.275 at 50%")
	_check(absf(wa._target_volumes["wind"] - 0.04) < 0.01, "Wind bed = 0.04 during sandstorm (not wind type)")

	# Fog at full progress → wind bed kicks in
	wa._update_target_volumes("fog", 1.0)
	_check(absf(wa._target_volumes["fog"] - 0.20) < 0.01, "Fog target = 0.20 at full")
	_check(absf(wa._target_volumes["wind"] - 0.08) < 0.01, "Wind bed = 0.08 during fog")

	# Progress below 0.05 → nothing
	wa._update_target_volumes("rain", 0.03)
	_check(wa._target_volumes["rain"] == 0.0, "Rain target = 0 when progress < 0.05")

	wa.queue_free()


# ===========================================================================
# 4. Volume Constants
# ===========================================================================

func test_volume_constants() -> void:
	print("\n[4] Volume Constants")
	_check(absf(wa_get_const("WEATHER_VOLUMES", "rain") - 0.40) < 0.01, "Rain volume = 0.40")
	_check(absf(wa_get_const("WEATHER_VOLUMES", "wind") - 0.30) < 0.01, "Wind volume = 0.30")
	_check(absf(wa_get_const("WEATHER_VOLUMES", "sandstorm") - 0.55) < 0.01, "Sandstorm volume = 0.55")
	_check(absf(wa_get_const("WEATHER_VOLUMES", "fog") - 0.20) < 0.01, "Fog volume = 0.20")


# ===========================================================================
# 5. Serialization Round-trip
# ===========================================================================

func test_serialization() -> void:
	print("\n[5] Serialization")
	var wa = WA_SCRIPT.new()
	add_child(wa)

	wa._active_weather = "sandstorm"
	var data := wa.serialize()
	_check(data.get("active_weather", "") == "sandstorm", "Serialized active_weather = sandstorm")

	var wa2 = WA_SCRIPT.new()
	add_child(wa2)
	wa2.deserialize(data)
	_check(wa2.get_active_weather() == "sandstorm", "Deserialized active_weather = sandstorm")

	# Empty serialization
	var wa3 = WA_SCRIPT.new()
	add_child(wa3)
	wa3.deserialize({})
	_check(wa3.get_active_weather() == "", "Empty deserialize → no weather")

	wa.queue_free()
	wa2.queue_free()
	wa3.queue_free()


# ===========================================================================
# 6. Stop All
# ===========================================================================

func test_stop_all() -> void:
	print("\n[6] Stop All")
	var wa = WA_SCRIPT.new()
	add_child(wa)

	wa._active_weather = "rain"
	wa._target_volumes["rain"] = 0.4
	wa.stop_all()

	_check(wa.get_active_weather() == "", "Active weather cleared after stop_all")
	_check(wa._target_volumes["rain"] == 0.0, "Rain target zeroed after stop_all")

	wa.queue_free()


# ===========================================================================
# 7. Public API
# ===========================================================================

func test_api() -> void:
	print("\n[7] Public API")
	var wa = WA_SCRIPT.new()
	add_child(wa)

	_check(wa.get_weather_volume("rain") >= 0.0, "get_weather_volume returns >= 0")
	_check(not wa.is_any_playing(), "is_any_playing false initially")

	wa.queue_free()


# ===========================================================================
# 8. Wind Pitch Constants
# ===========================================================================

func test_wind_pitch_constants() -> void:
	print("\n[8] Wind Pitch Constants")
	_check(absf(WA_SCRIPT.WIND_PITCH_BASE - 0.85) < 0.01, "WIND_PITCH_BASE = 0.85")
	_check(absf(WA_SCRIPT.WIND_PITCH_MAX - 1.35) < 0.01, "WIND_PITCH_MAX = 1.35")
	_check(absf(WA_SCRIPT.WIND_PITCH_LFO_SPEED - 0.4) < 0.01, "WIND_PITCH_LFO_SPEED = 0.4")
	_check(absf(WA_SCRIPT.WIND_PITCH_LFO_DEPTH - 0.12) < 0.01, "WIND_PITCH_LFO_DEPTH = 0.12")


# ===========================================================================
# Helpers
# ===========================================================================

func wa_get_const(const_name: String, key: String) -> float:
	var inst = WA_SCRIPT.new()
	var val = inst.get(const_name)
	inst.queue_free()
	if val is Dictionary and val.has(key):
		return float(val[key])
	return -1.0


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
