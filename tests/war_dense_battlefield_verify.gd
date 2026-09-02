extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("=== Starting War Mode Dense Battlefield Environment Verification ===")
	_test_military_outpost_components()
	_test_frontline_ruins_components()
	_test_wrecked_mecha_components()
	_test_industrial_pipeline_components()
	_test_war_world_dense_environment_integration()

	print("=== Dense Battlefield Environment Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_DENSE_BATTLEFIELD_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("DENSE_ENV_OK: %s" % label)
	else:
		_failed += 1
		push_error("DENSE_ENV_FAIL: %s" % label)


func _test_military_outpost_components() -> void:
	var world := Node3D.new()
	add_child(world)

	var outpost = WarBiomeGenerator.spawn_military_outpost(world, Vector3(0, 0, -400), true)
	_assert(outpost != null, "spawn_military_outpost returned valid Node3D")

	var bunker = outpost.get_node_or_null("CommandBunker")
	_assert(bunker != null and bunker is StaticBody3D, "Outpost has CommandBunker StaticBody3D")
	_assert(bunker.collision_layer == 2, "CommandBunker has collision_layer 2 (environment)")
	_assert(bunker.is_in_group("solid_obstacle"), "CommandBunker is marked as solid_obstacle")

	var tower = outpost.get_node_or_null("Watchtower")
	_assert(tower != null and tower is StaticBody3D, "Outpost has elevated Watchtower")
	var tower_light_found := false
	for c in tower.get_children():
		if c is OmniLight3D:
			tower_light_found = true
			break
	_assert(tower_light_found, "Watchtower has amber beacon OmniLight3D")

	var mast = outpost.get_node_or_null("RadarMast")
	_assert(mast != null and mast is StaticBody3D, "Outpost has RadarMast antenna")

	var cover_count: int = 0
	for child in outpost.get_children():
		if child.is_in_group("cover"):
			cover_count += 1

	_assert(cover_count >= 8, "Outpost has sandbag barricades, steel barriers, and crates (got %d)" % cover_count)

	world.queue_free()


func _test_frontline_ruins_components() -> void:
	var world := Node3D.new()
	add_child(world)

	var ruins = WarBiomeGenerator.spawn_frontline_ruins(world, Vector3(0, 0, 0), 35.0)
	_assert(ruins != null, "spawn_frontline_ruins returned valid Node3D")

	var building = ruins.get_node_or_null("CollapsedBuilding")
	_assert(building != null and building is StaticBody3D, "Frontline ruins has CollapsedBuilding")
	_assert(building.collision_layer == 2, "CollapsedBuilding has collision_layer 2")
	_assert(building.is_in_group("solid_obstacle"), "CollapsedBuilding is marked as solid_obstacle")

	var dragons_teeth_count: int = 0
	var sandbag_trench_count: int = 0
	var wreck_found: bool = false

	for child in ruins.get_children():
		if child is StaticBody3D:
			if child.name == "WreckedMecha":
				wreck_found = true
			elif child.find_child("PrismMesh", true, false) != null or child.position.z >= 14.0:
				dragons_teeth_count += 1
		if child.is_in_group("cover") and child.get("cover_type") == "sandbag":
			sandbag_trench_count += 1

	_assert(wreck_found, "Frontline ruins contains a smoldering WreckedMecha")
	_assert(sandbag_trench_count >= 4, "Frontline ruins contains trench sandbag parapets (got %d)" % sandbag_trench_count)
	_assert(dragons_teeth_count >= 4, "Frontline ruins contains anti-tank Dragon's Teeth (got %d)" % dragons_teeth_count)

	world.queue_free()


func _test_wrecked_mecha_components() -> void:
	var world := Node3D.new()
	add_child(world)

	var wreck = WarBiomeGenerator.spawn_wrecked_mecha(world, Vector3(50, 0, 50), 0.5)
	_assert(wreck != null and wreck is StaticBody3D, "spawn_wrecked_mecha created StaticBody3D")
	_assert(wreck.collision_layer == 2, "WreckedMecha has collision_layer 2")
	_assert(wreck.is_in_group("solid_obstacle"), "WreckedMecha is solid_obstacle")
	_assert(wreck.is_in_group("wreckage"), "WreckedMecha is in 'wreckage' group")
	var wreck_light_found := false
	for c in wreck.get_children():
		if c is OmniLight3D:
			wreck_light_found = true
			break
	_assert(wreck_light_found, "WreckedMecha has smoldering core glow OmniLight3D")

	world.queue_free()


func _test_industrial_pipeline_components() -> void:
	var world := Node3D.new()
	add_child(world)

	var pipe = WarBiomeGenerator.spawn_industrial_pipeline(world, Vector3(0, 0, 0), Vector3(60, 0, 0))
	_assert(pipe != null, "spawn_industrial_pipeline returned valid Node3D")

	var silo = pipe.get_node_or_null("FuelSilo")
	_assert(silo != null and silo is StaticBody3D, "Pipeline has FuelSilo at terminus")
	_assert(silo.collision_layer == 2, "FuelSilo has collision_layer 2")

	var pipe_segs: int = 0
	var piers: int = 0
	for child in pipe.get_children():
		if child is StaticBody3D and child != silo:
			pipe_segs += 1

	_assert(pipe_segs >= 4, "Pipeline created elevated cylindrical pipe segments and concrete piers (got %d)" % pipe_segs)

	world.queue_free()


func _test_war_world_dense_environment_integration() -> void:
	var world_scene = load("res://scenes/war/war_world.tscn")
	_assert(world_scene != null, "war_world.tscn loaded")

	var world = world_scene.instantiate()
	add_child(world)

	# Search all children recursively
	var outposts: Array[Node] = []
	var ruins: Array[Node] = []
	var pipelines: Array[Node] = []
	var wrecks: Array[Node] = []

	for node in world.find_children("*", "", true, false):
		if node.name.begins_with("MilitaryOutpost_"):
			outposts.append(node)
		elif node.name.begins_with("FrontlineRuins_"):
			ruins.append(node)
		elif node.name.begins_with("IndustrialPipeline_"):
			pipelines.append(node)
		elif node.name == "WreckedMecha":
			wrecks.append(node)

	_assert(outposts.size() == 4, "World spawned 4 tactical Military Outposts at Z=±420 (got %d)" % outposts.size())
	_assert(ruins.size() == 6, "World spawned 6 contested Frontline Ruins across No Man's Land (got %d)" % ruins.size())
	_assert(pipelines.size() >= 2, "World spawned industrial pipeline networks connecting canyons (got %d)" % pipelines.size())
	_assert(wrecks.size() >= 10, "World spawned smoldering Wrecked Mecha frames across battlefield (got %d)" % wrecks.size())

	# Verify ChunkLoader parenting
	var loader = world.get_node_or_null("ChunkLoader") as WarChunkLoader
	_assert(loader != null, "ChunkLoader exists in WarWorld")

	var chunk_children_count: int = 0
	for c in loader.get_children():
		chunk_children_count += c.get_child_count()

	_assert(chunk_children_count >= 15, "ChunkLoader contains chunked environment objects (got %d)" % chunk_children_count)

	world.queue_free()
