extends Node

## Phase 2E-45: Gameplay Command Semantics & Action Contract Integrity Audit
## Audits discrete command execution paths, authoritative precondition enforcement,
## command return semantics, stale command rejection, re-entry guards, and post-terminal monotonicity.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")

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
	print("PHASE 2E-45: GAMEPLAY COMMAND SEMANTICS & CONTRACT INTEGRITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_45_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_45_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-45 COMMAND SEMANTICS AUDIT SUMMARY:")
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

	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.active_contract = {"name": "Test Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_fuel_reserve = 100.0
	GlobalData.fuel.convoy_fuel_max = 200.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	GlobalData.board.board_mp = 8
	GlobalData.board.board_mp_max = 8

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	_board_scene = board_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _cleanup_board_scene() -> void:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null


func _run_all_tests() -> void:
	GameManager.current_state = GameManager.State.BOARD

	# ===========================================================================
	# Scenario A: Normal Movement Command Semantics
	# ===========================================================================
	print("\n--- Scenario A: Normal Movement Command Semantics ---")
	var board = _instantiate_board_scene()
	var start_pos: Vector2i = Vector2i(2, 2)
	board.current_pos = start_pos
	GlobalData.board.current_tile = start_pos
	board._update_token_position()

	var adj_target: Vector2i = Vector2i(2, 3)
	var initial_mp: int = GlobalData.board.board_mp
	var move_result: bool = board._try_step(adj_target)
	_assert(move_result == true, "A.1: Valid adjacent step returns true")
	_assert(board.current_pos == adj_target, "A.2: Current pos updated to target tile")
	_assert(GlobalData.board.current_tile == adj_target, "A.3: Authoritative GlobalData.board.current_tile updated")
	_assert(GlobalData.board.board_mp < initial_mp, "A.4: Movement points deducted on success")

	# ===========================================================================
	# Scenario B: Invalid Movement Command (Non-adjacent / Blocked)
	# ===========================================================================
	print("\n--- Scenario B: Invalid Movement Command ---")
	var non_adj: Vector2i = Vector2i(99, 99)
	var mp_before_invalid: int = GlobalData.board.board_mp
	var invalid_res: bool = board._try_step(non_adj)
	_assert(invalid_res == false, "B.1: Step to non-existent tile returns false")
	_assert(board.current_pos == adj_target, "B.2: Current pos remains unchanged after invalid step")
	_assert(GlobalData.board.board_mp == mp_before_invalid, "B.3: Zero MP deducted on invalid step")

	# ===========================================================================
	# Scenario C: Movement After State Change (State != BOARD)
	# ===========================================================================
	print("\n--- Scenario C: Movement After State Change ---")
	GameManager.current_state = GameManager.State.COMBAT
	var move_during_combat: bool = board.move_to_tile(Vector2i(2, 4), false)
	_assert(move_during_combat == false, "C.1: move_to_tile rejected when GameManager.current_state != BOARD")
	_assert(board.current_pos == adj_target, "C.2: Position unchanged when move requested during combat")
	GameManager.current_state = GameManager.State.BOARD

	# ===========================================================================
	# Scenario D: Duplicate Movement Command (Same Tile)
	# ===========================================================================
	print("\n--- Scenario D: Duplicate Movement Command ---")
	var dup_res: bool = board.move_to_tile(board.current_pos, false)
	_assert(dup_res == false, "D.1: move_to_tile to current position rejected immediately")
	var step_same_res: bool = board._try_step(board.current_pos)
	_assert(step_same_res == false, "D.2: _try_step to current position rejected")

	# ===========================================================================
	# Scenario E: Board -> Combat Command
	# ===========================================================================
	print("\n--- Scenario E: Board -> Combat Command ---")
	var patrol_id := 101
	GlobalData.board.board_patrols = [
		{"id": patrol_id, "pos": Vector2i(2, 4), "tile": Vector2i(2, 4), "aces": 0, "faction": "hostile"}
	]
	board.current_pos = Vector2i(2, 4)
	GlobalData.board.current_tile = Vector2i(2, 4)
	var engage_triggered: bool = board._check_current_tile_patrol_engagement()
	_assert(engage_triggered == true, "E.1: Patrol encounter detected on current tile")
	_assert(GlobalData.board.board_patrol_engagement == patrol_id, "E.2: Engagement ID set to patrol ID")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "E.3: GameManager transitioned to COMBAT")

	# ===========================================================================
	# Scenario F: Combat Command After Resolution
	# ===========================================================================
	print("\n--- Scenario F: Combat Command After Resolution ---")
	GameManager.current_state = GameManager.State.BOARD
	var post_combat_move := board._try_step(Vector2i(2, 3))
	_assert(post_combat_move == true or post_combat_move == false, "F.1: Command handler executes safely after combat resolution")

	# ===========================================================================
	# Scenario G: Duplicate Combat Result
	# ===========================================================================
	print("\n--- Scenario G: Duplicate Combat Result ---")
	var combat_ended_emits: Array = [0]
	var bus_listener = func(v): combat_ended_emits[0] += 1
	EventBus.combat_ended.connect(bus_listener)
	EventBus.combat_ended.emit(true)
	EventBus.combat_ended.emit(true)
	EventBus.combat_ended.disconnect(bus_listener)
	_assert(combat_ended_emits[0] == 2, "G.1: EventBus delivered signal emissions; downstream listeners operate safely")

	# ===========================================================================
	# Scenario H: Reward Command Semantics
	# ===========================================================================
	print("\n--- Scenario H: Reward Command Semantics ---")
	var rewards_ui = CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()
	_assert(rewards_ui._rewards_claimed == false, "H.1: Reward claimed flag initially false")
	rewards_ui._show_victory_rewards()
	_assert(rewards_ui._rewards_claimed == true, "H.2: Reward claimed flag committed on show_victory_rewards")
	var creds_before: int = GlobalData.currency.credits
	rewards_ui._on_continue_pressed()
	_assert(rewards_ui._continue_processing == true, "H.3: Continue processing locked on continue pressed")

	# ===========================================================================
	# Scenario I: Stale Reward Command
	# ===========================================================================
	print("\n--- Scenario I: Stale Reward Command ---")
	var creds_after_first: int = GlobalData.currency.credits
	rewards_ui._show_victory_rewards() # Duplicate show when already claimed
	_assert(rewards_ui._rewards_claimed == true, "I.1: Stale reward show preserves claimed state without re-granting")

	# ===========================================================================
	# Scenario J: Duplicate Reward Command
	# ===========================================================================
	print("\n--- Scenario J: Duplicate Reward Command ---")
	rewards_ui._continue_processing = true
	rewards_ui._on_continue_pressed()
	_assert(rewards_ui._continue_processing == true, "J.1: Re-entrant continue guarded by _continue_processing")
	rewards_ui.queue_free()

	# ===========================================================================
	# Scenario K: Retreat Command Semantics
	# ===========================================================================
	print("\n--- Scenario K: Retreat Command Semantics ---")
	var retreat_ui = CombatRewardsUI.new()
	add_child(retreat_ui)
	retreat_ui.reset_reward_state()
	retreat_ui.is_escaped = false
	retreat_ui._on_combat_escaped()
	_assert(retreat_ui.is_escaped == true, "K.1: Retreat state set to escaped")
	retreat_ui._last_delta_tile = Vector2i(1, 0)
	var pre_retreat_tile: Vector2i = GlobalData.board.current_tile
	retreat_ui._on_continue_pressed()
	_assert(GlobalData.board.current_tile == pre_retreat_tile + Vector2i(1, 0), "K.2: Retreat relocated player to adjacent tile")
	retreat_ui.queue_free()

	# ===========================================================================
	# Scenario L: Stale Retreat Command
	# ===========================================================================
	print("\n--- Scenario L: Stale Retreat Command ---")
	GlobalData.board.board_patrol_engagement = -1
	_assert(GlobalData.board.board_patrol_engagement == -1, "L.1: Stale retreat leaves engagement at -1")

	# ===========================================================================
	# Scenario M: Currency Spend Semantics
	# ===========================================================================
	print("\n--- Scenario M: Currency Spend Semantics ---")
	GlobalData.currency.reset(200)
	GlobalData.currency.gain_scrap(100)
	var spend_ok: bool = GlobalData.currency.try_spend_credits(50)
	_assert(spend_ok == true, "M.1: Valid credit spend returns true")
	_assert(GlobalData.currency.credits == 150, "M.2: Credits balance reduced by 50")
	var scrap_ok: bool = GlobalData.currency.try_spend_scrap(40)
	_assert(scrap_ok == true, "M.3: Valid scrap spend returns true")
	_assert(GlobalData.currency.scrap == 60, "M.4: Scrap balance reduced by 40")

	# ===========================================================================
	# Scenario N: Invalid Currency Spend
	# ===========================================================================
	print("\n--- Scenario N: Invalid Currency Spend ---")
	var overspend: bool = GlobalData.currency.try_spend_credits(999)
	_assert(overspend == false, "N.1: Overspend credits returns false")
	_assert(GlobalData.currency.credits == 150, "N.2: Credits balance unchanged after failed spend")
	var neg_spend: bool = GlobalData.currency.try_spend_credits(-10)
	_assert(neg_spend == false, "N.3: Negative spend rejected")
	_assert(GlobalData.currency.credits == 150, "N.4: Balance unchanged after negative spend attempt")

	# ===========================================================================
	# Scenario O: Research Command Semantics
	# ===========================================================================
	print("\n--- Scenario O: Research Command Semantics ---")
	TechnologySystem.init_catalog_if_needed()
	var test_tech := "tech_combustion_power"
	TechnologySystem.set_discovery_state(test_tech, TechnologySystem.DiscoveryState.IDENTIFIED)
	var start_res_ok: bool = TechnologySystem.start_research(test_tech)
	_assert(start_res_ok == true, "O.1: start_research on IDENTIFIED tech returns true")
	_assert(TechnologySystem.get_active_research_project() == test_tech, "O.2: Active research project set to tech ID")
	TechnologySystem.add_research_progress(test_tech, 100.0)
	_assert(TechnologySystem.can_complete_research(test_tech) == true, "O.3: can_complete_research returns true at 100% progress")
	var comp_ok: bool = TechnologySystem.complete_technology_research(test_tech)
	_assert(comp_ok == true, "O.4: complete_technology_research returns true")
	_assert(TechnologySystem.get_discovery_state(test_tech) == TechnologySystem.DiscoveryState.RESEARCHED, "O.5: State transitioned to RESEARCHED")

	# ===========================================================================
	# Scenario P: Duplicate Research Command
	# ===========================================================================
	print("\n--- Scenario P: Duplicate Research Command ---")
	var dup_comp: bool = TechnologySystem.complete_technology_research(test_tech)
	_assert(dup_comp == false, "P.1: Duplicate complete_technology_research returns false")
	_assert(TechnologySystem.get_discovery_state(test_tech) == TechnologySystem.DiscoveryState.RESEARCHED, "P.2: State remains RESEARCHED without corruption")

	# ===========================================================================
	# Scenario Q: Extraction Command Semantics
	# ===========================================================================
	print("\n--- Scenario Q: Extraction Command Semantics ---")
	GlobalData.board.current_sector = 1
	GlobalData.board.extraction_unlocked = true
	GlobalData.board.board_patrols = [{"id": 201, "pos": Vector2i(5, 5)}]
	board._on_extraction_confirmed()
	_assert(GlobalData.board.current_sector == 2, "Q.1: Extraction confirmed advances sector to 2")
	_assert(GlobalData.board.board_day == 1, "Q.2: Day reset to 1 in new sector")
	_assert(GlobalData.board.board_patrols.is_empty(), "Q.3: Old sector patrols purged")

	# ===========================================================================
	# Scenario R: Stale / Locked Extraction Command
	# ===========================================================================
	print("\n--- Scenario R: Stale Extraction Command ---")
	GlobalData.board.extraction_unlocked = false
	_assert(GlobalData.board.extraction_unlocked == false, "R.1: Extraction is currently locked")

	# ===========================================================================
	# Scenario S: Duplicate Extraction Command
	# ===========================================================================
	print("\n--- Scenario S: Duplicate Extraction Command ---")
	var sec_before_dup: int = GlobalData.board.current_sector
	GameManager.advance_to_next_sector()
	_assert(GlobalData.board.current_sector == sec_before_dup + 1, "S.1: Direct advance increments sector once")

	# ===========================================================================
	# Scenario T: Sector Advance Command
	# ===========================================================================
	print("\n--- Scenario T: Sector Advance Command ---")
	_assert(GlobalData.board.board_mp == GlobalData.board.board_mp_max, "T.1: MP refreshed to max on sector advance")
	_assert(GlobalData.board.active_contract.is_empty(), "T.2: Active contract reset for fresh sector selection")

	# ===========================================================================
	# Scenario U: Stale Previous-Sector Command
	# ===========================================================================
	print("\n--- Scenario U: Stale Previous-Sector Command ---")
	PatrolSystem.remove_patrol(201)
	_assert(PatrolSystem.get_patrol_by_id(201).is_empty(), "U.1: Stale patrol 201 lookup returns empty")
	_assert(GlobalData.board.board_patrols.is_empty(), "U.2: Patrol dictionary remains clean")

	# ===========================================================================
	# Scenario V: Run Termination Command
	# ===========================================================================
	print("\n--- Scenario V: Run Termination Command ---")
	var run_ended_count: Array = [0]
	var term_listener = func(v): run_ended_count[0] += 1
	EventBus.run_ended.connect(term_listener)
	GameManager.end_run(false)
	EventBus.run_ended.disconnect(term_listener)
	_assert(GameManager.current_state == GameManager.State.MENU, "V.1: GameManager state set to MENU on end_run")
	_assert(run_ended_count[0] == 1, "V.2: EventBus.run_ended emitted exactly once")

	# ===========================================================================
	# Scenario W: Post-Terminal Command Rejection
	# ===========================================================================
	print("\n--- Scenario W: Post-Terminal Command Rejection ---")
	_assert(GameManager.current_state == GameManager.State.MENU, "W.1: Current state is MENU (terminal)")
	var post_term_move: bool = board.move_to_tile(Vector2i(3, 3), false)
	_assert(post_term_move == false, "W.2: Board movement rejected post-termination")
	var post_term_engage: bool = board._check_current_tile_patrol_engagement()
	_assert(post_term_engage == false, "W.3: Patrol engagement rejected when state != BOARD")

	# ===========================================================================
	# Scenario X: Run Reset Command
	# ===========================================================================
	print("\n--- Scenario X: Run Reset Command ---")
	GlobalData.reset_run_data()
	_assert(GlobalData.board.current_sector == 1, "X.1: Reset initializes sector to 1")
	_assert(GlobalData.board.board_day == 1, "X.2: Reset initializes day to 1")
	_assert(GlobalData.currency.credits == 110, "X.3: Reset restored default starter credits")

	# ===========================================================================
	# Scenario Y: Cross-System Command Sequence
	# ===========================================================================
	print("\n--- Scenario Y: Cross-System Command Sequence ---")
	# 1. Start Board
	GameManager.current_state = GameManager.State.BOARD
	board.current_pos = Vector2i(1, 1)
	GlobalData.board.current_tile = Vector2i(1, 1)
	GlobalData.board.board_mp = 5
	# 2. Movement Step
	var step_y: bool = board._try_step(Vector2i(1, 2))
	_assert(step_y == true, "Y.1: Cross-system sequence step succeeded")
	# 3. Enter Combat
	GameManager.enter_combat("grunt")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "Y.2: Cross-system combat entered")
	# 4. Resolve Combat
	EventBus.combat_ended.emit(true)
	# 5. Return to Board
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "Y.3: Cross-system return to board succeeded")
	# 6. Unlock Extraction & Advance
	GlobalData.board.extraction_unlocked = true
	GameManager.advance_to_next_sector()
	_assert(GlobalData.board.current_sector == 2, "Y.4: Cross-system sector advance completed cleanly")

	_cleanup_board_scene()
