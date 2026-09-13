extends Node

## Verification test for Forest Waterfall & High Cliff Plateau variant.
## Run: godot --headless --path . res://tests/forest_waterfall_verify.tscn

var _checks := 0
var _fails := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("WATERFALL_OK: ", msg)
	else:
		_fails += 1
		printerr("WATERFALL_FAIL: ", msg)

func _ready() -> void:
	print("--- Running Forest Waterfall & Cliff Plateau Verification ---")
	GlobalData.board.board_theme_id = "forest"
	var ArenaGenClass = preload("res://scripts/arena/arena_generator.gd")
	var arena = ArenaGenClass.new()
	arena.current_theme = ArenaGenClass.BiomeTheme.FOREST
	arena.arena_size = 240.0
	add_child(arena)

	# 1. Test sub-zone resolution
	GlobalData.board.combat_tile_sub_zone = "forest_waterfall"
	_check(arena._resolve_forest_variant() == "waterfall", "Sub-zone forest_waterfall resolves to waterfall")

	GlobalData.board.combat_tile_sub_zone = "forest_river"
	_check(arena._resolve_forest_variant() == "river", "Sub-zone forest_river resolves to river")

	# 2. Test fallback randomization across tiles
	GlobalData.board.combat_tile_sub_zone = ""
	var seen: Dictionary = {}
	for i in range(20):
		GlobalData.board.current_tile = Vector2i(i * 3 + 1, i * 5 + 4)
		var v: String = arena._resolve_forest_variant()
		seen[v] = true
	_check(seen.has("waterfall") and seen.has("river"), "Alternates deterministically between waterfall and river")

	# 3. Test High Plateau elevation (North, wz < -30)
	arena.forest_variant = "waterfall"
	var plateau_h: float = arena._get_terrain_height(30.0, -60.0)
	_check(plateau_h > 20.0, "High Mountain Plateau rises above +20m (height = %.2fm)" % plateau_h)

	# 4. Test Lower Valley elevation (South, wz > 25)
	var valley_h: float = arena._get_terrain_height(30.0, 60.0)
	_check(valley_h >= -1.0 and valley_h < 3.0, "Lower Valley floor is walkable (height = %.2fm)" % valley_h)

	# 5. Test Waterfall plunge pool depression
	var pool_h: float = arena._get_terrain_height(0.0, 0.0)
	_check(pool_h < 0.0, "Waterfall plunge pool is sunken below water level (height = %.2fm)" % pool_h)

	# 6. Test Traversable West Mountain Ramp (incline < 28 degrees)
	var ramp_bot_y: float = arena._get_terrain_height(-50.0, 18.0)
	var ramp_top_y: float = arena._get_terrain_height(-50.0, -35.0)
	var dz: float = 18.0 - (-35.0)
	var dy: float = ramp_top_y - ramp_bot_y
	var angle_deg: float = rad_to_deg(atan(dy / dz))
	_check(angle_deg > 15.0 and angle_deg < 28.0, "West ramp has traversable ~22 degree incline (angle = %.1f deg, dy = %.1fm)" % [angle_deg, dy])

	# 7. Test Traversable East Mountain Ramp
	var east_bot_y: float = arena._get_terrain_height(50.0, 18.0)
	var east_top_y: float = arena._get_terrain_height(50.0, -35.0)
	var east_angle: float = rad_to_deg(atan((east_top_y - east_bot_y) / dz))
	_check(east_angle > 15.0 and east_angle < 28.0, "East ramp has traversable ~22 degree incline (angle = %.1f deg)" % east_angle)

	# 8. Test Arena Generation with Waterfall Variant
	arena.generate_arena()
	var terrain_node: Node = arena.tile_container.get_node_or_null("ForestWaterfallTerrain")
	_check(terrain_node != null, "ForestWaterfallTerrain mesh spawned in tile_container")

	# 9. Test Ground Collision
	var col_node: Node = arena.structures_container.get_node_or_null("ForestWaterfallCollision")
	var has_col: bool = col_node != null and (col_node is CollisionObject3D) and (col_node as CollisionObject3D).collision_layer == 2
	_check(has_col, "ForestWaterfallCollision created on collision_layer 2")

	# 10. Test Waterfall Cascade Visual Mesh
	var cascade: Node = arena.structures_container.get_node_or_null("WaterfallCascade")
	var has_cascade: bool = cascade != null and (cascade is MeshInstance3D) and ((cascade as MeshInstance3D).material_override is ShaderMaterial)
	_check(has_cascade, "WaterfallCascade mesh with animated water flow shader exists")

	# 11. Test Water Basin & Volume
	var basin: Node = arena.structures_container.get_node_or_null("ForestWaterfallBasin")
	var has_basin: bool = basin != null and basin.is_in_group("water_volume") and (basin is CollisionObject3D) and (basin as CollisionObject3D).collision_layer == 4
	_check(has_basin, "ForestWaterfallBasin created with layer 4 and water_volume group")

	# 12. Test Dense Overgrown Foliage & Clutter ("รกรุงรัง")
	var solid_obs: Array = get_tree().get_nodes_in_group("solid_obstacle")
	_check(solid_obs.size() >= 30, "Dense foliage & rocks spawned (found %d solid obstacles)" % solid_obs.size())

	# 13. Test Mist Spawner
	var mist0: Node = arena.structures_container.get_node_or_null("WaterfallMist0")
	_check(mist0 != null, "Waterfall spray mist spawned at plunge pool base")

	print("--- Forest Waterfall & Cliff Plateau Verification Finished ---")
	if _fails == 0:
		print("WATERFALL_ALL_OK: %d checks passed with 0 failures!" % _checks)
	else:
		printerr("WATERFALL_FAILURES: %d failures out of %d checks" % [_fails, _checks])

	get_tree().quit(0 if _fails == 0 else 1)
