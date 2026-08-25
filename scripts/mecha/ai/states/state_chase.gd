extends EnemyState
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")


## Chase state: move toward target using NavMesh pathfinding.

var gravity: float = -10.0
var path: PackedVector3Array = []
var path_index: int = 0
var path_update_timer: float = 0.0
const PATH_UPDATE_INTERVAL: float = 0.5
var _stuck_time: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO


func enter() -> void:
	path = []
	path_index = 0
	path_update_timer = 0.0
	_stuck_time = 0.0
	_last_pos = enemy.global_position if enemy else Vector3.ZERO
	# Shield archetypes advance with the barrier up so closing in doesn't cost
	# them HP; it drops only when they commit to an attack (state_attack).
	if enemy and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)


func physics_process(delta: float) -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return
	# A parked mech (pilot ejected) is no longer a threat — drop it and
	# re-acquire a live target (the pilot on foot, an ally, etc.).
	if enemy.target.has_meta("is_parked"):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	var distance = enemy.global_position.distance_to(enemy.target.global_position)

	# Transition to attack if in range (but not while reloading). Heavies fight
	# with their charge instead of the generic attack (whose heavy branch is a
	# no-op), so route them to StateCharge.
	if distance <= enemy.attack_range:
		if not enemy.is_reloading:
			if enemy.archetype == 2:
				state_machine.transition_to("StateCharge")
			else:
				state_machine.transition_to("StateAttack")
		return

	# Drained pool: the enemy withdraws to recharge instead of fighting on empty.
	if enemy.is_low_energy():
		enemy.flee_reason = "energy"
		state_machine.transition_to("StateFlee")
		return

	# Check if low HP -> flee
	if enemy.health_system and _is_low_hp():
		enemy.flee_reason = "hp"
		state_machine.transition_to("StateFlee")
		return

	# Rushers lunge: when the target is a short hop away (past melee range but
	# well within burst reach) the rusher dashes straight at the player instead
	# of slowly walking. Only in combat (this state) — never while patrolling.
	# The dash costs energy and has a cooldown, so it can't be spammed.
	if enemy.archetype == 0 and distance > enemy.attack_range and distance < 22.0:
		var dir: Vector3 = enemy.target.global_position - enemy.global_position
		dir.y = 0.0
		if enemy.start_dash(dir):
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
	if enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
		target_pos = enemy.squad_coordinator.get_tactical_waypoint(enemy, enemy.target, enemy.attack_range * 0.7)

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

	# Move toward waypoint with mutual separation + local obstacle avoidance
	if direction.length() > 0.1 and enemy.get("ragdolled") != true:
		var separation := Vector3.ZERO
		if enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
			separation = enemy.squad_coordinator.get_separation_vector(enemy, 6.0)

		var raw_dir: Vector3 = (direction.normalized() + separation * 1.3).normalized()
		# Raycast avoidance: steer around Environment (layer 2) blocking the way
		var space := enemy.get_world_3d().direct_space_state if enemy.get_world_3d() else null
		var move_dir: Vector3 = _NavAvoidance.steer_around(raw_dir, enemy.global_position, space, 3.5) if space else raw_dir
		enemy.velocity = move_dir * enemy.move_speed
		enemy.velocity.y = gravity
		enemy.move_and_slide()
		# If slid into a wall, nudge along the wall so we don't stick in corners
		if enemy.get_slide_collision_count() > 0:
			enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)
			# If still barely moving, count as stuck and force a repath + wide steer
			if enemy.velocity.length() < 1.0:
				_stuck_time += delta
				if _stuck_time > 0.6:
					path_update_timer = 0.0
					_stuck_time = 0.0
					# Hard 90° escape
					var escape := raw_dir.rotated(Vector3.UP, deg_to_rad(90.0 if randf() < 0.5 else -90.0))
					enemy.velocity = escape * enemy.move_speed
					enemy.velocity.y = gravity
					enemy.move_and_slide()
			else:
				_stuck_time = 0.0
		else:
			# Reset stuck timer when making progress
			if enemy.global_position.distance_to(_last_pos) > 0.4:
				_stuck_time = 0.0
			else:
				_stuck_time += delta
				if _stuck_time > 1.0:
					path_update_timer = 0.0
					_stuck_time = 0.0
			_last_pos = enemy.global_position

		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _direct_move(delta: float) -> void:
	# Fallback: tactical movement toward target slot + separation + raycast steer
	var target_pos: Vector3 = enemy.target.global_position
	if enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
		target_pos = enemy.squad_coordinator.get_tactical_waypoint(enemy, enemy.target, enemy.attack_range * 0.7)

	var direction = (target_pos - enemy.global_position)
	direction.y = 0.0

	var separation := Vector3.ZERO
	if enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
		separation = enemy.squad_coordinator.get_separation_vector(enemy, 6.0)

	var raw_dir = (direction.normalized() + separation * 1.3).normalized()
	var space := enemy.get_world_3d().direct_space_state if enemy.get_world_3d() else null
	var move_dir = _NavAvoidance.steer_around(raw_dir, enemy.global_position, space, 3.5) if space else raw_dir
	if enemy.get("ragdolled") != true:
		enemy.velocity = move_dir * enemy.move_speed
		enemy.velocity.y = gravity
		enemy.move_and_slide()
		if enemy.get_slide_collision_count() > 0:
			enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)

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
