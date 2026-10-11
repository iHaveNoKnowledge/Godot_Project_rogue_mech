class_name CampaignAutoResolveVerify
extends Node

const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")

## ---------------------------------------------------------------------------
## S2-B PHASE 2B — AUTO-RESOLVE EVIDENCE-GATED PATHS
##
## Implements ONLY approved outcomes (no strength comparison, no invented
## formula):
##   B1. Attacker DESTROYED before expiry -> DEFENDER_SUCCESS (resolve +
##       clear, nothing else mutated; zero-strength attackers included).
##   B2. Ordinary expiry (both sides standing) -> DEFERRED awaiting_policy;
##       record stays expired and recoverable, duplicate ticks change nothing.
##   B3. Multiple hostile participants -> DEFERRED, battle/record intact.
##   B4. Departed attacker still attributed via battle participants.
##   B5. DISABLED base -> SKIP (record kept, nothing applied).
##   B6. Stale (non-ACTIVE battle) records drop safely.
##   B7. Tactical resolution and deadline resolution never double-apply.
##   B8. Save/load around expiry applies exactly once.
##   B9. Unverifiable defender -> DEFERRED (GARRISON_ONLY).
##   B10. Mid-assault ownership flip -> DEFERRED (controller pin).
## ---------------------------------------------------------------------------

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN S2-B AUTO-RESOLVE VERIFY (Phase 2B) ---")
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
	GlobalData.current_campaign_player_node_id = ""
	if GlobalData != null and GlobalData.board != null:
		GlobalData.board.current_sector = 1
		GlobalData.board.current_tile = Vector2i(0, 0)
		GlobalData.board.board_patrol_engagement = -1


func _setup_assault(tag: String, tile: Vector2i, turn: int) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_" + tag, [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_" + tag, node_id, "OUTPOST", "federation", terr_id)
	var attacker_id := CampaignForce.register_force("force_zeon_" + tag, "PATROL", "zeon", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var r := CampaignBaseDefense.process_assault_turn(turn)
	var created: Array = r.get("created", [])
	if created.is_empty():
		_assert_true(false, "setup assault for %s" % tag)
		return {}
	return {
		"node_id": node_id, "base_id": base_id, "attacker_id": attacker_id,
		"battle_id": str(created[0]), "deadline": turn + 2,
	}


func _run_all_tests() -> void:
	_test_destroyed_attacker_succeeds()
	_test_ordinary_expiry_defers()
	_test_multi_hostile_defers()
	_test_departed_attacker_attributed()
	_test_disabled_base_skipped()
	_test_stale_drops_safely()
	_test_tactical_and_deadline_exclusive()
	_test_save_load_applies_once()
	_test_unverifiable_defender_defers()
	_test_ownership_flip_defers()
	_test_outcome_notice_once()
	_test_no_false_notice()


# ---------------------------------------------------------------------------
# B1: Attacker DESTROYED -> DEFENDER_SUCCESS (incl. zero-strength attacker).
# ---------------------------------------------------------------------------
func _test_destroyed_attacker_succeeds() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b1", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	_assert_eq(int(CampaignForce.describe_composition(attacker_id).get("strength", -1)), 0,
		"B1: Attacker strength is zero (valid, not missing)")
	_assert_true(CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DESTROYED),
		"B1: Attacker destroyed before expiry")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(r.get("auto_resolved", []),
		[{"battle_id": battle_id, "outcome": "defender_success"}],
		"B1: Defender success applied")
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"B1: Battle RESOLVED")
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B1: Record cleared after successful resolution")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE,
		"B1: Base untouched")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"B1: Controller untouched")
	_assert_eq(CampaignBattle.get_session_ref(battle_id), "", "B1: Session cleared")


# ---------------------------------------------------------------------------
# B2: Ordinary expiry with one verified ACTIVE attacker applies the approved
# attacker-success outcome (Option D): resolve + DISABLED base, controller
# preserved, attacker itself untouched, record cleared, repeat is a no-op.
# ---------------------------------------------------------------------------
func _test_ordinary_expiry_defers() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b2", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(r.get("expired_marked", []), [battle_id], "B2: Expiry marked")
	_assert_eq(r.get("auto_resolved", []),
		[{"battle_id": battle_id, "outcome": "attacker_success"}],
		"B2: Attacker success applied")
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"B2: Battle RESOLVED")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.DISABLED,
		"B2: Base DISABLED")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"B2: Controller preserved")
	_assert_eq(CampaignForce.get_state(attacker_id), CampaignForce.ForceState.ACTIVE,
		"B2: Attacker itself untouched")
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B2: Record cleared after application")

	var r2 := CampaignBaseDefense.process_assault_turn(9)
	_assert_true((r2.get("auto_resolved", []) as Array).is_empty(),
		"B2: Repeat tick applies nothing")
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B2: Record stays cleared")


