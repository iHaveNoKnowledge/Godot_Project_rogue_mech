class_name CampaignPlayerMovement
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN PLAYER STRATEGIC ROUTE MOVEMENT — Phase 5AK / C2.6.
##
## Architectural Contract:
##   - Single Player Movement Authority:
##     Validates and executes explicit strategic player movement between
##     connected campaign nodes.
##   - Topology Authority:
##     CampaignNodeRegistry owns all nodes and routes (read-only here).
##   - Authoritative Strategic Position:
##     GlobalData.current_campaign_player_node_id owns the strategic player location.
##   - Legacy Physical Position Compatibility:
##     Synchronizes GlobalData.board.current_tile / current_sector when nodes have
##     valid physical anchors, but does NOT require grid adjacency or physical walking.
##   - Separation of Concerns:
##     Does NOT advance CampaignTurnExecutive.
##     Does NOT trigger combat, encounters, supply consumption, or event resolution.
##   - Post-Move Exposure (C4-B6):
##     A successful hop that CHANGES nodes leaves a residual movement trace
##     (+1 heat at the destination) only when entering territory controlled
##     by a faction hostile to the player faction. No detection is reported
##     directly; validation-only checks and unchanged (same-node) moves
##     record nothing.
## ---------------------------------------------------------------------------

## Returns the strategic node ID of the player's current campaign position, or "" if not on a strategic node.
static func get_current_node_id() -> String:
	if GlobalData == null:
		return ""
	var node_id := GlobalData.current_campaign_player_node_id.strip_edges()
	if node_id != "" and CampaignNodeRegistry.has_node(node_id):
		return node_id

	# Fallback/Recovery from legacy physical board tile
	if GlobalData.board != null:
		var sector: int = GlobalData.board.current_sector
		var tile: Vector2i = GlobalData.board.current_tile
		var node_data := CampaignNodeRegistry.get_node_at(sector, tile)
		var derived_id := str(node_data.get("id", "")).strip_edges()
		if derived_id != "":
			GlobalData.current_campaign_player_node_id = derived_id
			return derived_id

	return node_id


## Sets the player's strategic node ID directly and syncs legacy board tile if anchored.
static func set_current_node_id(node_id: String) -> bool:
	if GlobalData == null:
		return false
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return false
	GlobalData.current_campaign_player_node_id = node_id
	if node_id != "" and GlobalData.board != null:
		var node := CampaignNodeRegistry.get_node(node_id)
		var tile: Vector2i = node.get("tile", Vector2i(-1, -1))
		var sector: int = int(node.get("sector", GlobalData.board.current_sector))
		if tile != Vector2i(-1, -1):
			GlobalData.board.current_tile = tile
			GlobalData.board.current_sector = sector
	return true


## Returns all strategic node IDs reachable from the player's current node position.
static func get_reachable_node_ids() -> Array[String]:
	var cur := get_current_node_id()
	if cur == "":
		return []
	return CampaignNodeRegistry.get_connected_node_ids(cur)


## Returns all strategic node data dictionaries reachable from the player's current node position.
static func get_reachable_nodes() -> Array:
	var cur := get_current_node_id()
	if cur == "":
		return []
	return CampaignNodeRegistry.get_connected_nodes(cur)


## Validates whether the player can move to the specified destination node without mutating any state.
static func can_move_to_node(destination_node_id: String) -> Dictionary:
	var source := get_current_node_id()
	if destination_node_id == "" or not CampaignNodeRegistry.has_node(destination_node_id):
		return _fail(source, destination_node_id, "unknown_destination")
	if source == "" or not CampaignNodeRegistry.has_node(source):
		return _fail(source, destination_node_id, "no_source_node")
	if source == destination_node_id:
		return {
			"ok": true,
			"changed": false,
			"from_node_id": source,
			"to_node_id": destination_node_id,
			"reason": "same_node",
		}
	var route_id := CampaignNodeRegistry.make_route_id(source, destination_node_id)
	if not CampaignNodeRegistry.has_route(route_id):
		return _fail(source, destination_node_id, "no_route")
	return {
		"ok": true,
		"changed": true,
		"from_node_id": source,
		"to_node_id": destination_node_id,
		"reason": "valid",
	}


## Attempts one strategic route hop for the player.
## Atomic: on failure, player position remains untouched.
## On success, updates GlobalData.current_campaign_player_node_id (and legacy board tile if anchored).
## A changed move into hostile-controlled territory additionally records a
## residual movement trace (+1 heat at the destination, C4-B6); same-node
## and failed moves record nothing and never report detection.
static func move_player_to_node(destination_node_id: String) -> Dictionary:
	var validation := can_move_to_node(destination_node_id)
	if not bool(validation.get("ok", false)):
		return validation
	if not bool(validation.get("changed", false)):
		return validation

	var source := str(validation.get("from_node_id", ""))
	set_current_node_id(destination_node_id)
	_apply_movement_trace(destination_node_id)

	return {
		"ok": true,
		"changed": true,
		"from_node_id": source,
		"to_node_id": destination_node_id,
		"reason": "moved",
	}


static func _fail(source: String, destination_node_id: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"from_node_id": source,
		"to_node_id": destination_node_id,
		"reason": reason,
	}


## Records the residual trace of a completed hop (C4-B6): +1 heat at the
## destination node when any covering territory is controlled by a faction
## hostile to the player faction. Never reports detection directly.
static func _apply_movement_trace(destination_node_id: String) -> void:
	var player_faction := FactionSystem.get_player_faction()
	for territory in CampaignTerritory.get_territories_for_node(destination_node_id):
		var controller := str(territory.get("controller", ""))
		if controller != "" and FactionSystem.get_relation(player_faction, controller) == FactionSystem.Relation.HOSTILE:
			CampaignStrategicHeat.add_node_heat(destination_node_id, 1)
			return
