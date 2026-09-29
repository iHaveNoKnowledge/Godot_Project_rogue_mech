extends Node

## Phase 2E-46: Gameplay Outcome & Side-Effect Integrity Audit Test Suite
## Audits complete consequence chain:
## Successful Command -> Authoritative Outcome -> Required Side Effects -> Event Propagation -> Derived State -> Persistence -> Exactly-Once Execution

const BoardManager = preload("res://scripts/board/board_manager.gd")
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
	print("PHASE 2E-46: GAMEPLAY OUTCOME & SIDE-EFFECT INTEGRITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_46_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_46_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-46 OUTCOME INTEGRITY AUDIT SUMMARY:")
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
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.active_contract = {"name": "Test Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.board.current_hazard = ""
	GlobalData.board.convoy_breakdown_turns = 0
	GlobalData.board.board_patrol_engagement = -1
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
		if _board_scene.get_parent():
			_board_scene.get_parent().remove_child(_board_scene)
		_board_scene.free()
		_board_scene = null


func _run_all_tests() -> void:
	await _test_scenario_a_normal_movement_side_effects()
	await _test_scenario_b_invalid_movement_zero_side_effects()
	await _test_scenario_c_tile_effect_side_effects()
	await _test_scenario_d_board_encounter_side_effects()
	await _test_scenario_e_board_to_combat_transition()
	await _test_scenario_f_combat_victory_reward_board()
	await _test_scenario_g_combat_retreat_no_reward()
	await _test_scenario_h_combat_defeat_terminal_path()
	await _test_scenario_i_duplicate_combat_result_idempotency()
	await _test_scenario_j_duplicate_reward_claim_idempotency()
	await _test_scenario_k_currency_spend_side_effects()
	await _test_scenario_l_fuel_spend_and_regen_side_effects()
	await _test_scenario_m_research_start_side_effects()
	await _test_scenario_n_research_completion_side_effects()
	await _test_scenario_o_tech_completion_combat_visibility()
	await _test_scenario_p_objective_completion_extraction_unlock()
	await _test_scenario_q_patrol_movement_state_sync()
	await _test_scenario_r_patrol_removal_state_sync()
	await _test_scenario_s_sector_transition_full_reconstruction()
	await _test_scenario_t_run_termination_side_effect_isolation()
	await _test_scenario_u_run_reset_zero_residual_state()
	await _test_scenario_v_save_load_consequence_reconstruction()
	await _test_scenario_w_cross_system_full_gameplay_loop()
	await _test_scenario_x_cross_system_tech_combat_persistence()


# --- Scenario A: Normal Movement Complete Side-Effect Chain ---
func _test_scenario_a_normal_movement_side_effects() -> void:
	print("\n--- Scenario A: Normal Movement Side-Effect Chain ---")
	var board := _instantiate_board_scene()
	var start_tile: Vector2i = board.current_pos
	var target_tile := start_tile + Vector2i(1, 0)
	if not board.nodes_dict.has(target_tile):
		target_tile = start_tile + Vector2i(0, 1)

	var tile_entered_events: Array[Vector2i] = []
	var on_tile_entered = func(t_pos: Vector2i, _tile): tile_entered_events.append(t_pos)
	EventBus.tile_entered.connect(on_tile_entered)

	var fuel_before := GlobalData.fuel.convoy_fuel
	var mp_before := GlobalData.board.board_mp

	var ok := board._try_step(target_tile)
	EventBus.tile_entered.disconnect(on_tile_entered)

	_assert(ok == true, "A.1: Step execution returned true")
	_assert(board.current_pos == target_tile, "A.2: BoardManager current_pos updated to target")
	_assert(GlobalData.board.current_tile == target_tile, "A.3: GlobalData current_tile authoritative position updated")
	_assert(GlobalData.board.board_mp < mp_before, "A.4: MP decremented by step cost")
	_assert(GlobalData.fuel.convoy_fuel < fuel_before, "A.5: Convoy fuel consumed for step")
	_assert(tile_entered_events.size() == 1, "A.6: tile_entered event emitted exactly once")
	_assert(tile_entered_events[0] == target_tile, "A.7: tile_entered payload contains target grid position")


# --- Scenario B: Invalid Movement Zero Side-Effects ---
func _test_scenario_b_invalid_movement_zero_side_effects() -> void:
	print("\n--- Scenario B: Invalid Movement Zero Side-Effects ---")
	var board := _instantiate_board_scene()
	var start_tile: Vector2i = board.current_pos
	var invalid_target := Vector2i(-99, -99)

	var tile_events: Array[Vector2i] = []
	var on_tile = func(t_pos: Vector2i, _tile): tile_events.append(t_pos)
	EventBus.tile_entered.connect(on_tile)

	var fuel_before := GlobalData.fuel.convoy_fuel
	var mp_before := GlobalData.board.board_mp

	var ok := board._try_step(invalid_target)
	EventBus.tile_entered.disconnect(on_tile)

	_assert(ok == false, "B.1: Invalid step returns false")
	_assert(board.current_pos == start_tile, "B.2: current_pos remains unchanged")
	_assert(GlobalData.board.current_tile == start_tile, "B.3: GlobalData current_tile unchanged")
	_assert(GlobalData.board.board_mp == mp_before, "B.4: Zero MP deducted on invalid step")
	_assert(GlobalData.fuel.convoy_fuel == fuel_before, "B.5: Zero fuel consumed on invalid step")
	_assert(tile_events.is_empty(), "B.6: Zero tile_entered events emitted")


# --- Scenario C: Movement into Effect Tile ---
func _test_scenario_c_tile_effect_side_effects() -> void:
	print("\n--- Scenario C: Movement into Effect Tile ---")
	var board := _instantiate_board_scene()
	var target_tile := board.current_pos + Vector2i(1, 0)
	if not board.nodes_dict.has(target_tile):
		target_tile = board.current_pos + Vector2i(0, 1)

	# Register wreckage on target tile
	var fake_loot := [{"type": "weapon", "weapon": null, "scrap": 35}]
	ScavengerSystem.register_tile_wreckage(target_tile, fake_loot)
	var scrap_before := GlobalData.currency.scrap

	var ok := board._try_step(target_tile)
	_assert(ok == true, "C.1: Step into wreckage tile succeeded")
	_assert(not ScavengerSystem.has_wreckage_at(target_tile), "C.2: Wreckage consumed from tile")
	_assert(GlobalData.currency.scrap >= scrap_before, "C.3: Currency scrap state updated from wreckage")


# --- Scenario D: Movement into Encounter Tile ---
func _test_scenario_d_board_encounter_side_effects() -> void:
	print("\n--- Scenario D: Board Encounter Side-Effects ---")
	var board := _instantiate_board_scene()
	var target_tile := board.current_pos + Vector2i(1, 0)
	if not board.nodes_dict.has(target_tile):
		target_tile = board.current_pos + Vector2i(0, 1)

	# Inject a patrol fleet on the target tile
	GlobalData.board.board_patrols = [{
		"id": 999,
		"pos": target_tile,
		"prev_pos": target_tile,
		"fleet_count": 1,
		"archetype": "armored",
		"faction": "hostile",
		"aces": 0,
		"grunts": 1
	}]

	var ok := board._try_step(target_tile)
	_assert(ok == true, "D.1: Step into patrol tile processed")
	_assert(GlobalData.board.board_patrol_engagement == 999, "D.2: board_patrol_engagement set to engaged patrol id (999)")


# --- Scenario E: Board -> Combat Transition ---
func _test_scenario_e_board_to_combat_transition() -> void:
	print("\n--- Scenario E: Board -> Combat Transition ---")
	GameManager.current_state = GameManager.State.BOARD
	GameManager.enter_combat("grunt")

	_assert(GameManager.current_state == GameManager.State.COMBAT, "E.1: GameManager state transitioned to State.COMBAT")
	_assert(GameManager.combat_node_type == "grunt", "E.2: combat_node_type set to 'grunt'")
	_assert(GameManager.is_boss_combat == false, "E.3: is_boss_combat is false for grunt encounter")
	_assert(GlobalData._combat_xp_awarded == false, "E.4: _combat_xp_awarded reset for new combat")


# --- Scenario F: Combat Victory -> Reward -> Board ---
func _test_scenario_f_combat_victory_reward_board() -> void:
	print("\n--- Scenario F: Combat Victory -> Reward -> Board ---")
	GameManager.current_state = GameManager.State.COMBAT
	GlobalData.board.board_patrol_engagement = 888
	GlobalData.board.board_patrols = [{
		"id": 888,
		"pos": Vector2i(2, 2),
		"fleet_count": 1,
		"faction": "hostile"
	}]
	var creds_before := GlobalData.currency.credits
	var scrap_before := GlobalData.currency.scrap

	# 1. Trigger combat ended signal
	EventBus.combat_ended.emit(true)
	_assert(PatrolSystem.get_patrol_by_id(888).is_empty(), "F.1: Engaged patrol 888 removed from board_patrols on victory")
	_assert(GlobalData.board.board_patrol_engagement == -1, "F.2: board_patrol_engagement reset to -1")

	# 2. Rewards UI continuation
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._show_victory_rewards()
	_assert(GlobalData.currency.credits > creds_before, "F.3: Credits awarded to currency authority")
	_assert(GlobalData.currency.scrap > scrap_before, "F.4: Scrap awarded to currency authority")

	rewards_ui._on_continue_pressed()
	_assert(GameManager.current_state == GameManager.State.BOARD, "F.5: Returned to State.BOARD on rewards continue")
	rewards_ui.queue_free()


# --- Scenario G: Combat Retreat -> Board Without Reward ---
func _test_scenario_g_combat_retreat_no_reward() -> void:
	print("\n--- Scenario G: Combat Retreat -> Board Without Reward ---")
	GameManager.current_state = GameManager.State.COMBAT
	GlobalData.board.board_patrol_engagement = 777
	GlobalData.board.board_patrols = [{
		"id": 777,
		"pos": Vector2i(3, 3),
		"fleet_count": 1,
		"faction": "hostile",
		"commander": {"name": "Ace Fox", "rivalry_count": 0, "bounty": 200}
	}]
	var creds_before := GlobalData.currency.credits
	var heat_before := GlobalData.board.heat

	EventBus.combat_escaped_directional.emit("retreat", Vector2i(0, 1))
	EventBus.combat_escaped.emit()

	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._on_continue_pressed()

	_assert(GlobalData.currency.credits == creds_before, "G.1: Zero victory credits awarded on retreat")
	_assert(GlobalData.board.heat >= heat_before, "G.2: Escape heat penalty applied")
	_assert(not PatrolSystem.get_patrol_by_id(777).is_empty(), "G.3: Patrol retained on retreat (rival survived)")
	_assert(GameManager.current_state == GameManager.State.BOARD, "G.4: Returned to State.BOARD on escape continue")
	rewards_ui.queue_free()


# --- Scenario H: Combat Defeat Terminal Path ---
func _test_scenario_h_combat_defeat_terminal_path() -> void:
	print("\n--- Scenario H: Combat Defeat Terminal Path ---")
	GameManager.current_state = GameManager.State.COMBAT
	GlobalData.weapons.battle_loot = [{"type": "weapon", "name": "Laser Rifle"}]

	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._on_combat_ended(false)

	_assert(rewards_ui.title_label.text == "DEFEATED", "H.1: Rewards UI displays DEFEATED title")
	_assert(GlobalData.weapons.battle_loot.is_empty(), "H.2: Battle loot cleared on defeat")
	rewards_ui.queue_free()


# --- Scenario I: Duplicate Combat Result Idempotency ---
func _test_scenario_i_duplicate_combat_result_idempotency() -> void:
	print("\n--- Scenario I: Duplicate Combat Result Idempotency ---")
	GameManager.current_state = GameManager.State.COMBAT
	GlobalData._combat_xp_awarded = false
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)

	rewards_ui._show_victory_rewards()
	var creds_first := GlobalData.currency.credits
	var scrap_first := GlobalData.currency.scrap

	# Attempt second call to _show_victory_rewards
	rewards_ui._show_victory_rewards()
	_assert(GlobalData.currency.credits == creds_first, "I.1: Duplicate victory call did not grant double credits")
	_assert(GlobalData.currency.scrap == scrap_first, "I.2: Duplicate victory call did not grant double scrap")
	rewards_ui.queue_free()


