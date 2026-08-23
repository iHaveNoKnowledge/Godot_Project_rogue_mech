extends Node

## Weather Tile Coloring — verification tests.
## Run: godot --headless --path . res://tests/weather_tile_coloring_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

const WTC_SCRIPT = preload("res://scripts/board/weather_tile_coloring.gd")

func _ready() -> void:
	print("")
	print("=== WEATHER TILE COLORING VERIFICATION ===")
	print("")

	test_initial_state()
	test_tint_constants()
	test_api()
	test_shader_uniforms()

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
	var wtc = WTC_SCRIPT.new()
	add_child(wtc)

	_check(wtc.get_current_weather() == "", "No weather at start")
	_check(absf(wtc.get_current_progress()) < 0.01, "Progress = 0 at start")

	wtc.queue_free()


# ===========================================================================
# 2. Tint Constants
# ===========================================================================

func test_tint_constants() -> void:
	print("\n[2] Tint Constants")

	# Rain tint
	var rain_tint = WTC_SCRIPT.WEATHER_TINTS.get("rain", {})
	_check(not rain_tint.is_empty(), "Rain tint exists")
	_check(absf(rain_tint["strength"] - 0.65) < 0.01, "Rain tint strength = 0.65")
	_check(absf(rain_tint["roughness"] - (-0.25)) < 0.01, "Rain roughness = -0.25 (wet sheen)")

	# Sandstorm tint
	var sand_tint = WTC_SCRIPT.WEATHER_TINTS.get("sandstorm", {})
	_check(not sand_tint.is_empty(), "Sandstorm tint exists")
	_check(absf(sand_tint["strength"] - 0.55) < 0.01, "Sandstorm tint strength = 0.55")
	_check(absf(sand_tint["roughness"] - 0.15) < 0.01, "Sandstorm roughness = 0.15")

	# Fog tint
	var fog_tint = WTC_SCRIPT.WEATHER_TINTS.get("fog", {})
	_check(not fog_tint.is_empty(), "Fog tint exists")
	_check(absf(fog_tint["strength"] - 0.70) < 0.01, "Fog tint strength = 0.70")
	_check(absf(fog_tint["roughness"] - 0.20) < 0.01, "Fog roughness = 0.20")

	# Dust storm tint
	var dust_tint = WTC_SCRIPT.WEATHER_TINTS.get("dust_storm", {})
	_check(not dust_tint.is_empty(), "Dust storm tint exists")
	_check(absf(dust_tint["strength"] - 0.45) < 0.01, "Dust storm tint strength = 0.45")


# ===========================================================================
# 3. Public API
# ===========================================================================

func test_api() -> void:
	print("\n[3] Public API")
	var wtc = WTC_SCRIPT.new()
	add_child(wtc)

	# get_weather_tint
	var rain = wtc.get_weather_tint("rain")
	_check(not rain.is_empty(), "get_weather_tint('rain') returns data")
	var empty = wtc.get_weather_tint("nonexistent")
	_check(empty.is_empty(), "get_weather_tint('nonexistent') returns empty")

	# get_effective_tint_strength (progress=0 → 0)
	wtc._current_progress = 0.0
	_check(absf(wtc.get_effective_tint_strength("rain")) < 0.01, "Effective strength = 0 when progress = 0")

	# get_effective_tint_strength (progress=1 → full)
	wtc._current_progress = 1.0
	_check(absf(wtc.get_effective_tint_strength("rain") - 0.65) < 0.01, "Effective strength = 0.65 at full progress")

	# get_effective_tint_strength (progress=0.5 → half)
	wtc._current_progress = 0.5
	_check(absf(wtc.get_effective_tint_strength("sandstorm") - 0.275) < 0.01, "Effective strength = 0.275 at 50%")

	# refresh
	wtc._current_weather = "rain"
	wtc.refresh()
	_check(wtc.get_current_weather() == "", "refresh() clears current weather")

	wtc.queue_free()


# ===========================================================================
# 4. Shader Uniforms (verify shader has the new parameters)
# ===========================================================================

func test_shader_uniforms() -> void:
	print("\n[4] Shader Uniforms")
	var shader = load("res://shaders/board_terrain_tile.gdshader") as Shader
	_check(shader != null, "Board terrain shader loads")

	# Check the shader source for weather tint parameters
	var code: String = shader.code
	_check(code.find("weather_tint_color") >= 0, "Shader has weather_tint_color uniform")
	_check(code.find("weather_tint_strength") >= 0, "Shader has weather_tint_strength uniform")
	_check(code.find("weather_roughness_mod") >= 0, "Shader has weather_roughness_mod uniform")
	_check(code.find("weather_tint_strength > 0.01") >= 0, "Shader applies weather tint when active")


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
