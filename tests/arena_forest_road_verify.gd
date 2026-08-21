extends Node

## Verifies the FOREST_ROAD arena biome (ถนนตัดผ่านป่า):
##   1. A forest board fought on a ROAD tile maps to BiomeTheme.FOREST_ROAD.
##   2. FOREST_ROAD builds a road band instead of the river + waterfall.
##   3. No cover spawns on the road band (|z| < 24).
##   4. Plain forest boards (non-road) still map to plain FOREST.
## Run: godot --headless --path . res://tests/arena_forest_road_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FOREST_ROAD_OK: " + name)
	else:
		_fails += 1
		printerr("FOREST_ROAD_FAIL: " + name)


func _ready() -> void:
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var forest_road: int = arena_script.BiomeTheme.FOREST_ROAD
	_check(forest_road == 5, "FOREST_ROAD is enum value 5")

	# Real flow: forest board, player stepped onto a ROAD tile -> road arena.
	GlobalData.reset_run_data()
	GlobalData.board.board_theme_id = "forest"
	GlobalData.board.combat_tile_terrain = "road"
	var arena := arena_script.new()
	arena.current_theme = arena._theme_from_board()
	_check(arena.current_theme == forest_road, "forest board + road tile -> FOREST_ROAD biome")

	# It builds the full arena without crashing and lays a road, not a river.
	arena.arena_size = 240.0
	arena.generate_arena()
	var structures := arena.get_node_or_null("ThemeStructures")
	_check(structures != null, "structures container created")
	var has_road := false
	var has_waterfall := false
	var has_river := false
	if structures:
		for child in structures.get_children():
			if child.name == "ForestRoad":
				has_road = true
			if child.name == "Waterfall":
				has_waterfall = true
			if child.name == "Riverband" or child.name.begins_with("River"):
				has_river = true
	_check(has_road, "FOREST_ROAD lays a ForestRoad band")
	_check(not has_waterfall, "no waterfall in the road-through-forest arena")
	_check(not has_river, "no river in the road-through-forest arena")

	# The road band surface sits at y=0 (level road), not the sunken river y.
	var strip_y := arena._forest_strip_y()
	_check(strip_y == 0.0, "road strip surface is level (y=0)")
	var center_h := arena._forest_terrain_height(0.0, 0.0)
	_check(absf(center_h) < 0.01, "terrain under the road is flat (%.2f)" % center_h)

	# No cover spawns on the road band.
	var seed_sys := preload("res://scripts/arena/arena_seed_system.gd").new()
	seed_sys.set_seed(2, Vector2i(7, 7))
	var cover := seed_sys.get_obstacle_positions(int(forest_road), 240.0)
	var on_road := 0
	for c in cover:
		if absf(c["pos"].z) < 24.0:
			on_road += 1
	_check(on_road == 0, "no cover on the road band (got %d)" % on_road)

	# Forest cover types only (6-8), same as plain forest.
	var city_props := 0
	for c in cover:
		if int(c["type"]) <= 5:
			city_props += 1
	_check(city_props == 0, "no city props in the road arena (got %d)" % city_props)

	# A forest board fought on NON-road terrain still gets the plain FOREST.
	GlobalData.board.combat_tile_terrain = "forest"
	var arena2 := arena_script.new()
	arena2.current_theme = arena2._theme_from_board()
	_check(arena2.current_theme == arena_script.BiomeTheme.FOREST,
		"forest board + forest tile -> plain FOREST biome")

	print("ARENA_FOREST_ROAD_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