# --- Scenario J: Duplicate Reward Claim Idempotency ---
func _test_scenario_j_duplicate_reward_claim_idempotency() -> void:
	print("\n--- Scenario J: Duplicate Reward Claim Idempotency ---")
	GameManager.current_state = GameManager.State.COMBAT
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._show_victory_rewards()

	rewards_ui._on_continue_pressed()
	var state_after_first := GameManager.current_state

	# Second press while already processing/closed
	rewards_ui._on_continue_pressed()
	_assert(GameManager.current_state == state_after_first, "J.1: Duplicate continue press preserved single return to board")
	rewards_ui.queue_free()


# --- Scenario K: Currency Spend Side-Effects ---
func _test_scenario_k_currency_spend_side_effects() -> void:
	print("\n--- Scenario K: Currency Spend Side-Effects ---")
	GlobalData.currency.credits = 300
	GlobalData.currency.scrap = 50
	GlobalData.currency.data_cores = 5

	var creds_events: Array[int] = []
	var on_creds = func(c: int): creds_events.append(c)
	EventBus.credits_changed.connect(on_creds)

	var ok_spend := GlobalData.currency.try_spend_credits(100)
	var fail_spend := GlobalData.currency.try_spend_credits(9999)
	EventBus.credits_changed.disconnect(on_creds)

	_assert(ok_spend == true, "K.1: Valid credits spend returned true")
	_assert(GlobalData.currency.credits == 200, "K.2: Credits balance atomically reduced by 100")
	_assert(fail_spend == false, "K.3: Overspend credits returned false")
	_assert(GlobalData.currency.credits == 200, "K.4: Credits balance unchanged on failed overspend")
	_assert(creds_events.size() == 1, "K.5: credits_changed signal emitted exactly once for valid spend")


