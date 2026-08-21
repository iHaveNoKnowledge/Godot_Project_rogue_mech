class_name EffectManager
extends Node

static var instance: EffectManager = null


func _ready() -> void:
	instance = self


static func spawn_muzzle_flash(position: Vector3, direction: Vector3, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	if instance == null:
		return

	# 1. Dynamic Flash OmniLight3D (illuminates mecha, weapon barrel, and ground!)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = 10.0
	light.omni_attenuation = 2.0
	instance.add_child(light)
	light.global_position = position

	var light_tween := instance.create_tween()
	light_tween.tween_property(light, "light_energy", 0.0, 0.09)
	light_tween.tween_callback(light.queue_free)

	# 2. Glowing Particle Burst
	var flash = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = direction
	mat.spread = 25.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 28.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.55

	flash.process_material = mat
	flash.amount = 8
	flash.lifetime = 0.12
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.12
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	particle_mat.emission_enabled = true
	particle_mat.emission = color
	particle_mat.emission_energy_multiplier = 4.0
	mesh_instance.material_override = particle_mat
	flash.add_child(mesh_instance)

	instance.add_child(flash)
	flash.global_position = position
	if direction.length_squared() > 0.001:
		flash.look_at(position + direction, Vector3.UP)

	var flash_tween := flash.create_tween()
	flash_tween.tween_interval(0.2)
	flash_tween.tween_callback(flash.queue_free)


static func spawn_impact(position: Vector3, normal: Vector3) -> void:
	if instance == null:
		return

	var impact = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = normal
	mat.spread = 60.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0, -6, 0)
	mat.scale_min = 0.06
	mat.scale_max = 0.18

	impact.process_material = mat
	impact.amount = 12
	impact.lifetime = 0.35
	impact.one_shot = true
	impact.explosiveness = 0.9
	impact.emitting = true

	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.06
	mesh_instance.mesh = sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.95)
	particle_mat.emission_enabled = true
	particle_mat.emission = Color(1.0, 0.7, 0.2)
	particle_mat.emission_energy_multiplier = 3.5
	mesh_instance.material_override = particle_mat
	impact.add_child(mesh_instance)

	instance.add_child(impact)
	impact.global_position = position

	var t := impact.create_tween()
	t.tween_interval(0.4)
	t.tween_callback(impact.queue_free)


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


