class_name CampaignNodeActionCapabilityContractVerify
extends Node

## ---------------------------------------------------------------------------
## 5AS — CAMPAIGN NODE ACTION CAPABILITY / CONTEXT CONTRACT VERIFICATION
##
## Verifies:
##   TEST 1: Action Recognition vs Action Availability vs Action Execution separation.
##   TEST 2: Authoritative node capability matrix across all strategic node types.
##   TEST 3: Valid context execution for investigate, resupply, trade.
##   TEST 4: Invalid context rejection with exact domain reason codes.
##   TEST 5: Full mutation snapshot invariance on invalid context (Zero Partial Mutation).
##   TEST 6: Location authority integrity (actions never shift player position).
##   TEST 7: Campaign turn integrity (Zero turn advancement across all actions/failures).
##   TEST 8: Multi-action coexistence and sequence isolation.
##   TEST 9: Future action compatibility boundary (capture, attack, defend routing).
## ---------------------------------------------------------------------------

const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0


func _ready() -> void:
	print("--- BEGIN CAMPAIGN NODE ACTION CAPABILITY CONTRACT VERIFY (Phase 5AS) ---")
	_run_all_tests()
	_print_summary()


func _assert_true(condition: bool, message: String) -> void:
	_total_assertions += 1
	if condition:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: " + message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_true(not condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_total_assertions += 1
	if actual == expected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: %s | Expected: %s, Got: %s" % [message, str(expected), str(actual)])


func _run_all_tests() -> void:
	_test_action_recognition_boundary()
	_test_node_capability_matrix()
	_test_valid_context_executions()
	_test_invalid_context_rejections()
	_test_invalid_context_snapshot_invariance()
	_test_location_authority_integrity()
	_test_turn_authority_zero_leakage()
	_test_multi_action_coexistence_and_isolation()
	_test_future_actions_boundary()


func _setup_clean_campaign_environment() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()

	if GlobalData != null:
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(0, 0)
		if GlobalData.currency != null:
			GlobalData.currency.credits = 1000
			GlobalData.currency.scrap = 100
			GlobalData.currency.data_cores = 5
		if GlobalData.fuel != null:
			GlobalData.fuel.mech_energy = 50.0
			GlobalData.fuel.mech_max_energy = 100.0
			GlobalData.fuel.convoy_fuel = 40.0
			GlobalData.fuel.convoy_max_fuel = 80.0
		GlobalData.fuel_inventory.clear()
		GlobalData.fuel_inventory["fuel_canister"] = 5


func _take_state_snapshot() -> Dictionary:
	var snap := {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"data_cores": GlobalData.currency.data_cores if GlobalData and GlobalData.currency else 0,
		"fuel_inventory": GlobalData.fuel_inventory.duplicate(true) if GlobalData else {},
		"mech_energy": GlobalData.fuel.mech_energy if GlobalData and GlobalData.fuel else 0.0,
		"convoy_fuel": GlobalData.fuel.convoy_fuel if GlobalData and GlobalData.fuel else 0.0,
		"current_tile": GlobalData.board.current_tile if GlobalData and GlobalData.board else Vector2i(-1, -1),
		"current_sector": GlobalData.board.current_sector if GlobalData and GlobalData.board else -1,
		"turn": CampaignTurnExecutive.get_turn(),
		"node_count": CampaignNodeRegistry.get_nodes().size(),
		"territory_count": CampaignTerritory.get_territories().size(),
		"base_count": CampaignBase.get_bases().size(),
		"force_count": CampaignForce.get_forces().size(),
		"battle_count": CampaignBattle.get_battles().size(),
	}
	return snap


# ---------------------------------------------------------------------------
# TEST 1: Action Recognition Boundary
# ---------------------------------------------------------------------------
func _test_action_recognition_boundary() -> void:
	_setup_clean_campaign_environment()

	_assert_true(CampaignPlayerDispatch.is_known_action("investigate"), "T1: investigate recognized")
	_assert_true(CampaignPlayerDispatch.is_known_action("resupply"), "T1: resupply recognized")
	_assert_true(CampaignPlayerDispatch.is_known_action("trade"), "T1: trade recognized")
	_assert_true(CampaignPlayerDispatch.is_known_action("attack"), "T1: attack recognized in core list")
	_assert_true(CampaignPlayerDispatch.is_known_action("defend"), "T1: defend recognized in core list")
	_assert_true(CampaignPlayerDispatch.is_known_action("capture"), "T1: capture recognized in core list")

	_assert_false(CampaignPlayerDispatch.is_known_action("unknown_action_xyz"), "T1: bogus action not recognized")
	_assert_false(CampaignPlayerDispatch.is_known_action(""), "T1: empty action not recognized")


