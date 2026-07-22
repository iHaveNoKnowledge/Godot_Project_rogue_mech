extends Node

@export var grid_size: Vector2i = Vector2i(8, 8)
@export var combat_ratio: float = 0.4
@export var event_ratio: float = 0.3
@export var safehouse_ratio: float = 0.15

var tile_scene: PackedScene = preload("res://scenes/board/board_tile.tscn")


func generate_board() -> Array:
	var total_tiles = grid_size.x * grid_size.y
	var combat_count = int(total_tiles * combat_ratio)
	var event_count = int(total_tiles * event_ratio)
	var safehouse_count = int(total_tiles * safehouse_ratio)
	var empty_count = total_tiles - combat_count - event_count - safehouse_count

	var type_pool: Array = []
	for i in combat_count:
		type_pool.append("combat")
	for i in event_count:
		type_pool.append("event")
	for i in safehouse_count:
		type_pool.append("safehouse")
	for i in empty_count:
		type_pool.append("empty")
	type_pool.shuffle()

	var grid: Array = []
	for y in grid_size.y:
		var row: Array = []
		for x in grid_size.x:
			var tile_type = type_pool.pop_back()
			var tile_instance = tile_scene.instantiate()
			tile_instance.set_meta("tile_type", tile_type)
			tile_instance.set_meta("grid_pos", Vector2i(x, y))
			tile_instance.position = Vector3(x * 2.5, 0, y * 2.5)
			row.append(tile_instance)
		grid.append(row)
	GlobalData.board_grid = grid
	return grid
