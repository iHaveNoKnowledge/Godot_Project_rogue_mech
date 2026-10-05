extends Node
## PHASE 3A CAMPAIGN NODE + ROUTE VERIFY (Campaign V2 foundation).
##
## Proves: node registration/identity/uniqueness, strategic-vs-transient tile
## classification, undirected routes with canonical IDs and strict rejection
## rules, graph invariants, reset/isolation, serialize round-trip, derivation
## determinism, board-object compatibility, and that registry calls never move
## player/board-movement state. Board movement itself is covered by the
## existing board lifecycle suites (2e_51/2e_52), which must also stay green.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("NODE-ROUTE OK: " + name)
	else:
		_fails += 1
		printerr("NODE-ROUTE FAIL: " + name)


func _fake_tile(tile_type: String) -> RefCounted:
	var t := RefCounted.new()
	t.set_meta("tile_type", tile_type)
	return t


func _ready() -> void:
	await get_tree().process_frame
	GlobalData.reset_run_data()
	_test_node_registration()
	_test_node_identity()
	_test_tile_classification()
	_test_routes()
	_test_invariants()
	_test_reset_isolation()
	_test_serialize_round_trip()
	_test_derivation_determinism()
	_test_board_compat()
	_test_movement_untouched()
	GlobalData.reset_run_data()
	print("CAMPAIGN_NODE_ROUTE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_NODE_ROUTE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_NODE_ROUTE_TESTS_PASSED")
		get_tree().quit(0)


# A — node registration.
func _test_node_registration() -> void:
	CampaignNodeRegistry.clear()
	var nid := CampaignNodeRegistry.register_node(1, Vector2i(12, 20), "city")
	_check(nid != "" and CampaignNodeRegistry.has_node(nid), "register valid node")
	_check(not CampaignNodeRegistry.get_node(nid).is_empty(), "get node returns data")
	_check(CampaignNodeRegistry.get_nodes().size() == 1, "list nodes has one entry")
	_check(CampaignNodeRegistry.register_node(1, Vector2i(12, 20), "city") == nid,
		"identical re-registration is idempotent")
	_check(CampaignNodeRegistry.register_node(1, Vector2i(12, 20), "city", nid) == nid,
		"explicit same-id re-registration is idempotent")
	_check(CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city", nid) == "",
		"same id on a different tile rejected")
	_check(CampaignNodeRegistry.register_node(1, Vector2i(12, 20), "safehouse") == "",
		"second node on the same tile rejected (0/1 rule)")
	_check(CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "bait") == "",
		"transient tile type rejected")
	_check(CampaignNodeRegistry.get_node("node_nope").is_empty(), "unknown node returns empty")
	_check(not CampaignNodeRegistry.remove_node("node_nope"), "removing unknown node returns false")
	_check(CampaignNodeRegistry.remove_node(nid), "removing known node returns true")
	_check(not CampaignNodeRegistry.has_node(nid), "removed node is gone")
	CampaignNodeRegistry.clear()


# B — node identity: stable pattern, board reference, sector scoping.
func _test_node_identity() -> void:
	CampaignNodeRegistry.clear()
	var nid := CampaignNodeRegistry.register_node(2, Vector2i(7, 9), "fuel_depot")
	_check(nid == "node_s2_fuel_depot_7_9", "stable id pattern node_s<sector>_<type>_<x>_<y>")
	var n := CampaignNodeRegistry.get_node(nid)
	_check(Vector2i(n.get("tile", Vector2i(-1, -1))) == Vector2i(7, 9)
		and int(n.get("sector", -1)) == 2, "node references board coordinate + sector")
	_check(str(n.get("node_type", "")) == "FUEL_DEPOT", "node type recorded")
	var at := CampaignNodeRegistry.get_node_at(2, Vector2i(7, 9))
	_check(str(at.get("id", "")) == nid, "tile index resolves the node")
	_check(CampaignNodeRegistry.get_node_at(3, Vector2i(7, 9)).is_empty(),
		"same coordinates in another sector resolve nothing (sector-scoped)")
	var other := CampaignNodeRegistry.register_node(3, Vector2i(7, 9), "fuel_depot")
	_check(other == "node_s3_fuel_depot_7_9", "same tile in another sector is a distinct node")
	CampaignNodeRegistry.clear()


