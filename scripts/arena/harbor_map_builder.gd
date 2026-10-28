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
const OFFICE_GLB_PATH = "res://assets/models/harbor/harbor_office_building.glb"
const TRAIN_GLB_PATH = "res://assets/models/harbor/harbor_freight_train.glb"
const PIPELINE_GLB_PATH = "res://assets/models/harbor/harbor_pipeline.glb"
const CONTAINER_GLB_PATH = "res://assets/models/harbor/harbor_container_modular.glb"
const SECURITY_GATE_GLB_PATH = "res://assets/models/harbor/harbor_security_gate.glb"
const CITY_BACKDROP_GLB_PATH = "res://assets/models/harbor/harbor_city_backdrop.glb"
const LIGHTHOUSE_GLB_PATH = "res://assets/models/harbor/harbor_breakwater_lighthouse.glb"
const DUMMY_ENEMY_PATH = "res://scenes/mecha/enemy_dummy_full.tscn"

# Material cache
var _mat_concrete: StandardMaterial3D
var _mat_curb_hazard: Material
var _mat_water: Material
var _mat_asphalt: StandardMaterial3D
var _mat_road_yellow_line: StandardMaterial3D
var _mat_road_white_line: StandardMaterial3D
var _mat_security_wall: StandardMaterial3D
var _container_mats: Array[Material] = []

func _ready() -> void:
	if build_on_ready:
		build_harbor_map()

func build_harbor_map() -> void:
	_init_materials()
	_build_concrete_piers()
	_build_harbor_basin_and_water()
	_build_open_ocean_extension()
	_build_cargo_ship()
	_build_gantry_cranes()
	_build_rail_and_trains()
	_build_warehouses()
	_build_office_buildings()
	_build_harbor_entrance_and_roads()
	_build_city_and_industrial_backdrop()
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

	# 4. Realistic Maritime Gerstner Fluid Water Shader
	var water_shader := load("res://shaders/harbor_gerstner_water.gdshader") as Shader
	if water_shader != null:
		var wm := ShaderMaterial.new()
		wm.shader = water_shader
		wm.set_shader_parameter("deep_color", Color(0.03, 0.10, 0.18, 0.95))
		wm.set_shader_parameter("shallow_color", Color(0.08, 0.36, 0.44, 0.82))
		wm.set_shader_parameter("foam_color", Color(0.92, 0.96, 1.0, 1.0))
		wm.set_shader_parameter("beer_law_factor", 0.35)
		wm.set_shader_parameter("refraction_strength", 0.035)
		wm.set_shader_parameter("wave_steepness", 0.30)
		wm.set_shader_parameter("time_speed", 1.0)
		wm.set_shader_parameter("roughness", 0.06)
		wm.set_shader_parameter("metallic", 0.85)
		if ResourceLoader.exists(norm_path):
			var ntex := load(norm_path)
			wm.set_shader_parameter("normal_bump_1", ntex)
			wm.set_shader_parameter("normal_bump_2", ntex)
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

	# 6. Road Markings & Security Perimeter Wall Materials
	_mat_road_yellow_line = StandardMaterial3D.new()
	_mat_road_yellow_line.albedo_color = Color(0.96, 0.78, 0.12)
	_mat_road_yellow_line.roughness = 0.5
	_mat_road_yellow_line.emission_enabled = true
	_mat_road_yellow_line.emission = Color(0.96, 0.78, 0.12)
	_mat_road_yellow_line.emission_energy_multiplier = 0.4

	_mat_road_white_line = StandardMaterial3D.new()
	_mat_road_white_line.albedo_color = Color(0.92, 0.94, 0.96)
	_mat_road_white_line.roughness = 0.5
	_mat_road_white_line.emission_enabled = true
	_mat_road_white_line.emission = Color(0.92, 0.94, 0.96)
	_mat_road_white_line.emission_energy_multiplier = 0.2

	_mat_security_wall = StandardMaterial3D.new()
	_mat_security_wall.albedo_color = Color(0.52, 0.55, 0.58)
	_mat_security_wall.roughness = 0.88
	_mat_security_wall.uv1_triplanar = true
	_mat_security_wall.uv1_scale = Vector3(0.08, 0.08, 0.08)
	if ResourceLoader.exists(norm_path):
		_mat_security_wall.normal_enabled = true
		_mat_security_wall.normal_texture = load(norm_path)
		_mat_security_wall.normal_scale = 1.0

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

	# Water Surface with Gerstner 3D Wave Tessellation (Optimized 30x50 subdivisions)
	var water_mesh = PlaneMesh.new()
	water_mesh.size = Vector2(28.0, 150.0)
	water_mesh.subdivide_width = 30
	water_mesh.subdivide_depth = 50
	var water_mi = MeshInstance3D.new()
	water_mi.name = "WaterSurface"
	water_mi.mesh = water_mesh
	water_mi.material_override = _mat_water
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mi.position = Vector3(-14.0, -2.2, -25.0)
	basin_root.add_child(water_mi)

	# Fluid Physics Area (Slows down walking in water and adds buoyancy/damping)
	var water_area = Area3D.new()
	water_area.name = "WaterFluidArea"
	water_area.position = Vector3(-14.0, -5.0, -25.0)
	water_area.linear_damp_space_override = Area3D.SPACE_OVERRIDE_COMBINE
	water_area.linear_damp = 4.0
	water_area.angular_damp_space_override = Area3D.SPACE_OVERRIDE_COMBINE
	water_area.angular_damp = 3.0
	var area_col = CollisionShape3D.new()
	var area_box = BoxShape3D.new()
	area_box.size = Vector3(28.0, 6.0, 150.0)
	area_col.shape = area_box
	water_area.add_child(area_col)
	basin_root.add_child(water_area)

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

	# Generate exact mesh collision for all parts of the ship (Fixes inverted collision permanently!)
	_generate_exact_collision_for_model(ship_inst)

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

