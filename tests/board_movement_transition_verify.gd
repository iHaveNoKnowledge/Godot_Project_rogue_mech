extends Node

## Verifies Board Movement Transitions and Animations:
##   1. Synchronous step & path execution.
##   2. Hopping arc and smooth position interpolation.
##   3. Tactical landing ripples & path trail markers.
##   4. Input & movement locking guards.

var _checks := 0
var _fails := 0

func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running board_movement_transition_verify ---")
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.reset_run_data()
	GlobalData.board.board_mp = 10
	GlobalData.fuel.convoy_fuel = 500.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0

	var bm_scene = preload("res://scenes/board/game_board.tscn")
	var bm = bm_scene.instantiate()
	add_child(bm)
	await get_tree().process_frame

	bm.visible = true
	get_tree().paused = false
	var inter_ui = bm.get_node_or_null("IntermissionUI")
	if inter_ui:
		inter_ui.visible = false
		if inter_ui.has_node("Root"):
			inter_ui.get_node("Root").visible = false

	# Ensure tiles exist
	_check(bm.nodes_dict.size() > 0, "board generated nodes successfully")
	_check(bm.player_token != null, "player token exists on board")

	# Test 1: Synchronous multi-tile movement
	var start_pos: Vector2i = bm.current_pos
	var target_pos: Vector2i = start_pos
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var candidate = start_pos + d
		if bm.nodes_dict.has(candidate):
			var terr = str(bm.nodes_dict[candidate].get_meta("terrain", "plain"))
			if BoardConfig.is_passable(terr):
				target_pos = candidate
				bm.nodes_dict[candidate].set_meta("tile_type", "empty")
				break

	_check(target_pos != start_pos, "found valid adjacent passable target tile %s" % str(target_pos))
	var moved = bm.move_to_tile(target_pos, false)
	_check(moved, "synchronous move_to_tile succeeded")
	_check(bm.current_pos == target_pos, "player current_pos updated to target tile")

	# Test 2: Token smooth step animation execution
	var next_pos: Vector2i = target_pos
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var candidate = target_pos + d
		if bm.nodes_dict.has(candidate) and candidate != start_pos:
			var terr = str(bm.nodes_dict[candidate].get_meta("terrain", "plain"))
			if BoardConfig.is_passable(terr):
				next_pos = candidate
				bm.nodes_dict[candidate].set_meta("tile_type", "empty")
				break

	if next_pos != target_pos:
		# Call animate step
		await bm._animate_token_step(target_pos, next_pos, 0.05)
		var expected_pos = bm.nodes_dict[next_pos].global_position + Vector3(0, 0.9, 0)
		_check(bm.player_token.global_position.distance_to(expected_pos) < 1.0, "token animated smoothly towards target position")

	# Test 3: Path trail markers creation and cleanup
	var dummy_path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	bm._show_path_trail(dummy_path)
	_check(bm._path_trail_markers.size() > 0, "path trail markers created on planned route")
	bm._clear_path_trail()
	_check(bm._path_trail_markers.size() == 0, "path trail markers cleared")

	# Test 4: Landing ripple visual spawning
	var ripple_target = bm.nodes_dict[target_pos].global_position
	bm._spawn_step_ripple(ripple_target)
	var found_ripple := false
	for child in bm.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh:
			found_ripple = true
			break
	_check(found_ripple, "step landing ripple mesh spawned on tile")

	# Test 5: Movement guard rejects input during moving
	bm._is_moving = true
	var rejected = bm.move_to_tile(start_pos, false)
	_check(not rejected, "move_to_tile rejected when _is_moving is true")
	bm._is_moving = false

	print("BOARD_TRANSITION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	bm.queue_free()
	get_tree().quit(1 if _fails > 0 else 0)
