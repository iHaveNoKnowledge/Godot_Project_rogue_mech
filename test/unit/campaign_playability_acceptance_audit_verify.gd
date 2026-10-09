class_name CampaignPlayabilityAcceptanceAuditVerify
extends Control

## =============================================================================
## CAMPAIGN PLAYABILITY ACCEPTANCE AUDIT VERIFICATION (Phase C2.8)
## =============================================================================
## Validates end-to-end runtime integration, player flow, scene transitions,
## contextual action dispatching, and state continuity for the Strategic Node Map.
## =============================================================================

const CampaignNodeMapScene = preload("res://scenes/ui/campaign_node_map.tscn")
const CampaignScenarioInitializer = preload("res://scripts/systems/campaign_scenario_initializer.gd")
const RunStartSystem = preload("res://scripts/systems/run_start_system.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const FactionSystem = preload("res://scripts/systems/faction_system.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("\n======================================================================")
	print("--- BEGIN CAMPAIGN PLAYABILITY ACCEPTANCE AUDIT (Phase C2.8) ---")
	print("======================================================================")

	_run_all_audits()

	print("\n----------------------------------------------------------------------")
	print("PHASE C2.8 ACCEPTANCE AUDIT SUMMARY: Passed: %d, Failed: %d" % [_pass_count, _fail_count])
	print("----------------------------------------------------------------------")

	if _fail_count == 0:
		print("ALL PLAYABILITY ACCEPTANCE AUDIT (C2.8) CHECKS PASSED!\n")
	else:
		printerr("PLAYABILITY ACCEPTANCE AUDIT (C2.8) CHECKS FAILED with %d errors!\n" % _fail_count)

	await get_tree().process_frame
	get_tree().quit(0 if _fail_count == 0 else 1)


func _run_all_audits() -> void:
	# Audit 1: Main Menu -> Start Campaign Flow & Scenario Population
	_audit_main_menu_to_campaign_initialization()

	# Audit 2: Strategic Node Map Real Scene Playability & Interaction
	_audit_node_map_playability_and_interaction()

	# Audit 3: Strategic Route-Hop Travel & Rejection Safety
	_audit_strategic_travel_flow()

	# Audit 4: Contextual Action Dispatching Matrix
	_audit_action_dispatch_matrix()

	# Audit 5: Scene Transition & State Continuity (Hangar & Save/Load)
	_audit_scene_transitions_and_continuity()

	# Audit 6: Lifecycle Isolation & Repeated Openings
	_audit_repeated_lifecycle_isolation()


# -----------------------------------------------------------------------------
# AUDIT 1: MAIN MENU -> START CAMPAIGN FLOW
# -----------------------------------------------------------------------------
func _audit_main_menu_to_campaign_initialization() -> void:
	print("\n--- Audit 1: Main Menu -> Start Campaign Flow ---")
	_reset_global_campaign_state()

	# Simulate Main Menu 'CAMPAIGN // STRATEGIC MAP' click
	var init_res: Dictionary = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_assert_true(bool(init_res.get("ok", false)), "RunStartSystem.start_campaign_scenario succeeded")
	_assert_eq(GlobalData.current_campaign_scenario_id, "frontier_skirmish", "Scenario ID set to frontier_skirmish")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_safehouse", "Player positioned at authored starting node_frontier_safehouse")

	# Verify Strategic Nodes
	var nodes: Array = CampaignNodeRegistry.get_nodes()
	_assert_eq(nodes.size(), 4, "Canonical scenario registered exactly 4 nodes")

	# Verify Factions & Relationships
	_assert_eq(FactionSystem.get_relation("federation", "zeon"), FactionSystem.Relation.HOSTILE, "Federation vs Zeon is Hostile")
	_assert_eq(FactionSystem.get_relation("federation", "outland"), FactionSystem.Relation.NEUTRAL, "Federation vs Outland is Neutral")

	# Instantiate Campaign Node Map Scene
	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	_assert_not_null(node_map, "CampaignNodeMap instantiates cleanly from scene file")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_safehouse", "Auto-selects player's current node on start")
	node_map.queue_free()


# -----------------------------------------------------------------------------
# AUDIT 2: STRATEGIC NODE MAP PLAYABILITY & INTERACTION
# -----------------------------------------------------------------------------
func _audit_node_map_playability_and_interaction() -> void:
	print("\n--- Audit 2: Strategic Node Map Playability & Interaction ---")
	_reset_global_campaign_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)

	# Verify Player Node Display & Initial Reachability
	_assert_eq(node_map.get_current_player_node_id(), "node_frontier_safehouse", "Current player node is safehouse")
	_assert_false(node_map.is_node_reachable("node_frontier_safehouse"), "Safehouse is current node, not reachable destination")
	_assert_true(node_map.is_node_reachable("node_frontier_city"), "City is 1-hop connected and reachable")
	_assert_false(node_map.is_node_reachable("node_frontier_depot"), "Depot is 2-hops away and unreachable")
	_assert_false(node_map.is_node_reachable("node_frontier_outpost"), "Outpost is 3-hops away and unreachable")

	# Select different nodes (selection without movement)
	node_map.select_node("node_frontier_city")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_city", "Selection updated to city")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_safehouse", "Player position remains at safehouse after selecting city")

	node_map.select_node("node_frontier_depot")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_depot", "Selection updated to depot")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_safehouse", "Player position remains at safehouse after selecting depot")

	# Inspection Data Verification
	var inspect_data: Dictionary = CampaignNodeInspection.inspect_node("node_frontier_city")
	var node_info: Dictionary = inspect_data.get("node", {})
	_assert_eq(str(node_info.get("id", "")), "node_frontier_city", "Node inspection matches selected node")
	_assert_eq(str(node_info.get("node_type", "")).to_upper(), "CITY", "Node type is CITY")

	node_map.queue_free()


