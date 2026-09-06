extends Node

## Generates an open 2D grid board (free movement, per-cell terrain) instead of
## the old layered branching node graph. A guaranteed main "road" path runs from
## the start (0,0) to the exit, and every walkable cell is reachable from start.

var tile_scene: PackedScene = preload("res://scenes/board/board_tile.tscn")

var grid_size: int = BoardConfig.GRID_SIZE


func generate_board() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board.board_seed

	var theme_id := BoardConfig.theme_for_sector(GlobalData.board.current_sector)
	GlobalData.board.board_theme_id = theme_id

	# Step 1: partition the 2D grid into organic sub-zones (micro-biomes).
	var sub_zone_grid := _generate_sub_zones(theme_id, rng)

	# Step 2: assign terrain per cell based on each cell's sub-zone weighted pool.
	var terrain_grid: Dictionary = {} # Vector2i -> String
	for y in range(grid_size):
		for x in range(grid_size):
			var cell := Vector2i(x, y)
			var sz: String = sub_zone_grid.get(cell, "")
			terrain_grid[cell] = _weighted_terrain_for_sub_zone(rng, sz, theme_id)

	# Step 3: pick dynamic start and exit locations (not fixed to corners)
	var start_key := Vector2i(rng.randi_range(1, 3), rng.randi_range(1, 3))
	var exit_key := Vector2i(grid_size - 1 - rng.randi_range(0, 3), grid_size - 1 - rng.randi_range(0, 3))

	# Step 4: carve a guaranteed main road from start to exit.
	_main_road(terrain_grid, start_key, exit_key, rng)

	# Step 5: forest/urban/water sub-zones get river/water features; bridges keep road passable.
	_carve_water(terrain_grid, theme_id, rng)

	# Step 6: keep only cells reachable from start walkable (flood fill). Cells
	# the player could never reach become rock so the map reads as solid.
	_trim_unreachable(terrain_grid, start_key)

	# Step 7: pick content tiles on walkable cells.
	var tile_types := _assign_content(terrain_grid, start_key, exit_key, rng)

	# Step 8: instantiate tiles + compute 4-dir walkable connections.
	var nodes_dict: Dictionary = {}
	for y in range(grid_size):
		for x in range(grid_size):
			var key := Vector2i(x, y)
			var type := str(tile_types.get(key, "empty"))
			var terrain := str(terrain_grid[key])
			var sub_zone_id := str(sub_zone_grid.get(key, ""))
			var tile_instance := tile_scene.instantiate()
			tile_instance.set_meta("tile_type", type)
			tile_instance.set_meta("grid_pos", key)
			tile_instance.set_meta("terrain", terrain)
			tile_instance.set_meta("sub_zone", sub_zone_id)
			tile_instance.position = Vector3(key.x * 4.0, 0, key.y * 4.0)

			var connects := _neighbor_keys(key)
			connects = connects.filter(func(k: Vector2i) -> bool:
				return BoardConfig.is_passable(terrain_grid.get(k, "rock")))
			tile_instance.set_meta("connections", connects)

			nodes_dict[key] = tile_instance

	GlobalData.board.board_grid = [nodes_dict]
	return {
		"nodes": nodes_dict,
		"terrain": terrain_grid,
		"sub_zones": sub_zone_grid,
		"tile_types": tile_types,
		"start_pos": start_key,
		"exit_pos": exit_key,
	}


## Builds vibrant sunlight and ambient lighting so the entire tabletop map
## is bright, crisp, and beautifully illuminated.
func build_environment_and_light() -> Node3D:
	var root := Node3D.new()
	root.name = "BoardLighting"

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.light_energy = 2.1
	sun.shadow_enabled = true
	sun.shadow_blur = 1.35
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_split_1 = 0.10
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.55
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	root.add_child(sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "BoardWorldEnv"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.10, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.78, 0.88)
	env.ambient_light_energy = 1.45

	# ACES Tonemapping & Contrast / Saturation adjustment for rich holographic tabletop feel
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.20

	# SSAO adds deep contact depth to board tiles, terrain hills, props, and mech tokens
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5

	# Glow for neon objective beacons, recon radars, and holographic tile paths
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.18
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.95
	world_env.environment = env
	root.add_child(world_env)

	return root


