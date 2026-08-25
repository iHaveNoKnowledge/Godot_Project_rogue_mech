@tool
class_name SeekCoverAction
extends ActionLeaf
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")


## Moves actor to the nearest cover object or retreats away from heavy danger.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null or not is_instance_valid(actor):
		return FAILURE
	
	var tree := actor.get_tree()
	if tree == null:
		return FAILURE
	
	var actor_pos: Vector3 = (actor as Node3D).global_position
	var covers: Array[Node] = tree.get_nodes_in_group("cover_object")
	
	var best_cover: Node3D = null
	var best_dist_sq: float = 60.0 * 60.0
	
	for c in covers:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		var d_sq := actor_pos.distance_squared_to(c.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_cover = c
	
	var move_speed: float = float(actor.get("move_speed")) if actor.get("move_speed") != null else 4.0
	
	if best_cover != null:
		var target_pos: Vector3 = best_cover.global_position
		var diff := target_pos - actor_pos
		diff.y = 0.0
		var dist := diff.length()
		
		if dist > 2.0:
			var raw_dir := diff.normalized()
			var space := (actor as Node3D).get_world_3d().direct_space_state if (actor as Node3D).get_world_3d() else null
			var dir: Vector3 = _NavAvoidance.steer_around(raw_dir, actor_pos, space, 2.8) if space else raw_dir
			(actor as CharacterBody3D).velocity.x = dir.x * move_speed * 1.1
			(actor as CharacterBody3D).velocity.z = dir.z * move_speed * 1.1
			(actor as CharacterBody3D).velocity.y = -10.0
			(actor as CharacterBody3D).move_and_slide()
			if (actor as CharacterBody3D).get_slide_collision_count() > 0:
				var flat := Vector3(dir.x * move_speed * 1.1, 0, dir.z * move_speed * 1.1)
				flat = _NavAvoidance.slide_along_wall(flat, actor as CharacterBody3D)
				(actor as CharacterBody3D).velocity.x = flat.x
				(actor as CharacterBody3D).velocity.z = flat.z
				(actor as CharacterBody3D).velocity.y = -10.0
				(actor as CharacterBody3D).move_and_slide()
			return RUNNING
		else:
			# Reached cover
			(actor as CharacterBody3D).velocity.x = 0.0
			(actor as CharacterBody3D).velocity.z = 0.0
			return SUCCESS
	
	# Fallback: retreat backwards away from enemy center or toward squad
	var mecha = GameManager.get_player_mecha() if GameManager else null
	if mecha != null and actor != mecha:
		var diff: Vector3 = mecha.global_position - actor_pos
		diff.y = 0.0
		if diff.length() > 5.0:
			var raw_dir: Vector3 = diff.normalized()
			var space2 := (actor as Node3D).get_world_3d().direct_space_state if (actor as Node3D).get_world_3d() else null
			var dir2: Vector3 = _NavAvoidance.steer_around(raw_dir, actor_pos, space2, 2.8) if space2 else raw_dir
			(actor as CharacterBody3D).velocity.x = dir2.x * move_speed
			(actor as CharacterBody3D).velocity.z = dir2.z * move_speed
			(actor as CharacterBody3D).velocity.y = -10.0
			(actor as CharacterBody3D).move_and_slide()
			return RUNNING
	
	return FAILURE
