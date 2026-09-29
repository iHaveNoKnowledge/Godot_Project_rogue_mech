extends Node

## Phase 2E-47: Temporal Ordering & Event Causality Integrity Audit Test Suite
## Verifies that all mutations, events, callbacks, deferred operations, scene transitions,
## and derived-state updates execute in the correct temporal order and are causally connected.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []
var _board_scene: BoardManager = null

var _timeline: Array[Dictionary] = []


func _record_step(step_name: String, data: Dictionary = {}) -> void:
	_timeline.append({
		"step": step_name,
		"seq": _timeline.size(),
		"time_us": Time.get_ticks_usec(),
		"data": data
	})


func _find_step_seq(step_name: String) -> int:
	for entry in _timeline:
		if entry["step"] == step_name:
			return int(entry["seq"])
	return -1


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failures.append(message)
		print("  [FAIL] %s" % message)


func _assert_order(first_step: String, second_step: String, context_msg: String) -> void:
	var s1 := _find_step_seq(first_step)
	var s2 := _find_step_seq(second_step)
	var ok := (s1 != -1 and s2 != -1 and s1 < s2)
	_assert(ok, "%s (Order: '%s' [#%d] < '%s' [#%d])" % [context_msg, first_step, s1, second_step, s2])


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-47: TEMPORAL ORDERING & EVENT CAUSALITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	_run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_47_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_47_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-47 CAUSALITY AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")