# -----------------------------------------------------------------------------
# AUDIT 3: STRATEGIC ROUTE-HOP TRAVEL & REJECTION SAFETY
# -----------------------------------------------------------------------------
func _audit_strategic_travel_flow() -> void:
	print("\n--- Audit 3: Strategic Route-Hop Travel & Rejection Safety ---")
	_reset_global_campaign_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)

	# 1. Travel to connected node
	var travel_receipt: Dictionary = node_map.travel_to_node("node_frontier_city")
	_assert_true(bool(travel_receipt.get("ok", false)), "Strategic travel to connected city succeeded")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_city", "Authoritative player node is node_frontier_city")
	_assert_eq(node_map.get_selected_node_id(), "node_frontier_city", "Map selection updated to destination")

	# Reachability updated reactively from city
	_assert_true(node_map.is_node_reachable("node_frontier_safehouse"), "From city: safehouse is reachable")
	_assert_true(node_map.is_node_reachable("node_frontier_depot"), "From city: depot is reachable")
	_assert_false(node_map.is_node_reachable("node_frontier_outpost"), "From city: outpost is 2 hops away, unreachable")

	# 2. Travel to unreachable node rejected atomically
	var unreach_receipt: Dictionary = node_map.travel_to_node("node_frontier_outpost")
	_assert_false(bool(unreach_receipt.get("ok", true)), "Travel to 2-hop unreachable outpost rejected")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_city", "Player position untouched after unreachable move")

	# 3. Travel to self rejected
	var self_receipt: Dictionary = node_map.travel_to_node("node_frontier_city")
	_assert_false(bool(self_receipt.get("ok", true)), "Travel to self rejected")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_city", "Player position untouched after self travel")

	# 4. Turn Authority Invariance
	var turn_before: int = CampaignTurnExecutive.get_turn()
	var turn_receipt: Dictionary = node_map.advance_turn()
	_assert_true(bool(turn_receipt.get("ok", false)), "Explicit advance_turn succeeded")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before + 1, "Turn advanced by exactly 1")

	node_map.queue_free()


