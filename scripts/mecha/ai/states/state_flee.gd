extends EnemyState

## Flee state: move away from target toward cover or edge.

var gravity: float = -10.0
var flee_timer: float = 0.0


func enter() -> void:
	flee_timer = 0.0


func physics_process(delta: float) -> void:
	flee_timer += delta

	# After fleeing for a while, reassess
	if flee_timer > 3.0:
		# If HP recovered, go back to chase
		if not _is_low_hp():
			state_machine.transition_to("StateChase")
			return
		# If still low HP, keep fleeing but pick new direction
		flee_timer = 0.0

	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	# Move away from target
	var away_dir = (enemy.global_position - enemy.target.global_position).normalized()
	away_dir.y = 0.0

	# Add some randomness to avoid running straight back
	away_dir = away_dir.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	away_dir = away_dir.normalized()

	enemy.velocity = away_dir * enemy.move_speed * 1.2
	enemy.velocity.y = gravity
	enemy.move_and_slide()

	if away_dir.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(away_dir.x, away_dir.z), 5.0 * delta)


func _is_low_hp() -> bool:
	if not enemy.health_system:
		return false
	var total_frame = 0.0
	var max_frame = 0.0
	for slot in enemy.health_system.parts:
		total_frame += enemy.health_system.parts[slot]["frame_hp"]
		max_frame += enemy.health_system.parts[slot]["max_frame"]
	return total_frame / max(max_frame, 1.0) < 0.3
