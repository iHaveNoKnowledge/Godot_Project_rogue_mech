@tool
class_name EngageRangedAction
extends ActionLeaf
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")


## Controls ranged aiming, positioning, strafing, and firing on target.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null or not is_instance_valid(actor):
		return FAILURE
	
	var target: Node3D = blackboard.get_value("combat_target")
	if target == null or not is_instance_valid(target):
		return FAILURE
	
	var profile: Dictionary = blackboard.get_value("personality_profile", {})
	var max_range: float = float(actor.get("attack_range")) if actor.get("attack_range") != null else 50.0
	var range_factor: float = float(profile.get("optimal_range_factor", 0.75))
	var ideal_dist := max_range * range_factor
	
	var actor_pos: Vector3 = (actor as Node3D).global_position
	var target_pos: Vector3 = target.global_position
	var diff: Vector3 = target_pos - actor_pos
	diff.y = 0.0
	var dist: float = diff.length()
	
	# Turn toward target smoothly
	if diff.length_squared() > 0.01:
		var target_yaw: float = atan2(-diff.x, -diff.z)
		(actor as Node3D).rotation.y = lerp_angle((actor as Node3D).rotation.y, target_yaw, 0.15)
	
	# Movement positioning (Tactical Flanking & Boid Separation)
	var move_speed: float = float(actor.get("move_speed")) if actor.get("move_speed") != null else 4.0
	var delta: float = actor.get_physics_process_delta_time() if actor.has_method("get_physics_process_delta_time") else 0.016
	
	var coordinator: EnemySquadCoordinator = blackboard.get_value("squad_coordinator")
	if coordinator == null and actor.get("squad_coordinator") != null:
		coordinator = actor.squad_coordinator
	
	var target_waypoint: Vector3
	if coordinator != null and is_instance_valid(coordinator):
		target_waypoint = coordinator.get_tactical_waypoint(actor as Node3D, target, ideal_dist)
	else:
		target_waypoint = target_pos - diff.normalized() * ideal_dist

	var to_waypoint := target_waypoint - actor_pos
	to_waypoint.y = 0.0
	var waypoint_dist := to_waypoint.length()

	var move_dir := Vector3.ZERO
	if waypoint_dist > 2.5:
		move_dir = to_waypoint.normalized()
	else:
		# Small lateral strafing when holding flanking slot
		var strafe_dir: float = blackboard.get_value("strafe_dir", 1.0)
		var strafe_timer: float = blackboard.get_value("strafe_timer", 0.0) - delta
		if strafe_timer <= 0.0:
			strafe_dir = -strafe_dir if randf() < 0.6 else strafe_dir
			strafe_timer = randf_range(1.5, 3.5)
			blackboard.set_value("strafe_dir", strafe_dir)
		blackboard.set_value("strafe_timer", strafe_timer)
		
		var perp: Vector3 = Vector3(-diff.z, 0, diff.x).normalized() * strafe_dir
		move_dir = perp * 0.5

	# Add Mutual Boids Separation Force to prevent blobbing
	var separation := Vector3.ZERO
	if coordinator != null and is_instance_valid(coordinator):
		separation = coordinator.get_separation_vector(actor as Node3D, 7.0)

	var raw_dir := (move_dir + separation * 1.5).normalized() if (move_dir + separation * 1.5).length() > 0.01 else Vector3.ZERO
	if raw_dir.length() > 0.01:
		var space := (actor as Node3D).get_world_3d().direct_space_state if (actor as Node3D).get_world_3d() else null
		raw_dir = _NavAvoidance.steer_around(raw_dir, (actor as Node3D).global_position, space, 2.8) if space else raw_dir
	var final_velocity := raw_dir * move_speed
	(actor as CharacterBody3D).velocity.x = final_velocity.x
	(actor as CharacterBody3D).velocity.z = final_velocity.z
	(actor as CharacterBody3D).velocity.y = -10.0
	(actor as CharacterBody3D).move_and_slide()
	if (actor as CharacterBody3D).get_slide_collision_count() > 0:
		var flat := Vector3(final_velocity.x, 0, final_velocity.z)
		flat = _NavAvoidance.slide_along_wall(flat, actor as CharacterBody3D)
		(actor as CharacterBody3D).velocity.x = flat.x
		(actor as CharacterBody3D).velocity.z = flat.z
		(actor as CharacterBody3D).velocity.y = -10.0
		(actor as CharacterBody3D).move_and_slide()
	
	# Trigger weapon fire
	if actor.has_method("_fire_ranged") and dist <= max_range:
		var atk_timer: float = float(actor.get("attack_timer")) if actor.get("attack_timer") != null else 0.0
		if atk_timer <= 0.0:
			actor.call("_fire_ranged")
			actor.set("attack_timer", float(actor.get("attack_cooldown")) if actor.get("attack_cooldown") != null else 0.9)
	
	return RUNNING