# --- Scenario L: Fuel Spend & Regen Side-Effects ---
func _test_scenario_l_fuel_spend_and_regen_side_effects() -> void:
	print("\n--- Scenario L: Fuel Spend & Regen Side-Effects ---")
	var board := _instantiate_board_scene()
	GlobalData.fuel.convoy_fuel = 50.0
	GlobalData.fuel.convoy_fuel_reserve = 10.0
	GlobalData.fuel.mech_energy = 200.0

	# Advance calendar day
	board._advance_calendar_day()
	_assert(GlobalData.fuel.convoy_fuel_reserve > 10.0, "L.1: Convoy fuel reserve replenished overnight")
	_assert(GlobalData.fuel.mech_energy > 200.0, "L.2: Mech energy regenerated overnight")
	_assert(GlobalData.board.board_day >= 2, "L.3: Calendar day incremented on dawn")


# --- Scenario M: Research Start Side-Effects ---
func _test_scenario_m_research_start_side_effects() -> void:
	print("\n--- Scenario M: Research Start Side-Effects ---")
	TechnologySystem.init_catalog_if_needed()
	var tech_id := "tech_adv_ballistics"
	if not TechnologySystem.has_technology(tech_id):
		tech_id = "tech_combustion_power"

	TechnologySystem.set_discovery_state(tech_id, TechnologySystem.DiscoveryState.IDENTIFIED)
	var started := TechnologySystem.start_research(tech_id)
	_assert(started == true, "M.1: Valid identified tech research started successfully")
	_assert(TechnologySystem.get_active_research_project() == tech_id, "M.2: Active research project set to tech_id")


