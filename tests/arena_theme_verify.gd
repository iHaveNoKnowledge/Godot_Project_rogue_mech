extends Node

## Verifies the board-zone -> arena-biome mapping (Feature 5):
##   1. Every board map theme has an entry in BoardConfig.THEME_ARENA.
##   2. Each mapping resolves to a valid BiomeTheme via arena_generator logic.
##   3. The mapping covers every theme theme_for_sector() can produce.
## Run: godot --headless --path . res://tests/arena_theme_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("THEME_OK: " + name)
	else:
		_fails += 1
		printerr("THEME_FAIL: " + name)


func _ready() -> void:
	# Every sector theme maps to a biome.
	var biomes := [
		"DESERT", "CITY_HIGHRISE", "CROSSROADS", "RIVER_BRIDGE", "FOREST",
	]
	for theme_id in ["suburb", "desert", "forest", "urban"]:
		var arena_name: String = BoardConfig.THEME_ARENA.get(theme_id, "")
		_check(arena_name != "", "%s maps to an arena name" % theme_id)
		_check(arena_name in biomes, "%s -> %s is a valid biome" % [theme_id, arena_name])

	# theme_for_sector can only produce themes that have an arena mapping.
	for sector in [1, 2, 3, 4]:
		var theme_id := BoardConfig.theme_for_sector(sector)
		_check(BoardConfig.THEME_ARENA.has(theme_id), "sector %d theme %s has arena mapping" % [sector, theme_id])

	# The arena generator resolves the board theme into a BiomeTheme enum.
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var arena := arena_script.new()
	for theme_id in ["suburb", "desert", "forest", "urban"]:
		GlobalData.board.board_theme_id = theme_id
		var biome = arena._theme_from_board()
		var biome_name: String = arena_script.BiomeTheme.keys()[biome]
		_check(biome_name == BoardConfig.THEME_ARENA[theme_id], "board %s -> arena %s" % [theme_id, biome_name])

	if _fails == 0:
		print("THEME_ALL_OK: %d checks passed" % _checks)
	else:
		printerr("THEME_FAILURES: %d/%d checks failed" % [_fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