# ---------------------------------------------------------------------------
# B3: Multiple hostile participants -> DEFER (no aggregation).
# ---------------------------------------------------------------------------
func _test_multi_hostile_defers() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b3", Vector2i(4, 4), 5)
	var node_id := str(ctx.get("node_id", ""))
	var battle_id := str(ctx.get("battle_id", ""))
	var outland_id := CampaignForce.register_force("force_outland_b3", "SCAVENGER", "outland", node_id)
	FactionSystem.set_relation("federation", "outland", FactionSystem.Relation.HOSTILE)
	_assert_true(CampaignBattle.add_participant(battle_id, outland_id),
		"B3: Second hostile joins the battle")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r.get("auto_resolved", []) as Array).is_empty(),
		"B3: No outcome with two hostile factions")
	_assert_eq(r.get("deferred", []),
		[{"battle_id": battle_id, "reason": "multi_or_no_attacker"}],
		"B3: Deferred with multi-hostile diagnostic")
	_assert_true(CampaignBattle.is_active(battle_id), "B3: Battle intact")
	_assert_eq(CampaignForce.get_state(outland_id), CampaignForce.ForceState.ACTIVE,
		"B3: Unrelated force untouched")


# ---------------------------------------------------------------------------
# B4: Departed attacker still attributed via battle participants.
# ---------------------------------------------------------------------------
func _test_departed_attacker_attributed() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b4", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "safehouse")
	_assert_true(CampaignForce.set_node(attacker_id, "node_s1_safehouse_9_9"),
		"B4: Attacker leaves the assault node")
	_assert_true(CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DESTROYED),
		"B4: Departed attacker destroyed")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(r.get("auto_resolved", []),
		[{"battle_id": battle_id, "outcome": "defender_success"}],
		"B4: Departed attacker still resolved via participants")
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"B4: Battle RESOLVED")


# ---------------------------------------------------------------------------
# B5: DISABLED base -> SKIP, record kept, nothing applied.
# ---------------------------------------------------------------------------
func _test_disabled_base_skipped() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b5", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	_assert_true(CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED),
		"B5: Base DISABLED before expiry")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r.get("auto_resolved", []) as Array).is_empty(),
		"B5: Nothing applied to a DISABLED base")
	_assert_eq(r.get("deferred", []),
		[{"battle_id": battle_id, "reason": "base_not_active"}],
		"B5: Deferred with base_not_active diagnostic")
	_assert_false(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B5: Record kept for recovery")
	_assert_true(CampaignBattle.is_active(battle_id), "B5: Battle intact")


# ---------------------------------------------------------------------------
# B6: Stale records (non-ACTIVE battle) drop safely.
# ---------------------------------------------------------------------------
func _test_stale_drops_safely() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b6", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	_assert_true(CampaignBattle.resolve_battle(battle_id), "B6: Battle resolved manually")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r.get("auto_resolved", []) as Array).is_empty(),
		"B6: Nothing applied to a stale record")
	_assert_eq(r.get("dropped_stale", []), [battle_id], "B6: Stale record dropped")
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B6: Record gone")


# ---------------------------------------------------------------------------
# B7: Tactical and deadline resolution never double-apply.
# ---------------------------------------------------------------------------
func _test_tactical_and_deadline_exclusive() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b7", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var node_id := str(ctx.get("node_id", ""))
	GlobalData.board.current_tile = Vector2i(4, 4)
	CampaignPlayerMovement.set_current_node_id(node_id)
	CampaignBaseDefense.ensure_defense_result_hook()

	# Tactical victory first: applier consumes and clears the record.
	CampaignBaseDefense.intervene(battle_id)
	CampaignBaseDefense.record_defense_engagement(battle_id, base_id)
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"B7: Tactical victory resolved")
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B7: Record cleared by tactical resolution")

	# A later expiration tick finds nothing to do.
	var r := CampaignBaseDefense.process_assault_turn(9)
	_assert_true((r.get("auto_resolved", []) as Array).is_empty(),
		"B7: Deadline pass applies nothing after tactical resolution")
	_assert_true((r.get("deferred", []) as Array).is_empty(),
		"B7: No phantom deferral either")

	# Reverse order on a still-deferred assault: expire first (DISABLED
	# attacker defers), then a tactical result still applies exactly once.
	_setup_clean_campaign_environment()
	var ctx2 := _setup_assault("b7b", Vector2i(4, 4), 5)
	var battle2 := str(ctx2.get("battle_id", ""))
	var node2 := str(ctx2.get("node_id", ""))
	var attacker2 := str(ctx2.get("attacker_id", ""))
	CampaignForce.set_state(attacker2, CampaignForce.ForceState.DISABLED)
	GlobalData.board.current_tile = Vector2i(4, 4)
	CampaignPlayerMovement.set_current_node_id(node2)
	CampaignBaseDefense.process_assault_turn(8)
	_assert_true(CampaignBaseDefense.is_assault_expired(battle2),
		"B7: Assault expired but deferred")
	CampaignBaseDefense.intervene(battle2)
	CampaignBaseDefense.record_defense_engagement(battle2, str(ctx2.get("base_id", "")))
	CampaignBaseDefense.ensure_defense_result_hook()
	EventBus.combat_ended.emit(true)
	_assert_eq(CampaignBattle.get_state(battle2), CampaignBattle.BattleState.RESOLVED,
		"B7: Tactical result still applies to an expired battle")
	_assert_true(CampaignBaseDefense.get_assault(battle2).is_empty(),
		"B7: Record cleared exactly once")