# 6. Industrial Warehouses (With Walkable Interior)
func _build_warehouses() -> void:
	if not ResourceLoader.exists(WAREHOUSE_GLB_PATH):
		return
	var wh_scene = load(WAREHOUSE_GLB_PATH) as PackedScene
	if wh_scene == null:
		return

	# Warehouse 1 (North-East corner of dockyard)
	var wh1 = wh_scene.instantiate() as Node3D
	wh1.name = "Industrial_Warehouse_NE"
	wh1.position = Vector3(45.0, 0.0, -45.0)
	add_child(wh1)
	_enhance_model_pbr(wh1, 1.1, 0.58, 0.82)
	_generate_exact_collision_for_model(wh1)
	_add_warehouse_interior_lights(wh1)

	# Warehouse 2 (South-East depot)
	var wh2 = wh_scene.instantiate() as Node3D
	wh2.name = "Industrial_Warehouse_SE"
	wh2.position = Vector3(45.0, 0.0, 35.0)
	add_child(wh2)
	_enhance_model_pbr(wh2, 1.1, 0.58, 0.82)
	_generate_exact_collision_for_model(wh2)
	_add_warehouse_interior_lights(wh2)

	# Warehouse 3 (West pier storage facility)
	var wh3 = wh_scene.instantiate() as Node3D
	wh3.name = "Industrial_Warehouse_West"
	wh3.position = Vector3(-65.0, 0.0, -20.0)
	wh3.rotation.y = PI * 0.5
	add_child(wh3)
	_enhance_model_pbr(wh3, 1.1, 0.58, 0.82)
	_generate_exact_collision_for_model(wh3)
	_add_warehouse_interior_lights(wh3)

