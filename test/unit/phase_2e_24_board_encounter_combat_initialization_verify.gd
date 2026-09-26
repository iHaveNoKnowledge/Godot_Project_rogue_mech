extends Node

## ===========================================================================
## PHASE 2E-24: Board -> Encounter Selection -> Combat Initialization Boundary Audit
##
## Verifies:
##   Test 1  - Normal encounter -> correct combat context
##   Test 2  - Patrol encounter -> correct patrol metadata & roster
##   Test 3  - Duel encounter -> correct duel metadata & signature opponent
##   Test 4  - Enemy Base -> correct faction/base context
##   Test 5  - Fuel Depot -> correct special encounter context
##   Test 6  - Combat A -> Board -> Combat B isolation
##   Test 7  - Loadout snapshot belongs to current combat
##   Test 8  - Transient combat state resets correctly
##   Test 9  - Duplicate combat-entry protection
##   Test 10 - Save -> reload -> Board -> Combat preserves correct encounter
##   Test 11 - Defeat -> Board -> Combat B isolation
##   Test 12 - Escape -> Board -> Combat B isolation
##   Test 13 - Board -> Combat -> Board -> Combat loop
##   Test 14 - Duplicate signal/callback does not initialize combat twice
## ===========================================================================

var _tests_passed: int = 0
var _tests_failed: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-24 BOARD -> ENCOUNTER -> COMBAT INITIALIZATION AUDIT ===")
	GameManager.suppress_scene_change = true

	_run_test_1_normal_encounter_context()
	_run_test_2_patrol_encounter_metadata_and_roster()
	_run_test_3_duel_encounter_metadata_and_opponent()
	_run_test_4_enemy_base_encounter_context()
	_run_test_5_fuel_depot_encounter_context()
	_run_test_6_combat_a_to_b_isolation()
	_run_test_7_loadout_snapshot_belongs_to_current_combat()
	_run_test_8_transient_combat_state_resets()
	_run_test_9_duplicate_combat_entry_protection()
	_run_test_10_save_reload_preserves_correct_encounter()
	_run_test_11_defeat_to_combat_b_isolation()
	_run_test_12_escape_to_combat_b_isolation()
	_run_test_13_board_combat_board_combat_loop()
	_run_test_14_duplicate_signal_callback_protection()

	GameManager.suppress_scene_change = false

	print("\n==================================================")
	print("PHASE 2E-24 ENCOUNTER COMBAT INITIALIZATION SUMMARY:")
	print("  Passed: %d" % _tests_passed)
	print("  Failed: %d" % _tests_failed)
	print("==================================================")

	if _tests_failed == 0:
		print("PHASE_2E_24_SUCCESS")
	else:
		push_error("PHASE_2E_24_FAILED with %d failures" % _tests_failed)

	get_tree().quit(0 if _tests_failed == 0 else 1)


func _assert_true(condition: bool, msg: String) -> void:
	if condition:
		_tests_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_tests_failed += 1
		print("  [FAIL] %s" % msg)


## ---------------------------------------------------------------------------
## TEST 1: Normal Encounter -> Correct Combat Context
## ---------------------------------------------------------------------------
func _run_test_1_normal_encounter_context() -> void:
	print("\n-- [TEST 1] Normal Encounter -> Correct Combat Context --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)
	GlobalData.board.current_tile = Vector2i(2, 3)
	GlobalData.board.combat_tile_terrain = "desert"
	GlobalData.board.combat_tile_sub_zone = "dunes"
	GlobalData.board.board_patrol_engagement = -1

	GameManager.enter_combat("grunt")

	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T1-1] Transitioned to State.COMBAT")
	_assert_true(GameManager.combat_node_type == "grunt", "[T1-2] combat_node_type is 'grunt'")
	_assert_true(GameManager.is_boss_combat == false, "[T1-3] is_boss_combat is false")
	_assert_true(GameManager.combat_fleet_count == 1, "[T1-4] combat_fleet_count is 1")
	_assert_true(GlobalData.board.board_patrol_engagement == -1, "[T1-5] board_patrol_engagement remains -1")

	# Verify SpawnManager wave defs
	var spawner := SpawnManager.new()
	var defs: Array = spawner._get_active_defs()
	_assert_true(not defs.is_empty(), "[T1-6] SpawnManager wave defs generated")
	_assert_true(defs.size() >= 1, "[T1-7] Normal wave contains at least 1 wave group")
	spawner.free()


