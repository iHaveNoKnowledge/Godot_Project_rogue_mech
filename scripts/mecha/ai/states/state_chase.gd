extends EnemyState

## Chase state: move toward target using NavMesh pathfinding.

var gravity: float = -10.0
var path: PackedVector3Array = []
var path_index: int = 0
var path_update_timer: float = 0.0
const PATH_UPDATE_INTERVAL: float = 0.5


func enter() -> void:
	path = []
	path_index = 0
	path_update_timer = 0.0


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

	# Update path periodically
	path_update_timer -= delta
	if path_update_timer <= 0.0 or path.is_empty():
		path_update_timer = PATH_UPDATE_INTERVAL
		_update_path()

	# Follow path
	_follow_path(delta)


func _update_path() -> void:
	var maps = NavigationServer3D.get_maps()
	if maps.is_empty():
		return

	var start_pos = enemy.global_position
	var target_pos = enemy.target.global_position

	path = NavigationServer3D.map_get_path(maps[0], start_pos, target_pos, true)
	path_index = 0


func _follow_path(delta: float) -> void:
	if path.is_empty():
		# Direct movement fallback
		_direct_move(delta)
		return

	# Get current waypoint
	if path_index >= path.size():
		path_index = path.size() - 1

	var waypoint = path[path_index]
	var direction = (waypoint - enemy.global_position)
	direction.y = 0.0

	# If close to waypoint, move to next
	if direction.length() < 1.5:
		path_index += 1
		if path_index >= path.size():
			_direct_move(delta)
			return
		waypoint = path[path_index]
		direction = (waypoint - enemy.global_position)
		direction.y = 0.0

	# Move toward waypoint
	if direction.length() > 0.1:
		enemy.velocity = direction.normalized() * enemy.move_speed
		enemy.velocity.y = gravity
		enemy.move_and_slide()

		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _direct_move(delta: float) -> void:
	# Fallback: direct movement toward target (no pathfinding)
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
