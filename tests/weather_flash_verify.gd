extends Node

## Weather Transition Flash — verification tests.
## Run: godot --headless --path . res://tests/weather_flash_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

const WTF_SCRIPT = preload("res://scripts/board/weather_transition_flash.gd")

func _ready() -> void:
	print("")
	print("=== WEATHER TRANSITION FLASH VERIFICATION ===")
	print("")

	test_initial_state()
	test_flash_colors()
	test_constants()
	test_animation_timing()
	test_api()

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
	var wtf = WTF_SCRIPT.new()
	add_child(wtf)

	_check(not wtf.is_flash_active(), "No flash active at start")
	_check(wtf.get_flash_weather() == "", "Flash weather empty at start")
	_check(absf(wtf.get_flash_alpha()) < 0.01, "Flash alpha = 0 at start")
	_check(wtf.has_node("WeatherFlashRect"), "WeatherFlashRect child exists")

	wtf.queue_free()


# ===========================================================================
# 2. Flash Colors
# ===========================================================================

func test_flash_colors() -> void:
	print("\n[2] Flash Colors")

	var rain_color = WTF_SCRIPT.WEATHER_FLASH_COLORS.get("rain", Color.BLACK)
	_check(rain_color.r < 0.5, "Rain flash is blue-ish (low R)")
	_check(rain_color.b > 0.5, "Rain flash is blue-ish (high B)")

	var sand_color = WTF_SCRIPT.WEATHER_FLASH_COLORS.get("sandstorm", Color.BLACK)
	_check(sand_color.r > 0.5, "Sandstorm flash is warm (high R)")
	_check(sand_color.g > 0.4, "Sandstorm flash is warm (high G)")

	var fog_color = WTF_SCRIPT.WEATHER_FLASH_COLORS.get("fog", Color.BLACK)
	_check(fog_color.r > 0.3 and fog_color.r < 0.8, "Fog flash is blue-grey")

	var dust_color = WTF_SCRIPT.WEATHER_FLASH_COLORS.get("dust_storm", Color.BLACK)
	_check(dust_color.r > 0.5, "Dust storm flash is warm")

	# Unknown weather returns white
	var wtf = WTF_SCRIPT.new()
	add_child(wtf)
	var unknown = wtf.get_flash_color("unknown_weather")
	_check(unknown == Color.WHITE, "Unknown weather → white flash")
	wtf.queue_free()


# ===========================================================================
# 3. Constants
# ===========================================================================

func test_constants() -> void:
	print("\n[3] Constants")
	_check(absf(WTF_SCRIPT.FLASH_ALPHA - 0.30) < 0.01, "FLASH_ALPHA = 0.30")
	_check(absf(WTF_SCRIPT.FADE_IN_TIME - 0.08) < 0.01, "FADE_IN_TIME = 0.08")
	_check(absf(WTF_SCRIPT.FADE_OUT_TIME - 0.80) < 0.01, "FADE_OUT_TIME = 0.80")


# ===========================================================================
# 4. Animation Timing
# ===========================================================================

func test_animation_timing() -> void:
	print("\n[4] Animation Timing")
	var wtf = WTF_SCRIPT.new()
	add_child(wtf)

	# Force a flash
	wtf.force_flash("rain")
	_check(wtf.is_flash_active(), "Flash active after force_flash")
	_check(wtf.get_flash_weather() == "rain", "Flash weather = rain after force")

	# During fade-in (time < FADE_IN_TIME)
	wtf._flash_time = 0.04  # Half of FADE_IN_TIME
	var alpha_in := wtf._calculate_flash_alpha(0.04)
	_check(alpha_in > 0.0 and alpha_in < WTF_SCRIPT.FLASH_ALPHA, "Fade-in alpha in range")

	# At peak (time = FADE_IN_TIME)
	var alpha_peak := wtf._calculate_flash_alpha(WTF_SCRIPT.FADE_IN_TIME)
	_check(absf(alpha_peak - WTF_SCRIPT.FLASH_ALPHA) < 0.01, "Peak alpha = FLASH_ALPHA")

	# During decay (time > FADE_IN_TIME)
	var alpha_decay := wtf._calculate_flash_alpha(WTF_SCRIPT.FADE_IN_TIME + 0.4)
	_check(alpha_decay < WTF_SCRIPT.FLASH_ALPHA, "Decay alpha < peak")
	_check(alpha_decay > 0.0, "Decay alpha > 0")

	# After full duration
	var alpha_done := wtf._calculate_flash_alpha(2.0)
	_check(alpha_done < 0.01, "Alpha near 0 after 2s")

	wtf.queue_free()


# ===========================================================================
# 5. Public API
# ===========================================================================

func test_api() -> void:
	print("\n[5] Public API")
	var wtf = WTF_SCRIPT.new()
	add_child(wtf)

	_check(not wtf.is_flash_active(), "is_flash_active false initially")
	_check(wtf.get_flash_alpha() >= 0.0, "get_flash_alpha >= 0")

	# get_flash_color for known weather
	var c: Color = wtf.get_flash_color("rain")
	_check(c != Color.WHITE, "get_flash_color('rain') returns non-white")

	wtf.queue_free()


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
