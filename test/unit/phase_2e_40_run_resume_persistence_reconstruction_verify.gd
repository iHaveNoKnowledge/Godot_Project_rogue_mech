extends Node

## Phase 2E-40: Run Resume & Persistence Reconstruction Integrity Audit
## Audits the persistence boundary and runtime reconstruction lifecycle:
## Live Run -> Save -> Process/Scene Interruption -> Load -> Authoritative Restoration ->
## Runtime Reconstruction -> Resume Gameplay.

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
	print("PHASE 2E-40: RUN RESUME & PERSISTENCE RECONSTRUCTION AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_40_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_40_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-40 PERSISTENCE & RECONSTRUCTION SUMMARY:")
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


func _capture_authoritative_snapshot() -> Dictionary:
	return {
		"sector": GlobalData.board.current_sector,
		"current_tile": GlobalData.board.current_tile,
		"board_seed": GlobalData.board.board_seed,
		"board_day": GlobalData.board.board_day,
		"board_mp": GlobalData.board.board_mp,
		"board_mp_max": GlobalData.board.board_mp_max,
		"heat": GlobalData.board.heat,
		"wanted": GlobalData.board.wanted_level,
		"credits": GlobalData.currency.credits,
		"scrap": GlobalData.currency.scrap,
		"data_cores": GlobalData.currency.data_cores,
		"objective_id": GlobalData.board.board_objective_id,
		"objective_progress": GlobalData.board.board_objective_progress,
		"objective_required": GlobalData.board.board_objective_required,
		"primary_objective_done": GlobalData.board.primary_objective_done,
		"extraction_unlocked": GlobalData.board.extraction_unlocked,
		"extraction_zone_pos": GlobalData.board.extraction_zone_pos,
		"patrols_count": GlobalData.board.board_patrols.size(),
		"engagement": GlobalData.board.board_patrol_engagement,
		"mech_energy": GlobalData.fuel.mech_energy,
		"convoy_fuel": GlobalData.fuel.convoy_fuel_reserve,
		"pilot_hp": GlobalData.pilot.pilot_hp,
		"hangar_count": GlobalData.hangar.hangar_mechs.size(),
		"research_projects": GlobalData.hangar.research_projects.duplicate(true),
		"research_unlocked": GlobalData.hangar.research_unlocked.duplicate(),
	}