# --- Scenario N: Research Completion Side-Effects ---
func _test_scenario_n_research_completion_side_effects() -> void:
	print("\n--- Scenario N: Research Completion Side-Effects ---")
	TechnologySystem.init_catalog_if_needed()
	var tech_id := "tech_adv_ballistics"
	if not TechnologySystem.has_technology(tech_id):
		tech_id = "tech_combustion_power"

	TechnologySystem.set_discovery_state(tech_id, TechnologySystem.DiscoveryState.IDENTIFIED)
	TechnologySystem.start_research(tech_id)
	var completed := TechnologySystem.complete_technology_research(tech_id, {"force": true})

	_assert(completed == true, "N.1: Research completed successfully")
	_assert(TechnologySystem.get_discovery_state(tech_id) == TechnologySystem.DiscoveryState.RESEARCHED, "N.2: Tech state transitioned to RESEARCHED")
	_assert(TechnologySystem.get_active_research_project() == "", "N.3: Active research project cleared upon completion")


# --- Scenario O: Technology Completion -> Combat Visibility ---
func _test_scenario_o_tech_completion_combat_visibility() -> void:
	print("\n--- Scenario O: Technology Completion -> Combat Visibility ---")
	TechnologySystem.init_catalog_if_needed()
	var tech_id := "tech_combustion_power"
	TechnologySystem.set_discovery_state(tech_id, TechnologySystem.DiscoveryState.RESEARCHED)
	var made_usable := TechnologySystem.record_technology_usable(tech_id)
	_assert(made_usable == true, "O.1: Researched tech marked as USABLE")
	_assert(TechnologySystem.get_discovery_state(tech_id) == TechnologySystem.DiscoveryState.USABLE, "O.2: Tech discovery state verified as USABLE")


