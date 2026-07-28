extends Node3D

## Generates procedural combat maps: Desert, Skyscraper City, Urban Crossroads, and River Bridge.

@export var arena_size: float = 240.0
@export var wall_height: float = 14.0
@export var wall_thickness: float = 3.0
@export var tile_count: int = 24
@export var pillar_size: float = 6.0

enum BiomeTheme { DESERT, CITY_HIGHRISE, CROSSROADS, RIVER_BRIDGE }

var current_theme: BiomeTheme = BiomeTheme.DESERT
var tile_container: Node3D
var wall_container: Node3D
var structures_container: Node3D


func _ready() -> void:
	current_theme = randi() % BiomeTheme.size() as BiomeTheme
	generate_arena()


func generate_arena() -> void:
	_create_containers()
	_add_ground_tiles()
	_create_walls()
	_create_pillars()
	_create_theme_structures()
	EventBus.arena_generated.emit({
		"size": arena_size,
		"theme": current_theme
	})


func _create_containers() -> void:
	wall_container = Node3D.new()
	wall_container.name = "Walls"
	add_child(wall_container)

	tile_container = Node3D.new()
	tile_container.name = "GroundTiles"
	add_child(tile_container)

	structures_container = Node3D.new()
	structures_container.name = "ThemeStructures"
	add_child(structures_container)


func _add_ground_tiles() -> void:
	var tile_size = arena_size / tile_count

	for x in range(tile_count):
		for z in range(tile_count):
			var pos_x = (x - tile_count / 2.0) * tile_size + tile_size / 2.0
			var pos_z = (z - tile_count / 2.0) * tile_size + tile_size / 2.0

			# Skip ground mesh inside river trench for RIVER_BRIDGE theme
			if current_theme == BiomeTheme.RIVER_BRIDGE and absf(pos_z) < 22.0:
				continue

			var tile = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(tile_size * 0.98, 0.1, tile_size * 0.98)
			tile.mesh = box

			var mat = StandardMaterial3D.new()
			var col = _get_theme_tile_color(x, z, pos_x, pos_z)
			mat.albedo_color = col
			mat.roughness = 0.8
			tile.material_override = mat

			tile.position = Vector3(pos_x, -0.39, pos_z)
			tile_container.add_child(tile)


func _get_theme_tile_color(x: int, z: int, pos_x: float, pos_z: float) -> Color:
	var v = randf_range(-0.04, 0.04)
	match current_theme:
		BiomeTheme.DESERT:
			# Sand dunes yellow/amber
			return Color(0.62 + v, 0.50 + v, 0.32 + v)

		BiomeTheme.CITY_HIGHRISE:
			# Asphalt roads and concrete sidewalks
			if int(abs(pos_x)) % 40 < 12 or int(abs(pos_z)) % 40 < 12:
				return Color(0.18 + v, 0.19 + v, 0.22 + v) # Asphalt street
			return Color(0.40 + v, 0.42 + v, 0.45 + v) # Sidewalk

		BiomeTheme.CROSSROADS:
			# 4-way Urban Intersection
			if absf(pos_x) < 18.0 or absf(pos_z) < 18.0:
				if (absf(pos_x) < 1.0 or absf(pos_z) < 1.0):
					return Color(0.85 + v, 0.75 + v, 0.20 + v) # Yellow center lane lines
				return Color(0.15 + v, 0.16 + v, 0.18 + v) # Road asphalt
			return Color(0.45 + v, 0.45 + v, 0.48 + v) # Corner building sidewalk

		BiomeTheme.RIVER_BRIDGE:
			# Riverbanks and bridge access roads
			if absf(pos_z) < 32.0:
				return Color(0.35 + v, 0.32 + v, 0.28 + v) # Riverbank dirt
			return Color(0.22 + v, 0.24 + v, 0.26 + v) # Access road


