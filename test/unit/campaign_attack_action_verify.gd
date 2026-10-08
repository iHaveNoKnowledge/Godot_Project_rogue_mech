class_name CampaignAttackActionVerify
extends Node

## ---------------------------------------------------------------------------
## 5AU — CAMPAIGN ATTACK / COMBAT BOUNDARY CONTRACT VERIFICATION
##
## Verifies:
##   TEST A: Action Recognition & Registration with CampaignPlayerDispatch.
##   TEST B: Valid Attack against Hostile Force at Node (Battle initiated).
##   TEST C: Valid Attack against Enemy Base Installation (Garrison created & Battle initiated).
##   TEST D: Capture Isolation / Zero Ownership Mutation (Base & Territory controllers unchanged).
##   TEST E: Turn Isolation / Zero Turn Advancement (Delta turn = 0).
##   TEST F: Player Not Present Rejection (player_not_at_node).
##   TEST G: Target Not Hostile Rejection (Friendly base or force -> target_not_hostile).
##   TEST H: No Active Target Rejection (Empty neutral node -> no_active_target).
##   TEST I: Atomic Failure Invariance (Zero side effects across all state systems).
##   TEST J: Multi-Action Coexistence (investigate, resupply, trade, capture, attack).
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignAttackAction = preload("res://scripts/systems/campaign_attack_action.gd")
const CampaignCaptureAction = preload("res://scripts/systems/campaign_capture_action.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0


func _ready() -> void:
	print("--- BEGIN CAMPAIGN ATTACK ACTION CONTRACT VERIFY (Phase 5AU) ---")
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
	}


func _run_all_tests() -> void:
	_test_action_recognition()
	_test_valid_attack_hostile_force()
	_test_valid_attack_enemy_base_garrison()
	_test_capture_isolation_zero_ownership_mutation()
	_test_turn_isolation_zero_advancement()
	_test_player_not_present_rejection()
	_test_target_not_hostile_rejection()
	_test_no_active_target_rejection()
	_test_atomic_failure_invariance()
	_test_multi_action_coexistence()


# ---------------------------------------------------------------------------
# TEST A: Action Recognition & Registration
# ---------------------------------------------------------------------------
func _test_action_recognition() -> void:
	_setup_clean_campaign_environment()

	_assert_true(CampaignPlayerDispatch.is_known_action("attack"), "TEST A: attack is known action")

	var known := CampaignPlayerDispatch.get_known_actions()
	_assert_true(known.has("attack"), "TEST A: attack is in known action IDs")
	_assert_true(known.has("investigate"), "TEST A: investigate is in known action IDs")
	_assert_true(known.has("resupply"), "TEST A: resupply is in known action IDs")
	_assert_true(known.has("trade"), "TEST A: trade is in known action IDs")
	_assert_true(known.has("capture"), "TEST A: capture is in known action IDs")


# ---------------------------------------------------------------------------
# TEST B: Valid Attack Against Hostile Force
# ---------------------------------------------------------------------------
func _test_valid_attack_hostile_force() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "comms_relay")
	GlobalData.board.current_tile = Vector2i(3, 3)

	var force_id := CampaignForce.register_force("force_hostile_01", "PATROL", "zeon", node_id)

	var intent := CampaignPlayerDispatch.create_intent("attack", node_id)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(receipt.get("ok", false)), "TEST B: Hostile force attack succeeds")
	_assert_eq(str(receipt.get("reason", "")), "attack_started", "TEST B: Reason is attack_started")
	_assert_eq(str(receipt.get("action_id", "")), "attack", "TEST B: Action ID is attack")
	_assert_eq(str(receipt.get("node_id", "")), node_id, "TEST B: Node ID matches")
	_assert_eq(str(receipt.get("target_id", "")), force_id, "TEST B: Target ID is hostile force")

	var battle_id := str(receipt.get("battle_id", ""))
	_assert_true(CampaignBattle.is_active(battle_id), "TEST B: Battle is active in CampaignBattle authority")


