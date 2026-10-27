class_name HarborMapBuilder
extends Node3D

## HarborMapBuilder: Procedural and assembly builder for the Tactical Harbor Combat Arena
## Modeled after the tactical isometric dockyard reference image.

@export var build_on_ready: bool = true
@export var spawn_enemy_dummies: bool = true

# Asset paths
const SHIP_GLB_PATH = "res://assets/models/harbor/harbor_cargo_ship.glb"
const CRANE_GLB_PATH = "res://assets/models/harbor/harbor_gantry_crane.glb"
const WAREHOUSE_GLB_PATH = "res://assets/models/harbor/harbor_warehouse.glb"
const TRAIN_GLB_PATH = "res://assets/models/harbor/harbor_freight_train.glb"
const PIPELINE_GLB_PATH = "res://assets/models/harbor/harbor_pipeline.glb"
const CONTAINER_GLB_PATH = "res://assets/models/harbor/harbor_container_modular.glb"
const DUMMY_ENEMY_PATH = "res://scenes/mecha/enemy_dummy_full.tscn"

# Material cache
var _mat_concrete: StandardMaterial3D
var _mat_curb_hazard: Material
var _mat_water: Material
var _mat_asphalt: StandardMaterial3D
var _container_mats: Array[Material] = []

func _ready() -> void:
	if build_on_ready:
		build_harbor_map()

func build_harbor_map() -> void:
	_init_materials()
	_build_concrete_piers()
	_build_harbor_basin_and_water()
	_build_cargo_ship()
	_build_gantry_cranes()
	_build_rail_and_trains()
	_build_warehouses()
	_build_pipelines()
	_build_tactical_container_clusters()
	_build_quayside_bollards_and_lights()
	if spawn_enemy_dummies:
		_spawn_tactical_enemies()