static func spawn_explosion(position: Vector3, radius: float = 8.0) -> void:
	if instance == null:
		return

	# 1. High-intensity Dynamic Light Flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.2)
	light.light_energy = 14.0
	light.omni_range = maxf(radius * 3.0, 22.0)
	light.omni_attenuation = 1.6
	instance.add_child(light)
	light.global_position = position

	var lt := instance.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.22)
	lt.tween_callback(light.queue_free)

	# 2. Expanding Fiery Shockwave Ring
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.5, 0.1)
	ring_mat.emission_energy_multiplier = 4.0
	ring.material_override = ring_mat
	instance.add_child(ring)
	ring.global_position = position + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.3, 0.1, 0.3)

	var ring_tween := instance.create_tween().set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3(radius * 1.5, 0.1, radius * 1.5), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.25)
	ring_tween.chain().tween_callback(ring.queue_free)

	# 3. Fiery Core Fireball Mesh
	var core_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	core_mesh.mesh = sphere
	var core_mat := StandardMaterial3D.new()
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.95)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.7, 0.2)
	core_mat.emission_energy_multiplier = 4.5
	core_mesh.material_override = core_mat
	instance.add_child(core_mesh)
	core_mesh.global_position = position
	core_mesh.scale = Vector3(0.2, 0.2, 0.2)

	var core_tween := instance.create_tween().set_parallel(true)
	core_tween.tween_property(core_mesh, "scale", Vector3(2.5, 2.5, 2.5), 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	core_tween.chain().tween_property(core_mesh, "scale", Vector3(0.1, 0.1, 0.1), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	core_tween.parallel().tween_property(core_mat, "albedo_color:a", 0.0, 0.18)
	core_tween.chain().tween_callback(core_mesh.queue_free)

	# 4. Explosion Screen Shake
	var rigs = instance.get_tree().get_nodes_in_group("camera_rig")
	if not rigs.is_empty() and rigs[0].has_method("add_shake"):
		var shake_str: float = clampf(radius * 0.05, 0.35, 0.65)
		rigs[0].add_shake(shake_str)

	# 5. Sound
	if AudioManager:
		AudioManager.play_explosion(position)

	# 6. Flying Fiery Sparks Particle Burst
	var explosion = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.7

	explosion.process_material = mat
	explosion.amount = 36
	explosion.lifetime = 0.55
	explosion.one_shot = true
	explosion.explosiveness = 0.95
	explosion.emitting = true

	var spark_inst = MeshInstance3D.new()
	var spark_sphere = SphereMesh.new()
	spark_sphere.radius = 0.15
	spark_inst.mesh = spark_sphere
	var particle_mat = StandardMaterial3D.new()
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.albedo_color = Color(1.0, 0.55, 0.15, 1.0)
	particle_mat.emission_enabled = true
	particle_mat.emission = Color(1.0, 0.5, 0.1)
	particle_mat.emission_energy_multiplier = 4.0
	spark_inst.material_override = particle_mat
	explosion.add_child(spark_inst)

	instance.add_child(explosion)
	explosion.global_position = position

	# 7. Billowing Smoke Puff
	var smoke = GPUParticles3D.new()
	var smoke_mat = ParticleProcessMaterial.new()
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 80.0
	smoke_mat.initial_velocity_min = 3.0
	smoke_mat.initial_velocity_max = 7.0
	smoke_mat.gravity = Vector3(0, 2.5, 0)
	smoke_mat.scale_min = 0.5
	smoke_mat.scale_max = 1.4

	smoke.process_material = smoke_mat
	smoke.amount = 20
	smoke.lifetime = 0.9
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.emitting = true

	var smoke_inst = MeshInstance3D.new()
	var smoke_sphere = SphereMesh.new()
	smoke_sphere.radius = 0.3
	smoke_inst.mesh = smoke_sphere
	var sm_mat = StandardMaterial3D.new()
	sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm_mat.albedo_color = Color(0.2, 0.2, 0.22, 0.6)
	smoke_inst.material_override = sm_mat
	smoke.add_child(smoke_inst)

	instance.add_child(smoke)
	smoke.global_position = position

	var cleanup_tween := explosion.create_tween()
	cleanup_tween.tween_interval(1.1)
	cleanup_tween.tween_callback(explosion.queue_free)
	cleanup_tween.tween_callback(smoke.queue_free)


## Deals area of effect explosion damage.
## - Pilots on foot (unarmored humans) take DEVASTATING damage (2.2x multiplier, lethal).
## - Armored Mechas with composite steel plating take moderated damage (0.75x multiplier, chipped armor).
static func apply_area_explosion_damage(
	blast_pos: Vector3,
	base_damage: float,
	radius: float = 8.0,
	fired_by_enemy: bool = false,
	damage_type: String = "explosive",
	exclude_node: Node = null
) -> void:
	if instance == null or instance.get_tree() == null:
		return

	var candidates: Array = []
	var tree := instance.get_tree()

	if fired_by_enemy:
		candidates.append_array(tree.get_nodes_in_group("mecha"))
		candidates.append_array(tree.get_nodes_in_group("pilot"))
		candidates.append_array(tree.get_nodes_in_group("ally"))
	else:
		candidates.append_array(tree.get_nodes_in_group("enemy"))
		candidates.append_array(tree.get_nodes_in_group("enemy_pilot"))

	for target in candidates:
		if not is_instance_valid(target) or target == exclude_node:
			continue

		var target_pos: Vector3 = target.global_position
		if target.is_in_group("mecha") or target.is_in_group("enemy") or target.is_in_group("ally"):
			target_pos += Vector3(0, 1.5, 0)
		else:
			target_pos += Vector3(0, 0.8, 0)

		var dist: float = blast_pos.distance_to(target_pos)
		if dist > radius:
			continue

		# Linear distance falloff: 100% at center down to 35% at the edge
		var falloff: float = clampf(1.0 - 0.65 * (dist / radius), 0.35, 1.0)
		var is_pilot: bool = target.is_in_group("pilot") or target.is_in_group("enemy_pilot")

		# Multiplier: Pilots (flesh/infantry) take 2.2x lethal explosion damage;
		# Mechas (heavy composite plating) absorb/deflect blast pressure, taking 0.75x chip damage.
		var type_mult: float = 2.2 if is_pilot else 0.75
		var final_dmg: float = base_damage * falloff * type_mult

		if target.has_method("take_damage_at_point"):
			target.take_damage_at_point(final_dmg, blast_pos, damage_type)
		elif target.has_method("take_damage"):
			target.take_damage(final_dmg, damage_type)

		# Knockback / impact push from blast center
		var push_dir: Vector3 = (target.global_position - blast_pos)
		push_dir.y = 0.0
		if push_dir.length_squared() > 0.01:
			push_dir = push_dir.normalized()
			if target.has_method("apply_impact"):
				target.apply_impact(15.0 * falloff, push_dir)
			elif target is CharacterBody3D:
				target.velocity += push_dir * (20.0 * falloff if is_pilot else 5.0 * falloff)

		var num_color := Color(1.0, 0.3, 0.2) if is_pilot else Color(1.0, 0.65, 0.15)
		spawn_damage_number(target.global_position + Vector3(0, 1.8 if is_pilot else 2.5, 0), final_dmg, num_color)


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


# Small burst of orange sparks + puff of grey smoke at a weapon barrel,
# used for reload-fail / jam feedback. Much lighter than a muzzle flash.
static func spawn_jam_sparks(position: Vector3) -> void:
	if instance == null:
		return

	# 1. Tiny spark burst (orange sparks shooting outward)
	var sparks := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	sparks.process_material = mat
	sparks.amount = 10
	sparks.lifetime = 0.3
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	var spark_mesh := MeshInstance3D.new()
	var spark_sphere := SphereMesh.new()
	spark_sphere.radius = 0.03
	spark_mesh.mesh = spark_sphere
	var spark_mat := StandardMaterial3D.new()
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.7, 0.2, 0.95)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.6, 0.1)
	spark_mat.emission_energy_multiplier = 5.0
	spark_mesh.material_override = spark_mat
	sparks.add_child(spark_mesh)
	instance.add_child(sparks)
	sparks.global_position = position

	var spark_tween := sparks.create_tween()
	spark_tween.tween_interval(0.35)
	spark_tween.tween_callback(sparks.queue_free)

	# 2. Small grey smoke puff
	var smoke := GPUParticles3D.new()
	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 60.0
	smoke_mat.initial_velocity_min = 1.0
	smoke_mat.initial_velocity_max = 2.5
	smoke_mat.gravity = Vector3(0, 0.5, 0)
	smoke_mat.scale_min = 0.08
	smoke_mat.scale_max = 0.18
	smoke.process_material = smoke_mat
	smoke.amount = 6
	smoke.lifetime = 0.6
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.emitting = true
	var smoke_mesh := MeshInstance3D.new()
	var smoke_sphere := SphereMesh.new()
	smoke_sphere.radius = 0.08
	smoke_mesh.mesh = smoke_sphere
	var smoke_std := StandardMaterial3D.new()
	smoke_std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_std.albedo_color = Color(0.5, 0.5, 0.5, 0.6)
	smoke_mesh.material_override = smoke_std
	smoke.add_child(smoke_mesh)
	instance.add_child(smoke)
	smoke.global_position = position + Vector3(0, 0.1, 0)

	var smoke_tween := smoke.create_tween()
	smoke_tween.tween_interval(0.7)
	smoke_tween.tween_callback(smoke.queue_free)

	# 3. Tiny flash light (warm orange, short-lived)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.1)
	light.light_energy = 2.0
	light.omni_range = 3.0
	light.omni_attenuation = 2.0
	instance.add_child(light)
	light.global_position = position
	var light_tween := instance.create_tween()
	light_tween.tween_property(light, "light_energy", 0.0, 0.15)
	light_tween.tween_callback(light.queue_free)