# ---------------------------------------------------------------------------
# TEST 2: Node Capability Matrix
# ---------------------------------------------------------------------------
func _test_node_capability_matrix() -> void:
	_setup_clean_campaign_environment()

	# Resupply node type checks
	_assert_true(CampaignResupplyAction.is_resupply_node_type("START"), "T2: START can resupply")
	_assert_true(CampaignResupplyAction.is_resupply_node_type("SAFEHOUSE"), "T2: SAFEHOUSE can resupply")
	_assert_true(CampaignResupplyAction.is_resupply_node_type("CITY"), "T2: CITY can resupply")
	_assert_true(CampaignResupplyAction.is_resupply_node_type("FUEL_DEPOT"), "T2: FUEL_DEPOT can resupply")
	_assert_true(CampaignResupplyAction.is_resupply_node_type("SUPPLY_DEPOT"), "T2: SUPPLY_DEPOT can resupply")

	_assert_false(CampaignResupplyAction.is_resupply_node_type("ENEMY_BASE"), "T2: ENEMY_BASE cannot resupply")
	_assert_false(CampaignResupplyAction.is_resupply_node_type("RESEARCH_LAB"), "T2: RESEARCH_LAB cannot resupply")
	_assert_false(CampaignResupplyAction.is_resupply_node_type("DATA_NODE"), "T2: DATA_NODE cannot resupply")
	_assert_false(CampaignResupplyAction.is_resupply_node_type("COMMS_RELAY"), "T2: COMMS_RELAY cannot resupply")
	_assert_false(CampaignResupplyAction.is_resupply_node_type("PROTOTYPE_VAULT"), "T2: PROTOTYPE_VAULT cannot resupply")
	_assert_false(CampaignResupplyAction.is_resupply_node_type("SALVAGE_CACHE"), "T2: SALVAGE_CACHE cannot resupply")
	_assert_false(CampaignResupplyAction.is_resupply_node_type("EXIT"), "T2: EXIT cannot resupply")

	# Trade node type checks
	_assert_true(CampaignTradeAction.is_trade_node_type("START"), "T2: START can trade")
	_assert_true(CampaignTradeAction.is_trade_node_type("SAFEHOUSE"), "T2: SAFEHOUSE can trade")
	_assert_true(CampaignTradeAction.is_trade_node_type("CITY"), "T2: CITY can trade")
	_assert_true(CampaignTradeAction.is_trade_node_type("SUPPLY_DEPOT"), "T2: SUPPLY_DEPOT can trade")

	_assert_false(CampaignTradeAction.is_trade_node_type("FUEL_DEPOT"), "T2: FUEL_DEPOT cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("ENEMY_BASE"), "T2: ENEMY_BASE cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("RESEARCH_LAB"), "T2: RESEARCH_LAB cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("DATA_NODE"), "T2: DATA_NODE cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("COMMS_RELAY"), "T2: COMMS_RELAY cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("PROTOTYPE_VAULT"), "T2: PROTOTYPE_VAULT cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("SALVAGE_CACHE"), "T2: SALVAGE_CACHE cannot trade")
	_assert_false(CampaignTradeAction.is_trade_node_type("EXIT"), "T2: EXIT cannot trade")


# ---------------------------------------------------------------------------
# TEST 3: Valid Context Executions
# ---------------------------------------------------------------------------
func _test_valid_context_executions() -> void:
	_setup_clean_campaign_environment()

	# Register a city node at (0, 0)
	var city_nid := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "city")
	GlobalData.board.current_tile = Vector2i(0, 0)

	# 1. Investigate city
	var inv_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", city_nid))
	_assert_true(bool(inv_res.get("ok", false)), "T3: Investigate at CITY succeeds")
	_assert_eq(str(inv_res.get("reason", "")), "investigation_resolved", "T3: Investigate reason correct")

	# 2. Trade at city (buy fuel_canister)
	var trade_intent := CampaignPlayerDispatch.create_intent("trade", city_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	})
	var trade_res := CampaignPlayerDispatch.dispatch_intent(trade_intent)
	_assert_true(bool(trade_res.get("ok", false)), "T3: Trade buy at CITY succeeds")
	_assert_eq(str(trade_res.get("reason", "")), "trade_completed", "T3: Trade reason correct")

	# 3. Resupply at city
	var resupply_intent := CampaignPlayerDispatch.create_intent("resupply", city_nid)
	var resupply_res := CampaignPlayerDispatch.dispatch_intent(resupply_intent)
	_assert_true(bool(resupply_res.get("ok", false)), "T3: Resupply at CITY succeeds")
	_assert_eq(str(resupply_res.get("reason", "")), "resupply_completed", "T3: Resupply reason correct")