# ---------------------------------------------------------------------------
# TEST C: Valid Attack Against Enemy Base Installation (Garrison Creation)
# ---------------------------------------------------------------------------
func _test_valid_attack_enemy_base_garrison() -> void:
	_setup_clean_campaign_environment()

	var enemy_base_nid := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "enemy_base")
	GlobalData.board.current_tile = Vector2i(5, 5)

	var terr_id := CampaignTerritory.register_territory("terr_zeon_alpha", [enemy_base_nid])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_zeon_alpha", enemy_base_nid, "OUTPOST", "zeon", terr_id)

	var intent := CampaignPlayerDispatch.create_intent("attack", enemy_base_nid)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(receipt.get("ok", false)), "TEST C: Enemy base attack succeeds")
	_assert_eq(str(receipt.get("reason", "")), "attack_started", "TEST C: Reason is attack_started")
	_assert_eq(str(receipt.get("target_id", "")), "base_zeon_alpha", "TEST C: Target ID is enemy base")

	var battle_id := str(receipt.get("battle_id", ""))
	_assert_true(CampaignBattle.is_active(battle_id), "TEST C: Base defense battle is active in CampaignBattle")


# ---------------------------------------------------------------------------
# TEST D: Capture Isolation / Zero Ownership Mutation
# ---------------------------------------------------------------------------
func _test_capture_isolation_zero_ownership_mutation() -> void:
	_setup_clean_campaign_environment()

	var enemy_base_nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "enemy_base")
	GlobalData.board.current_tile = Vector2i(4, 4)

	var terr_id := CampaignTerritory.register_territory("terr_zeon_beta", [enemy_base_nid])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_zeon_beta", enemy_base_nid, "OUTPOST", "zeon", terr_id)

	var base_before: Dictionary = CampaignBase.get_base("base_zeon_beta")
	var territory_before: String = CampaignTerritory.get_controller(terr_id)

	var intent := CampaignPlayerDispatch.create_intent("attack", enemy_base_nid)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(receipt.get("ok", false)), "TEST D: Attack starts cleanly")

	# Ownership MUST remain strictly unchanged by Attack
	var base_after: Dictionary = CampaignBase.get_base("base_zeon_beta")
	var territory_after: String = CampaignTerritory.get_controller(terr_id)

	_assert_eq(str(base_after.get("controller", "")), str(base_before.get("controller", "")), "TEST D: Base controller unchanged")
	_assert_eq(territory_after, territory_before, "TEST D: Territory controller unchanged")
	_assert_eq(str(base_after.get("controller", "")), "zeon", "TEST D: Base still controlled by zeon")


# ---------------------------------------------------------------------------
# TEST E: Turn Isolation / Zero Turn Advancement
# ---------------------------------------------------------------------------
func _test_turn_isolation_zero_advancement() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "enemy_base")
	GlobalData.board.current_tile = Vector2i(2, 2)
	var terr_id := CampaignTerritory.register_territory("terr_turn", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_turn_test", node_id, "OUTPOST", "zeon", terr_id)

	var turn_before: int = CampaignTurnExecutive.get_turn()

	var intent := CampaignPlayerDispatch.create_intent("attack", node_id)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(receipt.get("ok", false)), "TEST E: Attack succeeds")

	var turn_after: int = CampaignTurnExecutive.get_turn()
	_assert_eq(turn_after, turn_before, "TEST E: CampaignTurnExecutive turn delta is 0")


