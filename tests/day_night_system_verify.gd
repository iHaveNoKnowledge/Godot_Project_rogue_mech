extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: Day/Night System (GDD §3.1)
##
## Run: godot --headless --path . res://tests/day_night_system_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0

const DNS = preload("res://scripts/systems/day_night_system.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	GlobalData.reset_run_data()
	print("\n=== DayNightSystem Verification (GDD §3.1) ===\n")

	_test_initialization()
	_test_daytime_detection()
	_test_nighttime_detection()
	_test_radar_range_modifiers()
	_test_alert_per_step()
	_test_patrol_detect_radius()
	_test_artillery_targeting()
	_test_step_time_cost()
	_test_stealth_bonus()
	_test_time_advancement()
	_test_advance_to_dawn()
	_test_time_string()
	_test_phase_progress()
	_test_save_load()
	_test_integration_reveal()

	print("\n--- RESULT: checks=%d  fails=%d ---\n" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


# --------------------------------------------------------------------------
# 1. Initialization
# --------------------------------------------------------------------------

func _test_initialization() -> void:
	print("[1] Initialization")
	_check(DNS.current_hour() == 8.0, "default hour is 08:00")
	_check(DNS.current_day() == 1, "default day is 1")
	_check(DNS.is_daytime(), "08:00 is daytime")


# --------------------------------------------------------------------------
# 2. Daytime detection
# --------------------------------------------------------------------------

func _test_daytime_detection() -> void:
	print("\n[2] Daytime Detection")
	GlobalData.board.time_hour = 6.0
	_check(DNS.is_daytime(), "06:00 is daytime (dawn)")
	GlobalData.board.time_hour = 12.0
	_check(DNS.is_daytime(), "12:00 is daytime")
	GlobalData.board.time_hour = 17.99
	_check(DNS.is_daytime(), "17:59 is daytime")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 3. Nighttime detection
# --------------------------------------------------------------------------

func _test_nighttime_detection() -> void:
	print("\n[3] Nighttime Detection")
	GlobalData.board.time_hour = 18.0
	_check(DNS.is_nighttime(), "18:00 is nighttime (dusk)")
	GlobalData.board.time_hour = 0.0
	_check(DNS.is_nighttime(), "00:00 is nighttime")
	GlobalData.board.time_hour = 5.99
	_check(DNS.is_nighttime(), "05:59 is nighttime")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 4. Radar range modifiers
# --------------------------------------------------------------------------

func _test_radar_range_modifiers() -> void:
	print("\n[4] Radar Range Modifiers (GDD §3.1)")
	GlobalData.board.time_hour = 12.0
	_check(DNS.radar_range_multiplier() == 1.0, "day: 1.0x radar (full)")
	GlobalData.board.time_hour = 0.0
	_check(DNS.radar_range_multiplier() == 0.5, "night: 0.5x radar (-50%)")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 5. Alert per step
# --------------------------------------------------------------------------

func _test_alert_per_step() -> void:
	print("\n[5] Alert Per Step")
	GlobalData.board.time_hour = 12.0
	_check(DNS.alert_per_step() == 1, "day: +1 alert per step")
	GlobalData.board.time_hour = 0.0
	_check(DNS.alert_per_step() == 0, "night: +0 alert (stealth)")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 6. Patrol detection radius
# --------------------------------------------------------------------------

func _test_patrol_detect_radius() -> void:
	print("\n[6] Patrol Detection Radius")
	GlobalData.board.time_hour = 12.0
	_check(DNS.patrol_detect_radius() == 2, "day: detect radius 2")
	GlobalData.board.time_hour = 0.0
	_check(DNS.patrol_detect_radius() == 1, "night: detect radius 1")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 7. Artillery targeting
# --------------------------------------------------------------------------

func _test_artillery_targeting() -> void:
	print("\n[7] Artillery Targeting")
	GlobalData.board.time_hour = 12.0
	_check(DNS.artillery_targeting_multiplier() == 1.0, "day: 1.0x targeting")
	GlobalData.board.time_hour = 0.0
	_check(DNS.artillery_targeting_multiplier() == 0.5, "night: 0.5x targeting")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 8. Step time cost
# --------------------------------------------------------------------------

func _test_step_time_cost() -> void:
	print("\n[8] Step Time Cost")
	GlobalData.board.time_hour = 12.0
	_check(DNS.step_time_cost() == 1.0, "day: 1 hour per step")
	GlobalData.board.time_hour = 0.0
	_check(DNS.step_time_cost() == 2.0, "night: 2 hours per step")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 9. Stealth bonus
# --------------------------------------------------------------------------

func _test_stealth_bonus() -> void:
	print("\n[9] Stealth Bonus")
	GlobalData.board.time_hour = 12.0
	_check(DNS.stealth_bonus() == 0.0, "day: no stealth bonus")
	GlobalData.board.time_hour = 0.0
	_check(DNS.stealth_bonus() == 0.35, "night: +35% stealth")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 10. Time advancement
# --------------------------------------------------------------------------

func _test_time_advancement() -> void:
	print("\n[10] Time Advancement")
	GlobalData.board.time_hour = 10.0
	var crossed_dawn = DNS.advance_time(2.0)
	_check(is_equal_approx(GlobalData.board.time_hour, 12.0), "advanced 2h: now 12:00")
	_check(not crossed_dawn, "did not cross dawn")

	crossed_dawn = DNS.advance_time(8.0)
	_check(is_equal_approx(GlobalData.board.time_hour, 20.0), "advanced 8h: now 20:00")
	_check(not crossed_dawn, "20:00 is night, no dawn crossing")

	# Cross midnight into new day
	crossed_dawn = DNS.advance_time(6.0)
	_check(is_equal_approx(GlobalData.board.time_hour, 2.0), "wrapped to 02:00")
	_check(crossed_dawn, "crossed midnight into new day")

	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 11. Advance to dawn
# --------------------------------------------------------------------------

func _test_advance_to_dawn() -> void:
	print("\n[11] Advance to Dawn")
	GlobalData.board.time_hour = 22.0
	DNS.advance_to_next_dawn()
	_check(GlobalData.board.time_hour == 6.0, "snapped to 06:00 dawn")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 12. Time string formatting
# --------------------------------------------------------------------------

func _test_time_string() -> void:
	print("\n[12] Time String Formatting")
	GlobalData.board.time_hour = 8.0
	_check(DNS.time_string() == "08:00", "08:00 formatted correctly")
	GlobalData.board.time_hour = 14.5
	_check(DNS.time_string() == "14:30", "14:30 formatted correctly")
	GlobalData.board.time_hour = 0.0
	_check(DNS.time_string() == "00:00", "00:00 formatted correctly")
	GlobalData.board.time_hour = 23.75
	_check(DNS.time_string() == "23:45", "23:45 formatted correctly")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 13. Phase progress
# --------------------------------------------------------------------------

func _test_phase_progress() -> void:
	print("\n[13] Phase Progress")
	GlobalData.board.time_hour = 6.0
	_check(is_equal_approx(DNS.phase_progress(), 0.0), "dawn: 0% through day")
	GlobalData.board.time_hour = 12.0
	_check(is_equal_approx(DNS.phase_progress(), 0.5), "noon: 50% through day")
	GlobalData.board.time_hour = 18.0
	_check(is_equal_approx(DNS.phase_progress(), 0.0), "dusk: 0% through night")
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 14. Save/load
# --------------------------------------------------------------------------

func _test_save_load() -> void:
	print("\n[14] Save/Load")
	GlobalData.board.time_hour = 15.5
	GlobalData.save_run()
	var old_hour := GlobalData.board.time_hour
	GlobalData.board.time_hour = 0.0
	_check(GlobalData.load_run(), "save/load succeeded")
	_check(is_equal_approx(GlobalData.board.time_hour, old_hour), "time_hour restored: %.1f" % old_hour)
	GlobalData.board.time_hour = 8.0


# --------------------------------------------------------------------------
# 15. Integration: reveal radius changes at night
# --------------------------------------------------------------------------

func _test_integration_reveal() -> void:
	print("\n[15] Reveal Radius Integration")
	GlobalData.board.time_hour = 12.0
	var day_mult = DNS.radar_range_multiplier()
	_check(day_mult == 1.0, "day: full reveal radius")

	GlobalData.board.time_hour = 0.0
	var night_mult = DNS.radar_range_multiplier()
	_check(night_mult == 0.5, "night: half reveal radius")

	# Verify the formula: base_radius * mult
	var pilot_base := 3
	var expected_night := maxi(1, int(pilot_base * night_mult))
	_check(expected_night == 1, "pilot night radius: max(1, 3*0.5) = 1")

	var mech_base := 2
	var expected_night_mech := maxi(1, int(mech_base * night_mult))
	_check(expected_night_mech == 1, "mech night radius: max(1, 2*0.5) = 1")

	GlobalData.board.time_hour = 8.0
