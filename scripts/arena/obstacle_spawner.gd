extends Node3D

## Spawns procedural cover objects, street barricades, containers, and hazards tailored to the map theme.

@export var arena_size: float = 240.0

var seed_system: Node = null


func _ready() -> void:
	await get_tree().process_frame
	seed_system = get_node_or_null("../ArenaSeedSystem")
	spawn_covers()


func spawn_covers() -> void:
	var covers = _generate_positions()

	for def in covers:
		var cover = _create_cover(def)
		if cover:
			add_child(cover)


func _generate_positions() -> Array:
	var arena_gen = get_node_or_null("../ArenaGenerator")
	var theme = arena_gen.current_theme if arena_gen else 0
	# Follow the generator's field size so cover spreads across the whole arena
	# (an ace/boss fight on a bigger field shouldn't cluster cover in the center).
	if arena_gen != null and arena_gen.get("arena_size") != null:
		arena_size = float(arena_gen.arena_size)

	if seed_system:
		if seed_system.has_method("set_seed"):
			seed_system.set_seed(GlobalData.board.current_sector, GlobalData.board.current_tile)
		return seed_system.get_obstacle_positions(theme, arena_size)
	else:
		return _random_positions()


func _random_positions() -> Array:
	var results = []
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var half = arena_size / 2.0 - 15.0

	for i in range(30):
		results.append({
			"pos": Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)),
			"type": rng.randi_range(0, 5),
			"rot": rng.randf_range(0, TAU)
		})
	return results


