extends Node

## Verification test for Desert Map Variants (Chasm/Canyon, Mountains, Dunes, Oasis).
## Run: godot --headless --path . res://tests/desert_variants_verify.tscn

var _checks := 0
var _fails := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("DESERT_OK: ", msg)
	else:
		_fails += 1
		printerr("DESERT_FAIL: ", msg)

func _ready() -> void:
	print("--- Running Desert 4-Variants Verification ---")
	GlobalData.board.board_theme_id = "desert"
	var ArenaGenClass = preload("res://scripts/arena/arena_generator.gd")
	var arena = ArenaGenClass.new()
	arena.current_theme = ArenaGenClass.BiomeTheme.DESERT
	arena.arena_size = 240.0
	add_child(arena)

	# 1. Test sub-zone resolution
	GlobalData.board.combat_tile_sub_zone = "desert_canyon"
	_check(arena._resolve_desert_variant() == "canyon", "Sub-zone desert_canyon resolves to canyon")

	GlobalData.board.combat_tile_sub_zone = "desert_mountains"
	_check(arena._resolve_desert_variant() == "mountain", "Sub-zone desert_mountains resolves to mountain")

	GlobalData.board.combat_tile_sub_zone = "desert_dunes"
	_check(arena._resolve_desert_variant() == "dunes", "Sub-zone desert_dunes resolves to dunes")

	GlobalData.board.combat_tile_sub_zone = "desert_oasis"
	_check(arena._resolve_desert_variant() == "oasis", "Sub-zone desert_oasis resolves to oasis")

	# 2. Test fallback randomization across tiles when sub-zone is not set
	GlobalData.board.combat_tile_sub_zone = ""
	var seen_variants: Dictionary = {}
	for i in range(30):
		GlobalData.board.current_tile = Vector2i(i * 3 + 1, i * 7 + 2)
		var v: String = arena._resolve_desert_variant()
		seen_variants[v] = true
	_check(seen_variants.size() >= 3, "Alternates between multiple desert variants across tiles (seen: %s)" % [str(seen_variants.keys())])

	# 3. Test height calculations for Canyon / Chasm
	arena.desert_variant = "canyon"
	var chasm_center_z: float = sin(0.0) * 25.0 + cos(0.0) * 15.0 - 5.0 # ~ 10.0
	var deep_y: float = arena._get_terrain_height(0.0, chasm_center_z)
	_check(deep_y < -8.0, "Canyon center is deep chasm (height = %.2fm < -8.0m)" % deep_y)

	var bridge_z: float = sin(-45.0 * 0.035) * 25.0 + cos(-45.0 * 0.015) * 15.0 - 5.0
	var bridge_y: float = arena._get_terrain_height(-45.0, bridge_z)
	_check(bridge_y > -4.0, "Land bridge stays near surface (height = %.2fm > -4.0m)" % bridge_y)

	# 4. Test height calculations for Mountains
	arena.desert_variant = "mountain"
	# In central valley pass (wz = -5.0 at wx = 0)
	var valley_y: float = arena._get_terrain_height(0.0, -5.0)
	_check(valley_y < 4.0, "Mountain valley pass floor is navigable (height = %.2fm < 4.0m)" % valley_y)

	# On mountain ridge away from valley (e.g. at x = 0, z = 60.0)
	var peak_y: float = arena._get_terrain_height(0.0, 60.0)
	_check(peak_y > 8.0, "Mountain ridge rises to towering height (height = %.2fm > 8.0m)" % peak_y)

	# 5. Test actual Arena Generation for Canyon
	arena.desert_variant = "canyon"
	arena.generate_arena()
	var ground_tiles = arena.get_node_or_null("GroundTiles")
	_check(ground_tiles != null, "GroundTiles container created")
	var has_canyon := ground_tiles.has_node("DesertChasmModel") or ground_tiles.has_node("TerrainSurface")
	_check(has_canyon, "Desert Canyon ground spawned successfully")

	arena.queue_free()
	await get_tree().process_frame

	# 6. Test actual Arena Generation for Mountains
	GlobalData.board.combat_tile_sub_zone = "desert_mountains"
	var arena_mountain = ArenaGenClass.new()
	arena_mountain.current_theme = ArenaGenClass.BiomeTheme.DESERT
	arena_mountain.arena_size = 240.0
	add_child(arena_mountain)
	var mtn_ground = arena_mountain.get_node_or_null("GroundTiles")
	var has_mtn := mtn_ground != null and (mtn_ground.has_node("DesertMountainsModel") or mtn_ground.has_node("TerrainSurface"))
	_check(has_mtn, "Desert Mountains ground spawned successfully")
	arena_mountain.queue_free()
	await get_tree().process_frame

	# 7. Test actual Arena Generation for Dunes
	GlobalData.board.combat_tile_sub_zone = "desert_dunes"
	var arena_dunes = ArenaGenClass.new()
	arena_dunes.current_theme = ArenaGenClass.BiomeTheme.DESERT
	arena_dunes.arena_size = 240.0
	add_child(arena_dunes)
	var dunes_ground = arena_dunes.get_node_or_null("GroundTiles")
	_check(dunes_ground != null and dunes_ground.has_node("TerrainSurface"), "Desert Dunes generated TerrainSurface")
	arena_dunes.queue_free()

	print("--- Desert 4-Variants Verification Finished ---")
	if _fails == 0:
		print("DESERT_ALL_OK: %d checks passed!" % _checks)
	else:
		printerr("DESERT_FAILURES: %d/%d checks failed!" % [_fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
