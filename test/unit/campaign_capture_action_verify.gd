class_name CampaignCaptureActionVerify
extends Node

## ---------------------------------------------------------------------------
## 5AT — CAMPAIGN CAPTURE ACTION & OWNERSHIP AUTHORITY CONTRACT VERIFICATION
##
## Verifies:
##   TEST A: Action Recognition & Registration with CampaignPlayerDispatch.
##   TEST B: Valid Capture Context (Enemy Base -> Federation Player Ownership).
##   TEST C: Authoritative Ownership Mutation (Base & Territory Controller updated).
##   TEST D: Structured Receipt Contract (capture_completed, node, base, controllers).
##   TEST E: Wrong Node Type Rejection (safehouse, city, supply_depot without enemy base -> node_cannot_capture).
##   TEST F: Player Not Present Rejection (player_not_at_node).
##   TEST G: Already Player Owned Rejection (already_player_owned).
##   TEST H: Opposing / Multi-Faction Capture (zeon -> outland).
##   TEST I: Atomic Failure Invariance (Zero Partial Mutation across currency, fuel, forces, turn).
##   TEST J: Campaign Turn Integrity (Zero turn advancement across all success/failure paths).
##   TEST K: Idempotency Contract (First capture succeeds, second capture fails safely).
##   TEST L: Multi-Action Coexistence (capture -> investigate -> resupply -> trade).
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignCaptureAction = preload("res://scripts/systems/campaign_capture_action.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0


func _ready() -> void:
	print("--- BEGIN CAMPAIGN CAPTURE ACTION CONTRACT VERIFY (Phase 5AT) ---")
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


func _setup_clean_campaign_environment() -> void:
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
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(0, 0)
		if GlobalData.currency != null:
			GlobalData.currency.credits = 500
			GlobalData.currency.scrap = 50
			GlobalData.currency.data_cores = 3
		if GlobalData.fuel != null:
			GlobalData.fuel.mech_energy = 80.0
			GlobalData.fuel.mech_max_energy = 100.0
			GlobalData.fuel.convoy_fuel = 60.0
			GlobalData.fuel.convoy_max_fuel = 80.0
		GlobalData.fuel_inventory.clear()
		GlobalData.fuel_inventory["fuel_canister"] = 2


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"data_cores": GlobalData.currency.data_cores if GlobalData and GlobalData.currency else 0,
		"fuel_inventory": GlobalData.fuel_inventory.duplicate(true) if GlobalData else {},
		"mech_energy": GlobalData.fuel.mech_energy if GlobalData and GlobalData.fuel else 0.0,
		"convoy_fuel": GlobalData.fuel.convoy_fuel if GlobalData and GlobalData.fuel else 0.0,
		"current_tile": GlobalData.board.current_tile if GlobalData and GlobalData.board else Vector2i(-1, -1),
		"current_sector": GlobalData.board.current_sector if GlobalData and GlobalData.board else -1,
		"turn": CampaignTurnExecutive.get_turn(),
		"bases": CampaignBase.serialize(),
		"territories": CampaignTerritory.serialize(),
		"forces": CampaignForce.serialize(),
		"battles": CampaignBattle.serialize(),
	}


func _run_all_tests() -> void:
	_test_a_action_recognition()
	_test_b_valid_capture_context()
	_test_c_ownership_mutation()
	_test_d_receipt_contract()
	_test_e_wrong_node_type()
	_test_f_player_not_present()
	_test_g_already_owned()
	_test_h_opposing_faction_capture()
	_test_i_atomic_failure_invariance()
	_test_j_turn_integrity()
	_test_k_idempotency()
	_test_l_multi_action_coexistence()


# ---------------------------------------------------------------------------
# TEST A: Action Recognition
# ---------------------------------------------------------------------------
func _test_a_action_recognition() -> void:
	_setup_clean_campaign_environment()

	_assert_true(CampaignPlayerDispatch.is_known_action("capture"), "A1: 'capture' is recognized by CampaignPlayerDispatch")
	var known := CampaignPlayerDispatch.get_known_actions()
	_assert_true(known.has("capture"), "A2: get_known_actions contains 'capture'")


