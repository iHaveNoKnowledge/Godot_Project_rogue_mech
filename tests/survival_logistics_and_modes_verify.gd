extends Node3D

## Automated Verification for Survival Logistics, Multi-Tier Traversal (Convoy/Mecha/Pilot), Camouflage Seizure, and Recovery Compound Generation.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("LOGISTICS_OK: %s" % msg)
	else:
		_fails += 1
		print("LOGISTICS_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Survival Logistics & Multi-Tier Traversal Verification ---")

	# 1. Test Traversal Modes and Energy Pools in FuelManager
	GlobalData.fuel.reset()
	_check(GlobalData.fuel.traversal_mode == "convoy", "Initial traversal mode is 'convoy'")
	_check(GlobalData.fuel.convoy_fuel == 350.0, "Initial convoy fuel is 350.0")

	# Step costs for Convoy
	var c_road := GlobalData.fuel.get_mode_step_cost("road")
	_check(c_road["mp"] == 1 and c_road["fuel"] == 5.0, "Convoy on road costs 1 MP and 5 Fuel")
	var c_sand := GlobalData.fuel.get_mode_step_cost("sand")
	_check(c_sand["mp"] == 2 and c_sand["fuel"] == 30.0, "Convoy off-road/sand costs 2 MP and 30 Fuel")

	# 2. Test Deploy Mecha Mode
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.fuel.deploy_mecha()
	_check(GlobalData.fuel.traversal_mode == "mecha", "Switched to 'mecha' mode")
	_check(GlobalData.fuel.convoy_is_deployed == true, "convoy_is_deployed is true")
	_check(GlobalData.fuel.convoy_pos == Vector2i(2, 2), "Convoy base camp saved at (2, 2)")

	var m_sand := GlobalData.fuel.get_mode_step_cost("sand")
	_check(m_sand["mp"] == 1 and m_sand["energy"] == 20.0, "Mecha traversal on sand costs 1 MP and 20 Battery")

	# 3. Test Deploy Pilot Mode (Stealth & Stamina)
	GlobalData.fuel.deploy_pilot()
	_check(GlobalData.fuel.traversal_mode == "pilot", "Switched to 'pilot' mode")
	var p_road := GlobalData.fuel.get_mode_step_cost("road")
	_check(p_road["mp"] == 1 and p_road["stamina"] == 10.0, "Pilot on road costs 1 MP and 10 Stamina")

	# 4. Test Re-embarkation and Refueling
	GlobalData.fuel.carried_fuel = 40.0
	GlobalData.fuel.convoy_fuel = 300.0
	GlobalData.fuel.reembark_convoy()
	_check(GlobalData.fuel.traversal_mode == "convoy", "Returned and re-embarked to 'convoy' mode")
	_check(GlobalData.fuel.convoy_is_deployed == false, "convoy_is_deployed is false")
	_check(GlobalData.fuel.convoy_fuel == 340.0, "Carried 40 fuel successfully transferred into convoy tank (340.0)")

	# 5. Test Camouflage Evasion Rates
	_check(GlobalData.fuel.get_camouflage_rate("forest") == 0.75, "Forest camouflage rate is 75%")
	_check(GlobalData.fuel.get_camouflage_rate("urban") == 0.65, "Urban camouflage rate is 65%")
	_check(GlobalData.fuel.get_camouflage_rate("sand") == 0.40, "Desert sand camouflage rate is 40%")
	_check(GlobalData.fuel.get_camouflage_rate("road") == 0.15, "Road camouflage rate is 15%")

	# 6. Test 3-Stage Seizure Progression in PatrolSystem
	GlobalData.fuel.deploy_mecha()
	GlobalData.fuel.convoy_pos = Vector2i(1, 1)
	GlobalData.fuel.seizure_stage = 1
	GlobalData.fuel.seizure_turns_left = 2

	var mock_nodes := {Vector2i(1, 1): Node.new()}
	mock_nodes[Vector2i(1, 1)].set_meta("terrain", "forest")
	var rng := RandomNumberGenerator.new()

	# Day 1 advance
	PatrolSystem._process_parked_convoy_seizure(mock_nodes, rng, Vector2i(4, 4))
	_check(GlobalData.fuel.seizure_stage == 1 and GlobalData.fuel.seizure_turns_left == 1, "Stage 1 ticked down to 1 turn remaining")

	# Day 2 advance (transitions to Stage 2)
	PatrolSystem._process_parked_convoy_seizure(mock_nodes, rng, Vector2i(4, 4))
	_check(GlobalData.fuel.seizure_stage == 2 and GlobalData.fuel.seizure_turns_left == 2, "Transitioned to Stage 2: Salvage Breaching (2 turns)")

	# Day 3 & 4 advance (transitions to Stage 3)
	PatrolSystem._process_parked_convoy_seizure(mock_nodes, rng, Vector2i(4, 4))
	PatrolSystem._process_parked_convoy_seizure(mock_nodes, rng, Vector2i(4, 4))
	_check(GlobalData.fuel.seizure_stage == 3 and GlobalData.fuel.seizure_turns_left == 1, "Transitioned to Stage 3: Extraction Towing (1 turn)")

	# 7. Test Recovery Arena Compound Generation
	GameManager.combat_node_type = "recovery"
	var arena = preload("res://scripts/arena/arena_generator.gd").new()
	arena.current_theme = 0 # Desert
	add_child(arena)
	arena.generate_arena()

	var compound: Node3D = arena.get_node_or_null("ThemeStructures/RecoveryCompound")
	_check(compound != null, "Generated dense RecoveryCompound in arena")

	var target_asset: Node3D = compound.get_node_or_null("ParkedAssetTarget")
	_check(target_asset != null, "Found ParkedAssetTarget inside compound")

	var prompt: Label3D = target_asset.get_node_or_null("MountPrompt")
	_check(prompt != null and prompt.text.contains("MOUNT & IGNITE"), "Found '[E] MOUNT & IGNITE REACTOR!' prompt")

	# Clean up mock node
	mock_nodes[Vector2i(1, 1)].free()
	GameManager.combat_node_type = ""

	print("--- Survival Logistics & Multi-Tier Traversal Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_LOGISTICS_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
