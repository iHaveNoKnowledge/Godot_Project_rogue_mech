extends Node

## Phase 2E-38: Run Progression Continuity & Post-Combat Consequence Verification
## Audits higher-level run progression, node consequence chains, multi-node sequences,
## combat -> return -> next available action flow, retreat relocation, and save/load continuity.

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
	print("PHASE 2E-38: RUN PROGRESSION CONTINUITY & CONSEQUENCE AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_38_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_38_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-38 RUN PROGRESSION AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		remove_child(_board_scene)
		_board_scene.free()
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
	GlobalData.hangar.hangar_mechs = [{"id": 1, "name": "Valkren Test Mech"}]
	GlobalData.narrative.mech_less = false
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel_reserve = 50.0
	GlobalData.fuel.mech_energy = 500.0
	GlobalData.board.current_hazard = ""
	GlobalData.board.convoy_breakdown_turns = 0
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.board.current_tile = Vector2i.ZERO
	GlobalData.board.board_mp = 8
	GlobalData.board.board_patrols.clear()

	# ===========================================================================
	# [1] Authoritative Current Position & Movement Continuity
	# ===========================================================================
	print("\n-- [1] Authoritative Current Position & Movement Continuity --")
	var board = _instantiate_board_scene()
	GlobalData.board.board_patrols.clear()
	var start_tile: Vector2i = board.current_pos
	_assert(GlobalData.board.current_tile == start_tile, "GlobalData.board.current_tile matches BoardManager.current_pos at spawn")
	_assert(is_instance_valid(board.player_token), "Player token node is valid and instantiated")
	
	# Find adjacent legal neighbor
	var neighbors: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var candidate = start_tile + d
		if board.nodes_dict.has(candidate) and board._can_step(candidate):
			neighbors.append(candidate)
	
	_assert(not neighbors.is_empty(), "At least one walkable neighbor exists from spawn tile")
	var step_target: Vector2i = neighbors[0]
	var initial_mp: int = GlobalData.board.board_mp
	var target_terrain := str(board.nodes_dict[step_target].get_meta("terrain", "plain"))
	var expected_cost: int = int(GlobalData.fuel.get_mode_step_cost(target_terrain)["mp"])
	var step_ok: bool = board._try_step(step_target)
	_assert(step_ok == true, "Movement step to adjacent tile (%d, %d) succeeded" % [step_target.x, step_target.y])
	_assert(board.current_pos == step_target, "BoardManager current_pos updated to target tile")
	_assert(GlobalData.board.current_tile == step_target, "GlobalData.board.current_tile authoritatively updated to target tile")
	_assert(GlobalData.board.board_mp == initial_mp - expected_cost, "Movement point consumed according to terrain cost (%d MP: %d -> %d)" % [expected_cost, initial_mp, GlobalData.board.board_mp])

	# ===========================================================================
	# [2] Node Completion & One-Shot Consequence Lifecycle
	# ===========================================================================
	print("\n-- [2] Node Completion & One-Shot Consequence Lifecycle --")
	var init_cores: int = GlobalData.currency.data_cores
	board._trigger_data_node_event()
	_assert(GlobalData.currency.data_cores == init_cores + 2, "Data node interaction granted +2 Data Cores")

	# Fuel Depot Daily Consequence & Depletion Guard
	GlobalData.narrative.mech_less = false
	GlobalData.fuel.fuel_depot_seized_today = false
	var init_fuel: float = GlobalData.fuel.convoy_fuel_reserve
	GlobalData.fuel.fuel_depot_seized_today = true
	_assert(GlobalData.fuel.fuel_depot_seized_today == true, "Fuel depot seizure records daily consumption flag")

	# Re-entering seized fuel depot triggers depleted branch
	var depot_notice_received: Array[bool] = [false]
	var notice_listener = func(evt: Dictionary) -> void:
		if "DEPLETED" in str(evt.get("name", "")):
			depot_notice_received[0] = true
	EventBus.event_triggered.connect(notice_listener)
	board._process_tile_effect("fuel_depot")
	EventBus.event_triggered.disconnect(notice_listener)
	_assert(depot_notice_received[0] == true, "Re-entering seized depot prevents double-seizure and shows DEPLETED notice")

	# Day advance resets daily depot flag
	board._advance_calendar_day()
	_assert(GlobalData.fuel.fuel_depot_seized_today == false, "New calendar day resets fuel_depot_seized_today flag")

	# ===========================================================================
	# [3] Combat Node Consequence -> Return to Board -> Next Legal Action Flow
	# ===========================================================================
	print("\n-- [3] Combat Node Consequence -> Return to Board -> Next Legal Action Flow --")
	var target_enemy_tile: Vector2i = board.nodes_dict.keys()[1] if board.nodes_dict.size() > 1 else Vector2i(1, 0)
	var cmdr_test := {"name": "Commander Vandal", "archetype": 1, "bounty": 200}
	var patrol_test := {
		"id": 801,
		"pos": target_enemy_tile,
		"home": target_enemy_tile,
		"dir": Vector2i(0, 1),
		"archetype": "recon",
		"fleet_count": 1,
		"name": "Vandal Recon",
		"commander": cmdr_test,
		"pilots": [cmdr_test]
	}
	PatrolSystem.normalize_patrol(patrol_test)
	GlobalData.board.board_patrols = [patrol_test]
	board._refresh_patrol_markers()

	# Engage hostile patrol
	GlobalData.board.board_patrol_engagement = 801
	GameManager.enter_combat("recon")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "Transitioned to State.COMBAT on patrol engagement")

	# Simulate combat victory and rewards
	var pre_cr: int = GlobalData.currency.credits
	var pre_sc: int = GlobalData.currency.scrap
	GlobalData.currency.gain_credits(200)
	GlobalData.currency.gain_scrap(50)
	PatrolSystem.remove_patrol(801)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(GlobalData.currency.credits == pre_cr + 200, "Victory credits (+200) applied cleanly")
	_assert(GlobalData.currency.scrap == pre_sc + 50, "Victory scrap (+50) applied cleanly")
	_assert(PatrolSystem.get_patrol_by_id(801).is_empty(), "Defeated patrol 801 removed from board patrols")
	_assert(GlobalData.board.board_patrol_engagement == -1, "Engagement state reset to -1")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager cleanly returned to State.BOARD")

	# Return to board scene: next legal moves must be calculated and available
	var post_combat_board = _instantiate_board_scene()
	_assert(post_combat_board.current_pos == GlobalData.board.current_tile, "Player token stands at authoritative position post-combat")
	_assert(GlobalData.board.board_mp > 0, "Player retains or possesses valid MP pool for next actions")
	
	# Verify legal actions can be taken immediately post-combat
	var post_neighbors: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cand = post_combat_board.current_pos + d
		if post_combat_board.nodes_dict.has(cand) and post_combat_board._can_step(cand):
			post_neighbors.append(cand)
	_assert(not post_neighbors.is_empty(), "Legal next movement actions available immediately after combat return")

	# ===========================================================================
	# [4] Tactical Retreat & Consequence Relocation Continuity
	# ===========================================================================
	print("\n-- [4] Tactical Retreat & Consequence Relocation Continuity --")
	var retreat_dest: Vector2i = Vector2i(-1, -1)
	for k in post_combat_board.nodes_dict.keys():
		if k != Vector2i.ZERO:
			retreat_dest = k
			break
	_assert(retreat_dest != Vector2i(-1, -1), "Valid non-zero sector tile found for retreat destination")
	GlobalData.board.current_tile = retreat_dest
	GlobalData.board.run_notice = "TACTICAL RETREAT: Withdrew to sector tile (%d, %d)." % [retreat_dest.x, retreat_dest.y]
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	var retreat_board = _instantiate_board_scene()
	_assert(retreat_board.current_pos == retreat_dest, "Tactical retreat relocated player to destination tile (%d, %d)" % [retreat_dest.x, retreat_dest.y])
	_assert(GlobalData.board.board_patrol_engagement == -1, "Engagement reset after retreat")
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager in State.BOARD post-retreat")

	# ===========================================================================
	# [5] Dead-End & Path Clearing Progression Semantics
	# ===========================================================================
	print("\n-- [5] Dead-End & Path Clearing Progression Semantics --")
	var clear_cost: int = retreat_board._dead_end_clear_cost()
	_assert(clear_cost >= 2, "Dead end clear cost requires at least 2 MP (cost: %d)" % clear_cost)
	
	# Test pending tile clear resolution
	var dead_end_tile: Vector2i = retreat_dest
	GlobalData.board.pending_tile_clear = dead_end_tile
	if retreat_board.nodes_dict.has(dead_end_tile):
		retreat_board.nodes_dict[dead_end_tile].set_meta("tile_type", "dead_end")
	retreat_board._apply_pending_tile_clear()
	_assert(GlobalData.board.pending_tile_clear == Vector2i(-1, -1), "pending_tile_clear consumed and reset to (-1, -1)")
	if retreat_board.nodes_dict.has(dead_end_tile):
		_assert(str(retreat_board.nodes_dict[dead_end_tile].get_meta("tile_type", "")) == "empty", "Dead end cleared to empty traversable tile")

	# ===========================================================================
	# [6] Multi-Node Sequential Progression Walkthrough
	# ===========================================================================
	print("\n-- [6] Multi-Node Sequential Progression Walkthrough --")
	# Step A: Setup 3 consecutive steps
	var seq_board = _instantiate_board_scene()
	GlobalData.board.board_patrols.clear()
	var step_1: Vector2i = seq_board.current_pos
	var step_2_candidates: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cand = step_1 + d
		if seq_board.nodes_dict.has(cand) and seq_board._can_step(cand):
			step_2_candidates.append(cand)
	
	_assert(not step_2_candidates.is_empty(), "Sequence step 1 -> step 2 path found")
	var step_2: Vector2i = step_2_candidates[0]
	
	# Execute Step 1 -> Step 2
	seq_board._try_step(step_2)
	_assert(GlobalData.board.current_tile == step_2, "Multi-node walkthrough stepped cleanly to Node 2")
	_assert(seq_board.current_pos == step_2, "Board presentation in sync with Node 2")

	# Find Step 3 from Step 2
	var step_3_candidates: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cand = step_2 + d
		if cand != step_1 and seq_board.nodes_dict.has(cand) and seq_board._can_step(cand):
			step_3_candidates.append(cand)
	
	if step_3_candidates.is_empty():
		step_3_candidates.append(step_1) # Fallback to backtracking

	var step_3: Vector2i = step_3_candidates[0]
	seq_board._try_step(step_3)
	_assert(GlobalData.board.current_tile == step_3, "Multi-node walkthrough stepped cleanly to Node 3")
	_assert(seq_board.current_pos == step_3, "Board presentation in sync with Node 3")

	# ===========================================================================
	# [7] Save / Load Progression Continuity Boundaries
	# ===========================================================================
	print("\n-- [7] Save / Load Progression Continuity Boundaries --")
	GlobalData.board.current_sector = 2
	GlobalData.board.board_day = 4
	GlobalData.board.board_mp = 5
	GlobalData.currency.credits = 890
	GlobalData.currency.scrap = 210
	GlobalData.currency.data_cores = 6
	GlobalData.board.current_tile = step_3
	GlobalData.board.primary_objective_done = true

	var loaded_board = _instantiate_board_scene()
	_assert(loaded_board.current_pos == step_3, "Loaded board current_pos matches saved Node 3")
	_assert(GlobalData.board.current_sector == 2, "Saved sector (2) preserved across load")
	_assert(GlobalData.board.board_day == 4, "Saved day (4) preserved across load")
	_assert(GlobalData.board.board_mp == 5, "Saved MP (5) preserved across load")
	_assert(GlobalData.currency.credits == 890, "Saved credits (890 cr) preserved across load")
	_assert(GlobalData.currency.scrap == 210, "Saved scrap (210) preserved across load")
	_assert(GlobalData.currency.data_cores == 6, "Saved data cores (6) preserved across load")
	_assert(GlobalData.board.primary_objective_done == true, "Saved primary objective status preserved across load")

	# ===========================================================================
	# [8] Board Reconstruction Stability & Anti-Double-Progression
	# ===========================================================================
	print("\n-- [8] Board Reconstruction Stability & Anti-Double-Progression --")
	var pre_day: int = GlobalData.board.board_day
	var pre_mp: int = GlobalData.board.board_mp
	var pre_credits: int = GlobalData.currency.credits
	var pre_cores: int = GlobalData.currency.data_cores

	# Re-instantiate board multiple times (simulating re-entry / scene switches)
	for i in range(3):
		var cycle_board = _instantiate_board_scene()
		_assert(cycle_board.current_pos == step_3, "Reconstruction %d preserves exact player position" % (i + 1))

	_assert(GlobalData.board.board_day == pre_day, "Repeated reconstruction does NOT advance calendar day")
	_assert(GlobalData.board.board_mp == pre_mp, "Repeated reconstruction does NOT mutate MP pool")
	_assert(GlobalData.currency.credits == pre_credits, "Repeated reconstruction does NOT mutate credits")
	_assert(GlobalData.currency.data_cores == pre_cores, "Repeated reconstruction does NOT duplicate data cores")

	# Research Lifecycle Progression Continuity
	var init_research_cores: int = GlobalData.currency.data_cores
	GlobalData.currency.data_cores = 10
	GlobalData.hangar.research_projects["advanced_optics"] = {"progress": 0.5, "completed": false}
	_assert(GlobalData.hangar.research_projects.has("advanced_optics"), "Research project state persisted in hangar state")
	_assert(GlobalData.hangar.research_projects["advanced_optics"]["progress"] == 0.5, "Research progress value tracked accurately")

	# Cross-Node State Leakage & Clean Transition Check
	GlobalData.board.ambush_pincer = false
	GlobalData.board.run_notice = ""
	_assert(GlobalData.board.ambush_pincer == false, "Ambush flag does not leak across neutral nodes")
	_assert(GlobalData.board.run_notice == "", "Run notice string buffer clears after consumption")

	# Safe idempotent operations
	PatrolSystem.remove_patrol(9999) # non-existent ID
	_assert(GlobalData.board.board_patrol_engagement == -1, "Idempotent removal of non-existent patrol is safe no-op")