func _create_walls() -> void:
	var half = arena_size / 2.0

	var wall_defs = [
		{"pos": Vector3(0, wall_height / 2.0, -half), "size": Vector3(arena_size + wall_thickness * 2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height / 2.0, half), "size": Vector3(arena_size + wall_thickness * 2, wall_height, wall_thickness)},
		{"pos": Vector3(-half, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, arena_size)},
		{"pos": Vector3(half, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, arena_size)},
	]

	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = _get_wall_color()
	wall_mat.roughness = 0.85

	for def in wall_defs:
		var wall = StaticBody3D.new()
		wall.collision_layer = 2
		wall.collision_mask = 1

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = def["size"]
		collision.shape = shape
		wall.add_child(collision)

		var mesh_inst = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = def["size"]
		mesh_inst.mesh = box_mesh
		mesh_inst.material_override = wall_mat
		wall.add_child(mesh_inst)

		wall.position = def["pos"]
		wall_container.add_child(wall)


func _get_wall_color() -> Color:
	match current_theme:
		BiomeTheme.DESERT: return Color(0.48, 0.40, 0.30)
		BiomeTheme.CITY_HIGHRISE: return Color(0.20, 0.22, 0.28)
		BiomeTheme.CROSSROADS: return Color(0.25, 0.27, 0.32)
		BiomeTheme.RIVER_BRIDGE: return Color(0.30, 0.32, 0.35)


func _create_pillars() -> void:
	var half = arena_size / 2.0
	var offset = pillar_size

	var pillar_positions = [
		Vector3(-half + offset, 0, -half + offset),
		Vector3(half - offset, 0, -half + offset),
		Vector3(-half + offset, 0, half - offset),
		Vector3(half - offset, 0, half - offset),
	]

	var pillar_mat = StandardMaterial3D.new()
	pillar_mat.albedo_color = _get_wall_color().darkened(0.2)
	pillar_mat.roughness = 0.7

	for pos in pillar_positions:
		var pillar = StaticBody3D.new()
		pillar.collision_layer = 2
		pillar.collision_mask = 1

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(pillar_size, wall_height + 4, pillar_size)
		collision.shape = shape
		collision.position.y = (wall_height + 4) / 2.0
		pillar.add_child(collision)

		var mesh_inst = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(pillar_size, wall_height + 4, pillar_size)
		mesh_inst.mesh = box_mesh
		mesh_inst.material_override = pillar_mat
		pillar.add_child(mesh_inst)

		pillar.position = pos
		wall_container.add_child(pillar)


# ====================================================================
# MAP STRUCTURAL THEMES
# ====================================================================

func _create_theme_structures() -> void:
	match current_theme:
		BiomeTheme.DESERT:
			_build_desert_structures()
		BiomeTheme.CITY_HIGHRISE:
			_build_city_highrise_structures()
		BiomeTheme.CROSSROADS:
			_build_crossroads_structures()
		BiomeTheme.RIVER_BRIDGE:
			_build_river_bridge_structures()


func _build_desert_structures() -> void:
	# Outpost watchtowers & sand dunes
	var dune_positions = [
		Vector3(-50, 0, -60), Vector3(60, 0, -40),
		Vector3(-70, 0, 50), Vector3(50, 0, 70)
	]
	for pos in dune_positions:
		var dune = StaticBody3D.new()
		dune.collision_layer = 2
		dune.collision_mask = 1
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(25, 4, 25)
		collision.shape = shape
		collision.position.y = 2.0
		dune.add_child(collision)

		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(25, 4, 25)
		mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.65, 0.52, 0.35)
		mat.roughness = 0.9
		mesh.material_override = mat
		dune.add_child(mesh)
		dune.position = pos
		structures_container.add_child(dune)


func _build_city_highrise_structures() -> void:
	# Grid of skyscraper building blocks
	var b_coords = [-70.0, -35.0, 35.0, 70.0]
	for bx in b_coords:
		for bz in b_coords:
			if absf(bx) < 20.0 and absf(bz) < 20.0:
				continue # Clear spawn area
			var b_height = randf_range(25.0, 45.0)
			var building = StaticBody3D.new()
			building.collision_layer = 2
			building.collision_mask = 1

			var collision = CollisionShape3D.new()
			var shape = BoxShape3D.new()
			shape.size = Vector3(20, b_height, 20)
			collision.shape = shape
			collision.position.y = b_height / 2.0
			building.add_child(collision)

			var mesh = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(20, b_height, 20)
			mesh.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.18, 0.24)
			mat.metallic = 0.3
			mat.roughness = 0.5
			mesh.material_override = mat
			building.add_child(mesh)

			building.position = Vector3(bx, 0, bz)
			structures_container.add_child(building)