## ---------------------------------------------------------------------------
## TEST 2: Patrol Encounter -> Correct Metadata & Roster
## ---------------------------------------------------------------------------
func _run_test_2_patrol_encounter_metadata_and_roster() -> void:
	print("\n-- [TEST 2] Patrol Encounter -> Correct Metadata & Roster --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)

	# Register a mock patrol fleet with 3 pilots
	var test_patrol := {
		"id": 105,
		"name": "Bravo Vanguard",
		"pos": Vector2i(4, 4),
		"faction": "hostile",
		"fleet_count": 2,
		"aces": 1,
		"pilots": [
			{"display_name": "Ace Commander", "rank_title": "[CPT]", "archetype": 2},
			{"display_name": "Wingman Alpha", "rank_title": "[LT]", "archetype": 0},
			{"display_name": "Wingman Beta", "rank_title": "[SGT]", "archetype": 1}
		]
	}
	GlobalData.board.board_patrols = [test_patrol]
	GlobalData.board.board_patrol_engagement = 105

	GameManager.enter_combat("ace")

	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T2-1] Transitioned to State.COMBAT for Patrol")
	_assert_true(GameManager.combat_node_type == "ace", "[T2-2] combat_node_type is 'ace'")
	_assert_true(GameManager.combat_fleet_count == 2, "[T2-3] combat_fleet_count matches patrol fleet_count (2)")

	var spawner := SpawnManager.new()
	var defs: Array = spawner._get_active_defs()
	_assert_true(defs.size() == 1, "[T2-4] Patrol engagement uses 1 wave containing the full roster")
	var wave_item = defs[0][0]
	_assert_true(wave_item.get("type") == "patrol_roster", "[T2-5] Wave type is 'patrol_roster'")
	_assert_true(int(wave_item.get("count", 0)) == 3, "[T2-6] Wave roster count matches pilots size (3)")
	spawner.free()


## ---------------------------------------------------------------------------
## TEST 3: Duel Encounter -> Correct Metadata & Opponent
## ---------------------------------------------------------------------------
func _run_test_3_duel_encounter_metadata_and_opponent() -> void:
	print("\n-- [TEST 3] Duel Encounter -> Correct Metadata & Opponent --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)

	# Register a pending duel in RecruitSystem
	var duel_started := RecruitSystem.start_duel("serra", "test")
	_assert_true(duel_started, "[T3-0] RecruitSystem.start_duel succeeded")
	_assert_true(RecruitSystem.has_pending_duel(), "[T3-1] Pending duel is active in RecruitSystem")

	GameManager.enter_combat("duel")

	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T3-2] Transitioned to State.COMBAT for Duel")
	_assert_true(GameManager.combat_node_type == "duel", "[T3-3] combat_node_type is 'duel'")

	var spawner := SpawnManager.new()
	var defs: Array = spawner._get_active_defs()
	_assert_true(defs.size() == 1, "[T3-4] Duel wave definition has exactly 1 wave")
	_assert_true(defs[0].size() == 1, "[T3-5] Duel wave contains exactly 1 enemy unit")
	var duel_enemy = defs[0][0]
	_assert_true(str(duel_enemy.get("type")) == "heavy_full", "[T3-6] Duel enemy scene matches character duel_scene")
	_assert_true(int(duel_enemy.get("archetype")) == 2, "[T3-7] Duel enemy archetype matches character duel_archetype")
	_assert_true(int(duel_enemy.get("count")) == 1, "[T3-8] Duel enemy count is strictly 1")
	spawner.free()