func _init_materials() -> void:
	# 1. PBR Weathered Concrete Dock Floor (Triplanar 4K Cracked Concrete + Normal + AO)
	_mat_concrete = StandardMaterial3D.new()
	_mat_concrete.albedo_color = Color(0.72, 0.74, 0.76)
	_mat_concrete.roughness = 0.86
	_mat_concrete.metallic = 0.04
	_mat_concrete.metallic_specular = 0.30
	_mat_concrete.uv1_triplanar = true
	_mat_concrete.uv1_scale = Vector3(0.06, 0.06, 0.06)

	var concrete_diff_path := "res://resources/textures/cracked_concrete_02_diff_4k.jpg"
	if ResourceLoader.exists(concrete_diff_path):
		_mat_concrete.albedo_texture = load(concrete_diff_path)

	var norm_path := "res://resources/textures/road/normal.jpg"
	if ResourceLoader.exists(norm_path):
		_mat_concrete.normal_enabled = true
		_mat_concrete.normal_texture = load(norm_path)
		_mat_concrete.normal_scale = 1.25

	var rough_path := "res://resources/textures/road/pbr_asphalt_roughness.jpg"
	if ResourceLoader.exists(rough_path):
		_mat_concrete.roughness_texture = load(rough_path)

	var ao_path := "res://resources/textures/road/pbr_asphalt_ao.jpg"
	if ResourceLoader.exists(ao_path):
		_mat_concrete.ao_enabled = true
		_mat_concrete.ao_texture = load(ao_path)
		_mat_concrete.ao_light_affect = 0.50

	# 2. PBR Freight Yard Asphalt Floor
	_mat_asphalt = StandardMaterial3D.new()
	_mat_asphalt.roughness = 0.90
	_mat_asphalt.metallic = 0.02
	_mat_asphalt.uv1_triplanar = true
	_mat_asphalt.uv1_scale = Vector3(0.12, 0.12, 0.12)
	var asphalt_albedo := "res://resources/textures/road/pbr_asphalt_albedo.jpg"
	if ResourceLoader.exists(asphalt_albedo):
		_mat_asphalt.albedo_texture = load(asphalt_albedo)
	if ResourceLoader.exists(norm_path):
		_mat_asphalt.normal_enabled = true
		_mat_asphalt.normal_texture = load(norm_path)
		_mat_asphalt.normal_scale = 1.0

	# 3. Procedural Hazard Striped Curb (Yellow / Black 45-deg safety stripes + chips)
	var curb_shader := load("res://shaders/harbor_hazard_curb.gdshader") as Shader
	if curb_shader != null:
		var sm := ShaderMaterial.new()
		sm.shader = curb_shader
		sm.set_shader_parameter("yellow_color", Color(0.94, 0.76, 0.10))
		sm.set_shader_parameter("black_color", Color(0.12, 0.13, 0.14))
		sm.set_shader_parameter("stripe_scale", 1.8)
		sm.set_shader_parameter("wear_amount", 0.40)
		_mat_curb_hazard = sm
	else:
		_mat_curb_hazard = StandardMaterial3D.new()
		_mat_curb_hazard.albedo_color = Color(0.92, 0.76, 0.12)

	# 4. Realistic Maritime Water Shader (Dual wave scrolling normals + depth fade + shore foam)
	var water_shader := load("res://shaders/harbor_water.gdshader") as Shader
	if water_shader != null:
		var wm := ShaderMaterial.new()
		wm.shader = water_shader
		wm.set_shader_parameter("deep_water_color", Color(0.04, 0.14, 0.22, 0.95))
		wm.set_shader_parameter("shallow_water_color", Color(0.08, 0.32, 0.40, 0.88))
		wm.set_shader_parameter("foam_color", Color(0.88, 0.94, 0.98, 1.0))
		wm.set_shader_parameter("wave_scale", 6.0)
		wm.set_shader_parameter("wave_speed_1", 0.04)
		wm.set_shader_parameter("wave_speed_2", 0.025)
		wm.set_shader_parameter("roughness", 0.08)
		wm.set_shader_parameter("metallic", 0.85)
		if ResourceLoader.exists(norm_path):
			var ntex := load(norm_path)
			wm.set_shader_parameter("normal_map_1", ntex)
			wm.set_shader_parameter("normal_map_2", ntex)
		_mat_water = wm
	else:
		_mat_water = StandardMaterial3D.new()
		_mat_water.albedo_color = Color(0.08, 0.24, 0.35, 0.92)
		_mat_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# 5. Procedural Corrugated Container Materials (3D ribs + groove grime + rust drips)
	var cont_shader := load("res://shaders/harbor_corrugated_metal.gdshader") as Shader
	var colors := [
		Color(0.76, 0.22, 0.16), # Weathered Terracotta Red
		Color(0.16, 0.38, 0.65), # Port Logistics Cobalt Blue
		Color(0.12, 0.48, 0.45), # Maritime Teal
		Color(0.86, 0.48, 0.12), # Heavy Freight Orange
		Color(0.30, 0.45, 0.28)  # Military Storage Olive
	]
	_container_mats.clear()
	for c in colors:
		if cont_shader != null:
			var cm := ShaderMaterial.new()
			cm.shader = cont_shader
			cm.set_shader_parameter("container_color", c)
			cm.set_shader_parameter("rust_color", Color(0.48, 0.22, 0.12))
			cm.set_shader_parameter("grime_color", Color(0.10, 0.11, 0.12))
			cm.set_shader_parameter("rib_frequency", 18.0)
			cm.set_shader_parameter("rib_depth", 0.85)
			cm.set_shader_parameter("rust_amount", 0.35)
			cm.set_shader_parameter("edge_wear", 0.45)
			_container_mats.append(cm)
		else:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = c
			sm.roughness = 0.65
			_container_mats.append(sm)

