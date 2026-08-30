class_name ArenaBackdropSpawner
extends Node

## Spawns outer ground skirts, atmospheric biome backdrops, and proximity boundary indicators.

const OUTER_SKIRT_SIZE := 1200.0

static func build_perimeters(arena_gen: Node3D, theme: int, arena_size: float) -> void:
	if arena_gen == null:
		return

	var backdrop_root := Node3D.new()
	backdrop_root.name = "ArenaBackdropRoot"
	arena_gen.add_child(backdrop_root)

	# 1. Outer Ground Skirt (Seamless continuous horizon floor)
	_create_outer_ground_skirt(backdrop_root, arena_gen, theme, arena_size)

	# 2. Biome-Specific Perimeter Backdrops
	match theme:
		0: # DESERT
			_create_desert_backdrops(backdrop_root, arena_size)
		1, 2: # CITY_HIGHRISE, CROSSROADS
			_create_city_backdrops(backdrop_root, arena_size)
		3: # RIVER_BRIDGE
			_create_river_canyon_backdrops(backdrop_root, arena_size)
		4, 5: # FOREST, FOREST_ROAD
			_create_forest_backdrops(backdrop_root, arena_size)

	# 3. Proximity Holographic Perimeter Warning Grid
	_create_proximity_perimeter_grid(backdrop_root, arena_size)


