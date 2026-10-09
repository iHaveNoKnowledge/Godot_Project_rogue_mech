extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC NODE MAP UI & NAVIGATION VERIFICATION — Phase C2.7
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
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const FactionSystem = preload("res://scripts/systems/faction_system.gd")
const CampaignBattle = preload("res://scripts/systems/campaign_battle.gd")
const CampaignNodeMapScript = preload("res://scripts/ui/campaign_node_map.gd")
const CampaignNodeMapScene = preload("res://scenes/ui/campaign_node_map.tscn")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup: String = ""


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN STRATEGIC NODE MAP UI VERIFY (Phase C2.7) ---")
	print("======================================================================")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.close()


func _assert_true(condition: bool, message: String) -> void:
	_total_assertions += 1
	if condition:
		_passed_assertions += 1
		print("CAMPAIGN_C27 OK: %s" % message)
	else:
		_failed_assertions += 1
		printerr("CAMPAIGN_C27 FAIL: %s" % message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_true(not condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_total_assertions += 1
	if actual == expected:
		_passed_assertions += 1
		print("CAMPAIGN_C27 OK: %s" % message)
	else:
		_failed_assertions += 1
		printerr("CAMPAIGN_C27 FAIL: %s | Expected: %s, Got: %s" % [message, str(expected), str(actual)])


func _setup_canonical_frontier_environment() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()

	if GlobalData != null:
		GlobalData.current_campaign_id = ""
		GlobalData.current_campaign_scenario_id = ""
		GlobalData.current_campaign_faction_id = ""
		GlobalData.current_campaign_player_node_id = ""
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(1, 1)
			GlobalData.board.board_mp = 100
		if GlobalData.currency != null:
			GlobalData.currency.credits = 1000
			GlobalData.currency.scrap = 100
			GlobalData.currency.data_cores = 5
		if GlobalData.fuel != null:
			GlobalData.fuel.convoy_fuel = 50.0
			GlobalData.fuel.convoy_max_fuel = 80.0
		if GlobalData.weapons != null:
			GlobalData.weapons._ensure_default_frames()

	var res := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	if not res.get("ok", false):
		printerr("FATAL: Failed to start canonical scenario frontier_skirmish: %s" % str(res))


func _run_all_tests() -> void:
	# Test 1: Scene Loading & Instantiation
	print("\n--- Test 1: Scene Loading & Instantiation ---")
	_setup_canonical_frontier_environment()
	var instance = CampaignNodeMapScene.instantiate()
	_assert_true(instance != null, "CampaignNodeMap scene instantiates cleanly")
	_assert_true(instance is Control, "CampaignNodeMap is a Control node")
	add_child(instance)
	_assert_true(instance.is_inside_tree(), "CampaignNodeMap enters scene tree without error")
	instance.queue_free()

	# Test 2: Node & Route Rendering Parity
	print("\n--- Test 2: Node & Route Rendering Parity ---")
	_setup_canonical_frontier_environment()
	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	var rendered_nodes: Array = node_map.get_rendered_nodes()
	var registered_nodes: Array = CampaignNodeRegistry.get_nodes()
	_assert_eq(rendered_nodes.size(), registered_nodes.size(), "Rendered nodes count matches registered nodes (4)")
	for n in registered_nodes:
		var nid := str(n.get("id", ""))
		_assert_true(rendered_nodes.has(nid), "Rendered nodes includes registered node %s" % nid)
	var rendered_routes: Array = node_map.get_rendered_routes()
	_assert_eq(rendered_routes.size(), 3, "Rendered routes count matches canonical scenario routes (3)")
	node_map.queue_free()

	# Test 3: Layout Coordinates & Fallback
	print("\n--- Test 3: Layout Coordinates & Fallback ---")
	_setup_canonical_frontier_environment()
	var safehouse: Dictionary = CampaignNodeRegistry.get_node("node_frontier_safehouse")
	var city: Dictionary = CampaignNodeRegistry.get_node("node_frontier_city")
	_assert_eq(safehouse.get("map_position", Vector2.ZERO), Vector2(100, 200), "Safehouse has authored map_position (100, 200)")
	_assert_eq(city.get("map_position", Vector2.ZERO), Vector2(300, 200), "City has authored map_position (300, 200)")
	var fallback_pos_0: Vector2 = CampaignNodeMapScript.calculate_fallback_position(0, 4, 1)
	var fallback_pos_1: Vector2 = CampaignNodeMapScript.calculate_fallback_position(1, 4, 1)
	var fallback_pos_2: Vector2 = CampaignNodeMapScript.calculate_fallback_position(2, 4, 1)
	_assert_true(fallback_pos_0 != fallback_pos_1, "Fallback positions are distinct for index 0 and 1")
	_assert_true(fallback_pos_1 != fallback_pos_2, "Fallback positions are distinct for index 1 and 2")
	_assert_true(fallback_pos_0.x > 0 and fallback_pos_0.y > 0, "Fallback position has positive coordinates")

	# Test 4: Player Location & Reachability
	print("\n--- Test 4: Player Location & Reachability ---")
	_setup_canonical_frontier_environment()
	var current_node := CampaignPlayerMovement.get_current_node_id()
	_assert_eq(current_node, "node_frontier_safehouse", "Player starts at node_frontier_safehouse")
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	_assert_false(node_map.is_node_reachable("node_frontier_safehouse"), "Current node is not marked as reachable destination")
	_assert_true(node_map.is_node_reachable("node_frontier_city"), "Connected node_frontier_city is reachable (1 hop)")
	_assert_false(node_map.is_node_reachable("node_frontier_depot"), "Two-hop node_frontier_depot is unreachable for 1-hop travel")
	_assert_false(node_map.is_node_reachable("node_frontier_outpost"), "Three-hop node_frontier_outpost is unreachable for 1-hop travel")
	node_map.queue_free()

	# Test 5: Selection Invariance
	print("\n--- Test 5: Selection Invariance ---")
	_setup_canonical_frontier_environment()
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	var initial_player_node := CampaignPlayerMovement.get_current_node_id()
	node_map.select_node("node_frontier_city")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_city", "Selected node updated to city")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), initial_player_node, "Player position unchanged after selecting city")
	node_map.select_node("node_frontier_outpost")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_outpost", "Selected node updated to outpost")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), initial_player_node, "Player position unchanged after selecting outpost")
	node_map.queue_free()

	# Test 6: Strategic Travel Execution
	print("\n--- Test 6: Strategic Travel Execution ---")
	_setup_canonical_frontier_environment()
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	var travel_receipt: Dictionary = node_map.travel_to_node("node_frontier_city")
	_assert_true(bool(travel_receipt.get("ok", false)), "Travel to connected node_frontier_city succeeded")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_city", "Authoritative player node is now node_frontier_city")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_city", "Node Map selection updated to node_frontier_city")
	_assert_true(node_map.is_node_reachable("node_frontier_safehouse"), "From city: safehouse is now reachable")
	_assert_true(node_map.is_node_reachable("node_frontier_depot"), "From city: depot is now reachable")
	_assert_false(node_map.is_node_reachable("node_frontier_city"), "From city: city is current, not reachable destination")
	_assert_false(node_map.is_node_reachable("node_frontier_outpost"), "From city: outpost is 2 hops away, unreachable")
	node_map.queue_free()

	# Test 7: Travel Rejections & Safety
	print("\n--- Test 7: Travel Rejections & Safety ---")
	_setup_canonical_frontier_environment()
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	var unreach_res: Dictionary = node_map.travel_to_node("node_frontier_depot")
	_assert_false(bool(unreach_res.get("ok", true)), "Travel to disconnected depot rejected")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_safehouse", "Player position unchanged after rejected travel")
	var unknown_res: Dictionary = node_map.travel_to_node("node_nonexistent_xyz")
	_assert_false(bool(unknown_res.get("ok", true)), "Travel to unknown node rejected")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_safehouse", "Player position unchanged after unknown node travel")
	var self_res: Dictionary = node_map.travel_to_node("node_frontier_safehouse")
	_assert_false(bool(self_res.get("ok", true)), "Travel to self rejected")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_safehouse", "Player position unchanged after self travel")
	node_map.queue_free()

	# Test 8: Zero Tactical Grid Interference
	print("\n--- Test 8: Zero Tactical Grid Interference ---")
	_setup_canonical_frontier_environment()
	var initial_mp: int = GlobalData.board.board_mp
	var initial_fuel: float = GlobalData.fuel.convoy_fuel
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.travel_to_node("node_frontier_city")
	_assert_eq(GlobalData.board.board_mp, initial_mp, "Board MP unchanged during strategic node movement (zero tactical tile cost)")
	_assert_eq(GlobalData.fuel.convoy_fuel, initial_fuel, "Convoy fuel unchanged during strategic node movement")
	node_map.queue_free()

	# Test 9: Turn Authority Zero Leakage
	print("\n--- Test 9: Turn Authority Zero Leakage ---")
	_setup_canonical_frontier_environment()
	var turn_before: int = CampaignTurnExecutive.get_turn()
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.travel_to_node("node_frontier_city")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "Campaign turn unchanged after strategic travel")
	node_map.dispatch_node_action("investigate")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "Campaign turn unchanged after investigate action")
	var turn_res: Dictionary = node_map.advance_turn()
	_assert_true(bool(turn_res.get("ok", false)), "Explicit advance_turn succeeded")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before + 1, "Campaign turn advanced by exactly 1")
	node_map.queue_free()

	# Test 10: Node Situation Inspection & Dispatch
	print("\n--- Test 10: Node Situation Inspection & Dispatch ---")
	_setup_canonical_frontier_environment()
	node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	node_map.travel_to_node("node_frontier_city")
	var inv_res: Dictionary = node_map.dispatch_node_action("investigate")
	_assert_true(bool(inv_res.get("ok", false)), "Investigate action succeeded at current node (city)")
	_assert_eq(str(inv_res.get("reason", "")), "investigation_resolved", "Investigate reason is investigation_resolved")
	node_map.select_node("node_frontier_safehouse")
	var remote_action_res: Dictionary = node_map.dispatch_node_action("investigate")
	_assert_false(bool(remote_action_res.get("ok", true)), "Action rejected when player is not present at target node")
	_assert_eq(str(remote_action_res.get("reason", "")), "player_not_at_node", "Rejection reason is player_not_at_node")
	node_map.queue_free()

	# Test 11: Authored Topology Survival
	print("\n--- Test 11: Authored Topology Survival ---")
	_setup_canonical_frontier_environment()
	_assert_true(CampaignNodeRegistry.is_authored_topology(), "Scenario initialization set authored topology mode")
	CampaignNodeRegistry.rebuild_from_tile_types({ Vector2i(3, 3): "safehouse", Vector2i(3, 4): "city" }, 1)
	_assert_true(CampaignNodeRegistry.has_node("node_frontier_city"), "Authored city node survived board tile generation")
	_assert_true(CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id("node_frontier_safehouse", "node_frontier_city")), "Authored route survived board tile generation")
	_assert_eq(CampaignNodeRegistry.get_nodes().size(), 4, "Authored node count preserved (4)")

	# Test 12: Save/Load Roundtrip
	print("\n--- Test 12: Save/Load Roundtrip ---")
	_setup_canonical_frontier_environment()
	CampaignPlayerMovement.set_current_node_id("node_frontier_city")
	var saved_node: String = CampaignPlayerMovement.get_current_node_id()
	_assert_eq(saved_node, "node_frontier_city", "Player node is city before save")
	var save_ok: bool = SaveGameIO.save_run()
	_assert_true(save_ok, "SaveGameIO.save_run succeeded")
	CampaignPlayerMovement.set_current_node_id("")
	SaveGameIO.load_run()
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_city", "Player node restored to node_frontier_city")
	_assert_true(CampaignNodeRegistry.has_node("node_frontier_city"), "Restored topology retains node_frontier_city")
	_assert_true(CampaignNodeRegistry.has_route(CampaignNodeRegistry.make_route_id("node_frontier_city", "node_frontier_depot")), "Restored topology retains route city <-> depot")

	# Test 13: Instance Isolation & Lifecycle
	print("\n--- Test 13: Instance Isolation & Lifecycle ---")
	_setup_canonical_frontier_environment()
	var map1 = CampaignNodeMapScene.instantiate()
	add_child(map1)
	map1.select_node("node_frontier_depot")
	_assert_eq(map1.get_selected_node_id(), "node_frontier_depot", "Map1 selected depot")
	map1.queue_free()
	var map2 = CampaignNodeMapScene.instantiate()
	add_child(map2)
	_assert_eq(map2.get_selected_node_id(), "node_frontier_safehouse", "Fresh Map2 auto-selects player node (no stale selection from Map1)")
	map2.queue_free()

	# Test 14: Campaign Authorities Continuity
	print("\n--- Test 14: Campaign Authorities Continuity ---")
	_setup_canonical_frontier_environment()
	var force_id := "force_s1_fed_vanguard"
	_assert_true(CampaignForce.has_force(force_id), "Canonical force force_s1_fed_vanguard exists at node_frontier_city")
	var force_move_res: Dictionary = CampaignForceMovement.move_force(force_id, "node_frontier_depot")
	_assert_true(bool(force_move_res.get("ok", false)), "Strategic force movement across route city <-> depot succeeds")
	var force_data: Dictionary = CampaignForce.get_force(force_id)
	_assert_eq(str(force_data.get("node_id", "")), "node_frontier_depot", "Force location updated to node_frontier_depot")
	_assert_eq(FactionSystem.get_relation("federation", "zeon"), FactionSystem.Relation.HOSTILE, "Federation vs Zeon is HOSTILE")
	_assert_eq(FactionSystem.get_relation("federation", "outland"), FactionSystem.Relation.NEUTRAL, "Federation vs Outland is NEUTRAL")


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE C2.7 SUMMARY: Passed: %d, Failed: %d" % [_passed_assertions, _failed_assertions])
	print("----------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("ALL STRATEGIC NODE MAP UI (C2.7) CHECKS PASSED!")
		get_tree().quit(0)
	else:
		printerr("PHASE C2.7 FAILED with %d errors." % _failed_assertions)
		get_tree().quit(1)
