extends Node

## Generates an open 2D grid board (free movement, per-cell terrain) instead of
## the old layered branching node graph. A guaranteed main "road" path runs from
## the start (0,0) to the exit, and every walkable cell is reachable from start.

var tile_scene: PackedScene = preload("res://scenes/board/board_tile.tscn")

var grid_size: int = BoardConfig.GRID_SIZE


func generate_board() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board_seed

	var theme_id := BoardConfig.theme_for_sector(GlobalData.current_sector)
	GlobalData.board_theme_id = theme_id

	# Step 1: assign a terrain per cell from the theme's weighted pool.
	var terrain_grid: Dictionary = {} # Vector2i -> String
	for y in range(grid_size):
		for x in range(grid_size):
			terrain_grid[Vector2i(x, y)] = _weighted_terrain(rng, theme_id)

	# Step 2: carve a guaranteed main road from start (0,0) to exit (last,last).
	_main_road(terrain_grid, rng)

	# Step 3: forest/urban get a river band; bridges keep the road passable.
	_carve_water(terrain_grid, theme_id, rng)

	# Step 4: keep only cells reachable from start walkable (flood fill). Cells
	# the player could never reach become rock so the map reads as solid.
	_trim_unreachable(terrain_grid)

	# Step 5: pick content tiles on walkable cells.
	var tile_types := _assign_content(terrain_grid, rng)

	# Step 6: instantiate tiles + compute 4-dir walkable connections.
	var nodes_dict: Dictionary = {}
	for y in range(grid_size):
		for x in range(grid_size):
			var key := Vector2i(x, y)
			var type := str(tile_types.get(key, "empty"))
			var terrain := str(terrain_grid[key])
			var tile_instance := tile_scene.instantiate()
			tile_instance.set_meta("tile_type", type)
			tile_instance.set_meta("grid_pos", key)
			tile_instance.set_meta("terrain", terrain)
			tile_instance.position = Vector3(key.x * 4.0, 0, key.y * 4.0)

			var connects := _neighbor_keys(key)
			connects = connects.filter(func(k: Vector2i) -> bool:
				return BoardConfig.is_passable(terrain_grid.get(k, "rock")))
			tile_instance.set_meta("connections", connects)

			nodes_dict[key] = tile_instance

	GlobalData.board_grid = [nodes_dict]
	return {
		"nodes": nodes_dict,
		"terrain": terrain_grid,
		"tile_types": tile_types,
	}


## Builds a single large ground plane under the whole grid so the board reads
## as one seamless area instead of a grid of separate tile plates. The tiles
## themselves stay flush (flat PlaneMesh) so adjacent terrain merges visually.
func build_ground() -> MeshInstance3D:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(grid_size * 4.0 + 8.0, grid_size * 4.0 + 8.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.11, 0.09)
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = Vector3(grid_size * 2.0, -0.03, grid_size * 2.0)
	return ground


func _weighted_terrain(rng: RandomNumberGenerator, theme_id: String) -> String:
	var pool: Array = BoardConfig.THEME_TERRAIN.get(theme_id, BoardConfig.THEME_TERRAIN["suburb"])
	var total := 0
	for entry in pool:
		total += int(entry[1])
	var roll := rng.randi_range(1, maxi(total, 1))
	for entry in pool:
		roll -= int(entry[1])
		if roll <= 0:
			return str(entry[0])
	return "plain"


func _main_road(terrain_grid: Dictionary, rng: RandomNumberGenerator) -> void:
	var cur := Vector2i(0, 0)
	var goal := Vector2i(grid_size - 1, grid_size - 1)
	terrain_grid[cur] = "road"
	var guard := 0
	while cur != goal and guard < grid_size * grid_size * 2:
		guard += 1
		var dx := goal.x - cur.x
		var dy := goal.y - cur.y
		var horiz := rng.randf() < 0.5
		if absi(dx) < absi(dy):
			horiz = false
		elif absi(dy) < absi(dx):
			horiz = true
		var step: Vector2i
		if horiz and dx != 0:
			step = Vector2i(signi(dx), 0)
		elif dy != 0:
			step = Vector2i(0, signi(dy))
		else:
			step = Vector2i(signi(dx), 0)
		cur += step
		if terrain_grid.has(cur):
			terrain_grid[cur] = "road"


