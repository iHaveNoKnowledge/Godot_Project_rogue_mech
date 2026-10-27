extends Node3D

func _ready() -> void:
	print("--- BEGIN HARBOR COMBAT MAP VERIFICATION ---")
	
	# 1. Verify all 3D assets exist
	var required_assets = [
		"res://assets/models/harbor/harbor_cargo_ship.glb",
		"res://assets/models/harbor/harbor_gantry_crane.glb",
		"res://assets/models/harbor/harbor_warehouse.glb",
		"res://assets/models/harbor/harbor_freight_train.glb",
		"res://assets/models/harbor/harbor_pipeline.glb",
		"res://assets/models/harbor/harbor_container_modular.glb"
	]
	for path in required_assets:
		assert(ResourceLoader.exists(path), "Asset must exist: " + path)
		print("[PASS] Asset verified: ", path)
	
	# 2. Verify HarborMapBuilder script
	var builder_script = load("res://scripts/arena/harbor_map_builder.gd")
	assert(builder_script != null, "HarborMapBuilder must load")
	print("[PASS] HarborMapBuilder script loaded successfully.")
	
	# 3. Instantiate harbor map scene
	var map_scene = load("res://scenes/maps/harbor_combat_map.tscn") as PackedScene
	assert(map_scene != null, "Harbor combat map scene must load")
	var map_instance = map_scene.instantiate() as Node3D
	assert(map_instance != null, "Harbor combat map must instantiate")
	add_child(map_instance)
	print("[PASS] Harbor combat map scene instantiated.")
	
	# Wait one frame for _ready() and build_harbor_map() to execute
	await get_tree().process_frame
	
	# 4. Verify map structure
	var builder = map_instance.get_node_or_null("HarborMapBuilder")
	assert(builder != null, "HarborMapBuilder node must exist")
	
	var piers = builder.get_node_or_null("PiersRoot")
	assert(piers != null, "PiersRoot must exist")
	assert(piers.has_node("East_Pier"), "East_Pier must exist")
	assert(piers.has_node("West_Pier"), "West_Pier must exist")
	print("[PASS] Piers & Docks verified.")
	
	var basin = builder.get_node_or_null("BasinRoot")
	assert(basin != null, "BasinRoot must exist")
	assert(basin.has_node("WaterSurface"), "WaterSurface must exist")
	print("[PASS] Harbor Basin & Water verified.")
	
	assert(builder.has_node("Cargo_Ship"), "Cargo_Ship must be instantiated")
	print("[PASS] Cargo Container Ship verified.")
	
	assert(builder.has_node("Gantry_Crane_1"), "Gantry_Crane_1 must exist")
	assert(builder.has_node("Gantry_Crane_2"), "Gantry_Crane_2 must exist")
	print("[PASS] Container Gantry Cranes verified.")
	
	assert(builder.has_node("Freight_Train_1"), "Freight train must exist")
	assert(builder.has_node("Industrial_Warehouse_NE"), "Warehouse must exist")
	assert(builder.has_node("Industrial_Pipeline_1"), "Pipeline must exist")
	print("[PASS] Freight Train, Warehouses, and Pipelines verified.")
	
	var containers = builder.get_node_or_null("TacticalContainers")
	assert(containers != null and containers.get_child_count() > 0, "Tactical containers must exist")
	print("[PASS] Tactical Container Bunkers verified: count = %d" % containers.get_child_count())
	
	# 5. Verify Player Mecha and Enemy Dummies
	var player = map_instance.get_node_or_null("Mecha")
	assert(player != null, "Player Mecha must exist")
	assert(player.is_in_group("player"), "Mecha must be in player group")
	print("[PASS] Player Mecha verified.")
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	assert(enemies.size() >= 3, "At least 3 enemy mechas must be spawned")
	print("[PASS] Tactical Enemy Dummies verified: count = %d" % enemies.size())
	
	print("--- HARBOR COMBAT MAP VERIFICATION SUCCESSFUL ---")
	get_tree().quit(0)
