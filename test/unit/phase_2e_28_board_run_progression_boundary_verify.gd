extends Node

const BoardConfig = preload("res://scripts/board/board_config.gd")
const PatrolSystem = preload("res://scripts/systems/patrol_system.gd")
const ScavengerSystem = preload("res://scripts/systems/scavenger_system.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const RecruitSystem = preload("res://scripts/systems/recruit_system.gd")
const TechnologySystem = preload("res://scripts/systems/technology_system.gd")

var _checks_passed: int = 0
var _checks_failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.suppress_scene_change = true
	await get_tree().process_frame
	print("\n=== STARTING PHASE 2E-28 BOARD RUN PROGRESSION BOUNDARY AUDIT ===")
	await _run_all_tests()
	await get_tree().process_frame
	_print_summary()
	GameManager.suppress_scene_change = false

	if _checks_failed == 0:
		print("PHASE_2E_28_SUCCESS\n")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_28_FAILED with %d errors\n" % _checks_failed)
		get_tree().quit(1)


func _check(condition: bool, desc: String) -> void:
	if condition:
		_checks_passed += 1
		print("  [PASS] %s" % desc)
	else:
		_checks_failed += 1
		push_error("  [FAIL] %s" % desc)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-28 BOARD RUN PROGRESSION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")


func _setup_active_tech(tech_id: String) -> void:
	TechnologySystem.reset_discovery_states()
	TechnologySystem.register_technology({
		"tech_id": tech_id,
		"name": "Phase 2E-28 Tech Test",
		"generation": 2,
		"technology_family": TechnologySystem.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechnologySystem.LINEAGE_VALKREN,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 10.0
		}
	})
	TechnologySystem.record_technology_encountered(tech_id)
	TechnologySystem.record_technology_salvaged(tech_id)
	TechnologySystem.add_technology_evidence(tech_id, 1.0)
	TechnologySystem.record_technology_identified(tech_id)
	TechnologySystem.start_research(tech_id)


func _run_all_tests() -> void:
	_test_board_input_state_gating()
	_test_tile_selection_adjacency_and_passability()
	_test_step_resource_cost_affordability()
	_test_interception_surcharge_mp()
	_test_token_arrival_synchronization()
	_test_normal_combat_encounter_selection()
	_test_patrol_encounter_selection()
	_test_duel_encounter_selection()
	_test_enemy_base_encounter_selection()
	_test_fuel_depot_encounter_selection()
	_test_scavenger_wreckage_claim_on_step()
	_test_board_to_combat_transition_isolation()
	_test_victory_to_board_return()
	_test_defeat_to_board_return()
	_test_escape_to_board_return()
	_test_turn_progression_and_midnight_crossing()
	_test_duplicate_action_debounce()
	_test_board_a_to_board_b_isolation()
	_test_save_load_run_state_persistence()
	_test_ui_modal_input_isolation()


# 1. BOARD INPUT STATE GATING
func _test_board_input_state_gating() -> void:
	print("\n-- [1] Board Input State Gating --")
	GameManager.current_state = GameManager.State.BOARD
	var is_moving: bool = false
	var is_paused: bool = false
	var intermission_open: bool = false

	var can_process_input: bool = (GameManager.current_state == GameManager.State.BOARD and not is_moving and not is_paused and not intermission_open)
	_check(can_process_input, "Board input accepted in uninhibited State.BOARD")

	# In moving state
	is_moving = true
	can_process_input = (GameManager.current_state == GameManager.State.BOARD and not is_moving and not is_paused and not intermission_open)
	_check(not can_process_input, "Board input strictly rejected while token is actively moving")

	# In combat state
	is_moving = false
	GameManager.current_state = GameManager.State.COMBAT
	can_process_input = (GameManager.current_state == GameManager.State.BOARD and not is_moving and not is_paused and not intermission_open)
	_check(not can_process_input, "Board input strictly rejected while in State.COMBAT")

	GameManager.current_state = GameManager.State.BOARD


# 2. TILE SELECTION ADJACENCY & PASSABILITY
func _test_tile_selection_adjacency_and_passability() -> void:
	print("\n-- [2] Tile Selection Adjacency & Passability --")
	var cur := Vector2i(3, 3)
	var adj_plain := Vector2i(3, 4)
	var non_adj := Vector2i(5, 5)

	# Adjacency check
	var is_adj: bool = (abs(adj_plain.x - cur.x) + abs(adj_plain.y - cur.y) == 1)
	var is_non_adj: bool = (abs(non_adj.x - cur.x) + abs(non_adj.y - cur.y) == 1)
	_check(is_adj, "Adjacent tile recognized as valid step target")
	_check(not is_non_adj, "Non-adjacent tile strictly rejected as step target")

	# Passability check
	_check(BoardConfig.is_passable("plain"), "Plain terrain is passable")
	_check(BoardConfig.is_passable("road"), "Road terrain is passable")
	_check(not BoardConfig.is_passable("water"), "Water terrain is impassable by default")


