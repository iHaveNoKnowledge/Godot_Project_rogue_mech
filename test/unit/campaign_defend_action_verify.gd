class_name CampaignDefendActionVerify
extends Node

## ---------------------------------------------------------------------------
## S2-A — PLAYER-SIDE BASE DEFENSE VERIFICATION
##
## Verifies (in dependency order):
##   PART 1 (no dispatch handler needed):
##     C1. Engagement recording validates battle/session/base coherence.
##     C2. Victory resolves the matching battle and destroys the lone attacker;
##         base ownership and condition untouched.
##     C3. Defeat resolves the battle and DISABLEDs the base WITHOUT changing
##         its controller; the attacker is untouched.
##     C4. Retreat (combat_escaped) preserves the ACTIVE assault and pending slot.
##     C5. Duplicate result delivery and unrelated battles mutate nothing.
##     C6. Save/load recovery: ACTIVE intervention re-tracked, stale sessions
##         cleared, no duplicate application after restoration.
##   PART 2 (needs CampaignDefendAction + dispatch registration):
##     A. Defend action contract (valid/stale/failure paths, zero mutation).
##     B. Playable battle entry (combat type, context, loadout authority).
## ---------------------------------------------------------------------------

const CampaignBaseDefense = preload("res://scripts/systems/campaign_base_defense.gd")
const CampaignDefendAction = preload("res://scripts/systems/campaign_defend_action.gd")
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN S2-A PLAYER-SIDE BASE DEFENSE VERIFY ---")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	await get_tree().process_frame
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
			GlobalData.currency.scrap = 100


## Builds an assaulted player base with the player present. Returns context.
func _setup_assaulted_base(base_tag: String, tile: Vector2i) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_" + base_tag, [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_" + base_tag, node_id, "OUTPOST", "federation", terr_id)
	var attacker_id := CampaignForce.register_force("force_zeon_" + base_tag, "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	GlobalData.board.current_tile = tile
	CampaignPlayerMovement.set_current_node_id(node_id)
	var atk := CampaignBaseDefense.start_base_attack(base_id, attacker_id)
	if not bool(atk.get("ok", false)):
		_assert_true(false, "setup assault for %s" % base_tag)
		return {}
	return {
		"node_id": node_id,
		"base_id": base_id,
		"attacker_id": attacker_id,
		"battle_id": str(atk.get("battle_id", "")),
	}


func _run_all_tests() -> void:
	_test_record_validation()
	_test_victory_application()
	_test_defeat_application()
	_test_retreat_preservation()
	_test_duplicate_and_unrelated_ignored()
	_test_persistence_recovery()
	_test_defend_contract()
	_test_battle_entry()


# ---------------------------------------------------------------------------
# C1: Recording validates coherence (no battle/session/base invented).
# ---------------------------------------------------------------------------
func _test_record_validation() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("rec", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))

	# No session yet -> refuse to record.
	_assert_false(CampaignBaseDefense.record_defense_engagement(battle_id, base_id),
		"C1: Record refused without an intervention session")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), "",
		"C1: Pending slot stays empty after refused record")

	# Intervene, then record.
	var int_res := CampaignBaseDefense.intervene(battle_id)
	_assert_true(bool(int_res.get("ok", false)), "C1: Intervention starts")
	_assert_true(CampaignBaseDefense.record_defense_engagement(battle_id, base_id),
		"C1: Record accepted for a coherent intervention")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), battle_id,
		"C1: Pending slot tracks the battle")

	# Unknown battle / mismatched base never record.
	_assert_false(CampaignBaseDefense.record_defense_engagement("battle_nope", base_id),
		"C1: Unknown battle refused")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), "",
		"C1: Failed record leaves the slot empty")


# ---------------------------------------------------------------------------
# C2: Victory resolves + destroys the lone attacker; base untouched.
# ---------------------------------------------------------------------------
func _test_victory_application() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("vic", Vector2i(5, 5))
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	CampaignBaseDefense.intervene(battle_id)
	CampaignBaseDefense.record_defense_engagement(battle_id, base_id)
	CampaignBaseDefense.ensure_defense_result_hook()

	EventBus.combat_ended.emit(true)

	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"C2: Matching battle RESOLVED on victory")
	_assert_eq(CampaignForce.get_state(attacker_id), CampaignForce.ForceState.DESTROYED,
		"C2: Lone attacker DESTROYED on victory")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"C2: Base controller preserved on victory")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"C2: Base stays ACTIVE on victory")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), "",
		"C2: Pending slot consumed on victory")


# ---------------------------------------------------------------------------
# C3: Defeat DISABLEDs the base, keeps its controller, spares the attacker.
# ---------------------------------------------------------------------------
func _test_defeat_application() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("def", Vector2i(6, 6))
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	CampaignBaseDefense.intervene(battle_id)
	CampaignBaseDefense.record_defense_engagement(battle_id, base_id)
	CampaignBaseDefense.ensure_defense_result_hook()

	EventBus.combat_ended.emit(false)

	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"C3: Matching battle RESOLVED on defeat")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.DISABLED,
		"C3: Base DISABLED on defeat")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"C3: Base controller unchanged on defeat")
	_assert_eq(CampaignForce.get_state(attacker_id), CampaignForce.ForceState.ACTIVE,
		"C3: Attacker untouched on defeat")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), "",
		"C3: Pending slot consumed on defeat")


