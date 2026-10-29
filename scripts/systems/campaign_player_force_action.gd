class_name CampaignPlayerForceAction
extends RefCounted

## ---------------------------------------------------------------------------
## PLAYER DETACHMENT ACTIONS — Phase C8-B (raise / move / station).
##
## Domain authority for the three player-facing orders on a
## `CampaignPlayerForce` detachment. Audit evidence:
##   - CampaignPlayerForce (C8-A) owns the records; CampaignNodeRegistry owns
##     topology; CampaignBase owns installations; CurrencyManager owns credits.
##     No new state lives here — this file only validates and calls primitives.
##   - The C5 plan §4.5 ("hire additional Grunts by spending credits through
##     CurrencyManager") is the pricing authority; the old `safehouse`/hangar
##     flows already spend credits the same way.
##   - Move is ONE strategic route hop, mirroring `CampaignForceMovement`
##     (routes only; BoardTile adjacency is never consulted).
##
## Pricing/strength are PROVISIONAL balance values (spec §44).
##
## Firewalls: no turn advancement, no battle creation/resolution, no base or
## territory ownership mutation, no supply spend, no detection/heat writes.
## ---------------------------------------------------------------------------

const RAISE_CREDITS_COST := 120
const RAISE_UNIT_COUNT := 1
const RAISE_STRENGTH := 10


static func get_raise_cost() -> int:
	return RAISE_CREDITS_COST


static func get_raise_units() -> int:
	return RAISE_UNIT_COUNT


static func get_raise_strength() -> int:
	return RAISE_STRENGTH


## Detachments the player currently owns (id-sorted, verbatim records).
static func get_player_detachments() -> Array:
	return CampaignPlayerForce.get_detachments()


## Active detachments standing at a node (id-sorted).
static func get_detachments_at_node(node_id: String) -> Array:
	return CampaignPlayerForce.get_active_at_node(node_id)


## Raises a new detachment at the player's current node. `slug` becomes part of
## the stable id (`player_force_<slug>`). node_id "" means "the node the player
## stands on". Charges credits only after the authority accepted the record, and
## rolls the record back if the payment fails, so a failed raise is side-effect
## free.
static func raise_player_detachment(slug: String, node_id: String = "") -> Dictionary:
	var nid := node_id.strip_edges()
	if nid == "":
		nid = CampaignPlayerMovement.get_current_node_id()
	if nid == "" or not CampaignNodeRegistry.has_node(nid):
		return {"ok": false, "reason": "unknown_node", "node_id": nid}
	if not CampaignNodeInspection.is_player_at_node(nid):
		return {"ok": false, "reason": "player_not_at_node", "node_id": nid}
	var clean_slug := slug.strip_edges()
	if clean_slug == "":
		return {"ok": false, "reason": "invalid_slug", "slug": slug}
	var force_id := CampaignPlayerForce.make_detachment_id(clean_slug)
	if force_id == "":
		return {"ok": false, "reason": "invalid_slug", "slug": slug}
	if CampaignPlayerForce.has_detachment(force_id):
		return {"ok": false, "reason": "detachment_exists", "force_id": force_id}
	var registered := CampaignPlayerForce.register_detachment(
		force_id, nid, "", RAISE_UNIT_COUNT, RAISE_STRENGTH)
	if registered == "":
		return {"ok": false, "reason": "registration_rejected", "force_id": force_id}
	if not GlobalData.currency.try_spend_credits(RAISE_CREDITS_COST):
		CampaignPlayerForce.remove_detachment(force_id)
		return {
			"ok": false,
			"reason": "insufficient_credits",
			"cost": RAISE_CREDITS_COST,
			"credits": int(GlobalData.currency.credits),
		}
	return {
		"ok": true,
		"reason": "detachment_raised",
		"force_id": registered,
		"node_id": nid,
		"cost": RAISE_CREDITS_COST,
		"units": RAISE_UNIT_COUNT,
		"strength": RAISE_STRENGTH,
	}