## Builds a single large ground plane under the whole grid so the board reads
## as one seamless area instead of a grid of separate tile plates. The tiles
## themselves stay flush (flat PlaneMesh) so adjacent terrain merges visually.
## The plane now OVERSHOOTS the tile grid by ~20 units and fades to transparent
## with a heavily wobbled irregular edge — the table is an island, not a hard square.
func build_ground() -> MeshInstance3D:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var overshoot := 40.0 # 20 units beyond each side → 140×140 for 25 grid (100×100 tiles)
	plane.size = Vector2(grid_size * 4.0 + overshoot, grid_size * 4.0 + overshoot)
	ground.mesh = plane
	# Use fade shader instead of flat StandardMaterial — edge fades to void.
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/board_ground_fade.gdshader")
	mat.set_shader_parameter("ground_color", Color(0.09, 0.11, 0.09, 1.0))
	mat.set_shader_parameter("table_color", Color(0.06, 0.07, 0.08, 1.0))
	# Grid 25 → tiles 100×100, plane 140×140 → inner ratio 0.714; fade starts at
	# tile edge so the 20-unit overshoot is the entire soft irregular border.
	mat.set_shader_parameter("fade_start", 0.70)
	mat.set_shader_parameter("fade_softness", 0.28)
	mat.set_shader_parameter("noise_strength", 0.42)
	mat.set_shader_parameter("roughness_val", 1.0)
	ground.material_override = mat
	# Slightly lower to avoid z-fighting; large plane needs more subdiv for smooth fade.
	plane.subdivide_depth = 32
	plane.subdivide_width = 32
	ground.position = Vector3(grid_size * 2.0, -0.04, grid_size * 2.0)
	return ground


