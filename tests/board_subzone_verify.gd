extends Node

## Verifies Sector Sub-Zone (Micro-Biome) generation, metadata assignment,
## and Arena Generator matching.
## Run: godot --headless --path . res://tests/board_subzone_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SUBZONE_OK: " + name)
	else:
		_fails += 1
		printerr("SUBZONE_FAIL: " + name)


func _ready() -> void:
	print("--- Running Sub-Zone System Verification ---")

	# 1. Verify Sub-Zones Catalog per Theme
	for theme_id in ["suburb", "urban", "desert", "forest"]:
		var sz_list := BoardConfig.sub_zones_for_theme(theme_id)
		_check(sz_list.size() >= 3, "Theme '%s' has at least 3 sub-zones (found %d)" % [theme_id, sz_list.size()])
		for sz_id in sz_list:
			var info := BoardConfig.get_sub_zone_info(sz_id)
			_check(info.has("name") and str(info["name"]) != "", "Sub-zone '%s' has valid name" % sz_id)
			_check(info.has("terrain_weights") and not info["terrain_weights"].is_empty(), "Sub-zone '%s' has terrain weights" % sz_id)

	# 2. Verify Suburb specific sub-zones
	var suburb_zones := BoardConfig.sub_zones_for_theme("suburb")
	_check(suburb_zones.has("suburb_village"), "Suburb has suburb_village")
	_check(suburb_zones.has("suburb_meadow"), "Suburb has suburb_meadow")
	_check(suburb_zones.has("suburb_water"), "Suburb has suburb_water")

	# 3. Verify Board Generator Sub-Zone Partitioning
	var generator_script = preload("res://scripts/board/board_generator.gd")
	var generator := generator_script.new()
	add_child(generator)

	GlobalData.board.board_seed = 12345
	GlobalData.board.current_sector = 1 # suburb
	var board_data: Dictionary = generator.generate_board()

	var nodes: Dictionary = board_data.get("nodes", {})
	_check(nodes.size() == BoardConfig.GRID_SIZE * BoardConfig.GRID_SIZE, "Board generated 625 tiles")

	var sub_zones_found: Dictionary = {}
	var all_tiles_have_subzone := true

	for key in nodes:
		var tile = nodes[key]
		var sz: String = str(tile.get_meta("sub_zone", ""))
		if sz == "":
			all_tiles_have_subzone = false
		sub_zones_found[sz] = sub_zones_found.get(sz, 0) + 1

	_check(all_tiles_have_subzone, "Every tile on board has a non-empty sub_zone metadata")
	_check(sub_zones_found.size() >= 2, "Board generated multiple sub-zones on grid (found %d: %s)" % [sub_zones_found.size(), str(sub_zones_found.keys())])

	# 4. Verify BoardState sub_zone handling
	GlobalData.board.reset()
	_check(GlobalData.board.combat_tile_sub_zone == "", "BoardState.reset clears combat_tile_sub_zone")
	GlobalData.board.combat_tile_sub_zone = "suburb_village"
	_check(GlobalData.board.combat_tile_sub_zone == "suburb_village", "BoardState stores combat_tile_sub_zone")

	# 5. Verify Arena Generator Sub-Zone Mapping
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var arena := arena_script.new()

	# Suburb Village -> CROSSROADS
	GlobalData.board.board_theme_id = "suburb"
	GlobalData.board.combat_tile_terrain = "plain"
	GlobalData.board.combat_tile_sub_zone = "suburb_village"
	var biome_village = arena._theme_from_board()
	_check(biome_village == arena_script.BiomeTheme.CROSSROADS, "Suburb Village maps to CROSSROADS arena theme")

	# Suburb Wetland -> RIVER_BRIDGE
	GlobalData.board.combat_tile_sub_zone = "suburb_water"
	var biome_water = arena._theme_from_board()
	_check(biome_water == arena_script.BiomeTheme.RIVER_BRIDGE, "Suburb Wetland maps to RIVER_BRIDGE arena theme")

	# Forest Road -> FOREST_ROAD
	GlobalData.board.board_theme_id = "forest"
	GlobalData.board.combat_tile_terrain = "road"
	GlobalData.board.combat_tile_sub_zone = "forest_deep"
	var biome_froad = arena._theme_from_board()
	_check(biome_froad == arena_script.BiomeTheme.FOREST_ROAD, "Forest Road maps to FOREST_ROAD arena theme")

	# Forest River -> RIVER_BRIDGE
	GlobalData.board.combat_tile_terrain = "plain"
	GlobalData.board.combat_tile_sub_zone = "forest_river"
	var biome_friver = arena._theme_from_board()
	_check(biome_friver == arena_script.BiomeTheme.RIVER_BRIDGE, "Forest River maps to RIVER_BRIDGE arena theme")

	print("--- Results: %d/%d checks passed ---" % [_checks - _fails, _checks])
	if _fails == 0:
		print("SUBZONE_ALL_OK: All checks passed successfully!")
	else:
		printerr("SUBZONE_FAILURES: %d checks failed!" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
