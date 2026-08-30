extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	print("=== Running Destructible Skyscraper & Tile Corner Verification ===")
	_test_tile_building_corner_placement()
	_test_destructible_building_damage_and_collapse()
	_test_skyscraper_arena_generation()

	print("\n=== Test Results: %d Passed, %d Failed ===" % [passed, failed])
	if failed == 0:
		print("ALL_DESTRUCTIBLE_SKYSCRAPER_TESTS_PASSED")
	else:
		push_error("Some tests failed!")
	get_tree().quit(0 if failed == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[PASS] %s" % msg)
	else:
		failed += 1
		print("[FAIL] %s" % msg)
		push_error("Assertion failed: %s" % msg)


func _test_tile_building_corner_placement() -> void:
	var tile_scene = load("res://scenes/board/board_tile.tscn")
	var tile = tile_scene.instantiate()
	tile.set_meta("tile_type", "city")
	tile.set_meta("terrain", "plain")
	add_child(tile)

	var poi_node = tile.get_node_or_null("POIVisual")
	_assert(poi_node != null, "Tile creates POIVisual for city")

	var found_corner := false
	if poi_node:
		for child in poi_node.get_children():
			if child is Node3D and child.position.x > 0.5 and child.position.z < -0.5:
				found_corner = true
				break
	_assert(found_corner, "City building model sits near corner/edge (X > 0.5, Z < -0.5) keeping tile center clear")

	tile.queue_free()


func _test_destructible_building_damage_and_collapse() -> void:
	var DestructibleBuildingScript = preload("res://scripts/arena/destructible_building.gd")
	var building = DestructibleBuildingScript.new()
	var mat = StandardMaterial3D.new()
	building.setup_building(Vector3(18, 40, 18), mat, 100.0)
	add_child(building)

	_assert(building.current_hp == 100.0, "Building initialized with 100 HP")
	_assert(not building.is_destroyed, "Building starts intact")

	# 1. Kinetic damage
	building.take_damage(30.0, "kinetic")
	_assert(building.current_hp == 70.0, "Kinetic weapon deals 30 damage (70 HP left)")

	# 2. Explosive structural bonus damage (1.8x)
	building.take_damage(40.0, "explosive")
	# 40 * 1.8 = 72 damage -> current_hp = -2 -> collapses
	_assert(building.is_destroyed, "Explosive damage triggers building collapse")

	building.queue_free()


func _test_skyscraper_arena_generation() -> void:
	GlobalData.reset_run_data()
	GlobalData.board.board_theme_id = "urban"
	GlobalData.board.combat_tile_terrain = "plain"

	var arena_gen_script = load("res://scripts/arena/arena_generator.gd")
	var arena_gen = arena_gen_script.new()
	add_child(arena_gen)

	_assert(arena_gen.current_theme == 1, "Arena current_theme resolved to CITY_HIGHRISE (1)")

	var struct_container = arena_gen.get_node_or_null("ThemeStructures")
	_assert(struct_container != null, "ThemeStructures container created")

	var sky_city = struct_container.get_node_or_null("SkyscraperCity")
	_assert(sky_city != null, "SkyscraperCity cluster node created")

	var destructible_count := 0
	if sky_city:
		for child in sky_city.get_children():
			if child.is_in_group("destructible_building"):
				destructible_count += 1
	_assert(destructible_count >= 10, "Generated dense cluster of %d destructible skyscrapers" % destructible_count)

	arena_gen.queue_free()
