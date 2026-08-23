extends Node

## Day/Night + Weather Interactions — verification tests.
## Run: godot --headless --path . res://tests/day_night_weather_verify.tscn

var _checks := 0
var _pass := 0
var _fail := 0

func _ready() -> void:
	var WTS = load("res://scripts/systems/weather_transition_system.gd") as GDScript
	if WTS == null:
		print("FAIL: Could not load WeatherTransitionSystem script")
		_quit(1)
		return

	test_rain_night_interaction(WTS)
	test_fog_night_interaction(WTS)
	test_sandstorm_night_interaction(WTS)
	test_day_weather_normal(WTS)
	test_combined_detection_modifier(WTS)
	test_special_interaction_detection(WTS)

	print("\n=== RESULTS: %d/%d passed (%d failed) ===" % [_pass, _checks, _fail])
	_quit(1 if _fail > 0 else 0)


func _quit(code: int) -> void:
	get_tree().quit(code)


# 1. Rain at Night = Harder Stealth (reduced stealth bonus)
func test_rain_night_interaction(WTS: GDScript) -> void:
	print("\n[1] Rain at Night = Harder Stealth")
	var wts = WTS.new()

	wts.current_weather = "rain"
	wts.transition_progress = 1.0

	# Force night time (hour 22)
	GlobalData.board.time_hour = 22.0
	_check(wts._is_nighttime(), "It is nighttime at hour 22")

	# Rain at night should REDUCE stealth below base night value
	var stealth: float = wts.get_combined_stealth_bonus()
	_check(stealth < 0.35, "Rain at night reduces stealth below 35%%")

	# Day rain should have no stealth modifier
	GlobalData.board.time_hour = 12.0
	_check(wts._is_daytime(), "It is daytime at hour 12")
	var day_stealth: float = wts.get_combined_stealth_bonus()
	_check(absf(day_stealth) < 0.01, "Day rain has no stealth bonus")


# 2. Fog at Night = Super Stealth
func test_fog_night_interaction(WTS: GDScript) -> void:
	print("\n[2] Fog at Night = Super Stealth")
	var wts = WTS.new()

	wts.current_weather = "fog"
	wts.transition_progress = 1.0
	GlobalData.board.time_hour = 22.0

	var stealth: float = wts.get_combined_stealth_bonus()
	_check(stealth > 0.35, "Fog at night increases stealth above 35%% base")


# 3. Sandstorm at Night = Extreme Stealth
func test_sandstorm_night_interaction(WTS: GDScript) -> void:
	print("\n[3] Sandstorm at Night = Extreme Stealth")
	var wts = WTS.new()

	wts.current_weather = "sandstorm"
	wts.transition_progress = 1.0
	GlobalData.board.time_hour = 22.0

	var stealth: float = wts.get_combined_stealth_bonus()
	_check(stealth > 0.5, "Sandstorm at night gives extreme stealth (>50%%)")


# 4. Day Weather = Normal (no night synergy)
func test_day_weather_normal(WTS: GDScript) -> void:
	print("\n[4] Day Weather = Normal")
	var wts = WTS.new()
	GlobalData.board.time_hour = 12.0

	# Day fog = small stealth bonus
	wts.current_weather = "fog"
	wts.transition_progress = 1.0
	var fog_day: float = wts.get_combined_stealth_bonus()
	_check(fog_day > 0.0 and fog_day < 0.35, "Day fog gives moderate stealth bonus")

	# Day rain = no stealth bonus
	wts.current_weather = "rain"
	wts.transition_progress = 1.0
	var rain_day: float = wts.get_combined_stealth_bonus()
	_check(absf(rain_day) < 0.01, "Day rain has no stealth modifier")


# 5. Combined Detection Modifier
func test_combined_detection_modifier(WTS: GDScript) -> void:
	print("\n[5] Combined Detection Modifier")
	var wts = WTS.new()
	GlobalData.board.time_hour = 22.0

	# Night rain = worse detection (less negative)
	wts.current_weather = "rain"
	wts.transition_progress = 1.0
	var rain_mod: float = wts.get_combined_detection_modifier()
	_check(rain_mod > -2.0, "Rain at night detection modifier is mild")

	# Night fog = better detection (more negative)
	wts.current_weather = "fog"
	wts.transition_progress = 1.0
	var fog_mod: float = wts.get_combined_detection_modifier()
	_check(fog_mod < -2.0, "Fog at night detection modifier is strong")


# 6. Special Interaction Detection
func test_special_interaction_detection(WTS: GDScript) -> void:
	print("\n[6] Special Interaction Detection")
	var wts = WTS.new()

	# Rain at night = special
	wts.current_weather = "rain"
	GlobalData.board.time_hour = 22.0
	_check(wts.has_special_interaction(), "Rain at night is special interaction")

	# Rain at day = NOT special
	GlobalData.board.time_hour = 12.0
	_check(not wts.has_special_interaction(), "Rain at day is NOT special")

	# Fog at night = special
	wts.current_weather = "fog"
	GlobalData.board.time_hour = 22.0
	_check(wts.has_special_interaction(), "Fog at night is special interaction")

	# Sandstorm at night = special
	wts.current_weather = "sandstorm"
	GlobalData.board.time_hour = 22.0
	_check(wts.has_special_interaction(), "Sandstorm at night is special interaction")

	# Clear = not special
	wts.current_weather = ""
	_check(not wts.has_special_interaction(), "Clear weather is NOT special")


func _check(condition: bool, desc: String) -> void:
	_checks += 1
	if condition:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % desc)