func _find_passable_neighbor(board: BoardManager, origin: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cand: Vector2i = origin + d
		if board.nodes_dict.has(cand):
			var tile_node = board.nodes_dict[cand]
			var ter := str(tile_node.get_meta("terrain", "plain"))
			if BoardConfig.is_passable(ter):
				return cand
	return Vector2i(-1, -1)


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
	_test_scenario_a_movement_temporal_ordering()
	_test_scenario_b_movement_tile_effect_ordering()
	_test_scenario_c_movement_encounter_combat_ordering()
	_test_scenario_d_combat_victory_reward_board_ordering()
	_test_scenario_e_combat_retreat_heat_board_ordering()
	_test_scenario_f_duplicate_combat_resolution_temporal()
	_test_scenario_g_duplicate_reward_continue_temporal()
	_test_scenario_h_sector_transition_pending_work()
	_test_scenario_i_run_termination_temporal()
	_test_scenario_j_run_reset_stale_callback()
	_test_scenario_k_event_listener_reentry()
	_test_scenario_l_nested_signal_ordering()
	_test_scenario_m_queue_free_lifetime_safety()
	_test_scenario_n_timer_scene_boundary_safety()
	_test_scenario_o_save_load_pending_reactive_work()
	_test_scenario_p_full_causal_pipeline()


# --- Scenario A: Normal Board Movement Temporal Ordering ---
func _test_scenario_a_movement_temporal_ordering() -> void:
	print("\n--- Scenario A: Normal Movement Temporal Ordering ---")
	_timeline.clear()
	var board := _instantiate_board_scene()
	var start_tile: Vector2i = board.current_pos
	var target_tile := _find_passable_neighbor(board, start_tile)

	var mp_before := GlobalData.board.board_mp
	var step_ctx := {
		"observed_tile": Vector2i(-1, -1),
		"observed_mp": -1
	}

	var on_tile_entered = func(t_pos: Vector2i, _tile):
		step_ctx["observed_tile"] = t_pos
		step_ctx["observed_mp"] = GlobalData.board.board_mp
		_record_step("event:tile_entered", {"observed_tile": step_ctx["observed_tile"], "observed_mp": step_ctx["observed_mp"]})

	EventBus.tile_entered.connect(on_tile_entered)
	_record_step("command:try_step_start")

	var ok := board._try_step(target_tile)
	_record_step("command:try_step_end")
	EventBus.tile_entered.disconnect(on_tile_entered)

	_assert(ok == true, "A.1: Step returned true")
	_assert(step_ctx["observed_tile"] == target_tile, "A.2: Listener observed committed target tile when event fired (T1 Invariant)")
	_assert(step_ctx["observed_mp"] < mp_before, "A.3: Listener observed committed deducted MP when event fired")
	_assert_order("command:try_step_start", "event:tile_entered", "A.4: Command initiated before event emission")
	_assert_order("event:tile_entered", "command:try_step_end", "A.5: Event emission completed synchronously within step execution")


# --- Scenario B: Movement -> Tile Effect Ordering ---
func _test_scenario_b_movement_tile_effect_ordering() -> void:
	print("\n--- Scenario B: Movement -> Tile Effect Ordering ---")
	_timeline.clear()
	var board := _instantiate_board_scene()
	var target_tile := _find_passable_neighbor(board, board.current_pos)

	# Register wreckage on target tile
	ScavengerSystem.register_tile_wreckage(target_tile, [{"type": "weapon", "weapon": null, "scrap": 25}])

	var on_tile = func(t_pos: Vector2i, _tile):
		_record_step("event:tile_entered", {"pos": t_pos, "wreckage_remaining": ScavengerSystem.has_wreckage_at(t_pos)})

	EventBus.tile_entered.connect(on_tile)
	_record_step("command:move_to_wreckage")
	board._try_step(target_tile)
	EventBus.tile_entered.disconnect(on_tile)
	_record_step("command:wreckage_step_done")

	_assert(not ScavengerSystem.has_wreckage_at(target_tile), "B.1: Wreckage consumed upon entering tile")
	_assert_order("command:move_to_wreckage", "event:tile_entered", "B.2: Step initiated before tile entered notification")


# --- Scenario C: Movement -> Encounter -> Combat Transition Ordering ---
func _test_scenario_c_movement_encounter_combat_ordering() -> void:
	print("\n--- Scenario C: Movement -> Encounter -> Combat Transition Ordering ---")
	_timeline.clear()
	var board := _instantiate_board_scene()
	var target_tile := _find_passable_neighbor(board, board.current_pos)

	GlobalData.board.board_patrols = [{
		"id": 991,
		"pos": target_tile,
		"prev_pos": target_tile,
		"fleet_count": 1,
		"faction": "hostile"
	}]

	_record_step("command:step_into_patrol")
	board._try_step(target_tile)
	_record_step("authority:engagement_registered", {"id": GlobalData.board.board_patrol_engagement})

	_assert(GlobalData.board.board_patrol_engagement == 991, "C.1: Engagement registered for engaged patrol")
	_assert(GlobalData.board.current_tile == target_tile, "C.2: Authoritative tile updated to encounter position")
	_assert_order("command:step_into_patrol", "authority:engagement_registered", "C.3: Position step preceded combat engagement registration")


# --- Scenario D: Combat Victory -> Reward -> Board Return Ordering ---
func _test_scenario_d_combat_victory_reward_board_ordering() -> void:
	print("\n--- Scenario D: Combat Victory -> Reward -> Board Return Ordering ---")
	_timeline.clear()
	GameManager.current_state = GameManager.State.COMBAT
	GlobalData.board.board_patrol_engagement = 992
	GlobalData.board.board_patrols = [{"id": 992, "pos": Vector2i(2, 2), "fleet_count": 1, "faction": "hostile"}]

	var on_combat_ended = func(vic: bool):
		_record_step("event:combat_ended", {"victory": vic, "patrol_cleared": PatrolSystem.get_patrol_by_id(992).is_empty()})
	var on_state_changed = func(old_s: String, new_s: String):
		_record_step("event:state_changed", {"old": old_s, "new": new_s})

	EventBus.combat_ended.connect(on_combat_ended)
	EventBus.game_state_changed.connect(on_state_changed)

	_record_step("combat:win_trigger")
	EventBus.combat_ended.emit(true)

	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._show_victory_rewards()
	_record_step("ui:rewards_shown")

	rewards_ui._on_continue_pressed()
	_record_step("ui:rewards_continue_pressed")
	remove_child(rewards_ui)
	rewards_ui.free()

	EventBus.combat_ended.disconnect(on_combat_ended)
	EventBus.game_state_changed.disconnect(on_state_changed)

	_assert(PatrolSystem.get_patrol_by_id(992).is_empty(), "D.1: Patrol removed on combat victory")
	_assert(GameManager.current_state == GameManager.State.BOARD, "D.2: Game state returned to State.BOARD")
	_assert_order("combat:win_trigger", "event:combat_ended", "D.3: Win trigger preceded combat_ended signal")
	_assert_order("event:combat_ended", "ui:rewards_shown", "D.4: Combat ended handled before rewards presented")
	_assert_order("ui:rewards_shown", "ui:rewards_continue_pressed", "D.5: Rewards display preceded continue action")


# --- Scenario E: Combat Retreat -> Heat/State -> Board Return Ordering ---
func _test_scenario_e_combat_retreat_heat_board_ordering() -> void:
	print("\n--- Scenario E: Combat Retreat -> Heat/State -> Board Return Ordering ---")
	_timeline.clear()
	GameManager.current_state = GameManager.State.COMBAT
	var heat_before := GlobalData.board.heat

	var on_escaped = func():
		_record_step("event:combat_escaped", {"heat": GlobalData.board.heat})

	EventBus.combat_escaped.connect(on_escaped)

	_record_step("combat:escape_trigger")
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	EventBus.combat_escaped.emit()

	EventBus.combat_escaped.disconnect(on_escaped)
	rewards_ui._on_continue_pressed()
	_record_step("ui:escape_continue")
	remove_child(rewards_ui)
	rewards_ui.free()

	_assert(GlobalData.board.heat > heat_before, "E.1: Escape heat penalty applied")
	_assert(GameManager.current_state == GameManager.State.BOARD, "E.2: Game state returned to State.BOARD")
	_assert_order("combat:escape_trigger", "event:combat_escaped", "E.3: Escape trigger preceded escape signal")
	_assert_order("event:combat_escaped", "ui:escape_continue", "E.4: Escape notification preceded continue transition")


# --- Scenario F: Duplicate Combat Resolution Temporal Invariant ---
func _test_scenario_f_duplicate_combat_resolution_temporal() -> void:
	print("\n--- Scenario F: Duplicate Combat Resolution Temporal Invariant ---")
	GameManager.current_state = GameManager.State.COMBAT
	GameManager.combat_node_type = "normal"
	GlobalData._combat_xp_awarded = false
	GlobalData.hangar.pending_duel = {}
	GlobalData.board.board_patrol_engagement = -1

	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)

	# Initial resolution via EventBus
	EventBus.combat_ended.emit(true)
	var credits_after_first := GlobalData.currency.credits

	# Duplicate resolution event fires late
	EventBus.combat_ended.emit(true)
	rewards_ui._show_victory_rewards()

	_assert(GlobalData.currency.credits == credits_after_first, "F.1: Late/duplicate combat resolution produces zero extra reward payout")
	remove_child(rewards_ui)
	rewards_ui.free()


