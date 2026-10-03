extends Node

## War Mode Phase 3: Balance & Playtest Verification Suite
## Verifies War Mode economy, crafting stat ratios, drop rate distributions,
## deployment caps, carrier capacities, and Campaign Board escalation invariants.

const WarBalance = preload("res://scripts/war/war_balance.gd")
const WarValkyrionSystem = preload("res://scripts/war/war_valkyrion_system.gd")
const WarDeploymentManager = preload("res://scripts/war/war_deployment_manager.gd")
const CarrierDock = preload("res://scripts/war/carrier_dock.gd")
const FleetSystem = preload("res://scripts/systems/fleet_system.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failures.append(message)
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3: BALANCE & PLAYTEST VALIDATION")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("WAR_PHASE_3_BALANCE_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nWAR_PHASE_3_BALANCE_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("WAR MODE PHASE 3 TEST SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _run_all_tests() -> void:
	_test_crafting_economics()
	_test_drop_rate_distribution()
	_test_deployment_caps_and_cooldowns()
	_test_carrier_and_barracks_capacity()
	_test_campaign_security_and_escalation()


func _test_crafting_economics() -> void:
	print("\n-- [1] Crafting Economics & Resource Deductions --")
	_assert(WarBalance.ORIGINAL_COST_CREDITS == 800, "1.1: Original cost credits == 800")
	_assert(WarBalance.ORIGINAL_COST_SCRAP == 200, "1.2: Original cost scrap == 200")
	_assert(WarBalance.MASS_COST_CREDITS == 400, "1.3: Mass cost credits == 400")
	_assert(WarBalance.MASS_COST_SCRAP == 80, "1.4: Mass cost scrap == 80")
	_assert(WarBalance.MASS_STAT_RATIO == 0.75, "1.5: Mass stat ratio == 0.75 (75% spec)")

	# Test resource deduction boundary: Mass Product
	GlobalData.currency.credits = 399
	GlobalData.currency.scrap = 80
	_assert(not WarValkyrionSystem.craft_mass_product("bp_test"), "1.6: Insufficient credits rejects Mass craft")

	GlobalData.currency.credits = 400
	GlobalData.currency.scrap = 79
	_assert(not WarValkyrionSystem.craft_mass_product("bp_test"), "1.7: Insufficient scrap rejects Mass craft")

	GlobalData.currency.credits = 400
	GlobalData.currency.scrap = 80
	var success_mass := WarValkyrionSystem.craft_mass_product("bp_test")
	_assert(success_mass, "1.8: Exact resource boundary approves Mass craft")
	_assert(GlobalData.currency.credits == 0 and GlobalData.currency.scrap == 0,
		"1.9: Mass craft deducts exact 400c and 80s")

	# Test resource deduction boundary: Original
	GlobalData.currency.credits = 799
	GlobalData.currency.scrap = 200
	_assert(not WarValkyrionSystem.craft_original("bp_test"), "1.10: Insufficient credits rejects Original craft")

	GlobalData.currency.credits = 800
	GlobalData.currency.scrap = 199
	_assert(not WarValkyrionSystem.craft_original("bp_test"), "1.11: Insufficient scrap rejects Original craft")

	GlobalData.currency.credits = 800
	GlobalData.currency.scrap = 200
	var success_orig := WarValkyrionSystem.craft_original("bp_test")
	_assert(success_orig, "1.12: Exact resource boundary approves Original craft")
	_assert(GlobalData.currency.credits == 0 and GlobalData.currency.scrap == 0,
		"1.13: Original craft deducts exact 800c and 200s")


func _test_drop_rate_distribution() -> void:
	print("\n-- [2] Drop Rate Probability & Distribution Simulation --")
	const SAMPLES := 10000
	var counts := {
		"whole_mech": 0,
		"full_blueprint": 0,
		"part": 0,
		"frame": 0,
		"module": 0,
		"weapon": 0,
	}

	# Run simulation
	var invalid_count: int = 0
	for i in range(SAMPLES):
		var reward := WarValkyrionSystem.roll_data_reward()
		if not counts.has(reward):
			invalid_count += 1
		else:
			counts[reward] = counts[reward] + 1

	_assert(invalid_count == 0, "2.1: All %d rewards are valid catalog types" % SAMPLES)

	var p_whole: float = float(counts["whole_mech"]) / float(SAMPLES)
	var p_bp: float = float(counts["full_blueprint"]) / float(SAMPLES)
	var p_part: float = float(counts["part"]) / float(SAMPLES)
	var p_frame: float = float(counts["frame"]) / float(SAMPLES)
	var p_module: float = float(counts["module"]) / float(SAMPLES)
	var p_weapon: float = float(counts["weapon"]) / float(SAMPLES)

	print("  Observed Rates (N=%d):" % SAMPLES)
	print("    whole_mech:     %.3f (expected ~0.02)" % p_whole)
	print("    full_blueprint: %.3f (expected ~0.08)" % p_bp)
	print("    part:           %.3f (expected ~0.30)" % p_part)
	print("    frame:          %.3f (expected ~0.20)" % p_frame)
	print("    module:         %.3f (expected ~0.20)" % p_module)
	print("    weapon:         %.3f (expected ~0.20)" % p_weapon)

	_assert(absf(p_whole - 0.02) < 0.015, "2.2: whole_mech rate within statistical tolerance (2%)")
	_assert(absf(p_bp - 0.08) < 0.025, "2.3: full_blueprint rate within statistical tolerance (8%)")
	_assert(absf(p_part - 0.30) < 0.035, "2.4: part rate within statistical tolerance (30%)")
	_assert(absf(p_frame - 0.20) < 0.030, "2.5: frame rate within statistical tolerance (20%)")
	_assert(absf(p_module - 0.20) < 0.030, "2.6: module rate within statistical tolerance (20%)")
	_assert(absf(p_weapon - 0.20) < 0.030, "2.7: weapon rate within statistical tolerance (20%)")


func _test_deployment_caps_and_cooldowns() -> void:
	print("\n-- [3] Deployment Caps & Cooldown Lifecycle --")
	var dm := WarDeploymentManager.new()

	_assert(dm.can_deploy("line"), "3.1: Line deploy available at 0/5")
	_assert(dm.available_stock("line") == 5, "3.2: Line available stock == 5")

	# Deploy to cap (5)
	for i in range(5):
		_assert(dm.on_deployed("line"), "3.3.%d: Line deploy #%d succeeded" % [i + 1, i + 1])
	_assert(not dm.can_deploy("line"), "3.4: Line deploy rejected at 5/5 cap")
	_assert(dm.available_stock("line") == 0, "3.5: Line available stock == 0 at cap")

	# Destroy 1 line unit -> enters pending cooldown (30.0s)
	dm.on_destroyed("line")
	_assert(not dm.can_deploy("line"), "3.6: Cannot deploy while stock replenishing")
	_assert(dm.get_cooldown_remaining("line") > 20.0, "3.7: Cooldown active (~30s)")

	# Tick 15s -> still on cooldown
	dm.tick(15.0)
	_assert(not dm.can_deploy("line"), "3.8: Cooldown remaining at 15s")

	# Tick remaining 16s -> stock replenished
	dm.tick(16.0)
	_assert(dm.can_deploy("line"), "3.9: Line deploy available after cooldown expiration")
	_assert(dm.available_stock("line") == 1, "3.10: Line available stock restored to 1")

	# Valkyrion singleton cap (1)
	_assert(dm.can_deploy("valkyrion"), "3.11: Valkyrion deploy available at 0/1")
	_assert(dm.on_deployed("valkyrion"), "3.12: Valkyrion deployed (1/1)")
	_assert(not dm.can_deploy("valkyrion"), "3.13: Valkyrion deploy rejected at 1/1 cap")


func _test_carrier_and_barracks_capacity() -> void:
	print("\n-- [4] Carrier & Barracks Capacity Enforcements --")
	_assert(WarBalance.CARRIER_CAPACITY == 2, "4.1: Carrier capacity == 2 bays")
	_assert(WarBalance.BARRACKS_CAPACITY[1] == 4, "4.2: Barracks Lv1 capacity == 4")
	_assert(WarBalance.BARRACKS_CAPACITY[2] == 8, "4.3: Barracks Lv2 capacity == 8")
	_assert(WarBalance.BARRACKS_CAPACITY[3] == 12, "4.4: Barracks Lv3 capacity == 12")

	# Carrier dock boundary enforcement
	var cd := CarrierDock.new()
	add_child(cd)
	_assert(cd._docked.size() == 2, "4.5: CarrierDock internal bay array size == 2")
	_assert(cd._docked[0] == null and cd._docked[1] == null, "4.6: Both carrier bays initially empty")
	cd.queue_free()


func _test_campaign_security_and_escalation() -> void:
	print("\n-- [5] Campaign Board Security & Escalation Balance (CHANGEPLAN §4) --")
	GlobalData.narrative.fleet_security = 0.0
	GlobalData.narrative.security_upgrade_level = 1

	# Security upgrade cost progression
	_assert(FleetSystem.get_security_upgrade_cost() == 35, "5.1: Level 1 security upgrade cost == 35")
	GlobalData.narrative.security_upgrade_level = 2
	_assert(FleetSystem.get_security_upgrade_cost() == 75, "5.2: Level 2 security upgrade cost == 75")
	GlobalData.narrative.security_upgrade_level = 3
	_assert(FleetSystem.get_security_upgrade_cost() == 115, "5.3: Level 3 security upgrade cost == 115")
	GlobalData.narrative.security_upgrade_level = 4
	_assert(FleetSystem.get_security_upgrade_cost() == 155, "5.4: Level 4 security upgrade cost == 155")

	# Security points gain (+14 per upgrade)
	GlobalData.narrative.fleet_security = 20.0
	GlobalData.currency.credits = 500
	GlobalData.narrative.security_upgrade_level = 1
	var upgraded := FleetSystem.upgrade_fleet_security()
	_assert(upgraded, "5.5: Security upgrade succeeds with sufficient credits")
	_assert(FleetSystem.get_fleet_security() == 34.0, "5.6: Security increased by +14 (20 -> 34)")

	# Research node moves requirement
	_assert(GlobalData.narrative.enemy_base_required == 6.0, "5.7: enemy_base_required == 6.0 (6 moves to reach base)")