func _run_all_tests() -> void:
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.hangar.hangar_mechs = [{"id": 1, "name": "Valkren Alpha Chassis", "chassis": "valkren"}]
	GlobalData.narrative.mech_less = false

	# ===========================================================================
	# Scenario A: Fresh Sector Save / Load
	# ===========================================================================
	print("\n-- Scenario A: Fresh Sector Save / Load --")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)
	GlobalData.board.board_seed = 4242
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = 8
	GlobalData.board.board_mp_max = 8
	GlobalData.board.board_theme_id = "suburb"
	GlobalData.board.board_objective_id = "test_obj"
	GlobalData.board.board_objective_progress = 0
	GlobalData.board.board_objective_required = 3
	GlobalData.board.primary_objective_done = false
	GlobalData.board.extraction_unlocked = false
	GlobalData.currency.credits = 1000
	GlobalData.currency.scrap = 200
	GlobalData.currency.data_cores = 5
	GlobalData.fuel.mech_energy = 100.0
	GlobalData.fuel.convoy_fuel_reserve = 150.0

	SaveGameIO.save_run()
	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "Save file exists on disk after save_run()")

	# Clear runtime state
	GlobalData.currency.credits = 0
	GlobalData.board.current_sector = 99
	GlobalData.board.current_tile = Vector2i(99, 99)

	var loaded := SaveGameIO.load_run()
	_assert(loaded, "SaveGameIO.load_run() returned true")
	_assert(GlobalData.board.current_sector == 1, "Restored sector == 1")
	_assert(GlobalData.board.current_tile == Vector2i(1, 1), "Restored current_tile == (1,1)")
	_assert(GlobalData.currency.credits == 1000, "Restored credits == 1000")
	_assert(GlobalData.board.board_day == 1, "Restored day == 1")

	# ===========================================================================
	# Scenario B: Mid-Movement Save / Load
	# ===========================================================================
	print("\n-- Scenario B: Mid-Movement Save / Load --")
	GlobalData.board.current_tile = Vector2i(3, 2)
	GlobalData.board.board_mp = 5
	GlobalData.board.board_day = 2
	GlobalData.fuel.mech_energy = 75.0

	SaveGameIO.save_run()
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.board_mp = 8

	SaveGameIO.load_run()
	_assert(GlobalData.board.current_tile == Vector2i(3, 2), "Mid-movement current tile restored to (3,2)")
	_assert(GlobalData.board.board_mp == 5, "Mid-movement MP restored to 5")
	_assert(GlobalData.board.board_day == 2, "Mid-movement day restored to 2")
	_assert(GlobalData.fuel.mech_energy == 75.0, "Fuel restored to 75.0")

	# ===========================================================================
	# Scenario C: Data Node Save / Load
	# ===========================================================================
	print("\n-- Scenario C: Data Node Save / Load --")
	GlobalData.currency.data_cores = 12
	GlobalData.board.current_tile = Vector2i(2, 2)
	SaveGameIO.save_run()

	GlobalData.currency.data_cores = 0
	SaveGameIO.load_run()
	_assert(GlobalData.currency.data_cores == 12, "Data cores restored to 12 without loss or duplication")
	_assert(GlobalData.board.current_tile == Vector2i(2, 2), "Position on data node preserved at (2,2)")

	# ===========================================================================
	# Scenario D: Post-Combat Save / Load
	# ===========================================================================
	print("\n-- Scenario D: Post-Combat Save / Load --")
	GlobalData.board.board_patrols = [
		{"id": 101, "pos": Vector2i(1, 1), "home": Vector2i(1, 1), "dir": Vector2i(1, 0), "commander": {}},
		{"id": 102, "pos": Vector2i(5, 5), "home": Vector2i(5, 5), "dir": Vector2i(0, 1), "commander": {}}
	]
	GlobalData.board.board_patrol_engagement = -1
	# Simulate combat victory removing patrol 101 and granting credits
	GlobalData.board.board_patrols.remove_at(0)
	GlobalData.currency.credits += 500
	SaveGameIO.save_run()

	GlobalData.board.board_patrols.clear()
	GlobalData.currency.credits = 0
	SaveGameIO.load_run()
	_assert(GlobalData.board.board_patrols.size() == 1, "Patrol 101 remains destroyed (1 patrol left)")
	_assert(GlobalData.board.board_patrols[0]["id"] == 102, "Remaining patrol is patrol 102")
	_assert(GlobalData.currency.credits == 1500, "Post-combat reward credits preserved exactly")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1")

	# ===========================================================================
	# Scenario E: Retreat Save / Load
	# ===========================================================================
	print("\n-- Scenario E: Retreat Save / Load --")
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.board.heat = 3
	SaveGameIO.save_run()

	GlobalData.board.heat = 0
	SaveGameIO.load_run()
	_assert(GlobalData.board.heat == 3, "Heat after retreat restored to 3")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Engagement remains cleared (-1) after retreat load")

	# ===========================================================================
	# Scenario F: Objective Completion Save / Load
	# ===========================================================================
	print("\n-- Scenario F: Objective Completion Save / Load --")
	GlobalData.board.primary_objective_done = true
	GlobalData.board.extraction_unlocked = true
	GlobalData.board.extraction_zone_pos = Vector2i(7, 7)
	SaveGameIO.save_run()

	GlobalData.board.primary_objective_done = false
	GlobalData.board.extraction_unlocked = false
	GlobalData.board.extraction_zone_pos = Vector2i(-1, -1)
	SaveGameIO.load_run()
	_assert(GlobalData.board.primary_objective_done == true, "Primary objective done status restored as true")
	_assert(GlobalData.board.extraction_unlocked == true, "Extraction unlocked status restored as true")
	_assert(GlobalData.board.extraction_zone_pos == Vector2i(7, 7), "Extraction zone restored to (7,7)")

	# ===========================================================================
	# Scenario G: Pre-Extraction Save / Load
	# ===========================================================================
	print("\n-- Scenario G: Pre-Extraction Save / Load --")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(7, 7) # standing on extraction LZ
	SaveGameIO.save_run()

	SaveGameIO.load_run()
	_assert(GlobalData.board.current_sector == 1, "Sector did not prematurely advance upon pre-extraction load")
	_assert(GlobalData.board.current_tile == Vector2i(7, 7), "Current position remains on extraction LZ (7,7)")
	_assert(GlobalData.board.extraction_unlocked == true, "Extraction LZ remains unlocked")

	# ===========================================================================
	# Scenario H: Post-Sector-Transition Save / Load
	# ===========================================================================
	print("\n-- Scenario H: Post-Sector-Transition Save / Load --")
	GlobalData.board.current_sector = 2
	GlobalData.board.board_seed = 98765
	GlobalData.board.current_tile = Vector2i(1, 1)
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = 8
	GlobalData.board.primary_objective_done = false
	GlobalData.board.extraction_unlocked = false
	GlobalData.currency.credits = 2200
	SaveGameIO.save_run()

	GlobalData.board.current_sector = 1
	SaveGameIO.load_run()
	_assert(GlobalData.board.current_sector == 2, "Sector 2 state restored authoritatively")
	_assert(GlobalData.board.board_seed == 98765, "Sector 2 seed restored")
	_assert(GlobalData.board.primary_objective_done == false, "New sector objective fresh")
	_assert(GlobalData.currency.credits == 2200, "Persistent credits retained across transition")

	# ===========================================================================
	# Scenario I: Multi-Sector Resume
	# ===========================================================================
	print("\n-- Scenario I: Multi-Sector Resume --")
	GlobalData.board.current_sector = 3
	GlobalData.board.board_seed = 54321
	GlobalData.currency.credits = 3500
	GlobalData.currency.data_cores = 15
	SaveGameIO.save_run()

	SaveGameIO.load_run()
	_assert(GlobalData.board.current_sector == 3, "Multi-sector resume reached Sector 3")
	_assert(GlobalData.currency.credits == 3500, "Multi-sector credits retained (3500)")
	_assert(GlobalData.currency.data_cores == 15, "Multi-sector data cores retained (15)")

	# ===========================================================================
	# Scenario J: Stale Singleton State Replacement
	# ===========================================================================
	print("\n-- Scenario J: Stale Singleton State Replacement --")
	# Save known state
	GlobalData.board.current_sector = 2
	GlobalData.board.current_tile = Vector2i(4, 4)
	GlobalData.currency.credits = 1500
	SaveGameIO.save_run()

	# Mutate memory to wildly different stale state
	GlobalData.currency.credits = 999999
	GlobalData.board.current_sector = 99
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.fuel.convoy_fuel_reserve = 0.0

	# Load save
	SaveGameIO.load_run()
	_assert(GlobalData.currency.credits == 1500, "Stale credits (999999) fully overwritten by saved (1500)")
	_assert(GlobalData.board.current_sector == 2, "Stale sector (99) fully overwritten by saved (2)")
	_assert(GlobalData.board.current_tile == Vector2i(4, 4), "Stale tile (0,0) fully overwritten by saved (4,4)")

	# ===========================================================================
	# Scenario K: Stale Board Scene Replacement & Reconstruction
	# ===========================================================================
	print("\n-- Scenario K: Stale Board Scene Replacement & Reconstruction --")
	GlobalData.board.board_seed = 1337
	GlobalData.board.board_theme_id = "suburb"
	GlobalData.board.current_tile = Vector2i(2, 3)
	SaveGameIO.save_run()

	var board_k = _instantiate_board_scene()
	_assert(board_k != null, "BoardManager instantiated cleanly")
	_assert(board_k.current_pos == Vector2i(2, 3), "BoardManager current_pos initialized from loaded state (2,3)")
	var player_token = board_k.get_node_or_null("PlayerToken")
	_assert(player_token != null, "PlayerToken exists in reconstructed board")

	# ===========================================================================
	# Scenario L: Patrol Reconstruction
	# ===========================================================================
	print("\n-- Scenario L: Patrol Reconstruction --")
	GlobalData.board.board_patrols = [
		{"id": 201, "pos": Vector2i(1, 2), "home": Vector2i(1, 2), "dir": Vector2i(1, 0), "commander": {"name": "Ace Alpha"}},
		{"id": 202, "pos": Vector2i(4, 1), "home": Vector2i(4, 1), "dir": Vector2i(0, -1), "commander": {"name": "Ace Beta"}}
	]
	SaveGameIO.save_run()

	GlobalData.board.board_patrols.clear()
	SaveGameIO.load_run()
	_assert(GlobalData.board.board_patrols.size() == 2, "Both patrols deserialized cleanly")
	_assert(GlobalData.board.board_patrols[0]["pos"] == Vector2i(1, 2), "Patrol 201 pos restored to (1,2)")
	_assert(GlobalData.board.board_patrols[1]["pos"] == Vector2i(4, 1), "Patrol 202 pos restored to (4,1)")

	var board_l = _instantiate_board_scene()
	var patrol_container = board_l.get_node_or_null("PatrolMarkers")
	_assert(patrol_container != null, "PatrolMarkers container created on board reconstruction")
	if patrol_container:
		var patrol_marker_count := 0
		for child in patrol_container.get_children():
			if child is PatrolMarker:
				patrol_marker_count += 1
		_assert(patrol_marker_count == 2, "PatrolMarkers child count matches authoritative patrol count (2)")

	# ===========================================================================
	# Scenario M: Hangar & Research Reconstruction
	# ===========================================================================
	print("\n-- Scenario M: Hangar & Research Reconstruction --")
	GlobalData.hangar.research_projects = {"advanced_servos": {"progress": 75.0, "cost": 100.0}}
	GlobalData.hangar.research_unlocked = ["composite_plating"]
	GlobalData.hangar.hangar_mechs = [
		{"id": 10, "name": "Valkren Strike", "chassis": "valkren", "parts": {}, "frames": {}}
	]
	SaveGameIO.save_run()

	GlobalData.hangar.research_projects.clear()
	GlobalData.hangar.research_unlocked.clear()
	GlobalData.hangar.hangar_mechs.clear()

	SaveGameIO.load_run()
	_assert(GlobalData.hangar.research_projects.has("advanced_servos"), "Research project 'advanced_servos' restored")
	_assert(GlobalData.hangar.research_projects["advanced_servos"]["progress"] == 75.0, "Research progress 75.0 restored")
	_assert(GlobalData.hangar.research_unlocked.has("composite_plating"), "Unlocked research 'composite_plating' restored")
	_assert(GlobalData.hangar.hangar_mechs.size() == 1, "Hangar mech count restored (1)")
	_assert(GlobalData.hangar.hangar_mechs[0]["name"] == "Valkren Strike", "Hangar mech name restored")

	# ===========================================================================
	# Scenario N: Repeated Load Idempotency
	# ===========================================================================
	print("\n-- Scenario N: Repeated Load Idempotency --")
	var snap1 = _capture_authoritative_snapshot()
	SaveGameIO.load_run()
	var snap2 = _capture_authoritative_snapshot()
	SaveGameIO.load_run()
	var snap3 = _capture_authoritative_snapshot()

	_assert(snap1["credits"] == snap2["credits"] and snap2["credits"] == snap3["credits"], "Repeated load does not mutate credits")
	_assert(snap1["sector"] == snap2["sector"] and snap2["sector"] == snap3["sector"], "Repeated load does not advance sector")
	_assert(snap1["patrols_count"] == snap2["patrols_count"] and snap2["patrols_count"] == snap3["patrols_count"], "Repeated load does not duplicate patrols")
	_assert(snap1["research_unlocked"] == snap3["research_unlocked"], "Repeated load does not mutate research")

	# ===========================================================================
	# Scenario O: Load -> Continue Gameplay
	# ===========================================================================
	print("\n-- Scenario O: Load -> Continue Gameplay --")
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.board.board_mp = 6
	GlobalData.board.board_mp_max = 8
	SaveGameIO.save_run()

	SaveGameIO.load_run()
	var board_o = _instantiate_board_scene()
	_assert(board_o.current_pos == Vector2i(2, 2), "Reconstructed board at (2,2)")

	# Find valid adjacent tile to move to
	var target_tile := Vector2i(-1, -1)
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var cand = board_o.current_pos + d
		if board_o.nodes_dict.has(cand):
			var tile_node = board_o.nodes_dict[cand]
			tile_node.set_meta("terrain", "plain")
			tile_node.set_meta("tile_type", "empty")
			target_tile = cand
			break

	_assert(target_tile != Vector2i(-1, -1), "Valid adjacent target tile found")
	if target_tile != Vector2i(-1, -1):
		var initial_mp = GlobalData.board.board_mp
		var step_ok = board_o.move_to_tile(target_tile, false)
		_assert(step_ok, "Move to adjacent tile after load succeeded")
		_assert(board_o.current_pos == target_tile, "Post-load move updated board current_pos to target tile")
		_assert(GlobalData.board.current_tile == target_tile, "Post-load move updated authoritative current_tile to target tile")
		_assert(GlobalData.board.board_mp == initial_mp - 1, "Post-load move deducted 1 MP")

	# ===========================================================================
	# Scenario P: Load -> Sector Transition
	# ===========================================================================
	print("\n-- Scenario P: Load -> Sector Transition --")
	GlobalData.board.current_sector = 1
	GlobalData.board.primary_objective_done = true
	GlobalData.board.extraction_unlocked = true
	GlobalData.board.extraction_zone_pos = Vector2i(1, 1)
	GlobalData.board.current_tile = Vector2i(1, 1)
	SaveGameIO.save_run()

	SaveGameIO.load_run()
	var board_p = _instantiate_board_scene()
	_assert(GlobalData.board.current_sector == 1, "Loaded in Sector 1 before transition")

	# Confirm extraction and trigger transition
	board_p._on_extraction_confirmed()
	_assert(GlobalData.board.current_sector == 2, "Loaded run successfully transitions to Sector 2 upon extraction")

	# ===========================================================================
	# Scenario Q: Board Reconstruction Invariant
	# ===========================================================================
	print("\n-- Scenario Q: Board Reconstruction Invariant --")
	GlobalData.board.current_sector = 2
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.board.board_day = 4
	GlobalData.board.board_mp = 5
	GlobalData.currency.credits = 1800
	GlobalData.fuel.mech_energy = 80.0
	SaveGameIO.save_run()

	SaveGameIO.load_run()
	var snap_before_reconstruct = _capture_authoritative_snapshot()
	var board_q = _instantiate_board_scene()
	var snap_after_reconstruct = _capture_authoritative_snapshot()

	_assert(snap_before_reconstruct["sector"] == snap_after_reconstruct["sector"], "Board reconstruction does not mutate sector")
	_assert(snap_before_reconstruct["board_day"] == snap_after_reconstruct["board_day"], "Board reconstruction does not mutate board day")
	_assert(snap_before_reconstruct["board_mp"] == snap_after_reconstruct["board_mp"], "Board reconstruction does not mutate board MP")
	_assert(snap_before_reconstruct["credits"] == snap_after_reconstruct["credits"], "Board reconstruction does not mutate credits")
	_assert(snap_before_reconstruct["mech_energy"] == snap_after_reconstruct["mech_energy"], "Board reconstruction does not mutate fuel/energy")

	print("\nAll Phase 2E-40 test suites executed.")
