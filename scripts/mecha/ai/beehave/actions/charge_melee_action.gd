@tool
class_name ChargeMeleeAction
extends ActionLeaf

## Controls aggressive melee closing, dashing, and blade swinging.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null or not is_instance_valid(actor):
		return FAILURE
	
	var target: Node3D = blackboard.get_value("combat_target")
	if target == null or not is_instance_valid(target):
		return FAILURE
	
	var profile: Dictionary = blackboard.get_value("personality_profile", {})
	var dash_chance: float = float(profile.get("melee_dash_chance", 0.40))
	var move_speed: float = float(actor.get("move_speed")) if actor.get("move_speed") != null else 5.0
	
	var actor_pos: Vector3 = (actor as Node3D).global_position
	var target_pos: Vector3 = target.global_position
	var diff: Vector3 = target_pos - actor_pos
	diff.y = 0.0
	var dist: float = diff.length()
	
	# Turn toward target
	if diff.length_squared() > 0.01:
		var target_yaw: float = atan2(-diff.x, -diff.z)
		(actor as Node3D).rotation.y = lerp_angle((actor as Node3D).rotation.y, target_yaw, 0.20)
	
	# Close distance rapidly
	var dir: Vector3 = diff.normalized()
	var speed: float = move_speed * 1.3 # Sprint into melee
	
	# Dash surge if aggressive
	if dist > 8.0 and randf() < dash_chance * 0.05:
		speed *= 2.0
	
	(actor as CharacterBody3D).velocity.x = dir.x * speed
	(actor as CharacterBody3D).velocity.z = dir.z * speed
	
	# Execute melee strike when in close range (<= 4.0m)
	if dist <= 4.0:
		if actor.has_method("_fire_melee"):
			var atk_timer: float = float(actor.get("attack_timer")) if actor.get("attack_timer") != null else 0.0
			if atk_timer <= 0.0:
				actor.call("_fire_melee")
				actor.set("attack_timer", float(actor.get("attack_cooldown")) if actor.get("attack_cooldown") != null else 1.2)
		return SUCCESS
	
	return RUNNING