# 1. Concrete Piers (East Quayside, West Pier, and South Apron)
func _build_concrete_piers() -> void:
	var piers_root = Node3D.new()
	piers_root.name = "PiersRoot"
	add_child(piers_root)

	# East Pier (Main dockyard: X from 0.0 to 110.0, Z from -100.0 to 100.0)
	_create_static_slab("East_Pier", piers_root, Vector3(55.0, -1.0, 0.0), Vector3(110.0, 2.0, 200.0), _mat_concrete)

	# West Pier (Across the water: X from -110.0 to -28.0, Z from -100.0 to 100.0)
	_create_static_slab("West_Pier", piers_root, Vector3(-69.0, -1.0, 0.0), Vector3(82.0, 2.0, 200.0), _mat_concrete)

	# South Apron (Connecting East and West pier at the end of the slip: X from -28.0 to 0.0, Z from 45.0 to 100.0)
	_create_static_slab("South_Apron", piers_root, Vector3(-14.0, -1.0, 72.5), Vector3(28.0, 2.0, 55.0), _mat_concrete)

	# Yellow Hazard Curbs along the basin edge (X=0.0, X=-28.0, Z=45.0)
	# East quayside curb
	_create_static_slab("Curb_East", piers_root, Vector3(0.4, 0.15, -27.5), Vector3(0.8, 0.3, 145.0), _mat_curb_hazard)
	# West quayside curb
	_create_static_slab("Curb_West", piers_root, Vector3(-28.4, 0.15, -27.5), Vector3(0.8, 0.3, 145.0), _mat_curb_hazard)
	# South basin end curb
	_create_static_slab("Curb_South", piers_root, Vector3(-14.0, 0.15, 45.4), Vector3(29.6, 0.3, 0.8), _mat_curb_hazard)

# 2. Harbor Basin & Water
func _build_harbor_basin_and_water() -> void:
	var basin_root = Node3D.new()
	basin_root.name = "BasinRoot"
	add_child(basin_root)

	# Water Surface (Width 28m, Length 150m, situated at Y = -2.2)
	var water_mesh = PlaneMesh.new()
	water_mesh.size = Vector2(28.0, 150.0)
	var water_mi = MeshInstance3D.new()
	water_mi.name = "WaterSurface"
	water_mi.mesh = water_mesh
	water_mi.material_override = _mat_water
	water_mi.position = Vector3(-14.0, -2.2, -25.0)
	basin_root.add_child(water_mi)

	# Basin concrete floor (Bed at Y = -8.0)
	_create_static_slab("Basin_Floor", basin_root, Vector3(-14.0, -8.5, -25.0), Vector3(28.0, 1.0, 150.0), _mat_asphalt)

	# Basin side vertical retaining walls (from Y=-8.0 to Y=0.0)
	# East retaining wall (at X=0.0)
	_create_static_slab("Wall_East", basin_root, Vector3(0.2, -4.0, -25.0), Vector3(0.4, 8.0, 150.0), _mat_concrete)
	# West retaining wall (at X=-28.0)
	_create_static_slab("Wall_West", basin_root, Vector3(-28.2, -4.0, -25.0), Vector3(0.4, 8.0, 150.0), _mat_concrete)
	# South retaining wall (at Z=45.0)
	_create_static_slab("Wall_South", basin_root, Vector3(-14.0, -4.0, 45.2), Vector3(28.0, 8.0, 0.4), _mat_concrete)