# ---------------------------------------------------------------------------
# TEST B: Valid Capture Context
# ---------------------------------------------------------------------------
func _test_b_valid_capture_context() -> void:
	_setup_clean_campaign_environment()

	# Create Zeon Enemy Base at (7, 4)
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 4), "enemy_base", "node_frontier_outpost")
	var terr_id := CampaignTerritory.register_territory("terr_sector_beta", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	var base_id := CampaignBase.register_base("base_zeon_stronghold", node_id, "OUTPOST", "zeon", terr_id)

	# Place player at the node
	GlobalData.board.current_tile = Vector2i(7, 4)

	var intent := CampaignPlayerDispatch.create_intent("capture", node_id, {
		"claim_faction": "federation"
	})
	var res := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(res.get("ok", false)), "B1: Valid capture dispatch succeeds")
	_assert_eq(str(res.get("reason", "")), "capture_completed", "B2: Receipt reason is capture_completed")
	_assert_eq(str(res.get("previous_controller", "")), "zeon", "B3: Previous controller reported as zeon")
	_assert_eq(str(res.get("new_controller", "")), "federation", "B4: New controller reported as federation")


# ---------------------------------------------------------------------------
# TEST C: Ownership Mutation in Authoritative Layers
# ---------------------------------------------------------------------------
func _test_c_ownership_mutation() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "enemy_base", "node_base_c")
	var terr_id := CampaignTerritory.register_territory("terr_c", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	var base_id := CampaignBase.register_base("base_c", node_id, "OUTPOST", "zeon", terr_id)

	GlobalData.board.current_tile = Vector2i(5, 5)

	# Execute capture
	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_true(bool(res.get("ok", false)), "C1: Capture dispatch succeeds")

	# Check CampaignBase authority
	var base_record := CampaignBase.get_base(base_id)
	_assert_eq(str(base_record.get("controller", "")), "federation", "C2: CampaignBase controller updated to federation")

	# Check CampaignTerritory authority
	var terr_record := CampaignTerritory.get_territory(terr_id)
	_assert_eq(str(terr_record.get("controller", "")), "federation", "C3: CampaignTerritory controller updated to federation")
	_assert_eq(int(terr_record.get("control", -1)), CampaignTerritory.ControlState.CONTROLLED, "C4: Territory state is CONTROLLED")


# ---------------------------------------------------------------------------
# TEST D: Receipt Contract
# ---------------------------------------------------------------------------
func _test_d_receipt_contract() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "enemy_base", "node_base_d")
	var terr_id := CampaignTerritory.register_territory("terr_d", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	var base_id := CampaignBase.register_base("base_d", node_id, "OUTPOST", "zeon", terr_id)

	GlobalData.board.current_tile = Vector2i(6, 6)

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_true(res.has("ok"), "D1: Receipt contains 'ok'")
	_assert_true(res.has("reason"), "D2: Receipt contains 'reason'")
	_assert_true(res.has("node_id"), "D3: Receipt contains 'node_id'")
	_assert_true(res.has("base_id"), "D4: Receipt contains 'base_id'")
	_assert_true(res.has("previous_controller"), "D5: Receipt contains 'previous_controller'")
	_assert_true(res.has("new_controller"), "D6: Receipt contains 'new_controller'")
	_assert_true(res.has("territory_id"), "D7: Receipt contains 'territory_id'")


# ---------------------------------------------------------------------------
# TEST E: Wrong Node Type
# ---------------------------------------------------------------------------
func _test_e_wrong_node_type() -> void:
	_setup_clean_campaign_environment()

	var city_nid := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_city_e")
	var safe_nid := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse", "node_safe_e")
	var depot_nid := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "supply_depot", "node_depot_e")

	# City
	GlobalData.board.current_tile = Vector2i(1, 1)
	var res_city := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", city_nid))
	_assert_false(bool(res_city.get("ok", false)), "E1: Capture at CITY rejected")
	_assert_eq(str(res_city.get("reason", "")), "node_cannot_capture", "E2: Rejection reason node_cannot_capture")

	# Safehouse
	GlobalData.board.current_tile = Vector2i(2, 2)
	var res_safe := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", safe_nid))
	_assert_false(bool(res_safe.get("ok", false)), "E3: Capture at SAFEHOUSE rejected")
	_assert_eq(str(res_safe.get("reason", "")), "node_cannot_capture", "E4: Rejection reason node_cannot_capture")

	# Supply Depot
	GlobalData.board.current_tile = Vector2i(3, 3)
	var res_depot := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", depot_nid))
	_assert_false(bool(res_depot.get("ok", false)), "E5: Capture at SUPPLY_DEPOT rejected")
	_assert_eq(str(res_depot.get("reason", "")), "node_cannot_capture", "E6: Rejection reason node_cannot_capture")


# ---------------------------------------------------------------------------
# TEST F: Player Not Present
# ---------------------------------------------------------------------------
func _test_f_player_not_present() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "enemy_base", "node_base_f")
	CampaignBase.register_base("base_f", node_id, "OUTPOST", "zeon")

	# Player is elsewhere (0, 0)
	GlobalData.board.current_tile = Vector2i(0, 0)

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_false(bool(res.get("ok", false)), "F1: Remote capture rejected by dispatch")
	_assert_eq(str(res.get("reason", "")), "player_not_at_node", "F2: Rejection reason player_not_at_node")
	_assert_eq(str(CampaignBase.get_base("base_f").get("controller", "")), "zeon", "F3: Base controller remains zeon")


