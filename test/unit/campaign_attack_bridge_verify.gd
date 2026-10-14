class_name CampaignAttackBridgeVerify
extends Node

## ---------------------------------------------------------------------------
## Phase 2H-B Gate 2 + Gate 3A — ATTACK BRIDGE VERIFICATION.
##
## Gate 2 proved pending/result routing with the bridge dormant. Gate 3A wires
## production entry (dispatch records pending, connects the hook, and enters
## tactical combat) plus entry mutual exclusion against defense engagements:
##   A. Pending registration and identity (record/reject/evict).
##   B. Result isolation (session mismatch, missing, duplicate, stale).
##   C. Victory settlement (verified targets only, exactly once).
##   D. Non-victory results (defeat consumes, escape clears, all inert).
##   E. Reward boundary (no payout path; standalone board path untouched).
##   F. Isolation (defense pending, battle schema) + Gate 3A entry wiring.
##   G. Entry mutual exclusion (attack vs defense, both directions).
## ---------------------------------------------------------------------------

const CampaignAttackBridge = preload("res://scripts/systems/campaign_attack_bridge.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN GATE 2 ATTACK BRIDGE VERIFY ---")
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
	CampaignAttackBridge.reset_attack_state()
	# Gate 3A: entry tests reach tactical combat; suppress the real scene swap
	# in headless runs (same pattern as the defend suite).
	GameManager.suppress_scene_change = true
	GlobalData.current_campaign_player_node_id = ""
	if GlobalData != null:
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(0, 0)
			GlobalData.board.board_patrol_engagement = -1
		if GlobalData.currency != null:
			GlobalData.currency.credits = 1000
			GlobalData.currency.scrap = 50


## Builds an ACTIVE attack-style battle and returns its ids.
func _setup_attack_battle(tag: String, tile: Vector2i, factions: Array = ["zeon"]) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "city")
	var fids: Array = []
	var i := 0
	for fac in factions:
		var fid := CampaignForce.register_force("force_%s_%s" % [str(fac), tag], "PATROL", str(fac), node_id)
		fids.append(fid)
		i += 1
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	FactionSystem.set_relation("federation", "outland", FactionSystem.Relation.HOSTILE)
	var battle_id := CampaignBattle.make_battle_id(1, "atk_" + node_id)
	CampaignBattle.register_battle(battle_id, node_id, fids)
	CampaignBattle.prepare_launch(battle_id)
	return {"node_id": node_id, "battle_id": battle_id, "targets": fids}


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"turn": CampaignTurnExecutive.get_turn(),
	}


func _run_all_tests() -> void:
	_test_pending_registration()
	_test_pending_rejection()
	_test_result_isolation()
	_test_victory_settlement()
	_test_non_victory_results()
	_test_reward_boundary()
	_test_isolation_compatibility()
	_test_entry_mutual_exclusion()
	_test_abandon_and_reset_cleanup()


# ---------------------------------------------------------------------------
# A. Pending registration and identity.
# ---------------------------------------------------------------------------
func _test_pending_registration() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_attack_battle("a1", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))
	var targets: Array = ctx.get("targets", [])

	_assert_true(CampaignAttackBridge.record_attack_engagement(battle_id, targets),
		"A: Eligible ACTIVE battle records")
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), battle_id,
		"A: Pending slot tracks the battle")
	_assert_eq(CampaignBattle.get_session_ref(battle_id),
		"session_attack_" + battle_id, "A: Session marker written to the battle")
	# Re-recording the same battle refreshes without error.
	_assert_true(CampaignAttackBridge.record_attack_engagement(battle_id, targets),
		"A: Same-battle re-record refreshes")


