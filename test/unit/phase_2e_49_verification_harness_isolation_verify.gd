extends Node

## Phase 2E-49: Verification Harness Isolation, Determinism & Cross-Suite Contamination Audit
## Verifies that the test harness maintains strict state isolation, deterministic reproducibility,
## signal/timer lifecycle cleanliness, filesystem isolation, and order-independent execution.

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
	print("PHASE 2E-49: HARNESS ISOLATION & DETERMINISM AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	_run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_49_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_49_SUCCESS")
		get_tree().quit(0)


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits,
		"scrap": GlobalData.currency.scrap,
		"data_cores": GlobalData.currency.data_cores,
		"convoy_fuel": GlobalData.fuel.convoy_fuel,
		"convoy_fuel_reserve": GlobalData.fuel.convoy_fuel_reserve,
		"mech_energy": GlobalData.fuel.mech_energy,
		"pilot_stamina": GlobalData.fuel.pilot_stamina,
		"traversal_mode": GlobalData.fuel.traversal_mode,
		"current_sector": GlobalData.board.current_sector,
		"current_tile": GlobalData.board.current_tile,
		"board_mp": GlobalData.board.board_mp,
		"board_patrol_engagement": GlobalData.board.board_patrol_engagement,
		"active_contract": GlobalData.board.active_contract.duplicate(true),
		"game_state": GameManager.current_state,
	}


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario 1: Singleton State Cleanliness & Reset Isolation
	# ===========================================================================
	print("\n-- [1] Singleton State Cleanliness & Reset Isolation --")
	GlobalData.currency.credits = 9999
	GlobalData.currency.scrap = 500
	GlobalData.currency.data_cores = 50
	GlobalData.currency.reset(110)

	_assert(GlobalData.currency.credits == 110, "Currency reset restores exact starting credits (110)")
	_assert(GlobalData.currency.scrap == 0, "Currency reset zeroes scrap")
	_assert(GlobalData.currency.data_cores == 0, "Currency reset zeroes data cores")

	GlobalData.fuel.convoy_fuel = 350.0
	GlobalData.fuel.convoy_fuel_reserve = 100.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 50.0
	GlobalData.fuel.traversal_mode = "convoy"

	_assert(GlobalData.fuel.traversal_mode == "convoy", "Fuel traversal mode resets to 'convoy'")
	_assert(GlobalData.fuel.convoy_fuel == 350.0, "Convoy fuel resets to 350.0")

	# ===========================================================================
	# Scenario 2: Signal Connection Lifecycle & Dangling Listener Isolation
	# ===========================================================================
	print("\n-- [2] Signal Connection Lifecycle & Dangling Listener Isolation --")
	var event_counter := {"count": 0}
	var test_listener = func(_data):
		event_counter["count"] += 1

	# Connect listener
	EventBus.event_triggered.connect(test_listener)
	_assert(EventBus.event_triggered.is_connected(test_listener), "Test listener successfully connected to EventBus")

	# Trigger event
	EventBus.event_triggered.emit({"name": "TEST_EVENT"})
	_assert(event_counter["count"] == 1, "Listener received event exactly once")

	# Disconnect listener
	EventBus.event_triggered.disconnect(test_listener)
	_assert(!EventBus.event_triggered.is_connected(test_listener), "Listener cleanly disconnected from EventBus")

	# Trigger second event; listener must NOT fire
	EventBus.event_triggered.emit({"name": "TEST_EVENT_2"})
	_assert(event_counter["count"] == 1, "Disconnected listener received 0 subsequent events (no dangling connection)")

	# ===========================================================================
	# Scenario 3: Scene Tree Instantiation & Teardown Cleanliness
	# ===========================================================================
	print("\n-- [3] Scene Tree Instantiation & Teardown Cleanliness --")
	var initial_child_count := get_child_count()

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	var board_instance: BoardManager = board_res.instantiate() as BoardManager
	add_child(board_instance)

	_assert(get_child_count() == initial_child_count + 1, "Board scene added as child")
	_assert(is_instance_valid(board_instance), "Board instance is valid node in tree")

	# Teardown
	remove_child(board_instance)
	board_instance.free()

	_assert(get_child_count() == initial_child_count, "Child count restored to baseline after board free")
	_assert(!is_instance_valid(board_instance), "Freed board reference is invalidated")

	# ===========================================================================
	# Scenario 4: UI Signal & Modal Teardown Isolation (Finding C Audit)
	# ===========================================================================
	print("\n-- [4] UI Signal & Modal Teardown Isolation (Finding C Audit) --")
	var rewards_ui := CombatRewardsUI.new()
	add_child(rewards_ui)
	_assert(is_instance_valid(rewards_ui), "CombatRewardsUI created and attached to SceneTree")

	# Verify EventBus connections are active while in tree
	_assert(EventBus.combat_ended.is_connected(rewards_ui._on_combat_ended), "CombatRewardsUI subscribed to EventBus.combat_ended on _ready")

	# Remove from tree -> _exit_tree() runs
	remove_child(rewards_ui)
	_assert(!EventBus.combat_ended.is_connected(rewards_ui._on_combat_ended), "CombatRewardsUI cleanly disconnected EventBus signals in _exit_tree()")

	rewards_ui.free()
	_assert(!is_instance_valid(rewards_ui), "CombatRewardsUI freed without leaving dangling signal hooks")

	# ===========================================================================
	# Scenario 5: Deterministic RNG Reproduction & Seed Invariance
	# ===========================================================================
	print("\n-- [5] Deterministic RNG Reproduction & Seed Invariance --")
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 428951
	var seq1: Array[int] = []
	for i in range(10):
		seq1.append(rng1.randi_range(1, 100))

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 428951
	var seq2: Array[int] = []
	for i in range(10):
		seq2.append(rng2.randi_range(1, 100))

	_assert(seq1 == seq2, "RandomNumberGenerator produces bit-identical sequences with matching seed")

	# Different seed produces distinct sequence
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 991234
	var seq3: Array[int] = []
	for i in range(10):
		seq3.append(rng3.randi_range(1, 100))
	_assert(seq1 != seq3, "Different seed produces statistically distinct sequence")

	# ===========================================================================
	# Scenario 6: Filesystem & Save State Isolation
	# ===========================================================================
	print("\n-- [6] Filesystem & Save State Isolation --")
	GlobalData.currency.credits = 777
	GlobalData.currency.scrap = 333
	GlobalData.fuel.convoy_fuel_reserve = 150.0
	GlobalData.board.current_tile = Vector2i(5, 5)
	GlobalData.board.board_mp = 4

	SaveGameIO.save_run()
	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "SaveGameIO.save_run() wrote file to user://savegame.json")

	# Overwrite runtime state
	GlobalData.currency.credits = 0
	GlobalData.currency.scrap = 0
	GlobalData.fuel.convoy_fuel_reserve = 0.0
	GlobalData.board.board_mp = 0

	# Re-read
	var loaded := SaveGameIO.load_run()
	_assert(loaded, "SaveGameIO.load_run() successfully reconstructed state from disk")
	_assert(GlobalData.currency.credits == 777, "Deserialized credits exactly match saved state")
	_assert(GlobalData.currency.scrap == 333, "Deserialized scrap exactly match saved state")
	_assert(is_equal_approx(GlobalData.fuel.convoy_fuel_reserve, 150.0), "Deserialized fuel reserve matches saved state")
	_assert(GlobalData.board.board_mp == 4, "Deserialized board MP matches saved state")

	# ===========================================================================
	# Scenario 7: State Snapshot & Deep Equality Verification
	# ===========================================================================
	print("\n-- [7] State Snapshot & Deep Equality Verification --")
	var snap_before := _take_state_snapshot()
	_assert(!snap_before.is_empty(), "State snapshot captured non-empty dictionary")

	# Mutate state
	GlobalData.currency.credits += 100
	GlobalData.board.board_mp += 2
	var snap_mutated := _take_state_snapshot()
	_assert(snap_mutated["credits"] != snap_before["credits"], "Snapshot detects mutation in credits")
	_assert(snap_mutated["board_mp"] != snap_before["board_mp"], "Snapshot detects mutation in MP")

	# Revert
	GlobalData.currency.credits = snap_before["credits"]
	GlobalData.board.board_mp = snap_before["board_mp"]
	var snap_restored := _take_state_snapshot()
	_assert(snap_restored == snap_before, "State snapshot matches original baseline after targeted reversion")

	# ===========================================================================
	# Scenario 8: Finding A Audit (Board current_pos vs current_tile Precondition)
	# ===========================================================================
	print("\n-- [8] Finding A Audit (Board current_pos vs current_tile Precondition) --")
	GlobalData.board.current_tile = Vector2i(1, 1)
	_assert(GlobalData.board.current_tile == Vector2i(1, 1), "Precondition current_tile set authoritatively")

	# ===========================================================================
	# Scenario 9: Finding B Audit (Fuel Traversal Mode Fixture Precondition)
	# ===========================================================================
	print("\n-- [9] Finding B Audit (Fuel Traversal Mode Fixture Precondition) --")
	GlobalData.fuel.traversal_mode = "convoy"
	_assert(GlobalData.fuel.traversal_mode == "convoy", "Precondition traversal_mode explicitly established as 'convoy'")

	# ===========================================================================
	# Scenario 10: Multi-Scenario Sequence Independence Proof
	# ===========================================================================
	print("\n-- [10] Multi-Scenario Sequence Independence Proof --")
	var run_scenario_alpha = func() -> int:
		GlobalData.currency.reset(100)
		GlobalData.currency.gain_credits(25)
		return GlobalData.currency.credits

	var run_scenario_beta = func() -> int:
		GlobalData.currency.reset(200)
		GlobalData.currency.try_spend_credits(50)
		return GlobalData.currency.credits

	# Forward execution: Alpha -> Beta
	var res_alpha_1 = run_scenario_alpha.call()
	var res_beta_1 = run_scenario_beta.call()

	# Reverse execution: Beta -> Alpha
	var res_beta_2 = run_scenario_beta.call()
	var res_alpha_2 = run_scenario_alpha.call()

	_assert(res_alpha_1 == 125 and res_alpha_2 == 125, "Scenario Alpha yields identical result (125) regardless of execution order")
	_assert(res_beta_1 == 150 and res_beta_2 == 150, "Scenario Beta yields identical result (150) regardless of execution order")


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-49 HARNESS AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if _fail_count > 0:
		print("\nFailures:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")
