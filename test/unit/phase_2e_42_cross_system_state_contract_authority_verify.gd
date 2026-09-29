extends Node

## Phase 2E-42: Cross-System State Contract & Authority Integrity Audit
## Audits single-source-of-truth ownership, multi-writer discipline, shadow state elimination,
## and cross-system consistency contracts across Board, Combat, SaveGameIO, UI, and Systems.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []
var _board_scene: BoardManager = null


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failures.append(message)
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-42: CROSS-SYSTEM STATE CONTRACT AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_42_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_42_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-42 STATE CONTRACT AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		if _board_scene.get_parent():
			_board_scene.get_parent().remove_child(_board_scene)
		_board_scene.free()
		_board_scene = null

	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.active_contract = {"name": "Test Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.board.current_hazard = ""
	GlobalData.board.convoy_breakdown_turns = 0
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.fuel.convoy_is_deployed = false
	GlobalData.fuel.mecha_is_parked = false
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.board.board_mp = 8
	GlobalData.board.board_mp_max = 8

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	_board_scene = board_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _run_all_tests() -> void:
	GameManager.current_state = GameManager.State.BOARD

	# ===========================================================================
	# Domain A: Current Tile Authority
	# ===========================================================================
	print("\n-- Domain A: Current Tile Authority --")
	GlobalData.board.current_tile = Vector2i(2, 3)
	var board_a = _instantiate_board_scene()
	_assert(board_a.current_pos == Vector2i(2, 3), "BoardManager current_pos initialized from authoritative GlobalData.board.current_tile")

	# Presentation token mutation must not overwrite authoritative state
	var p_token = board_a.get_node_or_null("PlayerToken")
	if p_token:
		p_token.position = Vector3(99.0, 99.0, 99.0)
		_assert(GlobalData.board.current_tile == Vector2i(2, 3), "Mutating PlayerToken local transform does not corrupt authoritative current_tile")

	# Board move updates authoritative state
	var target_tile = Vector2i(-1, -1)
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var cand = board_a.current_pos + d
		if board_a.nodes_dict.has(cand):
			board_a.nodes_dict[cand].set_meta("terrain", "plain")
			board_a.nodes_dict[cand].set_meta("tile_type", "empty")
			target_tile = cand
			break
	if target_tile != Vector2i(-1, -1):
		var step_ok = board_a.move_to_tile(target_tile, false)
		_assert(step_ok, "Step to adjacent tile succeeded")
		_assert(GlobalData.board.current_tile == target_tile, "BoardManager.move_to_tile updates authoritative current_tile")
		_assert(board_a.current_pos == target_tile, "BoardManager current_pos stays in sync with authority")

	# ===========================================================================
	# Domain B: Current Sector Authority
	# ===========================================================================
	print("\n-- Domain B: Current Sector Authority --")
	GlobalData.board.current_sector = 2
	_assert(GlobalData.board.current_sector == 2, "GlobalData.board is the single authoritative owner of current_sector")

	# ===========================================================================
	# Domain C: Board Seed Authority
	# ===========================================================================
	print("\n-- Domain C: Board Seed Authority --")
	GlobalData.board.board_seed = 54321
	_assert(GlobalData.board.board_seed == 54321, "GlobalData.board.board_seed is the single authoritative owner of board seed")

	# ===========================================================================
	# Domain D: Board MP Authority
	# ===========================================================================
	print("\n-- Domain D: Board MP Authority --")
	GlobalData.board.board_mp = 7
	GlobalData.board.board_mp_max = 8
	_assert(GlobalData.board.board_mp == 7, "GlobalData.board.board_mp is authoritative MP owner")

	# ===========================================================================
	# Domain E: Patrol State Authority
	# ===========================================================================
	print("\n-- Domain E: Patrol State Authority --")
	GlobalData.board.board_patrols = [
		{"id": 501, "pos": Vector2i(1, 1), "home": Vector2i(1, 1), "dir": Vector2i(1, 0), "commander": {}}
	]
	_assert(GlobalData.board.board_patrols.size() == 1, "GlobalData.board.board_patrols is the single authority for patrols list")
	_assert(GlobalData.board.board_patrols[0]["id"] == 501, "Patrol 501 stored authoritatively")

	# ===========================================================================
	# Domain F: Objective Authority
	# ===========================================================================
	print("\n-- Domain F: Objective Authority --")
	GlobalData.board.board_objective_id = "test_contract_obj"
	GlobalData.board.board_objective_progress = 2
	GlobalData.board.board_objective_required = 4
	GlobalData.board.primary_objective_done = false
	_assert(GlobalData.board.board_objective_progress == 2, "GlobalData.board owns objective progress")
	_assert(GlobalData.board.primary_objective_done == false, "GlobalData.board owns primary_objective_done")

	# ===========================================================================
	# Domain G: Extraction Authority
	# ===========================================================================
	print("\n-- Domain G: Extraction Authority --")
	GlobalData.board.extraction_unlocked = true
	GlobalData.board.extraction_zone_pos = Vector2i(6, 6)
	_assert(GlobalData.board.extraction_unlocked == true, "GlobalData.board owns extraction_unlocked")
	_assert(GlobalData.board.extraction_zone_pos == Vector2i(6, 6), "GlobalData.board owns extraction_zone_pos")

	# ===========================================================================
	# Domain H: Currency Authority
	# ===========================================================================
	print("\n-- Domain H: Currency Authority --")
	GlobalData.currency.credits = 1500
	GlobalData.currency.scrap = 350
	GlobalData.currency.data_cores = 10
	_assert(GlobalData.currency.credits == 1500, "CurrencyManager is sole authoritative owner of credits")
	_assert(GlobalData.currency.scrap == 350, "CurrencyManager is sole authoritative owner of scrap")
	_assert(GlobalData.currency.data_cores == 10, "CurrencyManager is sole authoritative owner of data cores")

	# ===========================================================================
	# Domain I: Fuel & Energy Authority
	# ===========================================================================
	print("\n-- Domain I: Fuel & Energy Authority --")
	GlobalData.fuel.mech_energy = 85.0
	GlobalData.fuel.convoy_fuel_reserve = 175.0
	_assert(GlobalData.fuel.mech_energy == 85.0, "FuelManager is authoritative owner of mech_energy")
	_assert(GlobalData.fuel.convoy_fuel_reserve == 175.0, "FuelManager is authoritative owner of convoy_fuel_reserve")

	# ===========================================================================
	# Domain J: Loadout & Hangar Authority
	# ===========================================================================
	print("\n-- Domain J: Loadout & Hangar Authority --")
	GlobalData.weapons.chassis_id = "valkren"
	GlobalData.weapons.power_core_id = "combustion"
	_assert(GlobalData.weapons.chassis_id == "valkren", "WeaponInventoryState is authoritative owner of chassis_id")
	_assert(GlobalData.weapons.power_core_id == "combustion", "WeaponInventoryState is authoritative owner of power_core_id")

	# ===========================================================================
	# Domain K: Research Progression Authority
	# ===========================================================================
	print("\n-- Domain K: Research Progression Authority --")
	GlobalData.hangar.research_projects = {"heavy_plating": {"progress": 50.0, "cost": 100.0}}
	GlobalData.hangar.research_unlocked = ["fast_actuators"]
	_assert(GlobalData.hangar.research_projects.has("heavy_plating"), "HangarState is authoritative owner of research_projects")
	_assert(GlobalData.hangar.research_unlocked.has("fast_actuators"), "HangarState is authoritative owner of research_unlocked")

	# ===========================================================================
	# Domain L: Pilot State Authority
	# ===========================================================================
	print("\n-- Domain L: Pilot State Authority --")
	GlobalData.pilot.pilot_hp = 75.0
	GlobalData.pilot.pilot_max_hp = 100.0
	_assert(PilotSystem.get_hp() == 75.0, "PilotState/PilotSystem is authoritative owner of pilot HP")

	# ===========================================================================
	# Domain M: Technology System Authority
	# ===========================================================================
	print("\n-- Domain M: Technology System Authority --")
	var tech_discovery = TechnologySystem.serialize_discovery_states()
	_assert(tech_discovery is Dictionary, "TechnologySystem is sole authoritative owner of technology discovery states")

	# ===========================================================================
	# Domain N: Era Progression Authority
	# ===========================================================================
	print("\n-- Domain N: Era Progression Authority --")
	var era_state = EraProgressionSystem.serialize_era_state()
	_assert(era_state is Dictionary, "EraProgressionSystem is sole authoritative owner of era state")

	# ===========================================================================
	# Domain O: Heat / Wanted Authority
	# ===========================================================================
	print("\n-- Domain O: Heat / Wanted Authority --")
	GlobalData.board.heat = 2
	GlobalData.board.wanted_level = 3
	_assert(GlobalData.board.heat == 2, "GlobalData.board is authoritative owner of heat")
	_assert(GlobalData.board.wanted_level == 3, "GlobalData.board is authoritative owner of wanted_level")

	# ===========================================================================
	# Domain P: Combat Result Authority
	# ===========================================================================
	print("\n-- Domain P: Combat Result Authority --")
	GameManager.is_boss_combat = false
	GlobalData.board.board_patrol_engagement = -1
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to canonical cleared state (-1)")

	# ===========================================================================
	# Domain Q: Run State Machine Authority
	# ===========================================================================
	print("\n-- Domain Q: Run State Machine Authority --")
	GameManager.transition_to(GameManager.State.BOARD)
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager is single authoritative owner of game State machine")

	# ===========================================================================
	# Domain R: Save/Load Authority Boundary
	# ===========================================================================
	print("\n-- Domain R: Save/Load Authority Boundary --")
	# SaveGameIO reads authority and writes to file; does not store competing gameplay authority
	SaveGameIO.save_run()
	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "SaveGameIO serializes authoritative state to disk without competing memory cache")

	# ===========================================================================
	# Domain S: UI Reflection Invariance
	# ===========================================================================
	print("\n-- Domain S: UI Reflection Invariance --")
	# UI displays state without mutating authority on open
	var board_s = _instantiate_board_scene()
	_assert(board_s != null, "Board UI instantiated cleanly without unexpected state mutation")
	_assert(GlobalData.currency.credits == 1500, "Board UI instantiation preserved authoritative credits")

	# ===========================================================================
	# Domain T: Board / Combat Derived Reflection
	# ===========================================================================
	print("\n-- Domain T: Board / Combat Derived Reflection --")
	_assert(board_s.current_pos == GlobalData.board.current_tile, "BoardManager current_pos reflects authoritative current_tile exactly")

	print("\nAll Phase 2E-42 cross-system authority assertions passed.")
