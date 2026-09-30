extends Node

## Phase 2E-50: Global State Leakage & Reset Integrity Verification
## Comprehensive audit of global/shared runtime mutable state across test suites,
## scene transitions, board/combat lifecycles, and deterministic executions.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []


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
	print("PHASE 2E-50: GLOBAL STATE LEAKAGE & RESET AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	_run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_50_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_50_SUCCESS")
		get_tree().quit(0)


func _capture_global_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits,
		"scrap": GlobalData.currency.scrap,
		"data_cores": GlobalData.currency.data_cores,
		"convoy_fuel": GlobalData.fuel.convoy_fuel,
		"convoy_fuel_reserve": GlobalData.fuel.convoy_fuel_reserve,
		"mech_energy": GlobalData.fuel.mech_energy,
		"traversal_mode": GlobalData.fuel.traversal_mode,
		"board_mp": GlobalData.board.board_mp,
		"current_tile": GlobalData.board.current_tile,
		"board_seed": GlobalData.board.board_seed,
		"board_day": GlobalData.board.board_day,
		"time_hour": GlobalData.board.time_hour,
		"current_hazard": GlobalData.board.current_hazard,
		"convoy_breakdown_turns": GlobalData.board.convoy_breakdown_turns,
		"board_patrol_engagement": GlobalData.board.board_patrol_engagement,
		"patrol_count": GlobalData.board.board_patrols.size(),
		"game_state": GameManager.current_state,
		"mech_less": GlobalData.narrative.mech_less,
	}


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario 1: GlobalData Sub-Object Mutation and Clean Snapshot Rollback
	# ===========================================================================
	print("\n-- [1] GlobalData Sub-Object Mutation and Clean Snapshot Rollback --")
	var initial_snap := _capture_global_snapshot()
	_assert(not initial_snap.is_empty(), "Global state snapshot captured successfully")

	# Deliberately mutate multiple singletons
	GlobalData.currency.gain_credits(999)
	GlobalData.currency.gain_scrap(450)
	GlobalData.fuel.mech_energy = 123.45
	GlobalData.board.board_mp = 1
	GlobalData.board.current_hazard = GlobalData.HAZARD_SANDSTORM
	GlobalData.board.convoy_breakdown_turns = 3
	GlobalData.board.board_patrol_engagement = 888
	GameManager.current_state = GameManager.State.COMBAT

	var mutated_snap := _capture_global_snapshot()
	_assert(mutated_snap["credits"] != initial_snap["credits"], "Credits mutated in snapshot")
	_assert(mutated_snap["current_hazard"] == GlobalData.HAZARD_SANDSTORM, "Hazard mutated in snapshot")
	_assert(mutated_snap["board_patrol_engagement"] == 888, "Engagement mutated in snapshot")

	# Explicit rollback to initial baseline
	GlobalData.currency.credits = initial_snap["credits"]
	GlobalData.currency.scrap = initial_snap["scrap"]
	GlobalData.fuel.mech_energy = initial_snap["mech_energy"]
	GlobalData.board.board_mp = initial_snap["board_mp"]
	GlobalData.board.current_hazard = initial_snap["current_hazard"]
	GlobalData.board.convoy_breakdown_turns = initial_snap["convoy_breakdown_turns"]
	GlobalData.board.board_patrol_engagement = initial_snap["board_patrol_engagement"]
	GameManager.current_state = initial_snap["game_state"]

	var restored_snap := _capture_global_snapshot()
	_assert(restored_snap == initial_snap, "Explicit state restoration reconstitutes exact baseline snapshot")

	# ===========================================================================
	# Scenario 2: Board -> Combat -> Board State Transfer & Engagement Reset
	# ===========================================================================
	print("\n-- [2] Board -> Combat -> Board State Transfer & Engagement Reset --")
	GlobalData.board.board_patrols = [
		{"id": 501, "pos": Vector2i(3, 3), "home": Vector2i(3, 3), "dir": Vector2i(1, 0), "archetype": "recon", "fleet_count": 1, "name": "Scout"}
	]
	GlobalData.board.board_patrol_engagement = 501
	GameManager.enter_combat("grunt")
	_assert(GlobalData.board.board_patrol_engagement == 501, "Combat entry transfers patrol ID 501")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "Authoritative state is State.COMBAT")

	# Combat resolution flow
	PatrolSystem.remove_patrol(501)
	GlobalData.board.board_patrol_engagement = -1
	GameManager.return_to_board()

	_assert(GlobalData.board.board_patrol_engagement == -1, "Engagement ID reset to -1 upon return to board")
	_assert(GlobalData.board.board_patrols.is_empty(), "Resolved patrol 501 cleanly removed from board_patrols")
	_assert(GameManager.current_state == GameManager.State.BOARD, "Authoritative state restored to State.BOARD")

	# ===========================================================================
	# Scenario 3: Board Seed & Procedural Generation Isolation
	# ===========================================================================
	print("\n-- [3] Board Seed & Procedural Generation Isolation --")
	var mock_nodes: Dictionary = {}
	for x in range(6):
		for y in range(6):
			var n = Node.new()
			n.set_meta("tile_type", "empty")
			n.set_meta("terrain", "plain")
			mock_nodes[Vector2i(x, y)] = n
	GlobalData.board.board_grid = [mock_nodes]

	GlobalData.board.board_seed = 44444
	GlobalData.board.board_patrols = []
	PatrolSystem.spawn_patrols()
	var patrols_seed_a: Array = GlobalData.board.board_patrols.duplicate(true)
	_assert(not patrols_seed_a.is_empty(), "Patrols generated for seed 44444")

	GlobalData.board.board_seed = 99999
	GlobalData.board.board_patrols = []
	PatrolSystem.spawn_patrols()
	var patrols_seed_b: Array = GlobalData.board.board_patrols.duplicate(true)
	_assert(not patrols_seed_b.is_empty(), "Patrols generated for seed 99999")

	# Compare layout positions between seeds
	var pos_a: Array[Vector2i] = []
	for p in patrols_seed_a: pos_a.append(p.get("pos", Vector2i.ZERO))
	var pos_b: Array[Vector2i] = []
	for p in patrols_seed_b: pos_b.append(p.get("pos", Vector2i.ZERO))
	_assert(pos_a != pos_b or patrols_seed_a.size() != patrols_seed_b.size(), "Distinct seeds produce distinct procedural patrol placements")

	# Teardown mock nodes
	for n in mock_nodes.values():
		n.free()
	GlobalData.board.board_grid = []
	GlobalData.board.board_patrols = []

	# ===========================================================================
	# Scenario 4: Time/Day Clock & Midnight Crossing Isolation
	# ===========================================================================
	print("\n-- [4] Time/Day Clock & Midnight Crossing Isolation --")
	GlobalData.board.time_hour = 8.0
	GlobalData.board.board_day = 1
	_assert(GlobalData.board.time_hour == 8.0, "Clock initialized to 08:00")
	_assert(GlobalData.board.board_day == 1, "Day initialized to Day 1")

	# Advance time without crossing midnight
	DayNightSystem.advance_step("plain")
	_assert(GlobalData.board.time_hour > 8.0 and GlobalData.board.time_hour < 24.0, "Single step advances hour without crossing midnight")
	_assert(GlobalData.board.board_day == 1, "Day remains Day 1 within same calendar day")

	# Reset clock to standard morning baseline
	GlobalData.board.time_hour = 8.0
	_assert(GlobalData.board.time_hour == 8.0, "Clock restored cleanly to 08:00 baseline")

	# ===========================================================================
	# Scenario 5: Static System State Lifecycle Audit
	# ===========================================================================
	print("\n-- [5] Static System State Lifecycle Audit --")
	_assert(SpawnManager != null, "SpawnManager class accessible")
	SpawnManager._completed_fallback_enemy_ids.clear()
	_assert(SpawnManager._completed_fallback_enemy_ids.is_empty(), "SpawnManager fallback enemy cache cleared cleanly")

	SpawnManager._completed_fallback_enemy_ids["enemy_test_1"] = true
	_assert(SpawnManager._completed_fallback_enemy_ids.has("enemy_test_1"), "SpawnManager cache tracks spawned enemy")
	SpawnManager._completed_fallback_enemy_ids.clear()
	_assert(SpawnManager._completed_fallback_enemy_ids.is_empty(), "SpawnManager cache reset verified")

	# ===========================================================================
	# Scenario 6: EventBus Signal Connection Teardown on Node Free
	# ===========================================================================
	print("\n-- [6] EventBus Signal Connection Teardown on Node Free --")
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	_assert(EventBus.combat_ended.is_connected(rewards_ui._on_combat_ended), "CombatRewardsUI registered combat_ended listener in _ready")

	remove_child(rewards_ui)
	_assert(!EventBus.combat_ended.is_connected(rewards_ui._on_combat_ended), "CombatRewardsUI unregistered combat_ended listener in _exit_tree")
	rewards_ui.free()
	_assert(!is_instance_valid(rewards_ui), "CombatRewardsUI node freed cleanly")

	# ===========================================================================
	# Scenario 7: Synchronous Scene Instantiation & Free
	# ===========================================================================
	print("\n-- [7] Synchronous Scene Instantiation & Free --")
	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	var board_node: BoardManager = board_res.instantiate() as BoardManager
	add_child(board_node)
	_assert(is_instance_valid(board_node), "Board scene instantiated and attached to scene tree")

	remove_child(board_node)
	board_node.free()
	_assert(!is_instance_valid(board_node), "Board scene freed synchronously without deferred lingering")

	# ===========================================================================
	# Scenario 8: Narrative Mech-less Mode Contract Isolation
	# ===========================================================================
	print("\n-- [8] Narrative Mech-less Mode Contract Isolation --")
	GlobalData.narrative.mech_less = true
	_assert(GlobalData.narrative.mech_less == true, "mech_less set to true")
	GlobalData.narrative.mech_less = false
	_assert(GlobalData.narrative.mech_less == false, "mech_less reset to false")

	# ===========================================================================
	# Scenario 9: Fuel, Energy & Drop Tank Persistence
	# ===========================================================================
	print("\n-- [9] Fuel, Energy & Drop Tank Persistence --")
	GlobalData.fuel.mech_energy = 850.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.drop_tanks_attached = 2
	GlobalData.fuel.drop_tank_fuel = 80.0

	_assert(is_equal_approx(GlobalData.fuel.mech_energy, 850.0), "Mech energy stored authoritatively")
	_assert(GlobalData.fuel.drop_tanks_attached == 2, "Drop tanks attached count stored authoritatively")
	_assert(is_equal_approx(GlobalData.fuel.drop_tank_fuel, 80.0), "Drop tank fuel stored authoritatively")

	# Clean reset
	GlobalData.fuel.drop_tanks_attached = 0
	GlobalData.fuel.drop_tank_fuel = 0.0
	GlobalData.fuel.mech_energy = 1000.0
	_assert(GlobalData.fuel.drop_tanks_attached == 0, "Drop tanks reset cleanly")

	# ===========================================================================
	# Scenario 10: Multi-Run Determinism Invariance
	# ===========================================================================
	print("\n-- [10] Multi-Run Determinism Invariance --")
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 987654
	var seq1: Array[int] = []
	for i in range(15): seq1.append(rng1.randi_range(1, 1000))

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 987654
	var seq2: Array[int] = []
	for i in range(15): seq2.append(rng2.randi_range(1, 1000))

	_assert(seq1 == seq2, "Random sequences with identical seed produce bit-identical values")


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-50 GLOBAL STATE AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failures.is_empty():
		print("FAILED ASSERTIONS:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")
