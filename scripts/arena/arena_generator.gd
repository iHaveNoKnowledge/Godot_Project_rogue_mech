extends Node3D

## Generates the combat arena with walls, tiled ground, and corner pillars.
## Attach to a Node3D in game_world.tscn. Calls generate_arena() on _ready().

@export var arena_size: float = 120.0
@export var wall_height: float = 8.0
@export var wall_thickness: float = 2.0
@export var tile_count: int = 10
@export var pillar_size: float = 4.0

var tile_container: Node3D
var wall_container: Node3D


func _ready() -> void:
	generate_arena()


func generate_arena() -> void:
	# Keep original ground — just add visual tiles, walls, pillars
	_create_containers()
	_add_ground_tiles()
	_create_walls()
	_create_pillars()
	EventBus.arena_generated.emit({"size": arena_size})


func _create_containers() -> void:
	wall_container = Node3D.new()
	wall_container.name = "Walls"
	add_child(wall_container)

	tile_container = Node3D.new()
	tile_container.name = "GroundTiles"
	add_child(tile_container)


func _add_ground_tiles() -> void:
	# Visual-only tiles on top of the existing ground collision
	var tile_size = arena_size / tile_count

	for x in range(tile_count):
		for z in range(tile_count):
			var tile = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(tile_size, 0.1, tile_size)
			tile.mesh = box

			var mat = StandardMaterial3D.new()
			var variation = 0.05
			mat.albedo_color = Color(
				0.35 + randf_range(-variation, variation),
				0.45 + randf_range(-variation, variation),
				0.32 + randf_range(-variation, variation),
				1.0
			)
			tile.material_override = mat

			var pos_x = (x - tile_count / 2.0) * tile_size + tile_size / 2.0
			var pos_z = (z - tile_count / 2.0) * tile_size + tile_size / 2.0
			tile.position = Vector3(pos_x, -0.39, pos_z)
			tile_container.add_child(tile)


func _create_walls() -> void:
	var half = arena_size / 2.0

	# 4 walls: North, South, East, West
	var wall_defs = [
		{"pos": Vector3(0, wall_height / 2.0, -half), "size": Vector3(arena_size + wall_thickness * 2, wall_height, wall_thickness)},  # North
		{"pos": Vector3(0, wall_height / 2.0, half), "size": Vector3(arena_size + wall_thickness * 2, wall_height, wall_thickness)},   # South
		{"pos": Vector3(-half, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, arena_size)},                     # West
		{"pos": Vector3(half, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, arena_size)},                      # East
	]

	for def in wall_defs:
		var wall = StaticBody3D.new()
		wall.collision_layer = 2  # Environment
		wall.collision_mask = 1   # Mecha

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = def["size"]
		collision.shape = shape
		wall.add_child(collision)

		var mesh_inst = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = def["size"]
		mesh_inst.mesh = box_mesh

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.35, 1.0)
		mat.roughness = 0.8
		mesh_inst.material_override = mat

		wall.add_child(mesh_inst)
		wall.position = def["pos"]
		wall_container.add_child(wall)


func _create_pillars() -> void:
	var half = arena_size / 2.0
	var offset = pillar_size

	var pillar_positions = [
		Vector3(-half + offset, 0, -half + offset),
		Vector3(half - offset, 0, -half + offset),
		Vector3(-half + offset, 0, half - offset),
		Vector3(half - offset, 0, half - offset),
	]

	for pos in pillar_positions:
		var pillar = StaticBody3D.new()
		pillar.collision_layer = 2
		pillar.collision_mask = 1

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(pillar_size, wall_height + 2, pillar_size)
		collision.shape = shape
		collision.position.y = (wall_height + 2) / 2.0
		pillar.add_child(collision)

		var mesh_inst = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(pillar_size, wall_height + 2, pillar_size)
		mesh_inst.mesh = box_mesh

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.25, 0.3, 1.0)
		mat.roughness = 0.7
		mesh_inst.material_override = mat

		pillar.add_child(mesh_inst)
		pillar.position = pos
		wall_container.add_child(pillar)