# 7. Harbor Office Buildings (2-Story Walkable Interior & Rooftop)
func _build_office_buildings() -> void:
	if not ResourceLoader.exists(OFFICE_GLB_PATH):
		return
	var off_scene = load(OFFICE_GLB_PATH) as PackedScene
	if off_scene == null:
		return

	# Office 1: Port Administration HQ (East Pier, near warehouse & cranes)
	var off1 = off_scene.instantiate() as Node3D
	off1.name = "Port_Authority_HQ"
	off1.position = Vector3(26.0, 0.0, -5.0)
	add_child(off1)
	_enhance_model_pbr(off1, 0.8, 0.45, 0.75)
	_generate_exact_collision_for_model(off1)
	_add_office_interior_lights(off1)

	# Office 2: West Pier Customs & Gatehouse
	var off2 = off_scene.instantiate() as Node3D
	off2.name = "Port_Customs_Gatehouse"
	off2.position = Vector3(-55.0, 0.0, 35.0)
	off2.rotation.y = PI
	add_child(off2)
	_enhance_model_pbr(off2, 0.8, 0.45, 0.75)
	_generate_exact_collision_for_model(off2)
	_add_office_interior_lights(off2)

# 8. Industrial Pipeline
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
	_generate_exact_collision_for_model(pipe1)

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
	light.light_energy = 2.4
	light.omni_range = 24.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 20.0
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

func _generate_exact_collision_for_model(root_node: Node3D, collision_layer: int = 2) -> void:
	var sb := StaticBody3D.new()
	sb.name = root_node.name + "_Compound_Col"
	sb.collision_layer = collision_layer
	sb.collision_mask = 1
	root_node.add_child(sb)

	var inv_root := root_node.global_transform.affine_inverse()

	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var lname := mi.name.to_lower()
		# Filter out decorative, elevated, or thin non-blocking meshes
		if (lname.find("glow") != -1 or lname.find("glass") != -1 or lname.find("window") != -1 
				or lname.find("light") != -1 or lname.find("beacon") != -1 or lname.find("truss") != -1 
				or lname.find("ac") != -1 or lname.find("spire") != -1):
			continue
		var trimesh_shape := mi.mesh.create_trimesh_shape()
		if trimesh_shape != null:
			var cs := CollisionShape3D.new()
			cs.shape = trimesh_shape
			cs.transform = inv_root * mi.global_transform
			sb.add_child(cs)

func _add_warehouse_interior_lights(wh: Node3D) -> void:
	# 4 warm industrial pendant lights hanging from trusses (optimized with distance fade)
	for cy in [-11.0, -4.0, 4.0, 11.0]:
		var light := OmniLight3D.new()
		light.name = "WH_Interior_Light_%d" % int(cy)
		light.light_color = Color(1.0, 0.88, 0.72)
		light.light_energy = 2.2
		light.omni_range = 15.0
		light.omni_attenuation = 1.1
		light.distance_fade_enabled = true
		light.distance_fade_begin = 35.0
		light.distance_fade_length = 15.0
		light.position = Vector3(0.0, 8.2, cy)
		wh.add_child(light)

func _add_office_interior_lights(office: Node3D) -> void:
	# Ground floor office light
	var gf_light := OmniLight3D.new()
	gf_light.name = "Off_GF_Light"
	gf_light.light_color = Color(0.92, 0.96, 1.0)
	gf_light.light_energy = 1.8
	gf_light.omni_range = 13.0
	gf_light.distance_fade_enabled = true
	gf_light.distance_fade_begin = 30.0
	gf_light.distance_fade_length = 15.0
	gf_light.position = Vector3(-2.0, 3.2, 0.0)
	office.add_child(gf_light)

	# 2nd floor command center light
	var f2_light := OmniLight3D.new()
	f2_light.name = "Off_2F_Light"
	f2_light.light_color = Color(0.85, 0.94, 1.0)
	f2_light.light_energy = 2.0
	f2_light.omni_range = 13.0
	f2_light.distance_fade_enabled = true
	f2_light.distance_fade_begin = 30.0
	f2_light.distance_fade_length = 15.0
	f2_light.position = Vector3(-2.0, 7.0, 0.0)
	office.add_child(f2_light)

