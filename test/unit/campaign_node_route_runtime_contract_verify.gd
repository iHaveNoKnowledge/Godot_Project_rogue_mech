extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN NODE & ROUTE RUNTIME CONTRACT VERIFICATION
## Phase 5AH Contract Verification Suite
##
## Proves the architectural contract:
##                  TERRITORY
##               macro regional area
##                     │
##           ┌─────────┴─────────┐
##           │                   │
##         NODE ───── ROUTE ───── NODE
##           │                   │
##         BASE                FORCE
##           │
##         PLAYER
##
## Verified Sections:
##   A. Node authority (CampaignNodeRegistry is sole authoritative node topology owner)
##   B. Node identity (Stable IDs, sector scoping, 0/1 tile occupancy rule)
##   C. Node/territory separation (Node presence does not rewrite territory control)
##   D. Node/base separation (Node can exist independently of base)
##   E. Node/force separation (Node does not own forces; multiple forces allowed)
##   F. Force placement (Force node_id represents presence without schema expansion)
##   G. Player separation (Player is not a CampaignForce)
##   H. Route authority (CampaignNodeRegistry is sole route topology authority)
##   I. Route semantics (Route represents undirected connectivity only)
##   J. Route does not simulate movement (Creating/reading routes does not move entities)
##   K. Deterministic topology (Identical inputs produce identical nodes and routes)
##   L. Scenario immutability (Node/route operations cannot mutate ScenarioDefinition)
##   M. Canonical scenario semantics (frontier_skirmish depot/outland/zeon isolation)
##   N. No duplicate topology (No second runtime node or route registry)
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Node & Route Runtime Contract verification (Phase 5AH)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("NODE_ROUTE_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("NODE_ROUTE_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_node_authority()
	_test_b_node_identity()
	_test_c_node_territory_separation()
	_test_d_node_base_separation()
	_test_e_node_force_separation()
	_test_f_force_placement()
	_test_g_player_separation()
	_test_h_route_authority()
	_test_i_route_semantics()
	_test_j_route_does_not_simulate_movement()
	_test_k_deterministic_topology()
	_test_l_scenario_immutability()
	_test_m_canonical_scenario_semantics()
	_test_n_no_duplicate_topology()


func _clear_all_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionEconomySystem.reset()
	GlobalData.current_campaign_scenario_id = ""


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _code_without_comments(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# =============================================================================
# A — NODE AUTHORITY
# =============================================================================
func _test_a_node_authority() -> void:
	_clear_all_state()

	# CampaignNodeRegistry owns node registration, lookup, removal, and listing
	var reg_inst = CampaignNodeRegistry.new()
	_check(reg_inst.has_method("register_node"), "A1: CampaignNodeRegistry exposes register_node")
	_check(reg_inst.has_method("has_node"), "A2: CampaignNodeRegistry exposes has_node")
	_check(reg_inst.has_method("get_node"), "A3: CampaignNodeRegistry exposes get_node")
	_check(reg_inst.has_method("get_nodes"), "A4: CampaignNodeRegistry exposes get_nodes")
	_check(reg_inst.has_method("get_node_at"), "A5: CampaignNodeRegistry exposes get_node_at")
	_check(reg_inst.has_method("remove_node"), "A6: CampaignNodeRegistry exposes remove_node")
	_check(reg_inst.has_method("clear"), "A7: CampaignNodeRegistry exposes clear")

	# Node data carries only topology fields, no ownership or simulation fields
	var nid := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "city")
	var node_data := CampaignNodeRegistry.get_node(nid)
	_check(node_data.has("id") and node_data.has("tile") and node_data.has("sector") and node_data.has("node_type"),
		"A8: Node carries pure topology fields (id, tile, sector, node_type)")
	_check(not node_data.has("controller"), "A9: Node does not store controller")
	_check(not node_data.has("forces"), "A10: Node does not store forces array")
	_check(not node_data.has("base"), "A11: Node does not store base")
	_check(not node_data.has("supply"), "A12: Node does not store supply")


# =============================================================================
# B — NODE IDENTITY
# =============================================================================
func _test_b_node_identity() -> void:
	_clear_all_state()

	# Stable default pattern: node_s<sector>_<type>_<x>_<y>
	var nid := CampaignNodeRegistry.register_node(2, Vector2i(10, 15), "safehouse")
	_check(nid == "node_s2_safehouse_10_15", "B1: Stable ID pattern: node_s<sector>_<type>_<x>_<y>")

	# 0/1 tile occupancy: second node on same tile in same sector rejected
	var duplicate_tile := CampaignNodeRegistry.register_node(2, Vector2i(10, 15), "city")
	_check(duplicate_tile == "", "B2: Reject second node on same tile (0/1 rule)")

	# Sector scoping: same coordinates in different sector is distinct node
	var sector3_node := CampaignNodeRegistry.register_node(3, Vector2i(10, 15), "safehouse")
	_check(sector3_node == "node_s3_safehouse_10_15", "B3: Distinct node in sector 3 at same coordinate")
	_check(CampaignNodeRegistry.get_nodes().size() == 2, "B4: Two distinct nodes across sectors")

	# Re-registering identical node is idempotent
	var re_reg := CampaignNodeRegistry.register_node(2, Vector2i(10, 15), "safehouse", nid)
	_check(re_reg == nid, "B5: Re-registering identical node is idempotent")


# =============================================================================
# C — NODE / TERRITORY SEPARATION
# =============================================================================
func _test_c_node_territory_separation() -> void:
	_clear_all_state()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city")
	var tid := CampaignTerritory.register_territory("terr_test_c", [nid])
	CampaignTerritory.set_controlled(tid, "federation")

	# Node presence inside territory does not inject controller into node
	var node_data := CampaignNodeRegistry.get_node(nid)
	_check(not node_data.has("controller"), "C1: Node does not acquire controller property from territory")

	# Changing territory control does not mutate node
	CampaignTerritory.set_controlled(tid, "zeon")
	var node_data_after := CampaignNodeRegistry.get_node(nid)
	_check(node_data_after == node_data, "C2: Changing territory controller leaves node unchanged")

	# Setting territory contested does not mutate node
	CampaignTerritory.set_contested(tid, ["federation", "zeon"])
	_check(CampaignNodeRegistry.get_node(nid) == node_data, "C3: Contested territory leaves node unchanged")


# =============================================================================
# D — NODE / BASE SEPARATION
# =============================================================================
func _test_d_node_base_separation() -> void:
	_clear_all_state()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse")
	_check(CampaignBase.get_bases().is_empty(), "D1: Registering node does not create base")

	# Base can anchor to node, but node remains separate
	var bid := CampaignBase.register_base("base_test_d", nid, "OUTPOST", "federation", "")
	_check(bid != "", "D2: Base successfully anchored to node")
	_check(CampaignBase.has_base(bid), "D3: Base exists in CampaignBase")

	# Mutating base state (active -> disabled -> destroyed) does not mutate node
	var node_data_before := CampaignNodeRegistry.get_node(nid)
	CampaignBase.set_state(bid, CampaignBase.BaseState.DESTROYED)
	_check(CampaignBase.get_state(bid) == CampaignBase.BaseState.DESTROYED, "D4: Base state changed to DESTROYED")
	_check(CampaignNodeRegistry.get_node(nid) == node_data_before, "D5: Base state mutation does not mutate node")
	_check(CampaignNodeRegistry.has_node(nid), "D6: Base destroyed leaves node intact")


# =============================================================================
# E — NODE / FORCE SEPARATION
# =============================================================================
func _test_e_node_force_separation() -> void:
	_clear_all_state()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "city")
	_check(CampaignForce.get_forces().is_empty(), "E1: Node creation does not create forces")

	# Multiple forces can occupy the same node
	var fid_1 := CampaignForce.register_force("force_test_1", "PATROL", "federation", nid, "", 2, 20)
	var fid_2 := CampaignForce.register_force("force_test_2", "SCAVENGER", "outland", nid, "", 1, 10)
	_check(fid_1 != "" and fid_2 != "", "E2: Multiple forces successfully registered at same node")

	# Node data has no forces array
	var node_data := CampaignNodeRegistry.get_node(nid)
	_check(not node_data.has("forces"), "E3: Node does not maintain forces array")

	# Force state changes do not mutate node
	CampaignForce.set_state(fid_1, CampaignForce.ForceState.DISABLED)
	_check(CampaignNodeRegistry.get_node(nid) == node_data, "E4: Force state change does not mutate node")