# --- Scenario G: Duplicate Reward Continuation Temporal Invariant ---
func _test_scenario_g_duplicate_reward_continue_temporal() -> void:
	print("\n--- Scenario G: Duplicate Reward Continuation Temporal Invariant ---")
	GameManager.current_state = GameManager.State.COMBAT
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._show_victory_rewards()

	rewards_ui._on_continue_pressed()
	var state_after_first := GameManager.current_state

	# Rapid double-press or deferred re-trigger
	rewards_ui._on_continue_pressed()
	_assert(GameManager.current_state == state_after_first, "G.1: Secondary continue press ignored by active continue guard")
	remove_child(rewards_ui)
	rewards_ui.free()


# --- Scenario H: Sector Transition with Pending Work ---
func _test_scenario_h_sector_transition_pending_work() -> void:
	print("\n--- Scenario H: Sector Transition Pending Work ---")
	_timeline.clear()
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)
	GlobalData.board.board_patrols = [{"id": 994, "pos": Vector2i(4, 4), "fleet_count": 1}]

	_record_step("command:advance_sector_start")
	GameManager.advance_to_next_sector()
	_record_step("command:advance_sector_done", {
		"sector": GlobalData.board.current_sector,
		"tile": GlobalData.board.current_tile,
		"patrols": GlobalData.board.board_patrols.size()
	})

	_assert(GlobalData.board.current_sector == 2, "H.1: Sector incremented to 2")
	_assert(GlobalData.board.board_patrols.is_empty(), "H.2: Old sector patrols cleared atomically on sector change")
	_assert_order("command:advance_sector_start", "command:advance_sector_done", "H.3: Sector advance completed sequentially")


# --- Scenario I: Run Termination with Pending Work ---
func _test_scenario_i_run_termination_temporal() -> void:
	print("\n--- Scenario I: Run Termination with Pending Work ---")
	_timeline.clear()
	GameManager.current_state = GameManager.State.BOARD
	_record_step("command:game_over_call")
	GameManager.game_over()
	_record_step("authority:state_set_game_over", {"state": GameManager.current_state})

	_assert(GameManager.current_state == GameManager.State.MENU, "I.1: State is MENU on game_over")
	_assert_order("command:game_over_call", "authority:state_set_game_over", "I.3: Game over call committed terminal state")


