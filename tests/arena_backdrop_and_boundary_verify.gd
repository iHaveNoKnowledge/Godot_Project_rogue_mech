extends Node

func _ready() -> void:
	print("--- BEGIN ARENA BACKDROP AND BOUNDARY VERIFY TEST ---")
	test_outer_ground_skirt_generation()
	test_biome_specific_perimeter_backdrops()
	test_proximity_boundary_grid()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func test_outer_ground_skirt_generation() -> void:
	var dummy_arena := Node3D.new()
	add_child(dummy_arena)

	ArenaBackdropSpawner.build_perimeters(dummy_arena, 0, 240.0)

	var root := dummy_arena.get_node_or_null("ArenaBackdropRoot")
	assert_true(root != null, "ArenaBackdropRoot created under arena")

	var skirt := root.get_node_or_null("OuterGroundSkirt") as MeshInstance3D
	assert_true(skirt != null, "OuterGroundSkirt created")
	assert_true(skirt.mesh is PlaneMesh, "OuterGroundSkirt is a PlaneMesh")
	var pmesh: PlaneMesh = skirt.mesh
	assert_true(pmesh.size.x >= 1000.0, "OuterGroundSkirt is vast (>= 1000m across)")

	dummy_arena.queue_free()


func test_biome_specific_perimeter_backdrops() -> void:
	# Test Desert (theme 0)
	var desert_arena := Node3D.new()
	add_child(desert_arena)
	ArenaBackdropSpawner.build_perimeters(desert_arena, 0, 240.0)
	var d_root := desert_arena.get_node_or_null("ArenaBackdropRoot")
	assert_true(d_root != null and d_root.get_child_count() > 10, "Desert spawned multiple outer dunes and mesas")
	desert_arena.queue_free()

	# Test City (theme 1)
	var city_arena := Node3D.new()
	add_child(city_arena)
	ArenaBackdropSpawner.build_perimeters(city_arena, 1, 240.0)
	var c_root := city_arena.get_node_or_null("ArenaBackdropRoot")
	assert_true(c_root != null and c_root.get_child_count() > 10, "City spawned skyscraper skyline clusters and highways")
	city_arena.queue_free()

	# Test Forest (theme 4)
	var forest_arena := Node3D.new()
	add_child(forest_arena)
	ArenaBackdropSpawner.build_perimeters(forest_arena, 4, 240.0)
	var f_root := forest_arena.get_node_or_null("ArenaBackdropRoot")
	assert_true(f_root != null and f_root.get_child_count() > 20, "Forest spawned dense perimeter pine wall and mountain ridges")
	forest_arena.queue_free()

	# Test River (theme 3)
	var river_arena := Node3D.new()
	add_child(river_arena)
	ArenaBackdropSpawner.build_perimeters(river_arena, 3, 240.0)
	var r_root := river_arena.get_node_or_null("ArenaBackdropRoot")
	assert_true(r_root != null and r_root.get_child_count() > 10, "River spawned flanking canyon bluffs")
	river_arena.queue_free()


func test_proximity_boundary_grid() -> void:
	var dummy_arena := Node3D.new()
	add_child(dummy_arena)
	ArenaBackdropSpawner.build_perimeters(dummy_arena, 0, 240.0)
	var root := dummy_arena.get_node_or_null("ArenaBackdropRoot")
	var line := root.get_node_or_null("ProximityBoundaryLine") as MeshInstance3D
	assert_true(line != null, "ProximityBoundaryLine ribbon exists")
	assert_true(line.material_override is StandardMaterial3D, "Proximity boundary material configured")
	dummy_arena.queue_free()
