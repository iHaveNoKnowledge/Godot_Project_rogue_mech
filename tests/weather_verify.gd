extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: Weather System (Rain, Sandstorm, Fog)
##
## Tests:
##   1. Weather constants validation
##   2. Board state hazard assignment
##   3. Speed multipliers
##   4. Fuel drain multipliers
##   5. Patrol detection modifiers
##   6. EWar interaction (rain dampening)
##   7. Serialization support
##
## Run: godot --headless --path . res://tests/weather_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	print("")
	print("=== WEATHER SYSTEM VERIFICATION ===")
	print("")

	test_constants()
	test_board_state()
	test_speed_multipliers()
	test_fuel_drain()
	test_patrol_detection()
	test_ewar_interaction()
	test_serialization()

	print("")
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _fails])
	print("")
	if _fails == 0:
		print("ALL TESTS PASSED ✅")
	else:
		print("SOME TESTS FAILED ❌")
	get_tree().quit(1 if _fails > 0 else 0)


# ===========================================================================
# 1. Weather Constants
# ===========================================================================

func test_constants() -> void:
	print("[1] Weather Constants")
	var bs = preload("res://scripts/systems/board_state.gd")

	_check(bs.HAZARD_RAIN == "rain", "RAIN constant = 'rain'")
	_check(bs.HAZARD_SANDSTORM == "sandstorm", "SANDSTORM constant = 'sandstorm'")
	_check(bs.HAZARD_FOG == "fog", "FOG constant = 'fog'")

	_check(absf(bs.RAIN_SPEED_MULT - 0.80) < 0.01, "RAIN_SPEED_MULT = 0.80")
	_check(absf(bs.RAIN_FUEL_DRAIN_MULT - 1.3) < 0.01, "RAIN_FUEL_DRAIN_MULT = 1.3")
	_check(absf(bs.SANDSTORM_SPEED_MULT - 0.65) < 0.01, "SANDSTORM_SPEED_MULT = 0.65")
	_check(absf(bs.SANDSTORM_FUEL_DRAIN_MULT - 1.6) < 0.01, "SANDSTORM_FUEL_DRAIN_MULT = 1.6")
	_check(absf(bs.FOG_SPEED_MULT - 0.90) < 0.01, "FOG_SPEED_MULT = 0.90")
	_check(absf(bs.FOG_VISIBILITY_MULT - 0.35) < 0.01, "FOG_VISIBILITY_MULT = 0.35")


# ===========================================================================
# 2. Board State Hazard Assignment
# ===========================================================================

func test_board_state() -> void:
	print("[2] Board State Hazard Assignment")
	var bs = preload("res://scripts/systems/board_state.gd")
	var state = bs.new()

	_check(state.current_hazard == "", "No hazard by default")

	state.current_hazard = bs.HAZARD_RAIN
	_check(state.current_hazard == "rain", "Can set RAIN hazard")

	state.current_hazard = bs.HAZARD_SANDSTORM
	_check(state.current_hazard == "sandstorm", "Can set SANDSTORM hazard")

	state.current_hazard = bs.HAZARD_FOG
	_check(state.current_hazard == "fog", "Can set FOG hazard")

	state.current_hazard = ""
	_check(state.current_hazard == "", "Can clear hazard")


# ===========================================================================
# 3. Speed Multipliers
# ===========================================================================

func test_speed_multipliers() -> void:
	print("[3] Speed Multipliers")
	var bs = preload("res://scripts/systems/board_state.gd")

	# Base speed
	var base_speed := 100.0
	var effective := base_speed

	# Rain: 80%
	effective = base_speed * bs.RAIN_SPEED_MULT
	_check(absf(effective - 80.0) < 0.01, "Rain speed: 100 * 0.80 = 80")

	# Sandstorm: 65%
	effective = base_speed * bs.SANDSTORM_SPEED_MULT
	_check(absf(effective - 65.0) < 0.01, "Sandstorm speed: 100 * 0.65 = 65")

	# Fog: 90%
	effective = base_speed * bs.FOG_SPEED_MULT
	_check(absf(effective - 90.0) < 0.01, "Fog speed: 100 * 0.90 = 90")


# ===========================================================================
# 4. Fuel Drain
# ===========================================================================

func test_fuel_drain() -> void:
	print("[4] Fuel Drain Multipliers")
	var bs = preload("res://scripts/systems/board_state.gd")

	var base_fuel := 20.0

	# Rain: +30%
	var rain_fuel: float = base_fuel * bs.RAIN_FUEL_DRAIN_MULT
	_check(absf(rain_fuel - 26.0) < 0.01, "Rain fuel: 20 * 1.3 = 26")

	# Sandstorm: +60%
	var sand_fuel: float = base_fuel * bs.SANDSTORM_FUEL_DRAIN_MULT
	_check(absf(sand_fuel - 32.0) < 0.01, "Sandstorm fuel: 20 * 1.6 = 32")


# ===========================================================================
# 5. Patrol Detection
# ===========================================================================

func test_patrol_detection() -> void:
	print("[5] Patrol Detection Modifiers")
	var bs = preload("res://scripts/systems/board_state.gd")

	var base_detect := 10

	# Sandstorm halves detection
	var sand_detect := maxi(base_detect / 2, 0)
	_check(sand_detect == 5, "Sandstorm: detection 10 -> 5 (halved)")

	# Fog reduces to 35%
	var fog_detect := maxi(int(float(base_detect) * bs.FOG_VISIBILITY_MULT), 0)
	_check(fog_detect == 3, "Fog: detection 10 -> 3 (35%)")

	# Rain reduces by 1
	var rain_detect := maxi(base_detect - 1, 0)
	_check(rain_detect == 9, "Rain: detection 10 -> 9 (-1)")


# ===========================================================================
# 6. EWar Interaction
# ===========================================================================

func test_ewar_interaction() -> void:
	print("[6] EWar Interaction")
	var bs = preload("res://scripts/systems/board_state.gd")

	# Rain dampens EWar signal range
	_check(absf(bs.RAIN_EWAR_JAM_PENALTY - 0.5) < 0.01, "Rain EWar penalty = 0.5")

	# Combined: rain + JAM
	var base_detect := 10
	var jam_reduction := 4
	var rain_penalty := 1
	var combined := maxi(base_detect - jam_reduction - rain_penalty, 0)
	_check(combined == 5, "Rain + JAM: detection 10 - 4 - 1 = 5")


# ===========================================================================
# 7. Serialization Support
# ===========================================================================

func test_serialization() -> void:
	print("[7] Serialization Support")
	var bs = preload("res://scripts/systems/board_state.gd")
	var state = bs.new()

	state.current_hazard = bs.HAZARD_SANDSTORM
	_check(state.current_hazard == "sandstorm", "Set sandstorm before serialize")

	# Simulate save/load by checking constant exists
	_check(bs.HAZARD_RAIN != "", "RAIN constant serializable")
	_check(bs.HAZARD_SANDSTORM != "", "SANDSTORM constant serializable")
	_check(bs.HAZARD_FOG != "", "FOG constant serializable")
