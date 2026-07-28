extends Node

## Generates deterministic arena layouts and randomized obstacle placement.

enum ArenaVariant { OPEN_FIELD, CORRIDOR, CENTRAL_FORTRESS, SCATTER, CHOKEPOINT_CANYON, BUNKER_PERIMETER }

var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func set_seed(level: int, tile_pos: Vector2i) -> void:
	current_seed = hash(level * 1000 + tile_pos.x * 100 + tile_pos.y)
	rng.seed = current_seed


func get_variant() -> int:
	rng.seed = current_seed
	return rng.randi_range(0, ArenaVariant.size() - 1)


func get_variant_name() -> String:
	match get_variant():
		ArenaVariant.OPEN_FIELD: return "Open Field"
		ArenaVariant.CORRIDOR: return "Double Corridor"
		ArenaVariant.CENTRAL_FORTRESS: return "Central Fortress"
		ArenaVariant.SCATTER: return "Scattered Ruins"
		ArenaVariant.CHOKEPOINT_CANYON: return "Chokepoint Canyon"
		ArenaVariant.BUNKER_PERIMETER: return "Bunker Perimeter"
	return "Unknown"


func get_obstacle_positions(arena_size: float = 240.0) -> Array:
	rng.seed = current_seed
	var variant = get_variant()
	var half = arena_size / 2.0 - 15.0
	var positions = []

	match variant:
		ArenaVariant.OPEN_FIELD:
			# Sparse cover, wide sight lines
			for i in range(rng.randi_range(16, 22)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(25, 95)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		ArenaVariant.CORRIDOR:
			# Two parallel barrier corridors
			for side in [-30.0, 30.0]:
				for i in range(rng.randi_range(8, 12)):
					var z = (i - 5) * 16.0
					positions.append({
						"pos": Vector3(side + rng.randf_range(-3, 3), 0, z),
						"type": rng.randi_range(0, 1),
						"rot": 0.0
					})
			# Flanking cover
			for i in range(rng.randi_range(10, 15)):
				var s = [-1, 1][rng.randi() % 2]
				positions.append({
					"pos": Vector3(s * rng.randf_range(50, 95), 0, rng.randf_range(-80, 80)),
					"type": rng.randi_range(1, 5),
					"rot": rng.randf_range(0, TAU)
				})

		ArenaVariant.CENTRAL_FORTRESS:
			# Massive central fortress ring
			for i in range(rng.randi_range(12, 16)):
				var angle = (float(i) / 14.0) * TAU
				var radius = rng.randf_range(15, 30)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 4),
					"rot": angle
				})
			# Outer ring
			for i in range(rng.randi_range(15, 20)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(65, 100)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		ArenaVariant.CHOKEPOINT_CANYON:
			# Diagonal wall barriers forcing chokepoints
			for i in range(12):
				var offset = (i - 6) * 15.0
				positions.append({
					"pos": Vector3(offset, 0, offset * 0.5),
					"type": 4 if i % 3 == 0 else 0,
					"rot": deg_to_rad(45)
				})
			for i in range(rng.randi_range(12, 18)):
				positions.append({
					"pos": Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)),
					"type": rng.randi_range(1, 5),
					"rot": rng.randf_range(0, TAU)
				})

		ArenaVariant.BUNKER_PERIMETER:
			# 4 Bunker corners with open interior
			var corners = [
				Vector3(-60, 0, -60), Vector3(60, 0, -60),
				Vector3(-60, 0, 60), Vector3(60, 0, 60)
			]
			for corner in corners:
				for j in range(4):
					positions.append({
						"pos": corner + Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10)),
						"type": rng.randi_range(0, 4),
						"rot": rng.randf_range(0, TAU)
					})
			for i in range(rng.randi_range(10, 15)):
				positions.append({
					"pos": Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		_: # SCATTER
			for i in range(rng.randi_range(25, 35)):
				positions.append({
					"pos": Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

	# Ensure clearance around player spawn (0, 0)
	positions = positions.filter(func(p):
		return p["pos"].length() > 12.0
	)

	return positions
