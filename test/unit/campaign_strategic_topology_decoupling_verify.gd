extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC TOPOLOGY DECOUPLING VERIFICATION (Phase C2.6)
##
## Verifies:
##   1. Scenario defines multiple Nodes and non-adjacent explicit Routes.
##   2. Route connectivity works regardless of tile-coordinate distance.
##   3. Invalid route endpoints are rejected by ScenarioSchemaValidator.
##   4. Self-loops and duplicate routes are rejected by ScenarioSchemaValidator.
##   5. Player strategic Node ID is authoritative in CampaignPlayerMovement.
##   6. Movement to a connected Node succeeds without intermediate tile steps.
##   7. Movement to a disconnected or nonexistent Node fails without changing position.
##   8. Node inspection and action dispatch use strategic Node identity.
##   9. Strategic movement does not invoke per-tile movement costs or fuel/MP drain.
##  10. Explicit authored topology survives board generation / rebuild.
##  11. Save/load round-trips current Node ID and route graph.
##  12. Legacy tile-only save is handled safely.
##  13. Existing force movement and campaign turn contracts remain intact.
const RunStartSystem = preload("res://scripts/systems/run_start_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignForceMovement = preload("res://scripts/systems/campaign_force_movement.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const ScenarioDefinition = preload("res://resources/data/scenario_definition.gd")
const ScenarioSchemaValidator = preload("res://scripts/systems/scenario_schema_validator.gd")

var _passed_count := 0
var _failed_count := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Strategic Topology Decoupling Verification (C2.6)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("CAMPAIGN_C26 OK: %s" % test_name)
	else:
		_failed_count += 1
		printerr("CAMPAIGN_C26 FAIL: %s" % test_name)


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE C2.6 SUMMARY: Passed: %d, Failed: %d" % [_passed_count, _failed_count])
	print("----------------------------------------------------------------------")
	if _failed_count == 0:
		print("ALL STRATEGIC TOPOLOGY DECOUPLING (C2.6) CHECKS PASSED!")
		get_tree().quit(0)
	else:
		printerr("STRATEGIC TOPOLOGY DECOUPLING CHECKS FAILED!")
		get_tree().quit(1)


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.close()


func _run_all_tests() -> void:
	_test_scenario_explicit_routes_and_schema_validation()
	_test_route_connectivity_independent_of_grid_distance()
	_test_invalid_routes_self_loops_and_duplicates()
	_test_authoritative_player_strategic_node_position()
	_test_strategic_movement_success_and_failure()
	_test_strategic_movement_no_tile_side_effects()
	_test_node_inspection_and_action_dispatch_use_node_identity()
	_test_authored_topology_survives_board_rebuild()
	_test_save_load_roundtrip_and_legacy_fallback()
	_test_campaign_force_movement_and_turn_executive_integrity()


func _test_scenario_explicit_routes_and_schema_validation() -> void:
	print("\n--- Test 1: Scenario authored explicit routes & canonical validation ---")
	var scenario: ScenarioDefinition = load("res://resources/data/scenarios/frontier_skirmish.tres")
	_check(scenario != null, "Canonical scenario resource loads")
	var routes: Array = scenario.get_initial_route_specs()
	_check(routes.size() >= 3, "Canonical scenario contains authored explicit routes")
	_check(routes[0].has("a") and routes[0].has("b"), "Route spec has 'a' and 'b' endpoints")

	var validation := ScenarioSchemaValidator.validate_scenario(scenario)
	_check(bool(validation.get("valid", false)), "Canonical scenario with explicit routes is 100% valid under validator")
	_check(validation.get("errors", []).is_empty(), "Zero validation errors reported")


func _test_route_connectivity_independent_of_grid_distance() -> void:
	print("\n--- Test 2: Route connectivity independent of grid distance ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.set_authored_topology(true)

	# Register two nodes with large grid distance (0,0) and (30,30)
	var id_a := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "safehouse", "node_a")
	var id_b := CampaignNodeRegistry.register_node(1, Vector2i(30, 30), "city", "node_b")
	var rid := CampaignNodeRegistry.register_route("node_a", "node_b")

	_check(rid != "", "Explicit route registered across non-adjacent tiles")
	_check(CampaignNodeRegistry.has_route(rid), "Route exists in registry")
	_check(CampaignNodeRegistry.get_connected_node_ids("node_a") == ["node_b"], "node_a connects to node_b")
	_check(CampaignNodeRegistry.get_connected_node_ids("node_b") == ["node_a"], "node_b connects to node_a")


func _test_invalid_routes_self_loops_and_duplicates() -> void:
	print("\n--- Test 3: Invalid route endpoints, self-loops, and duplicates ---")
	var base_scenario: ScenarioDefinition = load("res://resources/data/scenarios/frontier_skirmish.tres")
	_check(base_scenario != null, "Base scenario loads for error testing")

	# 1. Unknown endpoint
	var s_dangling := base_scenario.duplicate(true) as ScenarioDefinition
	s_dangling.initial_route_specs = [{"a": "node_frontier_safehouse", "b": "node_nonexistent"}]
	var val1 := ScenarioSchemaValidator.validate_scenario(s_dangling)
	_check(not bool(val1.get("valid", false)), "Route to unknown node is invalid")
	var err_codes1: Array = []
	for e in val1.get("errors", []):
		err_codes1.append(e.get("code", ""))
	_check(err_codes1.has("DANGLING_NODE_REFERENCE"), "Reports DANGLING_NODE_REFERENCE error")

	# 2. Self loop
	var s_self := base_scenario.duplicate(true) as ScenarioDefinition
	s_self.initial_route_specs = [{"a": "node_frontier_safehouse", "b": "node_frontier_safehouse"}]
	var val2 := ScenarioSchemaValidator.validate_scenario(s_self)
	_check(not bool(val2.get("valid", false)), "Self-loop route is rejected")
	var err_codes2: Array = []
	for e in val2.get("errors", []):
		err_codes2.append(e.get("code", ""))
	_check(err_codes2.has("SELF_ROUTE_PROHIBITED"), "Reports SELF_ROUTE_PROHIBITED error")

	# 3. Duplicate route
	var s_dup := base_scenario.duplicate(true) as ScenarioDefinition
	s_dup.initial_route_specs = [
		{"a": "node_frontier_safehouse", "b": "node_frontier_city"},
		{"a": "node_frontier_city", "b": "node_frontier_safehouse"}
	]
	var val3 := ScenarioSchemaValidator.validate_scenario(s_dup)
	_check(not bool(val3.get("valid", false)), "Duplicate route is rejected")
	var err_codes3: Array = []
	for e in val3.get("errors", []):
		err_codes3.append(e.get("code", ""))
	_check(err_codes3.has("DUPLICATE_ROUTE_SPEC"), "Reports DUPLICATE_ROUTE_SPEC error")


func _test_authoritative_player_strategic_node_position() -> void:
	print("\n--- Test 4: Authoritative player strategic node position ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "safehouse", "node_safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(10, 10), "city", "node_city")

	GlobalData.current_campaign_player_node_id = ""
	CampaignPlayerMovement.set_current_node_id("node_safehouse")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_safehouse", "get_current_node_id returns set node")
	_check(GlobalData.board.current_tile == Vector2i(5, 5), "Legacy board current_tile synced with anchored node")

	# Position does not become empty if tile coordinates differ
	GlobalData.board.current_tile = Vector2i(99, 99)
	_check(CampaignPlayerMovement.get_current_node_id() == "node_safehouse", "Player node ID remains authoritative even if board tile changed")


func _test_strategic_movement_success_and_failure() -> void:
	print("\n--- Test 5: Strategic movement success and failure ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "n1")
	CampaignNodeRegistry.register_node(1, Vector2i(20, 20), "city", "n2")
	CampaignNodeRegistry.register_node(1, Vector2i(30, 30), "fuel_depot", "n3")
	CampaignNodeRegistry.register_route("n1", "n2")
	# n3 is not connected to n1

	CampaignPlayerMovement.set_current_node_id("n1")

	# Failed move to disconnected node
	var move_disconnected := CampaignPlayerMovement.move_player_to_node("n3")
	_check(not bool(move_disconnected.get("ok", false)), "Moving to disconnected node fails")
	_check(CampaignPlayerMovement.get_current_node_id() == "n1", "Position unchanged after failed move")

	# Failed move to unknown node
	var move_unknown := CampaignPlayerMovement.move_player_to_node("node_unknown")
	_check(not bool(move_unknown.get("ok", false)), "Moving to unknown node fails")
	_check(CampaignPlayerMovement.get_current_node_id() == "n1", "Position unchanged after unknown node move")

	# Successful move to connected node
	var move_valid := CampaignPlayerMovement.move_player_to_node("n2")
	_check(bool(move_valid.get("ok", false)), "Moving to connected node succeeds")
	_check(CampaignPlayerMovement.get_current_node_id() == "n2", "Player position updated to destination node")
	_check(GlobalData.board.current_tile == Vector2i(20, 20), "Legacy board tile updated to destination anchor")


func _test_strategic_movement_no_tile_side_effects() -> void:
	print("\n--- Test 6: Strategic movement has no tile side-effects (no MP/fuel drain, no turn advance) ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "safehouse", "base_node")
	CampaignNodeRegistry.register_node(1, Vector2i(25, 25), "city", "target_node")
	CampaignNodeRegistry.register_route("base_node", "target_node")

	CampaignTurnExecutive.reset()
	GlobalData.board.board_mp = 8
	GlobalData.fuel.mech_energy = 100.0
	CampaignPlayerMovement.set_current_node_id("base_node")

	var turn_before := CampaignTurnExecutive.get_turn()
	var mp_before := GlobalData.board.board_mp
	var fuel_before := GlobalData.fuel.mech_energy

	var res := CampaignPlayerMovement.move_player_to_node("target_node")
	_check(bool(res.get("ok", false)), "Hop performed across 25 tiles distance")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "Campaign turn executive not advanced by movement")
	_check(GlobalData.board.board_mp == mp_before, "Tactical board MP untouched by strategic hop")
	_check(GlobalData.fuel.mech_energy == fuel_before, "Tactical mech energy untouched by strategic hop")


func _test_node_inspection_and_action_dispatch_use_node_identity() -> void:
	print("\n--- Test 7: Node inspection and action dispatch use node identity ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_metro")
	CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "fuel_depot", "node_refuel")
	CampaignNodeRegistry.register_route("node_metro", "node_refuel")

	CampaignPlayerMovement.set_current_node_id("node_metro")

	_check(CampaignNodeInspection.is_player_at_node("node_metro"), "Player is detected at current node")
	_check(not CampaignNodeInspection.is_player_at_node("node_refuel"), "Player is NOT detected at other node")

	var intent_local := CampaignPlayerDispatch.create_intent("investigate", "node_metro")
	var val_local := CampaignPlayerDispatch.validate_intent(intent_local)
	_check(bool(val_local.get("ok", false)), "Dispatch intent valid at player's current node")

	var intent_remote := CampaignPlayerDispatch.create_intent("investigate", "node_refuel")
	var val_remote := CampaignPlayerDispatch.validate_intent(intent_remote)
	_check(not bool(val_remote.get("ok", false)), "Dispatch intent rejected when player is not at target node")
	_check(str(val_remote.get("reason", "")) == "player_not_at_node", "Rejection reason is player_not_at_node")


func _test_authored_topology_survives_board_rebuild() -> void:
	print("\n--- Test 8: Authored topology survives board rebuild ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.set_authored_topology(true)
	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "authored_1")
	CampaignNodeRegistry.register_node(1, Vector2i(10, 10), "city", "authored_2")
	CampaignNodeRegistry.register_route("authored_1", "authored_2")

	_check(CampaignNodeRegistry.is_authored_topology(), "Authored topology flag is active")

	# Simulate tactical board generating new tiles
	var mock_board := {
		Vector2i(3, 3): "safehouse",
		Vector2i(3, 4): "city"
	}
	var res := CampaignNodeRegistry.rebuild_from_tile_types(mock_board, 1)

	_check(CampaignNodeRegistry.has_node("authored_1"), "Authored node 1 survived board rebuild")
	_check(CampaignNodeRegistry.has_node("authored_2"), "Authored node 2 survived board rebuild")
	_check(CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id("authored_1", "authored_2")), "Authored route survived board rebuild")