# -----------------------------------------------------------------------------
# AUDIT 4: CONTEXTUAL ACTION DISPATCHING MATRIX
# -----------------------------------------------------------------------------
func _audit_action_dispatch_matrix() -> void:
	print("\n--- Audit 4: Contextual Action Dispatching Matrix ---")
	_reset_global_campaign_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)

	# Action 1: Investigate at Safehouse (Player is present)
	var inv_safe: Dictionary = node_map.dispatch_node_action("investigate")
	_assert_true(bool(inv_safe.get("ok", false)), "Investigate succeeded at current safehouse node")
	_assert_eq(str(inv_safe.get("reason", "")), "investigation_resolved", "Investigation resolved")

	# Action 2: Investigate when remote (Select city, but player at safehouse)
	node_map.select_node("node_frontier_city")
	var inv_remote: Dictionary = node_map.dispatch_node_action("investigate")
	_assert_false(bool(inv_remote.get("ok", true)), "Investigate rejected when player is remote")
	_assert_eq(str(inv_remote.get("reason", "")), "player_not_at_node", "Rejection reason is player_not_at_node")

	# Travel to city
	node_map.travel_to_node("node_frontier_city")

	# Action 3: Resupply at City
	var resupply_res: Dictionary = node_map.dispatch_node_action("resupply")
	_assert_true(bool(resupply_res.get("ok", false)), "Resupply action executed at city")

	# Action 4: Trade at City
	var trade_res: Dictionary = node_map.dispatch_node_action("trade", { "operation": "buy", "item_id": "fuel_canister", "quantity": 1 })
	# Trade should be validated by trade action capability
	_assert_not_null(trade_res, "Trade action dispatched and returned result dictionary")

	node_map.queue_free()


# -----------------------------------------------------------------------------
# AUDIT 5: SCENE TRANSITIONS & CONTINUITY
# -----------------------------------------------------------------------------
func _audit_scene_transitions_and_continuity() -> void:
	print("\n--- Audit 5: Scene Transitions & Continuity ---")
	_reset_global_campaign_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Move player to city
	CampaignPlayerMovement.move_player_to_node("node_frontier_city")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), "node_frontier_city", "Player moved to city")

	# Save run
	var save_ok := GlobalData.save_run()
	_assert_true(save_ok, "GlobalData.save_run succeeded")

	# Clear runtime state
	CampaignNodeRegistry.clear()
	GlobalData.current_campaign_player_node_id = ""

	# Load run
	var load_ok := GlobalData.load_run()
	_assert_true(load_ok, "GlobalData.load_run succeeded")
	_assert_eq(GlobalData.current_campaign_player_node_id, "node_frontier_city", "Restored player position to node_frontier_city")
	_assert_true(CampaignNodeRegistry.has_node("node_frontier_city"), "Topology retained node_frontier_city")
	_assert_true(CampaignNodeRegistry.has_node("node_frontier_safehouse"), "Topology retained node_frontier_safehouse")

	# Test GameManager return_to_board in Campaign Mode
	# Suppress actual viewport scene swap in test harness
	GameManager.suppress_scene_change = true
	GameManager.return_to_board()
	_assert_eq(GameManager.current_state, GameManager.State.BOARD, "GameManager transitioned to BOARD state")
	GameManager.suppress_scene_change = false


# -----------------------------------------------------------------------------
# AUDIT 6: LIFECYCLE ISOLATION & REPEATED OPENINGS
# -----------------------------------------------------------------------------
func _audit_repeated_lifecycle_isolation() -> void:
	print("\n--- Audit 6: Lifecycle Isolation & Repeated Openings ---")
	_reset_global_campaign_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Open instance 1
	var map1 = CampaignNodeMapScene.instantiate()
	add_child(map1)
	map1.select_node("node_frontier_city")
	map1.queue_free()

	# Open instance 2
	var map2 = CampaignNodeMapScene.instantiate()
	add_child(map2)
	_assert_eq(map2.get_selected_node_id(), "node_frontier_safehouse", "Fresh instance auto-selects player node, not stale selection")
	_assert_eq(CampaignNodeRegistry.get_nodes().size(), 4, "Zero node duplication across repeated scene instantiations")
	map2.queue_free()


# -----------------------------------------------------------------------------
# TEST HARNESS UTILITIES
# -----------------------------------------------------------------------------
func _reset_global_campaign_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignTurnExecutive.reset()
	GlobalData.current_campaign_player_node_id = ""
	GlobalData.current_campaign_scenario_id = ""
	GlobalData.current_campaign_faction_id = "federation"


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("AUDIT_C28 OK: %s" % msg)
	else:
		_fail_count += 1
		printerr("AUDIT_C28 FAIL: %s" % msg)


func _assert_false(cond: bool, msg: String) -> void:
	_assert_true(not cond, msg)


func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("AUDIT_C28 OK: %s (got %s)" % [msg, str(actual)])
	else:
		_fail_count += 1
		printerr("AUDIT_C28 FAIL: %s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func _assert_not_null(val, msg: String) -> void:
	_assert_true(val != null, msg)