func _carve_water(terrain_grid: Dictionary, theme_id: String, rng: RandomNumberGenerator) -> void:
	if theme_id not in ["forest", "urban"]:
		return
	var river_row := rng.randi_range(3, grid_size - 4)
	for x in range(grid_size):
		var key := Vector2i(x, river_row)
		if terrain_grid.get(key, "road") == "road":
			# The main road keeps a bridge crossing here.
			terrain_grid[key] = "bridge"
		else:
			terrain_grid[key] = "water"


func _trim_unreachable(terrain_grid: Dictionary) -> void:
	var visited: Dictionary = {}
	var frontier: Array = [Vector2i(0, 0)]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true
		for n in _neighbor_keys(cur):
			if visited.has(n):
				continue
			if terrain_grid.has(n) and BoardConfig.is_passable(terrain_grid[n]):
				frontier.append(n)
	for key in terrain_grid:
		if not visited.has(key):
			terrain_grid[key] = "rock"


func _assign_content(terrain_grid: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var grid_size_i := grid_size
	var start_key := Vector2i(0, 0)
	var exit_key := Vector2i(grid_size_i - 1, grid_size_i - 1)

	# All non-start/exit walkable cells, in distance-from-start order.
	var walkable: Array = []
	for key in terrain_grid:
		if key == start_key or key == exit_key:
			continue
		if BoardConfig.is_passable(terrain_grid[key]):
			walkable.append(key)
	walkable.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x + a.y) < (b.x + b.y))

	var result: Dictionary = {}
	result[start_key] = "start"
	result[exit_key] = "exit"

	# A random pool of candidate cells (shuffled) to spread content out. The
	# shuffle uses the board's SEEDED rng so hubs (city/safehouse) and every
	# content tile land on the SAME cells every time the board is visited —
	# returning from a battle never relocates the city or the objective.
	_seeded_shuffle(walkable, rng)

	# Guaranteed hubs near start (safehouse? no — keep start clean) and along
	# the middle/end: safehouse near half-way, city near 2/3.
	var mid := walkable.filter(func(k: Vector2i) -> bool:
		var d := k.x + k.y
		return d >= (grid_size_i - 1) and d <= (grid_size_i + 4))
	var far := walkable.filter(func(k: Vector2i) -> bool:
		var d := k.x + k.y
		return d >= (2 * (grid_size_i - 1)) / 3)
	if mid.is_empty() and not walkable.is_empty():
		mid = [walkable[walkable.size() / 2]]
	if far.is_empty() and not walkable.is_empty():
		far = [walkable[walkable.size() - 1]]
	if not mid.is_empty():
		result[mid[0]] = "safehouse"
	if not far.is_empty():
		result[far[0]] = "city"

	# Scatter content on the rest of the walkable pool.
	for key in walkable:
		if result.has(key):
			continue
		result[key] = _roll_content(rng)

	# Dead ends: any leftover walkable with no walkable neighbor beyond forward.
	return result


# Fisher-Yates shuffle driven by a seeded RandomNumberGenerator, so content
# placement (city/safehouse/events) is deterministic per board seed instead of
# re-rolling every time the board scene is rebuilt after a battle.
func _seeded_shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func _roll_content(rng: RandomNumberGenerator) -> String:
	# Combat NEVER rolls onto plain tiles — battles only happen when the player
	# steps onto a hostile patrol arrow (or a special tile like the enemy
	# research base). Random fights belong to the red ">" fleets you can see
	# moving on the map, not to invisible ground tiles.
	var roll := rng.randf()
	if roll < 0.22:
		return "event"
	elif roll < 0.34:
		return "data_node"
	elif roll < 0.44:
		return "dead_end"
	return "empty"


func _neighbor_keys(key: Vector2i) -> Array:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var result: Array = []
	for d in dirs:
		var n: Vector2i = key + d
		if n.x >= 0 and n.y >= 0 and n.x < grid_size and n.y < grid_size:
			result.append(n)
	return result