func _test_pending_rejection() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_attack_battle("a2", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))

	_assert_false(CampaignAttackBridge.record_attack_engagement("", ["force_x"]),
		"A: Empty battle id rejected")
	_assert_false(CampaignAttackBridge.record_attack_engagement("battle_nope", ["force_x"]),
		"A: Unknown battle rejected")
	_assert_false(CampaignAttackBridge.record_attack_engagement(battle_id, []),
		"A: Empty targets rejected")
	_assert_false(CampaignAttackBridge.record_attack_engagement(battle_id, ["force_nope"]),
		"A: Unknown force rejected")
	_assert_false(CampaignAttackBridge.record_attack_engagement(battle_id, ["force_dup", "force_dup"]),
		"A: Duplicate targets rejected")
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"A: Slot stays empty after rejections")

	# Non-ACTIVE battle rejected (PLANNED here).
	var node2 := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "city")
	var f2 := CampaignForce.register_force("force_zeon_a2b", "PATROL", "zeon", node2)
	var planned_id := CampaignBattle.make_battle_id(1, "atk_" + node2)
	CampaignBattle.register_battle(planned_id, node2, [f2])
	_assert_false(CampaignAttackBridge.record_attack_engagement(planned_id, [f2]),
		"A: PLANNED battle rejected")

	# Conflicting pending for a different battle is rejected, not overwritten.
	_assert_true(CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", [])),
		"A: First battle records")
	var node3 := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	var f3 := CampaignForce.register_force("force_zeon_a2c", "PATROL", "zeon", node3)
	var other_id := CampaignBattle.make_battle_id(1, "atk_" + node3)
	CampaignBattle.register_battle(other_id, node3, [f3])
	CampaignBattle.prepare_launch(other_id)
	_assert_false(CampaignAttackBridge.record_attack_engagement(other_id, [f3]),
		"A: Conflicting pending rejected, existing kept")
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), battle_id,
		"A: Original pending intact")


# ---------------------------------------------------------------------------
# B. Result isolation.
# ---------------------------------------------------------------------------
func _test_result_isolation() -> void:
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx := _setup_attack_battle("b1", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))
	var snap_before := _take_state_snapshot()

	# No pending: unrelated combat result ignored.
	EventBus.combat_ended.emit(true)
	_assert_eq(_take_state_snapshot(), snap_before, "B: No pending means zero mutation")

	# Session mismatch: pending retained, battle untouched.
	CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", []))
	CampaignBattle.set_session_ref(battle_id, "session_tampered")
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), battle_id,
		"B: Session mismatch retains pending")
	_assert_true(CampaignBattle.is_active(battle_id), "B: Battle untouched on mismatch")

	# Duplicate result after a valid consumption is harmless (covered in C;
	# here: consume manually, then emit).
	CampaignBaseDefense.reset_defense_state()
	CampaignAttackBridge.reset_attack_state()
	var ctx2 := _setup_attack_battle("b2", Vector2i(5, 5))
	var battle2 := str(ctx2.get("battle_id", ""))
	CampaignAttackBridge.record_attack_engagement(battle2, ctx2.get("targets", []))
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignBattle.get_state(battle2), CampaignBattle.BattleState.RESOLVED,
		"B: First delivery resolves")
	var snap_mid := _take_state_snapshot()
	EventBus.combat_ended.emit(true)
	_assert_eq(_take_state_snapshot(), snap_mid, "B: Duplicate delivery changes nothing")

	# Stale result (RESOLVED battle, leftover pending slot): rebuild a stale
	# slot by hand is impossible through the API (record requires ACTIVE),
	# so resolve-then-emit must find nothing to consume.
	EventBus.combat_ended.emit(false)
	_assert_eq(_take_state_snapshot(), snap_mid, "B: Stale delivery changes nothing")


# ---------------------------------------------------------------------------
# C. Victory settlement.
# ---------------------------------------------------------------------------
func _test_victory_settlement() -> void:
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx := _setup_attack_battle("c1", Vector2i(4, 4), ["zeon", "outland"])
	var battle_id := str(ctx.get("battle_id", ""))
	var z1 := "force_zeon_c1"
	var o1 := "force_outland_c1"
	CampaignAttackBridge.record_attack_engagement(battle_id, [z1, o1])

	# One target already dead: skipped, the other still destroyed.
	CampaignForce.set_state(o1, CampaignForce.ForceState.DESTROYED)
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignForce.get_state(z1), CampaignForce.ForceState.DESTROYED,
		"C: Verified target destroyed")
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"C: Battle RESOLVED exactly once")
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"C: Pending consumed")
	_assert_eq(CampaignBattle.get_session_ref(battle_id), "", "C: Session cleared")

	# Faction-flipped target is skipped, not destroyed.
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx2 := _setup_attack_battle("c2", Vector2i(4, 4))
	var battle2 := str(ctx2.get("battle_id", ""))
	var f2 := str((ctx2.get("targets", []) as Array)[0])
	CampaignForce.set_faction(f2, "federation")
	CampaignAttackBridge.record_attack_engagement(battle2, [f2])
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignForce.get_state(f2), CampaignForce.ForceState.ACTIVE,
		"C: Flipped target spared")
	_assert_true(CampaignBattle.is_active(battle2),
		"C: Battle left ACTIVE when no target verifies (deferred)")

	# Zero valid targets defers without consuming.
	CampaignAttackBridge.reset_attack_state()
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx3 := _setup_attack_battle("c3", Vector2i(4, 4))
	var battle3 := str(ctx3.get("battle_id", ""))
	var f3 := str((ctx3.get("targets", []) as Array)[0])
	CampaignForce.set_state(f3, CampaignForce.ForceState.DESTROYED)
	CampaignAttackBridge.record_attack_engagement(battle3, [f3])
	EventBus.combat_ended.emit(true)
	_assert_true(CampaignBattle.is_active(battle3),
		"C: All-dead targets defer (battle ACTIVE)")