# =============================================================================
# F — FORCE PLACEMENT
# =============================================================================
func _test_f_force_placement() -> void:
	_clear_all_state()

	var nid_a := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city")
	var nid_b := CampaignNodeRegistry.register_node(1, Vector2i(1, 2), "safehouse")
	var fid := CampaignForce.register_force("force_test_f", "PATROL", "federation", nid_a, "", 3, 30)

	var force_data := CampaignForce.get_force(fid)
	_check(force_data.get("node_id", "") == nid_a, "F1: Force node_id records presence at Node A")

	# Force schema remains strict (no injected node or territory objects)
	var keys := force_data.keys()
	keys.sort()
	var expected_keys := ["base_id", "faction", "force_type", "id", "node_id", "state", "strength", "unit_count"]
	expected_keys.sort()
	_check(keys == expected_keys, "F2: CampaignForce schema remains strictly locked without extra fields")


# =============================================================================
# G — PLAYER SEPARATION
# =============================================================================
func _test_g_player_separation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Player position is stored in GlobalData.board.current_tile, not CampaignForce
	_check(GlobalData.board.current_tile is Vector2i, "G1: Player position is Vector2i on board")
	_check(not CampaignForce.has_force("player"), "G2: Player is not in CampaignForce registry")

	for f in CampaignForce.get_forces():
		var f_id := str(f.get("id", ""))
		_check(not f_id.begins_with("player"), "G3: Force %s is not a player force" % f_id)
		_check(f.get("force_type", "") != "PLAYER", "G4: Force %s type != PLAYER" % f_id)


