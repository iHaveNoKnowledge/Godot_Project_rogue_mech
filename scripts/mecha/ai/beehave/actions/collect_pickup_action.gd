@tool
class_name CollectPickupAction
extends ActionLeaf
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")


## Sprints to a ground ammo/scrap pickup, collects it, and clears scavenge target.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null or not is_instance_valid(actor):
		return FAILURE
	
	var pickup: Node3D = blackboard.get_value("scavenge_target")
	if pickup == null or not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
		blackboard.erase_value("scavenge_target")
		return FAILURE
	
	var actor_pos: Vector3 = (actor as Node3D).global_position
	var pickup_pos: Vector3 = pickup.global_position
	var diff: Vector3 = pickup_pos - actor_pos
	diff.y = 0.0
	var dist: float = diff.length()
	
	var move_speed: float = float(actor.get("move_speed")) if actor.get("move_speed") != null else 4.0
	
	if dist > 2.0:
		var raw_dir: Vector3 = diff.normalized()
		var space := (actor as Node3D).get_world_3d().direct_space_state if (actor as Node3D).get_world_3d() else null
		var dir: Vector3 = _NavAvoidance.steer_around(raw_dir, actor_pos, space, 2.5) if space else raw_dir
		(actor as CharacterBody3D).velocity.x = dir.x * move_speed * 1.25
		(actor as CharacterBody3D).velocity.z = dir.z * move_speed * 1.25
		(actor as CharacterBody3D).velocity.y = -10.0
		(actor as CharacterBody3D).move_and_slide()
		if (actor as CharacterBody3D).get_slide_collision_count() > 0:
			var flat := Vector3(dir.x * move_speed * 1.25, 0, dir.z * move_speed * 1.25)
			flat = _NavAvoidance.slide_along_wall(flat, actor as CharacterBody3D)
			(actor as CharacterBody3D).velocity.x = flat.x
			(actor as CharacterBody3D).velocity.z = flat.z
			(actor as CharacterBody3D).velocity.y = -10.0
			(actor as CharacterBody3D).move_and_slide()
		return RUNNING
	else:
		# Collect pickup
		if actor.has_method("_collect_ammo_pickup"):
			actor.call("_collect_ammo_pickup", pickup)
		elif pickup.has_method("pickup_by"):
			pickup.call("pickup_by", actor)
		else:
			pickup.queue_free()
		
		blackboard.erase_value("scavenge_target")
		return SUCCESS
