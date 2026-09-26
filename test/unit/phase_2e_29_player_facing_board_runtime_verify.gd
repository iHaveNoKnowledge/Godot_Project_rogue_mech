extends Node

## Phase 2E-29: Player-Facing Board Runtime & Run UX Verification
## Verifies that authoritative Board/Run state is correctly synchronized to
## the player-facing runtime scene (game_board, BoardManager, BoardHUD, PlayerToken, BoardTile).

var _pass_count: int = 0
var _fail_count: int = 0
var _board_scene: Node3D = null


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-29 PLAYER-FACING BOARD RUNTIME AUDIT ===\n")
	GameManager.suppress_scene_change = true

	await _run_all_tests()

	print("\n==================================================")
	print("PHASE 2E-29 BOARD RUNTIME SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2E_29_SUCCESS\n")
	else:
		push_error("PHASE_2E_29_FAILURE: %d assertions failed" % _fail_count)

	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()

	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _setup_board() -> Node3D:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null

	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = 6
	GlobalData.board.board_mp_max = 6
	GlobalData.board.active_contract = {"name": "Test Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_max_fuel = 100.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	GlobalData.fuel.traversal_mode = "convoy"
	GameManager.current_state = GameManager.State.BOARD
	get_tree().paused = false

	var scene_res = load("res://scenes/board/game_board.tscn")
	_board_scene = scene_res.instantiate()
	add_child(_board_scene)

	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false

	return _board_scene


func _find_adjacent_passable(bm: Node3D, origin: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var candidate = origin + d
		if bm.nodes_dict.has(candidate):
			var tile = bm.nodes_dict[candidate]
			var terrain = str(tile.get_meta("terrain", "plain"))
			if BoardConfig.is_passable(terrain):
				return candidate
	return Vector2i(-1, -1)


func _run_all_tests() -> void:
	var bm = _setup_board()

	# [1] Board Scene Initialization
	print("-- [1] Board Scene Initialization --")
	_assert(bm != null, "game_board.tscn instantiates cleanly")
	_assert(bm.player_token != null, "PlayerToken exists in board scene")
	_assert(bm.get_node_or_null("BoardHUD") != null, "BoardHUD is attached to game_board")
	_assert(bm.get_node_or_null("BoardCamera") != null, "BoardCamera is attached to game_board")
	_assert(bm.nodes_dict.size() > 0, "BoardGenerator generated grid nodes into nodes_dict (%d tiles)" % bm.nodes_dict.size())

	# [2] Current Tile Visual Synchronization
	print("\n-- [2] Current Tile Visual Synchronization --")
	var cur = bm.current_pos
	_assert(bm.nodes_dict.has(cur), "Current position tile (%s) exists in grid" % str(cur))
	var cur_tile = bm.nodes_dict[cur]
	var expected_pos = cur_tile.global_position + Vector3(0, 0.9, 0)
	var pos_match = bm.player_token.global_position.distance_to(expected_pos) < 0.1
	_assert(pos_match, "PlayerToken visually aligns with current_pos tile world coordinates")
	var mode_tag = bm.player_token.get_node_or_null("ModeTag")
	_assert(mode_tag != null and mode_tag is Label3D, "PlayerToken possesses active 3D mode billboard label")

	# [3] Movement Visual Update
	print("\n-- [3] Movement Visual Update --")
	var adj_target = _find_adjacent_passable(bm, cur)
	_assert(adj_target != Vector2i(-1, -1), "Found adjacent passable tile (%s) from current position" % str(adj_target))
	var move_ok = bm.move_to_tile(adj_target, false)
	_assert(move_ok, "move_to_tile step succeeded to %s" % str(adj_target))
	_assert(bm.current_pos == adj_target, "BoardManager current_pos updated to %s" % str(adj_target))
	_assert(GlobalData.board.current_tile == adj_target, "GlobalData.board.current_tile updated to %s" % str(adj_target))
	var new_tile = bm.nodes_dict[adj_target]
	var new_expected = new_tile.global_position + Vector3(0, 0.9, 0)
	var token_moved = bm.player_token.global_position.distance_to(new_expected) < 0.1
	_assert(token_moved, "PlayerToken visually relocated to %s tile world pos" % str(adj_target))

	# [4] Invalid Movement Visual Stability
	print("\n-- [4] Invalid Movement Visual Stability --")
	var pre_token_pos = bm.player_token.global_position
	var pre_grid_pos = bm.current_pos
	GlobalData.board.board_mp = 0
	var invalid_move_target = _find_adjacent_passable(bm, pre_grid_pos)
	var invalid_move_ok = bm.move_to_tile(invalid_move_target, false)
	_assert(not invalid_move_ok, "Movement rejected with 0 MP")
	_assert(bm.current_pos == pre_grid_pos, "BoardManager current_pos remains %s" % str(pre_grid_pos))
	_assert(bm.player_token.global_position == pre_token_pos, "PlayerToken position remained perfectly stable")

	# [5] MP UI Synchronization
	print("\n-- [5] MP UI Synchronization --")
	var hud = bm.get_node("BoardHUD")
	GlobalData.board.board_mp = 4
	GlobalData.board.board_mp_max = 6
	hud._refresh()
	_assert(hud._mp_label.text == "MP 4/6", "HUD MP label text matches authoritative MP (got '%s')" % hud._mp_label.text)
	_assert(hud._mp_bar.value == 4.0, "HUD MP bar value matches authoritative MP (got %f)" % hud._mp_bar.value)
	_assert(hud._mp_bar.max_value == 6.0, "HUD MP bar max_value matches authoritative MP max")

	# [6] Fuel UI Synchronization
	print("\n-- [6] Fuel UI Synchronization --")
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel = 85.0
	GlobalData.fuel.convoy_max_fuel = 100.0
	hud._refresh()
	_assert(hud._energy_label.text.contains("CONVOY FUEL: 85 / 100"), "HUD displays Convoy Fuel: 85 / 100 in Convoy mode")
	_assert(hud._energy_bar.value == 85.0, "HUD Energy Bar value is 85.0")

	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.fuel.mech_energy = 450.0
	GlobalData.fuel.mech_max_energy = 1000.0
	hud._refresh()
	_assert(hud._energy_label.text.contains("MECHA BATTERY: 450 / 1000"), "HUD displays Mecha Battery: 450 / 1000 in Mecha mode")
	_assert(hud._energy_bar.value == 450.0, "HUD Energy Bar value is 450.0")

	GlobalData.fuel.traversal_mode = "pilot"
	GlobalData.fuel.pilot_stamina = 70.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	hud._refresh()
	_assert(hud._energy_label.text.contains("PILOT STAMINA: 70 / 100"), "HUD displays Pilot Stamina: 70 / 100 in Pilot mode")
	_assert(hud._energy_bar.value == 70.0, "HUD Energy Bar value is 70.0")

	# [7] Turn / Day UI Synchronization
	print("\n-- [7] Turn / Day UI Synchronization --")
	GlobalData.board.board_day = 5
	GlobalData.board.board_theme_id = "desert"
	hud._refresh()
	_assert(hud._day_label.text == "DAY 5 — DESERT", "HUD Day label accurately renders 'DAY 5 — DESERT'")

	# [8] Tile State Presentation
	print("\n-- [8] Tile State Presentation --")
	var test_tile_key = bm.nodes_dict.keys()[0]
	var test_tile = bm.nodes_dict[test_tile_key]
	_assert(test_tile != null, "Tile (%s) exists for presentation test" % str(test_tile_key))
	test_tile.highlight(true)
	_assert(test_tile.is_highlighted, "Tile highlight flag active")
	_assert(test_tile.is_revealed, "Tile revealed upon highlight")
	_assert(test_tile._reachable_glow != null and test_tile._reachable_glow.visible, "Tile reachable glow mesh active")
	test_tile.highlight(false)
	_assert(not test_tile.is_highlighted, "Tile highlight flag deactivated cleanly")
	_assert(test_tile._reachable_glow != null and not test_tile._reachable_glow.visible, "Tile reachable glow mesh hidden")

	# [9] Encounter Marker Presentation
	print("\n-- [9] Encounter Marker Presentation --")
	test_tile.set_enemy_base_model("camp")
	_assert(test_tile._enemy_base_model != null and test_tile._enemy_base_model.name == "EnemyBaseModel", "Enemy Base Camp model attached to tile")
	test_tile.set_enemy_base_model("rooted")
	_assert(test_tile._enemy_base_model != null, "Enemy Base Rooted model updated successfully")
	test_tile.clear_enemy_base_model()
	_assert(test_tile._enemy_base_model == null, "Enemy Base model cleared cleanly")

	# [10] Patrol Marker Presentation
	print("\n-- [10] Patrol Marker Presentation --")
	PatrolSystem.spawn_patrols()
	bm._refresh_patrol_markers()
	_assert(bm._patrol_marker_container != null, "PatrolMarker container initialized")
	var marker_count = bm._patrol_marker_container.get_child_count()
	_assert(marker_count > 0, "Rendered 3D patrol markers for active fleets on board (got %d markers)" % marker_count)

	# [11] Wreckage Presentation
	print("\n-- [11] Wreckage Presentation --")
	var wreck_pos = Vector2i(3, 3)
	var weapon = WeaponPart.new()
	weapon.weapon_name = "Autocannon 20mm"
	ScavengerSystem.register_tile_wreckage(wreck_pos, [{"type": "weapon", "weapon": weapon}], 50)
	_assert(ScavengerSystem.has_wreckage_at(wreck_pos), "Wreckage registered at tile %s" % str(wreck_pos))
	var wr_claimed = ScavengerSystem.claim_tile_wreckage(wreck_pos)
	_assert(int(wr_claimed.get("scrap", 0)) == 50, "Claimed exactly 50 scrap from wreckage")
	_assert(not ScavengerSystem.has_wreckage_at(wreck_pos), "Wreckage cleared from tile after claim")

	# [12] Board -> Combat Transition Lock
	print("\n-- [12] Board -> Combat Transition Lock --")
	GlobalData.board.board_mp = 6
	GlobalData.fuel.convoy_fuel = 100.0
	GameManager.enter_combat("grunt")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "Transitioned to State.COMBAT on request")
	var combat_step_ok = bm.move_to_tile(_find_adjacent_passable(bm, bm.current_pos), false)
	_assert(not combat_step_ok, "Board movement strictly rejected while in State.COMBAT")

	# [13] Combat -> Board Return Presentation
	print("\n-- [13] Combat -> Board Return Presentation --")
	GameManager.return_to_board()
	_assert(GameManager.current_state == GameManager.State.BOARD, "GameManager returned to State.BOARD")
	var intermission = bm.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false

	# [14] Victory Return Presentation
	print("\n-- [14] Victory Return Presentation --")
	GlobalData.board.board_patrol_engagement = 205
	GlobalData._on_combat_ended(true)
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement reset to -1 on victory")
	_assert(GameManager.current_state == GameManager.State.BOARD, "State is State.BOARD")

	# [15] Defeat Return Presentation
	print("\n-- [15] Defeat Return Presentation --")
	GlobalData.board.board_patrol_engagement = 206
	GlobalData._on_combat_ended(false)
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement cleared on defeat")
	_assert(GameManager.current_state == GameManager.State.BOARD, "State returned to State.BOARD on defeat")

	# [16] Escape Return Presentation
	print("\n-- [16] Escape Return Presentation --")
	GlobalData.board.board_patrol_engagement = 207
	GameManager.is_escaping = true
	PatrolSystem.resolve_patrol_combat(false)
	GameManager.return_to_board()
	if intermission:
		intermission.visible = false
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement cleared on escape")
	_assert(GameManager.current_state == GameManager.State.BOARD, "State restored to State.BOARD on escape")

	# [17] Save / Load UI Reconstruction
	print("\n-- [17] Save / Load UI Reconstruction --")
	var valid_saved_pos = _find_adjacent_passable(bm, bm.current_pos)
	GlobalData.board.current_tile = valid_saved_pos
	bm.current_pos = valid_saved_pos
	bm._update_token_position()
	GlobalData.board.board_day = 3
	GlobalData.board.board_mp = 5
	SaveGameIO.save_run()
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.board_day = 99
	GlobalData.board.board_mp = 0
	SaveGameIO.load_run()
	bm.current_pos = GlobalData.board.current_tile
	bm._update_token_position()
	_assert(GlobalData.board.current_tile == valid_saved_pos, "Restored board current_tile is %s" % str(valid_saved_pos))
	hud._refresh()
	_assert(hud._mp_label.text.contains("MP 5"), "HUD accurately displays restored MP 5")
	_assert(hud._day_label.text.contains("DAY 3"), "HUD accurately displays restored DAY 3")

	# [18] Board A -> Board B Visual Isolation
	print("\n-- [18] Board A -> Board B Visual Isolation --")
	bm._clear_highlights()
	var any_highlighted := false
	for k in bm.nodes_dict:
		if bm.nodes_dict[k].is_highlighted:
			any_highlighted = true
			break
	_assert(not any_highlighted, "Board A cleared highlights cleanly")
	bm._highlight_adjacent()
	var adj_count := 0
	for k in bm.nodes_dict:
		if bm.nodes_dict[k].is_highlighted:
			adj_count += 1
	_assert(adj_count > 0, "Board B highlighted fresh adjacent tiles (%d tiles)" % adj_count)

	# [19] Modal Input Isolation
	print("\n-- [19] Modal Input Isolation --")
	var event_ui = bm.get_node_or_null("EventUI")
	_assert(event_ui != null, "EventUI modal node exists on game_board")
	get_tree().paused = true
	var paused_step_ok = bm.move_to_tile(_find_adjacent_passable(bm, bm.current_pos), false)
	_assert(not paused_step_ok, "Movement strictly inhibited while SceneTree is paused by modal dialog")
	get_tree().paused = false
	if intermission:
		intermission.visible = false
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.board_mp = 6
	GlobalData.fuel.convoy_fuel = 100.0
	var unpaused_step_target = _find_adjacent_passable(bm, bm.current_pos)
	var unpaused_step_ok = bm.move_to_tile(unpaused_step_target, false)
	_assert(unpaused_step_ok, "Movement permitted after modal is closed and tree unpaused")

	# [20] Full Player-Facing Board Runtime Cycle
	print("\n-- [20] Full Player-Facing Board Runtime Cycle --")
	get_tree().paused = false
	if intermission:
		intermission.visible = false
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.board_mp = 6
	GlobalData.fuel.convoy_fuel = 100.0
	var cycle_start_pos = bm.current_pos
	var cycle_step_target = _find_adjacent_passable(bm, cycle_start_pos)
	var cycle_step_ok = bm.move_to_tile(cycle_step_target, false)
	_assert(cycle_step_ok, "Cycle Step succeeded to %s" % str(cycle_step_target))
	GameManager.enter_combat("grunt")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "Transitioned to State.COMBAT in cycle")
	GlobalData._on_combat_ended(true)
	GameManager.return_to_board()
	if intermission:
		intermission.visible = false
	_assert(GameManager.current_state == GameManager.State.BOARD, "Returned to State.BOARD in cycle")
	_assert(bm.current_pos == cycle_step_target, "Player position preserved at %s after cycle" % str(cycle_step_target))
	hud._refresh()
	_assert(hud._root.visible, "HUD root panel remains visible and responsive after full cycle")