# =============================================================================
# H — ROUTE AUTHORITY
# =============================================================================
func _test_h_route_authority() -> void:
	_clear_all_state()

	var reg_inst = CampaignNodeRegistry.new()
	_check(reg_inst.has_method("register_route"), "H1: CampaignNodeRegistry exposes register_route")
	_check(reg_inst.has_method("has_route"), "H2: CampaignNodeRegistry exposes has_route")
	_check(reg_inst.has_method("get_route"), "H3: CampaignNodeRegistry exposes get_route")
	_check(reg_inst.has_method("get_routes"), "H4: CampaignNodeRegistry exposes get_routes")
	_check(reg_inst.has_method("get_routes_for"), "H5: CampaignNodeRegistry exposes get_routes_for")
	_check(reg_inst.has_method("remove_route"), "H6: CampaignNodeRegistry exposes remove_route")


# =============================================================================
# I — ROUTE SEMANTICS
# =============================================================================
func _test_i_route_semantics() -> void:
	_clear_all_state()

	var a := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city")
	var b := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse")

	var rid := CampaignNodeRegistry.register_route(a, b)
	_check(rid != "", "I1: Route registered between Node A and Node B")

	var route_data := CampaignNodeRegistry.get_route(rid)
	_check(route_data.has("id") and route_data.has("a") and route_data.has("b"), "I2: Route has pure topology fields (id, a, b)")
	_check(not route_data.has("cost"), "I3: Route carries no travel cost field")
	_check(not route_data.has("supply"), "I4: Route carries no supply field")
	_check(not route_data.has("threat"), "I5: Route carries no threat field")
	_check(not route_data.has("controller"), "I6: Route carries no controller field")

	# Undirected edge: A,B and B,A resolve to same edge; duplicate rejected
	_check(CampaignNodeRegistry.register_route(b, a) == "", "I7: Reverse direction duplicate strictly rejected")
	_check(CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id(b, a)), "I8: Reverse lookup resolves to same route")


# =============================================================================
# J — ROUTE DOES NOT SIMULATE MOVEMENT
# =============================================================================
func _test_j_route_does_not_simulate_movement() -> void:
	_clear_all_state()

	var a := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city")
	var b := CampaignNodeRegistry.register_node(1, Vector2i(1, 0), "safehouse")
	var fid := CampaignForce.register_force("force_static", "PATROL", "federation", a, "", 1, 10)

	var tile_before: Vector2i = GlobalData.board.current_tile

	# Registering route does not move force or player
	var rid := CampaignNodeRegistry.register_route(a, b)
	_check(rid != "", "J1: Route registered")
	_check(CampaignForce.get_force(fid).get("node_id", "") == a, "J2: Force remained at Node A")
	_check(GlobalData.board.current_tile == tile_before, "J3: Player position remained unchanged")

	# Reading route does not move force or player
	var r := CampaignNodeRegistry.get_route(rid)
	_check(not r.is_empty(), "J4: Route retrieved")
	_check(CampaignForce.get_force(fid).get("node_id", "") == a, "J5: Force still at Node A")
	_check(GlobalData.board.current_tile == tile_before, "J6: Player position still unchanged")


# =============================================================================
# K — DETERMINISTIC TOPOLOGY
# =============================================================================
func _test_k_deterministic_topology() -> void:
	_clear_all_state()

	var tile_map := {
		Vector2i(0, 0): "city",
		Vector2i(1, 0): "safehouse",
		Vector2i(5, 5): "fuel_depot",
	}

	# Run 1
	var counts_1 := CampaignNodeRegistry.rebuild_from_tile_types(tile_map, 1)
	var snap_1 := JSON.stringify(CampaignNodeRegistry.serialize())

	_clear_all_state()

	# Run 2
	var counts_2 := CampaignNodeRegistry.rebuild_from_tile_types(tile_map, 1)
	var snap_2 := JSON.stringify(CampaignNodeRegistry.serialize())

	_check(counts_1 == counts_2, "K1: Rebuild counts match identically across runs")
	_check(snap_1 == snap_2, "K2: Serialized topology matches identically across runs")


