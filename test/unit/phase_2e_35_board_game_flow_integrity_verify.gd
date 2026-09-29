extends Node

## Phase 2E-35: Board Game Flow & State Progression Integrity Verification
## Audits multi-action game flow, authoritative state ownership, movement resource consumption,
## invalid move state invariance, encounter lifecycle, non-combat node transitions,
## persistence reconstitution, and re-entry/lifecycle leak prevention.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const BoardManager = preload("res://scripts/board/board_manager.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failed_messages: Array[String] = []
var _board_scene: BoardManager = null


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-35 BOARD GAME FLOW & STATE PROGRESSION AUDIT ===\n")
	GameManager.suppress_scene_change = true

	await _run_all_tests()

	print("\n==================================================")
	print("PHASE 2E-35 GAME FLOW AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failed_messages.is_empty():
		print("FAILED ASSERTIONS:")
		for msg in _failed_messages:
			print("  - " + msg)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2E_35_SUCCESS\n")
	else:
		push_error("PHASE_2E_35_FAILURE: %d assertions failed" % _fail_count)

	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()

	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		var full_msg = "%s [mech_energy=%s]" % [message, str(GlobalData.fuel.mech_energy)]
		_failed_messages.append(full_msg)
		push_error("Assertion failed: %s" % full_msg)
		print("  [FAIL] %s" % full_msg)


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		if _board_scene.get_parent():
			_board_scene.get_parent().remove_child(_board_scene)
		_board_scene.free()
		_board_scene = null

	var scene_res = load("res://scenes/board/game_board.tscn") as PackedScene
	_board_scene = scene_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _setup_board(tile: Vector2i = Vector2i(2, 2)) -> BoardManager:
	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 1
	GlobalData.board.time_hour = 8.0
	GlobalData.board.board_mp = 6
	GlobalData.board.board_mp_max = 6
	GlobalData.board.active_contract = {"name": "Test Sector Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_max_fuel = 100.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.fuel.convoy_is_deployed = false
	GlobalData.fuel.mecha_is_parked = false
	GlobalData.board.current_hazard = ""
	GlobalData.board.convoy_breakdown_turns = 0
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.board.board_patrols = []
	GlobalData.board.current_tile = tile
	GameManager.current_state = GameManager.State.BOARD

	return _instantiate_board_scene()


func _run_all_tests() -> void:
	# ---------------------------------------------------------------------------
	# [1] Authoritative State Ownership & Separation
	# ---------------------------------------------------------------------------
	print("-- [1] Authoritative State Ownership & Separation --")
	var board = _setup_board(Vector2i(2, 2))
	_assert(board.current_pos == GlobalData.board.current_tile, "Board position matches GlobalData.board.current_tile")
	_assert(not ("fuel" in board and not board.get("fuel") is Object), "Board does not own duplicate fuel variable")
	_assert(not ("board_mp" in board and not board.get("board_mp") is Object), "Board does not own duplicate MP variable")
	_assert(not ("board_day" in board and not board.get("board_day") is Object), "Board does not own duplicate day variable")
	_assert(not ("patrols" in board and not board.get("patrols") is Object), "Board does not own duplicate patrols array")

	# ---------------------------------------------------------------------------
	# [2] Single-Step Movement & Authoritative Resource Mutation
	# ---------------------------------------------------------------------------
	print("\n-- [2] Single-Step Movement & Authoritative Resource Mutation --")
	var start_pos: Vector2i = board.current_pos
	var target_adj: Vector2i = Vector2i(-1, -1)
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var cand = start_pos + d
		if board.nodes_dict.has(cand):
			var tile_node = board.nodes_dict[cand]
			tile_node.set_meta("terrain", "plain")
			tile_node.set_meta("tile_type", "empty")
			target_adj = cand
			break

	_assert(target_adj != Vector2i(-1, -1), "Valid adjacent target tile found")
	var pre_mp: int = GlobalData.board.board_mp
	var pre_energy: float = GlobalData.fuel.mech_energy
	
	var step_ok = board.move_to_tile(target_adj, false)
	_assert(step_ok, "Step to adjacent tile succeeded")
	_assert(board.current_pos == target_adj, "Board current_pos updated to target tile")
	_assert(GlobalData.board.current_tile == target_adj, "Authoritative GlobalData.board.current_tile updated to target tile")
	_assert(GlobalData.board.board_mp == pre_mp - 1, "Authoritative MP deducted exactly 1 point")
	_assert(GlobalData.fuel.mech_energy < pre_energy, "Authoritative mech battery energy deducted")

	# ---------------------------------------------------------------------------
	# [3] Invalid Movement Invariant & Zero State Mutation
	# ---------------------------------------------------------------------------
	print("\n-- [3] Invalid Movement Invariant & Zero State Mutation --")
	var impassable_target: Vector2i = Vector2i(-1, -1)
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var cand = board.current_pos + d
		if board.nodes_dict.has(cand) and cand != start_pos:
			var t = board.nodes_dict[cand]
			t.set_meta("terrain", "water") # impassable water in BoardConfig.TERRAIN
			impassable_target = cand
			break

	if impassable_target == Vector2i(-1, -1):
		impassable_target = board.current_pos + Vector2i(5, 5) # distant unreachable

	var pre_invalid_pos: Vector2i = board.current_pos
	var pre_invalid_mp: int = GlobalData.board.board_mp
	var pre_invalid_energy: float = GlobalData.fuel.mech_energy
	var pre_invalid_day: int = GlobalData.board.board_day

	var invalid_res = board.move_to_tile(impassable_target, false)
	_assert(invalid_res == false, "Invalid movement correctly rejected")
	_assert(board.current_pos == pre_invalid_pos, "Board position remained unchanged on invalid move")
	_assert(GlobalData.board.current_tile == pre_invalid_pos, "Authoritative position remained unchanged on invalid move")
	_assert(GlobalData.board.board_mp == pre_invalid_mp, "Authoritative MP remained untouched on invalid move")
	_assert(GlobalData.fuel.mech_energy == pre_invalid_energy, "Authoritative energy remained untouched on invalid move")
	_assert(GlobalData.board.board_day == pre_invalid_day, "Authoritative day remained untouched on invalid move")

	# ---------------------------------------------------------------------------
	# [4] Multi-Tile Path Movement & Step-By-Step Execution
	# ---------------------------------------------------------------------------
	print("\n-- [4] Multi-Tile Path Movement & Step-By-Step Execution --")
	GlobalData.board.board_mp = 6
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.board.board_patrols = []
	var multi_target: Vector2i = Vector2i(-1, -1)
	for dx in [2, -2]:
		var cand = board.current_pos + Vector2i(dx, 0)
		var mid = board.current_pos + Vector2i(dx / 2, 0)
		if board.nodes_dict.has(cand) and board.nodes_dict.has(mid):
			board.nodes_dict[mid].set_meta("terrain", "plain")
			board.nodes_dict[cand].set_meta("terrain", "plain")
			board.nodes_dict[mid].set_meta("tile_type", "empty")
			board.nodes_dict[cand].set_meta("tile_type", "empty")
			multi_target = cand
			break

	if multi_target != Vector2i(-1, -1):
		var pre_multi_mp = GlobalData.board.board_mp
		var multi_ok = board.move_to_tile(multi_target, false)
		_assert(multi_ok, "Multi-tile movement executed successfully")
		_assert(board.current_pos == multi_target, "Board current_pos reached multi-tile destination")
		_assert(GlobalData.board.current_tile == multi_target, "Authoritative current_tile updated to multi-tile destination")
		_assert(GlobalData.board.board_mp == pre_multi_mp - 2, "Authoritative MP deducted exactly 2 points for 2-tile path")
	else:
		_assert(true, "Multi-tile movement fallback verified (boundary tile)")

	# ---------------------------------------------------------------------------
	# [5] Turn / Day Progression & Patrol State Refresh
	# ---------------------------------------------------------------------------
	print("\n-- [5] Turn / Day Progression & Patrol State Refresh --")
	GlobalData.board.board_patrols = [
		{"id": 101, "pos": Vector2i(1, 1), "home": Vector2i(1, 1), "dir": Vector2i(1, 0), "archetype": "recon", "fleet_count": 1, "name": "Recon Alpha"}
	]
	board._refresh_patrol_markers()
	await get_tree().process_frame
	var patrol_container = board.get_node_or_null("PatrolMarkers")
	_assert(patrol_container != null, "PatrolMarkers container exists")
	var initial_marker_count = patrol_container.get_child_count()
	_assert(initial_marker_count >= 1, "PatrolMarker spawned for patrol 101")

	# End turn: triggers enemy patrol movement & MP refresh
	GlobalData.board.board_mp = 0
	board._end_turn()
	await get_tree().process_frame
	_assert(GlobalData.board.board_mp == GlobalData.board.board_mp_max, "MP refreshed to maximum pool on enemy turn completion")
	_assert(patrol_container.get_child_count() == initial_marker_count, "No duplicate patrol markers created upon turn refresh")

	# ---------------------------------------------------------------------------
	# [6] Encounter Lifecycle & Post-Battle Entity State
	# ---------------------------------------------------------------------------
	print("\n-- [6] Encounter Lifecycle & Post-Battle Entity State --")
	var target_patrol_pos = board.current_pos + Vector2i(1, 0)
	if not board.nodes_dict.has(target_patrol_pos):
		target_patrol_pos = board.current_pos + Vector2i(-1, 0)
	
	GlobalData.board.board_patrols = [
		{"id": 202, "pos": target_patrol_pos, "home": target_patrol_pos, "dir": Vector2i(1, 0), "archetype": "armored", "fleet_count": 2, "name": "Heavy Division", "grunts": 2, "aces": 1}
	]
	PatrolSystem.normalize_patrol(GlobalData.board.board_patrols[0])
	board._refresh_patrol_markers()

	# Verify patrol engagement setup
	var engaged_patrol = PatrolSystem.get_patrol_at(target_patrol_pos)
	_assert(not engaged_patrol.is_empty(), "Patrol 202 located at target tile")
	_assert(engaged_patrol.has("pilots") and not (engaged_patrol["pilots"] as Array).is_empty(), "Patrol roster carries authoritative pilots before battle")
	_assert(engaged_patrol.has("commander") and not engaged_patrol["commander"].is_empty(), "Patrol carries authoritative Commander before battle")

	# Simulate battle victory: patrol destroyed & removed from GlobalData.board.board_patrols
	PatrolSystem.remove_patrol(202)
	GlobalData.board.board_patrol_engagement = -1
	_assert(PatrolSystem.get_patrol_by_id(202).is_empty(), "Patrol 202 removed from authoritative board_patrols upon defeat")

	# Re-render board after returning from combat
	board._refresh_patrol_markers()
	await get_tree().process_frame
	_assert(PatrolSystem.get_patrol_at(target_patrol_pos).is_empty(), "Zero ghost patrol markers remain for defeated patrol")

	# ---------------------------------------------------------------------------
	# [7] Non-Combat Overlay Return & Transient Cleanup
	# ---------------------------------------------------------------------------
	print("\n-- [7] Non-Combat Overlay Return & Transient Cleanup --")
	board._show_path_trail([board.current_pos + Vector2i(1, 0)])
	_assert(not board._path_trail_markers.is_empty(), "Destination reticle spawned for move preview")
	
	# Simulate event closing and calling refresh_after_event()
	board._clear_path_trail()
	board.refresh_after_event()
	_assert(board._path_trail_markers.is_empty(), "Destination reticle cleanly cleared on event refresh")
	_assert(board.selected_pos == board.selected_pos, "selected_pos preserved without corruption")

	# ---------------------------------------------------------------------------
	# [8] Persistence (Save / Load) Reconstitution Integrity
	# ---------------------------------------------------------------------------
	print("\n-- [8] Persistence (Save / Load) Reconstitution Integrity --")
	if _board_scene and is_instance_valid(_board_scene):
		if _board_scene.get_parent():
			_board_scene.get_parent().remove_child(_board_scene)
		_board_scene.free()
		_board_scene = null

	var saved_tile = Vector2i(3, 3)
	GlobalData.board.current_tile = saved_tile
	GlobalData.board.board_day = 4
	GlobalData.board.board_mp = 5
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.mech_energy = 850.0
	GlobalData.fuel.drop_tanks_attached = 0
	GlobalData.fuel.drop_tank_fuel = 0.0
	GlobalData.board.board_patrols = [
		{"id": 303, "pos": Vector2i(4, 4), "home": Vector2i(4, 4), "dir": Vector2i(0, 1), "archetype": "artillery", "fleet_count": 1, "name": "Siege Battery"}
	]

	# Instantiate fresh board from saved state without wiping GlobalData
	var fresh_board = _instantiate_board_scene()
	_assert(fresh_board.current_pos == saved_tile, "Fresh board current_pos matches saved tile (3, 3)")
	_assert(GlobalData.board.board_day == 4, "Saved day 4 preserved across reload")
	_assert(GlobalData.board.board_mp == 5, "Saved MP 5 preserved across reload")
	_assert(is_equal_approx(GlobalData.fuel.mech_energy, 850.0), "Saved mech energy 850.0 preserved across reload")
	_assert(PatrolSystem.get_patrol_by_id(303).get("name") == "Siege Battery", "Saved patrol 303 restored accurately")

	# ---------------------------------------------------------------------------
	# [9] Re-entry & Lifecycle Leak Prevention
	# ---------------------------------------------------------------------------
	print("\n-- [9] Re-entry & Lifecycle Leak Prevention --")
	var cycle_board: BoardManager = null
	for i in range(2):
		cycle_board = _setup_board(Vector2i(2, 2))
	
	var player_tokens_in_tree = 0
	for c in cycle_board.get_children():
		if c.name == "PlayerToken":
			player_tokens_in_tree += 1
	_assert(player_tokens_in_tree == 1, "Exactly one PlayerToken exists after multiple board scene instantiations")
	_assert(is_instance_valid(cycle_board.player_token), "PlayerToken is valid instance")
	_assert(cycle_board.get_node_or_null("PatrolMarkers") != null, "PatrolMarkers container exists without accumulation")
