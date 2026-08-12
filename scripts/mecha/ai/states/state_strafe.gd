extends EnemyState

## Strafe state: ranged enemies circle-strafe while firing.

var strafe_angle: float = 0.0
var strafe_speed: float = 2.0
var fire_timer: float = 0.0


func enter() -> void:
	strafe_angle = randf() * TAU
	fire_timer = 0.0


func physics_process(delta: float) -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	var distance = enemy.global_position.distance_to(enemy.target.global_position)

	# If too close, chase away
	if distance < enemy.attack_range * 0.5:
		state_machine.transition_to("StateChase")
		return

	# Circle strafe
	strafe_angle += strafe_speed * delta
	var circle_radius = distance
	var target_pos = enemy.target.global_position
	var strafe_pos = target_pos + Vector3(
		cos(strafe_angle) * circle_radius,
		0,
		sin(strafe_angle) * circle_radius
	)

	var move_dir = (strafe_pos - enemy.global_position).normalized()
	move_dir.y = 0.0
	enemy.velocity = move_dir * enemy.move_speed
	enemy.velocity.y = -10.0
	enemy.move_and_slide()

	# Face target
	var face_dir = (target_pos - enemy.global_position).normalized()
	face_dir.y = 0.0
	if face_dir.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(face_dir.x, face_dir.z), 8.0 * delta)

	# Fire
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = enemy.attack_cooldown
		if enemy.has_ammo():
			_fire_at_target()
		else:
			# Out of ammo — chase to reposition while reloading
			state_machine.transition_to("StateChase")


func _fire_at_target() -> void:
	var from_pos = enemy.global_position + Vector3(0, 2, 0)
	var dir = (enemy.target.global_position - enemy.global_position).normalized()
	# Spawn through the shared WeaponCore (cooldown/ammo/heat all owned there).
	if enemy.fire_core:
		enemy.fire_core.try_fire(from_pos, dir, true, enemy)
