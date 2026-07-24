extends Node3D

## Spawns cover objects in the arena in predefined patterns.

@export var arena_size: float = 120.0
@export var min_spacing: float = 4.0


func _ready() -> void:
	# Wait for arena to generate
	await get_tree().process_frame
	spawn_covers()


func spawn_covers() -> void:
	var covers = _generate_cover_positions()

	for def in covers:
		var cover = _create_cover(def)
		add_child(cover)


func _generate_cover_positions() -> Array:
	var results = []
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var half = arena_size / 2.0 - 5.0  # Stay inside walls

	# Inner ring (radius ~20)
	for i in range(6):
		var angle = (i / 6.0) * TAU + rng.randf_range(-0.3, 0.3)
		var radius = 20.0 + rng.randf_range(-3, 3)
		var pos = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if pos.x > -half and pos.x < half and pos.z > -half and pos.z < half:
			results.append({"pos": pos, "type": rng.randi_range(0, 2)})

	# Outer ring (radius ~40)
	for i in range(8):
		var angle = (i / 8.0) * TAU + rng.randf_range(-0.3, 0.3)
		var radius = 40.0 + rng.randf_range(-5, 5)
		var pos = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if pos.x > -half and pos.x < half and pos.z > -half and pos.z < half:
			results.append({"pos": pos, "type": rng.randi_range(0, 3)})

	return results


func _create_cover(def: Dictionary) -> StaticBody3D:
	var cover_script = preload("res://scripts/arena/cover_object.gd")

	var type = def["type"]
	var pos = def["pos"]

	var cover = StaticBody3D.new()
	cover.set_script(cover_script)
	cover.position = pos

	var collision = CollisionShape3D.new()
	var mesh_inst = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.8

	match type:
		0:  # Concrete Barrier
			var shape = BoxShape3D.new()
			shape.size = Vector3(3, 1.5, 0.5)
			collision.shape = shape
			collision.position.y = 0.75

			var box = BoxMesh.new()
			box.size = Vector3(3, 1.5, 0.5)
			mesh_inst.mesh = box
			mat.albedo_color = Color(0.45, 0.45, 0.5, 1)
			cover.max_hp = 200.0
			cover.cover_type = "barrier"

		1:  # Crate Stack
			var shape = BoxShape3D.new()
			shape.size = Vector3(2, 3, 2)
			collision.shape = shape
			collision.position.y = 1.5

			var box = BoxMesh.new()
			box.size = Vector3(2, 3, 2)
			mesh_inst.mesh = box
			mat.albedo_color = Color(0.5, 0.4, 0.3, 1)
			cover.max_hp = 150.0
			cover.cover_type = "crate"

		2:  # Pillar
			var shape = CylinderShape3D.new()
			shape.radius = 0.8
			shape.height = 6.0
			collision.shape = shape
			collision.position.y = 3.0

			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.8
			cyl.bottom_radius = 0.8
			cyl.height = 6.0
			mesh_inst.mesh = cyl
			mat.albedo_color = Color(0.4, 0.4, 0.45, 1)
			cover.max_hp = 300.0
			cover.cover_type = "pillar"

		3:  # Destroyable Crate
			var shape = BoxShape3D.new()
			shape.size = Vector3(1.5, 1.5, 1.5)
			collision.shape = shape
			collision.position.y = 0.75

			var box = BoxMesh.new()
			box.size = Vector3(1.5, 1.5, 1.5)
			mesh_inst.mesh = box
			mat.albedo_color = Color(0.55, 0.45, 0.35, 1)
			cover.max_hp = 80.0
			cover.cover_type = "small_crate"

	cover.add_child(collision)
	cover.add_child(mesh_inst)
	mesh_inst.material_override = mat

	# Add damage particles for small crates
	if type == 3:
		var particles = GPUParticles3D.new()
		particles.name = "DamageParticles"
		particles.emitting = false
		particles.one_shot = true
		particles.amount = 8
		particles.lifetime = 0.5
		var mat_particles = ParticleProcessMaterial.new()
		mat_particles.direction = Vector3(0, 1, 0)
		mat_particles.spread = 45.0
		mat_particles.initial_velocity_min = 2.0
		mat_particles.initial_velocity_max = 4.0
		particles.process_material = mat_particles
		cover.add_child(particles)

	return cover
