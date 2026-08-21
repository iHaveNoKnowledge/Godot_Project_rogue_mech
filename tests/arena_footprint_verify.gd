extends Node

## Verifies the irregular battlefield footprint system:
##   1. Flat themes (desert/city/crossroads) build a seeded footprint; the
##      special-terrain themes (forest/river) keep a square frame (null).
##   2. The footprint is connected, never the full square, and sized sanely.
##   3. Deterministic: the same seed always produces the same shape, while
##      different seeds produce different shapes.
##   4. is_inside / distance_to_outline / ring_points agree with the outline.
##   5. A real arena: escape zones hug the outline and every solid obstacle
##      sits inside the footprint.
## Run: godot --headless --path . res://tests/arena_footprint_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FOOT_OK: " + name)
	else:
		_fails += 1
		printerr("FOOT_FAIL: " + name)


func _ready() -> void:
	# --- 1. Theme gating ---
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var gen := arena_script.new()
	gen.current_theme = arena_script.BiomeTheme.DESERT
	gen.arena_size = 240.0
	gen.generate_arena()
	# generate_arena alone never builds a footprint — _ready() does.
	_check(gen.footprint == null, "generate_arena does not build a footprint")

	GlobalData.reset_run_data()
	GlobalData.board.board_theme_id = "urban"
	var gen_flat := arena_script.new()
	gen_flat.current_theme = arena_script.BiomeTheme.CITY_HIGHRISE
	gen_flat.arena_size = 240.0
	add_child(gen_flat)
	var fp: ArenaFootprint = gen_flat.footprint
	_check(fp != null, "CITY_HIGHRISE arena builds an irregular footprint")

	GlobalData.reset_run_data()
	GlobalData.board.board_theme_id = "forest"
	var gen_forest := arena_script.new()
	gen_forest.current_theme = arena_script.BiomeTheme.FOREST
	gen_forest.arena_size = 240.0
	add_child(gen_forest)
	_check(gen_forest.footprint == null, "FOREST keeps its square frame (no footprint)")

	# --- 2. Pure module checks ---
	var fp1 := ArenaFootprint.create(12345, 240.0)
	_check(fp1 != null, "footprint creates from a seed")
	_check(fp1.n >= 5 and fp1.n <= 12, "grid is sized to the arena (n=%d)" % fp1.n)
	var grid_area := fp1.n * fp1.n
	_check(fp1.cells.size() >= 6 and fp1.cells.size() <= grid_area - 4,
		"cell count is non-trivial and non-square (%d/%d)" % [fp1.cells.size(), grid_area])
	_check(fp1.cells.size() < grid_area, "footprint is NOT the full square")
	_check(_is_connected(fp1.cells), "footprint region is connected")
	_check(fp1.segments.size() >= 4, "boundary has enough runs (got %d)" % fp1.segments.size())
	_check(fp1.perimeter > 0.0, "boundary perimeter is positive")

	# Boundary runs form a closed loop (every segment endpoint meets another).
	_check(_segments_form_loop(fp1.segments), "boundary segments form a closed loop")

	# --- 3. Determinism ---
	var fp1b := ArenaFootprint.create(12345, 240.0)
	_check(_same_cells(fp1, fp1b), "same seed -> same footprint shape")
	var differs := false
	for s in [1, 2, 3, 4]:
		var other := ArenaFootprint.create(s, 240.0)
		if not _same_cells(fp1, other):
			differs = true
			break
	_check(differs, "different seeds -> different shapes")

	# --- 4. Inside/outline/ring consistency ---
	var inside_ok := true
	for wc in fp1.world_centers:
		if not fp1.is_inside(wc):
			inside_ok = false
			break
	_check(inside_ok, "every cell center is inside the footprint")
	var corner := fp1.origin + Vector2(fp1.n, fp1.n) * ArenaFootprint.CELL_SIZE
	_check(not fp1.is_inside(corner + Vector2(5, 5)), "a point in the dead corner is outside")
	_check(fp1.distance_to_outline(fp1.centroid) > 0.0, "centroid is a real distance from the outline")

	var ring := fp1.ring_points(12, 10.0)
	_check(ring.size() == 12, "ring_points samples the outline (got %d)" % ring.size())
	var ring_inside := true
	for p in ring:
		if not fp1.is_inside(Vector2(p.x, p.z)):
			ring_inside = false
	_check(ring_inside, "ring points sit inside the footprint")

	# --- 5. Real arena integration ---
	GlobalData.reset_run_data()
	GlobalData.board.board_theme_id = "desert"
	var arena := arena_script.new()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(arena.footprint != null, "real DESERT arena builds a footprint")
	if arena.footprint != null:
		var zones: Array = []
		for z in arena.escape_zone_container.get_children():
			if z.is_in_group("escape_zone"):
				zones.append(z)
		_check(zones.size() == arena.footprint.outer_segments.size(),
			"escape zones hug the outer hull (zones=%d segments=%d)" % [zones.size(), arena.footprint.outer_segments.size()])
		var all_inside := true
		for body in arena.structures_container.get_children():
			if body.is_in_group("solid_obstacle") and body is Node3D \
					and not arena.footprint.is_inside(Vector2(body.position.x, body.position.z)):
				all_inside = false
				break
		_check(all_inside, "every solid obstacle sits inside the footprint")

	print("ARENA_FOOTPRINT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _same_cells(a: ArenaFootprint, b: ArenaFootprint) -> bool:
	if a.cells.size() != b.cells.size():
		return false
	var ka := a.cells.keys()
	ka.sort()
	var kb := b.cells.keys()
	kb.sort()
	for i in range(ka.size()):
		if ka[i] != kb[i]:
			return false
	return true


func _is_connected(cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var visited := {}
	var start: Vector2i = cells.keys()[0]
	visited[start] = true
	var stack := [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in dirs:
			var nb: Vector2i = c + d
			if cells.has(nb) and not visited.has(nb):
				visited[nb] = true
				stack.append(nb)
	return visited.size() == cells.size()


func _segments_form_loop(segments: Array) -> bool:
	# Every segment's start must match some segment's end (within epsilon) and
	# vice versa — the boundary is a closed polygon.
	var eps := 0.01
	var starts_ok := true
	var ends_ok := true
	for s in segments:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var has_match_start := false
		var has_match_end := false
		for t in segments:
			if t == s:
				continue
			var ta: Vector2 = t["a"]
			var tb: Vector2 = t["b"]
			if ta.distance_to(a) < eps or tb.distance_to(a) < eps:
				has_match_start = true
			if ta.distance_to(b) < eps or tb.distance_to(b) < eps:
				has_match_end = true
			if has_match_start and has_match_end:
				break
		if not has_match_start:
			starts_ok = false
		if not has_match_end:
			ends_ok = false
	return starts_ok and ends_ok
