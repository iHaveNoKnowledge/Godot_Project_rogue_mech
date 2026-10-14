class_name CampaignAttackActionVerify
extends Node

## ---------------------------------------------------------------------------
## 5AU — CAMPAIGN ATTACK / COMBAT BOUNDARY CONTRACT VERIFICATION
##
## Verifies:
##   TEST A: Action Recognition & Registration with CampaignPlayerDispatch.
##   TEST B: Valid Attack against Hostile Force at Node (Battle initiated).
##   TEST C: Hostile base without hostile forces defers (no fabricated garrison).
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
	CampaignBaseDefense.reset_defense_state()
	CampaignAttackBridge.reset_attack_state()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
	# Gate 3A: successful attacks now enter tactical combat; suppress the real
	# scene swap in headless runs (same pattern as the defend suite).
	GameManager.suppress_scene_change = true

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
	_test_active_identical_reuse()
	_test_active_mismatch_rejection()
	_test_terminal_suffix_allocation()
	_test_payload_id_validation()
	_test_legacy_active_reuse()
	_test_planned_battle_launch()
	_test_payload_mismatch_rejection()


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
# TEST C: Hostile Base Without Hostile Forces Defers (Phase 2H-B Gate 1 —
# no garrison is fabricated; capturing the base is the capture action's job)
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

	_assert_false(bool(receipt.get("ok", true)), "TEST C: Forceless base attack rejected")
	_assert_eq(str(receipt.get("reason", "")), "no_active_target", "TEST C: Reason is no_active_target")
	_assert_false(CampaignForce.has_force("force_garrison_" + enemy_base_nid),
		"TEST C: No garrison force fabricated")
	_assert_true(CampaignBattle.get_battles().is_empty(),
		"TEST C: No battle created without verified targets")


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
	CampaignForce.register_force("force_zeon_beta", "PATROL", "zeon", enemy_base_nid)

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
	CampaignForce.register_force("force_zeon_turn", "PATROL", "zeon", node_id)

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
	CampaignPlayerMovement.set_current_node_id(enemy_base_nid) # strategic presence is authoritative; tile alone does not reposition a pinned player node
	var terr_id := CampaignTerritory.register_territory("terr_coexist", [enemy_base_nid])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	CampaignBase.register_base("base_coexist", enemy_base_nid, "OUTPOST", "zeon", terr_id)
	CampaignForce.register_force("force_zeon_coexist", "PATROL", "zeon", enemy_base_nid)

	# 4. Attack
	var r4 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", enemy_base_nid))
	_assert_true(bool(r4.get("ok", false)), "TEST J: Attack succeeds")

	# 5. Capture
	var r5 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", enemy_base_nid))
	_assert_true(bool(r5.get("ok", false)), "TEST J: Capture succeeds")

	_assert_eq(CampaignTurnExecutive.get_turn(), 0, "TEST J: Turn remains 0 throughout all actions")


# ---------------------------------------------------------------------------
# TEST K: ACTIVE Identical Reuse (Phase 2H-B Gate 1)
# ---------------------------------------------------------------------------
func _test_active_identical_reuse() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	GlobalData.board.current_tile = Vector2i(7, 7)
	CampaignForce.register_force("force_zeon_k1", "PATROL", "zeon", node_id)
	CampaignForce.register_force("force_zeon_k2", "PATROL", "zeon", node_id)

	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(r1.get("ok", false)), "TEST K: First attack succeeds")
	var battle_id := str(r1.get("battle_id", ""))

	var r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(r2.get("ok", false)), "TEST K: Identical re-attack succeeds")
	_assert_eq(str(r2.get("battle_id", "")), battle_id, "TEST K: Same battle id reused")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "TEST K: Still a single battle")
	_assert_true(CampaignBattle.is_active(battle_id), "TEST K: Battle still ACTIVE")


# ---------------------------------------------------------------------------
# TEST L: ACTIVE Mismatch Rejection (Phase 2H-B Gate 1)
# ---------------------------------------------------------------------------
func _test_active_mismatch_rejection() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	GlobalData.board.current_tile = Vector2i(7, 7)
	CampaignForce.register_force("force_zeon_l1", "PATROL", "zeon", node_id)
	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(r1.get("ok", false)), "TEST L: First attack succeeds")
	var snap_before := _take_state_snapshot()

	# New hostile arrives: re-attack now names a different target set.
	CampaignForce.register_force("force_zeon_l2", "PATROL", "zeon", node_id)
	var r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_false(bool(r2.get("ok", false)), "TEST L: Mismatched re-attack rejected")
	_assert_eq(str(r2.get("reason", "")), "attack_target_mismatch",
		"TEST L: Reason is attack_target_mismatch")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "TEST L: No duplicate battle created")
	_assert_eq(_take_state_snapshot(), snap_before, "TEST L: Rejection leaves state untouched")


# ---------------------------------------------------------------------------
# TEST M: Terminal Suffix Allocation (Phase 2H-B Gate 1)
# ---------------------------------------------------------------------------
func _test_terminal_suffix_allocation() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	GlobalData.board.current_tile = Vector2i(7, 7)
	CampaignForce.register_force("force_zeon_m1", "PATROL", "zeon", node_id)
	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	var first_id := str(r1.get("battle_id", ""))
	_assert_true(CampaignBattle.resolve_battle(first_id), "TEST M: First battle resolved")

	var r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(r2.get("ok", false)), "TEST M: Post-terminal attack succeeds")
	var second_id := str(r2.get("battle_id", ""))
	_assert_true(second_id != first_id, "TEST M: New unique id issued")
	_assert_true(second_id.ends_with("_s2"), "TEST M: Suffix follows the _s2 convention")
	_assert_true(CampaignBattle.is_active(second_id), "TEST M: New battle ACTIVE (never stale)")

	CampaignBattle.cancel_battle(second_id)
	var r3 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(r3.get("ok", false)), "TEST M: Post-cancel attack succeeds")
	_assert_true(str(r3.get("battle_id", "")).ends_with("_s3"),
		"TEST M: Cancelled history advances the suffix identically")