# ---------------------------------------------------------------------------
# TEST 4: Invalid Context Rejections
# ---------------------------------------------------------------------------
func _test_invalid_context_rejections() -> void:
	_setup_clean_campaign_environment()

	var enemy_base_nid := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "enemy_base")
	var fuel_depot_nid := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "fuel_depot")

	# Player is at fuel_depot (2, 2)
	GlobalData.board.current_tile = Vector2i(2, 2)

	# Try trade at FUEL_DEPOT (not trade capable)
	var trade_fuel_depot := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", fuel_depot_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_false(bool(trade_fuel_depot.get("ok", false)), "T4: Trade at FUEL_DEPOT rejected")
	_assert_eq(str(trade_fuel_depot.get("reason", "")), "node_cannot_trade", "T4: Rejection reason node_cannot_trade")

	# Move player to enemy_base (5, 5)
	GlobalData.board.current_tile = Vector2i(5, 5)

	# Try resupply at ENEMY_BASE (not resupply capable)
	var resupply_enemy_base := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", enemy_base_nid))
	_assert_false(bool(resupply_enemy_base.get("ok", false)), "T4: Resupply at ENEMY_BASE rejected")
	_assert_eq(str(resupply_enemy_base.get("reason", "")), "node_cannot_resupply", "T4: Rejection reason node_cannot_resupply")

	# Try trade at ENEMY_BASE (not trade capable)
	var trade_enemy_base := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", enemy_base_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_false(bool(trade_enemy_base.get("ok", false)), "T4: Trade at ENEMY_BASE rejected")
	_assert_eq(str(trade_enemy_base.get("reason", "")), "node_cannot_trade", "T4: Rejection reason node_cannot_trade")

	# Try action at remote node where player is not physically located
	var remote_resupply := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", fuel_depot_nid))
	_assert_false(bool(remote_resupply.get("ok", false)), "T4: Remote action rejected by dispatch")
	_assert_eq(str(remote_resupply.get("reason", "")), "player_not_at_node", "T4: Rejection reason player_not_at_node")


# ---------------------------------------------------------------------------
# TEST 5: Invalid Context Snapshot Invariance (Zero Partial Mutation)
# ---------------------------------------------------------------------------
func _test_invalid_context_snapshot_invariance() -> void:
	_setup_clean_campaign_environment()

	var lab_nid := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "research_lab")
	GlobalData.board.current_tile = Vector2i(3, 3)

	var snap_before := _take_state_snapshot()

	# Attempt invalid resupply at research lab
	var res1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", lab_nid))
	_assert_false(bool(res1.get("ok", false)), "T5: Resupply at lab rejected")

	var snap_after1 := _take_state_snapshot()
	_assert_eq(snap_after1, snap_before, "T5: State unchanged after invalid resupply")

	# Attempt invalid trade at research lab
	var res2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", lab_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_false(bool(res2.get("ok", false)), "T5: Trade at lab rejected")

	var snap_after2 := _take_state_snapshot()
	_assert_eq(snap_after2, snap_before, "T5: State unchanged after invalid trade")

	# Attempt invalid capture (research lab is not capturable)
	var res3 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", lab_nid))
	_assert_false(bool(res3.get("ok", false)), "T5: Invalid capture at lab rejected")
	_assert_eq(str(res3.get("reason", "")), "node_cannot_capture", "T5: Reason node_cannot_capture")

	var snap_after3 := _take_state_snapshot()
	_assert_eq(snap_after3, snap_before, "T5: State unchanged after invalid capture")

	# Attempt invalid attack (research lab has no active hostile target)
	var res4 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", lab_nid))
	_assert_false(bool(res4.get("ok", false)), "T5: Invalid attack at lab rejected")
	_assert_eq(str(res4.get("reason", "")), "no_active_target", "T5: Reason no_active_target")

	var snap_after4 := _take_state_snapshot()
	_assert_eq(snap_after4, snap_before, "T5: State unchanged after invalid attack")

	# Attempt unimplemented action (e.g. defend)
	var res5 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("defend", lab_nid))
	_assert_false(bool(res5.get("ok", false)), "T5: Unimplemented action rejected")
	_assert_eq(str(res5.get("reason", "")), "action_not_implemented", "T5: Reason action_not_implemented")

	var snap_after5 := _take_state_snapshot()
	_assert_eq(snap_after5, snap_before, "T5: State unchanged after unimplemented action")