## Moves one detachment across a single registered strategic route.
static func move_player_detachment(force_id: String, destination_node_id: String) -> Dictionary:
	if force_id == "" or not CampaignPlayerForce.has_detachment(force_id):
		return _move_fail(force_id, "", destination_node_id, "unknown_detachment")
	if not CampaignPlayerForce.is_active(force_id):
		return _move_fail(force_id, _node_of(force_id), destination_node_id, "detachment_not_active")
	var source := _node_of(force_id)
	if source == "" or not CampaignNodeRegistry.has_node(source):
		return _move_fail(force_id, source, destination_node_id, "no_source_node")
	if destination_node_id == "" or not CampaignNodeRegistry.has_node(destination_node_id):
		return _move_fail(force_id, source, destination_node_id, "unknown_destination")
	if source == destination_node_id:
		return _move_fail(force_id, source, destination_node_id, "same_node")
	var route_id := CampaignNodeRegistry.make_route_id(source, destination_node_id)
	if not CampaignNodeRegistry.has_route(route_id):
		return _move_fail(force_id, source, destination_node_id, "no_route")
	if not CampaignPlayerForce.set_node(force_id, destination_node_id):
		return _move_fail(force_id, source, destination_node_id, "move_rejected")
	return {
		"ok": true,
		"reason": "detachment_moved",
		"force_id": force_id,
		"from_node_id": source,
		"to_node_id": destination_node_id,
	}


## Binds a detachment to a player-owned base at the same node.
static func station_player_detachment(force_id: String, base_id: String) -> Dictionary:
	if force_id == "" or not CampaignPlayerForce.has_detachment(force_id):
		return {"ok": false, "reason": "unknown_detachment", "force_id": force_id, "base_id": base_id}
	if base_id == "" or not CampaignBase.has_base(base_id):
		return {"ok": false, "reason": "unknown_base", "force_id": force_id, "base_id": base_id}
	var base := CampaignBase.get_base(base_id)
	if int(base.get("state", -1)) == CampaignBase.BaseState.DESTROYED:
		return {"ok": false, "reason": "base_destroyed", "force_id": force_id, "base_id": base_id}
	var controller := str(base.get("controller", "")).strip_edges()
	if controller != FactionSystem.get_player_faction():
		return {"ok": false, "reason": "base_not_player_owned", "force_id": force_id, "base_id": base_id}
	var force_node := _node_of(force_id)
	if force_node == "" or force_node != str(base.get("node_id", "")):
		return {"ok": false, "reason": "detachment_not_at_base", "force_id": force_id, "base_id": base_id}
	if not CampaignPlayerForce.set_base(force_id, base_id):
		return {"ok": false, "reason": "station_rejected", "force_id": force_id, "base_id": base_id}
	return {"ok": true, "reason": "detachment_stationed", "force_id": force_id, "base_id": base_id}


## Clears the base binding (the detachment keeps its node).
static func unstation_player_detachment(force_id: String) -> Dictionary:
	if force_id == "" or not CampaignPlayerForce.has_detachment(force_id):
		return {"ok": false, "reason": "unknown_detachment", "force_id": force_id}
	if not CampaignPlayerForce.set_base(force_id, ""):
		return {"ok": false, "reason": "unstation_rejected", "force_id": force_id}
	return {"ok": true, "reason": "detachment_unstationed", "force_id": force_id}


## Straight-line display summary for one detachment (UI + tests).
static func describe_detachment(force_id: String) -> String:
	if not CampaignPlayerForce.has_detachment(force_id):
		return ""
	var d := CampaignPlayerForce.get_detachment(force_id)
	var base_text := str(d.get("base_id", ""))
	if base_text == "":
		base_text = "field"
	return "%s [%s] units=%d str=%d @ %s (%s)" % [
		force_id,
		CampaignPlayerForce.state_to_name(int(d.get("state", 0))),
		int(d.get("unit_count", 0)),
		int(d.get("strength", 0)),
		str(d.get("node_id", "")),
		base_text,
	]


static func _node_of(force_id: String) -> String:
	if not CampaignPlayerForce.has_detachment(force_id):
		return ""
	return str(CampaignPlayerForce.get_detachment(force_id).get("node_id", ""))


static func _move_fail(force_id: String, source: String, destination: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"force_id": force_id,
		"from_node_id": source,
		"to_node_id": destination,
	}