# 3. Cargo Container Ship
func _build_cargo_ship() -> void:
	if not ResourceLoader.exists(SHIP_GLB_PATH):
		push_warning("Ship GLB not found at " + SHIP_GLB_PATH)
		return

	var ship_scene = load(SHIP_GLB_PATH) as PackedScene
	if ship_scene == null:
		return

	var ship_inst = ship_scene.instantiate() as Node3D
	ship_inst.name = "Cargo_Ship"
	# Ship sits in the basin, stern facing backward (+Z), bow facing forward (-Z)
	# Water surface is Y = -2.2. Ship waterline sits at Y = -2.2.
	ship_inst.position = Vector3(-14.0, -2.2, -10.0)
	add_child(ship_inst)
	_enhance_model_pbr(ship_inst, 1.1, 0.52, 0.82)

	# Add StaticBody3D collision boundaries for the ship so players can walk on it
	var ship_col = StaticBody3D.new()
	ship_col.name = "Ship_Collision"
	ship_col.collision_layer = 2
	ship_col.collision_mask = 1
	ship_inst.add_child(ship_col)

	# Main Hull Deck collision
	_add_box_shape(ship_col, Vector3(0.0, 2.0, 0.0), Vector3(16.0, 4.0, 68.0))
	# Stern Superstructure collision
	_add_box_shape(ship_col, Vector3(0.0, 8.0, -25.0), Vector3(14.0, 8.0, 12.0))
	# Container Stacks in hold collision (Provides Height Advantage!)
	_add_box_shape(ship_col, Vector3(0.0, 4.5, 0.0), Vector3(12.0, 5.0, 32.0))

# 4. Gantry Cranes
func _build_gantry_cranes() -> void:
	if not ResourceLoader.exists(CRANE_GLB_PATH):
		return
	var crane_scene = load(CRANE_GLB_PATH) as PackedScene
	if crane_scene == null:
		return

	# Crane 1 (Fore dock)
	var crane1 = crane_scene.instantiate() as Node3D
	crane1.name = "Gantry_Crane_1"
	# Position along the East quay at X = 8.0, spanning over the quayside rails
	crane1.position = Vector3(8.0, 0.0, -25.0)
	# Boom extends towards -X (over the ship!)
	crane1.rotation.y = PI
	add_child(crane1)
	_enhance_model_pbr(crane1, 0.9, 0.45, 0.78)
	_add_crane_collision(crane1)

	# Crane 2 (Aft dock)
	var crane2 = crane_scene.instantiate() as Node3D
	crane2.name = "Gantry_Crane_2"
	crane2.position = Vector3(8.0, 0.0, 12.0)
	crane2.rotation.y = PI
	add_child(crane2)
	_enhance_model_pbr(crane2, 0.9, 0.45, 0.78)
	_add_crane_collision(crane2)

func _add_crane_collision(crane: Node3D) -> void:
	var col_body = StaticBody3D.new()
	col_body.name = "Crane_Collision"
	col_body.collision_layer = 2
	col_body.collision_mask = 1
	crane.add_child(col_body)

	# 4 Leg pillars (Feet at X=±7.0, Y=±4.5)
	for fx in [-7.0, 7.0]:
		for fy in [-4.5, 4.5]:
			_add_box_shape(col_body, Vector3(fx, 8.0, fy), Vector3(1.6, 16.0, 1.6))
	# Portal Header Beam (Height 16m)
	_add_box_shape(col_body, Vector3(0.0, 16.0, 0.0), Vector3(15.0, 2.0, 6.0))
	# Cantilever Boom (Height 18m)
	_add_box_shape(col_body, Vector3(3.5, 18.5, 0.0), Vector3(28.0, 3.0, 4.0))

# 5. Railway Tracks & Freight Train
func _build_rail_and_trains() -> void:
	if not ResourceLoader.exists(TRAIN_GLB_PATH):
		return
	var train_scene = load(TRAIN_GLB_PATH) as PackedScene
	if train_scene == null:
		return

	# Train Line 1 (Closest to dock at X = 4.5)
	var train1 = train_scene.instantiate() as Node3D
	train1.name = "Freight_Train_1"
	train1.position = Vector3(4.5, 0.0, -42.0)
	add_child(train1)
	_enhance_model_pbr(train1, 1.2, 0.65, 0.88)
	_add_train_collision(train1)

	var train2 = train_scene.instantiate() as Node3D
	train2.name = "Freight_Train_2"
	train2.position = Vector3(4.5, 0.0, 32.0)
	add_child(train2)
	_enhance_model_pbr(train2, 1.2, 0.65, 0.88)
	_add_train_collision(train2)

	# Train Line 2 (Inland rail line at X = 18.0)
	var train3 = train_scene.instantiate() as Node3D
	train3.name = "Freight_Train_3"
	train3.position = Vector3(18.0, 0.0, -10.0)
	add_child(train3)
	_enhance_model_pbr(train3, 1.2, 0.65, 0.88)
	_add_train_collision(train3)