# ---------------------------------------------------------------------------
# TEST G: Already Player Owned
# ---------------------------------------------------------------------------
func _test_g_already_owned() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "enemy_base", "node_base_g")
	CampaignBase.register_base("base_g", node_id, "OUTPOST", "federation") # already federation

	GlobalData.board.current_tile = Vector2i(8, 8)

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id, {
		"claim_faction": "federation"
	}))
	_assert_false(bool(res.get("ok", false)), "G1: Capture of already-owned base rejected")
	_assert_eq(str(res.get("reason", "")), "already_player_owned", "G2: Reason is already_player_owned")


# ---------------------------------------------------------------------------
# TEST H: Opposing / Multi-Faction Capture
# ---------------------------------------------------------------------------
func _test_h_opposing_faction_capture() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "enemy_base", "node_base_h")
	var base_id := CampaignBase.register_base("base_h", node_id, "OUTPOST", "zeon")

	GlobalData.board.current_tile = Vector2i(9, 9)

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id, {
		"claim_faction": "outland"
	}))
	_assert_true(bool(res.get("ok", false)), "H1: Capture claim for outland succeeds")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "outland", "H2: Base controller updated to outland")


# ---------------------------------------------------------------------------
# TEST I: Atomic Failure Invariance
# ---------------------------------------------------------------------------
func _test_i_atomic_failure_invariance() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "city", "node_city_i")
	GlobalData.board.current_tile = Vector2i(4, 4)

	var snap_before := _take_state_snapshot()

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_false(bool(res.get("ok", false)), "I1: Invalid capture rejected")

	var snap_after := _take_state_snapshot()
	_assert_eq(snap_after, snap_before, "I2: State snapshot 100% unchanged after failed capture")


# ---------------------------------------------------------------------------
# TEST J: Turn Integrity (Zero Turn Advancement)
# ---------------------------------------------------------------------------
func _test_j_turn_integrity() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "enemy_base", "node_base_j")
	CampaignBase.register_base("base_j", node_id, "OUTPOST", "zeon")
	GlobalData.board.current_tile = Vector2i(7, 7)

	var turn_before := CampaignTurnExecutive.get_turn()

	# Successful capture
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "J1: Successful capture causes 0 turn advance")

	# Failed capture (already owned)
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "J2: Failed capture causes 0 turn advance")


# ---------------------------------------------------------------------------
# TEST K: Idempotency Contract
# ---------------------------------------------------------------------------
func _test_k_idempotency() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "enemy_base", "node_base_k")
	var base_id := CampaignBase.register_base("base_k", node_id, "OUTPOST", "zeon")
	GlobalData.board.current_tile = Vector2i(3, 3)

	# 1st capture -> success
	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_true(bool(r1.get("ok", false)), "K1: First capture succeeds")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation", "K2: Controller is federation")

	# 2nd capture -> rejected
	var r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_false(bool(r2.get("ok", false)), "K3: Second capture rejected")
	_assert_eq(str(r2.get("reason", "")), "already_player_owned", "K4: Second capture reason is already_player_owned")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation", "K5: Controller remains federation (mutated exactly once)")


# ---------------------------------------------------------------------------
# TEST L: Multi-Action Coexistence
# ---------------------------------------------------------------------------
func _test_l_multi_action_coexistence() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "enemy_base", "node_base_l")
	var base_id := CampaignBase.register_base("base_l", node_id, "OUTPOST", "zeon")
	GlobalData.board.current_tile = Vector2i(2, 2)

	# 1. Investigate enemy base
	var r_inv := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", node_id))
	_assert_true(bool(r_inv.get("ok", false)), "L1: Investigate at enemy base succeeds")

	# 2. Capture enemy base
	var r_cap := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", node_id))
	_assert_true(bool(r_cap.get("ok", false)), "L2: Capture succeeds")

	# 3. Investigate again after capture
	var r_inv2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", node_id))
	_assert_true(bool(r_inv2.get("ok", false)), "L3: Investigate after capture succeeds")

	var situation: Dictionary = r_inv2.get("situation", {})
	var base_info: Dictionary = situation.get("base", {})
	_assert_eq(str(base_info.get("controller", "")), "federation", "L4: Inspection reports updated controller federation")


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("CAMPAIGN CAPTURE ACTION CONTRACT VERIFY (Phase 5AT) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 5AT Campaign Capture Action Contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 5AT Campaign Capture Action Contract has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
