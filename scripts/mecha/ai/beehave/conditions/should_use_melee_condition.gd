@tool
class_name ShouldUseMeleeCondition
extends ConditionLeaf

## Checks if actor should switch to melee blade engagement.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null:
		return FAILURE
	
	var target: Node3D = blackboard.get_value("combat_target")
	if target == null or not is_instance_valid(target):
		return FAILURE
	
	var profile: Dictionary = blackboard.get_value("personality_profile", {})
	var dist: float = (actor as Node3D).global_position.distance_to(target.global_position)
	
	# 1. Close combat range (< 6m) always allows melee
	if dist <= 6.0:
		return SUCCESS
	
	# 2. Aggressive trait strongly favors melee charge if within dash range (< 20m)
	if profile.get("prefer_melee", false) and dist <= 20.0:
		return SUCCESS
	
	# 3. If ranged weapon is totally dry or reloading near target, fallback to blade
	var fire_core: WeaponCore = actor.get("fire_core")
	if fire_core != null:
		if fire_core.is_completely_dry():
			return SUCCESS
		if fire_core.ammo <= 0 and dist <= 18.0:
			return SUCCESS
	
	return FAILURE
