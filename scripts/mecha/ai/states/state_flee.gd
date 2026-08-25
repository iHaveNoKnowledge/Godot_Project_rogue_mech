extends EnemyState
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")


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
	# An energy-drained withdrawal is telegraphed to the player: amber signal
	# flash, pulsing "RETREATING" plate and a one-shot klaxon (set_retreating).
	if enemy.flee_reason == "energy":
		enemy.set_retreating(true)
	_update_flee_path()


func exit() -> void:
	# Clear the retreat feedback the moment the enemy re-engages (or dies) so
	# the plate and amber flash never linger on a mech that's back in the fight.
	if enemy != null and is_instance_valid(enemy):
		enemy.set_retreating(false)


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
			if enemy.energy >= enemy.recharged_energy:
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

	# Frozen while ragdolled — a mech with no legs can't retreat either.
	if direction.length() > 0.1 and enemy.get("ragdolled") != true:
		var raw_dir: Vector3 = direction.normalized()
		var space := enemy.get_world_3d().direct_space_state if enemy.get_world_3d() else null
		var move_dir: Vector3 = _NavAvoidance.steer_around(raw_dir, enemy.global_position, space, 3.0) if space else raw_dir
		enemy.velocity = move_dir * enemy.move_speed * enemy.flee_speed_mult
		enemy.velocity.y = gravity
		enemy.move_and_slide()
		if enemy.get_slide_collision_count() > 0:
			enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)

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
	var space := enemy.get_world_3d().direct_space_state if enemy.get_world_3d() else null
	var move_dir: Vector3 = _NavAvoidance.steer_around(away_dir, enemy.global_position, space, 3.0) if space else away_dir
	enemy.velocity = move_dir * enemy.move_speed * enemy.flee_speed_mult
	enemy.velocity.y = gravity
	enemy.move_and_slide()
	if enemy.get_slide_collision_count() > 0:
		enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)

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
