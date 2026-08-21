extends CharacterBody3D

const EffectFactory = preload("res://scripts/effects/effect_factory.gd")

var speed: float = 50.0
var damage: float = 25.0
var damage_type: String = "kinetic"
var impact: float = 0.0
var lifetime: float = 5.0
var timer: float = 0.0
var trail_timer: float = 0.0
var direction: Vector3 = Vector3.FORWARD
var fired_by_enemy: bool = false
# Railgun rounds leave a shrinking sonic-boom ring along their flight path.
var sonic_boom: bool = false
var ricochet_chance: float = 0.15
var prev_position: Vector3
var explosion_radius: float = 3.0
# Gravity pull (m/s^2) applied to the projectile so shots arc and drop over
# distance instead of flying perfectly straight forever.
var drop_gravity: float = 3.0
# Close-range shots stay laser-flat: gravity only starts pulling once the shot
# has travelled this far, so point-blank hits never sag below the crosshair.
var drop_start_distance: float = 15.0
var _traveled: float = 0.0
var _drop_speed: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
	prev_position = global_position


func get_damage() -> float:
	return damage


func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return

	prev_position = global_position
	var step := speed * delta
	position += direction * step
	_traveled += step

	# Bullet drop: accumulate downward velocity each frame so long shots sag
	# toward the ground (ground/cover is caught by the between-frame raycast).
	# Gravity only engages after `drop_start_distance` so close-range shots fly
	# flat; beyond that they arc gently with the reduced pull.
	if _traveled > drop_start_distance:
		_drop_speed += drop_gravity * delta
		position.y -= _drop_speed * delta

	# Check for obstacle (cover) collision using raycast between frames
	_check_obstacle_collision()

	if fired_by_enemy:
		# Enemy projectile -> check for player mecha, fielded allies, and the
		# player pilot on foot (dismounted pilots are shootable — same rule as
		# the enemy pilots, so no pilot can hide forever on foot).
		var targets: Array = []
		targets.append_array(get_tree().get_nodes_in_group("mecha"))
		targets.append_array(get_tree().get_nodes_in_group("ally"))
		targets.append_array(get_tree().get_nodes_in_group("pilot"))
		for mecha in targets:
			if not is_instance_valid(mecha):
				continue
			var dist = global_position.distance_to(mecha.global_position + Vector3(0, 1.5, 0))
			if dist < 1.5:
				_hit_target(mecha)
				return
	else:
		# Player projectile -> check for enemies (mechs AND ejected enemy pilots:
		# the pilot is in the "enemy" group and has take_damage, so a fleeing
		# pilot can be shot down instead of always getting away).
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			var dist = global_position.distance_to(enemy.global_position + Vector3(0, 1.5, 0))
			if dist < 1.5:
				_hit_target(enemy)
				return

	# Fallback: explode below the lowest possible terrain (global safety net at
	# top ~ -2.5). Real terrain (banks, bridges, riverbed) is already caught by
	# the raycast above.
	if global_position.y <= -2.5:
		if damage_type.to_lower() == "explosive":
			_explode(global_position)
		else:
			EffectManager.spawn_hit_spark(global_position, Vector3.UP, damage_type)
		queue_free()
		return

	trail_timer += delta
	if trail_timer >= 0.03:
		trail_timer = 0.0
		_spawn_trail()
		if sonic_boom:
			_spawn_sonic_boom_ring()


func _check_obstacle_collision() -> void:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(prev_position, global_position)
	# Layer 2 = Environment (cover objects, walls)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result["collider"]
		var hit_pos = result["position"]
		var hit_normal = result["normal"]

		# Deal damage to cover
		if collider.has_method("take_damage"):
			collider.take_damage(damage, damage_type)

		if damage_type.to_lower() == "explosive":
			_explode(hit_pos)
			queue_free()
			return

		EffectManager.spawn_hit_spark(hit_pos, hit_normal, damage_type)

		# Ricochet check: some bullets bounce off
		if randf() < ricochet_chance:
			_ricochet(hit_pos, hit_normal)
		else:
			queue_free()


func _ricochet(hit_pos: Vector3, normal: Vector3) -> void:
	# Reflect direction off the surface normal
	direction = direction.bounce(normal).normalized()
	_drop_speed = 0.0
	_traveled = 0.0
	prev_position = hit_pos
	global_position = hit_pos + normal * 0.1
	# Reduce damage on ricochet
	damage *= 0.5
	ricochet_chance *= 0.5  # Less likely to ricochet again


func _hit_target(target: Node3D) -> void:
	var final_damage = damage
	if damage_type.to_lower() == "melee" and GlobalData.weapons.chassis_id == "brawler":
		final_damage *= 1.4

	if damage_type.to_lower() == "explosive":
		_explode(position)
		return

	EffectManager.spawn_hit_spark(position, -direction if direction.length_squared() > 0.001 else Vector3.UP, damage_type)
	if AudioManager:
		AudioManager.play_impact_by_type(damage_type, position)

	if target.has_method("take_damage_at_point"):
		target.take_damage_at_point(final_damage, position, damage_type)
	elif target.has_method("take_damage"):
		target.take_damage(final_damage, damage_type)

	if target.has_method("apply_impact") and impact > 0.0:
		target.apply_impact(impact, direction)

	EffectManager.spawn_damage_number(position + Vector3(0, 1.5, 0), final_damage, Color.WHITE)
	queue_free()


func _explode(blast_pos: Vector3) -> void:
	EffectManager.spawn_explosion(blast_pos, explosion_radius)
	if get_tree():
		EffectFactory.spawn_fire_burst(get_tree(), blast_pos, maxf(explosion_radius * 0.7, 0.8), 0.45, 6.0)
		EffectFactory.spawn_smoke_plume(get_tree(), blast_pos, 6, 0.3, 0.6, 0.9)
		EffectFactory.spawn_burning_ground(get_tree(), blast_pos, maxf(explosion_radius * 0.8, 1.0), 2.5)
	EffectManager.apply_area_explosion_damage(blast_pos, damage, explosion_radius, fired_by_enemy, damage_type)
	queue_free()


func _spawn_trail() -> void:
	EffectFactory.spawn_trail_dir(get_tree(), global_position, direction,
		Vector3(0.02, 0.02, 0.15), Color(1, 0.8, 0.3, 0.9),
		Color(1, 0.7, 0.2), 0.2, 3.0)


# A railgun round tears the air as it passes: a bright expanding shockwave ring
# (torus) that swells out from the flight line and fades, reading as the sonic
# boom cutting through the air along the projectile's path.
func _spawn_sonic_boom_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 12
	ring.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.9, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.85, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat

	# Ring lies in the plane perpendicular to the flight line.
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	ring.look_at(global_position + direction, Vector3.UP)
	ring.rotate_object_local(Vector3.FORWARD, deg_to_rad(90.0))

	var tween := get_tree().create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.2, 3.2, 1.0), 0.28) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tween.chain().tween_callback(ring.queue_free)