func _add_train_collision(train: Node3D) -> void:
	var col_body = StaticBody3D.new()
	col_body.name = "Train_Collision"
	col_body.collision_layer = 2
	col_body.collision_mask = 1
	train.add_child(col_body)
	# Flatcar deck + side bulkheads (Cover Low: ~1.4m high)
	_add_box_shape(col_body, Vector3(0.0, 0.7, 0.0), Vector3(3.0, 1.4, 14.0))

# 6. Industrial Warehouses
func _build_warehouses() -> void:
	if not ResourceLoader.exists(WAREHOUSE_GLB_PATH):
		return
	var wh_scene = load(WAREHOUSE_GLB_PATH) as PackedScene
	if wh_scene == null:
		return

	# Warehouse 1 (North-East corner of dockyard)
	var wh1 = wh_scene.instantiate() as Node3D
	wh1.name = "Industrial_Warehouse_NE"
	wh1.position = Vector3(42.0, 0.0, -45.0)
	add_child(wh1)
	_enhance_model_pbr(wh1, 1.1, 0.58, 0.82)
	_add_warehouse_collision(wh1)

	# Warehouse 2 (South-East depot)
	var wh2 = wh_scene.instantiate() as Node3D
	wh2.name = "Industrial_Warehouse_SE"
	wh2.position = Vector3(42.0, 0.0, 35.0)
	add_child(wh2)
	_enhance_model_pbr(wh2, 1.1, 0.58, 0.82)
	_add_warehouse_collision(wh2)

	# Warehouse 3 (West pier storage facility)
	var wh3 = wh_scene.instantiate() as Node3D
	wh3.name = "Industrial_Warehouse_West"
	wh3.position = Vector3(-65.0, 0.0, -20.0)
	wh3.rotation.y = PI * 0.5
	add_child(wh3)
	_enhance_model_pbr(wh3, 1.1, 0.58, 0.82)
	_add_warehouse_collision(wh3)

func _add_warehouse_collision(wh: Node3D) -> void:
	var col_body = StaticBody3D.new()
	col_body.name = "WH_Collision"
	col_body.collision_layer = 2
	col_body.collision_mask = 1
	wh.add_child(col_body)
	# Main warehouse hall (Width 24m, Length 32m, Height 12.5m)
	_add_box_shape(col_body, Vector3(0.0, 6.0, 0.0), Vector3(24.0, 12.0, 32.0))
	# Side office annex
	_add_box_shape(col_body, Vector3(14.5, 2.5, 6.0), Vector3(5.0, 5.0, 12.0))

# 7. Industrial Pipeline
func _build_pipelines() -> void:
	if not ResourceLoader.exists(PIPELINE_GLB_PATH):
		return
	var pipe_scene = load(PIPELINE_GLB_PATH) as PackedScene
	if pipe_scene == null:
		return

	# Pipeline running along the South-East edge (turning at the warehouse)
	var pipe1 = pipe_scene.instantiate() as Node3D
	pipe1.name = "Industrial_Pipeline_1"
	pipe1.position = Vector3(25.0, 0.0, 52.0)
	pipe1.rotation.y = PI * 0.5
	add_child(pipe1)
	_enhance_model_pbr(pipe1, 1.0, 0.40, 0.70)

	var col_body = StaticBody3D.new()
	col_body.name = "Pipe_Collision"
	col_body.collision_layer = 2
	col_body.collision_mask = 1
	pipe1.add_child(col_body)
	# Main pipe collision (Cover Low: 1.5m tall)
	_add_box_shape(col_body, Vector3(0.0, 0.75, 0.0), Vector3(1.6, 1.5, 18.0))

