class_name CampaignNodeRegistry
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN NODE + ROUTE REGISTRY — Phase 3A (Campaign V2 foundation).
##
## Strategic topology layer OVER the existing physical board. Authority split:
##   BoardState / BoardManager own the physical board (35x35 grid, tiles,
##     movement, encounters). This registry owns ONLY strategic topology
##     references (nodes + routes) and never moves the player, never triggers
##     combat, never replaces BoardTile.
##
## Board facts established by audit (do not re-decide lightly):
##   - Tiles have NO persistent IDs; identity is the Vector2i grid coordinate
##     (nodes_dict key + grid_pos meta), stable within a run/sector and
##     seed-deterministic across board rebuilds (generate_board is seeded;
##     content shuffle is seeded so hubs/objectives land on the same cells).
##   - tile "connections" meta is 4-dir walkable adjacency for movement, not
##     strategic topology.
##   - Content tiles mutate mid-run (enemy_base planted/cleared, objectives
##     consumed to "empty"); the registry syncs via rebuild_from_board (after
##     generation) and sync_tile (after strategic mutations).
##
## Node model: {id, tile: Vector2i, sector: int, node_type: String}.
##   id pattern: node_s<sector>_<tiletype>_<x>_<y> (stable within a campaign).
##   One tile hosts 0 or 1 nodes (board content is one tile_type per cell).
## Route model: {id, a, b} undirected; id is canonical so A,B == B,A.
##
## Out of scope (later phases): territory/faction ownership, bases, forces,
## battles, supply, detection, threat, pathfinding, route movement, combat.
## ---------------------------------------------------------------------------

# Tile types that become persistent strategic nodes, mapped to node types.
# Everything else (event, bait, hazards, distress/unknown signals,
# scavenge_site, dead_end, ambush, breakdown, wreckage, supply_truck,
# fuel_choice, empty, ...) is a transient encounter, not topology.
# Rationale: listed tiles are guaranteed hubs (start/exit/safehouse/city),
# repeatable facilities (fuel_depot/research_lab), or contract/enemy-driven
# objectives (comms_relay/prototype_vault/data_node/salvage_cache/
# supply_depot/enemy_base) that persist until explicitly completed/destroyed.
const STRATEGIC_TILE_TYPES := {
	"start": "START",
	"exit": "EXIT",
	"safehouse": "SAFEHOUSE",
	"city": "CITY",
	"fuel_depot": "FUEL_DEPOT",
	"research_lab": "RESEARCH_LAB",
	"enemy_base": "ENEMY_BASE",
	"comms_relay": "COMMS_RELAY",
	"prototype_vault": "PROTOTYPE_VAULT",
	"data_node": "DATA_NODE",
	"salvage_cache": "SALVAGE_CACHE",
	"supply_depot": "SUPPLY_DEPOT",
}

static var _nodes: Dictionary = {}
static var _tile_index: Dictionary = {}
static var _routes: Dictionary = {}


static func is_strategic_tile(tile_type: String) -> bool:
	return STRATEGIC_TILE_TYPES.has(tile_type)


static func node_type_for_tile(tile_type: String) -> String:
	return str(STRATEGIC_TILE_TYPES.get(tile_type, ""))


static func make_node_id(sector: int, tile_type: String, tile: Vector2i) -> String:
	return "node_s%d_%s_%d_%d" % [sector, tile_type, tile.x, tile.y]


static func _tile_key(sector: int, tile: Vector2i) -> String:
	return "%d|%d|%d" % [sector, tile.x, tile.y]


static func _route_key(a: String, b: String) -> String:
	return a + "||" + b if a <= b else b + "||" + a


static func make_route_id(a: String, b: String) -> String:
	var first := a if a <= b else b
	var second := b if a <= b else a
	return "route_%s__%s" % [first, second]


# --- Nodes ---------------------------------------------------------------

static func has_node(node_id: String) -> bool:
	return _nodes.has(node_id)