# ---------------------------------------------------------------------------
# D. Non-victory results.
# ---------------------------------------------------------------------------
func _test_non_victory_results() -> void:
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx := _setup_attack_battle("d1", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))
	var fid := str((ctx.get("targets", []) as Array)[0])
	CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", []))

	EventBus.combat_ended.emit(false)
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"D: Defeat consumes pending")
	_assert_true(CampaignBattle.is_active(battle_id), "D: Battle stays ACTIVE")
	_assert_eq(CampaignForce.get_state(fid), CampaignForce.ForceState.ACTIVE,
		"D: Forces unchanged on defeat")

	# Escape clears pending without mutation; a later unrelated victory
	# cannot consume the old session (the cross-talk fix).
	CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", []))
	EventBus.combat_escaped.emit()
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"D: Escape clears pending")
	_assert_true(CampaignBattle.is_active(battle_id), "D: Battle stays ACTIVE")
	var snap_before := _take_state_snapshot()
	EventBus.combat_ended.emit(true)
	_assert_eq(_take_state_snapshot(), snap_before,
		"D: Post-escape unrelated victory changes nothing")


# ---------------------------------------------------------------------------
# E. Reward boundary.
# ---------------------------------------------------------------------------
func _test_reward_boundary() -> void:
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx := _setup_attack_battle("e1", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))
	CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", []))
	var credits_before: int = GlobalData.currency.credits
	var scrap_before: int = GlobalData.currency.scrap

	EventBus.combat_ended.emit(true)
	_assert_eq(GlobalData.currency.credits, credits_before,
		"E: Bridge victory pays no credits")
	_assert_eq(GlobalData.currency.scrap, scrap_before, "E: Bridge victory pays no scrap")

	var src := FileAccess.get_file_as_string("res://scripts/systems/campaign_attack_bridge.gd")
	_assert_false(src.contains("gain_credits") or src.contains("gain_scrap"),
		"E: Bridge source has no payout path")


# ---------------------------------------------------------------------------
# F. Isolation and compatibility.
# ---------------------------------------------------------------------------
func _test_isolation_compatibility() -> void:
	_setup_clean_campaign_environment()
	# Defense pending is untouched by the attack applier.
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_f1", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_f1", node_id, "OUTPOST", "federation", terr_id)
	var atk := CampaignForce.register_force("force_zeon_f1", "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var def_battle := CampaignBaseDefense.start_base_attack(base_id, atk)
	var def_bid := str(def_battle.get("battle_id", ""))
	CampaignBaseDefense.ensure_defense_result_hook()
	CampaignAttackBridge.ensure_attack_result_hook()

	# An unrelated attack victory elsewhere leaves the defense battle alone
	# (no defense pending exists here; the defense applier ignores it).
	var node2 := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	var g2 := CampaignForce.register_force("force_zeon_f2", "PATROL", "zeon", node2)
	var atk_battle := CampaignBattle.make_battle_id(1, "atk_" + node2)
	CampaignBattle.register_battle(atk_battle, node2, [g2])
	CampaignBattle.prepare_launch(atk_battle)
	CampaignAttackBridge.record_attack_engagement(atk_battle, [g2])
	EventBus.combat_ended.emit(true)
	_assert_true(CampaignBattle.is_active(def_bid), "F: Defense battle untouched")
	_assert_eq(CampaignBattle.get_state(atk_battle), CampaignBattle.BattleState.RESOLVED,
		"F: Attack battle resolved")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"F: Base ownership untouched by attack victory")

	# Battle records keep the locked 5-key schema (no roles smuggled in).
	for b in CampaignBattle.get_battles():
		var keys: Array = (b as Dictionary).keys()
		keys.sort()
		_assert_eq(keys, ["id", "node_id", "participants", "session_ref", "state"],
			"F: Battle schema unchanged")

	# Gate 3A: attack dispatch wires entry — records pending, connects the
	# result hook, and enters tactical combat (scene swap suppressed here).
	CampaignAttackBridge.reset_attack_state()
	_setup_clean_campaign_environment()
	var ctx2 := _setup_attack_battle("f2", Vector2i(4, 4))
	var f2_battle := str(ctx2.get("battle_id", ""))
	var f2_node := str(ctx2.get("node_id", ""))
	CampaignPlayerMovement.set_current_node_id(f2_node)
	GlobalData.board.current_tile = Vector2i(4, 4)
	var res := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", f2_node))
	_assert_true(bool(res.get("ok", false)), "F: Attack dispatch succeeds")
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), f2_battle,
		"F: Dispatch records bridge pending")
	_assert_eq(CampaignBattle.get_session_ref(f2_battle),
		"session_attack_" + f2_battle, "F: Dispatch stamps the session marker")
	_assert_eq(GameManager.current_state, GameManager.State.COMBAT,
		"F: Dispatch enters tactical combat")
	_assert_eq(GameManager.combat_node_type, "grunt",
		"F: Attack combat type is grunt")
	GameManager.transition_to(GameManager.State.BOARD)


