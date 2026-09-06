extends Node

## Generates deterministic obstacle layouts tailored for Desert, Highrise City, Crossroads, and River Bridge maps.

var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


# The arena generator's irregular footprint (null on square arenas), resolved
# lazily so cover filtering works regardless of node _ready ordering.
func _arena_footprint() -> ArenaFootprint:
	var arena_gen = get_node_or_null("../ArenaGenerator")
	if arena_gen != null and arena_gen.get("footprint") != null:
		return arena_gen.footprint
	return null


func set_seed(level: int, tile_pos: Vector2i) -> void:
	current_seed = hash(level * 1000 + tile_pos.x * 100 + tile_pos.y)
	rng.seed = current_seed


func get_obstacle_positions(theme: int = 0, arena_size: float = 240.0) -> Array:
	# NOTE: never randomize() here — that would defeat the deterministic seed
	# set by set_seed(). Callers must call set_seed() first (or leave the seed 0
	# for a fixed default layout).
	var half = arena_size / 2.0 - 15.0
	var positions = []

	match theme:
		0: # DESERT (ทะเลทราย)
			# Outpost perimeter & scattered sand dunes/bunkers — dense layout so
			# the 240-400m field never reads empty.
			for i in range(rng.randi_range(60, 80)):
				var angle = rng.randf() * TAU
				var radius = rng.randf_range(20, 100)
				positions.append({
					"pos": Vector3(cos(angle) * radius, 0, sin(angle) * radius),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		1: # CITY_HIGHRISE (เมืองตึกเยอะ)
			# Street alley barricades & container stacks — dense cover for CQB.
			for i in range(rng.randi_range(62, 85)):
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
			# Corner cover — doubled for dense crossfire lanes.
			for i in range(rng.randi_range(40, 55)):
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
			# Flanking bridge cover & riverbank supply crates — dense.
			for i in range(rng.randi_range(50, 70)):
				var rx = rng.randf_range(-half, half)
				var rz = rng.randf_range(-half, half)
				if absf(rz) < 22.0:
					# Trench zone: only bridge strips are dry ground (center + flanks)
					var on_center_bridge = absf(rx) <= 15.0
					var on_flank_bridge = absf(rx - 75.0) <= 7.5 or absf(rx + 75.0) <= 7.5
					if not on_center_bridge and not on_flank_bridge:
						continue # In water
				positions.append({
					"pos": Vector3(rx, 0, rz),
					"type": rng.randi_range(0, 5),
					"rot": rng.randf_range(0, TAU)
				})

		4, 5: # FOREST (ป่า) / FOREST_ROAD (ถนนตัดผ่านป่า)
			# Trees are both cover and scenery; logs and ferns add clutter. Only
			# forest cover types (6=tree trunk, 7=fallen log, 8=fern) are used so
			# no city props (containers, barriers, pillars) break the biome. The
			# central band stays clear on both variants (river strip / road).
			# Doubled density for thick jungle concealment gameplay.
			for i in range(rng.randi_range(70, 95)):
				var x = rng.randf_range(-half, half)
				var z = rng.randf_range(-half, half)
				if absf(z) < 24.0:
					continue # Keep the river/road band clear of cover
				positions.append({
					"pos": Vector3(x, 0, z),
					"type": rng.randi_range(6, 8),
					"rot": rng.randf_range(0, TAU)
				})

	# Filter out player spawn (0, 0)
	positions = positions.filter(func(p):
		return p["pos"].length() > 10.0
	)

	# On an irregular footprint, drop any cover that would land in the void
	# outside the battlefield outline.
	var fp := _arena_footprint()
	if fp != null:
		positions = positions.filter(func(p):
			return fp.is_inside(Vector2(p["pos"].x, p["pos"].z))
		)

	return positions