# ---------------------------------------------------------------------------
# C4: Retreat preserves the unresolved assault (no listener on escaped).
# ---------------------------------------------------------------------------
func _test_retreat_preservation() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("ret", Vector2i(7, 7))
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	CampaignBaseDefense.intervene(battle_id)
	CampaignBaseDefense.record_defense_engagement(battle_id, base_id)
	CampaignBaseDefense.ensure_defense_result_hook()

	EventBus.combat_escaped.emit()

	_assert_true(CampaignBattle.is_active(battle_id),
		"C4: Battle stays ACTIVE after retreat")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), battle_id,
		"C4: Pending slot preserved after retreat")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"C4: Base condition unchanged after retreat")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"C4: Base controller unchanged after retreat")


# ---------------------------------------------------------------------------
# C5: Duplicates and unrelated battles mutate nothing.
# ---------------------------------------------------------------------------
func _test_duplicate_and_unrelated_ignored() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("dup", Vector2i(8, 8))
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	CampaignBaseDefense.intervene(battle_id)
	CampaignBaseDefense.record_defense_engagement(battle_id, base_id)
	CampaignBaseDefense.ensure_defense_result_hook()

	EventBus.combat_ended.emit(true)
	var attacker_state := CampaignForce.get_state(str(ctx.get("attacker_id", "")))

	# Duplicate delivery of the same outcome.
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignForce.get_state(str(ctx.get("attacker_id", ""))), attacker_state,
		"C5: Duplicate victory changes nothing")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"C5: Base still ACTIVE after duplicate")

	# An unrelated tactical battle ending touches no campaign base.
	var other_node := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "safehouse")
	var fa := CampaignForce.register_force("force_other_a", "PATROL", "zeon", other_node)
	var fb := CampaignForce.register_force("force_other_b", "PATROL", "outland", other_node)
	var other_battle := CampaignBattle.register_battle("battle_unrelated", other_node, [fa, fb])
	CampaignBattle.prepare_launch(other_battle)
	EventBus.combat_ended.emit(false)
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"C5: Unrelated defeat leaves the defended base ACTIVE")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"C5: Unrelated defeat leaves the controller intact")


# ---------------------------------------------------------------------------
# C6: Save/load recovery (assault ACTIVE, intervention recorded, stale).
# ---------------------------------------------------------------------------
func _test_persistence_recovery() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assaulted_base("per", Vector2i(3, 3))
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	CampaignBaseDefense.intervene(battle_id)
	CampaignBaseDefense.record_defense_engagement(battle_id, base_id)

	_assert_true(SaveGameIO.save_run(), "C6: Save with ACTIVE intervention succeeds")
	# Simulate a fresh process: statics wiped, records restored from disk.
	CampaignBaseDefense.reset_defense_state()
	_assert_true(SaveGameIO.load_run(), "C6: Load restores the assault")
	_assert_true(CampaignBattle.is_active(battle_id),
		"C6: Intervention battle still ACTIVE after load")
	CampaignBaseDefense.ensure_defense_result_hook()

	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"C6: Recovered engagement resolves on victory")
	_assert_eq(CampaignForce.get_state(attacker_id), CampaignForce.ForceState.DESTROYED,
		"C6: Recovered engagement destroys the attacker")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"C6: Controller preserved after recovery")

	# Stale marker on a RESOLVED battle is cleaned, never applied.
	CampaignBattle.set_session_ref(battle_id,
		CampaignBaseDefense.INTERVENTION_SESSION_PREFIX + battle_id)
	CampaignBaseDefense.recover_pending_defense_from_records()
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), "",
		"C6: Stale session never re-tracked")
	_assert_eq(CampaignBattle.get_session_ref(battle_id), "",
		"C6: Stale session marker cleared")


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"mech_energy": GlobalData.fuel.mech_energy if GlobalData and GlobalData.fuel else 0.0,
		"convoy_fuel": GlobalData.fuel.convoy_fuel if GlobalData and GlobalData.fuel else 0.0,
		"turn": CampaignTurnExecutive.get_turn(),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
	}