# ---------------------------------------------------------------------------
# G. Entry mutual exclusion (Gate 3A): at most one campaign-result pending
# session is ever live. Attack entry is rejected while a defense engagement
# is tracked, and defense intervention is rejected while an attack is tracked.
# Both rejections are read-only (zero battle/force mutation).
# ---------------------------------------------------------------------------
func _test_entry_mutual_exclusion() -> void:
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	CampaignBaseDefense.ensure_defense_result_hook()

	# Live defense engagement: player base under assault, intervention
	# recorded (the production defend path up to combat entry).
	var home := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse")
	var home_terr := CampaignTerritory.register_territory("terr_g_home", [home])
	CampaignTerritory.set_controlled(home_terr, "federation")
	var home_base := CampaignBase.register_base("base_g_home", home, "OUTPOST", "federation", home_terr)
	var besieger := CampaignForce.register_force("force_zeon_g1", "PATROL", "zeon", home)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	CampaignPlayerMovement.set_current_node_id(home)
	GlobalData.board.current_tile = Vector2i(4, 4)
	var assault := CampaignBaseDefense.start_base_attack(home_base, besieger)
	_assert_true(bool(assault.get("ok", false)), "G: Defense assault starts")
	var def_battle := str(assault.get("battle_id", ""))
	_assert_true(bool(CampaignBaseDefense.intervene(def_battle).get("ok", false)),
		"G: Defense intervention starts")
	_assert_true(CampaignBaseDefense.record_defense_engagement(def_battle, home_base),
		"G: Defense engagement recorded")

	# Attack entry elsewhere is rejected while the defense is live.
	var far := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city")
	CampaignForce.register_force("force_zeon_g2", "PATROL", "zeon", far)
	CampaignPlayerMovement.set_current_node_id(far)
	GlobalData.board.current_tile = Vector2i(7, 7)
	var battles_before := CampaignBattle.get_battles().size()
	var blocked := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", far))
	_assert_false(bool(blocked.get("ok", false)), "G: Attack blocked during live defense")
	_assert_eq(str(blocked.get("reason", "")), "defense_engagement_active",
		"G: Block reason is defense_engagement_active")
	_assert_eq(CampaignBattle.get_battles().size(), battles_before,
		"G: Blocked attack creates no battle")

	# The defense combat ends in victory (production exit path): the assault
	# resolves and entry frees for the attack.
	CampaignPlayerMovement.set_current_node_id(home)
	GlobalData.board.current_tile = Vector2i(4, 4)
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"G: No attack pending leaks from the defense result")
	CampaignPlayerMovement.set_current_node_id(far)
	GlobalData.board.current_tile = Vector2i(7, 7)
	var allowed := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", far))
	_assert_true(bool(allowed.get("ok", false)), "G: Attack succeeds after defense ends")
	var atk_battle := str(allowed.get("battle_id", ""))
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), atk_battle,
		"G: Attack engagement recorded")

	# Mirror: defense intervention is rejected while the attack is live.
	var besieger2 := CampaignForce.register_force("force_zeon_g3", "PATROL", "zeon", home)
	var assault2 := CampaignBaseDefense.start_base_attack(home_base, besieger2)
	_assert_true(bool(assault2.get("ok", false)), "G: Second defense assault starts")
	var blocked_def := CampaignBaseDefense.intervene(str(assault2.get("battle_id", "")))
	_assert_false(bool(blocked_def.get("ok", false)), "G: Defense blocked during live attack")
	_assert_eq(str(blocked_def.get("reason", "")), "attack_engagement_active",
		"G: Block reason is attack_engagement_active")

	CampaignAttackBridge.reset_attack_state()
	CampaignBaseDefense.reset_defense_state()
	GameManager.transition_to(GameManager.State.BOARD)


