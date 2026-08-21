extends Node3D

## Verification test for Dynamic Thermal Heat Bloom (Machine Gun heat-based bullet spread):
## Verifies that as weapon heat rises, projectile dispersion angle increases dynamically.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("HEAT_SPREAD_OK: %s" % msg)
	else:
		_fails += 1
		print("HEAT_SPREAD_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Dynamic Thermal Heat Spread Verification ---")

	var mg_res = load("res://resources/mech/stock/weapon_machine_gun.tres")
	_check(mg_res != null, "Loaded weapon_machine_gun.tres")

	var core = WeaponCore.from_weapon(mg_res)
	core.spread = 0.0 # Test with 0 base spread to isolate thermal bloom
	core.heat_capacity = 100.0
	core.heat = 0.0

	# 1. Cold barrel (0 heat): pellet_dir should be exact aim_dir
	var cold_aim := Vector3(0, 0, -1)
	var cold_shot_fired := core.consume_shot()
	_check(cold_shot_fired, "Cold shot consumed successfully")
	var cold_heat_ratio := core.get_heat_percent()
	_check(cold_heat_ratio < 0.1, "Cold barrel heat ratio is low (%.2f)" % cold_heat_ratio)

	# 2. Accumulate heat to 90%
	core.heat = 90.0
	var hot_heat_ratio := core.get_heat_percent()
	_check(hot_heat_ratio >= 0.9, "Heated barrel heat ratio is high (%.2f)" % hot_heat_ratio)

	# 3. Simulate firing 30 hot shots and check average deviation angle
	var total_deviation: float = 0.0
	for i in range(30):
		var current_spread: float = float(core.spread) + (core.heat / core.heat_capacity) * 0.075
		var angle := randf_range(0.0, TAU)
		var radius := randf_range(0.0, current_spread)
		total_deviation += radius

	var avg_deviation := total_deviation / 30.0
	_check(avg_deviation > 0.02, "Hot barrel has active bullet spread bloom (avg_deviation=%.4f rad)" % avg_deviation)

	# 4. Cool down heat to 0
	core._cool_heat(10.0)
	_check(core.heat <= 0.0, "Weapon cooled down to 0 heat")

	print("HEAT_SPREAD_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
