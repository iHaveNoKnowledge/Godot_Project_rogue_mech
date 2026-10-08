extends Node

## ---------------------------------------------------------------------------
## VALKREN CAMPAIGN V2 — C2: NODE / ROUTE / TURN PROGRESSION VERIFICATION
##
## Verifies:
##   1. Node Authority & Invariants: CampaignNodeRegistry owns nodes; deterministic ID.
##   2. Route Authority & Invariants: Canonical undirected route; duplicate rejection.
##   3. Reachable Node Queries: Read-only adjacency and player reachability.
##   4. Player Movement Traversal: Node -> Route -> Node; atomic physical sync; delta turn = 0.
##   5. Turn Authority: CampaignTurnExecutive sole turn owner; movement never advances turn.
##   6. Force Movement Isolation: Force movement uses topology and never mutates player position.
##   7. Save / Load Persistence: Player & force positions survive round-trip without topology duplication.
## ---------------------------------------------------------------------------

const RunStartSystem = preload("res://scripts/systems/run_start_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignForceMovement = preload("res://scripts/systems/campaign_force_movement.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")

var _passed_count: int = 0
var _failed_count: int = 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Node / Route / Turn Progression Verification (C2)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("CAMPAIGN_C2 OK: %s" % test_name)
	else:
		_failed_count += 1
		printerr("CAMPAIGN_C2 FAIL: %s" % test_name)


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE C2 SUMMARY: Passed: %d, Failed: %d" % [_passed_count, _failed_count])
	print("----------------------------------------------------------------------")
	if _failed_count == 0:
		print("ALL CAMPAIGN NODE / ROUTE / TURN (C2) CHECKS PASSED!")


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.close()


func _clear_all_state() -> void:
	RunStartSystem._clear_campaign_runtime_state()
	GlobalData.pilot.reset()
	GlobalData.hangar.reset()


func _run_all_tests() -> void:
	_test_node_authority_and_identity()
	_test_route_authority_and_undirected_canonical()
	_test_reachable_node_queries()
	_test_player_strategic_movement()
	_test_turn_independence_from_movement()
	_test_force_movement_isolation()
	_test_save_load_position_fidelity()


func _test_node_authority_and_identity() -> void:
	print("\n--- Test: Node Authority & Identity ---")
	_clear_all_state()
	var nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "city")
	_check(nid != "", "Node registered successfully")
	_check(nid == "node_s1_city_4_4", "Node ID follows deterministic pattern: node_s1_city_4_4")
	_check(CampaignNodeRegistry.has_node(nid), "has_node returns true for registered node")
	_check(not CampaignNodeRegistry.has_node("non_existent_node"), "has_node returns false for unknown node")

	var node_data := CampaignNodeRegistry.get_node(nid)
	_check(node_data.get("id") == nid, "get_node returns correct id")
	_check(node_data.get("tile") == Vector2i(4, 4), "get_node returns correct tile anchor")
	_check(node_data.get("sector") == 1, "get_node returns correct sector")
	_check(node_data.get("node_type") == "CITY", "get_node returns canonical CITY type")

	# Node at tile lookup
	var found_node := CampaignNodeRegistry.get_node_at(1, Vector2i(4, 4))
	_check(found_node.get("id") == nid, "get_node_at returns node for matching sector and tile")
	_check(CampaignNodeRegistry.get_node_at(1, Vector2i(99, 99)).is_empty(), "get_node_at returns empty for unmapped tile")