static func _create_outer_ground_skirt(parent: Node3D, arena_gen: Node3D, theme: int, arena_size: float) -> void:
	var skirt_mesh := PlaneMesh.new()
	skirt_mesh.size = Vector2(OUTER_SKIRT_SIZE, OUTER_SKIRT_SIZE)
	skirt_mesh.subdivide_width = 8
	skirt_mesh.subdivide_depth = 8

	var mi := MeshInstance3D.new()
	mi.name = "OuterGroundSkirt"
	mi.mesh = skirt_mesh
	mi.position = Vector3(0, -0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	mat.specular = 0.05

	match theme:
		0: # DESERT
			mat.albedo_color = Color(0.78, 0.62, 0.42)
		1, 2: # CITY / CROSSROADS
			mat.albedo_color = Color(0.18, 0.19, 0.22)
		3: # RIVER BRIDGE
			mat.albedo_color = Color(0.38, 0.42, 0.35)
		4, 5: # FOREST
			mat.albedo_color = Color(0.24, 0.36, 0.20)

	mi.material_override = mat
	parent.add_child(mi)


static func _create_desert_backdrops(parent: Node3D, arena_size: float) -> void:
	var half := arena_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var dune_mat := StandardMaterial3D.new()
	dune_mat.albedo_color = Color(0.72, 0.55, 0.36)
	dune_mat.roughness = 0.92

	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.58, 0.42, 0.30)
	rock_mat.roughness = 0.95

	# Outer Ring of Rolling Sand Dunes
	var num_dunes := 28
	for i in range(num_dunes):
		var angle := (float(i) / float(num_dunes)) * TAU + rng.randf_range(-0.1, 0.1)
		var dist := half + rng.randf_range(35.0, 160.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var dune := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		var d_scale_x := rng.randf_range(60.0, 140.0)
		var d_scale_y := rng.randf_range(16.0, 38.0)
		var d_scale_z := rng.randf_range(50.0, 100.0)
		s_mesh.radius = 1.0
		s_mesh.height = 2.0
		dune.mesh = s_mesh
		dune.scale = Vector3(d_scale_x, d_scale_y, d_scale_z)
		dune.position = Vector3(pos.x, d_scale_y * 0.35, pos.z)
		dune.rotation.y = angle + PI * 0.5
		dune.material_override = dune_mat
		dune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(dune)

	# Distant Sandstone Mesa Rock Bluffs
	var num_mesas := 14
	for i in range(num_mesas):
		var angle := (float(i) / float(num_mesas)) * TAU + rng.randf_range(-0.2, 0.2)
		var dist := half + rng.randf_range(140.0, 280.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var mesa := MeshInstance3D.new()
		var b_mesh := BoxMesh.new()
		var m_w := rng.randf_range(50.0, 110.0)
		var m_h := rng.randf_range(45.0, 95.0)
		var m_d := rng.randf_range(50.0, 90.0)
		b_mesh.size = Vector3(m_w, m_h, m_d)
		mesa.mesh = b_mesh
		mesa.position = Vector3(pos.x, m_h * 0.5 - 5.0, pos.z)
		mesa.rotation.y = rng.randf_range(0.0, TAU)
		mesa.material_override = rock_mat
		mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesa)


static func _create_forest_backdrops(parent: Node3D, arena_size: float) -> void:
	var half := arena_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 88

	var pine_mat := StandardMaterial3D.new()
	pine_mat.albedo_color = Color(0.12, 0.22, 0.10)
	pine_mat.roughness = 0.85

	var mountain_mat := StandardMaterial3D.new()
	mountain_mat.albedo_color = Color(0.20, 0.28, 0.22)
	mountain_mat.roughness = 0.95

	# 1. Dense Perimeter Tree Line (Impenetrable wall of pines just outside boundary)
	var num_trees := 70
	for i in range(num_trees):
		var angle := (float(i) / float(num_trees)) * TAU + rng.randf_range(-0.05, 0.05)
		var dist := half + rng.randf_range(6.0, 24.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var tree := MeshInstance3D.new()
		var c_mesh := CylinderMesh.new()
		c_mesh.top_radius = 0.1
		c_mesh.bottom_radius = rng.randf_range(4.5, 7.5)
		c_mesh.height = rng.randf_range(18.0, 32.0)
		tree.mesh = c_mesh
		tree.position = Vector3(pos.x, c_mesh.height * 0.5, pos.z)
		tree.material_override = pine_mat
		tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(tree)

	# 2. Outer Layered Forested Mountain Ridges
	var num_mountains := 18
	for i in range(num_mountains):
		var angle := (float(i) / float(num_mountains)) * TAU + rng.randf_range(-0.15, 0.15)
		var dist := half + rng.randf_range(90.0, 240.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var mtn := MeshInstance3D.new()
		var p_mesh := PrismMesh.new()
		var m_w := rng.randf_range(110.0, 220.0)
		var m_h := rng.randf_range(60.0, 130.0)
		var m_d := rng.randf_range(80.0, 160.0)
		p_mesh.size = Vector3(m_w, m_h, m_d)
		mtn.mesh = p_mesh
		mtn.position = Vector3(pos.x, m_h * 0.5 - 8.0, pos.z)
		mtn.rotation.y = angle + PI * 0.5 + rng.randf_range(-0.3, 0.3)
		mtn.material_override = mountain_mat
		mtn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mtn)


static func _create_city_backdrops(parent: Node3D, arena_size: float) -> void:
	var half := arena_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 101

	var bld_mat := StandardMaterial3D.new()
	bld_mat.albedo_color = Color(0.16, 0.18, 0.22)
	bld_mat.metallic = 0.2
	bld_mat.roughness = 0.75

	var hwy_mat := StandardMaterial3D.new()
	hwy_mat.albedo_color = Color(0.25, 0.26, 0.28)
	hwy_mat.roughness = 0.85

	# 1. Distant Megalopolis Skyscraper Silhouette Clusters
	var num_towers := 36
	for i in range(num_towers):
		var angle := (float(i) / float(num_towers)) * TAU + rng.randf_range(-0.1, 0.1)
		var dist := half + rng.randf_range(40.0, 220.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var tower := MeshInstance3D.new()
		var b_mesh := BoxMesh.new()
		var t_w := rng.randf_range(25.0, 55.0)
		var t_h := rng.randf_range(70.0, 180.0)
		var t_d := rng.randf_range(25.0, 55.0)
		b_mesh.size = Vector3(t_w, t_h, t_d)
		tower.mesh = b_mesh
		tower.position = Vector3(pos.x, t_h * 0.5, pos.z)
		tower.material_override = bld_mat
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(tower)

	# 2. Perimeter Barricaded Highway Overpasses
	var num_hwys := 8
	for i in range(num_hwys):
		var angle := (float(i) / float(num_hwys)) * TAU
		var dist := half + 18.0
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var hwy := MeshInstance3D.new()
		var h_mesh := BoxMesh.new()
		h_mesh.size = Vector3(60.0, 6.0, 14.0)
		hwy.mesh = h_mesh
		hwy.position = Vector3(pos.x, 8.0, pos.z)
		hwy.rotation.y = angle + PI * 0.5
		hwy.material_override = hwy_mat
		hwy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(hwy)


static func _create_river_canyon_backdrops(parent: Node3D, arena_size: float) -> void:
	var half := arena_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 202

	var cliff_mat := StandardMaterial3D.new()
	cliff_mat.albedo_color = Color(0.42, 0.38, 0.32)
	cliff_mat.roughness = 0.95

	# Flanking River Canyon Bluffs
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		for j in range(12):
			var z_pos: float = lerpf(-half * 1.4, half * 1.4, float(j) / 11.0)
			var x_pos: float = float(side) * (half + rng.randf_range(25.0, 70.0))

			var bluff := MeshInstance3D.new()
			var b_mesh := BoxMesh.new()
			var b_w := rng.randf_range(50.0, 90.0)
			var b_h := rng.randf_range(40.0, 85.0)
			var b_d := rng.randf_range(45.0, 75.0)
			b_mesh.size = Vector3(b_w, b_h, b_d)
			bluff.mesh = b_mesh
			bluff.position = Vector3(x_pos, b_h * 0.5 - 4.0, z_pos)
			bluff.rotation.y = rng.randf_range(-0.3, 0.3)
			bluff.material_override = cliff_mat
			bluff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(bluff)


static func _create_proximity_perimeter_grid(parent: Node3D, arena_size: float) -> void:
	var half := arena_size * 0.5

	var boundary_line := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "ProximityBoundaryLine"
	mi.mesh = boundary_line

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Draw subtle perimeter boundary quad ribbon at y = 0.15
	boundary_line.clear_surfaces()
	boundary_line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var pts := [
		Vector3(-half, 0.2, -half),
		Vector3(half, 0.2, -half),
		Vector3(half, 0.2, half),
		Vector3(-half, 0.2, half),
		Vector3(-half, 0.2, -half)
	]
	for p in pts:
		boundary_line.surface_add_vertex(p)
	boundary_line.surface_end()

	mi.material_override = mat
	parent.add_child(mi)