# 8. Tactical Shipping Container Stacks (Cover High & Cover Low)
func _build_tactical_container_clusters() -> void:
	var cont_root = Node3D.new()
	cont_root.name = "TacticalContainers"
	add_child(cont_root)

	# Container standard dimensions: 2.4m wide (half=1.2), 6.0m long (half=3.0), 2.6m high (half=1.3)
	# Cluster 1: Near Crane 2 (Center Dock chokepoint)
	_spawn_container_stack(cont_root, Vector3(12.0, 0.0, -2.0), 0.0, 2, 2)
	_spawn_container_stack(cont_root, Vector3(15.0, 0.0, -2.0), 0.0, 1, 1)

	# Cluster 2: Central quayside bunker (Forming the hexagon cover zone from the blueprint!)
	_spawn_container_stack(cont_root, Vector3(22.0, 0.0, -18.0), PI * 0.25, 2, 3)
	_spawn_container_stack(cont_root, Vector3(26.0, 0.0, -14.0), 0.0, 1, 2)

	# Cluster 3: South Pier near pipeline
	_spawn_container_stack(cont_root, Vector3(14.0, 0.0, 22.0), 0.0, 2, 2)
	_spawn_container_stack(cont_root, Vector3(17.0, 0.0, 22.0), 0.0, 1, 1)

	# Cluster 4: West Pier staging area
	_spawn_container_stack(cont_root, Vector3(-42.0, 0.0, -5.0), PI * 0.5, 2, 3)
	_spawn_container_stack(cont_root, Vector3(-42.0, 0.0, 15.0), 0.0, 1, 2)

func _spawn_container_stack(parent: Node3D, base_pos: Vector3, rot_y: float, tiers: int, count_x: int) -> void:
	var stack_node = Node3D.new()
	stack_node.position = base_pos
	stack_node.rotation.y = rot_y
	parent.add_child(stack_node)

	var col_body = StaticBody3D.new()
	col_body.name = "Stack_Col"
	col_body.collision_layer = 2
	col_body.collision_mask = 1
	col_body.add_to_group("cover")
	if tiers >= 2:
		col_body.add_to_group("cover_high")
	else:
		col_body.add_to_group("cover_low")
	stack_node.add_child(col_body)

	var c_w = 2.4
	var c_l = 6.0
	var c_h = 2.6

	for t in range(tiers):
		var zy = (t + 0.5) * c_h
		for x in range(count_x):
			var zx = (x - (count_x - 1) * 0.5) * (c_w + 0.1)
			var mi = MeshInstance3D.new()
			var bmesh = BoxMesh.new()
			bmesh.size = Vector3(c_w, c_h, c_l)
			mi.mesh = bmesh
			var mat_idx = (t * 2 + x + int(base_pos.x)) % _container_mats.size()
			mi.material_override = _container_mats[abs(mat_idx)]
			mi.position = Vector3(zx, zy, 0.0)
			col_body.add_child(mi)

			# Collision shape for each container
			_add_box_shape(col_body, Vector3(zx, zy, 0.0), Vector3(c_w, c_h, c_l))

# 9. Quayside Bollards & Light Poles
func _build_quayside_bollards_and_lights() -> void:
	var details_root = Node3D.new()
	details_root.name = "QuaysideDetails"
	add_child(details_root)

	var bollard_mesh = CylinderMesh.new()
	bollard_mesh.top_radius = 0.3
	bollard_mesh.bottom_radius = 0.35
	bollard_mesh.height = 0.8

	# Mooring bollards along East quay (X = 0.8m)
	for z in range(-80, 40, 15):
		var mi = MeshInstance3D.new()
		mi.mesh = bollard_mesh
		mi.material_override = _mat_curb_hazard
		mi.position = Vector3(1.2, 0.4, float(z))
		details_root.add_child(mi)

	# Industrial floodlight towers
	var light_spots = [
		Vector3(12.0, 0.0, -50.0),
		Vector3(12.0, 0.0, 0.0),
		Vector3(12.0, 0.0, 45.0),
		Vector3(-26.0, 0.0, -30.0),
		Vector3(-26.0, 0.0, 30.0)
	]
	for lpos in light_spots:
		_build_light_pole(details_root, lpos)