# =============================================================================
# L — SCENARIO IMMUTABILITY
# =============================================================================
func _test_l_scenario_immutability() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var node_specs_before: Array = scenario.get_initial_node_specs().duplicate(true)

	# Register a new node and route in runtime registry
	var new_nid := CampaignNodeRegistry.register_node(1, Vector2i(25, 25), "safehouse")
	_check(new_nid != "", "L1: New runtime node registered")
	CampaignNodeRegistry.register_route("node_frontier_safehouse", new_nid)

	# ScenarioDefinition initial_node_specs must be strictly unmutated
	var node_specs_after: Array = scenario.get_initial_node_specs()
	_check(node_specs_after == node_specs_before, "L2: ScenarioDefinition.initial_node_specs is completely unmutated")
	_check(not ("_nodes" in scenario), "L3: ScenarioDefinition does not contain _nodes")
	_check(not ("_routes" in scenario), "L4: ScenarioDefinition does not contain _routes")


# =============================================================================
# M — CANONICAL SCENARIO SEMANTICS (frontier_skirmish)
# =============================================================================
func _test_m_canonical_scenario_semantics() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Canonical scenario nodes
	_check(CampaignNodeRegistry.has_node("node_frontier_safehouse"), "M1: Safehouse node registered")
	_check(CampaignNodeRegistry.has_node("node_frontier_city"), "M2: City node registered")
	_check(CampaignNodeRegistry.has_node("node_frontier_depot"), "M3: Depot node registered")
	_check(CampaignNodeRegistry.has_node("node_frontier_outpost"), "M4: Outpost node registered")

	# Verify semantic closure:
	# 1. Depot is member of terr_frontier_sector_beta (controlled by zeon)
	var beta_terr := CampaignTerritory.get_territory("terr_frontier_sector_beta")
	_check(beta_terr.get("controller", "") == "zeon", "M5: Sector Beta territory controlled by zeon")
	var beta_members: Array = CampaignTerritory.get_members("terr_frontier_sector_beta")
	_check(beta_members.has("node_frontier_depot"), "M6: Depot node is inside Sector Beta territory")

	# 2. Outland force is located at depot
	var outland_force := CampaignForce.get_force("force_s1_outland_scavengers")
	_check(outland_force.get("node_id", "") == "node_frontier_depot", "M7: Outland scavengers located at depot node")
	_check(outland_force.get("faction", "") == "outland", "M8: Force faction is outland")

	# 3. CRITICAL: Outland force presence at depot did NOT change Sector Beta territory controller to outland
	_check(CampaignTerritory.get_controller("terr_frontier_sector_beta") == "zeon",
		"M9: Sector Beta controller remains zeon despite Outland force presence at depot")
	_check(not CampaignTerritory.is_contested("terr_frontier_sector_beta"),
		"M10: Sector Beta is not contested by Outland presence")


# =============================================================================
# N — NO DUPLICATE TOPOLOGY
# =============================================================================
func _test_n_no_duplicate_topology() -> void:
	_clear_all_state()

	# GlobalData has no node/route registry
	_check(not ("nodes" in GlobalData), "N1: GlobalData does not declare nodes")
	_check(not ("routes" in GlobalData), "N2: GlobalData does not declare routes")
	_check(not ("node_registry" in GlobalData), "N3: GlobalData does not declare node_registry")

	# BoardState has no strategic node registry
	_check(not ("strategic_nodes" in GlobalData.board), "N4: BoardState does not declare strategic_nodes")
	_check(not ("strategic_routes" in GlobalData.board), "N5: BoardState does not declare strategic_routes")

	# CampaignTerritory, CampaignBase, CampaignForce do not store nodes or routes
	var terr_inst = CampaignTerritory.new()
	var base_inst = CampaignBase.new()
	var force_inst = CampaignForce.new()
	_check(not terr_inst.has_method("register_node"), "N6: CampaignTerritory does not own register_node")
	_check(not base_inst.has_method("register_node"), "N7: CampaignBase does not own register_node")
	_check(not force_inst.has_method("register_node"), "N8: CampaignForce does not own register_node")


# =============================================================================
# SUMMARY & EXIT
# =============================================================================
func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE 5AH SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN NODE & ROUTE RUNTIME CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN NODE & ROUTE RUNTIME CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
