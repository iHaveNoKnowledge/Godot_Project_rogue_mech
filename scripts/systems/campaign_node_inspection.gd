class_name CampaignNodeInspection
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN NODE SITUATION / STRATEGIC INSPECTION AUTHORITY — Phase 5AL
##
## Read-only query/projection layer for strategic campaign nodes.
## Answers: "What is currently present at this strategic node?" without
## performing any gameplay action.
##
## Pure observation operation:
##   - Zero state mutation
##   - Zero topology mutation (reads CampaignNodeRegistry)
##   - Zero force mutation (reads CampaignForce)
##   - Zero territory mutation (reads CampaignTerritory)
##   - Zero base mutation (reads CampaignBase)
##   - Zero player movement (derives presence from BoardState)
##   - Zero turn advancement (CampaignTurnExecutive untouched)
##   - Zero battle creation (CampaignBattle untouched)
##   - Zero heat/wanted or faction relation side-effects
## ---------------------------------------------------------------------------

const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")


## Inspects a strategic node by ID and returns a comprehensive, read-only
## situation projection. Unknown node IDs fail deterministically.
static func inspect_node(node_id: String) -> Dictionary:
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return {
			"ok": false,
			"reason": "unknown_node",
			"node": {},
			"routes": [],
			"forces": [],
			"territory": {},
			"base": {},
			"player_present": false,
			"factions_present": [],
		}

	var node := CampaignNodeRegistry.get_node(node_id)

	# Routes / neighbors
	var routes: Array = []
	for r in CampaignNodeRegistry.get_routes_for(node_id):
		for key in ["a", "b"]:
			var other := str((r as Dictionary).get(key, ""))
			if other != "" and other != node_id and not routes.has(other):
				routes.append(other)
	routes.sort()

	# Forces at node, deterministically ordered by force ID
	var force_ids: Array = CampaignForce.get_forces_at_node(node_id)
	force_ids.sort()
	var forces: Array = []
	var factions_set: Dictionary = {}
	for fid in force_ids:
		var f: Dictionary = CampaignForce.get_force(str(fid))
		if not f.is_empty():
			forces.append(f)
			var faction := str(f.get("faction", "")).strip_edges()
			if faction != "":
				factions_set[faction] = true

	# Territory containing node
	var territory := {}
	var covering := CampaignTerritory.get_territories_for_node(node_id)
	if not covering.is_empty():
		territory = CampaignTerritory.get_territory(str(covering[0].get("id", "")))

	# Base anchored at node
	var base := CampaignBase.get_base_at_node(node_id)

	# Derived player presence
	var player_here := is_player_at_node(node_id)

	# Factions present
	var factions_present: Array = factions_set.keys()
	factions_present.sort()

	return {
		"ok": true,
		"reason": "inspected",
		"node": node,
		"routes": routes,
		"forces": forces,
		"territory": territory,
		"base": base,
		"player_present": player_here,
		"factions_present": factions_present,
	}


## Returns whether the player is currently located on the given strategic node.
static func is_player_at_node(node_id: String) -> bool:
	if node_id == "":
		return false
	return get_current_player_node_id() == node_id


## Returns the node ID of the strategic node the player is currently on,
## or "" if the player is not on a registered strategic node.
static func get_current_player_node_id() -> String:
	return CampaignPlayerMovement.get_current_node_id()
