class_name CampaignRecoverActionVerify
extends Node

## ---------------------------------------------------------------------------
## Phase 2D-1 — BASE RECOVERY ACTION VERIFICATION
##
## Verifies the player 'recover' action (DISABLED -> ACTIVE for 150 credits):
##   R1. Valid recovery: exactly 150 spent, ACTIVE, controller unchanged.
##   R2. Wrong controller rejected without mutation.
##   R3. Already-ACTIVE base rejected (base_not_disabled) without mutation.
##   R4. Destroyed/missing base rejected through authoritative lookup.
##   R5. Insufficient credits: no deduction, no state change.
##   R6. ACTIVE assault blocks recovery without mutation.
##   R7. Player-not-at-node rejected without mutation.
##   R8. Duplicate dispatch cannot spend twice.
##   R9. Spending/state atomicity (spend gate + refund branch present).
##   R10. Save/load round-trip preserves recovered state and credits.
##   R11. ACTIVE atk_ battle at the same node does not block recovery (2H-A).
## ---------------------------------------------------------------------------

const CampaignRecoverAction = preload("res://scripts/systems/campaign_recover_action.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN PHASE 2D-1 BASE RECOVERY VERIFY ---")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	_run_all_tests()
	_restore_save_backup()
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
	FactionSystem.set_player_faction("federation")
	CampaignBaseDefense.reset_defense_state()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
	GlobalData.current_campaign_player_node_id = ""
	if GlobalData != null:
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(0, 0)
			GlobalData.board.board_patrol_engagement = -1
		if GlobalData.currency != null:
			GlobalData.currency.credits = 1000
			GlobalData.currency.scrap = 50


## Registers a federation OUTPOST base left DISABLED, with the player present.
func _setup_disabled_base(tag: String, tile: Vector2i) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_" + tag, [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_" + tag, node_id, "OUTPOST", "federation", terr_id)
	CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED)
	GlobalData.board.current_tile = tile
	CampaignPlayerMovement.set_current_node_id(node_id)
	return {"node_id": node_id, "base_id": base_id}


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"turn": CampaignTurnExecutive.get_turn(),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
	}


func _run_all_tests() -> void:
	_test_valid_recovery()
	_test_wrong_controller()
	_test_already_active()
	_test_destroyed_or_missing_base()
	_test_insufficient_credits()
	_test_active_assault_blocks()
	_test_player_not_at_node()
	_test_duplicate_dispatch()
	_test_spend_atomicity()
	_test_save_load_round_trip()
	_test_attack_battle_does_not_block()


# ---------------------------------------------------------------------------
# R1: Valid recovery.
# ---------------------------------------------------------------------------
func _test_valid_recovery() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r1", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var turn_before: int = CampaignTurnExecutive.get_turn()

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_true(bool(res.get("ok", false)), "R1: Valid recovery succeeds")
	_assert_eq(str(res.get("reason", "")), "recovery_completed", "R1: Reason is recovery_completed")
	_assert_eq(int(res.get("credits_spent", -1)), 150, "R1: Receipt reports exactly 150 spent")
	_assert_eq(GlobalData.currency.credits, 850, "R1: Exactly 150 credits deducted")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"R1: Base is ACTIVE")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"R1: Controller unchanged")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "R1: No turn consumed")


# ---------------------------------------------------------------------------
# R2: Wrong controller rejected without mutation.
# ---------------------------------------------------------------------------
func _test_wrong_controller() -> void:
	_setup_clean_campaign_environment()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_r2", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	var base_id := CampaignBase.register_base("base_r2", node_id, "OUTPOST", "zeon", terr_id)
	CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED)
	GlobalData.board.current_tile = Vector2i(5, 5)
	CampaignPlayerMovement.set_current_node_id(node_id)
	var snap_before := _take_state_snapshot()

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_false(bool(res.get("ok", true)), "R2: Foreign base rejected")
	_assert_eq(str(res.get("reason", "")), "not_player_base", "R2: Reason is not_player_base")
	_assert_eq(_take_state_snapshot(), snap_before, "R2: Zero mutation (credits and base intact)")


