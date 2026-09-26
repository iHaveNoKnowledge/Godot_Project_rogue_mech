extends Node

const CombatRewardsUICls = preload("res://scripts/ui/combat_rewards_ui.gd")
const SpawnManagerCls = preload("res://scripts/systems/spawn_manager.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("\n=== STARTING PHASE 2E-23 COMBAT -> BOARD & RUN PROGRESSION VERIFICATION ===")
	await _run_all_tests()
	await get_tree().process_frame
	_print_summary()
	if _failed == 0:
		print("PHASE_2E_23_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_23_FAILED with %d errors" % _failed)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % message)
	else:
		_failed += 1
		push_error("  [FAIL] %s" % message)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-23 COMBAT -> BOARD & RUN PROGRESSION SUMMARY:")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("==================================================")


func _setup_active_tech(tech_id: String) -> void:
	TechnologySystem.reset_discovery_states()
	TechnologySystem.register_technology({
		"tech_id": tech_id,
		"name": "Phase 2E-23 Tech Test",
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
	await _test_1_victory_returns_to_correct_board_state()
	await _test_2_victory_resolves_encounter_exactly_once()
	await _test_3_duplicate_combat_completion_no_double_board_resolution()
	await _test_4_duplicate_continue_no_duplicate_board_progression()
	await _test_5_sector_progression_occurs_once()
	await _test_6_reload_preserves_resolved_board_state()
	await _test_7_reload_preserves_sector_progression()
	await _test_8_cross_combat_isolation_no_tile_leakage()
	await _test_9_defeat_board_semantics()
	await _test_10_escape_board_semantics()
	await _test_11_normal_combat_matrix()
	await _test_12_patrol_encounter_matrix()
	await _test_13_duel_encounter_matrix()
	await _test_14_enemy_base_encounter_matrix()
	await _test_15_fuel_depot_encounter_matrix()
	await _test_16_board_combat_board_loop_playable()


# --- [TEST 1] Victory returns to correct board state ---
func _test_1_victory_returns_to_correct_board_state() -> void:
	print("\n-- [TEST 1] Victory Returns to Correct Board State --")
	var start_tile := Vector2i(3, 4)
	GlobalData.board.current_tile = start_tile
	GameManager.suppress_scene_change = true

	# Enter combat from tile (3, 4)
	GameManager.enter_combat("grunt")
	_check(GameManager.current_state == GameManager.State.COMBAT, "[T1-1] State entered COMBAT")

	# Victory event
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	# Simulate Continue -> return to board
	GameManager.return_to_board()
	_check(GameManager.current_state == GameManager.State.BOARD, "[T1-2] State returned to BOARD")
	_check(GlobalData.board.current_tile == start_tile, "[T1-3] Board current_tile remains logically associated with (3, 4)")

	GameManager.suppress_scene_change = false


# --- [TEST 2] Victory resolves the encounter exactly once ---
func _test_2_victory_resolves_encounter_exactly_once() -> void:
	print("\n-- [TEST 2] Victory Resolves Encounter Exactly Once --")
	_setup_active_tech("tech_test_t2")
	var prog_before: float = TechnologySystem.get_research_progress("tech_test_t2")

	GlobalData.board.board_patrol_engagement = 42
	GlobalData.board.board_patrols = [{
		"id": 42,
		"pos": Vector2i(2, 2),
		"commander": {"name": "Test Rival", "rivalry_count": 0, "bounty": 80}
	}]
	GlobalData._combat_xp_awarded = false

	# Emit victory
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(GlobalData.board.board_patrol_engagement == -1, "[T2-1] Patrol engagement reset to -1")
	_check(GlobalData.board.board_patrols.is_empty(), "[T2-2] Defeated patrol removed from board_patrols")
	var prog_after: float = TechnologySystem.get_research_progress("tech_test_t2")
	_check(is_equal_approx(prog_after, prog_before + 20.0), "[T2-3] Research advanced by exactly 2.0 (20%)")


# --- [TEST 3] Duplicate combat completion does not duplicate board resolution ---
func _test_3_duplicate_combat_completion_no_double_board_resolution() -> void:
	print("\n-- [TEST 3] Duplicate Combat Completion No Double Board Resolution --")
	_setup_active_tech("tech_test_t3")
	var prog_before: float = TechnologySystem.get_research_progress("tech_test_t3")
	var xp_before: int = PilotSkillSystem.get_xp()

	GlobalData.board.board_patrol_engagement = 55
	GlobalData.board.board_patrols = [{
		"id": 55,
		"pos": Vector2i(1, 2),
		"commander": {"name": "Test Rival 2", "rivalry_count": 0, "bounty": 50}
	}]
	GlobalData._combat_xp_awarded = false

	# First emission
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	var prog_first: float = TechnologySystem.get_research_progress("tech_test_t3")
	var xp_first: int = PilotSkillSystem.get_xp()

	# Duplicate emission
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	var prog_second: float = TechnologySystem.get_research_progress("tech_test_t3")
	var xp_second: int = PilotSkillSystem.get_xp()

	_check(is_equal_approx(prog_second, prog_first), "[T3-1] Duplicate combat_ended does not double-advance research")
	_check(xp_second == xp_first, "[T3-2] Duplicate combat_ended does not double-award Pilot XP")
	_check(GlobalData.board.board_patrol_engagement == -1, "[T3-3] Patrol engagement remains -1")


# --- [TEST 4] Duplicate Continue does not duplicate board progression ---
func _test_4_duplicate_continue_no_duplicate_board_progression() -> void:
	print("\n-- [TEST 4] Duplicate Continue Does Not Duplicate Board Progression --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	GameManager.suppress_scene_change = true
	var transition_data := {"count": 0}
	var on_trans = func(_o, _n) -> void:
		transition_data["count"] += 1
	EventBus.game_state_changed.connect(on_trans)

	# Click Continue twice rapidly
	rewards_ui._on_continue_pressed()
	rewards_ui._on_continue_pressed()

	_check(transition_data["count"] == 1, "[T4-1] Duplicate continue produces exactly 1 transition request")

	EventBus.game_state_changed.disconnect(on_trans)
	GameManager.suppress_scene_change = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# --- [TEST 5] Sector progression occurs exactly once where intended ---
func _test_5_sector_progression_occurs_once() -> void:
	print("\n-- [TEST 5] Sector Progression Occurs Once --")
	GameManager.suppress_scene_change = true
	var sector_before: int = GlobalData.board.current_sector

	# Advance to next sector via boss victory / extraction
	GameManager.advance_to_next_sector()
	_check(GlobalData.board.current_sector == sector_before + 1, "[T5-1] Sector advanced by exactly 1")
	_check(GlobalData.board.current_tile == Vector2i.ZERO, "[T5-2] New sector current_tile reset to (0, 0)")
	_check(GlobalData.board.board_day == 1, "[T5-3] New sector board_day reset to 1")
	_check(GlobalData.board.board_patrol_engagement == -1, "[T5-4] Patrol engagement reset to -1")

	GameManager.suppress_scene_change = false


# --- [TEST 6] Reload preserves resolved board state ---
func _test_6_reload_preserves_resolved_board_state() -> void:
	print("\n-- [TEST 6] Reload Preserves Resolved Board State --")
	GlobalData.board.current_tile = Vector2i(6, 7)
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.narrative.enemy_base_active = false
	GlobalData.fuel.fuel_depot_approach = ""

	SaveGameIO.save_run()

	# Mutate runtime state
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.board_patrol_engagement = 999

	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "[T6-1] SaveGameIO.load_run succeeded")
	_check(GlobalData.board.current_tile == Vector2i(6, 7), "[T6-2] Restored current_tile is (6, 7)")
	_check(GlobalData.board.board_patrol_engagement == -1, "[T6-3] Restored patrol engagement is -1")


# --- [TEST 7] Reload preserves sector progression ---
func _test_7_reload_preserves_sector_progression() -> void:
	print("\n-- [TEST 7] Reload Preserves Sector Progression --")
	GlobalData.board.current_sector = 3
	SaveGameIO.save_run()

	GlobalData.board.current_sector = 1
	var load_ok := SaveGameIO.load_run()
	_check(load_ok, "[T7-1] SaveGameIO.load_run succeeded")
	_check(GlobalData.board.current_sector == 3, "[T7-2] Restored current_sector is 3")


# --- [TEST 8] Combat A -> Combat B does not leak tile state ---
func _test_8_cross_combat_isolation_no_tile_leakage() -> void:
	print("\n-- [TEST 8] Cross-Combat Isolation No Tile Leakage --")
	GameManager.suppress_scene_change = true

	# Combat A at (2, 3)
	GlobalData.board.current_tile = Vector2i(2, 3)
	GameManager.enter_combat("grunt")
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	GameManager.return_to_board()
	_check(GlobalData.board.current_tile == Vector2i(2, 3), "[T8-1] Combat A finished at (2, 3)")

	# Move to (4, 5) and enter Combat B
	GlobalData.board.current_tile = Vector2i(4, 5)
	GameManager.enter_combat("grunt")
	_check(GlobalData.board.current_tile == Vector2i(4, 5), "[T8-2] Combat B entered from (4, 5)")
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	GameManager.return_to_board()
	_check(GlobalData.board.current_tile == Vector2i(4, 5), "[T8-3] Combat B finished at (4, 5) without reverting to (2, 3)")

	GameManager.suppress_scene_change = false


# --- [TEST 9] Defeat preserves correct board semantics ---
func _test_9_defeat_board_semantics() -> void:
	print("\n-- [TEST 9] Defeat Preserves Correct Board Semantics --")
	_setup_active_tech("tech_test_t9")
	var prog_before: float = TechnologySystem.get_research_progress("tech_test_t9")
	var sector_before: int = GlobalData.board.current_sector
	GlobalData.board.board_patrol_engagement = 77

	# Defeat event
	EventBus.combat_ended.emit(false)
	await get_tree().process_frame

	_check(GlobalData.board.board_patrol_engagement == -1, "[T9-1] Patrol engagement cleared on defeat")
	_check(is_equal_approx(TechnologySystem.get_research_progress("tech_test_t9"), prog_before), "[T9-2] Defeat does NOT advance research progression")
	_check(GlobalData.board.current_sector == sector_before, "[T9-3] Defeat does NOT advance sector progression")


# --- [TEST 10] Escape preserves correct board semantics ---
func _test_10_escape_board_semantics() -> void:
	print("\n-- [TEST 10] Escape Preserves Correct Board Semantics --")
	var rewards_ui = CombatRewardsUICls.new()
	add_child(rewards_ui)
	rewards_ui.reset_reward_state()

	GlobalData.board.current_tile = Vector2i(2, 2)
	GameManager.suppress_scene_change = true

	# Directional breakthrough escape (delta = (1, 0))
	rewards_ui._on_combat_escaped_directional("breakthrough", Vector2i(1, 0))
	rewards_ui._on_combat_escaped()
	_check(rewards_ui.is_escaped == true, "[T10-1] is_escaped is true")

	# Continue pressed
	rewards_ui._on_continue_pressed()
	_check(GlobalData.board.current_tile == Vector2i(3, 2), "[T10-2] Breakthrough moved current_tile from (2,2) to (3,2)")
	_check(GameManager.current_state == GameManager.State.BOARD, "[T10-3] Returned to BOARD state on escape")

	GameManager.suppress_scene_change = false
	get_tree().paused = false
	rewards_ui.queue_free()
	await get_tree().process_frame


# --- [TEST 11] Normal combat encounter matrix ---
func _test_11_normal_combat_matrix() -> void:
	print("\n-- [TEST 11] Normal Combat Matrix --")
	_setup_active_tech("tech_matrix_normal")
	var p_before: float = TechnologySystem.get_research_progress("tech_matrix_normal")

	GlobalData.board.current_tile = Vector2i(1, 1)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.combat_node_type = "grunt"
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(is_equal_approx(TechnologySystem.get_research_progress("tech_matrix_normal"), p_before + 20.0), "[T11-1] Normal combat advances research by 2.0")
	_check(GlobalData.board.current_tile == Vector2i(1, 1), "[T11-2] Current tile remains (1, 1)")


# --- [TEST 12] Patrol encounter matrix ---
func _test_12_patrol_encounter_matrix() -> void:
	print("\n-- [TEST 12] Patrol Encounter Matrix --")
	_setup_active_tech("tech_matrix_patrol")
	var p_before: float = TechnologySystem.get_research_progress("tech_matrix_patrol")

	GlobalData.board.board_patrol_engagement = 101
	GlobalData.board.board_patrols = [{"id": 101, "pos": Vector2i(2, 3), "commander": {"name": "Patrol Alpha", "bounty": 100}}]
	GameManager.combat_node_type = "grunt"
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(is_equal_approx(TechnologySystem.get_research_progress("tech_matrix_patrol"), p_before + 20.0), "[T12-1] Patrol victory advances research by 2.0")
	_check(GlobalData.board.board_patrol_engagement == -1, "[T12-2] Patrol engagement reset to -1")
	_check(GlobalData.board.board_patrols.is_empty(), "[T12-3] Defeated patrol removed from board")


# --- [TEST 13] Duel encounter matrix ---
func _test_13_duel_encounter_matrix() -> void:
	print("\n-- [TEST 13] Duel Encounter Matrix --")
	_setup_active_tech("tech_matrix_duel")
	var p_before: float = TechnologySystem.get_research_progress("tech_matrix_duel")

	GlobalData.board.board_patrol_engagement = -1
	GlobalData.hangar.pending_duel = {"character_id": "rival_charlie"}
	GameManager.combat_node_type = "duel"
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(is_equal_approx(TechnologySystem.get_research_progress("tech_matrix_duel"), p_before + 20.0), "[T13-1] Duel victory advances research by 2.0")
	_check(GlobalData.hangar.pending_duel.is_empty(), "[T13-2] Pending duel cleared")


# --- [TEST 14] Enemy Base encounter matrix ---
func _test_14_enemy_base_encounter_matrix() -> void:
	print("\n-- [TEST 14] Enemy Base Encounter Matrix --")
	_setup_active_tech("tech_matrix_base")
	var p_before: float = TechnologySystem.get_research_progress("tech_matrix_base")

	GlobalData.board.board_patrol_engagement = -1
	GlobalData.narrative.enemy_base_active = true
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(5, 5)
	GameManager.combat_node_type = "enemy_base"
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(is_equal_approx(TechnologySystem.get_research_progress("tech_matrix_base"), p_before + 20.0), "[T14-1] Enemy base victory advances research by 2.0")
	_check(GlobalData.narrative.enemy_base_active == false, "[T14-2] Enemy base marked inactive")
	_check(GlobalData.narrative.enemy_base_tile_pos == Vector2i(-1, -1), "[T14-3] Enemy base tile position reset")


# --- [TEST 15] Fuel Depot encounter matrix ---
func _test_15_fuel_depot_encounter_matrix() -> void:
	print("\n-- [TEST 15] Fuel Depot Encounter Matrix --")
	_setup_active_tech("tech_matrix_fuel")
	var p_before: float = TechnologySystem.get_research_progress("tech_matrix_fuel")

	GlobalData.board.board_patrol_engagement = -1
	GlobalData.fuel.fuel_depot_approach = "precise"
	GlobalData.fuel.mech_fuel_inventory.reset([{"type": 0, "capacity": 100.0, "current": 0.0}])
	GameManager.combat_node_type = "fuel_depot"
	GlobalData._combat_xp_awarded = false

	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	_check(is_equal_approx(TechnologySystem.get_research_progress("tech_matrix_fuel"), p_before + 20.0), "[T15-1] Fuel depot victory advances research by 2.0")
	_check(GlobalData.fuel.fuel_depot_approach == "", "[T15-2] Fuel depot approach cleared")


# --- [TEST 16] Board -> Combat -> Board loop remains playable ---
func _test_16_board_combat_board_loop_playable() -> void:
	print("\n-- [TEST 16] Board -> Combat -> Board Loop Remains Playable --")
	GameManager.suppress_scene_change = true

	# Step 1: Start on board at (2, 2)
	GlobalData.board.current_tile = Vector2i(2, 2)
	GameManager.transition_to(GameManager.State.BOARD)
	_check(GameManager.current_state == GameManager.State.BOARD, "[T16-1] Loop starts at State.BOARD")

	# Step 2: Select and enter combat
	GameManager.enter_combat("grunt")
	_check(GameManager.current_state == GameManager.State.COMBAT, "[T16-2] Transitioned to State.COMBAT")

	# Step 3: Combat completes with victory
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	# Step 4: Finalize and return to board
	GameManager.return_to_board()
	_check(GameManager.current_state == GameManager.State.BOARD, "[T16-3] Returned to State.BOARD")
	_check(GlobalData.board.current_tile == Vector2i(2, 2), "[T16-4] Position preserved on board")

	# Step 5: Can move to adjacent tile (3, 2)
	GlobalData.board.current_tile = Vector2i(3, 2)
	_check(GlobalData.board.current_tile == Vector2i(3, 2), "[T16-5] Next valid board movement executed")

	GameManager.suppress_scene_change = false
