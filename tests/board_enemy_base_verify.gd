extends Node

## Headless verification of the enemy base's 3D model lifecycle on the board:
##   - a freshly planted base is a temporary camp (triangular tent model)
##   - once its research has rooted in (>= half done) the model upgrades to a
##     tall fortified building (boxes/prisms only, never cylinders)
##   - an ACTIVE base survives a board reload (tile type + model restored)
##   - a destroyed/completed base leaves no model behind
## Run: godot --headless --path . res://tests/board_enemy_base_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("BASE OK: " + name)
	else:
		_fails += 1
		printerr("BASE FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.current_sector = 1
	GlobalData.board_seed = 999
	GlobalData.board_objective_intro_consumed = true
	GameManager.current_state = GameManager.State.BOARD

	var board = load("res://scenes/board/game_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	var pos := Vector2i(-1, -1)
	for key in board.nodes_dict:
		if str(board.nodes_dict[key].get_meta("tile_type", "empty")) == "empty":
			pos = key
			break
	_check(pos != Vector2i(-1, -1), "found a tile for the enemy base")
	var tile = board.nodes_dict[pos]

	# A freshly planted base (progress 0) is a temporary camp — a tent prism.
	GlobalData.enemy_base_active = true
	GlobalData.enemy_base_progress = 0.0
	GlobalData.enemy_base_required = 8.0
	GlobalData.enemy_base_tile_pos = pos
	tile.set_meta("tile_type", "enemy_base")
	board._refresh_enemy_base_model()
	_check(tile._enemy_base_model != null, "active base gets a 3D model on its tile")
	_check(_has_prism(tile._enemy_base_model), "a fresh base is a temporary camp (triangular tent)")

	# Rooting in (>= half the research done) upgrades it to a tall building.
	GlobalData.enemy_base_progress = 6.0
	board._refresh_enemy_base_model()
	_check(not _has_prism(tile._enemy_base_model), "rooted base upgrades from tent to fortified building")
	var mesh_count := _mesh_count(tile._enemy_base_model)
	_check(mesh_count >= 5, "rooted building is multi-storey (%d meshes)" % mesh_count)

	# Simulate a board reload: the regenerated tile loses its base marking.
	tile.set_meta("tile_type", "empty")
	tile.clear_enemy_base_model()
	board._restore_enemy_base_tile()
	board._refresh_enemy_base_model()
	_check(str(tile.get_meta("tile_type", "empty")) == "enemy_base", "active base tile survives a board reload")
	_check(tile._enemy_base_model != null, "active base model is restored after reload")
	# Rooted base (still >= half) keeps the tower, not the tent.
	_check(not _has_prism(tile._enemy_base_model), "restored base stays a fortified building, not a tent")

	# Destroying/completing the base removes the model and reverts the tile.
	GlobalData.enemy_base_active = false
	GlobalData.enemy_base_tile_pos = pos
	GlobalData.pending_enemy_base_tile_reset = pos
	board._clear_enemy_base_tile()
	_check(tile._enemy_base_model == null, "destroyed base leaves no model behind")
	_check(str(tile.get_meta("tile_type", "empty")) == "empty", "destroyed base tile reverts to ordinary ground")

	print("BOARD_ENEMY_BASE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _has_prism(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh is PrismMesh:
		return true
	for child in node.get_children():
		if _has_prism(child):
			return true
	return false


func _mesh_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _mesh_count(child)
	return count
