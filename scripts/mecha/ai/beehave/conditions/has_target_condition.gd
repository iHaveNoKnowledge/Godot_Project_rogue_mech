@tool
class_name HasTargetCondition
extends ConditionLeaf

## Checks if actor has a living, valid combat target in blackboard.

func tick(actor: Node, blackboard: Blackboard) -> int:
	var target: Node3D = blackboard.get_value("combat_target")
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		# Check if target is destroyed
		var hs = target.get_node_or_null("HealthSystem")
		if hs != null and hs.get("is_destroyed") == true:
			blackboard.erase_value("combat_target")
			return FAILURE
		return SUCCESS
	blackboard.erase_value("combat_target")
	return FAILURE
