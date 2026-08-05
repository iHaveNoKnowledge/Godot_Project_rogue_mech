extends Node

@export var num_layers: int = 7
@export var min_nodes_per_layer: int = 2
@export var max_nodes_per_layer: int = 4

var tile_scene: PackedScene = preload("res://scenes/board/board_tile.tscn")


func generate_board() -> Dictionary:
	var nodes_dict: Dictionary = {} # Key: Vector2i(layer, index), Value: Node3D (BoardTile)
	var layer_nodes: Array = [] # Array of Arrays of Vector2i keys

	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board_seed

	# Step 1: Determine structure for each layer
	for l in range(num_layers):
		var count: int = 1
		if l == 0 or l == num_layers - 1:
			count = 1 # Start (Layer 0) and Exit (Last Layer) have exactly 1 node
		else:
			count = rng.randi_range(min_nodes_per_layer, max_nodes_per_layer)

		var current_layer_keys: Array = []
		for i in range(count):
			var key = Vector2i(l, i)
			current_layer_keys.append(key)
		layer_nodes.append(current_layer_keys)

	# Step 2: Determine connections between layer L and L+1
	var connections_dict: Dictionary = {} # Key: Vector2i(layer, index), Value: Array[Vector2i]

	for l in range(num_layers - 1):
		var curr_keys = layer_nodes[l]
		var next_keys = layer_nodes[l + 1]

		# Ensure every node in current layer connects to at least 1 node in next layer
		for key in curr_keys:
			if not connections_dict.has(key):
				connections_dict[key] = []
			
			var target_index = rng.randi() % next_keys.size()
			var target_key = next_keys[target_index]
			if not connections_dict[key].has(target_key):
				connections_dict[key].append(target_key)

		# Ensure every node in next layer has at least 1 incoming connection from current layer
		for n_key in next_keys:
			var has_incoming = false
			for c_key in curr_keys:
				if connections_dict.has(c_key) and connections_dict[c_key].has(n_key):
					has_incoming = true
					break

			if not has_incoming:
				# Pick a random node from current layer and add connection
				var source_key = curr_keys[rng.randi() % curr_keys.size()]
				if not connections_dict.has(source_key):
					connections_dict[source_key] = []
				connections_dict[source_key].append(n_key)

	# Step 3: Instantiate tiles with tile types
	var type_pool = ["combat", "combat", "event", "safehouse", "data_node", "dead_end", "enemy_base"]

	for l in range(num_layers):
		var keys = layer_nodes[l]
		var count = keys.size()

		for i in range(count):
			var key = keys[i]
			var tile_type: String = "empty"

			if l == 0:
				tile_type = "start"
			elif l == num_layers - 1:
				tile_type = "exit"
			elif l == int(num_layers / 2) and i == 0:
				tile_type = "safehouse" # Mid-run guaranteed safehouse
			else:
				tile_type = type_pool[rng.randi() % type_pool.size()]

			var tile_instance = tile_scene.instantiate()
			tile_instance.set_meta("tile_type", tile_type)
			tile_instance.set_meta("grid_pos", key)
			
			# Position in 3D space (X along layer, Z spaced vertically)
			var x_pos = l * 4.0
			var z_offset = (float(i) - float(count - 1) / 2.0) * 3.5
			tile_instance.position = Vector3(x_pos, 0, z_offset)
			
			var connects: Array = connections_dict.get(key, [])
			tile_instance.set_meta("connections", connects)

			nodes_dict[key] = tile_instance

	GlobalData.board_grid = [nodes_dict]
	return {
		"nodes": nodes_dict,
		"layer_nodes": layer_nodes,
		"connections": connections_dict
	}
