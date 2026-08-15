extends EnemyState

## Flee state: move away from target using NavMesh pathfinding.

var gravity: float = -10.0
var flee_timer: float = 0.0
var path: PackedVector3Array = []
var path_index: int = 0


func enter() -> void:
	flee_timer = 0.0
	path = []
	path_index = 0
	if not _has_valid_target():
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return
	_update_flee_path()


func physics_process(delta: float) -> void:
	flee_timer += delta

	# Validate the target first — everything below dereferences it.
	if not _has_valid_target():
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	# After fleeing for a while, reassess. An energy-fleeing enemy only returns
	# once the pool recharges (it withdrew to recharge); a hurt one returns as
	# soon as it is no longer critically damaged.
	if flee_timer > 3.0:
		if enemy.flee_reason == "energy":
			if enemy.energy >= enemy.RECHARGED_ENERGY:
				enemy.flee_reason = ""
				state_machine.transition_to("StateChase")
				return
		else:
			if not _is_low_hp():
				enemy.flee_reason = ""
				state_machine.transition_to("StateChase")
				return
		flee_timer = 0.0
		_update_flee_path()

	# Follow flee path
	if path.is_empty():
		_direct_flee(delta)
		return

	if path_index >= path.size():
		path_index = path.size() - 1

	var waypoint = path[path_index]
	var direction = (waypoint - enemy.global_position)
	direction.y = 0.0

	if direction.length() < 1.5:
		path_index += 1
		if path_index >= path.size():
			_direct_flee(delta)
			return
		waypoint = path[path_index]
		direction = (waypoint - enemy.global_position)
		direction.y = 0.0

	if direction.length() > 0.1:
		enemy.velocity = direction.normalized() * enemy.move_speed * 1.2
		enemy.velocity.y = gravity
		enemy.move_and_slide()

		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _has_valid_target() -> bool:
	return enemy.target != null and is_instance_valid(enemy.target)


func _update_flee_path() -> void:
	if not _has_valid_target():
		return
	var maps = NavigationServer3D.get_maps()
	if maps.is_empty():
		return

	var away_dir = (enemy.global_position - enemy.target.global_position).normalized()
	away_dir.y = 0.0
	away_dir = away_dir.rotated(Vector3.UP, randf_range(-0.5, 0.5)).normalized()

	var flee_target = enemy.global_position + away_dir * 30.0
	flee_target.y = 0.0

	path = NavigationServer3D.map_get_path(maps[0], enemy.global_position, flee_target, true)
	path_index = 0


func _direct_flee(delta: float) -> void:
	if not _has_valid_target():
		return
	var away_dir = (enemy.global_position - enemy.target.global_position).normalized()
	away_dir.y = 0.0
	away_dir = away_dir.rotated(Vector3.UP, randf_range(-0.5, 0.5)).normalized()

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
