extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: Power Core System (GDD §4.3)
##
## Run: godot --headless --path . res://tests/power_core_system_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0

const PCS = preload("res://scripts/systems/power_core_system.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	GlobalData.reset_run_data()
	print("\n=== PowerCoreSystem Verification (GDD §4.3) ===\n")

	_test_core_ids()
	_test_board_cost_multiplier()
	_test_heat_accumulation_multiplier()
	_test_passive_heat_rate()
	_test_dash_speed_multiplier()
	_test_frame_heat_risk()
	_test_drops_loot()
	_test_hk_attraction()
	_test_fuel_compatibility()
	_test_stats_summary()
	_test_core_switching()
	_test_board_cost_integration()

	print("\n--- RESULT: checks=%d  fails=%d ---\n" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_core_ids() -> void:
	print("[1] Core Class IDs")
	_check(PCS.COMBUSTION == "combustion", "COMBUSTION id")
	_check(PCS.HYBRID == "hybrid", "HYBRID id")
	_check(PCS.ANCIENT == "ancient", "ANCIENT id")


func _test_board_cost_multiplier() -> void:
	print("\n[2] Board Cost Multipliers (GDD §4.3)")
	_check(PCS.board_cost_multiplier("combustion") == 1.0, "combustion: 1.0x")
	_check(PCS.board_cost_multiplier("hybrid") == 0.8, "hybrid: 0.8x (saves 20%)")
	_check(PCS.board_cost_multiplier("ancient") == 0.0, "ancient: 0.0x (free)")


func _test_heat_accumulation_multiplier() -> void:
	print("\n[3] Heat Accumulation Multipliers")
	_check(PCS.heat_accumulation_multiplier("combustion") == 1.0, "combustion: 1.0x")
	_check(PCS.heat_accumulation_multiplier("hybrid") == 1.5, "hybrid: 1.5x (high heat)")
	_check(PCS.heat_accumulation_multiplier("ancient") == 0.3, "ancient: 0.3x (low heat)")
	var bio_hybrid = PCS.heat_accumulation_multiplier("hybrid", true)
	_check(is_equal_approx(bio_hybrid, 1.5 * 1.3), "hybrid + bio-fuel: 1.95x (+30% penalty)")


func _test_passive_heat_rate() -> void:
	print("\n[4] Passive Heat Rate")
	_check(PCS.passive_heat_rate("combustion") == 0.8, "combustion: 0.8/s passive")
	_check(PCS.passive_heat_rate("hybrid") == 0.0, "hybrid: 0.0/s")
	_check(PCS.passive_heat_rate("ancient") == 0.0, "ancient: 0.0/s")


func _test_dash_speed_multiplier() -> void:
	print("\n[5] Dash Speed Multipliers")
	_check(PCS.dash_speed_multiplier("combustion") == 0.9, "combustion: 0.9x (slow)")
	_check(PCS.dash_speed_multiplier("hybrid") == 1.25, "hybrid: 1.25x (fast)")
	_check(PCS.dash_speed_multiplier("ancient") == 1.15, "ancient: 1.15x")


func _test_frame_heat_risk() -> void:
	print("\n[6] Frame Heat Risk")
	_check(not PCS.has_frame_heat_risk("combustion"), "combustion: no frame risk")
	_check(PCS.has_frame_heat_risk("hybrid"), "hybrid: HAS frame risk")
	_check(not PCS.has_frame_heat_risk("ancient"), "ancient: no frame risk")
	_check(PCS.frame_heat_drain_rate(0.5, "hybrid") == 0.0, "hybrid: no drain below 75%")
	_check(PCS.frame_heat_drain_rate(0.8, "hybrid") > 0.0, "hybrid: drain above 75%")
	_check(PCS.frame_heat_drain_rate(0.8, "combustion") == 0.0, "combustion: always 0")


func _test_drops_loot() -> void:
	print("\n[7] Loot Drop Behavior")
	_check(PCS.drops_loot("combustion"), "combustion: drops loot")
	_check(PCS.drops_loot("hybrid"), "hybrid: drops loot")
	_check(not PCS.drops_loot("ancient"), "ancient: does NOT drop loot")


func _test_hk_attraction() -> void:
	print("\n[8] Hunter-Killer Attraction")
	_check(PCS.hk_attraction_multiplier("combustion") == 1.0, "combustion: 1.0x")
	_check(PCS.hk_attraction_multiplier("hybrid") == 1.0, "hybrid: 1.0x")
	_check(PCS.hk_attraction_multiplier("ancient") == 2.0, "ancient: 2.0x (attracts HK)")


func _test_fuel_compatibility() -> void:
	print("\n[9] Fuel Type Compatibility (GDD §4.2)")
	_check(PCS.is_fuel_compatible("combustion", 0), "combustion accepts Crude (0)")
	_check(PCS.is_fuel_compatible("combustion", 2), "combustion accepts Bio (2)")
	_check(not PCS.is_fuel_compatible("combustion", 1), "combustion rejects Refined (1)")
	_check(PCS.is_fuel_compatible("hybrid", 1), "hybrid accepts Refined (1)")
	_check(PCS.is_fuel_compatible("hybrid", 2), "hybrid accepts Bio (2)")
	_check(not PCS.is_fuel_compatible("hybrid", 0), "hybrid rejects Crude (0)")
	_check(PCS.is_fuel_compatible("ancient", 1), "ancient accepts Refined (1)")
	_check(not PCS.is_fuel_compatible("ancient", 0), "ancient rejects Crude (0)")
	_check(not PCS.is_fuel_compatible("ancient", 2), "ancient rejects Bio (2)")


func _test_stats_summary() -> void:
	print("\n[10] Stats Summary")
	var stats = PCS.stats_summary("hybrid")
	_check(stats["id"] == "hybrid", "summary has correct id")
	_check(stats["name"] == "Overclocked Hybrid Core", "summary has display name")
	_check(stats["board_cost_mult"] == 0.8, "summary has board cost mult")
	_check(stats["heat_accum_mult"] == 1.5, "summary has heat accum mult")
	_check(stats["frame_heat_risk"] == true, "summary has frame heat risk")
	_check(stats["drops_loot"] == true, "summary has drops_loot")
	_check(stats["hk_attraction"] == 1.0, "summary has hk attraction")


func _test_core_switching() -> void:
	print("\n[11] Core Switching")
	_check(PCS.get_current_core() == "combustion", "default core is combustion")

	PCS.set_core("hybrid")
	_check(PCS.get_current_core() == "hybrid", "set to hybrid")
	_check(PCS.board_cost_multiplier() == 0.8, "active hybrid has 0.8x board cost")

	PCS.set_core("ancient")
	_check(PCS.get_current_core() == "ancient", "set to ancient")
	_check(PCS.board_cost_multiplier() == 0.0, "active ancient has 0.0x board cost")

	PCS.set_core("combustion")


func _test_board_cost_integration() -> void:
	print("\n[12] Board Cost Integration")
	var fm = GlobalData.fuel
	fm.traversal_mode = "mecha"

	PCS.set_core("combustion")
	var costs_combustion = fm.get_mode_step_cost("road")
	_check(float(costs_combustion["energy"]) == 10.0, "combustion road energy: 10")

	PCS.set_core("hybrid")
	var costs_hybrid = fm.get_mode_step_cost("road")
	_check(float(costs_hybrid["energy"]) == 8.0, "hybrid road energy: 8 (0.8x)")

	PCS.set_core("ancient")
	var costs_ancient = fm.get_mode_step_cost("road")
	_check(float(costs_ancient["energy"]) == 0.0, "ancient road energy: 0 (free)")

	PCS.set_core("combustion")
	fm.traversal_mode = "convoy"