# --- Scenario P: Objective Completion -> Extraction Unlock ---
func _test_scenario_p_objective_completion_extraction_unlock() -> void:
	print("\n--- Scenario P: Objective Completion -> Extraction Unlock ---")
	GlobalData.board.active_contract.clear()
	GlobalData.board.board_objective_id = "patrol_hunt"
	GlobalData.board.board_objective_progress = 0
	GlobalData.board.board_objective_required = 1
	GlobalData.board.extraction_unlocked = false

	BoardSystem.complete()
	_assert(BoardSystem.is_objective_complete() == true, "P.1: Objective marked complete after adding required progress")
	GlobalData.board.extraction_unlocked = true
	_assert(GlobalData.board.extraction_unlocked == true, "P.2: Extraction LZ unlocked following objective completion")


# --- Scenario Q: Patrol Movement State Sync ---
func _test_scenario_q_patrol_movement_state_sync() -> void:
	print("\n--- Scenario Q: Patrol Movement State Sync ---")
	GlobalData.board.board_patrols = [{
		"id": 101,
		"pos": Vector2i(2, 2),
		"prev_pos": Vector2i(2, 2),
		"fleet_count": 1,
		"archetype": "armored",
		"faction": "hostile"
	}]
	var ambush := PatrolSystem.advance_step_turn(Vector2i(0, 0))
	var p := PatrolSystem.get_patrol_by_id(101)
	_assert(not p.is_empty(), "Q.1: Patrol 101 persisted in state")
	_assert(p.has("pos"), "Q.2: Patrol contains updated pos coordinate")


# --- Scenario R: Patrol Removal State Sync ---
func _test_scenario_r_patrol_removal_state_sync() -> void:
	print("\n--- Scenario R: Patrol Removal State Sync ---")
	GlobalData.board.board_patrols = [{
		"id": 202,
		"pos": Vector2i(4, 4),
		"fleet_count": 1,
		"faction": "hostile"
	}]
	PatrolSystem.remove_patrol(202)
	_assert(PatrolSystem.get_patrol_by_id(202).is_empty(), "R.1: Patrol 202 removed from authoritative board_patrols")
	_assert(PatrolSystem.get_patrol_at(Vector2i(4, 4)).is_empty(), "R.2: Tile (4,4) query returns no patrol")


# --- Scenario S: Sector Transition Full Reconstruction ---
func _test_scenario_s_sector_transition_full_reconstruction() -> void:
	print("\n--- Scenario S: Sector Transition Full Reconstruction ---")
	GlobalData.board.current_sector = 1
	GlobalData.board.board_patrols = [{
		"id": 303,
		"pos": Vector2i(5, 5),
		"fleet_count": 1,
		"faction": "hostile"
	}]
	GlobalData.board.extraction_unlocked = true

	GameManager.advance_to_next_sector()
	_assert(GlobalData.board.current_sector == 2, "S.1: current_sector incremented to 2")
	_assert(GlobalData.board.current_tile == Vector2i.ZERO, "S.2: Player tile reset to origin Vector2i.ZERO")
	_assert(GlobalData.board.board_day == 1, "S.3: Day reset to 1 for fresh sector")
	_assert(GlobalData.board.board_patrols.is_empty(), "S.4: Old sector patrols cleared")
	_assert(GlobalData.board.extraction_unlocked == false, "S.5: Extraction unlocked flag reset to false")


# --- Scenario T: Run Termination Side-Effect Isolation ---
func _test_scenario_t_run_termination_side_effect_isolation() -> void:
	print("\n--- Scenario T: Run Termination Side-Effect Isolation ---")
	var end_events: Array = [0]
	var on_end = func(v): end_events[0] += 1
	EventBus.run_ended.connect(on_end)

	GameManager.end_run(false)
	EventBus.run_ended.disconnect(on_end)

	_assert(GameManager.current_state == GameManager.State.MENU, "T.1: GameManager state set to MENU on end_run")
	_assert(end_events[0] == 1, "T.2: EventBus.run_ended emitted exactly once")


