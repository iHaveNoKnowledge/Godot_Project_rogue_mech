extends Node3D

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: MeshInstance3D = $PlayerToken

var current_pos: Vector2i = Vector2i.ZERO
var board: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	# Show intermission UI after moving (unless entering combat)
	if tile_type != "combat":
		var intermission = get_node_or_null("IntermissionUI")
		if intermission:
			intermission.visible = true
			intermission.status_label.text = intermission._get_status_text()
	return true


func _process_tile_effect(tile_type: String) -> void:
	match tile_type:
		"combat":
			GameManager.enter_combat()
		"event":
			_trigger_random_event()
		"safehouse":
			var safehouse = get_node_or_null("../SafehouseUI")
			if safehouse:
				safehouse.visible = true
				get_tree().paused = true
		_:
			pass


func _trigger_random_event() -> void:
	var events = [
		{"name": "Abandoned Cache", "effect": "credits", "amount": 50, "desc": "Found an abandoned cache! +50 credits"},
		{"name": "Salvage Parts", "effect": "spare_parts", "amount": 5, "desc": "Found salvage parts! +5 spare parts"},
		{"name": "Ambush", "effect": "damage", "amount": 20, "desc": "Ambushed! Take 20 damage"},
		{"name": "Friendly Trader", "effect": "credits", "amount": 30, "desc": "Met a friendly trader. +30 credits"},
		{"name": "Data Terminal", "effect": "data_cores", "amount": 1, "desc": "Found a data terminal! +1 data core"},
	]
	var event = events[randi() % events.size()]
	EventBus.event_triggered.emit(event)
	# Apply effect
	match event["effect"]:
		"credits":
			GlobalData.credits += event["amount"]
		"spare_parts":
			GlobalData.spare_parts += event["amount"]
		"data_cores":
			GlobalData.data_cores += event["amount"]
		"damage":
			# Apply damage to player
			pass


func get_tile_type(pos: Vector2i) -> String:
	if _is_in_bounds(pos):
		return board[pos.y][pos.x].get_meta("tile_type", "empty")
	return "empty"


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