# 10. Harbor Entrance Checkpoint, Security Blast Walls, and 4-Lane Access Highway
func _build_harbor_entrance_and_roads() -> void:
	var entrance_root := Node3D.new()
	entrance_root.name = "EntranceAndRoads"
	add_child(entrance_root)

	# 1. Main Harbor Security Gate Checkpoint (At South Apron gap: Vector3(-14.0, 0.0, 97.0))
	if ResourceLoader.exists(SECURITY_GATE_GLB_PATH):
		var gate_scene = load(SECURITY_GATE_GLB_PATH) as PackedScene
		if gate_scene != null:
			var gate = gate_scene.instantiate() as Node3D
			gate.name = "Harbor_Security_Gate"
			gate.position = Vector3(-14.0, 0.0, 97.0)
			gate.rotation.y = PI
			entrance_root.add_child(gate)
			_enhance_model_pbr(gate, 1.0, 0.45, 0.80)
			_generate_exact_collision_for_model(gate)

			# Checkpoint lane illumination floodlights (with distance fade)
			for lx in [-4.0, 4.0]:
				var lane_spot := SpotLight3D.new()
				lane_spot.name = "Gate_Lane_Light_%d" % int(lx)
				lane_spot.light_color = Color(0.92, 0.96, 1.0)
				lane_spot.light_energy = 3.0
				lane_spot.spot_range = 14.0
				lane_spot.spot_angle = 48.0
				lane_spot.distance_fade_enabled = true
				lane_spot.distance_fade_begin = 40.0
				lane_spot.distance_fade_length = 15.0
				lane_spot.position = Vector3(lx, 6.0, 0.0)
				lane_spot.rotation.x = -PI * 0.45
				gate.add_child(lane_spot)

	# 2. Heavy Concrete Perimeter Blast Walls (Tactical perimeter enclosure)
	# South boundary wall (Left of gate: X from -110.0 to -28.0)
	_create_static_slab("Wall_South_Left", entrance_root, Vector3(-69.0, 2.0, 99.5), Vector3(82.0, 4.2, 0.8), _mat_security_wall)
	# South boundary wall (Right of gate: X from 0.0 to 110.0)
	_create_static_slab("Wall_South_Right", entrance_root, Vector3(55.0, 2.0, 99.5), Vector3(110.0, 4.2, 0.8), _mat_security_wall)
	# East dock boundary wall (X=110.0, Z from -100.0 to 100.0)
	_create_static_slab("Wall_East_Boundary", entrance_root, Vector3(109.5, 2.0, 0.0), Vector3(0.8, 4.2, 200.0), _mat_security_wall)
	# West pier boundary wall (X=-110.0, Z from -100.0 to 100.0)
	_create_static_slab("Wall_West_Boundary", entrance_root, Vector3(-109.5, 2.0, 0.0), Vector3(0.8, 4.2, 200.0), _mat_security_wall)

	# 3. 4-Lane Access Highway (Outside gate: Z from 104.0 to 124.0, X from -140.0 to 140.0)
	_create_static_slab("Highway_Roadbed", entrance_root, Vector3(0.0, -0.9, 114.0), Vector3(280.0, 1.8, 20.0), _mat_asphalt)
	# Center double yellow division line
	_create_static_slab("Road_Center_Line", entrance_root, Vector3(0.0, 0.02, 114.0), Vector3(280.0, 0.02, 0.4), _mat_road_yellow_line)
	# North lane boundary white line
	_create_static_slab("Road_White_Line_N", entrance_root, Vector3(0.0, 0.02, 109.0), Vector3(280.0, 0.02, 0.25), _mat_road_white_line)
	# South lane boundary white line
	_create_static_slab("Road_White_Line_S", entrance_root, Vector3(0.0, 0.02, 119.0), Vector3(280.0, 0.02, 0.25), _mat_road_white_line)
	# South outer road curb
	_create_static_slab("Highway_Curb_South", entrance_root, Vector3(0.0, 0.15, 124.3), Vector3(280.0, 0.3, 0.6), _mat_curb_hazard)

	# 4. Highway Streetlights (Tall steel poles with warm sodium lighting + distance fade)
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.15
	pole_mesh.bottom_radius = 0.25
	pole_mesh.height = 10.0

	for sx in range(-120, 130, 40):
		var pole_mi := MeshInstance3D.new()
		pole_mi.mesh = pole_mesh
		pole_mi.material_override = _mat_asphalt
		pole_mi.position = Vector3(float(sx), 5.0, 123.5)
		entrance_root.add_child(pole_mi)

		var street_light := OmniLight3D.new()
		street_light.name = "Street_Light_%d" % sx
		street_light.light_color = Color(1.0, 0.82, 0.58)
		street_light.light_energy = 2.4
		street_light.omni_range = 18.0
		street_light.omni_attenuation = 1.0
		street_light.distance_fade_enabled = true
		street_light.distance_fade_begin = 45.0
		street_light.distance_fade_length = 20.0
		street_light.position = Vector3(float(sx), 9.8, 121.5)
		entrance_root.add_child(street_light)

