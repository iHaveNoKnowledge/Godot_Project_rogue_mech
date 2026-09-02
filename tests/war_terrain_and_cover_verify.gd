extends Node

func _ready() -> void:
	print("=== Starting War Mode 3-Tier Terrain & Biome Cover Verification ===")
	_test_height_function_tiers()
	_test_ramp_connectivity()
	_test_chunked_heightmap_generation()
	_test_biome_scatter_and_cover()
	_test_cover_damage_and_ramming()
	_test_war_world_integration()
	print("=== War Mode 3-Tier Terrain & Biome Cover Finished: ALL TESTS PASSED ===")
	get_tree().quit(0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		printerr("TEST FAILED: ", msg)
		push_error(msg)
		get_tree().quit(1)
	else:
		print("WAR_TERRAIN_OK: ", msg)


func _test_height_function_tiers() -> void:
	# 1. Base locations must be flat (Y approx 0)
	var friendly_h := WarBiomeGenerator.get_ground_height(0.0, -800.0)
	var enemy_h := WarBiomeGenerator.get_ground_height(0.0, 800.0)
	_assert(absf(friendly_h) < 0.5, "Friendly base at (0, -800) is flat: Y = %.2f" % friendly_h)
	_assert(absf(enemy_h) < 0.5, "Enemy base at (0, 800) is flat: Y = %.2f" % enemy_h)

	# 2. Low ground: River Canyon and Desert Sunken Quarry
	var river_h := WarBiomeGenerator.get_ground_height(210.0, -250.0)
	_assert(river_h <= -8.0, "River canyon floor is deep low ground: Y = %.2f (expected <= -8.0)" % river_h)

	var quarry_h := WarBiomeGenerator.get_ground_height(-500.0, -435.0)
	_assert(quarry_h <= -7.0, "Desert quarry floor is sunken low ground: Y = %.2f (expected <= -7.0)" % quarry_h)

	# 3. High ground: Mesas and Plateaus (Y >= +18.0)
	var mesa1_h := WarBiomeGenerator.get_ground_height(-450.0, -100.0)
	_assert(mesa1_h >= 18.0, "Mesa 1 plateau top is high ground: Y = %.2f (expected >= 18.0)" % mesa1_h)

	var mesa2_h := WarBiomeGenerator.get_ground_height(520.0, -250.0)
	_assert(mesa2_h >= 17.0, "Mesa 2 plateau top is high ground: Y = %.2f (expected >= 17.0)" % mesa2_h)

	var mesa4_h := WarBiomeGenerator.get_ground_height(480.0, 380.0)
	_assert(mesa4_h >= 20.0, "Mesa 4 River Bluff is high ground: Y = %.2f (expected >= 20.0)" % mesa4_h)


func _test_ramp_connectivity() -> void:
	# Mesa 1 Ramp connects -310 (ground) to -390 (mesa top) along X at Z = -100
	var h_ground := WarBiomeGenerator.get_ground_height(-310.0, -100.0)
	var h_mid := WarBiomeGenerator.get_ground_height(-350.0, -100.0)
	var h_top := WarBiomeGenerator.get_ground_height(-390.0, -100.0)

	_assert(h_mid > h_ground and h_mid < h_top,
		"Mesa ramp has continuous intermediate slope: ground=%.2f < mid=%.2f < top=%.2f" % [h_ground, h_mid, h_top])

	# River canyon ramp connects mid-ground to riverbed along X around Z = -450
	var h_canyon_top := WarBiomeGenerator.get_ground_height(120.0, -450.0)
	var h_canyon_mid := WarBiomeGenerator.get_ground_height(160.0, -450.0)
	var h_canyon_bot := WarBiomeGenerator.get_ground_height(200.0, -450.0)

	_assert(h_canyon_mid < h_canyon_top and h_canyon_mid > h_canyon_bot,
		"Canyon ramp has continuous descending slope: top=%.2f > mid=%.2f > bot=%.2f" % [h_canyon_top, h_canyon_mid, h_canyon_bot])


func _test_chunked_heightmap_generation() -> void:
	var root := Node3D.new()
	add_child(root)
	WarBiomeGenerator.build_biome_ground(root, 1337)

	var chunk_count := 0
	var valid_heightmaps := 0
	var valid_meshes := 0

	for child in root.get_children():
		if child is StaticBody3D and child.name.begins_with("TerrainChunk"):
			chunk_count += 1
			for sub in child.get_children():
				if sub is CollisionShape3D and sub.shape is HeightMapShape3D:
					var hms: HeightMapShape3D = sub.shape as HeightMapShape3D
					if hms.map_width == 51 and hms.map_depth == 51 and hms.map_data.size() == 2601:
						valid_heightmaps += 1
				elif sub is MeshInstance3D and sub.mesh is ArrayMesh:
					valid_meshes += 1

	_assert(chunk_count == 16, "Generated 16 terrain chunks (got %d)" % chunk_count)
	_assert(valid_heightmaps == 16, "All 16 chunks have valid 51x51 HeightMapShape3D colliders (got %d)" % valid_heightmaps)
	_assert(valid_meshes == 16, "All 16 chunks have valid SurfaceTool ArrayMeshes (got %d)" % valid_meshes)
	root.queue_free()


func _test_biome_scatter_and_cover() -> void:
	var root := Node3D.new()
	add_child(root)
	WarBiomeGenerator.populate_biome_scatter(root, 1337)

	var solid_count := 0
	var cover_count := 0
	var cover_types: Dictionary = {}

	for node in root.find_children("*", "", true, false):
		if node.is_in_group("solid_obstacle"):
			solid_count += 1
		if node.is_in_group("cover"):
			cover_count += 1
			var ctype: String = node.get("cover_type") if node.get("cover_type") != null else "unknown"
			cover_types[ctype] = cover_types.get(ctype, 0) + 1

	_assert(solid_count >= 5, "Spawned %d indestructible landmark solid obstacles" % solid_count)
	_assert(cover_count >= 40, "Spawned %d tactical cover objects across biomes" % cover_count)
	_assert(cover_types.has("sandbag") or cover_types.has("sandstone_spire"), "Spawned desert tactical cover")
	_assert(cover_types.has("barrier") or cover_types.has("container"), "Spawned urban tactical cover")
	_assert(cover_types.has("tree") or cover_types.has("boulder"), "Spawned forest/river tactical cover")
	root.queue_free()


func _test_cover_damage_and_ramming() -> void:
	var CoverScript = load("res://scripts/arena/cover_object.gd")
	var cover = CoverScript.new()
	cover.max_hp = 200.0
	cover.current_hp = 200.0
	cover.armor_class = 1.0
	add_child(cover)

	# 1. Weapon damage
	cover.take_damage(50.0, "kinetic")
	_assert(cover.current_hp <= 150.0, "Cover took kinetic weapon damage (HP: %.1f)" % cover.current_hp)

	# 2. Mecha ramming
	_assert(cover.has_method("ram_by_mecha"), "Cover has ram_by_mecha method")
	cover.ram_by_mecha(20.0)
	_assert(cover.current_hp <= 0.0 or cover.is_queued_for_deletion(), "Heavy Mecha ram breached and destroyed cover")
	if is_instance_valid(cover) and not cover.is_queued_for_deletion():
		cover.queue_free()


func _test_war_world_integration() -> void:
	var world_scene = load("res://scenes/war/war_world.tscn")
	_assert(world_scene != null, "war_world.tscn loaded successfully")
	var world = world_scene.instantiate()
	add_child(world)

	var ground = world.get_node_or_null("Ground")
	_assert(ground != null, "Ground node exists in war_world")

	# Verify no legacy flat 2000x2000 box collision left on Ground
	var legacy_flat_box := false
	for child in ground.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var b := child.shape as BoxShape3D
			if b.size.x > 1000.0:
				legacy_flat_box = true
	_assert(not legacy_flat_box, "Legacy flat 2000x2000 box collision was cleanly purged")

	# Verify BiomeRoot exists and contains TerrainChunks
	var biome_root = ground.get_node_or_null("BiomeRoot")
	_assert(biome_root != null, "BiomeRoot exists on Ground")

	var chunk_count := 0
	for c in biome_root.get_children():
		if c.name.begins_with("TerrainChunk"):
			chunk_count += 1
	_assert(chunk_count == 16, "World instantiated 16 chunked heightmap terrains (got %d)" % chunk_count)

	# Verify OreNodes exist and some are located in low ground
	var ore_nodes := get_tree().get_nodes_in_group("ore_node")
	_assert(ore_nodes.size() >= 8, "Found %d ore/oil nodes in war world" % ore_nodes.size())

	var low_ground_ores := 0
	for o in ore_nodes:
		if (o as Node3D).global_position.y < -4.0:
			low_ground_ores += 1
	_assert(low_ground_ores >= 2, "Found %d ore nodes tucked inside canyons/quarries" % low_ground_ores)

	# Verify Ground Mesh normals point UP and cull_mode is CULL_DISABLED
	var first_chunk = biome_root.get_node_or_null("TerrainChunk_0_0")
	_assert(first_chunk != null, "Found TerrainChunk_0_0")
	if first_chunk:
		var mi = first_chunk.get_node_or_null("TerrainMesh") as MeshInstance3D
		_assert(mi != null and mi.mesh != null, "TerrainMesh exists on chunk")
		var mat = mi.material_override as StandardMaterial3D
		_assert(mat != null and mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "Terrain material has CULL_DISABLED for full visibility")
		var arrays = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_assert(normals.size() > 0 and normals[0].y > 0.5, "Terrain mesh normals point upwards (normal.y = %.2f)" % normals[0].y)

	# Verify Player Mecha is spawned on ground (not floating)
	var player_mecha = world.get_node_or_null("Mecha") as CharacterBody3D
	_assert(player_mecha != null, "Player Mecha node exists")
	_assert(player_mecha.position.y < 0.2, "Player Mecha is grounded (position.y = %.2f)" % player_mecha.position.y)
	_assert(player_mecha.is_in_group("player"), "Player Mecha has 'player' group")

	# Verify Friendly AI Squad Mechas are spawned with ally_dummy AI (NOT player mecha controller)
	var allies := get_tree().get_nodes_in_group("ally")
	var ally_mechas: Array = []
	for a in allies:
		if a is CharacterBody3D and (a as Node).name.begins_with("AllyMecha"):
			ally_mechas.append(a)
	_assert(ally_mechas.size() >= 2, "Found %d friendly AI squad mechas" % ally_mechas.size())
	for a in ally_mechas:
		var script_path: String = a.get_script().resource_path if a.get_script() else ""
		_assert(script_path.contains("ally_dummy"), "Ally mecha runs autonomous AI script (ally_dummy), not player controller")

	# Verify Realtime Hangar Customizer opens and allows live fitting on PartMeshManager
	var customizer = load("res://scripts/war/war_realtime_customizer.gd").new()
	customizer.mecha_ref = player_mecha
	world.add_child(customizer)
	_assert(customizer._panel != null, "WarRealtimeCustomizer built UI overlay")
	_assert(customizer._slot_button_container != null, "WarRealtimeCustomizer has slot button container")
	var pmm = player_mecha.get_node_or_null("PartMeshManager")
	_assert(pmm != null, "Player mecha has PartMeshManager")
	# Live equip a part
	customizer._equip_part("body", {"id": "body_002", "name": "Fortress Heavy Reactive", "slot": "body", "hp": 110, "armor": 75, "weight": 22})
	_assert(pmm.slot_meshes.has("body"), "PartMeshManager updated body slot live in realtime")
	customizer._close()

	world.queue_free()