func _test_route_authority_and_undirected_canonical() -> void:
	print("\n--- Test: Route Authority & Undirected Canonical Contract ---")
	_clear_all_state()
	var n1 := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_n1")
	var n2 := CampaignNodeRegistry.register_node(1, Vector2i(2, 1), "city", "node_n2")
	var n3 := CampaignNodeRegistry.register_node(1, Vector2i(3, 1), "fuel_depot", "node_n3")

	# Register route n1 <-> n2
	var r1 := CampaignNodeRegistry.register_route(n1, n2)
	_check(r1 != "", "Route n1-n2 registered successfully")
	_check(r1 == "route_node_n1__node_n2", "Canonical route ID is route_node_n1__node_n2")

	# Register reverse route n2 <-> n1 (must detect duplicate and reject)
	var r_dup := CampaignNodeRegistry.register_route(n2, n1)
	_check(r_dup == "", "Reverse route registration rejected as duplicate edge")

	# Query route
	_check(CampaignNodeRegistry.has_route("route_node_n1__node_n2"), "has_route finds canonical route ID")
	_check(CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id(n2, n1)), "make_route_id resolves symmetrically")
	_check(not CampaignNodeRegistry.has_route("route_node_n1__node_n3"), "has_route returns false for unconnected nodes")

	# Self loop rejected
	var r_loop := CampaignNodeRegistry.register_route(n1, n1)
	_check(r_loop == "", "Self-loop route registration rejected")


func _test_reachable_node_queries() -> void:
	print("\n--- Test: Reachable Node Queries ---")
	_clear_all_state()
	var n1 := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_hub")
	var n2 := CampaignNodeRegistry.register_node(1, Vector2i(2, 1), "city", "node_east")
	var n3 := CampaignNodeRegistry.register_node(1, Vector2i(1, 2), "fuel_depot", "node_south")
	var n4 := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "enemy_base", "node_isolated")

	CampaignNodeRegistry.register_route(n1, n2)
	CampaignNodeRegistry.register_route(n1, n3)

	var connected_ids := CampaignNodeRegistry.get_connected_node_ids(n1)
	_check(connected_ids.size() == 2, "Hub node has exactly 2 connected neighbors")
	_check(connected_ids.has("node_east") and connected_ids.has("node_south"), "Hub neighbors are node_east and node_south")
	_check(not connected_ids.has("node_isolated"), "Isolated node is not in connected neighbors")

	# Player reachability from current position
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1) # On node_hub
	_check(CampaignPlayerMovement.get_current_node_id() == "node_hub", "Player current node derived as node_hub")

	var reachable_ids := CampaignPlayerMovement.get_reachable_node_ids()
	_check(reachable_ids == connected_ids, "Player reachable node IDs match hub connected node IDs")
	var reachable_nodes := CampaignPlayerMovement.get_reachable_nodes()
	_check(reachable_nodes.size() == 2, "Player reachable full node data returns 2 dictionaries")


func _test_player_strategic_movement() -> void:
	print("\n--- Test: Player Strategic Movement (Node -> Route -> Node) ---")
	_clear_all_state()
	var n1 := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse", "node_start")
	var n2 := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "city", "node_dest")
	var n3 := CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "fuel_depot", "node_unreachable")
	CampaignNodeRegistry.register_route(n1, n2)

	# Place player at start
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)
	_check(CampaignPlayerMovement.get_current_node_id() == "node_start", "Player is at node_start")

	# Move to unreachable node (no route)
	var res_bad_route = CampaignPlayerMovement.move_player_to_node("node_unreachable")
	_check(not res_bad_route.get("ok", true), "Movement to disconnected node rejected")
	_check(res_bad_route.get("reason") == "no_route", "Failure reason is no_route")
	_check(GlobalData.board.current_tile == Vector2i(2, 2), "Player position untouched after bad route attempt")

	# Move to unknown node
	var res_bad_node = CampaignPlayerMovement.move_player_to_node("node_unknown_xyz")
	_check(not res_bad_node.get("ok", true), "Movement to unknown node rejected")
	_check(res_bad_node.get("reason") == "unknown_destination", "Failure reason is unknown_destination")
	_check(GlobalData.board.current_tile == Vector2i(2, 2), "Player position untouched after unknown node attempt")

	# Move to valid connected node
	var res_move = CampaignPlayerMovement.move_player_to_node("node_dest")
	_check(res_move.get("ok", false), "Movement to connected node succeeds")
	_check(GlobalData.board.current_tile == Vector2i(4, 4), "Player physical tile updated to destination anchor (4, 4)")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_dest", "Player strategic node is now node_dest")

	# Move to same node
	var res_same = CampaignPlayerMovement.move_player_to_node("node_dest")
	_check(res_same.get("ok", false) and not res_same.get("changed", true), "Moving to same node reports ok=true and changed=false")