## Partitions the 25x25 grid into organic sub-zone clusters using seeded Voronoi centroids.
func _generate_sub_zones(theme_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var available_sub_zones := BoardConfig.sub_zones_for_theme(theme_id)
	var sub_zone_grid: Dictionary = {} # Vector2i -> String

	if available_sub_zones.is_empty():
		for y in range(grid_size):
			for x in range(grid_size):
				sub_zone_grid[Vector2i(x, y)] = theme_id + "_default"
		return sub_zone_grid

	# Generate 3 to 4 cluster centroids across the map
	var num_centroids := mini(maxi(available_sub_zones.size(), 3), 4)
	var centroids: Array = []
	var shuffled_zones := available_sub_zones.duplicate()
	_seeded_shuffle(shuffled_zones, rng)

	for i in range(num_centroids):
		var sz_id: String = shuffled_zones[i % shuffled_zones.size()]
		var cx := rng.randf_range(3.0, float(grid_size) - 4.0)
		var cy := rng.randf_range(3.0, float(grid_size) - 4.0)
		centroids.append({"pos": Vector2(cx, cy), "sub_zone": sz_id})

	# Assign each grid cell to the nearest centroid with a slight perturbation for natural organic borders
	for y in range(grid_size):
		for x in range(grid_size):
			var cell := Vector2i(x, y)
			var cell_v := Vector2(float(x), float(y))
			var best_dist := 999999.0
			var best_sz: String = available_sub_zones[0]

			for c in centroids:
				var c_pos: Vector2 = c["pos"]
				# Simple deterministic jitter based on cell coord and seed
				var jitter := sin(float(x) * 1.7 + float(y) * 2.3 + float(GlobalData.board.board_seed % 100)) * 2.2
				var d := cell_v.distance_squared_to(c_pos) + jitter
				if d < best_dist:
					best_dist = d
					best_sz = str(c["sub_zone"])

			sub_zone_grid[cell] = best_sz

	return sub_zone_grid


func _weighted_terrain_for_sub_zone(rng: RandomNumberGenerator, sub_zone_id: String, theme_id: String) -> String:
	var pool: Array = BoardConfig.terrain_pool_for_sub_zone(sub_zone_id, theme_id)
	var total := 0
	for entry in pool:
		total += int(entry[1])
	var roll := rng.randi_range(1, maxi(total, 1))
	for entry in pool:
		roll -= int(entry[1])
		if roll <= 0:
			return str(entry[0])
	return "plain"


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


func _main_road(terrain_grid: Dictionary, start_k: Vector2i, goal_k: Vector2i, rng: RandomNumberGenerator) -> void:
	var cur := start_k
	var goal := goal_k
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
	var river_row := rng.randi_range(4, grid_size - 5)
	for x in range(grid_size):
		var key := Vector2i(x, river_row)
		if terrain_grid.get(key, "road") == "road":
			# The main road keeps a bridge crossing here.
			terrain_grid[key] = "bridge"
		else:
			terrain_grid[key] = "water"


func _trim_unreachable(terrain_grid: Dictionary, start_k: Vector2i) -> void:
	var visited: Dictionary = {}
	var frontier: Array = [start_k]
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


func _assign_content(terrain_grid: Dictionary, start_key: Vector2i, exit_key: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var grid_size_i := grid_size

	# All non-start/exit walkable cells, in distance-from-start order.
	var walkable: Array = []
	for key in terrain_grid:
		if key == start_key or key == exit_key:
			continue
		if BoardConfig.is_passable(terrain_grid[key]):
			walkable.append(key)
	walkable.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (abs(a.x - start_key.x) + abs(a.y - start_key.y)) < (abs(b.x - start_key.x) + abs(b.y - start_key.y)))

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

	# Extraction Mode Contract Placement:
	# Primary Objective Target placed in deep territory (between 1/2 and 4/5 distance)
	var contract: Dictionary = GlobalData.board.active_contract
	var primary_placed := false
	if not contract.is_empty():
		var p_info: Dictionary = contract.get("primary", {})
		var p_type: String = str(p_info.get("target_tile_type", "comms_relay"))
		var deep_candidates = walkable.filter(func(k: Vector2i) -> bool:
			if result.has(k) or k == start_key or k == exit_key:
				return false
			var dist = abs(k.x - start_key.x) + abs(k.y - start_key.y)
			return dist >= int(grid_size_i * 0.6) and dist <= int(grid_size_i * 1.2))
		if deep_candidates.is_empty():
			deep_candidates = walkable.filter(func(k: Vector2i) -> bool: return not result.has(k) and k != start_key and k != exit_key)
		if not deep_candidates.is_empty():
			var p_pos: Vector2i = deep_candidates[0]
			result[p_pos] = p_type
			primary_placed = true

		# Secondary Objective Targets
		var secondaries = contract.get("secondaries", [])
		if secondaries is Array:
			var s_candidates = walkable.filter(func(k: Vector2i) -> bool: return not result.has(k) and k != start_key and k != exit_key)
			var s_idx := 0
			for sec in secondaries:
				var s_type: String = str(sec.get("target_tile_type", ""))
				if s_type != "" and s_idx < s_candidates.size():
					result[s_candidates[s_idx]] = s_type
					s_idx += 1

	GlobalData.board.extraction_zone_pos = exit_key

	# Scatter content on the rest of the walkable pool.
	for key in walkable:
		if result.has(key):
			continue
		result[key] = _roll_content(rng)

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
	# Bait tiles are decoy supply caches: they look like loot but spring a
	# pincer ambush (see board_manager._trigger_bait_trap).
	var roll := rng.randf()
	if roll < 0.05:
		return "event"
	elif roll < 0.09:
		return "data_node"
	elif roll < 0.12:
		return "bait"
	elif roll < 0.15:
		return "fuel_depot"
	elif roll < 0.18:
		return "supply_truck"
	elif roll < 0.22:
		return "fuel_choice"
	elif roll < 0.25:
		return "research_lab"
	elif roll < 0.28:
		return "dust_storm"
	elif roll < 0.31:
		return "tactical_smog"
	elif roll < 0.33:
		return "rain"
	elif roll < 0.35:
		return "sandstorm"
	elif roll < 0.37:
		return "fog"
	elif roll < 0.40:
		return "emp_zone"
	elif roll < 0.38:
		return "distress_signal"
	elif roll < 0.43:
		return "scavenge_site"
	elif roll < 0.47:
		return "unknown_signal"
	elif roll < 0.50:
		return "dead_end"
	return "empty" # 50% open wilderness, scenic roads, and uncrowded terrain


func _neighbor_keys(key: Vector2i) -> Array:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var result: Array = []
	for d in dirs:
		var n: Vector2i = key + d
		if n.x >= 0 and n.y >= 0 and n.x < grid_size and n.y < grid_size:
			result.append(n)
	return result