func _build_crossroads_structures() -> void:
	# 4 Major corner skyscraper blocks surrounding 4-way intersection
	var corners = [
		Vector3(-55, 0, -55), Vector3(55, 0, -55),
		Vector3(-55, 0, 55), Vector3(55, 0, 55)
	]
	for pos in corners:
		var b_height = randf_range(30.0, 50.0)
		var block = StaticBody3D.new()
		block.collision_layer = 2
		block.collision_mask = 1

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(50, b_height, 50)
		collision.shape = shape
		collision.position.y = b_height / 2.0
		block.add_child(collision)

		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(50, b_height, 50)
		mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.14, 0.20)
		mat.metallic = 0.4
		mat.roughness = 0.4
		mesh.material_override = mat
		block.add_child(mesh)

		block.position = pos
		structures_container.add_child(block)


func _build_river_bridge_structures() -> void:
	# 1. Animated Water Trench in Center (Z = -20 to 20)
	var water = MeshInstance3D.new()
	var water_box = BoxMesh.new()
	water_box.size = Vector3(arena_size, 0.2, 40)
	water.mesh = water_box

	var water_mat = StandardMaterial3D.new()
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color = Color(0.1, 0.4, 0.7, 0.75)
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.05, 0.25, 0.5)
	water_mat.emission_energy_multiplier = 1.2
	water_mat.roughness = 0.1
	water.material_override = water_mat
	water.position = Vector3(0, -0.6, 0)
	structures_container.add_child(water)

	# 2. Main Center Steel Bridge Crossing (X = -20 to 20, Z = -25 to 25)
	var bridge = StaticBody3D.new()
	bridge.collision_layer = 2
	bridge.collision_mask = 1

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(30, 1.0, 52)
	collision.shape = shape
	collision.position.y = 0.0
	bridge.add_child(collision)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(30, 1.0, 52)
	mesh.mesh = box
	var bridge_mat = StandardMaterial3D.new()
	bridge_mat.albedo_color = Color(0.35, 0.38, 0.42)
	bridge_mat.metallic = 0.7
	bridge_mat.roughness = 0.4
	mesh.material_override = bridge_mat
	bridge.add_child(mesh)

	# Steel Bridge Side Girders
	for side in [-15.0, 15.0]:
		var girder = MeshInstance3D.new()
		var g_mesh = BoxMesh.new()
		g_mesh.size = Vector3(1.2, 8.0, 52.0)
		girder.mesh = g_mesh
		var g_mat = StandardMaterial3D.new()
		g_mat.albedo_color = Color(0.7, 0.25, 0.15) # Rusted Red Truss Steel
		g_mat.metallic = 0.6
		girder.material_override = g_mat
		girder.position = Vector3(side, 4.0, 0)
		bridge.add_child(girder)

	bridge.position = Vector3(0, 0, 0)
	structures_container.add_child(bridge)

	# 3. Flanking Side Bridges (East and West)
	for flank_x in [-75.0, 75.0]:
		var f_bridge = StaticBody3D.new()
		f_bridge.collision_layer = 2
		f_bridge.collision_mask = 1

		var f_collision = CollisionShape3D.new()
		var f_shape = BoxShape3D.new()
		f_shape.size = Vector3(15, 1.0, 52)
		f_collision.shape = f_shape
		f_collision.position.y = 0.0
		f_bridge.add_child(f_collision)

		var f_mesh = MeshInstance3D.new()
		var f_box = BoxMesh.new()
		f_box.size = Vector3(15, 1.0, 52)
		f_mesh.mesh = f_box
		f_mesh.material_override = bridge_mat
		f_bridge.add_child(f_mesh)

		f_bridge.position = Vector3(flank_x, 0, 0)
		structures_container.add_child(f_bridge)
