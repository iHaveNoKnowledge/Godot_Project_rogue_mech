@tool
class_name HasScavengeTargetCondition
extends ConditionLeaf

## Checks if actor needs ammo/resources and there is a valid pickup nearby.

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null:
		return FAILURE
	
	var profile: Dictionary = blackboard.get_value("personality_profile", {})
	var ammo_threshold: float = float(profile.get("scavenge_ammo_threshold", 0.30))
	var scan_radius: float = float(profile.get("scavenge_scan_radius", 30.0))
	
	# Check ammo status
	var fire_core: WeaponCore = actor.get("fire_core")
	var needs_ammo := false
	if fire_core != null and fire_core.max_ammo > 0:
		var ammo_ratio := float(fire_core.ammo) / float(fire_core.max_ammo)
		if ammo_ratio <= ammo_threshold or fire_core.ammo <= 0:
			needs_ammo = true
	
	# If pilot has Scavenger trait, they also scavenge when full if safe
	var trait_type: int = int(profile.get("type", AiPilotTraits.PersonalityType.BALANCED))
	if trait_type == AiPilotTraits.PersonalityType.SCAVENGER:
		needs_ammo = true
	
	if not needs_ammo:
		return FAILURE
	
	# Find nearest pickup in tree
	var tree := actor.get_tree()
	if tree == null:
		return FAILURE
	
	var pickups: Array[Node] = []
	for group in ["ammo_pickup", "loot_pickup"]:
		pickups.append_array(tree.get_nodes_in_group(group))
	
	var nearest_pickup: Node3D = null
	var nearest_dist_sq := scan_radius * scan_radius
	var actor_pos: Vector3 = actor.global_position
	
	for p in pickups:
		if not is_instance_valid(p) or not (p is Node3D):
			continue
		var d_sq := actor_pos.distance_squared_to(p.global_position)
		if d_sq < nearest_dist_sq:
			nearest_dist_sq = d_sq
			nearest_pickup = p
	
	if nearest_pickup != null:
		blackboard.set_value("scavenge_target", nearest_pickup)
		return SUCCESS
	
	return FAILURE