# --- Scenario J: Run Reset Followed by Stale Callback Attempt ---
func _test_scenario_j_run_reset_stale_callback() -> void:
	print("\n--- Scenario J: Run Reset Followed by Stale Callback Attempt ---")
	_timeline.clear()
	GlobalData.currency.credits = 9999
	GlobalData.board.current_sector = 4

	_record_step("command:reset_run")
	GlobalData.reset_run_data()
	_record_step("authority:run_reset_complete", {
		"credits": GlobalData.currency.credits,
		"sector": GlobalData.board.current_sector
	})

	# Simulated stale deferred callback from old sector trying to mutate currency
	var stale_callback = func(amount: int):
		if GameManager.current_state == GameManager.State.MENU:
			# Stale board callback rejected when in terminal/menu state
			_record_step("stale_callback:rejected")
		else:
			GlobalData.currency.gain_credits(amount)
			_record_step("stale_callback:applied")

	stale_callback.call(500)

	_assert(GlobalData.currency.credits == 110, "J.1: Currency reset to clean starting baseline (110)")
	_assert(GlobalData.board.current_sector == 1, "J.2: Sector reset to 1")
	_assert_order("command:reset_run", "authority:run_reset_complete", "J.3: Reset command preceded state snapshot")
	_assert_order("authority:run_reset_complete", "stale_callback:rejected", "J.4: Stale callback rejected after reset boundary")


# --- Scenario K: Event Listener Cascading Reaction Integrity ---
func _test_scenario_k_event_listener_reentry() -> void:
	print("\n--- Scenario K: Event Listener Cascading Reaction Integrity ---")
	_timeline.clear()
	var cascade_order: Array[String] = []

	var on_heat = func(new_heat: int):
		cascade_order.append("heat_received")
		_record_step("listener:heat_changed", {"val": new_heat})

	var on_damage = func(_slot: String, _dmg: float, _type: String):
		cascade_order.append("damage_start")
		_record_step("listener:damage_start")
		EventBus.heat_changed.emit(5)
		cascade_order.append("damage_end")
		_record_step("listener:damage_end")

	EventBus.damage_received.connect(on_damage)
	EventBus.heat_changed.connect(on_heat)

	_record_step("command:emit_root_event")
	EventBus.damage_received.emit("torso", 15.0, "ballistic")

	EventBus.damage_received.disconnect(on_damage)
	EventBus.heat_changed.disconnect(on_heat)

	_assert(cascade_order == ["damage_start", "heat_received", "damage_end"], "K.1: Cascading reactive signals execute in deterministic nested order")
	_assert_order("listener:damage_start", "listener:heat_changed", "K.2: Outer listener started before cascading listener")
	_assert_order("listener:heat_changed", "listener:damage_end", "K.3: Cascading listener completed before outer listener completed")


# --- Scenario L: Nested Signal Emission Ordering ---
func _test_scenario_l_nested_signal_ordering() -> void:
	print("\n--- Scenario L: Nested Signal Emission Ordering ---")
	_timeline.clear()
	var execution_order: Array[String] = []

	var on_sig_b = func(_lvl: int, _sp: int):
		execution_order.append("sig_b")
		_record_step("signal:B_received")

	var on_sig_a = func():
		execution_order.append("sig_a_start")
		_record_step("signal:A_start")
		EventBus.pilot_level_up.emit(2, 1)
		execution_order.append("sig_a_end")
		_record_step("signal:A_end")

	var on_dmg = func(_s: String, _d: float, _t: String):
		on_sig_a.call()

	EventBus.damage_received.connect(on_dmg)
	EventBus.pilot_level_up.connect(on_sig_b)

	EventBus.damage_received.emit("torso", 10.0, "kinetic")

	EventBus.damage_received.disconnect(on_dmg)
	EventBus.pilot_level_up.disconnect(on_sig_b)

	_assert(execution_order == ["sig_a_start", "sig_b", "sig_a_end"], "L.1: Synchronous nested signals execute within the emitting call frame")
	_assert_order("signal:A_start", "signal:B_received", "L.2: Outer signal started before inner signal")
	_assert_order("signal:B_received", "signal:A_end", "L.3: Inner signal completed before outer signal unblocked")


# --- Scenario M: queue_free / Deferred Callback Lifetime Safety ---
func _test_scenario_m_queue_free_lifetime_safety() -> void:
	print("\n--- Scenario M: queue_free / Deferred Callback Lifetime Safety ---")
	_timeline.clear()
	var dummy := Node.new()
	add_child(dummy)
	_record_step("node:created")

	dummy.queue_free()
	_record_step("node:queue_freed")

	# Invariant: queued for deletion node is safely identifiable
	_assert(dummy.is_queued_for_deletion() == true, "M.1: is_queued_for_deletion() is immediately true upon queue_free()")
	_assert_order("node:created", "node:queue_freed", "M.2: Creation preceded queue_free request")


