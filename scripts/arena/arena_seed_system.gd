extends Node

## Generates deterministic obstacle layouts tailored for Desert, Highrise City, Crossroads, and River Bridge maps.

var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func set_seed(level: int, tile_pos: Vector2i) -> void:
	current_seed = hash(level * 1000 + tile_pos.x * 100 + tile_pos.y)
	rng.seed = current_seed


func get_obstacle_positions(theme: int = 0, arena_size: float = 240.0) -> Array:
	rng.seed = current_seed
	var half = arena_size / 2.0 - 15.0
	var positions = []

	match theme:
		0: # DESERT (ทะเลทราย)
			# Outpost perimeter & scattered sand dunes/bunkers
			for i in range(rng.randi_range(28, 38)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(20, 100)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		1: # CITY_HIGHRISE (เมืองตึกเยอะ)
			# Street alley barricades & container stacks
			for i in range(rng.randi_range(30, 42)):
				var x = rng.randf_range(-half, half)
				var z = rng.randf_range(-half, half)
				if absf(x) < 15.0 and absf(z) < 15.0: continue
				positions.append({
					"pos": Vector3(x, 0, z),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		2: # CROSSROADS (สี่แยก)
			# Intersection barricades, bus shelters & traffic posts
			for side in [-20.0, 20.0]:
				for i in range(5):
					var pos_val = (i - 2) * 12.0
					positions.append({"pos": Vector3(side, 0, pos_val), "type": 0, "rot": deg_to_rad(90)})
					positions.append({"pos": Vector3(pos_val, 0, side), "type": 0, "rot": 0.0})
			# Corner cover
			for i in range(rng.randi_range(20, 28)):
				positions.append({
					"pos": Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)),
					"type": rng.randi_range(1, 5),
					"rot": rng.randf_range(0, TAU)
				})

		3: # RIVER_BRIDGE (สะพานแม่น้ำ)
			# Bridge entrance/exit barricades & riverbank rocks
			for z in [-28.0, 28.0]:
				for bx in [-10.0, 0.0, 10.0]:
					positions.append({"pos": Vector3(bx, 0, z), "type": 0, "rot": 0.0})
			# Flanking bridge cover & riverbank supply crates
			for i in range(rng.randi_range(25, 35)):
				var rx = rng.randf_range(-half, half)
				var rz = rng.randf_range(-half, half)
				if absf(rz) < 22.0 and absf(rx) > 20.0: continue # In water
				positions.append({
					"pos": Vector3(rx, 0, rz),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

	# Filter out player spawn (0, 0)
	positions = positions.filter(func(p):
		return p["pos"].length() > 10.0
	)

	return positions
