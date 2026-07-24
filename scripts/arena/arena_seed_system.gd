extends Node

## Generates deterministic arena layouts from a seed.
## Each combat encounter gets a slightly different arena.

enum ArenaVariant { OPEN_FIELD, CORRIDOR, CENTRAL_FORTRESS, SCATTER }

var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func set_seed(level: int, tile_pos: Vector2i) -> void:
	current_seed = hash(level * 1000 + tile_pos.x * 100 + tile_pos.y)
	rng.seed = current_seed


func get_variant() -> int:
	rng.seed = current_seed
	return rng.randi_range(0, 3)


func get_variant_name() -> String:
	match get_variant():
		ArenaVariant.OPEN_FIELD: return "Open Field"
		ArenaVariant.CORRIDOR: return "Corridor"
		ArenaVariant.CENTRAL_FORTRESS: return "Central Fortress"
		ArenaVariant.SCATTER: return "Scatter"
	return "Unknown"


func get_obstacle_positions(arena_size: float = 120.0) -> Array:
	rng.seed = current_seed
	var variant = get_variant()
	var half = arena_size / 2.0 - 8.0
	var positions = []

	match variant:
		ArenaVariant.OPEN_FIELD:
			# Sparse cover, long sight lines
			for i in range(rng.randi_range(6, 8)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(15, 45)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 2)
				})

		ArenaVariant.CORRIDOR:
			# Central wall divides arena
			var wall_count = rng.randi_range(4, 6)
			for i in range(wall_count):
				var z = (i - wall_count / 2.0) * 4.0
				positions.append({
					"pos": Vector3(0, 0, z),
					"type": 0  # Barriers
				})
			# Flanking routes
			for i in range(rng.randi_range(4, 6)):
				var side = [-1, 1][rng.randi() % 2]
				positions.append({
					"pos": Vector3(side * rng.randf_range(20, 40), 0, rng.randf_range(-30, 30)),
					"type": rng.randi_range(1, 3)
				})

		ArenaVariant.CENTRAL_FORTRESS:
			# Dense center with open perimeter
			for i in range(rng.randi_range(8, 10)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(5, 12)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 3)
				})
			# Outer ring
			for i in range(rng.randi_range(4, 6)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(35, 50)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 1)
				})

		ArenaVariant.SCATTER:
			# Random uniform distribution
			for i in range(rng.randi_range(10, 14)):
				positions.append({
					"pos": Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)),
					"type": rng.randi_range(0, 3)
				})

	# Filter out positions too close to center (player spawn)
	positions = positions.filter(func(p):
		return p["pos"].length() > 8.0
	)

	return positions
