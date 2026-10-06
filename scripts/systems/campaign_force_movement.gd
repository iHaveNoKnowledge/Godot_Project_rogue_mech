class_name CampaignForceMovement
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN FORCE STRATEGIC MOVEMENT — Phase 5T (first gameplay slice).
##
## Audit evidence (do not re-decide lightly):
##   - CampaignForce.set_node() is a low-level relocation primitive (5K):
##     validated reference write, zero production callers, no cost, no gate.
##     It is NOT gameplay by itself.
##   - Cross-domain orchestration is NOT YET MODELED (5S): no manager, bus,
##     or transaction authority exists, and this action must not become one.
##   - Strategic routes are undirected canonical topology (3A): {id, a, b},
##     A,B == B,A, no cost fields, no movement semantics attached.
##   - BoardTile connections are 4-dir walkable adjacency for the physical
##     board — never a substitute for strategic routes.
##
## Contract (v1, one hop, validated BEFORE any mutation):
##   ACTIVE force at Node A + registered route A<->B  =>  force.node_id = B.
##   Everything else rejects with {ok:false, reason} and mutates nothing.
##   Success mutates ONLY CampaignForce.node_id (via set_node); the receipt
##   is {ok, force_id, from_node_id, to_node_id, reason} — "moved" on
##   success, a snake_case error code on failure.
##
## Ownership: Force owns state (this action only CALLS its primitive);
## NodeRegistry owns topology (read-only here); Territory/Base/Battle/
## Faction/Turn/Supply/Detection/Orders are never touched (locked by
## 5I/5J/5K/5L/5M/5N/5O/5P/5Q/5R). Stateless: no mutable state of its own,
## no reset, no signals, no turn advancement, no persistence fields.
## ---------------------------------------------------------------------------

## Attempts one strategic route hop. Never throws; failures return
## {ok:false} with the force and every other authority untouched.
static func move_force(force_id: String, destination_node_id: String) -> Dictionary:
	if force_id == "" or not CampaignForce.has_force(force_id):
		return _fail(force_id, _current_node_of(force_id), destination_node_id,
			"unknown_force")
	if CampaignForce.get_state(force_id) != CampaignForce.ForceState.ACTIVE:
		return _fail(force_id, _current_node_of(force_id), destination_node_id,
			"force_not_active")
	var source := _current_node_of(force_id)
	if source == "" or not CampaignNodeRegistry.has_node(source):
		return _fail(force_id, source, destination_node_id, "no_source_node")
	if destination_node_id == "" or not CampaignNodeRegistry.has_node(destination_node_id):
		return _fail(force_id, source, destination_node_id, "unknown_destination")
	if source == destination_node_id:
		return _fail(force_id, source, destination_node_id, "same_node")
	var route_id := CampaignNodeRegistry.make_route_id(source, destination_node_id)
	if not CampaignNodeRegistry.has_route(route_id):
		return _fail(force_id, source, destination_node_id, "no_route")
	CampaignForce.set_node(force_id, destination_node_id)
	return {
		"ok": true,
		"force_id": force_id,
		"from_node_id": source,
		"to_node_id": destination_node_id,
		"reason": "moved",
	}


static func _current_node_of(force_id: String) -> String:
	if not CampaignForce.has_force(force_id):
		return ""
	return str(CampaignForce.get_force(force_id).get("node_id", ""))


static func _fail(force_id: String, source: String, destination_node_id: String,
		reason: String) -> Dictionary:
	return {
		"ok": false,
		"force_id": force_id,
		"from_node_id": source,
		"to_node_id": destination_node_id,
		"reason": reason,
	}