# ---------------------------------------------------------------------------
# TEST N: Payload ID Validation (Phase 2H-B Gate 1)
# ---------------------------------------------------------------------------
func _test_payload_id_validation() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	GlobalData.board.current_tile = Vector2i(7, 7)
	CampaignForce.register_force("force_zeon_n1", "PATROL", "zeon", node_id)

	var bad_unknown := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", node_id, {"battle_id": "battle_nope"}))
	_assert_false(bool(bad_unknown.get("ok", false)), "TEST N: Unknown payload id rejected")
	_assert_eq(str(bad_unknown.get("reason", "")), "unknown_battle",
		"TEST N: Reason is unknown_battle")

	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	var real_id := str(r1.get("battle_id", ""))
	var bad_resolved := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", node_id, {"battle_id": real_id}))
	# Still ACTIVE and identical here, so this succeeds; resolve it first.
	_assert_true(bool(bad_resolved.get("ok", false)), "TEST N: Matching ACTIVE payload id accepted")
	_assert_true(CampaignBattle.resolve_battle(real_id), "TEST N: Battle resolved")
	var bad_terminal := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", node_id, {"battle_id": real_id}))
	_assert_false(bool(bad_terminal.get("ok", false)), "TEST N: Terminal payload id rejected")
	_assert_eq(str(bad_terminal.get("reason", "")), "battle_not_active",
		"TEST N: Reason is battle_not_active")


# ---------------------------------------------------------------------------
# TEST O: Legacy ACTIVE Reuse (Phase 2H-B Gate 1)
# ---------------------------------------------------------------------------
func _test_legacy_active_reuse() -> void:
	_setup_clean_campaign_environment()

	# A legacy atk_ battle (e.g. from an old save) with matching identity.
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	GlobalData.board.current_tile = Vector2i(7, 7)
	CampaignForce.register_force("force_zeon_o1", "PATROL", "zeon", node_id)
	var legacy_id := CampaignBattle.make_battle_id(1, "atk_" + node_id)
	CampaignBattle.register_battle(legacy_id, node_id, ["force_zeon_o1"])
	CampaignBattle.prepare_launch(legacy_id)

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(res.get("ok", false)), "TEST O: Legacy ACTIVE battle reused")
	_assert_eq(str(res.get("battle_id", "")), legacy_id, "TEST O: Same legacy id returned")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "TEST O: No duplicate battle")


# ---------------------------------------------------------------------------
# TEST P: PLANNED Battle Launch (Gate 1 closure — pre-registered battle is
# launched in place, never duplicated or overwritten).
# ---------------------------------------------------------------------------
func _test_planned_battle_launch() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "city")
	GlobalData.board.current_tile = Vector2i(9, 9)
	CampaignForce.register_force("force_zeon_p1", "PATROL", "zeon", node_id)
	var planned_id := CampaignBattle.make_battle_id(1, "atk_" + node_id)
	CampaignBattle.register_battle(planned_id, node_id, ["force_zeon_p1"])
	_assert_true(CampaignBattle.is_planned(planned_id), "TEST P: Battle starts PLANNED")

	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	_assert_true(bool(res.get("ok", false)), "TEST P: Attack on PLANNED battle succeeds")
	_assert_eq(str(res.get("battle_id", "")), planned_id, "TEST P: Same battle id reused")
	_assert_true(CampaignBattle.is_active(planned_id), "TEST P: PLANNED battle launched ACTIVE")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "TEST P: No duplicate battle")
	_assert_eq(CampaignBattle.get_participants(planned_id), ["force_zeon_p1"],
		"TEST P: Participant roster untouched")


# ---------------------------------------------------------------------------
# TEST Q: Payload Mismatch Rejection (Gate 1 closure — a supplied ACTIVE id
# whose targets differ is rejected without touching the existing battle).
# ---------------------------------------------------------------------------
func _test_payload_mismatch_rejection() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "city")
	GlobalData.board.current_tile = Vector2i(9, 9)
	CampaignForce.register_force("force_zeon_q1", "PATROL", "zeon", node_id)
	var r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("attack", node_id))
	var real_id := str(r1.get("battle_id", ""))
	_assert_true(CampaignBattle.is_active(real_id), "TEST Q: Setup battle ACTIVE")

	# A second hostile arrives: the stored battle no longer matches.
	CampaignForce.register_force("force_zeon_q2", "PATROL", "zeon", node_id)
	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", node_id, {"battle_id": real_id}))
	_assert_false(bool(res.get("ok", false)), "TEST Q: Mismatched payload id rejected")
	_assert_eq(str(res.get("reason", "")), "attack_target_mismatch",
		"TEST Q: Reason is attack_target_mismatch")
	_assert_eq(CampaignBattle.get_participants(real_id), ["force_zeon_q1"],
		"TEST Q: Existing battle participants untouched")
	_assert_true(CampaignBattle.is_active(real_id), "TEST Q: Existing battle still ACTIVE")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "TEST Q: No second battle registered")


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
	GameManager.suppress_scene_change = false
	GameManager.transition_to(GameManager.State.BOARD)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