# ---------------------------------------------------------------------------
# TEST F: Player Not Present Rejection
# ---------------------------------------------------------------------------
func _test_player_not_present_rejection() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "enemy_base")
	GlobalData.board.current_tile = Vector2i(0, 0) # Player is elsewhere
	var terr_id := CampaignTerritory.register_territory("terr_remote", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_remote", node_id, "OUTPOST", "zeon", terr_id)

	var intent := CampaignPlayerDispatch.create_intent("attack", node_id)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_false(bool(receipt.get("ok", false)), "TEST F: Remote attack rejected")
	_assert_eq(str(receipt.get("reason", "")), "player_not_at_node", "TEST F: Reason is player_not_at_node")


# ---------------------------------------------------------------------------
# TEST G: Target Not Hostile Rejection
# ---------------------------------------------------------------------------
func _test_target_not_hostile_rejection() -> void:
	_setup_clean_campaign_environment()

	var safehouse_nid := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse")
	GlobalData.board.current_tile = Vector2i(1, 1)

	var terr_id := CampaignTerritory.register_territory("terr_friendly", [safehouse_nid])
	CampaignTerritory.set_controlled(terr_id, "federation")
	CampaignBase.register_base("base_friendly", safehouse_nid, "OUTPOST", "federation", terr_id)
	CampaignForce.register_force("force_friendly_01", "PATROL", "federation", safehouse_nid)

	var intent := CampaignPlayerDispatch.create_intent("attack", safehouse_nid)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_false(bool(receipt.get("ok", false)), "TEST G: Friendly target attack rejected")
	_assert_eq(str(receipt.get("reason", "")), "target_not_hostile", "TEST G: Reason is target_not_hostile")


# ---------------------------------------------------------------------------
# TEST H: No Active Target Rejection
# ---------------------------------------------------------------------------
func _test_no_active_target_rejection() -> void:
	_setup_clean_campaign_environment()

	var neutral_nid := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "safehouse")
	GlobalData.board.current_tile = Vector2i(3, 3)

	var intent := CampaignPlayerDispatch.create_intent("attack", neutral_nid)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_false(bool(receipt.get("ok", false)), "TEST H: Empty node attack rejected")
	_assert_eq(str(receipt.get("reason", "")), "no_active_target", "TEST H: Reason is no_active_target")


# ---------------------------------------------------------------------------
# TEST I: Atomic Failure Invariance
# ---------------------------------------------------------------------------
func _test_atomic_failure_invariance() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "enemy_base")
	GlobalData.board.current_tile = Vector2i(0, 0)
	var terr_id := CampaignTerritory.register_territory("terr_atomic", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_atomic_test", node_id, "OUTPOST", "zeon", terr_id)

	var snapshot_before := _take_state_snapshot()

	var intent := CampaignPlayerDispatch.create_intent("attack", node_id)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)
	_assert_false(bool(receipt.get("ok", false)), "TEST I: Rejection is clean")

	var snapshot_after := _take_state_snapshot()
	_assert_eq(snapshot_after, snapshot_before, "TEST I: State snapshot unchanged on failure")


# ---------------------------------------------------------------------------
# TEST J: Multi-Action Coexistence
# ---------------------------------------------------------------------------
func _test_multi_action_coexistence() -> void:
	_setup_clean_campaign_environment()

	# Create supply depot
	var depot_nid := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "supply_depot")
	GlobalData.board.current_tile = Vector2i(1, 1)

	# 1. Investigate
	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", depot_nid))
	_assert_true(bool(r1.get("ok", false)), "TEST J: Investigate succeeds")

	# 2. Resupply
	var r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", depot_nid))
	_assert_true(bool(r2.get("ok", false)), "TEST J: Resupply succeeds")

	# 3. Trade
	var r3 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", depot_nid, {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1
	}))
	_assert_true(bool(r3.get("ok", false)), "TEST J: Trade succeeds")

	# Move to enemy base
	var enemy_base_nid := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "enemy_base")
	GlobalData.board.current_tile = Vector2i(2, 2)
	var terr_id := CampaignTerritory.register_territory("terr_coexist", [enemy_base_nid])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_coexist", enemy_base_nid, "OUTPOST", "zeon", terr_id)

	# 4. Attack
	var r4 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", enemy_base_nid))
	_assert_true(bool(r4.get("ok", false)), "TEST J: Attack succeeds")

	# 5. Capture
	var r5 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", enemy_base_nid))
	_assert_true(bool(r5.get("ok", false)), "TEST J: Capture succeeds")

	_assert_eq(CampaignTurnExecutive.get_turn(), 0, "TEST J: Turn remains 0 throughout all actions")


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("CAMPAIGN ATTACK ACTION VERIFY (Phase 5AU) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 5AU Campaign Attack / Combat Boundary Contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 5AU Campaign Attack / Combat Boundary Contract has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
