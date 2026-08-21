@tool
class_name EngageRangedAction
extends ActionLeaf

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
	
	# Movement positioning (Kiting / Closing in)
	var move_speed: float = float(actor.get("move_speed")) if actor.get("move_speed") != null else 4.0
	var delta: float = actor.get_physics_process_delta_time() if actor.has_method("get_physics_process_delta_time") else 0.016
	
	if dist > ideal_dist + 4.0:
		# Move forward toward target
		var dir: Vector3 = diff.normalized()
		(actor as CharacterBody3D).velocity.x = dir.x * move_speed
		(actor as CharacterBody3D).velocity.z = dir.z * move_speed
	elif dist < ideal_dist - 4.0:
		# Back up away from target
		var dir: Vector3 = -diff.normalized()
		(actor as CharacterBody3D).velocity.x = dir.x * move_speed * 0.7
		(actor as CharacterBody3D).velocity.z = dir.z * move_speed * 0.7
	else:
		# Strafe left/right around target
		var strafe_dir: float = blackboard.get_value("strafe_dir", 1.0)
		var strafe_timer: float = blackboard.get_value("strafe_timer", 0.0) - delta
		if strafe_timer <= 0.0:
			strafe_dir = -strafe_dir if randf() < 0.6 else strafe_dir
			strafe_timer = randf_range(1.5, 3.5)
			blackboard.set_value("strafe_dir", strafe_dir)
		blackboard.set_value("strafe_timer", strafe_timer)
		
		var perp: Vector3 = Vector3(-diff.z, 0, diff.x).normalized() * strafe_dir
		(actor as CharacterBody3D).velocity.x = perp.x * move_speed * 0.6
		(actor as CharacterBody3D).velocity.z = perp.z * move_speed * 0.6
	
	# Trigger weapon fire
	if actor.has_method("_fire_ranged") and dist <= max_range:
		var atk_timer: float = float(actor.get("attack_timer")) if actor.get("attack_timer") != null else 0.0
		if atk_timer <= 0.0:
			actor.call("_fire_ranged")
			actor.set("attack_timer", float(actor.get("attack_cooldown")) if actor.get("attack_cooldown") != null else 0.9)
	
	return RUNNING