# ---------------------------------------------------------------------------
# H. Signal-less exit + run-reset cleanup (Gate 3A-FIX): pause Abandon
# (return_to_board) and Main Menu (game_over) drop only the attack pending
# slot — no fabricated result, no battle resolution, no force mutation.
# reset_run_data clears bridge state. Header documents the wired lifecycle.
# ---------------------------------------------------------------------------
func _test_abandon_and_reset_cleanup() -> void:
	_setup_clean_campaign_environment()
	CampaignAttackBridge.ensure_attack_result_hook()
	var ctx := _setup_attack_battle("h1", Vector2i(4, 4))
	var battle_id := str(ctx.get("battle_id", ""))
	var fid := str((ctx.get("targets", []) as Array)[0])
	_assert_true(CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", [])),
		"H: Engagement recorded")

	# Pause Abandon path: pending dropped, everything else intact.
	GameManager.return_to_board()
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"H: Abandon clears attack pending")
	_assert_true(CampaignBattle.is_active(battle_id),
		"H: Battle stays ACTIVE (no resolution on abandon)")
	_assert_eq(CampaignForce.get_state(fid), CampaignForce.ForceState.ACTIVE,
		"H: Forces untouched on abandon")
	_assert_eq(CampaignBattle.get_session_ref(battle_id), "session_attack_" + battle_id,
		"H: Session marker kept (same battle retry-able)")
	_assert_eq(GameManager.current_state, GameManager.State.BOARD,
		"H: Returned to board")

	# A later unrelated victory cannot consume the abandoned session.
	var snap_before := _take_state_snapshot()
	EventBus.combat_ended.emit(true)
	_assert_eq(_take_state_snapshot(), snap_before,
		"H: Post-abandon victory changes nothing")

	# Same-battle re-entry still works after abandon.
	_assert_true(CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", [])),
		"H: Same battle re-records after abandon")

	# Main Menu path clears too, without resolving or mutating.
	GameManager.game_over()
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"H: game_over clears attack pending")
	_assert_true(CampaignBattle.is_active(battle_id),
		"H: Battle stays ACTIVE on game_over")
	_assert_eq(GameManager.current_state, GameManager.State.MENU,
		"H: game_over reaches menu")
	GameManager.transition_to(GameManager.State.BOARD)

	# Full run reset clears bridge state (battles cleared with it).
	_assert_true(CampaignAttackBridge.record_attack_engagement(battle_id, ctx.get("targets", [])),
		"H: Engagement re-recorded before reset")
	GlobalData.reset_run_data()
	_assert_eq(CampaignAttackBridge.get_pending_attack_battle_id(), "",
		"H: reset_run_data clears attack pending")
	_assert_true(CampaignBattle.get_battles().is_empty(),
		"H: reset_run_data clears battles as before")

	# Header documents the wired lifecycle (no stale dormancy claim).
	var src := FileAccess.get_file_as_string("res://scripts/systems/campaign_attack_bridge.gd")
	_assert_false(src.contains("NO tactical entry wiring"),
		"H: Stale dormancy claim gone")
	_assert_true(src.contains("does NOT provide perfect encounter"),
		"H: Identity limitation documented")


func _restore_save_backup() -> void:
	CampaignAttackBridge.reset_attack_state()
	CampaignBaseDefense.reset_defense_state()
	GameManager.suppress_scene_change = false
	GameManager.transition_to(GameManager.State.BOARD)
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
	print("CAMPAIGN ATTACK BRIDGE VERIFY RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Gate 2 attack bridge contract strictly satisfied.")
	else:
		printerr("FAILED: Gate 2 attack bridge has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
