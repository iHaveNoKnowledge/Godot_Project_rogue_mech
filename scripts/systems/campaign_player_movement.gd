class_name CampaignPlayerMovement
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN PLAYER STRATEGIC ROUTE MOVEMENT — Phase 5AK.
##
## Architectural Contract:
##   - Single Player Movement Authority:
##     Validates and executes explicit strategic player movement between
##     connected campaign nodes.
##   - Topology Authority:
##     CampaignNodeRegistry owns all nodes and routes (read-only here).
##   - Physical Position Authority:
##     BoardState (GlobalData.board) owns physical player position (current_tile, current_sector).
##   - Derived Strategic Position:
##     Player strategic node is derived via CampaignNodeRegistry.get_node_at(sector, current_tile).
##   - Separation of Concerns:
##     Does NOT create/mutate CampaignForce (no Player CampaignForce).
##     Does NOT mutate CampaignTerritory, CampaignBase, or CampaignBattle.
##     Does NOT advance CampaignTurnExecutive.
##     Does NOT mutate FactionSystem, FactionEconomySystem, or HeatWantedSystem.
##     Does NOT trigger combat, encounters, supply consumption, or event resolution.
##   - Stateless Action Primitive:
##     Pure RefCounted static class with no persistent variables, no signals,
##     and no duplicate coordinate/topology state.
## ---------------------------------------------------------------------------

## Returns the strategic node ID of the player's current physical position, or "" if not on a strategic node.
static func get_current_node_id() -> String:
	if GlobalData.board == null:
		return ""
	var sector: int = GlobalData.board.current_sector
	var tile: Vector2i = GlobalData.board.current_tile
	var node_data := CampaignNodeRegistry.get_node_at(sector, tile)
	return str(node_data.get("id", ""))


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
## Atomic: on failure, GlobalData.board position remains untouched.
## On success, updates GlobalData.board.current_tile and current_sector to match destination node.
static func move_player_to_node(destination_node_id: String) -> Dictionary:
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

	var dest_node := CampaignNodeRegistry.get_node(destination_node_id)
	if not dest_node.has("tile") or not dest_node.has("sector"):
		return _fail(source, destination_node_id, "invalid_node_data")

	var dest_tile: Vector2i = dest_node.get("tile", Vector2i(-1, -1))
	var dest_sector: int = int(dest_node.get("sector", 1))
	if dest_tile == Vector2i(-1, -1):
		return _fail(source, destination_node_id, "invalid_node_coordinates")

	# Atomically commit physical position
	GlobalData.board.current_tile = dest_tile
	GlobalData.board.current_sector = dest_sector

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
