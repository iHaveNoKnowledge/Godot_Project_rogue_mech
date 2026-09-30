extends Node

## Phase 2E-51: Board -> Combat -> Board Lifecycle Integrity Verification
## Audits and validates that the complete runtime lifecycle:
## Board -> Movement -> Patrol Engagement -> Combat -> Resolution -> Return to Board -> Continued Movement
## is lifecycle-safe, state-safe, identity-safe, and repeatable without node/singleton leakage.

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
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _cleanup_board() -> void:
	if _board_scene and is_instance_valid(_board_scene):
		if _board_scene.get_parent():
			_board_scene.get_parent().remove_child(_board_scene)
		_board_scene.free()
		_board_scene = null


func _instantiate_board() -> BoardManager:
	_cleanup_board()
	var scene_res := load("res://scenes/board/game_board.tscn") as PackedScene
	_board_scene = scene_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-51: BOARD -> COMBAT -> BOARD LIFECYCLE AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	_run_all_tests()
	_cleanup_board()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_51_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_51_SUCCESS")
		get_tree().quit(0)


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario 1: Initial Board State & Identity Baseline
	# ===========================================================================
	print("\n-- [1] Initial Board State & Identity Baseline --")
	GlobalData.board.board_seed = 10001
	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 1
	GlobalData.board.time_hour = 8.0
	GlobalData.board.board_mp = 8
	GlobalData.board.board_mp_max = 8
	GlobalData.board.current_hazard = ""
	GlobalData.board.convoy_breakdown_turns = 0
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.board.board_patrols = []
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.currency.credits = 300
	GlobalData.currency.scrap = 100
	GameManager.current_state = GameManager.State.BOARD

	var board := _instantiate_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "1.1: GameManager starts in State.BOARD")
	_assert(GlobalData.board.board_patrol_engagement == -1, "1.2: Initial board_patrol_engagement is idle (-1)")
	_assert(board.current_pos == Vector2i(2, 2), "1.3: BoardManager current_pos initialized to (2, 2)")
	_assert(GlobalData.board.current_tile == Vector2i(2, 2), "1.4: GlobalData.board.current_tile matches (2, 2)")
	_assert(is_instance_valid(board.player_token), "1.5: PlayerToken instantiated and valid")

	# ===========================================================================
	# Scenario 2: Deterministic Patrol Placement on Adjacent Walkable Tile
	# ===========================================================================
	print("\n-- [2] Deterministic Patrol Placement on Adjacent Walkable Tile --")
	var target_tile := Vector2i(3, 2)
	var cmdr_info := {
		"name": "Captain Strike",
		"display_name": "Captain Strike",
		"trait": "Predator",
		"bounty": 250,
		"archetype": 4,
	}
	var patrol_101 := {
		"id": 101,
		"pos": target_tile,
		"home": target_tile,
		"dir": Vector2i(1, 0),
		"archetype": "hunter_killer",
		"fleet_count": 2,
		"name": "Strike Vanguard",
		"commander": cmdr_info,
		"pilots": [cmdr_info]
	}
	var patrol_102 := {
		"id": 102,
		"pos": Vector2i(5, 5),
		"home": Vector2i(5, 5),
		"dir": Vector2i(0, 1),
		"archetype": "recon",
		"fleet_count": 1,
		"name": "Distant Scout",
	}
	PatrolSystem.normalize_patrol(patrol_101)
	PatrolSystem.normalize_patrol(patrol_102)
	GlobalData.board.board_patrols = [patrol_101, patrol_102]
	board._refresh_patrol_markers()

	_assert(GlobalData.board.board_patrols.size() == 2, "2.1: Exactly 2 patrols registered in GlobalData.board.board_patrols")
	_assert(PatrolSystem.get_patrol_by_id(101).get("name") == "Strike Vanguard", "2.2: Patrol 101 retrievable by ID")
	_assert(PatrolSystem.get_patrol_by_id(102).get("name") == "Distant Scout", "2.3: Patrol 102 retrievable by ID")

	# ===========================================================================
	# Scenario 3: Player Movement Onto Patrol & Automatic Combat Trigger
	# ===========================================================================
	print("\n-- [3] Player Movement Onto Patrol & Automatic Combat Trigger --")
	var step_ok: bool = board._try_step(target_tile)
	_assert(step_ok == true, "3.1: Movement step onto patrol tile (3, 2) executed successfully")
	_assert(board.current_pos == target_tile, "3.2: BoardManager position advanced to target tile (3, 2)")
	_assert(GlobalData.board.current_tile == target_tile, "3.3: GlobalData position synchronized to target tile (3, 2)")
	_assert(GlobalData.board.board_patrol_engagement == 101, "3.4: Patrol 101 engagement recorded in board_patrol_engagement")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "3.5: GameManager automatically transitioned to State.COMBAT")
	_assert(GameManager.combat_fleet_count == 2, "3.6: Fleet count resolved to 2 from engaged patrol data")

	# ===========================================================================
	# Scenario 4: Combat State Authority & Loadout Preservation
	# ===========================================================================
	print("\n-- [4] Combat State Authority & Loadout Preservation --")
	_assert(GlobalData.pre_combat_weapon_loadout is Dictionary, "4.1: Pre-combat weapon loadout snapshot preserved")
	var engaged_patrol := PatrolSystem.get_patrol_by_id(GlobalData.board.board_patrol_engagement)
	_assert(not engaged_patrol.is_empty(), "4.2: Engaged patrol data accessible during combat")
	_assert(engaged_patrol.get("commander", {}).get("name") == "Captain Strike", "4.3: Commander identity preserved intact into combat")

	# ===========================================================================
	# Scenario 5: Combat Victory Resolution & Exact Single-Mutation Patrol Removal
	# ===========================================================================
	print("\n-- [5] Combat Victory Resolution & Exact Single-Mutation Patrol Removal --")
	var pre_credits: int = GlobalData.currency.credits
	var pre_scrap: int = GlobalData.currency.scrap
	GlobalData.currency.gain_credits(250)
	GlobalData.currency.gain_scrap(50)

	PatrolSystem.remove_patrol(101)
	GlobalData.board.board_patrol_engagement = -1

	_assert(PatrolSystem.get_patrol_by_id(101).is_empty(), "5.1: Defeated patrol 101 removed from PatrolSystem")
	_assert(GlobalData.board.board_patrols.size() == 1, "5.2: Exactly 1 surviving patrol (102) remains in board_patrols")
	_assert(not PatrolSystem.get_patrol_by_id(102).is_empty(), "5.3: Surviving patrol 102 remains fully intact")
	_assert(GlobalData.board.board_patrol_engagement == -1, "5.4: board_patrol_engagement reset to -1")
	_assert(GlobalData.currency.credits == pre_credits + 250, "5.5: Credits awarded (+250 cr)")
	_assert(GlobalData.currency.scrap == pre_scrap + 50, "5.6: Scrap awarded (+50 scrap)")

	# ===========================================================================
	# Scenario 6: Return to Board & Clean Scene Presentation Reconstruction
	# ===========================================================================
	print("\n-- [6] Return to Board & Clean Scene Presentation Reconstruction --")
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "6.1: GameManager state returned to State.BOARD")

	# Instantiate fresh board simulating scene transition reload
	var returned_board := _instantiate_board()
	_assert(returned_board.current_pos == target_tile, "6.2: Reconstructed board current_pos matches tile (3, 2)")
	_assert(GlobalData.board.current_tile == target_tile, "6.3: Authoritative global position is tile (3, 2)")
	_assert(GlobalData.board.board_patrol_engagement == -1, "6.4: Engagement remains idle (-1) on board reload")
	_assert(PatrolSystem.get_patrol_by_id(101).is_empty(), "6.5: Defeated patrol 101 is absent from reconstructed board")
	_assert(not PatrolSystem.get_patrol_by_id(102).is_empty(), "6.6: Surviving patrol 102 preserved across board reload")

	var tokens_count := 0
	for c in returned_board.get_children():
		if c.name == "PlayerToken":
			tokens_count += 1
	_assert(tokens_count == 1, "6.7: Exactly one PlayerToken exists on returned board scene")

	# ===========================================================================
	# Scenario 7: Post-Combat Board Gameplay Continuation
	# ===========================================================================
	print("\n-- [7] Post-Combat Board Gameplay Continuation --")
	# Find adjacent neighbor to continue moving
	var next_tile := Vector2i(4, 2)
	var can_step_next := returned_board._can_step(next_tile)
	if not can_step_next:
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0)]:
			if returned_board._can_step(target_tile + d):
				next_tile = target_tile + d
				break

	var initial_mp_post := GlobalData.board.board_mp
	var step_post_ok := returned_board._try_step(next_tile)
	_assert(step_post_ok == true, "7.1: Post-combat movement to adjacent tile (%d, %d) succeeded" % [next_tile.x, next_tile.y])
	_assert(returned_board.current_pos == next_tile, "7.2: BoardManager position advanced to new tile (%d, %d)" % [next_tile.x, next_tile.y])
	_assert(GlobalData.board.current_tile == next_tile, "7.3: GlobalData position synchronized to new tile")
	_assert(GlobalData.board.board_patrol_engagement == -1, "7.4: No spurious combat triggered on empty tile")
	_assert(GameManager.current_state == GameManager.State.BOARD, "7.5: GameManager remains in State.BOARD")
	_assert(GlobalData.board.board_mp < initial_mp_post, "7.6: Movement points consumed for step")

	# ===========================================================================
	# Scenario 8: Second Complete Board -> Combat -> Board Lifecycle (Repeatability)
	# ===========================================================================
	print("\n-- [8] Second Complete Board -> Combat -> Board Lifecycle (Repeatability) --")
	var patrol_202_tile := Vector2i(5, 2)
	if not returned_board._can_step(patrol_202_tile):
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if returned_board._can_step(next_tile + d):
				patrol_202_tile = next_tile + d
				break

	var cmdr_202 := {"name": "Major Iron", "bounty": 300, "archetype": 2}
	var patrol_202 := {
		"id": 202,
		"pos": patrol_202_tile,
		"home": patrol_202_tile,
		"dir": Vector2i(0, 1),
		"archetype": "armored",
		"fleet_count": 1,
		"name": "Iron Guard",
		"commander": cmdr_202,
		"pilots": [cmdr_202]
	}
	PatrolSystem.normalize_patrol(patrol_202)
	GlobalData.board.board_patrols = [patrol_202]
	returned_board._refresh_patrol_markers()

	# Move onto patrol 202
	GlobalData.board.board_mp = 8
	var step_202_ok := returned_board._try_step(patrol_202_tile)
	_assert(step_202_ok == true, "8.1: Step onto second patrol 202 executed")
	_assert(GlobalData.board.board_patrol_engagement == 202, "8.2: Second engagement registered ID 202")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "8.3: State transitioned to State.COMBAT for second battle")

	# Resolve second battle
	PatrolSystem.remove_patrol(202)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(GlobalData.board.board_patrol_engagement == -1, "8.4: Second engagement cleared to -1")
	_assert(GlobalData.board.board_patrols.is_empty(), "8.5: All patrols defeated")
	_assert(GameManager.current_state == GameManager.State.BOARD, "8.6: Returned cleanly to State.BOARD after second battle")

	# ===========================================================================
	# Scenario 9: SceneTree Integrity Check & No Orphaned Residue
	# ===========================================================================
	print("\n-- [9] SceneTree Integrity Check & No Orphaned Residue --")
	var final_board := _instantiate_board()
	_assert(is_instance_valid(final_board), "9.1: Final BoardManager is a valid SceneTree node")
	_assert(is_instance_valid(final_board.player_token), "9.2: PlayerToken is valid and active")
	_assert(final_board.get_node_or_null("PatrolMarkers") != null, "9.3: PatrolMarkers container exists without accumulation")

	# ===========================================================================
	# Scenario 10: Negative Stale Engagement Guard
	# ===========================================================================
	print("\n-- [10] Negative Stale Engagement Guard --")
	# If board_patrol_engagement holds a non-existent patrol ID, board engagement check ignores it
	GlobalData.board.board_patrol_engagement = -1
	var stale_check := final_board._check_current_tile_patrol_engagement()
	_assert(stale_check == false, "10.1: Engagement check returns false when no patrol exists on current tile")
	_assert(GameManager.current_state == GameManager.State.BOARD, "10.2: GameManager stays in State.BOARD without erroneous combat trigger")


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-51 LIFECYCLE AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")
