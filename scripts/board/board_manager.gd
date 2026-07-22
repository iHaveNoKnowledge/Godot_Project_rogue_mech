extends Node3D

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: MeshInstance3D = $PlayerToken

var current_pos: Vector2i = Vector2i.ZERO
var board: Array = []


func _ready() -> void:
	var generator = get_node_or_null("BoardGenerator")
	if generator:
		board = generator.generate_board()
		for row in board:
			for tile in row:
				tile_container.add_child(tile)
	current_pos = GlobalData.current_tile
	_update_token_position()
	_highlight_adjacent()


func move_to_tile(target: Vector2i) -> bool:
	if not _is_adjacent(current_pos, target):
		return false
	if not _is_in_bounds(target):
		return false
	current_pos = target
	GlobalData.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()
	var tile_data = board[target.y][target.x]
	var tile_type = tile_data.get_meta("tile_type", "empty")
	EventBus.tile_entered.emit(target, tile_data)
	_process_tile_effect(tile_type)
	return true


func _process_tile_effect(tile_type: String) -> void:
	match tile_type:
		"combat":
			GameManager.enter_combat()
		"event":
			pass
		"safehouse":
			GameManager.enter_safehouse()
		_:
			pass


func _update_token_position() -> void:
	player_token.position = Vector3(current_pos.x * 2.5, 0.5, current_pos.y * 2.5)


func _highlight_adjacent() -> void:
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in directions:
		var pos = current_pos + dir
		if _is_in_bounds(pos):
			var tile = board[pos.y][pos.x]
			tile.highlight(true)


func _clear_highlights() -> void:
	for row in board:
		for tile in row:
			tile.highlight(false)


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < board.size() and pos.y >= 0 and pos.y < board[0].size()
