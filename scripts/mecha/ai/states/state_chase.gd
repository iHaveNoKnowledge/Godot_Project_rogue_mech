extends EnemyState

## Chase state: move toward target.

var gravity: float = -10.0


func enter() -> void:
	pass


func physics_process(delta: float) -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	var distance = enemy.global_position.distance_to(enemy.target.global_position)

	# Transition to attack if in range
	if distance <= enemy.attack_range:
		state_machine.transition_to("StateAttack")
		return

	# Check if low HP -> flee
	if enemy.health_system and _is_low_hp():
		state_machine.transition_to("StateFlee")
		return

	# Move toward target
	var direction = (enemy.target.global_position - enemy.global_position).normalized()
	direction.y = 0.0
	enemy.velocity = direction * enemy.move_speed
	enemy.velocity.y = gravity
	enemy.move_and_slide()

	if direction.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _is_low_hp() -> bool:
	if not enemy.health_system:
		return false
	var total_frame = 0.0
	var max_frame = 0.0
	for slot in enemy.health_system.parts:
		total_frame += enemy.health_system.parts[slot]["frame_hp"]
		max_frame += enemy.health_system.parts[slot]["max_frame"]
	return total_frame / max(max_frame, 1.0) < 0.3