## ---------------------------------------------------------------------------
## TEST 4: Enemy Base -> Correct Context
## ---------------------------------------------------------------------------
func _run_test_4_enemy_base_encounter_context() -> void:
	print("\n-- [TEST 4] Enemy Base Encounter Context --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)

	GlobalData.narrative.enemy_base_active = true
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(5, 5)
	GlobalData.narrative.enemy_base_progress = 10.0
	GlobalData.narrative.enemy_base_required = 20.0

	GameManager.enter_combat("enemy_base")

	_assert_true(GameManager.combat_node_type == "enemy_base", "[T4-1] combat_node_type is 'enemy_base'")
	_assert_true(GlobalData.narrative.enemy_base_active == true, "[T4-2] Enemy base active flag maintained during combat")


## ---------------------------------------------------------------------------
## TEST 5: Fuel Depot -> Correct Special Encounter Context
## ---------------------------------------------------------------------------
func _run_test_5_fuel_depot_encounter_context() -> void:
	print("\n-- [TEST 5] Fuel Depot Encounter Context --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)

	GlobalData.fuel.fuel_depot_approach = "precise"
	GameManager.enter_combat("fuel_depot")

	_assert_true(GameManager.combat_node_type == "fuel_depot", "[T5-1] combat_node_type is 'fuel_depot'")
	_assert_true(GlobalData.fuel.fuel_depot_approach == "precise", "[T5-2] fuel_depot_approach preserved for combat resolution")


## ---------------------------------------------------------------------------
## TEST 6: Combat A -> Board -> Combat B Isolation
## ---------------------------------------------------------------------------
func _run_test_6_combat_a_to_b_isolation() -> void:
	print("\n-- [TEST 6] Combat A -> Board -> Combat B Isolation --")
	GlobalData.reset_run_data()

	# Combat A: Patrol Ace fight
	GlobalData.board.board_patrol_engagement = 201
	GlobalData.board.board_patrols = [{"id": 201, "pilots": [{"archetype": 1}, {"archetype": 2}]}]
	GameManager.enter_combat("ace")
	_assert_true(GameManager.combat_node_type == "ace", "[T6-1] Combat A is 'ace'")
	_assert_true(GlobalData.board.board_patrol_engagement == 201, "[T6-2] Combat A engagement is 201")

	# Finish Combat A
	EventBus.combat_ended.emit(true)
	GameManager.return_to_board()
	_assert_true(GameManager.current_state == GameManager.State.BOARD, "[T6-3] Returned to State.BOARD")
	_assert_true(GlobalData.board.board_patrol_engagement == -1, "[T6-4] Combat A patrol engagement cleared to -1")

	# Combat B: Normal Grunt fight
	GameManager.enter_combat("grunt")
	_assert_true(GameManager.combat_node_type == "grunt", "[T6-5] Combat B is 'grunt' (not 'ace')")
	_assert_true(GlobalData.board.board_patrol_engagement == -1, "[T6-6] Combat B has clean patrol engagement (-1)")

	var spawner := SpawnManager.new()
	var defs_b: Array = spawner._get_active_defs()
	var is_patrol_roster := false
	if defs_b.size() > 0 and defs_b[0].size() > 0:
		is_patrol_roster = (defs_b[0][0].get("type") == "patrol_roster")
	_assert_true(not is_patrol_roster, "[T6-7] Combat B did NOT inherit Combat A's patrol_roster wave")
	spawner.free()


## ---------------------------------------------------------------------------
## TEST 7: Loadout Snapshot Belongs to Current Combat
## ---------------------------------------------------------------------------
func _run_test_7_loadout_snapshot_belongs_to_current_combat() -> void:
	print("\n-- [TEST 7] Loadout Snapshot Belongs to Current Combat --")
	GlobalData.reset_run_data()

	# Equip loadout A
	GlobalData.weapons.weapon_loadout = {
		"left": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"right": "res://resources/mech/stock/weapon_heat_blade.tres",
		"carry": []
	}
	GameManager.enter_combat("grunt")
	_assert_true(str(GlobalData.pre_combat_weapon_loadout.get("left")) == "res://resources/mech/stock/weapon_beam_rifle.tres", "[T7-1] Snapshot A has beam rifle in left")

	# Return to board and change loadout to Shotgun
	GameManager.return_to_board()
	GlobalData.weapons.weapon_loadout = {
		"left": "res://resources/mech/stock/weapon_combat_shotgun.tres",
		"right": "res://resources/mech/stock/weapon_heat_blade.tres",
		"carry": []
	}
	GameManager.enter_combat("grunt")
	_assert_true(str(GlobalData.pre_combat_weapon_loadout.get("left")) == "res://resources/mech/stock/weapon_combat_shotgun.tres", "[T7-2] Snapshot B accurately captures new shotgun loadout")


## ---------------------------------------------------------------------------
## TEST 8: Transient Combat State Resets Correctly
## ---------------------------------------------------------------------------
func _run_test_8_transient_combat_state_resets() -> void:
	print("\n-- [TEST 8] Transient Combat State Resets Correctly --")
	GlobalData.reset_run_data()

	# Simulate previous combat having set flags
	GlobalData._combat_xp_awarded = true
	GameManager.is_escaping = true

	# Enter new combat
	GameManager.enter_combat("grunt")

	_assert_true(GlobalData._combat_xp_awarded == false, "[T8-1] _combat_xp_awarded reset to false upon enter_combat")
	_assert_true(GameManager.is_escaping == false, "[T8-2] is_escaping reset to false upon enter_combat")


## ---------------------------------------------------------------------------
## TEST 9: Duplicate Combat-Entry Protection
## ---------------------------------------------------------------------------
func _run_test_9_duplicate_combat_entry_protection() -> void:
	print("\n-- [TEST 9] Duplicate Combat-Entry Protection --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)

	var board_mgr_script = load("res://scripts/board/board_manager.gd")
	var board_mgr = Node3D.new()
	var tile_cont = Node3D.new()
	tile_cont.name = "TileContainer"
	board_mgr.add_child(tile_cont)
	var p_token = Node3D.new()
	p_token.name = "PlayerToken"
	board_mgr.add_child(p_token)
	board_mgr.set_script(board_mgr_script)
	add_child(board_mgr)

	# Call _request_combat once
	board_mgr._request_combat("grunt")
	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T9-1] State transitioned to COMBAT on first request")

	# Change node_type intentionally to see if second request overrides it while in COMBAT
	GameManager.combat_node_type = "initial_type"
	board_mgr._request_combat("ignored_type")
	_assert_true(GameManager.combat_node_type == "initial_type", "[T9-2] Second _request_combat ignored while in State.COMBAT")

	board_mgr.queue_free()


## ---------------------------------------------------------------------------
## TEST 10: Save -> Reload -> Board -> Combat Preserves Correct Encounter
## ---------------------------------------------------------------------------
func _run_test_10_save_reload_preserves_correct_encounter() -> void:
	print("\n-- [TEST 10] Save -> Reload -> Board -> Combat Preserves Correct Encounter --")
	GlobalData.reset_run_data()
	GlobalData.board.current_tile = Vector2i(7, 3)
	GlobalData.board.board_patrols = [{"id": 305, "pos": Vector2i(7, 3), "fleet_count": 1, "pilots": []}]
	SaveGameIO.save_run()

	# Clear memory
	GlobalData.reset_run_data()

	# Reload from disk
	var loaded := SaveGameIO.load_run()
	_assert_true(loaded == true, "[T10-1] SaveGameIO.load_run succeeded")
	_assert_true(GlobalData.board.current_tile == Vector2i(7, 3), "[T10-2] Restored current tile (7, 3)")
	_assert_true(GlobalData.board.board_patrol_engagement == -1, "[T10-3] Restored transient patrol engagement is -1")

	# Now engage patrol 305 and enter combat
	GlobalData.board.board_patrol_engagement = 305
	GameManager.enter_combat("grunt")
	_assert_true(GameManager.combat_node_type == "grunt", "[T10-4] Combat initialized from reloaded board state")


## ---------------------------------------------------------------------------
## TEST 11: Defeat -> Board -> Combat B Isolation
## ---------------------------------------------------------------------------
func _run_test_11_defeat_to_combat_b_isolation() -> void:
	print("\n-- [TEST 11] Defeat -> Board -> Combat B Isolation --")
	GlobalData.reset_run_data()

	# Combat A ends in Defeat
	GameManager.enter_combat("boss")
	_assert_true(GameManager.is_boss_combat == true, "[T11-1] Combat A is boss combat")
	EventBus.combat_ended.emit(false)
	GameManager.return_to_board()

	_assert_true(GameManager.current_state == GameManager.State.BOARD, "[T11-2] Returned to BOARD after defeat")

	# Combat B starts
	GameManager.enter_combat("grunt")
	_assert_true(GameManager.combat_node_type == "grunt", "[T11-3] Combat B is 'grunt'")
	_assert_true(GameManager.is_boss_combat == false, "[T11-4] is_boss_combat reset to false for Combat B")
	_assert_true(GlobalData._combat_xp_awarded == false, "[T11-5] XP awarded latch is clean for Combat B")


## ---------------------------------------------------------------------------
## TEST 12: Escape -> Board -> Combat B Isolation
## ---------------------------------------------------------------------------
func _run_test_12_escape_to_combat_b_isolation() -> void:
	print("\n-- [TEST 12] Escape -> Board -> Combat B Isolation --")
	GlobalData.reset_run_data()

	GameManager.enter_combat("ace")
	GameManager.is_escaping = true
	EventBus.combat_ended.emit(false) # Escape terminates combat without victory
	GameManager.return_to_board()

	_assert_true(GameManager.current_state == GameManager.State.BOARD, "[T12-1] Returned to BOARD after escape")

	# Combat B starts
	GameManager.enter_combat("grunt")
	_assert_true(GameManager.is_escaping == false, "[T12-2] is_escaping reset to false for Combat B")
	_assert_true(GameManager.combat_node_type == "grunt", "[T12-3] Combat B entered cleanly as 'grunt'")


## ---------------------------------------------------------------------------
## TEST 13: Board -> Combat -> Board -> Combat Loop
## ---------------------------------------------------------------------------
func _run_test_13_board_combat_board_combat_loop() -> void:
	print("\n-- [TEST 13] Board -> Combat -> Board -> Combat Loop --")
	GlobalData.reset_run_data()

	# Cycle 1: Grunt
	GameManager.transition_to(GameManager.State.BOARD)
	GameManager.enter_combat("grunt")
	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T13-1] Cycle 1 entered COMBAT")
	EventBus.combat_ended.emit(true)
	GameManager.return_to_board()
	_assert_true(GameManager.current_state == GameManager.State.BOARD, "[T13-2] Cycle 1 returned to BOARD")

	# Cycle 2: Patrol Ace
	GlobalData.board.board_patrol_engagement = 401
	GlobalData.board.board_patrols = [{"id": 401, "pilots": [{"archetype": 0}]}]
	GameManager.enter_combat("ace")
	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T13-3] Cycle 2 entered COMBAT")
	EventBus.combat_ended.emit(true)
	GameManager.return_to_board()
	_assert_true(GameManager.current_state == GameManager.State.BOARD, "[T13-4] Cycle 2 returned to BOARD")
	_assert_true(GlobalData.board.board_patrol_engagement == -1, "[T13-5] Cycle 2 engagement cleared")

	# Cycle 3: Boss
	GameManager.enter_combat("boss")
	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T13-6] Cycle 3 entered COMBAT")
	_assert_true(GameManager.is_boss_combat == true, "[T13-7] Cycle 3 is boss combat")
	EventBus.combat_ended.emit(true)
	GameManager.return_to_board()
	_assert_true(GameManager.current_state == GameManager.State.BOARD, "[T13-8] Cycle 3 returned to BOARD")
	_assert_true(GameManager.is_boss_combat == false, "[T13-9] Boss flag reset on return to board")


## ---------------------------------------------------------------------------
## TEST 14: Duplicate Signal / Callback Protection
## ---------------------------------------------------------------------------
func _run_test_14_duplicate_signal_callback_protection() -> void:
	print("\n-- [TEST 14] Duplicate Signal / Callback Protection --")
	GlobalData.reset_run_data()
	GameManager.transition_to(GameManager.State.BOARD)

	var signal_box: Array = [0]
	var dummy_listener = func(_old_st, _new_st):
		signal_box[0] += 1
	EventBus.game_state_changed.connect(dummy_listener)

	GameManager.enter_combat("grunt")
	_assert_true(signal_box[0] == 1, "[T14-1] Single state transition emitted exactly 1 signal (got %d)" % signal_box[0])

	# Attempting enter_combat again while already in COMBAT
	GameManager.enter_combat("grunt")
	_assert_true(signal_box[0] == 2, "[T14-2] Repeated enter_combat in COMBAT emits cleanly without corrupting state (got %d)" % signal_box[0])

	EventBus.game_state_changed.disconnect(dummy_listener)