# 11. Landward Metropolitan & Industrial Skyline Backdrop
func _build_city_and_industrial_backdrop() -> void:
	if not ResourceLoader.exists(CITY_BACKDROP_GLB_PATH):
		return
	var city_scene = load(CITY_BACKDROP_GLB_PATH) as PackedScene
	if city_scene == null:
		return

	var backdrop_root := Node3D.new()
	backdrop_root.name = "CityBackdropRoot"
	add_child(backdrop_root)

	# South Horizon Backdrops (Behind Highway: Z ~ 150 to 160)
	var positions := [
		Vector3(0.0, 0.0, 150.0),      # Center backdrop
		Vector3(85.0, 0.0, 158.0),     # South-East heavy industry sector
		Vector3(-85.0, 0.0, 158.0),    # South-West distribution sector
		Vector3(148.0, 0.0, 15.0),     # East flank city skyline
		Vector3(148.0, 0.0, -65.0)     # East flank northern towers
	]
	var rotations := [
		0.0,
		0.0,
		0.0,
		PI * 0.5,
		PI * 0.5
	]

	for i in range(positions.size()):
		var bldg = city_scene.instantiate() as Node3D
		bldg.name = "City_Backdrop_%d" % (i + 1)
		bldg.position = positions[i]
		bldg.rotation.y = rotations[i]
		backdrop_root.add_child(bldg)
		_enhance_model_pbr(bldg, 0.8, 0.40, 0.70)
		_optimize_backdrop_node(bldg, 420.0)

