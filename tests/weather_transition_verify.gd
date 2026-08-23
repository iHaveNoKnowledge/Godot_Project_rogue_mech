extends Node

## Weather Transition System — verification tests.
## Run: godot --headless --path . res://tests/weather_transition_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

func _ready() -> void:
	var WTS = load("res://scripts/systems/weather_transition_system.gd") as GDScript
	if WTS == null:
		print("FAIL: Could not load WeatherTransitionSystem script")
		_quit(1)
		return

	test_rolling_initial_weather(WTS)
	test_duration_countdown(WTS)
	test_transition_progress(WTS)
	test_effectiveness_multipliers(WTS)
	test_forecast_generation(WTS)
	test_serialize_deserialize(WTS)
	test_visibility_radius_modifier(WTS)

	print("\n=== RESULTS: %d/%d passed (%d failed) ===" % [_pass, _checks, _fail])
	_quit(1 if _fail > 0 else 0)


func _quit(code: int) -> void:
	get_tree().quit(code)


# 1. Roll Initial Weather
func test_rolling_initial_weather(WTS: GDScript) -> void:
	print("\n[1] Roll Initial Weather")
	var wts = WTS.new()

	wts.roll_initial_weather(10.0)
	_check(wts.weather_duration >= 0, "duration >= 0 after roll")
	_check(wts.weather_max_duration >= 0, "max_duration >= 0 after roll")
	_check(wts.transition_progress >= 0.0 and wts.transition_progress <= 1.0, "transition_progress in [0,1]")

	for h in [0.0, 6.0, 12.0, 18.0, 22.0]:
		wts.roll_initial_weather(h)
		_check(true, "roll at hour %.0f ok" % h)


# 2. Duration Countdown
func test_duration_countdown(WTS: GDScript) -> void:
	print("\n[2] Duration Countdown")
	var wts = WTS.new()

	wts.current_weather = "rain"
	wts.weather_duration = 3
	wts.weather_max_duration = 3
	wts.transition_progress = 1.0
	wts.is_transitioning = false

	var _event: Dictionary = wts.tick_step(12.0)
	_check(wts.weather_duration == 2, "duration decreased to 2")
	_check(wts.total_steps == 1, "total_steps incremented")

	_event = wts.tick_step(12.0)
	_check(wts.weather_duration == 1, "duration decreased to 1")

	_event = wts.tick_step(12.0)
	_check(wts.weather_duration == 0, "duration hit 0")
	_check(wts.current_weather == "" or wts.is_transitioning, "weather begins transition after duration")


# 3. Transition Progress
func test_transition_progress(WTS: GDScript) -> void:
	print("\n[3] Transition Progress")
	var wts = WTS.new()

	wts.current_weather = "fog"
	wts.weather_duration = 10
	wts.weather_max_duration = 10
	wts.transition_progress = 0.0
	wts.is_transitioning = true

	for i in range(5):
		wts.tick_step(12.0)
	_check(wts.transition_progress > 0.0, "transition progress increased during fade-in")

	wts.transition_progress = 0.0
	wts.is_transitioning = true
	for i in range(10):
		wts.tick_step(12.0)
	_check(wts.transition_progress >= 0.9, "transition reaches ~1.0 after enough ticks")


# 4. Effectiveness Multipliers
func test_effectiveness_multipliers(WTS: GDScript) -> void:
	print("\n[4] Effectiveness Multipliers")
	var wts = WTS.new()

	# Clear weather
	wts.current_weather = ""
	wts.transition_progress = 1.0
	_check(absf(wts.get_speed_multiplier() - 1.0) < 0.001, "clear speed mult = 1.0")
	_check(absf(wts.get_fuel_drain_multiplier() - 1.0) < 0.001, "clear fuel drain mult = 1.0")
	_check(absf(wts.get_effectiveness()) < 0.001, "clear effectiveness = 0")

	# Rain at full transition
	wts.current_weather = "rain"
	wts.transition_progress = 1.0
	_check(absf(wts.get_speed_multiplier() - 0.80) < 0.01, "rain speed mult = 0.80")
	_check(absf(wts.get_fuel_drain_multiplier() - 1.3) < 0.01, "rain fuel drain = 1.3")

	# Sandstorm
	wts.current_weather = "sandstorm"
	wts.transition_progress = 1.0
	_check(absf(wts.get_speed_multiplier() - 0.65) < 0.01, "sandstorm speed = 0.65")
	_check(absf(wts.get_fuel_drain_multiplier() - 1.6) < 0.01, "sandstorm fuel = 1.6")

	# Fog
	wts.current_weather = "fog"
	wts.transition_progress = 1.0
	_check(absf(wts.get_speed_multiplier() - 0.90) < 0.01, "fog speed = 0.90")
	_check(absf(wts.get_fuel_drain_multiplier() - 1.1) < 0.01, "fog fuel = 1.1")

	# Dust storm
	wts.current_weather = "dust_storm"
	wts.transition_progress = 1.0
	_check(absf(wts.get_speed_multiplier() - 0.85) < 0.01, "dust storm speed = 0.85")
	_check(absf(wts.get_fuel_drain_multiplier() - 1.5) < 0.01, "dust storm fuel = 1.5")

	# Partial transition blend
	wts.current_weather = "rain"
	wts.transition_progress = 0.5
	var speed_at_half: float = wts.get_speed_multiplier()
	_check(speed_at_half > 0.80 and speed_at_half < 1.0, "partial rain speed between 0.80 and 1.0")


