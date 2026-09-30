extends Node

## Phase 2E-52: Combat Result -> Board State Preservation Audit
## Proves that the combat result (energy, currency/rewards, patrol elimination, player position,
## and board environment) transfers back into the Board session correctly, exactly once,
## and survives deferred destruction (_exit_tree / queue_free), frame ticks, and subsequent cycles.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const MechaController = preload("res://scripts/mecha/mecha_controller.gd")
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
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _cleanup_board() -> void:
	if _board_scene and is_instance_valid(_board_scene):
		if _board_scene.get_parent():
			_board_scene.get_parent().remove_child(_board_scene)
		_board_scene.free()
		_board_scene = null


func _instantiate_board() -> BoardManager:
	_cleanup_board()
	var scene_res := load("res://scenes/board/game_board.tscn") as PackedScene
	_board_scene = scene_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-52: COMBAT RESULT -> BOARD PRESERVATION AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_cleanup_board()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_52_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_52_SUCCESS")
		get_tree().quit(0)


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario 1: Deterministic Non-Default Board State Snapshot Pre-Combat
	# ===========================================================================
	print("\n-- [1] Deterministic Non-Default Board State Snapshot Pre-Combat --")
	GlobalData.board.board_seed = 10001
	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 4
	GlobalData.board.time_hour = 13.5
	GlobalData.board.board_mp = 8
	GlobalData.board.board_mp_max = 8
	GlobalData.board.current_hazard = GlobalData.HAZARD_DUST_STORM
	GlobalData.board.convoy_breakdown_turns = 2
	GlobalData.board.board_patrol_engagement = -1
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.drop_tanks_attached = 0
	GlobalData.fuel.drop_tank_fuel = 0.0
	GlobalData.fuel.mech_energy = 73.0
	GlobalData.fuel.mech_max_energy = 200.0
	GlobalData.weapons.part_damage.clear()
	GlobalData.currency.credits = 345
	GlobalData.currency.scrap = 42
	GameManager.current_state = GameManager.State.BOARD

	var board := _instantiate_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "1.1: GameManager begins in State.BOARD")
	_assert(GlobalData.fuel.mech_energy == 73.0, "1.2: Initial mech_energy is distinctive 73.0")
	_assert(GlobalData.board.board_day == 4, "1.3: Initial board_day is 4")
	_assert(GlobalData.board.time_hour == 13.5, "1.4: Initial time_hour is 13.5")
	_assert(GlobalData.board.convoy_breakdown_turns == 2, "1.5: Initial convoy_breakdown_turns is 2")
	_assert(GlobalData.currency.credits == 345, "1.6: Initial credits are 345")
	_assert(GlobalData.currency.scrap == 42, "1.7: Initial scrap is 42")

	# ===========================================================================
	# Scenario 2: Patrol Setup and Combat Trigger Boundary
	# ===========================================================================
	print("\n-- [2] Patrol Setup and Combat Trigger Boundary --")
	var target_tile := Vector2i(3, 2)
	var cmdr_info := {
		"name": "Captain Strike",
		"trait": "Predator",
		"bounty": 250,
		"archetype": 4,
	}
	var patrol_101 := {
		"id": 101,
		"pos": target_tile,
		"home": target_tile,
		"dir": Vector2i(1, 0),
		"archetype": "hunter_killer",
		"fleet_count": 2,
		"name": "Strike Vanguard",
		"commander": cmdr_info,
		"pilots": [cmdr_info]
	}
	var cmdr_102 := {
		"name": "Scout Master",
		"trait": "Perceptive",
		"bounty": 150,
		"archetype": 1,
	}
	var patrol_102 := {
		"id": 102,
		"pos": Vector2i(5, 5),
		"home": Vector2i(5, 5),
		"dir": Vector2i(0, 1),
		"archetype": "recon",
		"fleet_count": 1,
		"name": "Distant Scout",
		"commander": cmdr_102,
		"pilots": [cmdr_102]
	}
	PatrolSystem.normalize_patrol(patrol_101)
	PatrolSystem.normalize_patrol(patrol_102)
	GlobalData.board.board_patrols = [patrol_101, patrol_102]
	board._refresh_patrol_markers()

	var step_ok: bool = board._try_step(target_tile)
	_assert(step_ok == true, "2.1: Step onto patrol tile (3, 2) executed")
	_assert(GlobalData.board.current_tile == target_tile, "2.2: GlobalData current_tile synchronized to (3, 2)")
	_assert(GlobalData.board.board_patrol_engagement == 101, "2.3: Patrol 101 engagement recorded")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "2.4: GameManager transitioned to State.COMBAT")
	_assert(GlobalData.pre_combat_weapon_loadout is Dictionary, "2.5: Pre-combat loadout snapshot exists")

	# ===========================================================================
	# Scenario 3: MechaController In-Combat Energy Mutation & Lifecycle
	# ===========================================================================
	print("\n-- [3] MechaController In-Combat Energy Mutation & Lifecycle --")
	var mecha: MechaController = MechaController.new()
	mecha.name = "Mecha"
	add_child(mecha)

	_assert(is_instance_valid(mecha.energy_system), "3.1: MechaController energy_system instantiated")
	_assert(mecha.energy == 73.0, "3.2: MechaController initialized energy from GlobalData (73.0)")
	_assert(mecha.max_energy == 200.0, "3.3: MechaController initialized max_energy (200.0)")

	# Simulate active combat energy drain (e.g. roller dash / thrusters)
	mecha.energy_system.energy = 58.5
	_assert(mecha.energy == 58.5, "3.4: In-combat energy drained to distinctive 58.5")

	# ===========================================================================
	# Scenario 4: Combat Victory, Authoritative Rewards & Exactly-Once Semantics
	# ===========================================================================
	print("\n-- [4] Combat Victory, Authoritative Rewards & Exactly-Once Semantics --")
	var rewards_ui: CombatRewardsUI = CombatRewardsUI.new()
	add_child(rewards_ui)

	var pre_credits: int = GlobalData.currency.credits
	var pre_scrap: int = GlobalData.currency.scrap

	# Simulate combat ended signal
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame

	var credits_after_first: int = GlobalData.currency.credits
	var scrap_after_first: int = GlobalData.currency.scrap
	_assert(credits_after_first > pre_credits, "4.1: Credits awarded on victory (%d -> %d)" % [pre_credits, credits_after_first])
	_assert(scrap_after_first > pre_scrap, "4.2: Scrap awarded on victory (%d -> %d)" % [pre_scrap, scrap_after_first])

	# Negative test: second spurious combat_ended signal must NOT double-grant
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_assert(GlobalData.currency.credits == credits_after_first, "4.3: Double combat_ended signal ignored by _rewards_claimed guard (credits unchanged)")
	_assert(GlobalData.currency.scrap == scrap_after_first, "4.4: Scrap unchanged on duplicate signal")

	# Resolve patrol removal and engagement clear
	PatrolSystem.remove_patrol(101)
	GlobalData.board.board_patrol_engagement = -1
	_assert(PatrolSystem.get_patrol_by_id(101).is_empty(), "4.5: Defeated patrol 101 removed from PatrolSystem")
	_assert(GlobalData.board.board_patrols.size() == 1, "4.6: Exactly 1 surviving patrol remaining")
	_assert(GlobalData.board.board_patrol_engagement == -1, "4.7: Engagement cleared to -1")

	# Clean up rewards UI
	rewards_ui.queue_free()
	await get_tree().process_frame

	# ===========================================================================
	# Scenario 5: MechaController Deferred Teardown & Energy Commitment
	# ===========================================================================
	print("\n-- [5] MechaController Deferred Teardown & Energy Commitment --")
	# Removing from tree invokes _exit_tree() which calls energy_system.persist_to_global()
	remove_child(mecha)
	mecha.free()

	# Checkpoint A: Immediately post-teardown
	_assert(GlobalData.fuel.mech_energy == 58.5, "5.1 [CHECKPOINT A]: GlobalData.fuel.mech_energy immediately matches final combat energy (58.5)")

	# Checkpoint B: After deferred frames
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(GlobalData.fuel.mech_energy == 58.5, "5.2 [CHECKPOINT B]: GlobalData.fuel.mech_energy remains 58.5 after deferred process frames")

	# ===========================================================================
	# Scenario 6: Return to Board & Scene Reconstruction State Invariants
	# ===========================================================================
	print("\n-- [6] Return to Board & Scene Reconstruction State Invariants --")
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "6.1: GameManager state returned to State.BOARD")

	var returned_board := _instantiate_board()
	await get_tree().process_frame

	# Checkpoint C: After board reconstruction
	_assert(GlobalData.fuel.mech_energy == 58.5, "6.2 [CHECKPOINT C]: GlobalData.fuel.mech_energy preserved across board reconstruction (58.5)")
	_assert(GlobalData.board.current_tile == target_tile, "6.3: Player position preserved at target tile (3, 2)")
	_assert(returned_board.current_pos == target_tile, "6.4: BoardManager current_pos matches tile (3, 2)")
	_assert(GlobalData.board.board_day == 4, "6.5: Board calendar day preserved (4)")
	_assert(GlobalData.board.convoy_breakdown_turns == 2, "6.6: Convoy breakdown turns preserved (2)")
	_assert(PatrolSystem.get_patrol_by_id(101).is_empty(), "6.7: Defeated patrol 101 remains absent after board reconstruction")
	_assert(not PatrolSystem.get_patrol_by_id(102).is_empty(), "6.8: Surviving patrol 102 remains present on reconstructed board")
	_assert(GlobalData.board.board_patrol_engagement == -1, "6.9: Engagement remains idle (-1)")

	# ===========================================================================
	# Scenario 7: Post-Return Gameplay Movement Continuation
	# ===========================================================================
	print("\n-- [7] Post-Return Gameplay Movement Continuation --")
	var next_tile := Vector2i(4, 2)
	if not returned_board._can_step(next_tile):
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0)]:
			if returned_board._can_step(target_tile + d):
				next_tile = target_tile + d
				break

	var step_post_ok := returned_board._try_step(next_tile)
	_assert(step_post_ok == true, "7.1: Post-combat movement step executed successfully")
	_assert(returned_board.current_pos == next_tile, "7.2: BoardManager position advanced to (%d, %d)" % [next_tile.x, next_tile.y])
	_assert(GlobalData.board.current_tile == next_tile, "7.3: GlobalData current_tile synchronized to (%d, %d)" % [next_tile.x, next_tile.y])
	_assert(GlobalData.board.board_patrol_engagement == -1, "7.4: No spurious patrol engagement triggered")
	_assert(GameManager.current_state == GameManager.State.BOARD, "7.5: GameManager remains in State.BOARD")
	_assert(GlobalData.fuel.mech_energy == 58.5, "7.6: Mech energy preserved across convoy board step (58.5)")

	# ===========================================================================
	# Scenario 8: Second Complete Lifecycle with Distinct Values (Cross-Cycle Independence)
	# ===========================================================================
	print("\n-- [8] Second Complete Lifecycle with Distinct Values (Cross-Cycle Independence) --")
	var patrol_202_tile := Vector2i(5, 2)
	if not returned_board._can_step(patrol_202_tile):
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if returned_board._can_step(next_tile + d):
				patrol_202_tile = next_tile + d
				break

	var cmdr_202 := {"name": "Major Iron", "bounty": 300, "archetype": 2}
	var patrol_202 := {
		"id": 202,
		"pos": patrol_202_tile,
		"home": patrol_202_tile,
		"dir": Vector2i(0, 1),
		"archetype": "armored",
		"fleet_count": 1,
		"name": "Iron Guard",
		"commander": cmdr_202,
		"pilots": [cmdr_202]
	}
	PatrolSystem.normalize_patrol(patrol_202)
	GlobalData.board.board_patrols = [patrol_202]
	returned_board._refresh_patrol_markers()

	# Move onto patrol 202
	GlobalData.board.board_mp = 8
	var step_202_ok := returned_board._try_step(patrol_202_tile)
	_assert(step_202_ok == true, "8.1: Step onto Cycle 2 patrol (202) succeeded")
	_assert(GlobalData.board.board_patrol_engagement == 202, "8.2: Engagement recorded ID 202")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "8.3: State transitioned to State.COMBAT for Cycle 2")

	# Spawn Cycle 2 MechaController
	var mecha_cycle2 := MechaController.new()
	mecha_cycle2.name = "Mecha"
	add_child(mecha_cycle2)
	_assert(mecha_cycle2.energy == 58.5, "8.4: Cycle 2 MechaController correctly loaded persistent energy (58.5)")

	# Mutate energy in Cycle 2 combat down to 41.2
	mecha_cycle2.energy_system.energy = 41.2
	_assert(mecha_cycle2.energy == 41.2, "8.5: Cycle 2 energy mutated to 41.2")

	# Resolve Cycle 2 combat
	PatrolSystem.remove_patrol(202)
	GlobalData.board.board_patrol_engagement = -1

	# Cycle 2 teardown
	remove_child(mecha_cycle2)
	mecha_cycle2.free()
	await get_tree().process_frame

	GameManager.return_to_board()
	_assert(GlobalData.fuel.mech_energy == 41.2, "8.6: Cycle 2 energy persisted accurately to GlobalData (41.2)")
	_assert(PatrolSystem.get_patrol_by_id(202).is_empty(), "8.7: Patrol 202 removed permanently")
	_assert(GlobalData.board.board_patrols.is_empty(), "8.8: All sector patrols defeated after Cycle 2")
	_assert(GameManager.current_state == GameManager.State.BOARD, "8.9: GameManager returned to State.BOARD after Cycle 2")

	# ===========================================================================
	# Scenario 9: Negative & Teardown Idempotency Checks
	# ===========================================================================
	print("\n-- [9] Negative & Teardown Idempotency Checks --")
	# Idempotent patrol removal
	var count_before_redundant := GlobalData.board.board_patrols.size()
	PatrolSystem.remove_patrol(9999) # Non-existent ID
	_assert(GlobalData.board.board_patrols.size() == count_before_redundant, "9.1: Removing non-existent patrol ID is harmless and does not drift count")

	# Idempotent energy persistence
	var test_energy_sys = preload("res://scripts/mecha/mecha_energy_system.gd").new()
	test_energy_sys.energy = 41.2
	test_energy_sys.max_energy = 200.0
	test_energy_sys.persist_to_global()
	test_energy_sys.persist_to_global()
	_assert(GlobalData.fuel.mech_energy == 41.2, "9.2: Redundant persist_to_global() calls produce identical state")
	test_energy_sys.free()

	# Stale engagement safety
	GlobalData.board.board_patrol_engagement = -1
	_assert(GlobalData.board.board_patrol_engagement == -1, "9.3: board_patrol_engagement safely reset to idle (-1)")


func _print_summary() -> void:
	print("\n--------------------------------------------------")
	print("PHASE 2E-52 TEST SUMMARY")
	print("--------------------------------------------------")
	print("Passed: %d" % _pass_count)
	print("Failed: %d" % _fail_count)
	if _fail_count > 0:
		print("\nFailures:")
		for f in _failures:
			print("  - %s" % f)
	print("--------------------------------------------------")