# 12. Endless Open Ocean Extension, Breakwater, and Coastal Lighthouse
func _build_open_ocean_extension() -> void:
	var ocean_root := Node3D.new()
	ocean_root.name = "OpenOceanRoot"
	add_child(ocean_root)

	# 1. Vast Open Horizon Ocean Surface (Optimized 32x32 subdivision, no shadow casting)
	var ocean_mesh := PlaneMesh.new()
	ocean_mesh.size = Vector2(900.0, 750.0)
	ocean_mesh.subdivide_width = 32
	ocean_mesh.subdivide_depth = 32
	var ocean_mi := MeshInstance3D.new()
	ocean_mi.name = "VastOceanSurface"
	ocean_mi.mesh = ocean_mesh
	ocean_mi.material_override = _mat_water
	ocean_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean_mi.position = Vector3(0.0, -2.25, -475.0)
	ocean_root.add_child(ocean_mi)

	# 2. Breakwater Jetty & Coastal Lighthouse (At Z = -260.0 in the bay entrance)
	if ResourceLoader.exists(LIGHTHOUSE_GLB_PATH):
		var lh_scene = load(LIGHTHOUSE_GLB_PATH) as PackedScene
		if lh_scene != null:
			var lh = lh_scene.instantiate() as Node3D
			lh.name = "Breakwater_Lighthouse"
			lh.position = Vector3(65.0, -2.2, -260.0)
			ocean_root.add_child(lh)
			_enhance_model_pbr(lh, 0.9, 0.35, 0.75)
			_generate_exact_collision_for_model(lh)
			_optimize_backdrop_node(lh, 450.0)

			# Powerful coastal beacon beam (optimized with distance fade)
			var beacon_omni := OmniLight3D.new()
			beacon_omni.name = "LH_Beacon_Omni"
			beacon_omni.light_color = Color(1.0, 0.96, 0.80)
			beacon_omni.light_energy = 4.5
			beacon_omni.omni_range = 35.0
			beacon_omni.distance_fade_enabled = true
			beacon_omni.distance_fade_begin = 120.0
			beacon_omni.distance_fade_length = 35.0
			beacon_omni.position = Vector3(45.0, 27.5, 0.0)
			lh.add_child(beacon_omni)

			var beacon_spot := SpotLight3D.new()
			beacon_spot.name = "LH_Beacon_Beam"
			beacon_spot.light_color = Color(1.0, 0.98, 0.85)
			beacon_spot.light_energy = 7.0
			beacon_spot.spot_range = 140.0
			beacon_spot.spot_angle = 32.0
			beacon_spot.distance_fade_enabled = true
			beacon_spot.distance_fade_begin = 130.0
			beacon_spot.distance_fade_length = 35.0
			beacon_spot.position = Vector3(45.0, 27.5, 0.0)
			beacon_spot.rotation.y = -PI * 0.65
			lh.add_child(beacon_spot)

	# 3. Channel Navigation Marker Buoys (Flashing Green & Red with distance fade)
	var buoy_mesh := CylinderMesh.new()
	buoy_mesh.top_radius = 0.8
	buoy_mesh.bottom_radius = 1.1
	buoy_mesh.height = 2.4

	# Starboard Buoy (Green beacon, X = 25.0)
	var buoy_green := MeshInstance3D.new()
	buoy_green.name = "Navigation_Buoy_Starboard"
	buoy_green.mesh = buoy_mesh
	var mat_g := StandardMaterial3D.new()
	mat_g.albedo_color = Color(0.12, 0.85, 0.25)
	mat_g.roughness = 0.4
	buoy_green.material_override = mat_g
	buoy_green.position = Vector3(25.0, -1.8, -135.0)
	ocean_root.add_child(buoy_green)

	var g_light := OmniLight3D.new()
	g_light.name = "Buoy_Green_Light"
	g_light.light_color = Color(0.15, 1.0, 0.35)
	g_light.light_energy = 2.8
	g_light.omni_range = 16.0
	g_light.distance_fade_enabled = true
	g_light.distance_fade_begin = 60.0
	g_light.distance_fade_length = 25.0
	g_light.position = Vector3(0.0, 1.8, 0.0)
	buoy_green.add_child(g_light)

	# Port Buoy (Red beacon, X = -55.0)
	var buoy_red := MeshInstance3D.new()
	buoy_red.name = "Navigation_Buoy_Port"
	buoy_red.mesh = buoy_mesh
	var mat_r := StandardMaterial3D.new()
	mat_r.albedo_color = Color(0.85, 0.15, 0.12)
	mat_r.roughness = 0.4
	buoy_red.material_override = mat_r
	buoy_red.position = Vector3(-55.0, -1.8, -135.0)
	ocean_root.add_child(buoy_red)

	var r_light := OmniLight3D.new()
	r_light.name = "Buoy_Red_Light"
	r_light.light_color = Color(1.0, 0.20, 0.15)
	r_light.light_energy = 2.8
	r_light.omni_range = 16.0
	r_light.distance_fade_enabled = true
	r_light.distance_fade_begin = 60.0
	r_light.distance_fade_length = 25.0
	r_light.position = Vector3(0.0, 1.8, 0.0)
	buoy_red.add_child(r_light)

func _optimize_backdrop_node(root_node: Node3D, max_dist: float = 400.0) -> void:
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = max_dist
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF




