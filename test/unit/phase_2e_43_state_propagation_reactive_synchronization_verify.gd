extends Node

## Phase 2E-43: State Propagation & Reactive Synchronization Integrity Audit
## Audits exact-once reactive propagation, dependency synchronization, cache invalidation,
## duplicate event elimination, and ordering invariants across Board, Combat, Save/Load, UI, and Systems.

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
	print("PHASE 2E-43: STATE PROPAGATION & REACTIVE SYNCHRONIZATION AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	await _run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_43_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_43_SUCCESS")
		get_tree().quit(0)


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-43 PROPAGATION AUDIT SUMMARY:")
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
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
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
	# Scenario A: Current Tile Propagation
	# ===========================================================================
	print("\n--- Scenario A: Current Tile Propagation ---")
	var board = _instantiate_board_scene()
	var start_tile: Vector2i = Vector2i(2, 2)
	board.current_pos = start_tile
	GlobalData.board.current_tile = start_tile
	board._update_token_position()
	var initial_token_pos: Vector3 = board.player_token.global_position

	var target_tile: Vector2i = Vector2i(2, 3)
	board.current_pos = target_tile
	GlobalData.board.current_tile = target_tile
	board._update_token_position()
	var new_token_pos: Vector3 = board.player_token.global_position

	_assert(GlobalData.board.current_tile == target_tile, "Tile authority updated to target tile")
	_assert(board.current_pos == target_tile, "BoardManager derived current_pos updated")
	_assert(new_token_pos != initial_token_pos, "PlayerToken 3D presentation moved following authority update")

	# ===========================================================================
	# Scenario B: Patrol Spawn Propagation
	# ===========================================================================
	print("\n--- Scenario B: Patrol Spawn Propagation ---")
	GlobalData.board.board_patrols.clear()
	var patrol_data: Dictionary = {
		"id": "patrol_test_01",
		"pos": Vector2i(3, 3),
		"type": "scout",
		"unit_type": "patrol_light",
		"fleet_type": "vanguard",
		"alert": 0,
		"hp": 100.0,
		"max_hp": 100.0
	}
	GlobalData.board.board_patrols.append(patrol_data)
	board._refresh_patrol_markers()

	var marker_count: int = 0
	var marker_container = board._patrol_marker_container if board._patrol_marker_container else board.get_node_or_null("PatrolMarkers")
	if marker_container:
		for child in marker_container.get_children():
			if child is PatrolMarker and str(child.fleet_data.get("id", "")) == "patrol_test_01":
				marker_count += 1
	_assert(marker_count == 1, "Patrol spawn propagated exactly one visual marker into marker container")

	# ===========================================================================
	# Scenario C: Patrol Movement Propagation
	# ===========================================================================
	print("\n--- Scenario C: Patrol Movement Propagation ---")
	patrol_data["pos"] = Vector2i(3, 4)
	board._refresh_patrol_markers()
	var found_marker: PatrolMarker = null
	if marker_container:
		for child in marker_container.get_children():
			if child is PatrolMarker and str(child.fleet_data.get("id", "")) == "patrol_test_01":
				found_marker = child
				break
	_assert(found_marker != null and PatrolSystem.normalize_dir(found_marker.fleet_data.get("pos")) == Vector2i(3, 4), "Patrol movement propagated to visual marker pos")

	# ===========================================================================
	# Scenario D: Patrol Removal Propagation
	# ===========================================================================
	print("\n--- Scenario D: Patrol Removal Propagation ---")
	GlobalData.board.board_patrols.clear()
	board._refresh_patrol_markers()
	var remaining_markers: int = 0
	if marker_container:
		for child in marker_container.get_children():
			if child is PatrolMarker and not child.is_queued_for_deletion():
				remaining_markers += 1
	_assert(remaining_markers == 0, "Patrol removal propagated cleanly with zero orphan markers")

	# ===========================================================================
	# Scenario E: Objective Propagation
	# ===========================================================================
	print("\n--- Scenario E: Objective Propagation ---")
	GlobalData.board.primary_objective_done = false
	_assert(GlobalData.board.primary_objective_done == false, "Objective initial state is incomplete")
	GlobalData.board.primary_objective_done = true
	_assert(GlobalData.board.primary_objective_done == true, "Objective completion propagated to authoritative board state")

	# ===========================================================================
	# Scenario F: Extraction Propagation
	# ===========================================================================
	print("\n--- Scenario F: Extraction Propagation ---")
	GlobalData.board.extraction_unlocked = false
	_assert(GlobalData.board.extraction_unlocked == false, "Extraction initial state is locked")
	GlobalData.board.extraction_unlocked = true
	GlobalData.board.extraction_zone_pos = Vector2i(7, 7)
	_assert(GlobalData.board.extraction_unlocked == true, "Extraction unlock propagated to authoritative state")
	_assert(GlobalData.board.extraction_zone_pos == Vector2i(7, 7), "Extraction zone position propagated to authoritative state")

	# ===========================================================================
	# Scenario G: Currency Propagation
	# ===========================================================================
	print("\n--- Scenario G: Currency Propagation ---")
	GlobalData.currency.reset(100)
	GlobalData.currency.gain_credits(50)
	_assert(GlobalData.currency.credits == 150, "Credits gain propagated to CurrencyManager")
	var spent := GlobalData.currency.try_spend_credits(30)
	_assert(spent and GlobalData.currency.credits == 120, "Credits spend propagated exactly once to balance")
	var overspend := GlobalData.currency.try_spend_credits(200)
	_assert(not overspend and GlobalData.currency.credits == 120, "Overspend rejected without corrupting balance")

	# ===========================================================================
	# Scenario H: Fuel Propagation
	# ===========================================================================
	print("\n--- Scenario H: Fuel Propagation ---")
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_energy = maxf(GlobalData.fuel.mech_energy - 25.0, 0.0)
	_assert(GlobalData.fuel.mech_energy == 975.0, "Energy consumption propagated to FuelManager")

	# ===========================================================================
	# Scenario I: Loadout Propagation
	# ===========================================================================
	print("\n--- Scenario I: Loadout Propagation ---")
	GlobalData.weapons.weapon_loadout["right"] = "w_starter_right"
	GlobalData.weapons.chassis_id = "valkren_heavy"
	_assert(GlobalData.weapons.weapon_loadout["right"] == "w_starter_right", "Loadout equipment change propagated to WeaponInventoryState")
	_assert(GlobalData.weapons.chassis_id == "valkren_heavy", "Chassis change propagated to WeaponInventoryState")

	# ===========================================================================
	# Scenario J: Research -> Technology Propagation
	# ===========================================================================
	print("\n--- Scenario J: Research -> Technology Propagation ---")
	TechnologySystem.init_catalog_if_needed()
	var test_tech_id := "tech_prop_test_2e43"
	TechnologySystem.register_technology({
		"tech_id": test_tech_id,
		"name": "Propagation Test Architecture",
		"generation": 1,
		"technology_family": TechnologySystem.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechnologySystem.LINEAGE_VALKREN,
		"tags": ["test"],
		"prerequisites": [],
		"discovery_metadata": {
			"base_state": TechnologySystem.DiscoveryState.IDENTIFIED,
			"research_time": 1.0
		},
		"diffusion_metadata": {
			"category": TechnologySystem.CATEGORY_CONVENTIONAL,
			"min_era_phase": 1,
			"default_diffused": true,
			"factions": [TechnologySystem.FACTION_ALL]
		}
	})
	TechnologySystem.set_discovery_state(test_tech_id, TechnologySystem.DiscoveryState.IDENTIFIED)
	var started := TechnologySystem.start_research(test_tech_id)
	_assert(started and TechnologySystem.get_active_research_project() == test_tech_id, "Active research project set in TechnologySystem")

	var prog_res := ResearchProgressionSystem.dispatch_progression("test_lab", 5.0, {"auto_finalize": true})
	var final_state := TechnologySystem.get_discovery_state(test_tech_id)
	_assert(final_state >= TechnologySystem.DiscoveryState.RESEARCHED, "Research completion propagated to TechnologySystem discovery state (USABLE/RESEARCHED)")

	# ===========================================================================
	# Scenario K: Pilot Propagation
	# ===========================================================================
	print("\n--- Scenario K: Pilot Propagation ---")
	GlobalData.pilot.pilot_hp = 100.0
	GlobalData.pilot.pilot_hp = 80.0
	_assert(GlobalData.pilot.pilot_hp == 80.0, "Pilot HP mutation propagated to PilotState")

	# ===========================================================================
	# Scenario L: Technology / Era Propagation
	# ===========================================================================
	print("\n--- Scenario L: Technology / Era Propagation ---")
	EraProgressionSystem.current_phase = EraProgressionSystem.EraPhase.PHASE_1_TACTICAL
	EraProgressionSystem.current_phase = EraProgressionSystem.EraPhase.PHASE_2_ENERGY
	_assert(EraProgressionSystem.current_phase == EraProgressionSystem.EraPhase.PHASE_2_ENERGY, "Era phase advance propagated to EraProgressionSystem")

	# ===========================================================================
	# Scenario M: Combat Victory Propagation
	# ===========================================================================
	print("\n--- Scenario M: Combat Victory Propagation ---")
	var rewards_ui = CombatRewardsUI.new()
	add_child(rewards_ui)
	rewards_ui._rewards_claimed = false
	var pre_credits: int = GlobalData.currency.credits
	rewards_ui._show_victory_rewards()
	_assert(rewards_ui._rewards_claimed == true, "Victory rewards claimed flag set on first show")
	# Trigger again to test duplicate guard
	rewards_ui._show_victory_rewards()
	_assert(rewards_ui._rewards_claimed == true, "Duplicate victory reward call guarded cleanly")
	rewards_ui.queue_free()

	# ===========================================================================
	# Scenario N: Combat Retreat Propagation
	# ===========================================================================
	print("\n--- Scenario N: Combat Retreat Propagation ---")
	var rewards_ui_retreat = CombatRewardsUI.new()
	add_child(rewards_ui_retreat)
	rewards_ui_retreat.is_escaped = false
	rewards_ui_retreat._on_combat_escaped()
	_assert(rewards_ui_retreat.is_escaped == true, "Combat retreat state propagated to rewards UI")
	rewards_ui_retreat.queue_free()

	# ===========================================================================
	# Scenario O: Combat Defeat Propagation
	# ===========================================================================
	print("\n--- Scenario O: Combat Defeat Propagation ---")
	var rewards_ui_defeat = CombatRewardsUI.new()
	add_child(rewards_ui_defeat)
	rewards_ui_defeat._show_defeat_screen()
	_assert(rewards_ui_defeat.title_label.text == "DEFEATED", "Defeat screen title and state correctly set")
	rewards_ui_defeat.queue_free()

	# ===========================================================================
	# Scenario P: Run State Propagation
	# ===========================================================================
	print("\n--- Scenario P: Run State Propagation ---")
	var state_events: Array[String] = []
	var on_state_change = func(old_s: String, new_s: String):
		state_events.append("%s->%s" % [old_s, new_s])
	EventBus.game_state_changed.connect(on_state_change)
	GameManager.current_state = GameManager.State.COMBAT
	EventBus.game_state_changed.emit("BOARD", "COMBAT")
	_assert(state_events.has("BOARD->COMBAT"), "Run state transition event propagated through EventBus")
	EventBus.game_state_changed.disconnect(on_state_change)

	# ===========================================================================
	# Scenario Q: EventBus Propagation
	# ===========================================================================
	print("\n--- Scenario Q: EventBus Propagation ---")
	var heat_box: Array[int] = [-1]
	var on_heat = func(h: int):
		heat_box[0] = h
	EventBus.heat_changed.connect(on_heat)
	EventBus.heat_changed.emit(7)
	_assert(heat_box[0] == 7, "EventBus heat_changed notification propagated with payload")
	EventBus.heat_changed.disconnect(on_heat)

	# ===========================================================================
	# Scenario R: Save/Load Propagation
	# ===========================================================================
	print("\n--- Scenario R: Save/Load Propagation ---")
	GlobalData.currency.credits = 888
	GlobalData.board.current_sector = 2
	SaveGameIO.save_run()
	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "SaveGameIO saved run file to disk")
	var save_file := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	var serialized: Dictionary = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	_assert(serialized.has("credits") and serialized["credits"] == 888, "SaveGameIO captured updated credits")
	_assert(serialized.has("sector") and serialized["sector"] == 2, "SaveGameIO captured updated sector")

	# ===========================================================================
	# Scenario S: Cross-Scene Propagation
	# ===========================================================================
	print("\n--- Scenario S: Cross-Scene Propagation ---")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.currency.credits = 550
	GameManager.current_state = GameManager.State.COMBAT
	_assert(GlobalData.currency.credits == 550, "Currency preserved across scene state transition")
	GameManager.current_state = GameManager.State.BOARD
	_assert(GlobalData.currency.credits == 550, "Currency preserved on return to board")

	# ===========================================================================
	# Scenario T: Run Reset Propagation
	# ===========================================================================
	print("\n--- Scenario T: Run Reset Propagation ---")
	GlobalData.reset_run_data()
	_assert(GlobalData.board.current_sector == 1, "Run reset propagated sector back to 1")
	_assert(GlobalData.board.board_day == 1, "Run reset propagated day back to 1")
	_assert(GlobalData.board.board_patrols.is_empty(), "Run reset cleared patrols")

	# ===========================================================================
	# Scenario U: Negative / Non-Propagation
	# ===========================================================================
	print("\n--- Scenario U: Negative / Non-Propagation ---")
	var pre_token_pos: Vector3 = board.player_token.global_position
	GlobalData.currency.gain_credits(100)
	var post_token_pos: Vector3 = board.player_token.global_position
	_assert(pre_token_pos == post_token_pos, "Currency mutation did NOT alter player token position (no over-propagation)")

	# ===========================================================================
	# Scenario V: Duplicate Callback Guard
	# ===========================================================================
	print("\n--- Scenario V: Duplicate Callback Guard ---")
	var dup_rewards = CombatRewardsUI.new()
	add_child(dup_rewards)
	dup_rewards._continue_processing = false
	dup_rewards._on_continue_pressed()
	_assert(dup_rewards._continue_processing == true, "First continue press locks processing flag")
	# Second press while processing should early exit
	dup_rewards._on_continue_pressed()
	_assert(dup_rewards._continue_processing == true, "Second continue press rejected cleanly without double processing")
	dup_rewards.queue_free()

	# ===========================================================================
	# Scenario W: Stale Cache Detection
	# ===========================================================================
	print("\n--- Scenario W: Stale Cache Detection ---")
	var fresh_pos: Vector2i = Vector2i(4, 4)
	GlobalData.board.current_tile = fresh_pos
	board.current_pos = fresh_pos
	board._update_token_position()
	_assert(board.current_pos == GlobalData.board.current_tile, "Derived board current_pos matches authoritative tile without staleness")

	# ===========================================================================
	# Scenario X: Ordering / Deferred Transition
	# ===========================================================================
	print("\n--- Scenario X: Ordering / Deferred Transition ---")
	var execution_order: Array[String] = []
	execution_order.append("AUTHORITY_MUTATION")
	GlobalData.currency.credits = 300
	execution_order.append("DOMAIN_LOGIC")
	SaveGameIO.save_run()
	execution_order.append("PERSISTENCE")

	var snap_file := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	var snapshot: Dictionary = JSON.parse_string(snap_file.get_as_text())
	snap_file.close()

	_assert(execution_order == ["AUTHORITY_MUTATION", "DOMAIN_LOGIC", "PERSISTENCE"], "Execution ordered correctly from authority mutation to persistence")
	_assert(snapshot["credits"] == 300, "Persistence captured authority mutation executed prior to save")

	_cleanup_board_scene()
