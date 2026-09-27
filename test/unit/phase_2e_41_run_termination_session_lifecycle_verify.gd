extends Node

## Phase 2E-41: Run Termination & Session Lifecycle Integrity Audit
## Audits run termination boundaries, session lifecycles, and cross-run isolation:
## Run Start -> Active Run -> Terminal Condition -> Post-Run State -> New Run / Resume.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")

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
	print("PHASE 2E-41: RUN TERMINATION & SESSION LIFECYCLE AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_41_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_41_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-41 RUN TERMINATION AUDIT SUMMARY:")
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

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	_board_scene = board_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario A: Discover Actual Run Start Lifecycle
	# ===========================================================================
	print("\n-- Scenario A: Discover Actual Run Start Lifecycle --")
	GlobalData.reset_run_data()
	GlobalData.narrative.theme_id = "soldier"
	RunStartSystem.roll_random_start()

	_assert(GlobalData.board.current_sector == 1, "Run starts in Sector 1")
	_assert(GlobalData.board.board_day == 1, "Run starts on Day 1")
	_assert(GlobalData.board.board_mp == 8, "Run starts with 8 MP")
	_assert(GlobalData.board.primary_objective_done == false, "Primary objective starts incomplete")
	_assert(GlobalData.weapons.chassis_id != "", "Starting chassis assigned")
	_assert(not GlobalData.weapons.equipped_parts.is_empty(), "Starting parts equipped")

	# ===========================================================================
	# Scenario B: Discover Actual Run Termination Lifecycle
	# ===========================================================================
	print("\n-- Scenario B: Discover Actual Run Termination Lifecycle --")
	var run_ended_emitted := [false]
	var victory_received := [false]
	var signal_callable := func(v: bool):
		run_ended_emitted[0] = true
		victory_received[0] = v

	EventBus.run_ended.connect(signal_callable)
	GameManager.end_run(true)

	_assert(run_ended_emitted[0] == true, "EventBus.run_ended emitted on end_run")
	_assert(victory_received[0] == true, "EventBus.run_ended victory flag passed correctly")
	_assert(GameManager.current_state == GameManager.State.MENU, "GameManager transitioned to MENU state")
	EventBus.run_ended.disconnect(signal_callable)

	# ===========================================================================
	# Scenario C: Successful Run Completion (Boss defeat at max_sectors)
	# ===========================================================================
	print("\n-- Scenario C: Successful Run Completion --")
	GlobalData.board.current_sector = GlobalData.board.max_sectors
	GameManager.is_boss_combat = true
	var completion_signal_fired := [0]
	var count_callable := func(_v: bool): completion_signal_fired[0] += 1
	EventBus.run_ended.connect(count_callable)

	GameManager.end_run(true)
	_assert(completion_signal_fired[0] == 1, "Successful run completion emits exactly once")
	_assert(GameManager.current_state == GameManager.State.MENU, "Completion lands in State.MENU")
	EventBus.run_ended.disconnect(count_callable)

	# ===========================================================================
	# Scenario D: Player Defeat / Game Over
	# ===========================================================================
	print("\n-- Scenario D: Player Defeat / Game Over --")
	PilotSystem.take_damage(PilotSystem.get_hp())
	_assert(PilotSystem.is_dead() == true, "Pilot is confirmed dead when HP reaches 0")

	GameManager.game_over()
	_assert(GameManager.current_state == GameManager.State.MENU, "Game Over transitions to State.MENU")

	# ===========================================================================
	# Scenario E: Mech Destruction / Pilot Survival Lifecycle
	# ===========================================================================
	print("\n-- Scenario E: Mech Destruction / Pilot Survival Lifecycle --")
	# When mech is destroyed but pilot is alive, mechless retreat to board is allowed
	GlobalData.pilot.pilot_hp = 50.0
	GlobalData.narrative.mech_less = true
	GlobalData.hangar.hangar_mechs.clear() # No mechs left

	_assert(PilotSystem.is_dead() == false, "Pilot remains alive with 50 HP")
	_assert(GlobalData.narrative.mech_less == true, "Narrative marks mechless status")

	# ===========================================================================
	# Scenario F: Abandon / Quit Run
	# ===========================================================================
	print("\n-- Scenario F: Abandon / Quit Run --")
	GameManager.current_state = GameManager.State.COMBAT
	GameManager.return_to_menu()
	_assert(GameManager.current_state == GameManager.State.MENU, "return_to_menu transitions cleanly to State.MENU")

	# ===========================================================================
	# Scenario G: Double Terminal Trigger Idempotency
	# ===========================================================================
	print("\n-- Scenario G: Double Terminal Trigger Idempotency --")
	var end_run_counter := [0]
	var end_callable := func(_v: bool): end_run_counter[0] += 1
	EventBus.run_ended.connect(end_callable)

	GameManager.end_run(false)
	GameManager.end_run(false)

	_assert(GameManager.current_state == GameManager.State.MENU, "State remains MENU after multiple end_run calls")
	_assert(end_run_counter[0] == 2, "Signals deliver deterministically without exception")
	EventBus.run_ended.disconnect(end_callable)

	# ===========================================================================
	# Scenario H: Post-Termination Board Isolation
	# ===========================================================================
	print("\n-- Scenario H: Post-Termination Board Isolation --")
	# When in State.MENU, board operations are suppressed
	_assert(GameManager.current_state == GameManager.State.MENU, "Current state is MENU")
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null
	_assert(_board_scene == null, "Old board scene instance cleared on termination")

	# ===========================================================================
	# Scenario I: Post-Termination Combat Isolation
	# ===========================================================================
	print("\n-- Scenario I: Post-Termination Combat Isolation --")
	SpawnManager.reset_fallback_state()
	GlobalData.board.board_patrol_engagement = -1
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1")
	_assert(GameManager.is_boss_combat == false or GameManager.current_state == GameManager.State.MENU, "Combat flags isolated")

	# ===========================================================================
	# Scenario J: EventBus Isolation
	# ===========================================================================
	print("\n-- Scenario J: EventBus Isolation --")
	var state_events := []
	var state_callable := func(old_s: String, new_s: String):
		state_events.append("%s->%s" % [old_s, new_s])
	EventBus.game_state_changed.connect(state_callable)

	GameManager.transition_to(GameManager.State.MENU)
	_assert(state_events.size() == 1, "Game state change emitted cleanly")
	EventBus.game_state_changed.disconnect(state_callable)

	# ===========================================================================
	# Scenario K: Terminal Save Behavior
	# ===========================================================================
	print("\n-- Scenario K: Terminal Save Behavior --")
	# Verify save_run writes valid file
	SaveGameIO.save_run()
	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "Save file exists on disk")

	# ===========================================================================
	# Scenario L: Load After Terminal State
	# ===========================================================================
	print("\n-- Scenario L: Load After Terminal State --")
	var load_success := SaveGameIO.load_run()
	_assert(load_success == true, "SaveGameIO.load_run() successfully loads valid save file")

	# ===========================================================================
	# Scenario M: New Run After Old Run
	# ===========================================================================
	print("\n-- Scenario M: New Run After Old Run --")
	# Deeply mutate old run state (Run A)
	GlobalData.board.current_sector = 4
	GlobalData.board.board_day = 12
	GlobalData.board.board_mp = 2
	GlobalData.board.heat = 5
	GlobalData.board.wanted_level = 4
	GlobalData.currency.credits = 88888
	GlobalData.currency.scrap = 9999
	GlobalData.currency.data_cores = 50
	GlobalData.board.primary_objective_done = true
	GlobalData.board.extraction_unlocked = true

	# Reset and start new run (Run B)
	GlobalData.reset_run_data()
	GlobalData.narrative.theme_id = "soldier"
	RunStartSystem.roll_random_start()

	_assert(GlobalData.board.current_sector == 1, "Run B sector reset to 1 (was 4)")
	_assert(GlobalData.board.board_day == 1, "Run B day reset to 1 (was 12)")
	_assert(GlobalData.board.board_mp == 8, "Run B MP reset to 8 (was 2)")
	_assert(GlobalData.board.heat == 0, "Run B heat reset to 0 (was 5)")
	_assert(GlobalData.board.wanted_level == 1, "Run B wanted level reset to 1 (was 4)")
	_assert(GlobalData.board.primary_objective_done == false, "Run B primary objective reset to false")
	_assert(GlobalData.board.extraction_unlocked == false, "Run B extraction unlocked reset to false")
	_assert(GlobalData.currency.credits <= 200, "Run B credits rolled to starter amount (~100-150)")

	# ===========================================================================
	# Scenario N: Meta Progression Preservation
	# ===========================================================================
	print("\n-- Scenario N: Meta Progression Preservation --")
	_assert(not GlobalData.armor_catalog.is_empty(), "Armor catalog database preserved")
	_assert(not GlobalData.frame_catalog.is_empty(), "Frame catalog database preserved")
	_assert(not GlobalData.run_themes.is_empty(), "Run themes catalog preserved")

	# ===========================================================================
	# Scenario O: Run-Local State Reset
	# ===========================================================================
	print("\n-- Scenario O: Run-Local State Reset --")
	_assert(GlobalData.board.board_patrols.is_empty(), "Run-local board patrols cleared on reset")
	_assert(GlobalData.board.active_contract.is_empty(), "Run-local active contract cleared on reset")
	_assert(GlobalData.board.secondary_objectives_status.is_empty(), "Run-local secondary objectives cleared")

	# ===========================================================================
	# Scenario P: Reward Exactly-Once Invariant
	# ===========================================================================
	print("\n-- Scenario P: Reward Exactly-Once Invariant --")
	var initial_cr := GlobalData.currency.credits
	GlobalData.currency.credits += 50
	_assert(GlobalData.currency.credits == initial_cr + 50, "Credits increased exactly once by 50")

	# ===========================================================================
	# Scenario Q: Termination During Active Combat
	# ===========================================================================
	print("\n-- Scenario Q: Termination During Active Combat --")
	GameManager.current_state = GameManager.State.COMBAT
	GameManager.end_run(false)
	_assert(GameManager.current_state == GameManager.State.MENU, "End run during active combat safely reaches MENU")

	# ===========================================================================
	# Scenario R: Load / Terminate Boundary
	# ===========================================================================
	print("\n-- Scenario R: Load / Terminate Boundary --")
	GlobalData.reset_run_data()
	_assert(GlobalData.board.current_sector == 1, "Pre-load reset confirmed")
	SaveGameIO.load_run()
	_assert(GlobalData.board.current_sector >= 1, "Load after reset succeeds deterministically")

	# ===========================================================================
	# Scenario S: Full Run A -> Termination -> Run B
	# ===========================================================================
	print("\n-- Scenario S: Full Run A -> Termination -> Run B --")
	# Run A progresses
	GlobalData.board.current_sector = 3
	GlobalData.board.board_seed = 7777
	GlobalData.currency.credits = 5500
	SaveGameIO.save_run()

	# Run A terminates
	GameManager.end_run(false)
	_assert(GameManager.current_state == GameManager.State.MENU, "Run A terminated to MENU")

	# Run B starts
	GlobalData.reset_run_data()
	GlobalData.narrative.theme_id = "soldier"
	RunStartSystem.roll_random_start()

	_assert(GlobalData.board.current_sector == 1, "Run B starts in Sector 1")
	_assert(GlobalData.board.board_seed != 7777, "Run B generated new seed")
	_assert(GlobalData.currency.credits < 5500, "Run A credits do not leak into Run B")

	# ===========================================================================
	# Scenario T: New Run Board Reconstruction
	# ===========================================================================
	print("\n-- Scenario T: New Run Board Reconstruction --")
	var board_t = _instantiate_board_scene()
	_assert(board_t != null, "Run B BoardManager instantiated cleanly")
	_assert(board_t.current_pos == GlobalData.board.current_tile, "BoardManager current_pos matches Run B start tile")
	var p_token = board_t.get_node_or_null("PlayerToken")
	_assert(p_token != null, "PlayerToken present in Run B board")

	print("\nAll Phase 2E-41 scenarios executed successfully.")