# ---------------------------------------------------------------------------
# TEST 6: Location Authority Integrity
# ---------------------------------------------------------------------------
func _test_location_authority_integrity() -> void:
	_setup_clean_campaign_environment()

	var city_nid := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city")
	GlobalData.board.current_tile = Vector2i(1, 1)
	GlobalData.board.current_sector = 1

	_assert_eq(CampaignNodeInspection.get_current_player_node_id(), city_nid, "T6: Inspection reports correct current node")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), city_nid, "T6: Movement reports correct current node")

	# Execute investigate
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", city_nid))
	_assert_eq(GlobalData.board.current_tile, Vector2i(1, 1), "T6: Position unchanged after investigate")

	# Execute resupply
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", city_nid))
	_assert_eq(GlobalData.board.current_tile, Vector2i(1, 1), "T6: Position unchanged after resupply")

	# Execute trade
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", city_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_eq(GlobalData.board.current_tile, Vector2i(1, 1), "T6: Position unchanged after trade")


# ---------------------------------------------------------------------------
# TEST 7: Campaign Turn Integrity
# ---------------------------------------------------------------------------
func _test_turn_authority_zero_leakage() -> void:
	_setup_clean_campaign_environment()

	var depot_nid := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "supply_depot")
	GlobalData.board.current_tile = Vector2i(0, 0)

	var turn_start := CampaignTurnExecutive.get_turn()

	# Investigate
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", depot_nid))
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_start, "T7: Turn unchanged after investigate")

	# Resupply
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", depot_nid))
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_start, "T7: Turn unchanged after resupply")

	# Trade
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", depot_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_start, "T7: Turn unchanged after trade")

	# Explicit CampaignTurnExecutive call alone advances turn
	var turn_receipt := CampaignTurnExecutive.advance_campaign_turn("test_world_step", {"day_boundary": false})
	_assert_true(bool(turn_receipt.get("ok", false)), "T7: Explicit turn advance succeeds")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_start + 1, "T7: Turn increments only via TurnExecutive")


# ---------------------------------------------------------------------------
# TEST 8: Multi-Action Coexistence and Sequence Isolation
# ---------------------------------------------------------------------------
func _test_multi_action_coexistence_and_isolation() -> void:
	_setup_clean_campaign_environment()

	var depot_nid := CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "supply_depot")
	GlobalData.board.current_tile = Vector2i(0, 0)

	# Sequence 1: Investigate -> Trade -> Resupply -> Investigate
	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", depot_nid))
	_assert_true(bool(r1.get("ok", false)), "T8: Seq1 Investigate OK")

	var r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", depot_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_true(bool(r2.get("ok", false)), "T8: Seq1 Trade OK")

	var r3 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", depot_nid))
	_assert_true(bool(r3.get("ok", false)), "T8: Seq1 Resupply OK")

	var r4 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", depot_nid))
	_assert_true(bool(r4.get("ok", false)), "T8: Seq1 Final Investigate OK")

	# Sequence 2: Interleaved with failed actions without state contamination
	var r_fail := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", depot_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 999999 # cannot afford
	}))
	_assert_false(bool(r_fail.get("ok", false)), "T8: Excessive trade fails safely")

	var r5 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", depot_nid))
	_assert_true(bool(r5.get("ok", false)), "T8: Investigate succeeds immediately after failed trade")


# ---------------------------------------------------------------------------
# TEST 9: Future Actions Boundary
# ---------------------------------------------------------------------------
func _test_future_actions_boundary() -> void:
	_setup_clean_campaign_environment()

	var enemy_base_nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "enemy_base")
	GlobalData.board.current_tile = Vector2i(4, 4)

	for action in ["defend"]:
		var intent := CampaignPlayerDispatch.create_intent(action, enemy_base_nid)
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_assert_false(bool(res.get("ok", false)), "T9: Future action %s safely rejected" % action)
		_assert_eq(str(res.get("reason", "")), "action_not_implemented", "T9: Reason is action_not_implemented for %s" % action)


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("CAMPAIGN NODE ACTION CAPABILITY CONTRACT VERIFY (Phase 5AS) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 5AS Node Action Capability Contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 5AS Node Action Capability Contract has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