static func get_node(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	return (_nodes[node_id] as Dictionary).duplicate(true)


static func get_nodes() -> Array:
	var ids := _nodes.keys()
	ids.sort()
	var out: Array = []
	for nid in ids:
		out.append((_nodes[nid] as Dictionary).duplicate(true))
	return out


static func get_node_at(sector: int, tile: Vector2i) -> Dictionary:
	var nid := str(_tile_index.get(_tile_key(sector, tile), ""))
	if nid == "":
		return {}
	return get_node(nid)


## Registers one node. Returns the node id, or "" when rejected:
## unknown tile type, tile already hosting a DIFFERENT node (0/1 rule), or id
## collision with a different tile/type. Re-registering the identical node is
## idempotent (returns the id). node_id "" auto-derives the stable pattern.
static func register_node(sector: int, tile: Vector2i, tile_type: String, node_id: String = "") -> String:
	if not is_strategic_tile(tile_type):
		return ""
	var want_id := node_id if node_id != "" else make_node_id(sector, tile_type, tile)
	var want_key := _tile_key(sector, tile)
	if _nodes.has(want_id):
		var existing: Dictionary = _nodes[want_id]
		if Vector2i(existing.get("tile", Vector2i(-1, -1))) == tile \
				and int(existing.get("sector", -1)) == sector \
				and str(existing.get("node_type", "")) == node_type_for_tile(tile_type):
			return want_id
		return ""
	if _tile_index.has(want_key):
		return ""
	_nodes[want_id] = {
		"id": want_id,
		"tile": tile,
		"sector": sector,
		"node_type": node_type_for_tile(tile_type),
	}
	_tile_index[want_key] = want_id
	return want_id


## Removes a node and every route attached to it (dangling routes are
## impossible by construction). Returns false when the id is unknown.
static func remove_node(node_id: String) -> bool:
	if not _nodes.has(node_id):
		return false
	var doomed: Dictionary = _nodes[node_id]
	_nodes.erase(node_id)
	_tile_index.erase(_tile_key(int(doomed.get("sector", -1)), doomed.get("tile", Vector2i(-1, -1))))
	var dead: Array = []
	for key in _routes:
		var r: Dictionary = _routes[key]
		if str(r.get("a", "")) == node_id or str(r.get("b", "")) == node_id:
			dead.append(key)
	for key in dead:
		_routes.erase(key)
	return true


# --- Routes --------------------------------------------------------------

static func has_route(route_id: String) -> bool:
	return _routes.has(_canonical_route_lookup(route_id))


static func get_route(route_id: String) -> Dictionary:
	var key := _canonical_route_lookup(route_id)
	if key == "" or not _routes.has(key):
		return {}
	return (_routes[key] as Dictionary).duplicate(true)


static func get_routes() -> Array:
	var keys := _routes.keys()
	keys.sort()
	var out: Array = []
	for key in keys:
		out.append((_routes[key] as Dictionary).duplicate(true))
	return out


static func get_routes_for(node_id: String) -> Array:
	var out: Array = []
	for key in _routes:
		var r: Dictionary = _routes[key]
		if str(r.get("a", "")) == node_id or str(r.get("b", "")) == node_id:
			out.append(r.duplicate(true))
	return out


## Returns all node IDs directly reachable from the given node via registered routes.
static func get_connected_node_ids(node_id: String) -> Array[String]:
	var out: Array[String] = []
	if node_id == "" or not has_node(node_id):
		return out
	for r in get_routes_for(node_id):
		var a := str(r.get("a", ""))
		var b := str(r.get("b", ""))
		var other := b if a == node_id else a
		if other != "" and not out.has(other) and has_node(other):
			out.append(other)
	out.sort()
	return out


## Returns full node data dictionaries for all nodes reachable from the given node.
static func get_connected_nodes(node_id: String) -> Array:
	var ids := get_connected_node_ids(node_id)
	var out: Array = []
	for nid in ids:
		out.append(get_node(nid))
	return out


## Registers an undirected route. A,B and B,A resolve to the same id.
## Returns the route id, or "" when rejected: unknown endpoint, self-loop,
## or an already-registered undirected edge (strict duplicate rejection).
static func register_route(a: String, b: String) -> String:
	if a == "" or b == "" or a == b:
		return ""
	if not _nodes.has(a) or not _nodes.has(b):
		return ""
	var key := _route_key(a, b)
	if _routes.has(key):
		return ""
	_routes[key] = {"id": make_route_id(a, b), "a": a if a <= b else b, "b": b if a <= b else a}
	return str((_routes[key] as Dictionary).get("id", ""))


static func remove_route(route_id: String) -> bool:
	var key := _canonical_route_lookup(route_id)
	if key == "" or not _routes.has(key):
		return false
	_routes.erase(key)
	return true


static func _canonical_route_lookup(route_id: String) -> String:
	for key in _routes:
		if str((_routes[key] as Dictionary).get("id", "")) == route_id:
			return key
	return ""


# --- Derivation ----------------------------------------------------------

## Full rebuild from live board tiles ({Vector2i: tile Node}). Clears first
## (idempotent). Derives nodes for strategic tiles, then routes between nodes
## on 4-neighboring cells (deterministic, board-grounded adjacency — no
## invented topology). Returns {nodes, routes} counts.
static func rebuild_from_board(nodes_dict: Dictionary, sector: int) -> Dictionary:
	var flat := {}
	for pos in nodes_dict:
		var tile = nodes_dict[pos]
		if tile != null and tile.has_method("get_meta") and pos is Vector2i:
			flat[pos] = str(tile.get_meta("tile_type", "empty"))
	return rebuild_from_tile_types(flat, sector)


## Headless/test-friendly rebuild from a plain {Vector2i: tile_type} map.
static func rebuild_from_tile_types(tile_types: Dictionary, sector: int) -> Dictionary:
	clear()
	for pos in tile_types:
		if pos is Vector2i:
			register_node(sector, pos, str(tile_types[pos]))
	_derive_adjacency_routes()
	return {"nodes": _nodes.size(), "routes": _routes.size()}


static func _derive_adjacency_routes() -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for nid in _nodes:
		var n: Dictionary = _nodes[nid]
		var tile: Vector2i = n.get("tile", Vector2i(-1, -1))
		var sector := int(n.get("sector", -1))
		for d in dirs:
			var other := get_node_at(sector, tile + d)
			if not other.is_empty() and str(other.get("id", "")) != nid:
				register_route(nid, str(other.get("id", "")))


## Incremental sync for a single mutated tile (strategic tile changed or
## consumed to "empty"). Replaces any node previously hosted there, then
## re-derives adjacency routes around it. No-ops for transient tiles except
## removing a stale node (a consumed tile hosts nothing).
static func sync_tile(sector: int, tile: Vector2i, tile_type: String) -> String:
	var old := get_node_at(sector, tile)
	if not old.is_empty():
		remove_node(str(old.get("id", "")))
	if not is_strategic_tile(tile_type):
		return ""
	var nid := register_node(sector, tile, tile_type)
	if nid == "":
		return ""
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var other := get_node_at(sector, tile + d)
		if not other.is_empty():
			register_route(nid, str(other.get("id", "")))
	return nid


# --- Invariants ----------------------------------------------------------

## Structural health check. Returns violation strings (empty = healthy).
static func validate() -> Array:
	var problems: Array = []
	for key in _routes:
		var r: Dictionary = _routes[key]
		var a := str(r.get("a", ""))
		var b := str(r.get("b", ""))
		if a == "" or b == "":
			problems.append("route %s has empty endpoint" % str(r.get("id", "?")))
		if a == b and a != "":
			problems.append("route %s is a self-loop" % str(r.get("id", "?")))
		if a != "" and not _nodes.has(a):
			problems.append("route %s references unknown node %s" % [str(r.get("id", "?")), a])
		if b != "" and not _nodes.has(b):
			problems.append("route %s references unknown node %s" % [str(r.get("id", "?")), b])
		if key != _route_key(a, b):
			problems.append("route %s key not canonical" % str(r.get("id", "?")))
	var seen := {}
	for key in _routes:
		var rid := str((_routes[key] as Dictionary).get("id", ""))
		if seen.has(rid):
			problems.append("duplicate route id %s" % rid)
		seen[rid] = true
	return problems


# --- Persistence (snapshots; 3A topology is DERIVED, see below) -----------
#
# Phase 3A persists NOTHING in SaveGameIO: nodes/routes rebuild
# deterministically from the seed-stable board (generate + restores), and
# 3A nodes carry no mutable state (no owner/supply/garrison). serialize/
# deserialize exist for equivalence tests and future phases that add mutable
# topology state.

static func serialize() -> Dictionary:
	var nodes: Array = []
	for n in get_nodes():
		var c: Dictionary = (n as Dictionary).duplicate(true)
		var t: Vector2i = c.get("tile", Vector2i.ZERO)
		c["tile"] = {"x": t.x, "y": t.y}
		nodes.append(c)
	var routes: Array = []
	for r in get_routes():
		routes.append((r as Dictionary).duplicate(true))
	return {"nodes": nodes, "routes": routes}


static func deserialize(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var nodes = data.get("nodes", [])
	if nodes is Array:
		for n in nodes:
			if not (n is Dictionary):
				continue
			var t = n.get("tile", {})
			var tile := Vector2i(-1, -1)
			if t is Dictionary:
				tile = Vector2i(int(t.get("x", -1)), int(t.get("y", -1)))
			elif t is Vector2i:
				tile = t
			var sector := int(n.get("sector", 1))
			# Node types round-trip as stored; tile_type is recovered from the
			# node type for re-registration (both use the same vocabulary).
			var ntype := str(n.get("node_type", ""))
			var tile_type := ntype.to_lower()
			var nid := register_node(sector, tile, tile_type, str(n.get("id", "")))
			if nid == "" and tile_type != "":
				register_node(sector, tile, tile_type)
	var routes = data.get("routes", [])
	if routes is Array:
		for r in routes:
			if r is Dictionary:
				register_route(str(r.get("a", "")), str(r.get("b", "")))


static func clear() -> void:
	_nodes.clear()
	_tile_index.clear()
	_routes.clear()
