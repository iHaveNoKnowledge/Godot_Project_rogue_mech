extends CharacterBody3D

var speed: float = 50.0
var damage: float = 25.0
var damage_type: String = "kinetic"
var impact: float = 0.0
var lifetime: float = 5.0
var timer: float = 0.0
var trail_timer: float = 0.0
var direction: Vector3 = Vector3.FORWARD
var fired_by_enemy: bool = false
var ricochet_chance: float = 0.15
var prev_position: Vector3
var explosion_radius: float = 3.0


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
	position += direction * speed * delta

	# Check for obstacle (cover) collision using raycast between frames
	_check_obstacle_collision()

	if fired_by_enemy:
		# Enemy projectile -> check for player mecha and fielded allies
		var targets: Array = []
		targets.append_array(get_tree().get_nodes_in_group("mecha"))
		targets.append_array(get_tree().get_nodes_in_group("ally"))
		for mecha in targets:
			if not is_instance_valid(mecha):
				continue
			var dist = global_position.distance_to(mecha.global_position + Vector3(0, 1.5, 0))
			if dist < 1.5:
				_hit_target(mecha)
				return
	else:
		# Player projectile -> check for enemies
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
			EffectManager.spawn_impact(global_position, Vector3.UP)
		queue_free()
		return

	trail_timer += delta
	if trail_timer >= 0.03:
		trail_timer = 0.0
		_spawn_trail()


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

		EffectManager.spawn_impact(hit_pos, hit_normal)

		# Ricochet check: some bullets bounce off
		if randf() < ricochet_chance:
			_ricochet(hit_pos, hit_normal)
		else:
			queue_free()


func _ricochet(hit_pos: Vector3, normal: Vector3) -> void:
	# Reflect direction off the surface normal
	direction = direction.bounce(normal).normalized()
	prev_position = hit_pos
	global_position = hit_pos + normal * 0.1
	# Reduce damage on ricochet
	damage *= 0.5
	ricochet_chance *= 0.5  # Less likely to ricochet again


func _hit_target(target: Node3D) -> void:
	var final_damage = damage
	if damage_type.to_lower() == "melee" and GlobalData.chassis_id == "brawler":
		final_damage *= 1.4

	if damage_type.to_lower() == "explosive":
		_explode(position)
		return

	EffectManager.spawn_impact(position, Vector3.UP)
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
	EffectManager.spawn_explosion(blast_pos)
	if AudioManager:
		AudioManager.play_explosion(blast_pos)

	var candidates: Array
	if fired_by_enemy:
		candidates.append_array(get_tree().get_nodes_in_group("mecha"))
		candidates.append_array(get_tree().get_nodes_in_group("ally"))
	else:
		candidates.append_array(get_tree().get_nodes_in_group("enemy"))

	for target in candidates:
		if not is_instance_valid(target):
			continue
		var dist = blast_pos.distance_to(target.global_position + Vector3(0, 1.5, 0))
		if dist > explosion_radius:
			continue
		# Falloff: full damage at center, 30% at edge
		var falloff = 1.0 - 0.7 * (dist / explosion_radius)
		var splash_damage = damage * falloff
		if target.has_method("take_damage_at_point"):
			target.take_damage_at_point(splash_damage, blast_pos, damage_type)
		elif target.has_method("take_damage"):
			target.take_damage(splash_damage, damage_type)
		EffectManager.spawn_damage_number(target.global_position + Vector3(0, 1.5, 0), splash_damage, Color(1.0, 0.6, 0.1))
	queue_free()


func _spawn_trail() -> void:
	var trail = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.02, 0.02, 0.15)
	trail.mesh = box

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.8, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.2)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = mat

	get_tree().current_scene.add_child(trail)
	trail.global_position = global_position
	trail.look_at(global_position + direction, Vector3.UP)

	var tween = get_tree().create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.tween_callback(trail.queue_free)
