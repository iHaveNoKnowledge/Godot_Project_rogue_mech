extends Node

@export var grid_size: Vector2i = Vector2i(8, 8)
@export var combat_ratio: float = 0.35
@export var event_ratio: float = 0.25
@export var safehouse_ratio: float = 0.15
@export var data_node_ratio: float = 0.15
@export var dead_end_ratio: float = 0.10

var tile_scene: PackedScene = preload("res://scenes/board/board_tile.tscn")


func generate_board() -> Array:
	var total_inner_tiles = (grid_size.x * grid_size.y) - 2 # Exclude start (0,0) and exit (7,7)
	
	var combat_count = int(total_inner_tiles * combat_ratio)
	var event_count = int(total_inner_tiles * event_ratio)
	var safehouse_count = int(total_inner_tiles * safehouse_ratio)
	var data_node_count = int(total_inner_tiles * data_node_ratio)
	var dead_end_count = int(total_inner_tiles * dead_end_ratio)
	var empty_count = total_inner_tiles - (combat_count + event_count + safehouse_count + data_node_count + dead_end_count)

	var type_pool: Array = []
	for i in combat_count:
		type_pool.append("combat")
	for i in event_count:
		type_pool.append("event")
	for i in safehouse_count:
		type_pool.append("safehouse")
	for i in data_node_count:
		type_pool.append("data_node")
	for i in dead_end_count:
		type_pool.append("dead_end")
	for i in max(0, empty_count):
		type_pool.append("empty")
	type_pool.shuffle()

	var grid: Array = []
	for y in grid_size.y:
		var row: Array = []
		for x in grid_size.x:
			var tile_type: String = "empty"
			
			# Enforce fixed Start (0,0) and Exit (max_x, max_y)
			if x == 0 and y == 0:
				tile_type = "start"
			elif x == grid_size.x - 1 and y == grid_size.y - 1:
				tile_type = "exit"
			else:
				if not type_pool.is_empty():
					tile_type = type_pool.pop_back()

			var tile_instance = tile_scene.instantiate()
			tile_instance.set_meta("tile_type", tile_type)
			tile_instance.set_meta("grid_pos", Vector2i(x, y))
			tile_instance.position = Vector3(x * 2.5, 0, y * 2.5)
			row.append(tile_instance)
		grid.append(row)

	GlobalData.board_grid = grid
	return grid