func _create_cover(def: Dictionary) -> StaticBody3D:
	var cover_script = preload("res://scripts/arena/cover_object.gd")
	var type = def["type"]
	var pos = def["pos"]
	var rot = def.get("rot", 0.0)

	var cover = StaticBody3D.new()
	cover.set_script(cover_script)
	# Drop the cover onto the walkable surface so props sit ON the terrain
	# (gentle hills, dunes, and riverbanks all rise above the flat floor).
	cover.position = Vector3(pos.x, _surface_y_at(pos), pos.z)
	cover.rotation.y = rot
	cover.add_to_group("cover")

	# Tall covers (tree trunks, fallen logs) double as concealment: an enemy
	# standing inside their footprint is hidden from the player.
	if type == 6 or type == 7:
		cover.add_to_group("concealment")

	var collision = CollisionShape3D.new()
	var mesh_inst = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.8

	cover.collision_layer = 2
	cover.collision_mask = 1

	match type:
		0: # Concrete Barrier
			var shape = BoxShape3D.new()
			shape.size = Vector3(6, 2.2, 1.2)
			collision.shape = shape
			collision.position.y = 1.1
			var box = BoxMesh.new()
			box.size = Vector3(6, 2.2, 1.2)
			mesh_inst.mesh = box
			mesh_inst.position.y = 1.1
			mat.albedo_color = Color(0.40, 0.42, 0.45, 1)
			cover.max_hp = 400.0
			cover.cover_type = "barrier"

		1: # Cargo Container
			var shape = BoxShape3D.new()
			shape.size = Vector3(4, 3.2, 8)
			collision.shape = shape
			collision.position.y = 1.6
			var box = BoxMesh.new()
			box.size = Vector3(4, 3.2, 8)
			mesh_inst.mesh = box
			mesh_inst.position.y = 1.6
			mat.albedo_color = Color(0.25, 0.35, 0.50, 1)
			cover.max_hp = 600.0
			cover.cover_type = "container"

		2: # Reinforced Pillar
			var shape = CylinderShape3D.new()
			shape.radius = 1.8
			shape.height = 8.0
			collision.shape = shape
			collision.position.y = 4.0
			var cyl = CylinderMesh.new()
			cyl.top_radius = 1.8
			cyl.bottom_radius = 1.8
			cyl.height = 8.0
			mesh_inst.mesh = cyl
			mesh_inst.position.y = 4.0
			mat.albedo_color = Color(0.35, 0.35, 0.40, 1)
			cover.max_hp = 800.0
			cover.cover_type = "pillar"

		3: # Destroyable Crate Stack
			var shape = BoxShape3D.new()
			shape.size = Vector3(3, 2.5, 3)
			collision.shape = shape
			collision.position.y = 1.25
			var box = BoxMesh.new()
			box.size = Vector3(3, 2.5, 3)
			mesh_inst.mesh = box
			mesh_inst.position.y = 1.25
			mat.albedo_color = Color(0.60, 0.45, 0.28, 1)
			cover.max_hp = 180.0
			cover.cover_type = "small_crate"

		4: # High Defense Wall
			var shape = BoxShape3D.new()
			shape.size = Vector3(10, 3.5, 1.5)
			collision.shape = shape
			collision.position.y = 1.75
			var box = BoxMesh.new()
			box.size = Vector3(10, 3.5, 1.5)
			mesh_inst.mesh = box
			mesh_inst.position.y = 1.75
			mat.albedo_color = Color(0.30, 0.30, 0.35, 1)
			cover.max_hp = 700.0
			cover.cover_type = "fortress_wall"

		5: # Explosive Barrel Hazard
			var shape = CylinderShape3D.new()
			shape.radius = 1.0
			shape.height = 2.2
			collision.shape = shape
			collision.position.y = 1.1
			var cyl = CylinderMesh.new()
			cyl.top_radius = 1.0
			cyl.bottom_radius = 1.0
			cyl.height = 2.2
			mesh_inst.mesh = cyl
			mesh_inst.position.y = 1.1
			mat.albedo_color = Color(0.9, 0.2, 0.1, 1)
			mat.emission_enabled = true
			mat.emission = Color(0.8, 0.1, 0.0)
			mat.emission_energy_multiplier = 1.5
			cover.max_hp = 50.0
			cover.cover_type = "explosive_barrel"

		6: # Forest Tree Trunk (cover: thick trunk)
			var shape = CylinderShape3D.new()
			shape.radius = 1.5
			shape.height = 9.0
			collision.shape = shape
			collision.position.y = 4.5
			var cyl = CylinderMesh.new()
			cyl.top_radius = 1.0
			cyl.bottom_radius = 1.5
			cyl.height = 9.0
			mesh_inst.mesh = cyl
			mesh_inst.position.y = 4.5
			mat.albedo_color = Color(0.32, 0.20, 0.10, 1)
			cover.max_hp = 700.0
			cover.cover_type = "tree_trunk"

		7: # Fallen Log
			var shape = CylinderShape3D.new()
			shape.radius = 1.0
			shape.height = 8.0
			collision.shape = shape
			collision.rotation_degrees.x = 90.0
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.9
			cyl.bottom_radius = 1.0
			cyl.height = 8.0
			mesh_inst.mesh = cyl
			mesh_inst.rotation_degrees.x = 90.0
			mat.albedo_color = Color(0.30, 0.20, 0.10, 1)
			cover.max_hp = 250.0
			cover.cover_type = "fallen_log"

		8: # Forest Fern / Bush
			var shape = CylinderShape3D.new()
			shape.radius = 1.2
			shape.height = 2.2
			collision.shape = shape
			collision.position.y = 1.1
			var cyl = CylinderMesh.new()
			cyl.top_radius = 1.2
			cyl.bottom_radius = 1.2
			cyl.height = 2.2
			mesh_inst.mesh = cyl
			mesh_inst.position.y = 1.1
			mat.albedo_color = Color(0.14, 0.38, 0.14, 1)
			cover.max_hp = 120.0
			cover.cover_type = "fern"

	cover.add_child(collision)
	cover.add_child(mesh_inst)
	mesh_inst.material_override = mat

	return cover


# Surface height under a spawn position: raycasts down onto the environment
# collision layer (ground tiles, terrain heightmaps, dunes, riverbanks) so
# cover never ends up half-buried or floating above the ground.
func _surface_y_at(pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 80.0, 0),
		pos + Vector3(0, -80.0, 0),
		2  # Environment layer: ground, terrain, dunes, banks, bridges.
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return pos.y
	return hit.position.y