# Tile classification: strategic set accepted, transient set refused.
func _test_tile_classification() -> void:
	CampaignNodeRegistry.clear()
	var strategic := ["start", "exit", "safehouse", "city", "fuel_depot",
		"research_lab", "enemy_base", "comms_relay", "prototype_vault",
		"data_node", "salvage_cache", "supply_depot"]
	var x := 0
	for t in strategic:
		_check(CampaignNodeRegistry.register_node(1, Vector2i(x, 0), t) != "",
			"strategic tile accepted: " + t)
		x += 1
	_check(CampaignNodeRegistry.get_nodes().size() == strategic.size(),
		"all strategic types registered")
	var transient := ["event", "bait", "dust_storm", "tactical_smog", "rain",
		"sandstorm", "fog", "emp_zone", "distress_signal", "scavenge_site",
		"unknown_signal", "dead_end", "ambush", "breakdown", "wreckage",
		"supply_truck", "fuel_choice", "empty", ""]
	for t in transient:
		_check(CampaignNodeRegistry.register_node(1, Vector2i(x, 1), t) == "",
			"transient tile refused: '" + t + "'")
		x += 1
	CampaignNodeRegistry.clear()


# C — routes: undirected, canonical, strict rejection.
func _test_routes() -> void:
	CampaignNodeRegistry.clear()
	var a := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city")
	var b := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "safehouse")
	var rid := CampaignNodeRegistry.register_route(a, b)
	_check(rid != "" and CampaignNodeRegistry.has_route(rid), "A<->B route valid")
	_check(CampaignNodeRegistry.register_route(b, a) == "",
		"B<->A duplicate strictly rejected (same edge)")
	var r := CampaignNodeRegistry.get_route(rid)
	_check(str(r.get("a", "")) <= str(r.get("b", "")), "stored endpoints canonicalized")
	_check(CampaignNodeRegistry.register_route(a, b) == "", "exact duplicate rejected")
	_check(CampaignNodeRegistry.register_route(a, a) == "", "self-route rejected")
	_check(CampaignNodeRegistry.register_route(a, "node_nope") == "", "unknown endpoint rejected")
	_check(CampaignNodeRegistry.register_route("node_nope", "node_nope2") == "",
		"two unknown endpoints rejected")
	_check(CampaignNodeRegistry.register_route("", b) == "", "empty endpoint rejected")
	_check(CampaignNodeRegistry.get_route("route_nope").is_empty(), "unknown route returns empty")
	_check(not CampaignNodeRegistry.remove_route("route_nope"), "removing unknown route is false")
	_check(CampaignNodeRegistry.remove_route(rid), "removing known route is true")
	_check(CampaignNodeRegistry.get_routes().is_empty(), "route list empty after removal")
	CampaignNodeRegistry.clear()


# D — graph invariants incl. cascade on node removal.
func _test_invariants() -> void:
	CampaignNodeRegistry.clear()
	var a := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city")
	var b := CampaignNodeRegistry.register_node(1, Vector2i(1, 0), "safehouse")
	var c := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "research_lab")
	CampaignNodeRegistry.register_route(a, b)
	CampaignNodeRegistry.register_route(b, c)
	_check(CampaignNodeRegistry.validate().is_empty(), "healthy graph validates clean")
	_check(CampaignNodeRegistry.get_routes_for(b).size() == 2, "node degree query works")
	CampaignNodeRegistry.remove_node(b)
	_check(CampaignNodeRegistry.get_routes().is_empty(),
		"removing a node cascades its routes (no dangling edges)")
	_check(CampaignNodeRegistry.validate().is_empty(), "graph still valid after cascade")
	_check(CampaignNodeRegistry.has_node(a) and CampaignNodeRegistry.has_node(c),
		"unrelated nodes survive the cascade")
	CampaignNodeRegistry.clear()


# E/G — reset and new-run isolation.
func _test_reset_isolation() -> void:
	CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city")
	CampaignNodeRegistry.register_route(
		CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city"),
		CampaignNodeRegistry.register_node(1, Vector2i(0, 1), "safehouse"))
	GlobalData.reset_run_data()
	_check(CampaignNodeRegistry.get_nodes().is_empty()
		and CampaignNodeRegistry.get_routes().is_empty(),
		"reset_run_data clears topology (no Run A leakage)")


