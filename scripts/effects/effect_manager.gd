class_name EffectManager
extends Node

static var instance: EffectManager = null


func _ready() -> void:
	instance = self


static func spawn_muzzle_flash(position: Vector3, direction: Vector3) -> void:
	if instance == null:
		return

	var flash = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = direction
	mat.spread = 30.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 25.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.5

	flash.process_material = mat
	flash.amount = 6
	flash.lifetime = 0.15
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.albedo_color = Color(1, 0.9, 0.5, 0.8)
	mesh_instance.material_override = particle_mat
	flash.add_child(mesh_instance)

	instance.add_child(flash)
	flash.global_position = position
	flash.look_at(position + direction)

	await instance.get_tree().create_timer(0.3).timeout
	if is_instance_valid(flash):
		flash.queue_free()


static func spawn_impact(position: Vector3, normal: Vector3) -> void:
	if instance == null:
		return

	var impact = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = normal
	mat.spread = 60.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 8.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.15

	impact.process_material = mat
	impact.amount = 10
	impact.lifetime = 0.4
	impact.one_shot = true
	impact.explosiveness = 0.8
	impact.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.albedo_color = Color(1, 0.7, 0.3, 0.9)
	mesh_instance.material_override = particle_mat
	impact.add_child(mesh_instance)

	instance.add_child(impact)
	impact.global_position = position

	await instance.get_tree().create_timer(0.5).timeout
	if is_instance_valid(impact):
		impact.queue_free()


static func spawn_damage_number(position: Vector3, damage: float, color: Color = Color.WHITE) -> void:
	if instance == null:
		return

	var label = Label3D.new()
	label.text = str(int(damage))
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color

	instance.add_child(label)
	label.global_position = position + Vector3(randf_range(-0.5, 0.5), 1.0, 0)

	var tween = instance.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", position.y + 2.5, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


static func spawn_explosion(position: Vector3) -> void:
	if instance == null:
		return

	var explosion = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0, -3, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8

	explosion.process_material = mat
	explosion.amount = 30
	explosion.lifetime = 0.8
	explosion.one_shot = true
	explosion.explosiveness = 0.9
	explosion.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.albedo_color = Color(1, 0.5, 0.1, 1)
	mesh_instance.material_override = particle_mat
	explosion.add_child(mesh_instance)

	instance.add_child(explosion)
	explosion.global_position = position

	await instance.get_tree().create_timer(1.0).timeout
	if is_instance_valid(explosion):
		explosion.queue_free()


## Spawns a fading arc of box meshes tracing a melee swing. The arc sweeps from
## -30° to +30° around the swing direction (flipped by sweep_dir for alternating
## combo swings); each segment spawns progressively further out and fades over
## 0.3s. Shared by the player's melee weapons and enemy/ally RUSHER swings.
static func spawn_melee_trail(
	from_pos: Vector3,
	direction: Vector3,
	color: Color,
	emission: Color = Color(1.0, 0.35, 0.2),
	forward_start: float = 1.2,
	forward_step: float = 1.2,
	sweep_dir: float = 1.0,
) -> void:
	if instance == null:
		return

	var trail_count := 5
	var sweep_width := 5.0
	for i in range(trail_count):
		var t := float(i) / float(trail_count - 1)
		var trail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(sweep_width, 0.08, 0.2)
		trail.mesh = box

		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 1.0 - t * 0.6)
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 5.0 - t * 3.0
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = mat

		instance.get_tree().current_scene.add_child(trail)

		var height_offset := lerpf(1.8, 0.8, t)
		trail.global_position = from_pos + Vector3(0, height_offset, 0) + direction * (forward_start + t * forward_step)
		trail.look_at(trail.global_position + direction, Vector3.UP)
		trail.rotate_object_local(Vector3.FORWARD, deg_to_rad(90))
		trail.rotate_object_local(Vector3.UP, deg_to_rad((-30.0 + t * 60.0) * sweep_dir))

		var delay := t * 0.04
		var tween := instance.get_tree().create_tween()
		tween.tween_interval(delay)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tween.tween_callback(trail.queue_free)


## Collision-based melee hit check: casts a ray from the attacker (~chest
## height) along the swing. Whiffs when the ray stops on environment geometry
## (collision_layer bit 2) first, and only damages the first body that exposes
## take_damage(). Damage is applied directly and never depends on an EffectManager
## instance being live (only the damage-number visual does). Returns true when
## something took damage.
static func melee_hit_ray(
	attacker: Node3D,
	direction: Vector3,
	range: float,
	collision_mask: int,
	damage: float,
	damage_type: String = "blunt",
) -> bool:
	if attacker == null or attacker.get_viewport() == null:
		return false

	var space_state = attacker.get_viewport().get_world_3d().direct_space_state
	var start := attacker.global_position + Vector3(0, 1.5, 0)
	var end := start + direction * range
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = collision_mask
	var result = space_state.intersect_ray(query)
	if not result:
		return false

	var collider: CollisionObject3D = result["collider"]
	# If the ray stopped on a wall/cover first, the swing whiffs.
	if collider.collision_layer & 2 != 0:
		return false

	var victim: Node = collider
	while victim and not victim.has_method("take_damage"):
		victim = victim.get_parent()
	if victim == null or not victim.has_method("take_damage"):
		return false

	# Melee hits carry their attack type (heat/pierce/blunt) so armor plates
	# and shields match on it just like bullets and beams.
	victim.take_damage(damage, damage_type)
	spawn_damage_number(result["position"] + Vector3(0, 1, 0), damage, Color(1, 0.5, 0))
	return true
