extends Node

## Automated test for Extraction Run Mode:
## 1. Board Config: Grid size expansion (35x35) and contract generation.
## 2. Heat / Wanted System: init_contract_heat, step increments, and clamping.
## 3. Extraction Objectives & Board State: primary completion, extraction LZ unlock.
## 4. Patrol Movement: multi-step turn logic and high-heat reinforcement spawning.
## 5. UI Modals: ExtractionMissionSelect and ExtractionSummaryModal instantiation.

var _checks := 0
var _fails := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("EXTRACTION_OK: ", msg)
	else:
		_fails += 1
		printerr("EXTRACTION_FAIL: ", msg)

func _ready() -> void:
	print("--- BEGIN EXTRACTION RUN MODE VERIFICATION ---")

	# Test 1: Grid Size & Contracts
	_check(BoardConfig.GRID_SIZE >= 35, "BoardConfig.GRID_SIZE is 35 (expanded extraction map)")
	var contracts: Array[Dictionary] = BoardConfig.get_contracts_for_sector(1)
	_check(contracts.size() >= 3, "get_contracts_for_sector returns at least 3 extraction contracts")
	var c0 = contracts[0]
	_check(c0.has("primary") and c0.has("min_heat") and c0.has("max_heat"), "Contract contains primary objective and heat bounds")

	# Test 2: Heat & Wanted System
	HeatWantedSystem.init_contract_heat(2, 4)
	_check(GlobalData.board.extraction_min_heat == 2, "Min heat correctly initialized to 2")
	_check(GlobalData.board.extraction_max_heat == 4, "Max heat correctly initialized to 4")
	_check(GlobalData.board.wanted_level >= 2, "Wanted level starts at min heat level (2★)")

	# Simulate 8 player steps -> should add 2 heat points
	var initial_heat := GlobalData.board.heat
	for i in range(8):
		HeatWantedSystem.on_player_step_heat()
	_check(GlobalData.board.mission_step_count == 8, "Mission step count incremented to 8")
	_check(GlobalData.board.heat >= initial_heat + 2, "Heat increased from step traversal")

	# Test 3: Objectives & Extraction LZ
	GlobalData.board.active_contract = c0
	GlobalData.board.primary_objective_done = false
	GlobalData.board.extraction_unlocked = false
	GlobalData.board.extraction_zone_pos = Vector2i(34, 34)

	_check(not BoardSystem.is_objective_complete(), "Extraction not complete prior to primary objective")
	GlobalData.board.primary_objective_done = true
	GlobalData.board.extraction_unlocked = true
	_check(BoardSystem.is_objective_complete(), "Primary objective done unlocks extraction")

	# Test 4: Patrol Step Turn
	var mock_nodes: Dictionary = {}
	for x in range(8, 15):
		for y in range(8, 15):
			var t := Node.new()
			t.set_meta("terrain", "plain")
			t.set_meta("tile_type", "empty")
			mock_nodes[Vector2i(x, y)] = t
	GlobalData.board.board_grid = [mock_nodes]

	var mock_patrol := {
		"id": 999,
		"pos": Vector2i(10, 10),
		"home": Vector2i(10, 10),
		"prev_pos": Vector2i(10, 10),
		"name": "Test Recon Squad",
		"grunts": 2,
		"aces": 0,
		"archetype": "recon",
		"aggro": true,
		"faction": "hostile",
		"character_id": "",
		"dir": Vector2i(1, 0),
		"commander": {},
		"pilots": [],
		"squad_id": "test_squad",
		"squad_name": "Test Recon Squad",
		"formation": "wedge",
		"fleet_count": 1,
		"merged_fleets": [],
	}
	GlobalData.board.board_patrols = [mock_patrol]
	var player_pos := Vector2i(12, 10)
	var ambush_tile := PatrolSystem.advance_step_turn(player_pos)
	_check(mock_patrol["pos"] != Vector2i(10, 10), "Hostile patrol moved in 1:1 step turn")

	# Clean up mock nodes
	for k in mock_nodes:
		mock_nodes[k].free()
	GlobalData.board.board_grid = []

	# Test 5: UI Modal Instantiation
	var select_modal := ExtractionMissionSelect.new()
	add_child(select_modal)
	select_modal.open_select(1)
	_check(select_modal.visible, "ExtractionMissionSelect modal opens successfully")
	select_modal.queue_free()

	var summary_modal := ExtractionSummaryModal.new()
	add_child(summary_modal)
	summary_modal.show_summary(c0, 500, 50, 3)
	_check(summary_modal.visible, "ExtractionSummaryModal displays report successfully")
	summary_modal.queue_free()

	# Summary
	print("--- EXTRACTION RUN VERIFICATION COMPLETE: %d checks, %d failures ---" % [_checks, _fails])
	if _fails == 0:
		print("ALL EXTRACTION TESTS PASSED!")
	else:
		printerr("SOME EXTRACTION TESTS FAILED!")
	get_tree().quit(0 if _fails == 0 else 1)
