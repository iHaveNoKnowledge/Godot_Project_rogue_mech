extends Node3D

## Generates the expanded combat arena with customizable biome themes, walls, and tiled ground.

@export var arena_size: float = 240.0
@export var wall_height: float = 12.0
@export var wall_thickness: float = 3.0
@export var tile_count: int = 20
@export var pillar_size: float = 6.0

enum BiomeTheme { INDUSTRIAL, VOLCANIC, CYBERPUNK, DESERT, SNOW }

var current_theme: BiomeTheme = BiomeTheme.INDUSTRIAL
var tile_container: Node3D
var wall_container: Node3D


func _ready() -> void:
	# Randomize biome theme for each combat map
	current_theme = randi() % BiomeTheme.size() as BiomeTheme
	generate_arena()


func generate_arena() -> void:
	_create_containers()
	_add_ground_tiles()
	_create_walls()
	_create_pillars()
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


func _add_ground_tiles() -> void:
	var tile_size = arena_size / tile_count

	for x in range(tile_count):
		for z in range(tile_count):
			var tile = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(tile_size * 0.98, 0.1, tile_size * 0.98)
			tile.mesh = box

			var mat = StandardMaterial3D.new()
			var col = _get_theme_tile_color(x, z)
			mat.albedo_color = col
			mat.roughness = 0.75
			tile.material_override = mat

			var pos_x = (x - tile_count / 2.0) * tile_size + tile_size / 2.0
			var pos_z = (z - tile_count / 2.0) * tile_size + tile_size / 2.0
			tile.position = Vector3(pos_x, -0.39, pos_z)
			tile_container.add_child(tile)


func _get_theme_tile_color(x: int, z: int) -> Color:
	var v = randf_range(-0.04, 0.04)
	match current_theme:
		BiomeTheme.VOLCANIC:
			# Dark obsidian with occasional magma orange lines
			if (x + z) % 7 == 0:
				return Color(0.85 + v, 0.25 + v, 0.05 + v)
			return Color(0.12 + v, 0.10 + v, 0.11 + v)
		BiomeTheme.CYBERPUNK:
			# Dark metallic with cyan grid lines
			if (x + z) % 6 == 0:
				return Color(0.0 + v, 0.7 + v, 0.9 + v)
			return Color(0.08 + v, 0.12 + v, 0.18 + v)
		BiomeTheme.DESERT:
			# Sand yellow and beige
			return Color(0.55 + v, 0.45 + v, 0.32 + v)
		BiomeTheme.SNOW:
			# Cold ice blue and white
			return Color(0.70 + v, 0.78 + v, 0.85 + v)
		_: # INDUSTRIAL
			# Concrete grey and hazard stripes
			if (x + z) % 8 == 0:
				return Color(0.80 + v, 0.65 + v, 0.15 + v)
			return Color(0.32 + v, 0.35 + v, 0.38 + v)


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
		BiomeTheme.VOLCANIC: return Color(0.18, 0.12, 0.14)
		BiomeTheme.CYBERPUNK: return Color(0.10, 0.15, 0.25)
		BiomeTheme.DESERT: return Color(0.45, 0.38, 0.28)
		BiomeTheme.SNOW: return Color(0.55, 0.62, 0.70)
		_: return Color(0.25, 0.28, 0.32)


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