# ---------------------------------------------------------------------------
# R3: Already-ACTIVE base rejected.
# ---------------------------------------------------------------------------
func _test_already_active() -> void:
	_setup_clean_campaign_environment()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	var terr_id := CampaignTerritory.register_territory("terr_r3", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_r3", node_id, "OUTPOST", "federation", terr_id)
	GlobalData.board.current_tile = Vector2i(2, 2)
	CampaignPlayerMovement.set_current_node_id(node_id)
	var snap_before := _take_state_snapshot()

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_false(bool(res.get("ok", true)), "R3: ACTIVE base rejected")
	_assert_eq(str(res.get("reason", "")), "base_not_disabled", "R3: Reason is base_not_disabled")
	_assert_eq(_take_state_snapshot(), snap_before, "R3: Zero mutation")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"R3: Base still ACTIVE")


# ---------------------------------------------------------------------------
# R4: Destroyed/missing base rejected through authoritative lookup.
# ---------------------------------------------------------------------------
func _test_destroyed_or_missing_base() -> void:
	_setup_clean_campaign_environment()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_r4", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_r4", node_id, "OUTPOST", "federation", terr_id)
	CampaignBase.set_state(base_id, CampaignBase.BaseState.DESTROYED)
	GlobalData.board.current_tile = Vector2i(3, 3)
	CampaignPlayerMovement.set_current_node_id(node_id)

	var res_gone := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_false(bool(res_gone.get("ok", true)), "R4: Destroyed base rejected")
	_assert_eq(str(res_gone.get("reason", "")), "no_base_to_recover",
		"R4: Destroyed base reads as no base (authoritative lookup)")

	var res_unknown := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", "node_nope"))
	_assert_eq(str(res_unknown.get("reason", "")), "unknown_node", "R4: Unknown node rejected")

	# Wrong action id rejected by the handler itself.
	var bad := CampaignRecoverAction.handle_recover({"action_id": "attack", "node_id": node_id})
	_assert_eq(str(bad.get("reason", "")), "invalid_action_for_handler",
		"R4: Wrong action id rejected")


# ---------------------------------------------------------------------------
# R5: Insufficient credits: no deduction, no state change.
# ---------------------------------------------------------------------------
func _test_insufficient_credits() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r5", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	GlobalData.currency.credits = 100

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_false(bool(res.get("ok", true)), "R5: Unfunded recovery rejected")
	_assert_eq(str(res.get("reason", "")), "insufficient_credits",
		"R5: Reason is insufficient_credits")
	_assert_eq(GlobalData.currency.credits, 100, "R5: Not a single credit deducted")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.DISABLED,
		"R5: Base still DISABLED")


# ---------------------------------------------------------------------------
# R6: ACTIVE assault blocks recovery without mutation.
# ---------------------------------------------------------------------------
func _test_active_assault_blocks() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r6", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var attacker_id := CampaignForce.register_force("force_zeon_r6", "PATROL", "zeon", node_id)
	var atk := CampaignBaseDefense.start_base_attack(base_id, attacker_id)
	_assert_true(bool(atk.get("ok", false)), "R6: Assault starts on the DISABLED base")
	var snap_before := _take_state_snapshot()

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_false(bool(res.get("ok", true)), "R6: Recovery during assault rejected")
	_assert_eq(str(res.get("reason", "")), "assault_in_progress",
		"R6: Reason is assault_in_progress")
	_assert_eq(_take_state_snapshot(), snap_before, "R6: Zero mutation")
	_assert_true(CampaignBaseDefense.is_base_under_attack(base_id),
		"R6: Assault still ACTIVE afterwards")


# ---------------------------------------------------------------------------
# R7: Player not at node rejected without mutation.
# ---------------------------------------------------------------------------
func _test_player_not_at_node() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r7", Vector2i(4, 4))
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.current_campaign_player_node_id = ""
	var snap_before := _take_state_snapshot()

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", str(ctx.get("node_id", ""))))
	_assert_eq(str(res.get("reason", "")), "player_not_at_node", "R7: Remote node rejected")
	_assert_eq(_take_state_snapshot(), snap_before, "R7: Zero mutation")


