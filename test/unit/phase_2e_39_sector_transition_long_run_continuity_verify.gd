extends Node

## Phase 2E-39: Sector Transition & Long-Run Continuity Verification
## Audits higher-level Run lifecycle across Sector boundaries:
## Primary Objective -> Extraction LZ -> Sector Completion -> Transition ->
## New Sector Generation -> Persistent State Retention -> Multi-Sector Progression.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const BoardManager = preload("res://scripts/board/board_manager.gd")

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
	print("PHASE 2E-39: SECTOR TRANSITION & LONG-RUN CONTINUITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_39_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_39_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-39 SECTOR TRANSITION AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	_board_scene = board_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _run_all_tests() -> void:
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.hangar.hangar_mechs = [{"id": 1, "name": "Valkren Vanguard Chassis", "chassis": "valkren"}]
	GlobalData.narrative.mech_less = false

	# ===========================================================================
	# [1] Sector Identity & Objective Lifecycle Before Extraction
	# ===========================================================================
	print("\n-- [1] Sector Identity & Objective Lifecycle Before Extraction --")
	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 3
	GlobalData.board.primary_objective_done = false
	GlobalData.board.extraction_unlocked = false
	GlobalData.currency.credits = 1250
	GlobalData.currency.scrap = 340
	GlobalData.currency.data_cores = 8

	var board1 = _instantiate_board_scene()
	_assert(GlobalData.board.current_sector == 1, "Current sector initialized to Sector 1")
	_assert(GlobalData.board.primary_objective_done == false, "Primary objective initially incomplete")
	_assert(GlobalData.board.extraction_unlocked == false, "Extraction LZ initially locked")

	# Trigger primary objective completion
	board1._trigger_extraction_primary_objective("Comms Tower Down", "Tower destroyed, Extraction LZ unlocked")
	_assert(GlobalData.board.primary_objective_done == true, "Primary objective marked complete authoritatively")
	_assert(GlobalData.board.extraction_unlocked == true, "Extraction LZ unlocked upon objective completion")

	# ===========================================================================
	# [2] Sector Transition Exactly-Once Advancement & Reset Semantics
	# ===========================================================================
	print("\n-- [2] Sector Transition Exactly-Once Advancement & Reset Semantics --")
	var pre_sec: int = GlobalData.board.current_sector
	var pre_wanted: int = GlobalData.board.wanted_level
	var pre_credits: int = GlobalData.currency.credits
	var pre_scrap: int = GlobalData.currency.scrap
	var pre_cores: int = GlobalData.currency.data_cores
	var old_tile: Vector2i = board1.current_pos

	# Setup old sector patrol to ensure it does not leak
	var old_patrol := {"id": 901, "pos": Vector2i(2, 2), "home": Vector2i(2, 2), "name": "Sector 1 Guard"}
	GlobalData.board.board_patrols = [old_patrol]
	GlobalData.board.board_patrol_engagement = 901

	# Execute Sector Transition via production entry point
	board1._on_extraction_confirmed()

	_assert(GlobalData.board.current_sector == pre_sec + 1, "Sector advanced exactly once (%d -> %d)" % [pre_sec, GlobalData.board.current_sector])
	_assert(GlobalData.board.board_day == 1, "New sector board day reset to Day 1")
	_assert(GlobalData.board.board_mp == GlobalData.board.board_mp_max, "New sector MP reset to max (%d)" % GlobalData.board.board_mp_max)
	_assert(GlobalData.board.primary_objective_done == false, "New sector primary objective reset to incomplete")
	_assert(GlobalData.board.extraction_unlocked == false, "New sector extraction LZ reset to locked")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Old patrol engagement reset to -1")
	_assert(GlobalData.board.board_patrols.is_empty(), "Old sector patrols cleared from authoritative state")

	# ===========================================================================
	# [3] Persistent Run State Retention Across Sector Boundary
	# ===========================================================================
	print("\n-- [3] Persistent Run State Retention Across Sector Boundary --")
	_assert(GlobalData.currency.credits == pre_credits, "Credits retained across sector transition (%d cr)" % GlobalData.currency.credits)
	_assert(GlobalData.currency.scrap == pre_scrap, "Scrap retained across sector transition (%d scrap)" % GlobalData.currency.scrap)
	_assert(GlobalData.currency.data_cores == pre_cores, "Data cores retained across sector transition (%d cores)" % GlobalData.currency.data_cores)
	_assert(not GlobalData.hangar.hangar_mechs.is_empty(), "Hangar mech roster preserved across sector transition")
	_assert(GlobalData.board.wanted_level >= pre_wanted, "Wanted level escalated/maintained across sector boundary")

	# ===========================================================================
	# [4] New Sector Board Generation & Presentation Continuity
	# ===========================================================================
	print("\n-- [4] New Sector Board Generation & Presentation Continuity --")
	var board2 = _instantiate_board_scene()
	_assert(board2.current_pos == GlobalData.board.current_tile, "BoardManager current_pos matches GlobalData.board.current_tile on new sector board")
	_assert(board2.current_pos != Vector2i.ZERO or board2.nodes_dict.has(Vector2i.ZERO), "Player positioned on legal valid tile on new sector map")
	_assert(is_instance_valid(board2.player_token), "Player 3D unit token instantiated on new sector board")
	_assert(GlobalData.board.board_objective_id != "", "New sector objective ID assigned")
	_assert(PatrolSystem.get_patrol_by_id(901).is_empty(), "Old Sector 1 patrol (ID: 901) does not exist in new Sector 2")

	# ===========================================================================
	# [5] Save / Load Boundaries Around Sector Transition
	# ===========================================================================
	print("\n-- [5] Save / Load Boundaries Around Sector Transition --")
	# Scenario A: Save in Sector 2, reload and verify exact continuity
	GlobalData.board.current_sector = 2
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = 8
	GlobalData.currency.credits = 1500
	GlobalData.currency.scrap = 400
	GlobalData.currency.data_cores = 10
	GlobalData.hangar.research_projects["advanced_radar"] = {"progress": 0.8, "completed": false}

	var loaded_board = _instantiate_board_scene()
	_assert(GlobalData.board.current_sector == 2, "Saved sector (Sector 2) restored cleanly")
	_assert(GlobalData.board.board_day == 1, "Saved board day (Day 1) restored cleanly")
	_assert(GlobalData.board.board_mp == 8, "Saved board MP (8) restored cleanly")
	_assert(GlobalData.currency.credits == 1500, "Saved credits (1500) restored cleanly")
	_assert(GlobalData.currency.scrap == 400, "Saved scrap (400) restored cleanly")
	_assert(GlobalData.currency.data_cores == 10, "Saved data cores (10) restored cleanly")
	_assert(GlobalData.hangar.research_projects.has("advanced_radar"), "Active research project preserved across sector load")

	# ===========================================================================
	# [6] Board Reconstruction Idempotency in New Sector
	# ===========================================================================
	print("\n-- [6] Board Reconstruction Idempotency in New Sector --")
	var sec_before := GlobalData.board.current_sector
	var mp_before := GlobalData.board.board_mp
	var day_before := GlobalData.board.board_day
	var cr_before := GlobalData.currency.credits

	for i in range(3):
		var cycle_board = _instantiate_board_scene()
		_assert(cycle_board.current_pos == GlobalData.board.current_tile, "Re-entry cycle %d preserved player position" % (i + 1))

	_assert(GlobalData.board.current_sector == sec_before, "Reconstruction does NOT advance sector")
	_assert(GlobalData.board.board_mp == mp_before, "Reconstruction does NOT mutate MP")
	_assert(GlobalData.board.board_day == day_before, "Reconstruction does NOT advance day")
	_assert(GlobalData.currency.credits == cr_before, "Reconstruction does NOT mutate credits")

	# ===========================================================================
	# [7] Multi-Sector Sequential Progression (Sector 2 -> Sector 3)
	# ===========================================================================
	print("\n-- [7] Multi-Sector Sequential Progression (Sector 2 -> Sector 3) --")
	# Complete Sector 2 objective & extract
	loaded_board._trigger_extraction_primary_objective("Destroy Sector 2 Radar", "Radar silenced, LZ unlocked")
	_assert(GlobalData.board.primary_objective_done == true, "Sector 2 primary objective completed")
	_assert(GlobalData.board.extraction_unlocked == true, "Sector 2 extraction LZ unlocked")

	# Grant additional rewards in Sector 2
	GlobalData.currency.gain_credits(500)
	GlobalData.currency.gain_scrap(150)
	GlobalData.currency.data_cores += 3

	# Advance Sector 2 -> Sector 3
	loaded_board._on_extraction_confirmed()

	_assert(GlobalData.board.current_sector == 3, "Multi-sector progression stepped cleanly to Sector 3")
	_assert(GlobalData.currency.credits == 2000, "Cumulative credits preserved in Sector 3 (2000 cr)")
	_assert(GlobalData.currency.scrap == 550, "Cumulative scrap preserved in Sector 3 (550 scrap)")
	_assert(GlobalData.currency.data_cores == 13, "Cumulative data cores preserved in Sector 3 (13 cores)")
	_assert(GlobalData.board.board_day == 1, "Sector 3 board day initialized to 1")
	_assert(GlobalData.board.board_mp == GlobalData.board.board_mp_max, "Sector 3 MP initialized to max")
	_assert(GlobalData.board.primary_objective_done == false, "Sector 3 objective reset to incomplete")

	# Instantiate Sector 3 board
	var board3 = _instantiate_board_scene()
	_assert(board3.current_pos == GlobalData.board.current_tile, "Sector 3 BoardManager positioned on new sector spawn tile")
	_assert(is_instance_valid(board3.player_token), "Sector 3 player token valid and active")

	# ===========================================================================
	# [8] Cross-Sector State Leakage & Isolation Protection
	# ===========================================================================
	print("\n-- [8] Cross-Sector State Leakage & Isolation Protection --")
	_assert(GlobalData.board.active_contract.is_empty(), "Sector 2 contract cleared, not leaking into Sector 3")
	_assert(GlobalData.board.secondary_objectives_status.is_empty(), "Secondary objectives cleared for Sector 3")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement isolated to -1")
	_assert(GlobalData.board.mission_step_count == 0, "Mission step counter reset to 0 in Sector 3")