func _build_light_pole(parent: Node3D, pos: Vector3) -> void:
	var pole = Node3D.new()
	pole.position = pos
	parent.add_child(pole)

	# Pole mast
	var mast_mesh = CylinderMesh.new()
	mast_mesh.top_radius = 0.15
	mast_mesh.bottom_radius = 0.25
	mast_mesh.height = 12.0
	var mi = MeshInstance3D.new()
	mi.mesh = mast_mesh
	mi.material_override = _mat_asphalt
	mi.position = Vector3(0.0, 6.0, 0.0)
	pole.add_child(mi)

	# Floodlight fixture
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 2.5
	light.omni_range = 35.0
	light.position = Vector3(0.0, 12.0, 0.0)
	pole.add_child(light)

# 10. Tactical Enemy Spawns (Matching the 3 Mechas in the diagram)
func _spawn_tactical_enemies() -> void:
	if not ResourceLoader.exists(DUMMY_ENEMY_PATH):
		return
	var dummy_scene = load(DUMMY_ENEMY_PATH) as PackedScene
	if dummy_scene == null:
		return

	# MECHA-1: Positioned near the container stack (Cover Low)
	var e1 = dummy_scene.instantiate() as Node3D
	e1.name = "Enemy_Mecha_1"
	e1.position = Vector3(16.5, 0.0, 5.0)
	e1.rotation.y = -PI * 0.75
	e1.add_to_group("enemy")
	add_child(e1)

	# MECHA-2: Positioned near warehouse corner (Cover High)
	var e2 = dummy_scene.instantiate() as Node3D
	e2.name = "Enemy_Mecha_2"
	e2.position = Vector3(32.0, 0.0, -28.0)
	e2.rotation.y = PI * 0.25
	e2.add_to_group("enemy")
	add_child(e2)

	# MECHA-3: Positioned near the crane tracks
	var e3 = dummy_scene.instantiate() as Node3D
	e3.name = "Enemy_Mecha_3"
	e3.position = Vector3(6.0, 0.0, -32.0)
	e3.rotation.y = 0.0
	e3.add_to_group("enemy")
	add_child(e3)

# --- Helper Methods ---

func _create_static_slab(name: String, parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var sb = StaticBody3D.new()
	sb.name = name
	sb.position = pos
	sb.collision_layer = 2
	sb.collision_mask = 1
	parent.add_child(sb)

	var col = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	sb.add_child(col)

	var mi = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mi.mesh = box_mesh
	mi.material_override = mat
	sb.add_child(mi)
	return sb

func _add_box_shape(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	body.add_child(col)

func _enhance_model_pbr(root_node: Node3D, norm_scale: float = 1.0, min_roughness: float = 0.5, max_roughness: float = 0.85) -> void:
	var norm_path := "res://resources/textures/road/normal.jpg"
	var ntex: Texture2D = load(norm_path) if ResourceLoader.exists(norm_path) else null
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.name.begins_with("Ship_Crate") and not _container_mats.is_empty():
			var h := hash(mi.name)
			mi.material_override = _container_mats[abs(h) % _container_mats.size()]
			continue
		var active_mat := mi.get_active_material(0)
		if active_mat is StandardMaterial3D:
			var pbr := active_mat.duplicate() as StandardMaterial3D
			if ntex != null and not pbr.normal_enabled:
				pbr.normal_enabled = true
				pbr.normal_texture = ntex
				pbr.normal_scale = norm_scale
			pbr.roughness = clamp(pbr.roughness, min_roughness, max_roughness)
			pbr.metallic_specular = 0.35
			mi.material_override = pbr