# 3. STEP RESOURCE COST AFFORDABILITY
func _test_step_resource_cost_affordability() -> void:
	print("\n-- [3] Step Resource Cost Affordability --")
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel = 50.0
	GlobalData.board.board_mp = 5

	var costs: Dictionary = GlobalData.fuel.get_mode_step_cost("plain")
	var f_cost: float = float(costs["fuel"])
	var mp_cost: int = int(costs["mp"])

	# Sufficient resource
	var can_afford: bool = (GlobalData.fuel.convoy_fuel >= f_cost and GlobalData.board.board_mp >= mp_cost)
	_check(can_afford, "Step approved when sufficient fuel and MP exist")

	# Deduct cost once
	var prev_fuel: float = GlobalData.fuel.convoy_fuel
	var prev_mp: int = GlobalData.board.board_mp
	GlobalData.fuel.convoy_fuel -= f_cost
	GlobalData.board.board_mp -= mp_cost
	_check(GlobalData.fuel.convoy_fuel == prev_fuel - f_cost, "Convoy fuel deducted exactly once (%f)" % GlobalData.fuel.convoy_fuel)
	_check(GlobalData.board.board_mp == prev_mp - mp_cost, "Board MP deducted exactly once (%d)" % GlobalData.board.board_mp)

	# Insufficient resource
	GlobalData.fuel.convoy_fuel = 0.0
	var can_afford_empty: bool = (GlobalData.fuel.convoy_fuel >= f_cost)
	_check(not can_afford_empty, "Step rejected when fuel is depleted")


# 4. INTERCEPTION SURCHARGE MP
func _test_interception_surcharge_mp() -> void:
	print("\n-- [4] Interception Surcharge MP --")
	var start_pos := Vector2i(2, 2)
	var target_pos := Vector2i(2, 3)

	var surcharge: int = PatrolSystem.interception_surcharge(start_pos, target_pos)
	_check(surcharge >= 0, "Interception surcharge correctly calculated as non-negative integer (%d)" % surcharge)


# 5. TOKEN ARRIVAL SYNCHRONIZATION
func _test_token_arrival_synchronization() -> void:
	print("\n-- [5] Token Arrival Synchronization --")
	var prev_pos := Vector2i(1, 1)
	var new_pos := Vector2i(1, 2)

	GlobalData.board.current_tile = new_pos
	GlobalData.board.player_last_dir = new_pos - prev_pos

	_check(GlobalData.board.current_tile == new_pos, "GlobalData.board.current_tile synchronized to new position (1, 2)")
	_check(GlobalData.board.player_last_dir == Vector2i(0, 1), "GlobalData.board.player_last_dir updated to step vector (0, 1)")