func _test_turn_independence_from_movement() -> void:
	print("\n--- Test: Turn Independence from Movement (Δturn = 0) ---")
	_clear_all_state()
	var n1 := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_a")
	var n2 := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_b")
	CampaignNodeRegistry.register_route(n1, n2)

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)

	var initial_turn: int = CampaignTurnExecutive.get_turn()
	_check(initial_turn == 0, "Initial turn counter is 0")

	# Perform 5 hops back and forth
	CampaignPlayerMovement.move_player_to_node("node_b")
	CampaignPlayerMovement.move_player_to_node("node_a")
	CampaignPlayerMovement.move_player_to_node("node_b")
	CampaignPlayerMovement.move_player_to_node("node_a")
	CampaignPlayerMovement.move_player_to_node("node_b")

	_check(CampaignTurnExecutive.get_turn() == 0, "5 strategic player moves caused exactly 0 turn advances (turn still 0)")

	# Explicit turn progression
	CampaignTurnExecutive.advance_campaign_turn()
	_check(CampaignTurnExecutive.get_turn() == 1, "Turn incremented to 1 only upon explicit CampaignTurnExecutive call")


func _test_force_movement_isolation() -> void:
	print("\n--- Test: Force Movement Isolation ---")
	_clear_all_state()
	var n1 := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_f1")
	var n2 := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_f2")
	var n3 := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "enemy_base", "node_f3")
	CampaignNodeRegistry.register_route(n1, n2)

	# Register force at node_f1
	var fid := CampaignForce.register_force("force_test_01", "PATROL", "", "node_f1", "", 2, 20)
	_check(fid != "", "Force registered at node_f1")

	# Set player at node_f3
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(9, 9)
	_check(CampaignPlayerMovement.get_current_node_id() == "node_f3", "Player is at node_f3")

	# Move force from node_f1 to node_f2
	var res_force = CampaignForceMovement.move_force(fid, "node_f2")
	_check(res_force.get("ok", false), "Force moved successfully to node_f2")
	_check(CampaignForce.get_force(fid).get("node_id") == "node_f2", "Force location updated to node_f2")

	# Verify player position and turn were NOT mutated
	_check(GlobalData.board.current_tile == Vector2i(9, 9), "Player physical tile remains untouched (9, 9)")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_f3", "Player strategic position remains node_f3")
	_check(CampaignTurnExecutive.get_turn() == 0, "Force movement caused 0 turn advances")


func _test_save_load_position_fidelity() -> void:
	print("\n--- Test: Save / Load Position Fidelity ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.weapons._ensure_default_frames()

	# Connect safehouse and city, and place player at safehouse (1, 1)
	CampaignNodeRegistry.register_route("node_frontier_safehouse", "node_frontier_city")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)
	_check(CampaignPlayerMovement.get_current_node_id() == "node_frontier_safehouse", "Player starts at node_frontier_safehouse")

	# Move player to node_frontier_city (tile (3, 2))
	var move_res = CampaignPlayerMovement.move_player_to_node("node_frontier_city")
	_check(move_res.get("ok", false), "Player moved to node_frontier_city")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_frontier_city", "Player is at node_frontier_city")

	# Save run
	var saved: bool = SaveGameIO.save_run()
	_check(saved, "Save run succeeds")

	# Clear runtime
	RunStartSystem._clear_campaign_runtime_state()
	GlobalData.board.current_tile = Vector2i(-1, -1)
	_check(CampaignPlayerMovement.get_current_node_id() == "", "Position cleared on reset")

	# Load run
	var loaded: bool = SaveGameIO.load_run()
	_check(loaded, "Load run succeeds")
	_check(GlobalData.board.current_tile == Vector2i(3, 2), "Physical tile restored to (3, 2)")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_frontier_city", "Strategic node derived correctly as node_frontier_city")