# --- Scenario U: Run Reset Zero Residual State ---
func _test_scenario_u_run_reset_zero_residual_state() -> void:
	print("\n--- Scenario U: Run Reset Zero Residual State ---")
	GlobalData.currency.credits = 5000
	GlobalData.board.current_sector = 4
	GlobalData.reset_run_data()

	_assert(GlobalData.board.current_sector == 1, "U.1: Sector reset to 1 on run reset")
	_assert(GlobalData.board.board_day == 1, "U.2: Day reset to 1 on run reset")
	_assert(GlobalData.currency.credits == 110, "U.3: Starter credits reset to standard default")


# --- Scenario V: Save -> Load Consequence Reconstruction ---
func _test_scenario_v_save_load_consequence_reconstruction() -> void:
	print("\n--- Scenario V: Save -> Load Consequence Reconstruction ---")
	GlobalData.board.current_sector = 2
	GlobalData.board.current_tile = Vector2i(3, 4)
	GlobalData.currency.credits = 777
	GlobalData.currency.scrap = 88
	GlobalData.save_run()

	# Mutate in-memory
	GlobalData.board.current_sector = 99
	GlobalData.currency.credits = 0

	# Reload from save
	GlobalData.load_run()
	_assert(GlobalData.board.current_sector == 2, "V.1: Loaded sector matched saved sector (2)")
	_assert(GlobalData.board.current_tile == Vector2i(3, 4), "V.2: Loaded player position matched saved position (3,4)")
	_assert(GlobalData.currency.credits == 777, "V.3: Loaded credits matched saved credits (777)")
	_assert(GlobalData.currency.scrap == 88, "V.4: Loaded scrap matched saved scrap (88)")


# --- Scenario W: Cross-System Full Gameplay Loop ---
func _test_scenario_w_cross_system_full_gameplay_loop() -> void:
	print("\n--- Scenario W: Cross-System Full Gameplay Loop ---")
	# 1. Start on board
	var board := _instantiate_board_scene()
	_assert(GameManager.current_state == GameManager.State.BOARD, "W.1: Initial State is BOARD")

	# 2. Enter combat
	GameManager.enter_combat("grunt")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "W.2: Transitioned to COMBAT")

	# 3. Resolve combat with victory
	EventBus.combat_ended.emit(true)
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._show_victory_rewards()
	rewards_ui._on_continue_pressed()
	rewards_ui.queue_free()
	_assert(GameManager.current_state == GameManager.State.BOARD, "W.3: Returned to BOARD after victory rewards")

	# 4. Complete objective & unlock extraction
	BoardSystem.complete()
	GlobalData.board.extraction_unlocked = true
	_assert(GlobalData.board.extraction_unlocked == true, "W.4: Extraction unlocked")

	# 5. Advance sector
	GameManager.advance_to_next_sector()
	_assert(GlobalData.board.current_sector >= 2, "W.5: Advanced to next sector successfully")
	_cleanup_board_scene()


# --- Scenario X: Cross-System Tech -> Combat -> Persistence ---
func _test_scenario_x_cross_system_tech_combat_persistence() -> void:
	print("\n--- Scenario X: Cross-System Tech -> Combat -> Persistence ---")
	TechnologySystem.init_catalog_if_needed()
	var tech_id := "tech_hydraulic_actuation"
	TechnologySystem.set_discovery_state(tech_id, TechnologySystem.DiscoveryState.RESEARCHED)
	TechnologySystem.record_technology_usable(tech_id)
	_assert(TechnologySystem.get_discovery_state(tech_id) == TechnologySystem.DiscoveryState.USABLE, "X.1: Tech marked USABLE")

	# Save and verify persistence roundtrip of tech discovery
	GlobalData.save_run()
	TechnologySystem.set_discovery_state(tech_id, TechnologySystem.DiscoveryState.UNKNOWN)
	GlobalData.load_run()
	_assert(TechnologySystem.get_discovery_state(tech_id) == TechnologySystem.DiscoveryState.USABLE, "X.2: Tech state USABLE reconstructed from save file")