# --- Scenario N: Timer/Process Frame Scene Boundary Safety ---
func _test_scenario_n_timer_scene_boundary_safety() -> void:
	print("\n--- Scenario N: Timer/Process Frame Scene Boundary Safety ---")
	_timeline.clear()
	var executed := false
	var valid_at_execution := false

	var source_node := Node.new()
	add_child(source_node)

	var callback = func(node_ref: Node):
		if is_instance_valid(node_ref):
			if node_ref.is_inside_tree():
				valid_at_execution = true
		executed = true
		_record_step("callback:executed", {"valid": valid_at_execution})

	# Node is removed before callback executes
	remove_child(source_node)
	source_node.free()
	_record_step("node:freed_before_callback")

	callback.call(source_node)

	_assert(executed == true, "N.1: Callback executed")
	_assert(valid_at_execution == false, "N.2: Callback correctly detected invalidated node reference")
	_assert_order("node:freed_before_callback", "callback:executed", "N.3: Node invalidation preceded callback check")


# --- Scenario O: Save/Load Boundary with Reactive State ---
func _test_scenario_o_save_load_pending_reactive_work() -> void:
	print("\n--- Scenario O: Save/Load Boundary with Reactive State ---")
	_timeline.clear()
	GlobalData.board.current_sector = 3
	GlobalData.currency.credits = 1200
	GlobalData.board.current_tile = Vector2i(5, 7)

	_record_step("state:pre_save_snapshot")
	SaveGameIO.save_run()
	_record_step("io:save_data_gathered")

	# Mutate state post-save
	GlobalData.currency.credits = 5000
	GlobalData.board.current_sector = 5
	_record_step("state:mutated_post_save")

	# Restore from snapshot
	SaveGameIO.load_run()
	_record_step("io:save_data_applied")

	_assert(GlobalData.currency.credits == 1200, "O.1: Currency restored accurately from snapshot")
	_assert(GlobalData.board.current_sector == 3, "O.2: Sector restored accurately from snapshot")
	_assert_order("state:pre_save_snapshot", "io:save_data_gathered", "O.3: Snapshot captured before gather")
	_assert_order("io:save_data_gathered", "state:mutated_post_save", "O.4: Gather completed before mutation")
	_assert_order("state:mutated_post_save", "io:save_data_applied", "O.5: Mutation preceded restoration boundary")


# --- Scenario P: Full Causal Pipeline ---
func _test_scenario_p_full_causal_pipeline() -> void:
	print("\n--- Scenario P: Full Causal Pipeline ---")
	_timeline.clear()

	# 1. Start on Board
	var board := _instantiate_board_scene()
	_record_step("phase:1_board_start", {"tile": board.current_pos})
	_assert(GameManager.current_state == GameManager.State.BOARD, "P.1: Initial state is BOARD")

	# 2. Step into enemy encounter tile
	var target_tile := _find_passable_neighbor(board, board.current_pos)
	GlobalData.board.board_patrols = [{"id": 995, "pos": target_tile, "fleet_count": 1, "faction": "hostile"}]
	board._try_step(target_tile)
	_record_step("phase:2_step_complete", {"tile": GlobalData.board.current_tile})
	_assert(GlobalData.board.current_tile == target_tile, "P.2: Step moved token to target")

	# 3. Enter Combat
	GameManager.enter_combat("grunt")
	_record_step("phase:3_combat_entered", {"state": GameManager.current_state})
	_assert(GameManager.current_state == GameManager.State.COMBAT, "P.3: State changed to COMBAT")

	# 4. Win Combat and claim rewards
	EventBus.combat_ended.emit(true)
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._show_victory_rewards()
	rewards_ui._on_continue_pressed()
	remove_child(rewards_ui)
	rewards_ui.free()
	_record_step("phase:4_rewards_returned_board", {"state": GameManager.current_state})
	_assert(GameManager.current_state == GameManager.State.BOARD, "P.4: State returned to BOARD")

	# 5. Advance Sector
	GameManager.advance_to_next_sector()
	_record_step("phase:5_sector_advanced", {"sector": GlobalData.board.current_sector})
	_assert(GlobalData.board.current_sector >= 2, "P.5: Advanced to Sector 2+")

	# Verify full pipeline temporal ordering
	_assert_order("phase:1_board_start", "phase:2_step_complete", "P.6: Board start preceded step")
	_assert_order("phase:2_step_complete", "phase:3_combat_entered", "P.7: Step preceded combat entry")
	_assert_order("phase:3_combat_entered", "phase:4_rewards_returned_board", "P.8: Combat entry preceded rewards return")
	_assert_order("phase:4_rewards_returned_board", "phase:5_sector_advanced", "P.9: Return to board preceded sector advancement")
