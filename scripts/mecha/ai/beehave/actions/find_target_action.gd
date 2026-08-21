@tool
class_name FindTargetAction
extends ActionLeaf

## Finds and acquires a combat target matching the pilot's personality priority.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null or not actor.is_inside_tree():
		return FAILURE
	
	var tree := actor.get_tree()
	if tree == null:
		return FAILURE
	
	var profile: Dictionary = blackboard.get_value("personality_profile", {})
	var priority: String = str(profile.get("target_priority", "nearest"))
	
	# Determine opposing group
	var is_ally: bool = actor.is_in_group("ally")
	var target_group := "enemy" if is_ally else "ally"
	var candidates: Array[Node] = tree.get_nodes_in_group(target_group)
	
	# If looking for allies from enemy side, also include player
	if not is_ally:
		candidates.append_array(tree.get_nodes_in_group("player"))
	
	var best_target: Node3D = null
	var best_score: float = -999999.0
	var actor_pos: Vector3 = (actor as Node3D).global_position
	
	for c in candidates:
		if not is_instance_valid(c) or not (c is Node3D) or c == actor:
			continue
		if c.is_queued_for_deletion():
			continue
		var hs = c.get_node_or_null("HealthSystem")
		if hs != null and hs.get("is_destroyed") == true:
			continue
		
		var dist := actor_pos.distance_to(c.global_position)
		var score := 0.0
		
		match priority:
			"lowest_hp":
				var hp_ratio: float = 1.0
				var max_h = hs.get("max_health") if hs else null
				var cur_h = hs.get("current_health") if hs else null
				if max_h != null and float(max_h) > 0.0 and cur_h != null:
					hp_ratio = float(cur_h) / float(max_h)
				score = (1.0 - hp_ratio) * 100.0 - (dist * 0.5)
			"isolated":
				# Distance from other opponents adds score
				score = -dist
			"protect_allies":
				var mecha = GameManager.get_player_mecha() if GameManager else null
				var ally_pos: Vector3 = mecha.global_position if mecha else actor_pos
				var d_to_ally: float = ally_pos.distance_to(c.global_position)
				score = -d_to_ally - (dist * 0.3)
			_: # "nearest"
				score = -dist
		
		if score > best_score:
			best_score = score
			best_target = c
	
	if best_target != null:
		blackboard.set_value("combat_target", best_target)
		if actor.get("target") != null:
			actor.target = best_target
		return SUCCESS
	
	return FAILURE
