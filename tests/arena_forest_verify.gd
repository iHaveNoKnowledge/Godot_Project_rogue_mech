extends Node

## Verifies the FOREST arena biome generation:
##   1. board "forest" maps to BiomeTheme.FOREST.
##   2. FOREST ground tiles + structures build without errors.
##   3. FOREST seed layout excludes cover in the river band.
## Run: godot --headless --path . res://tests/arena_forest_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FOREST_OK: " + name)
	else:
		_fails += 1
		printerr("FOREST_FAIL: " + name)


func _ready() -> void:
	# Real flow: generate a sector-2 board (odd seed -> forest theme), which is
	# exactly how board_theme_id is set during gameplay, then build the arena.
	GlobalData.reset_run_data()
	GlobalData.current_sector = 2
	GlobalData.board_seed = 1 # odd -> forest
	var gen := preload("res://scripts/board/board_generator.gd").new()
	gen.generate_board()
	_check(GlobalData.board_theme_id == "forest", "board generation sets forest theme")

	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var biome = arena_script.BiomeTheme.FOREST
	_check(biome == 4, "FOREST is enum value 4")

	var arena := arena_script.new()
	arena.current_theme = arena._theme_from_board()
	_check(arena.current_theme == biome, "board forest -> FOREST biome")
	arena.arena_size = 240.0
	arena.generate_arena()
	_check(arena.get_node_or_null("ThemeStructures") != null, "structures container created")
	_check(arena.get_node_or_null("EscapeZones") != null, "escape zones container created")

	# FOREST builds river + waterfall + trees without crashing.
	var structures := arena.get_node_or_null("ThemeStructures")
	var has_waterfall := false
	var has_river := false
	if structures:
		for child in structures.get_children():
			if child.name == "Waterfall":
				has_waterfall = true
			if child.name == "Riverband" or child.name.begins_with("River"):
				has_river = true
	_check(structures.get_child_count() > 5, "multiple forest structures spawned")

	# Seed layout: no cover inside the river band (|z| < 24).
	var seed_sys := preload("res://scripts/arena/arena_seed_system.gd").new()
	seed_sys.set_seed(2, Vector2i(7, 7))
	var cover := seed_sys.get_obstacle_positions(4, 240.0)
	var in_water := 0
	for c in cover:
		if absf(c["pos"].z) < 24.0:
			in_water += 1
	_check(in_water == 0, "no cover inside the river band (got %d)" % in_water)

	# No city props: every FOREST cover must be a forest type (6-8), never a
	# city container/barrier/pillar (0-5) — otherwise the forest arena reads as
	# a building site.
	var city_props := 0
	for c in cover:
		if int(c["type"]) <= 5:
			city_props += 1
	_check(city_props == 0, "no city props in forest arena (got %d)" % city_props)

	print("ARENA_FOREST_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)