# F — serialize/deserialize equivalence.
func _test_serialize_round_trip() -> void:
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.rebuild_from_tile_types({
		Vector2i(2, 2): "city",
		Vector2i(2, 3): "safehouse",
		Vector2i(5, 5): "fuel_depot",
		Vector2i(6, 6): "event",
	}, 1)
	var snap_a := JSON.stringify(CampaignNodeRegistry.serialize())
	CampaignNodeRegistry.clear()
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "clear empties topology")
	CampaignNodeRegistry.deserialize(JSON.parse_string(snap_a))
	var snap_b := JSON.stringify(CampaignNodeRegistry.serialize())
	_check(snap_a == snap_b, "deserialize restores equivalent topology")
	_check(CampaignNodeRegistry.get_nodes().size() == 3, "three strategic nodes restored")
	_check(CampaignNodeRegistry.get_routes().size() == 1, "one adjacency route restored")
	CampaignNodeRegistry.deserialize({})
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "empty payload restores as empty")
	CampaignNodeRegistry.clear()


# Derivation determinism: same board input always yields the same topology.
func _test_derivation_determinism() -> void:
	var tiles := {
		Vector2i(0, 0): "start",
		Vector2i(2, 2): "city",
		Vector2i(2, 3): "safehouse",
		Vector2i(4, 4): "enemy_base",
		Vector2i(9, 9): "exit",
	}
	CampaignNodeRegistry.rebuild_from_tile_types(tiles, 1)
	var first := JSON.stringify(CampaignNodeRegistry.serialize())
	CampaignNodeRegistry.rebuild_from_tile_types(tiles, 1)
	var second := JSON.stringify(CampaignNodeRegistry.serialize())
	_check(first == second, "rebuild is deterministic for identical board input")
	_check(CampaignNodeRegistry.get_nodes().size() == 5, "five nodes derived")
	_check(CampaignNodeRegistry.get_routes().size() == 1, "one adjacency route derived (city-safehouse)")
	_check(CampaignNodeRegistry.validate().is_empty(), "derived graph validates clean")
	# Incremental sync: plant + consume a strategic tile.
	var planted := CampaignNodeRegistry.sync_tile(1, Vector2i(3, 3), "fuel_depot")
	_check(planted == "node_s1_fuel_depot_3_3", "sync plants a node on a strategic tile")
	_check(CampaignNodeRegistry.sync_tile(1, Vector2i(3, 3), "empty") == "",
		"sync on consumed tile returns empty")
	_check(CampaignNodeRegistry.get_node_at(1, Vector2i(3, 3)).is_empty(),
		"consumed tile hosts no node")
	_check(CampaignNodeRegistry.validate().is_empty(), "graph valid after sync churn")
	CampaignNodeRegistry.clear()


# H — rebuild accepts real board-tile objects (get_meta path).
func _test_board_compat() -> void:
	CampaignNodeRegistry.clear()
	var board := {
		Vector2i(1, 1): _fake_tile("city"),
		Vector2i(1, 2): _fake_tile("bait"),
		Vector2i(3, 3): _fake_tile("research_lab"),
	}
	var res := CampaignNodeRegistry.rebuild_from_board(board, 2)
	_check(int(res.get("nodes", -1)) == 2, "board rebuild registers strategic tiles only")
	_check(int(res.get("routes", -1)) == 0, "no adjacency across the gap")
	_check(CampaignNodeRegistry.has_node("node_s2_city_1_1"), "city node id stable")
	_check(CampaignNodeRegistry.has_node("node_s2_research_lab_3_3"), "lab node id stable")
	CampaignNodeRegistry.clear()


# I — registry calls never touch player/board-movement state.
func _test_movement_untouched() -> void:
	var tile_before: Vector2i = GlobalData.board.current_tile
	var mp_before: int = GlobalData.board.board_mp
	var day_before: int = GlobalData.board.board_day
	CampaignNodeRegistry.rebuild_from_tile_types({Vector2i(0, 0): "start", Vector2i(9, 9): "exit"}, 1)
	CampaignNodeRegistry.sync_tile(1, Vector2i(4, 4), "enemy_base")
	CampaignNodeRegistry.sync_tile(1, Vector2i(4, 4), "empty")
	_check(GlobalData.board.current_tile == tile_before, "current tile untouched")
	_check(GlobalData.board.board_mp == mp_before, "movement points untouched")
	_check(GlobalData.board.board_day == day_before, "board day untouched")
	_check(GlobalData.board.board_grid.is_empty(), "board grid itself untouched")
	CampaignNodeRegistry.clear()