# ---------------------------------------------------------------------------
# R8: Duplicate dispatch cannot spend twice.
# ---------------------------------------------------------------------------
func _test_duplicate_dispatch() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r8", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))

	var first := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_true(bool(first.get("ok", false)), "R8: First recovery succeeds")
	var second := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_false(bool(second.get("ok", true)), "R8: Second recovery rejected")
	_assert_eq(str(second.get("reason", "")), "base_not_disabled",
		"R8: Reason is base_not_disabled")
	_assert_eq(GlobalData.currency.credits, 850, "R8: Only 150 ever deducted")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"R8: Base ACTIVE")


# ---------------------------------------------------------------------------
# R9: Spending/state atomicity.
# ---------------------------------------------------------------------------
func _test_spend_atomicity() -> void:
	_setup_clean_campaign_environment()
	# try_spend_credits is atomic by contract: failed spend mutates nothing.
	GlobalData.currency.credits = 149
	_assert_false(GlobalData.currency.try_spend_credits(150),
		"R9: try_spend fails below cost")
	_assert_eq(GlobalData.currency.credits, 149, "R9: Failed spend deducts nothing")
	_assert_true(GlobalData.currency.try_spend_credits(100),
		"R9: Affordable spend succeeds")
	_assert_eq(GlobalData.currency.credits, 49, "R9: Successful spend deducts exactly")
	# The handler deducts only after all eligibility checks, and carries a
	# refund branch (existing gain_credits) if the graph transition ever fails.
	var src := FileAccess.get_file_as_string(
		"res://scripts/systems/campaign_recover_action.gd")
	_assert_true(src.contains("try_spend_credits(RECOVER_COST_CREDITS)"),
		"R9: Handler spends through the atomic API")
	_assert_true(src.contains("gain_credits(RECOVER_COST_CREDITS)"),
		"R9: Refund branch present for transition failure")


# ---------------------------------------------------------------------------
# R10: Save/load round-trip preserves recovered state and credits.
# ---------------------------------------------------------------------------
func _test_save_load_round_trip() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r10", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_true(bool(res.get("ok", false)), "R10: Recovery succeeds")
	_assert_true(SaveGameIO.save_run(), "R10: Save succeeds")
	GlobalData.currency.credits = 0
	CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED)
	_assert_true(SaveGameIO.load_run(), "R10: Load succeeds")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"R10: ACTIVE state restored")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"R10: Controller restored")
	_assert_eq(GlobalData.currency.credits, 850, "R10: Deducted credits restored")


# ---------------------------------------------------------------------------
# R11: ACTIVE atk_ battle at the same node does not block recovery (2H-A).
# ---------------------------------------------------------------------------
func _test_attack_battle_does_not_block() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_disabled_base("r11", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))

	var fa := CampaignForce.register_force("force_zeon_r11", "PATROL", "zeon", node_id)
	var fb := CampaignForce.register_force("force_fed_r11", "PATROL", "federation", node_id)
	var atk_bid := CampaignBattle.register_battle("battle_s1_atk_" + node_id, node_id, [fa, fb])
	CampaignBattle.prepare_launch(atk_bid)
	_assert_false(CampaignBaseDefense.is_base_under_attack(base_id),
		"R11: atk_ battle is not an assault")

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("recover", node_id))
	_assert_true(bool(res.get("ok", false)), "R11: Recovery succeeds despite atk_ battle")
	_assert_eq(str(res.get("reason", "")), "recovery_completed", "R11: Reason is recovery_completed")
	_assert_eq(GlobalData.currency.credits, 850, "R11: Exactly 150 deducted")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"R11: Base ACTIVE")


func _restore_save_backup() -> void:
	GlobalData.reset_run_data()
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.flush()
			f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("PHASE 2D-1 BASE RECOVERY VERIFY RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 2D-1 base recovery contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 2D-1 base recovery has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