func _test_save_load_roundtrip_and_legacy_fallback() -> void:
	print("\n--- Test 9: Save/load round-trip and legacy fallback ---")
	RunStartSystem._clear_campaign_runtime_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.weapons._ensure_default_frames()

	# Place player at node_frontier_city
	CampaignPlayerMovement.set_current_node_id("node_frontier_city")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_frontier_city", "Player placed at node_frontier_city")

	# Save
	var save_success := SaveGameIO.save_run()
	_check(save_success, "SaveGameIO.save_run succeeded")

	# Clear runtime
	RunStartSystem._clear_campaign_runtime_state()
	_check(CampaignPlayerMovement.get_current_node_id() == "", "Runtime cleared")

	# Restore
	var load_success := SaveGameIO.load_run()
	_check(load_success, "SaveGameIO.load_run succeeded")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_frontier_city", "Restored authoritative player_node_id")
	_check(CampaignNodeRegistry.has_node("node_frontier_safehouse"), "Restored safehouse node")
	_check(CampaignNodeRegistry.has_node("node_frontier_city"), "Restored city node")
	_check(CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id("node_frontier_safehouse", "node_frontier_city")), "Restored route safehouse<->city")

	# Test legacy fallback restore without player_node_id
	var legacy_dict := {
		"schema_version": 1,
		"sector": 1,
		"position": {"x": 1, "y": 1},
		"nodes": CampaignNodeRegistry.serialize()
	}
	GlobalData.current_campaign_player_node_id = ""
	SaveGameIO.restore_from_dict(legacy_dict)
	_check(GlobalData.current_campaign_player_node_id == "node_frontier_safehouse", "Legacy save tile (1,1) recovered node node_frontier_safehouse")


func _test_campaign_force_movement_and_turn_executive_integrity() -> void:
	print("\n--- Test 10: Campaign Force Movement & Turn Executive Contracts Intact ---")
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.set_authored_topology(true)
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse", "node_base")
	CampaignNodeRegistry.register_node(1, Vector2i(20, 20), "enemy_base", "node_target")
	CampaignNodeRegistry.register_route("node_base", "node_target")

	CampaignForce.clear()
	CampaignForce.register_force("force_test", "PATROL", "zeon", "node_base", "", 2, 20)

	var force_move_res := CampaignForceMovement.move_force("force_test", "node_target")
	_check(bool(force_move_res.get("ok", false)), "Force successfully moved across strategic route")
	_check(CampaignForce.get_force("force_test").get("node_id", "") == "node_target", "Force location updated to node_target")