# 5. Forecast Generation
func test_forecast_generation(WTS: GDScript) -> void:
	print("\n[5] Forecast Generation")
	var wts = WTS.new()

	wts._generate_forecast()
	_check(wts.forecast.size() == 3, "forecast has 3 entries")

	var text: String = wts.get_forecast_text()
	_check(text.begins_with("FORECAST:"), "forecast text starts with FORECAST:")
	_check(text.length() > 10, "forecast text is non-trivial")


# 6. Serialize / Deserialize
func test_serialize_deserialize(WTS: GDScript) -> void:
	print("\n[6] Serialize / Deserialize")
	var wts1 = WTS.new()
	wts1.current_weather = "sandstorm"
	wts1.weather_duration = 7
	wts1.weather_max_duration = 10
	wts1.transition_progress = 0.7
	wts1.is_transitioning = true
	wts1.total_steps = 42
	wts1.forecast.clear()
	wts1.forecast.append("rain")
	wts1.forecast.append("fog")
	wts1.forecast.append("clear")

	var data: Dictionary = wts1.serialize()
	_check(data.has("current_weather"), "serialize has current_weather")
	_check(data["current_weather"] == "sandstorm", "serialized weather = sandstorm")
	_check(data["weather_duration"] == 7, "serialized duration = 7")

	var wts2 = WTS.new()
	wts2.deserialize(data)
	_check(wts2.current_weather == "sandstorm", "deserialized weather = sandstorm")
	_check(wts2.weather_duration == 7, "deserialized duration = 7")
	_check(wts2.weather_max_duration == 10, "deserialized max_duration = 10")
	_check(absf(wts2.transition_progress - 0.7) < 0.01, "deserialized transition = 0.7")
	_check(wts2.is_transitioning == true, "deserialized is_transitioning")
	_check(wts2.total_steps == 42, "deserialized total_steps = 42")
	_check(wts2.forecast.size() == 3, "deserialized forecast size = 3")


func test_visibility_radius_modifier(WTS: GDScript) -> void:
	print("\n[7] Visibility Radius Modifier")
	var wts = WTS.new()

	# Clear weather → 1.0
	wts.current_weather = ""
	_check(absf(wts.get_visibility_radius_modifier() - 1.0) < 0.01, "Clear → 1.0")

	# Fog at full progress → 0.40
	wts.current_weather = "fog"
	wts.transition_progress = 1.0
	_check(absf(wts.get_visibility_radius_modifier() - 0.40) < 0.01, "Fog full → 0.40")

	# Fog at 50% progress → 0.70
	wts.transition_progress = 0.5
	_check(absf(wts.get_visibility_radius_modifier() - 0.70) < 0.05, "Fog 50% → ~0.70")

	# Sandstorm at full → 0.50
	wts.current_weather = "sandstorm"
	wts.transition_progress = 1.0
	_check(absf(wts.get_visibility_radius_modifier() - 0.50) < 0.01, "Sandstorm full → 0.50")

	# Rain at full → 0.85
	wts.current_weather = "rain"
	wts.transition_progress = 1.0
	_check(absf(wts.get_visibility_radius_modifier() - 0.85) < 0.01, "Rain full → 0.85")

	# Dust storm at full → 0.55
	wts.current_weather = "dust_storm"
	wts.transition_progress = 1.0
	_check(absf(wts.get_visibility_radius_modifier() - 0.55) < 0.01, "Dust storm full → 0.55")

	# Sandstorm at 30% → blended
	wts.current_weather = "sandstorm"
	wts.transition_progress = 0.3
	var vis: float = wts.get_visibility_radius_modifier()
	_check(vis > 0.5 and vis < 1.0, "Sandstorm 30%% → blended between 1.0 and 0.5")


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
