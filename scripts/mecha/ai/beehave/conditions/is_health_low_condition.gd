@tool
class_name IsHealthLowCondition
extends ConditionLeaf

## Checks if actor HP is below the pilot's personality flee threshold.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null:
		return FAILURE
	
	var health_system = actor.get("health_system")
	if health_system == null and actor is Node:
		health_system = actor.get_node_or_null("HealthSystem")
	if health_system == null or not is_instance_valid(health_system):
		return FAILURE
	
	var cur_val = health_system.get("current_health")
	var max_val = health_system.get("max_health")
	var cur_hp: float = float(cur_val) if cur_val != null else 100.0
	var max_hp: float = float(max_val) if max_val != null else 100.0
	if max_hp <= 0.0:
		return FAILURE
	
	var hp_ratio: float = cur_hp / max_hp
	var profile: Dictionary = blackboard.get_value("personality_profile", {})
	var threshold: float = float(profile.get("flee_hp_threshold", 0.25))
	
	# If HP is at or below the pilot's threshold, condition succeeds (triggers flee/cover sequence)
	if hp_ratio <= threshold:
		return SUCCESS
	return FAILURE