# ---------------------------------------------------------------------------
# B8: Save/load around expiry applies exactly once.
# ---------------------------------------------------------------------------
func _test_save_load_applies_once() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b8", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	_assert_true(SaveGameIO.save_run(), "B8: Save with live assault succeeds")
	CampaignBaseDefense.reset_defense_state()
	_assert_true(SaveGameIO.load_run(), "B8: Load restores the live assault")
	_assert_false(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"B8: Record survived load")
	_assert_false(CampaignBaseDefense.is_assault_expired(battle_id),
		"B8: Not yet expired after load")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(r.get("auto_resolved", []),
		[{"battle_id": battle_id, "outcome": "attacker_success"}],
		"B8: Recovered expiry applies once")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.DISABLED,
		"B8: Base DISABLED by the recovered application")
	var r2 := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r2.get("auto_resolved", []) as Array).is_empty(),
		"B8: Second pass applies nothing")


# ---------------------------------------------------------------------------
# B9: Unverifiable defender -> DEFER (GARRISON_ONLY).
# ---------------------------------------------------------------------------
func _test_unverifiable_defender_defers() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b9", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	for fid in CampaignBattle.get_participants(battle_id):
		if str(fid) != attacker_id:
			CampaignForce.set_faction(str(fid), "outland")
			CampaignForce.set_base(str(fid), "")
	FactionSystem.set_relation("federation", "outland", FactionSystem.Relation.NEUTRAL)
	CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DESTROYED)

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r.get("auto_resolved", []) as Array).is_empty(),
		"B9: No outcome without a verifiable defender")
	_assert_eq(r.get("deferred", []),
		[{"battle_id": battle_id, "reason": "no_verified_defender"}],
		"B9: Deferred with defender diagnostic")
	_assert_true(CampaignBattle.is_active(battle_id), "B9: Battle intact")


# ---------------------------------------------------------------------------
# B10: Mid-assault ownership flip -> DEFER (controller pin).
# ---------------------------------------------------------------------------
func _test_ownership_flip_defers() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("b10", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	_assert_true(CampaignBase.set_controller(base_id, "zeon"),
		"B10: Controller flipped mid-assault")

	var r := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r.get("auto_resolved", []) as Array).is_empty(),
		"B10: No outcome after ownership flip")
	_assert_eq(r.get("deferred", []),
		[{"battle_id": battle_id, "reason": "ownership_changed"}],
		"B10: Deferred with ownership diagnostic")
	_assert_true(CampaignBattle.is_active(battle_id), "B10: Battle intact")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "zeon",
		"B10: Flipped controller preserved (never reverted)")


var _notices: Array = []


func _on_test_notice(event: Dictionary) -> void:
	_notices.append(event)


func _watch_notices() -> void:
	if not EventBus.event_triggered.is_connected(_on_test_notice):
		EventBus.event_triggered.connect(_on_test_notice)
	_notices.clear()


func _unwatch_notices() -> void:
	if EventBus.event_triggered.is_connected(_on_test_notice):
		EventBus.event_triggered.disconnect(_on_test_notice)
	_notices.clear()


# ---------------------------------------------------------------------------
# C: One notice per applied outcome; never for deferred/skipped assaults.
# ---------------------------------------------------------------------------
func _test_outcome_notice_once() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("c1", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	_watch_notices()

	CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(_notices.size(), 1, "C: Exactly one notice emitted")
	_assert_eq(str(_notices[0].get("name", "")), "BASE DEFENSE LOST",
		"C: Defeat notice names the outcome")
	_assert_true(str(_notices[0].get("desc", "")).contains(base_id),
		"C: Notice identifies the verified base")

	CampaignBaseDefense.process_assault_turn(9)
	_assert_eq(_notices.size(), 1, "C: Repeat tick emits no duplicate")

	_assert_true(SaveGameIO.save_run(), "C: Save after outcome succeeds")
	CampaignBaseDefense.reset_defense_state()
	_assert_true(SaveGameIO.load_run(), "C: Load succeeds")
	CampaignBaseDefense.process_assault_turn(9)
	_assert_eq(_notices.size(), 1, "C: Save/load causes no duplicate notice")
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"C: Battle stays RESOLVED")
	_unwatch_notices()


func _test_no_false_notice() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_assault("c2", Vector2i(4, 4), 5)
	var battle_id := str(ctx.get("battle_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DISABLED)
	_watch_notices()

	CampaignBaseDefense.process_assault_turn(8)
	_assert_true(_notices.is_empty(), "C: Deferred assault emits no notice")
	_assert_true(CampaignBattle.is_active(battle_id), "C: Battle still ACTIVE")
	_unwatch_notices()


func _restore_save_backup() -> void:
	_unwatch_notices()
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
	print("S2-B AUTO-RESOLVE VERIFY RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: S2-B auto-resolve evidence-gated paths strictly satisfied.")
	else:
		printerr("FAILED: S2-B auto-resolve has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
