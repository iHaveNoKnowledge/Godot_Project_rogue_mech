extends EnemyState

## Attack state: execute attack when in range.

var attack_timer: float = 0.0
var strafe_timer: float = 0.0
var strafe_direction: float = 0.0


func enter() -> void:
	attack_timer = 0.0
	strafe_timer = 0.0
	strafe_direction = [-1.0, 1.0][randi() % 2]


func physics_process(delta: float) -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	var distance = enemy.global_position.distance_to(enemy.target.global_position)

	# If target moved out of range, chase again
	if distance > enemy.attack_range * 1.2:
		state_machine.transition_to("StateChase")
		return

	# Low HP check
	if enemy.health_system and _is_low_hp():
		state_machine.transition_to("StateFlee")
		return

	# Face target
	var direction = (enemy.target.global_position - enemy.global_position).normalized()
	direction.y = 0.0
	if direction.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 8.0 * delta)

	# Slight strafe while attacking
	strafe_timer += delta
	if strafe_timer > 2.0:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	var strafe = enemy.global_transform.basis.x * strafe_direction * enemy.move_speed * 0.3
	enemy.velocity = strafe
	enemy.velocity.y = -10.0
	enemy.move_and_slide()

	# Attack
	attack_timer -= delta
	if attack_timer <= 0.0:
		attack_timer = enemy.attack_cooldown
		_perform_attack()


func _perform_attack() -> void:
	var archetype = enemy.get("archetype", 0)

	match archetype:
		0:  # RUSHER - melee
			if enemy.target and enemy.target.has_method("take_damage"):
				enemy.target.take_damage(enemy.attack_damage, "melee")
		1:  # RANGED - projectile
			_fire_ranged()
		2:  # HEAVY - charge (handled by state_charge)
			pass
		3:  # SUPPORT - heal nearest ally
			_heal_nearest_ally()


func _heal_nearest_ally() -> void:
	var enemies = enemy.get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0

	for e in enemies:
		if not is_instance_valid(e) or e == enemy:
			continue
		if not e.health_system or e.health_system.is_destroyed:
			continue
		var dist = enemy.global_position.distance_to(e.global_position)
		if dist < 40.0 and dist < nearest_dist:
			nearest = e
			nearest_dist = dist

	if nearest and nearest.health_system and nearest.health_system.has_method("take_heal"):
		nearest.health_system.take_heal(5.0)
		# Visual feedback
		EffectManager.spawn_damage_number(nearest.global_position + Vector3(0, 3, 0), 5.0, Color(0.2, 1.0, 0.2))


func _fire_ranged() -> void:
	var projectile_scene = preload("res://scenes/mecha/effects/projectile.tscn")
	var projectile = projectile_scene.instantiate()
	enemy.get_tree().current_scene.add_child(projectile)
	projectile.global_position = enemy.global_position + Vector3(0, 2, 0)

	var dir = (enemy.target.global_position - enemy.global_position).normalized()
	projectile.speed = 30.0
	projectile.damage = enemy.attack_damage
	projectile.damage_type = "kinetic"
	projectile.fired_by_enemy = true
	projectile.direction = dir
	projectile.look_at(enemy.target.global_position, Vector3.UP)


func _is_low_hp() -> bool:
	if not enemy.health_system:
		return false
	var total_frame = 0.0
	var max_frame = 0.0
	for slot in enemy.health_system.parts:
		total_frame += enemy.health_system.parts[slot]["frame_hp"]
		max_frame += enemy.health_system.parts[slot]["max_frame"]
	return total_frame / max(max_frame, 1.0) < 0.3