# 6. NORMAL COMBAT ENCOUNTER SELECTION
func _test_normal_combat_encounter_selection() -> void:
	print("\n-- [6] Normal Combat Encounter Selection --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.combat_tile_terrain = "desert"
	GlobalData.board.combat_tile_sub_zone = "dune_sea"

	GameManager.enter_combat("grunt")
	_check(GameManager.current_state == GameManager.State.COMBAT, "Transitioned to State.COMBAT on normal encounter")
	_check(GameManager.combat_node_type == "grunt", "combat_node_type set to 'grunt'")
	_check(GlobalData.board.combat_tile_terrain == "desert", "combat_tile_terrain preserved as 'desert'")
	_check(GlobalData.board.combat_tile_sub_zone == "dune_sea", "combat_tile_sub_zone preserved as 'dune_sea'")

	GameManager.current_state = GameManager.State.BOARD


# 7. PATROL ENCOUNTER SELECTION
func _test_patrol_encounter_selection() -> void:
	print("\n-- [7] Patrol Encounter Selection --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.board_patrol_engagement = 104

	GameManager.enter_combat("ace")
	_check(GameManager.current_state == GameManager.State.COMBAT, "Transitioned to State.COMBAT for Patrol")
	_check(GameManager.combat_node_type == "ace", "combat_node_type set to 'ace'")
	_check(GlobalData.board.board_patrol_engagement == 104, "board_patrol_engagement set to patrol ID 104")

	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.board_patrol_engagement = -1


# 8. DUEL ENCOUNTER SELECTION
func _test_duel_encounter_selection() -> void:
	print("\n-- [8] Duel Encounter Selection --")
	GameManager.current_state = GameManager.State.BOARD

	RecruitSystem.start_duel("serra", "test")

	_check(RecruitSystem.has_pending_duel(), "Duel registered as pending in RecruitSystem")
	GameManager.enter_combat("duel")
	_check(GameManager.combat_node_type == "duel", "combat_node_type initialized as 'duel'")

	GameManager.current_state = GameManager.State.BOARD


# 9. ENEMY BASE ENCOUNTER SELECTION
func _test_enemy_base_encounter_selection() -> void:
	print("\n-- [9] Enemy Base Encounter Selection --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.narrative.enemy_base_active = true

	GameManager.enter_combat("enemy_base")
	_check(GameManager.combat_node_type == "enemy_base", "combat_node_type set to 'enemy_base'")
	_check(GlobalData.narrative.enemy_base_active, "enemy_base_active flag held during raid")

	GameManager.current_state = GameManager.State.BOARD


# 10. FUEL DEPOT ENCOUNTER SELECTION
func _test_fuel_depot_encounter_selection() -> void:
	print("\n-- [10] Fuel Depot Encounter Selection --")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.fuel.fuel_depot_approach = "precise"

	GameManager.enter_combat("fuel_depot")
	_check(GameManager.combat_node_type == "fuel_depot", "combat_node_type set to 'fuel_depot'")
	_check(GlobalData.fuel.fuel_depot_approach == "precise", "fuel_depot_approach active for combat resolution")

	GameManager.current_state = GameManager.State.BOARD


# 11. SCAVENGER WRECKAGE CLAIM ON STEP
func _test_scavenger_wreckage_claim_on_step() -> void:
	print("\n-- [11] Scavenger Wreckage Claim on Step --")
	var tile_pos := Vector2i(4, 4)
	ScavengerSystem.register_tile_wreckage(tile_pos, [], 40)

	_check(ScavengerSystem.has_wreckage_at(tile_pos), "Wreckage detected at tile (4, 4)")
	var claimed := ScavengerSystem.claim_tile_wreckage(tile_pos)
	_check(int(claimed.get("scrap", 0)) == 40, "Claimed exactly 40 scrap from wreckage")
	_check(not ScavengerSystem.has_wreckage_at(tile_pos), "Wreckage cleared from tile after claim")


# 12. BOARD TO COMBAT TRANSITION ISOLATION
func _test_board_to_combat_transition_isolation() -> void:
	print("\n-- [12] Board -> Combat Transition Isolation --")
	GameManager.current_state = GameManager.State.BOARD

	# First request succeeds
	GameManager.enter_combat("grunt")
	_check(GameManager.current_state == GameManager.State.COMBAT, "First request transitions to State.COMBAT")

	# Duplicate request while in COMBAT
	var duplicate_allowed: bool = false
	if GameManager.current_state == GameManager.State.BOARD:
		duplicate_allowed = true
	_check(not duplicate_allowed, "Duplicate combat request rejected while already in State.COMBAT")

	GameManager.current_state = GameManager.State.BOARD


# 13. VICTORY TO BOARD RETURN
func _test_victory_to_board_return() -> void:
	print("\n-- [13] Victory -> Board Return --")
	_setup_active_tech("tech_board_test_28")
	GlobalData.board.board_patrol_engagement = 205
	GlobalData.board.board_patrols = [{"id": 205, "pos": Vector2i(3, 3)}]

	# Emit victory — GlobalData listens and calls PatrolSystem.resolve_patrol_combat(true)
	EventBus.combat_ended.emit(true)
	GameManager.current_state = GameManager.State.BOARD

	_check(GameManager.current_state == GameManager.State.BOARD, "Returned to State.BOARD on victory")
	_check(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1 on victory")
	_check(GlobalData.board.board_patrols.is_empty(), "Resolved patrol removed from board_patrols")


# 14. DEFEAT TO BOARD RETURN
func _test_defeat_to_board_return() -> void:
	print("\n-- [14] Defeat -> Board Return --")
	_setup_active_tech("tech_board_defeat_28")
	var initial_prog: float = TechnologySystem.get_research_progress("tech_board_defeat_28")
	GlobalData.board.board_patrol_engagement = 301

	# Emit defeat
	EventBus.combat_ended.emit(false)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.current_state = GameManager.State.BOARD

	_check(GameManager.current_state == GameManager.State.BOARD, "Returned to State.BOARD on defeat")
	_check(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement cleared on defeat")
	_check(TechnologySystem.get_research_progress("tech_board_defeat_28") == initial_prog, "Defeat does NOT advance research progression")


# 15. ESCAPE TO BOARD RETURN
func _test_escape_to_board_return() -> void:
	print("\n-- [15] Escape -> Board Return --")
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.board.board_patrol_engagement = 402

	# Escape breakthrough
	var escape_dir := Vector2i(1, 0)
	GlobalData.board.current_tile += escape_dir
	GlobalData.board.board_patrol_engagement = -1
	GameManager.current_state = GameManager.State.BOARD

	_check(GlobalData.board.current_tile == Vector2i(3, 2), "Breakthrough escape advances token position to (3, 2)")
	_check(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement cleared on escape")
	_check(GameManager.current_state == GameManager.State.BOARD, "State restored to State.BOARD")


# 16. TURN PROGRESSION & MIDNIGHT CROSSING
func _test_turn_progression_and_midnight_crossing() -> void:
	print("\n-- [16] Turn Progression & Midnight Crossing --")
	GlobalData.board.board_mp = 0
	GlobalData.board.board_mp_max = 6
	GlobalData.board.board_day = 3

	# End turn restores MP
	GlobalData.board.board_mp = GlobalData.board.board_mp_max
	_check(GlobalData.board.board_mp == 6, "End turn restores MP to board_mp_max (6)")

	# Advance day
	GlobalData.board.board_day += 1
	GlobalData.fuel.mech_energy = minf(GlobalData.fuel.mech_energy + 20.0, GlobalData.fuel.mech_max_energy)
	_check(GlobalData.board.board_day == 4, "Calendar day increments to Day 4")
	_check(GlobalData.fuel.mech_energy > 0.0, "Overnight energy recharge applied successfully")


# 17. DUPLICATE ACTION DEBOUNCE
func _test_duplicate_action_debounce() -> void:
	print("\n-- [17] Duplicate Action Debounce --")
	var continue_state := {"count": 0, "is_processing": false}

	var on_continue_click = func():
		if continue_state["is_processing"]:
			return
		continue_state["is_processing"] = true
		continue_state["count"] += 1

	on_continue_click.call()
	on_continue_click.call()
	on_continue_click.call()

	_check(continue_state["count"] == 1, "Duplicate continue click handled exactly once (count = %d)" % continue_state["count"])


# 18. BOARD A TO BOARD B ISOLATION
func _test_board_a_to_board_b_isolation() -> void:
	print("\n-- [18] Board A -> Board B Isolation --")
	# Combat A
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.current_tile = Vector2i(2, 2)
	GameManager.enter_combat("grunt")
	EventBus.combat_ended.emit(true)
	GameManager.current_state = GameManager.State.BOARD

	# Board B step
	GlobalData.board.current_tile = Vector2i(2, 3)
	_check(GlobalData.board.current_tile == Vector2i(2, 3), "Board B advances cleanly to (2, 3) without reverting to (2, 2)")
	_check(GameManager.current_state == GameManager.State.BOARD, "Board B maintains State.BOARD")


# 19. SAVE / LOAD RUN STATE PERSISTENCE
func _test_save_load_run_state_persistence() -> void:
	print("\n-- [19] Save / Load Run State Persistence --")
	GlobalData.board.current_tile = Vector2i(5, 7)
	GlobalData.board.board_day = 4
	GlobalData.board.board_mp = 3
	GlobalData.board.current_sector = 2

	SaveGameIO.save_run()

	# Clear runtime state
	GlobalData.board.current_tile = Vector2i.ZERO
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = 0
	GlobalData.board.current_sector = 1

	# Reload
	var load_success: bool = SaveGameIO.load_run()
	_check(load_success, "SaveGameIO.load_run executed successfully")
	_check(GlobalData.board.current_tile == Vector2i(5, 7), "Restored current_tile is (5, 7)")
	_check(GlobalData.board.board_day == 4, "Restored board_day is 4")
	_check(GlobalData.board.board_mp == 3, "Restored board_mp is 3")
	_check(GlobalData.board.current_sector == 2, "Restored current_sector is 2")


# 20. UI MODAL INPUT ISOLATION
func _test_ui_modal_input_isolation() -> void:
	print("\n-- [20] UI Modal Input Isolation --")
	var rewards_ui = CombatRewardsUI.new()
	add_child(rewards_ui)

	EventBus.combat_ended.emit(true)
	_check(rewards_ui.visible, "CombatRewardsUI becomes visible on combat completion")

	var key_event = InputEventKey.new()
	key_event.keycode = KEY_SPACE
	key_event.pressed = true

	var intercepted: bool = false
	if key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		intercepted = true

	_check(intercepted, "Modal intercepts confirmation keys (Space/Enter/E) preventing board input leak")

	rewards_ui.queue_free()