# ---------------------------------------------------------------------------
# A: Defend action contract (valid/stale/failure paths, zero mutation).
# ---------------------------------------------------------------------------
func _test_defend_contract() -> void:
	_setup_clean_campaign_environment()
	GameManager.suppress_scene_change = true

	# Wrong action id rejected by the handler itself.
	var bad := CampaignDefendAction.handle_defend({"action_id": "attack", "node_id": "x"})
	_assert_eq(str(bad.get("reason", "")), "invalid_action_for_handler",
		"A: Wrong action id rejected")

	# Unknown node.
	var unk := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", "node_nope"))
	_assert_eq(str(unk.get("reason", "")), "unknown_node", "A: Unknown node rejected")

	# City with no base.
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_a")
	GlobalData.board.current_tile = Vector2i(2, 2)
	var nobe := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", "node_city_a"))
	_assert_eq(str(nobe.get("reason", "")), "no_base_to_defend", "A: Baseless node rejected")

	# Foreign-controlled base with an assault running is not ours to defend.
	var zeon_node := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "safehouse")
	var zeon_terr := CampaignTerritory.register_territory("terr_zeon_a", [zeon_node])
	CampaignTerritory.set_controlled(zeon_terr, "zeon")
	var zeon_base := CampaignBase.register_base("base_zeon_a", zeon_node, "OUTPOST", "zeon", zeon_terr)
	var zeon_inv := CampaignForce.register_force("force_outland_a", "PATROL", "outland", zeon_node)
	CampaignBaseDefense.start_base_attack(zeon_base, zeon_inv)
	GlobalData.board.current_tile = Vector2i(6, 6)
	CampaignPlayerMovement.set_current_node_id(zeon_node)
	var notours := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", zeon_node))
	_assert_eq(str(notours.get("reason", "")), "not_player_base", "A: Foreign base rejected")

	# Own base with no assault running.
	var ctx := _setup_assaulted_base("cta", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var battle_id := str(ctx.get("battle_id", ""))
	CampaignBattle.cancel_battle(battle_id)
	var stale := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", node_id))
	_assert_eq(str(stale.get("reason", "")), "base_not_under_attack",
		"A: Stale (cancelled) assault rejected")

	# Fresh assault, player elsewhere: dispatch-level presence gate.
	var ctx2 := _setup_assaulted_base("ctb", Vector2i(5, 5))
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.current_campaign_player_node_id = ""
	var remote := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", str(ctx2.get("node_id", ""))))
	_assert_eq(str(remote.get("reason", "")), "player_not_at_node",
		"A: Remote node rejected")

	# Failure paths leave zero side effects.
	var snap_before := _take_state_snapshot()
	CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", "node_nope"))
	CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", "node_city_a"))
	_assert_eq(_take_state_snapshot(), snap_before, "A: Failures mutate nothing")

	# Valid defense: full vertical slice through dispatch.
	_setup_clean_campaign_environment()
	GameManager.suppress_scene_change = true
	var ok_ctx := _setup_assaulted_base("ok", Vector2i(7, 7))
	var ok_node := str(ok_ctx.get("node_id", ""))
	var ok_base := str(ok_ctx.get("base_id", ""))
	var ok_battle := str(ok_ctx.get("battle_id", ""))
	var turn_before: int = CampaignTurnExecutive.get_turn()
	var credits_before: int = GlobalData.currency.credits
	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", ok_node))
	_assert_true(bool(res.get("ok", false)), "A: Valid defend succeeds")
	_assert_eq(str(res.get("reason", "")), "defense_started", "A: Reason is defense_started")
	_assert_eq(str(res.get("base_id", "")), ok_base, "A: Receipt names the base")
	_assert_eq(str(res.get("battle_id", "")), ok_battle, "A: Receipt names the battle")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "A: No turn consumed")
	_assert_eq(GlobalData.currency.credits, credits_before, "A: No credits consumed")

	GameManager.suppress_scene_change = false
	GameManager.transition_to(GameManager.State.BOARD)


# ---------------------------------------------------------------------------
# B: Playable battle entry (type, context, loadout authority).
# ---------------------------------------------------------------------------
func _test_battle_entry() -> void:
	_setup_clean_campaign_environment()
	GameManager.suppress_scene_change = true
	var ctx := _setup_assaulted_base("ent", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var battle_id := str(ctx.get("battle_id", ""))
	var loadout_before: Dictionary = GlobalData.weapons.weapon_loadout.duplicate(true)

	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", node_id))
	_assert_true(bool(res.get("ok", false)), "B: Defend dispatch succeeds")

	_assert_eq(str(res.get("combat_type", "")), "grunt", "B: Combat type is the supported grunt value")
	_assert_eq(GameManager.combat_node_type, "grunt", "B: Manager carries the grunt type")
	_assert_eq(GameManager.current_state, GameManager.State.COMBAT,
		"B: Tactical battle entered")
	_assert_eq(str(res.get("session_ref", "")), CampaignBattle.get_session_ref(battle_id),
		"B: Session marker matches the battle record")
	_assert_eq(CampaignBaseDefense.get_pending_defense_battle_id(), battle_id,
		"B: Engagement tracked for result routing")
	_assert_eq(GlobalData.weapons.weapon_loadout, loadout_before,
		"B: Player loadout authority preserved on entry")
	_assert_eq(GlobalData.pre_combat_weapon_loadout, loadout_before,
		"B: Pre-combat snapshot preserved on entry")

	GameManager.suppress_scene_change = false
	GameManager.transition_to(GameManager.State.BOARD)


func _restore_save_backup() -> void:
	CampaignBaseDefense.reset_defense_state()
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
	print("S2-A PLAYER-SIDE BASE DEFENSE VERIFY RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: S2-A player-side base defense contract strictly satisfied.")
	else:
		printerr("FAILED: S2-A player-side base defense has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
