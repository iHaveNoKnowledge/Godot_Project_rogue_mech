class_name CampaignAssaultSchedulingVerify
extends Node

## ---------------------------------------------------------------------------
## S2-B PHASE 2A — ASSAULT SCHEDULING, ABSOLUTE DEADLINE & PERSISTENCE
##
## Verifies (no auto-resolve outcomes in this phase by gate order):
##   T1. Hostile ACTIVE force co-located with an eligible player base starts
##       exactly one assault (ACTIVE battle + record with deadline = T+2).
##   T2. Friendly/neutral forces never trigger.
##   T3. Inactive/destroyed forces are ignored.
##   T4. Repeated scans never duplicate records or battles.
##   T5. Exact T+2 boundary; expiration marks without mutating battle/base/force.
##   T6. Retreat and re-intervention preserve the original deadline.
##   T7. Counter-only turns skip scheduling and expiration.
##   T8. Executive integration: day-boundary phase runs with receipt key.
##   T9. Save/load preserves assault identity and deadline.
##   T10. Legacy payloads (no key) and malformed rows fail safely.
##   T11. Expired-but-unresolved assaults stay recoverable, never vanish.
## ---------------------------------------------------------------------------

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN S2-B ASSAULT SCHEDULING VERIFY (Phase 2A) ---")
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
	CampaignAttackBridge.reset_attack_state()
	GlobalData.current_campaign_player_node_id = ""
	if GlobalData != null and GlobalData.board != null:
		GlobalData.board.current_sector = 1
		GlobalData.board.current_tile = Vector2i(0, 0)
		GlobalData.board.board_patrol_engagement = -1


## Registers one federation OUTPOST base and returns its ids.
func _setup_player_base(tag: String, tile: Vector2i) -> Dictionary:
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_" + tag, [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_" + tag, node_id, "OUTPOST", "federation", terr_id)
	return {"node_id": node_id, "base_id": base_id}


func _add_force(tag: String, faction: String, node_id: String) -> String:
	return CampaignForce.register_force("force_" + tag, "PATROL", faction, node_id)


func _take_state_snapshot() -> Dictionary:
	return {
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"turn": CampaignTurnExecutive.get_turn(),
	}


func _run_all_tests() -> void:
	_test_hostile_triggers_single_assault()
	_test_friendly_neutral_ignored()
	_test_inactive_forces_ignored()
	_test_repeat_scans_idempotent()
	_test_deadline_boundary()
	_test_retreat_preserves_deadline()
	_test_counter_only_turn_skips()
	_test_executive_integration()
	_test_save_load_preserves()
	_test_legacy_and_malformed_safe()
	_test_expired_unresolved_recoverable()
	_test_repeat_assault_identity()


# ---------------------------------------------------------------------------
# T1: Hostile ACTIVE force at a player base starts exactly one assault.
# ---------------------------------------------------------------------------
func _test_hostile_triggers_single_assault() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t1", Vector2i(4, 4))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_add_force("zeon_t1", "zeon", str(ctx.get("node_id", "")))

	var r := CampaignBaseDefense.process_assault_turn(5)
	var created: Array = r.get("created", [])
	_assert_eq(created.size(), 1, "T1: Exactly one assault created")
	var battle_id := str(created[0]) if not created.is_empty() else ""
	_assert_true(CampaignBattle.is_active(battle_id), "T1: Assault battle is ACTIVE")
	var rec := CampaignBaseDefense.get_assault(battle_id)
	_assert_eq(str(rec.get("base_id", "")), str(ctx.get("base_id", "")), "T1: Record names the base")
	_assert_eq(int(rec.get("created_turn", -1)), 5, "T1: Creation turn stamped")
	_assert_eq(int(rec.get("deadline_turn", -1)), 7, "T1: Deadline is T+2")
	_assert_false(bool(rec.get("expired", true)), "T1: Fresh assault not expired")


# ---------------------------------------------------------------------------
# T2: Friendly and neutral forces never trigger.
# ---------------------------------------------------------------------------
func _test_friendly_neutral_ignored() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t2", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	_add_force("fed_t2", "federation", node_id)
	_add_force("out_t2", "outland", node_id)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)

	var r := CampaignBaseDefense.process_assault_turn(5)
	_assert_true((r.get("created", []) as Array).is_empty(), "T2: No assault from friendly/neutral forces")
	_assert_true(CampaignBaseDefense.get_assaults().is_empty(), "T2: No assault records")
	_assert_true(CampaignBattle.get_battles().is_empty(), "T2: No battles created")


# ---------------------------------------------------------------------------
# T3: Inactive and destroyed forces are ignored.
# ---------------------------------------------------------------------------
func _test_inactive_forces_ignored() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t3", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var dis_id := _add_force("zeon_dis", "zeon", node_id)
	var des_id := _add_force("zeon_des", "zeon", node_id)
	CampaignForce.set_state(dis_id, CampaignForce.ForceState.DISABLED)
	CampaignForce.set_state(des_id, CampaignForce.ForceState.DESTROYED)

	var r := CampaignBaseDefense.process_assault_turn(5)
	_assert_true((r.get("created", []) as Array).is_empty(), "T3: No assault from inactive forces")
	_assert_true(CampaignBattle.get_battles().is_empty(), "T3: No battles created")


# ---------------------------------------------------------------------------
# T4: Repeated scans never duplicate records or battles.
# ---------------------------------------------------------------------------
func _test_repeat_scans_idempotent() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t4", Vector2i(4, 4))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_add_force("zeon_t4", "zeon", str(ctx.get("node_id", "")))

	var r1 := CampaignBaseDefense.process_assault_turn(5)
	var r2 := CampaignBaseDefense.process_assault_turn(5)
	var r3 := CampaignBaseDefense.process_assault_turn(6)
	_assert_eq((r1.get("created", []) as Array).size(), 1, "T4: First scan creates one")
	_assert_true((r2.get("created", []) as Array).is_empty(), "T4: Repeat scan creates none")
	_assert_true((r3.get("created", []) as Array).is_empty(), "T4: Later scan creates none")
	_assert_eq(CampaignBaseDefense.get_assaults().size(), 1, "T4: Single assault record")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "T4: Single battle")
	_assert_eq(int(CampaignBaseDefense.get_assault(str((r1.get("created", []) as Array)[0])).get("deadline_turn", -1)), 7,
		"T4: Deadline never extended by repeats")


# ---------------------------------------------------------------------------
# T5: Exact T+2 boundary; expiration marks only (no auto-mutation).
# ---------------------------------------------------------------------------
func _test_deadline_boundary() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t5", Vector2i(4, 4))
	var base_id := str(ctx.get("base_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var attacker_id := _add_force("zeon_t5", "zeon", str(ctx.get("node_id", "")))

	var r5 := CampaignBaseDefense.process_assault_turn(5)
	var battle_id := str((r5.get("created", []) as Array)[0])
	for t in [5, 6, 7]:
		var r := CampaignBaseDefense.process_assault_turn(t)
		_assert_true((r.get("expired_marked", []) as Array).is_empty(),
			"T5: No expiration at turn %d" % t)
		_assert_true(CampaignBattle.is_active(battle_id),
			"T5: Battle ACTIVE at turn %d" % t)
	_assert_false(CampaignBaseDefense.is_assault_expired(battle_id),
		"T5: Not expired through the deadline turn")

	# Past the deadline with one verified ACTIVE attacker, the approved
	# Option-D outcome applies (attacker success): resolve + DISABLED base,
	# controller preserved, attacker itself untouched.
	var r8 := CampaignBaseDefense.process_assault_turn(8)
	_assert_eq(r8.get("expired_marked", []), [battle_id], "T5: Expiration marked past the deadline")
	_assert_eq(r8.get("auto_resolved", []),
		[{"battle_id": battle_id, "outcome": "attacker_success"}],
		"T5: Attacker success applied")
	_assert_eq(CampaignBattle.get_state(battle_id), CampaignBattle.BattleState.RESOLVED,
		"T5: Battle RESOLVED by the approved outcome")
	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.DISABLED,
		"T5: Base DISABLED by the approved outcome")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation",
		"T5: Controller untouched by the approved outcome")
	_assert_eq(CampaignForce.get_state(attacker_id), CampaignForce.ForceState.ACTIVE,
		"T5: Attacker itself untouched (no extra side effect)")
	_assert_true(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"T5: Record cleared after application")

	var r8b := CampaignBaseDefense.process_assault_turn(8)
	_assert_true((r8b.get("expired_marked", []) as Array).is_empty(),
		"T5: Expiration never marked twice")
	_assert_true((r8b.get("auto_resolved", []) as Array).is_empty(),
		"T5: Outcome never applied twice")
	_assert_true((r8b.get("created", []) as Array).is_empty(),
		"T5: Resolved assault never duplicated")


# ---------------------------------------------------------------------------
# T6: Retreat and re-intervention preserve the original deadline.
# ---------------------------------------------------------------------------
func _test_retreat_preserves_deadline() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t6", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_add_force("zeon_t6", "zeon", node_id)
	GlobalData.board.current_tile = Vector2i(4, 4)
	CampaignPlayerMovement.set_current_node_id(node_id)

	var r := CampaignBaseDefense.process_assault_turn(5)
	var battle_id := str((r.get("created", []) as Array)[0])
	CampaignBaseDefense.intervene(battle_id)
	EventBus.combat_escaped.emit()
	_assert_eq(int(CampaignBaseDefense.get_assault(battle_id).get("deadline_turn", -1)), 7,
		"T6: Retreat keeps the deadline")
	_assert_true(CampaignBattle.is_active(battle_id), "T6: Assault ACTIVE after retreat")

	var again := CampaignBaseDefense.intervene(battle_id)
	_assert_true(bool(again.get("ok", false)), "T6: Re-intervention allowed")
	_assert_eq(int(CampaignBaseDefense.get_assault(battle_id).get("deadline_turn", -1)), 7,
		"T6: Re-intervention keeps the deadline")


# ---------------------------------------------------------------------------
# T7: Counter-only turns skip scheduling and expiration.
# ---------------------------------------------------------------------------
func _test_counter_only_turn_skips() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t7", Vector2i(4, 4))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_add_force("zeon_t7", "zeon", str(ctx.get("node_id", "")))

	var r := CampaignTurnExecutive.advance_campaign_turn("probe_counter", {"day_boundary": false})
	_assert_eq(CampaignTurnExecutive.get_turn(), 1, "T7: Counter still advances")
	_assert_true(bool(r.get("strategic_assault_skipped", false)),
		"T7: Assault phase skipped on counter-only turns")
	_assert_true(CampaignBaseDefense.get_assaults().is_empty(), "T7: Nothing scheduled")
	_assert_true(CampaignBattle.get_battles().is_empty(), "T7: No battles created")


# ---------------------------------------------------------------------------
# T8: Executive integration on the day-boundary path.
# ---------------------------------------------------------------------------
func _test_executive_integration() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t8", Vector2i(4, 4))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_add_force("zeon_t8", "zeon", str(ctx.get("node_id", "")))

	var r := CampaignTurnExecutive.advance_campaign_turn("probe_day", {})
	_assert_true(bool(r.get("ok", false)), "T8: Day turn advances")
	_assert_eq(CampaignTurnExecutive.get_turn(), 1, "T8: Turn is 1")
	_assert_true((r.get("phases", []) as Array).has("strategic_assault"),
		"T8: Assault phase runs on day boundary")
	_assert_true(r.has("strategic_assault"), "T8: Receipt carries the assault key")
	var created: Array = (r.get("strategic_assault", {}) as Dictionary).get("created", [])
	_assert_eq(created.size(), 1, "T8: Executive scheduled exactly one assault")
	var rec := CampaignBaseDefense.get_assault(str(created[0]))
	_assert_eq(int(rec.get("created_turn", -1)), 1, "T8: Creation stamped with the new turn")
	_assert_eq(int(rec.get("deadline_turn", -1)), 3, "T8: Deadline is T+2")


# ---------------------------------------------------------------------------
# T9: Save/load preserves assault identity and deadline.
# ---------------------------------------------------------------------------
func _test_save_load_preserves() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t9", Vector2i(4, 4))
	var base_id := str(ctx.get("base_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_add_force("zeon_t9", "zeon", str(ctx.get("node_id", "")))

	var r := CampaignBaseDefense.process_assault_turn(5)
	var battle_id := str((r.get("created", []) as Array)[0])
	_assert_true(SaveGameIO.save_run(), "T9: Save with live assault succeeds")
	CampaignBaseDefense.reset_defense_state()
	_assert_true(SaveGameIO.load_run(), "T9: Load restores the assault")
	var rec := CampaignBaseDefense.get_assault(battle_id)
	_assert_eq(str(rec.get("base_id", "")), base_id, "T9: Base identity preserved")
	_assert_eq(int(rec.get("created_turn", -1)), 5, "T9: Creation turn preserved")
	_assert_eq(int(rec.get("deadline_turn", -1)), 7, "T9: Deadline preserved")
	_assert_false(bool(rec.get("expired", true)), "T9: Expiry flag preserved")
	_assert_true(CampaignBattle.is_active(battle_id), "T9: Battle ACTIVE after load")


# ---------------------------------------------------------------------------
# T10: Legacy payloads and malformed rows fail safely.
# ---------------------------------------------------------------------------
func _test_legacy_and_malformed_safe() -> void:
	_setup_clean_campaign_environment()
	# Legacy payload without the key restores empty assaults.
	SaveGameIO.restore_from_dict({})
	_assert_true(CampaignBaseDefense.get_assaults().is_empty(), "T10: Legacy payload loads empty")

	# Rebuild world, then feed malformed rows around one valid row.
	_setup_clean_campaign_environment()
	var ctx2 := _setup_player_base("t10b", Vector2i(4, 4))
	var base2 := str(ctx2.get("base_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var attacker2 := _add_force("zeon_t10b", "zeon", str(ctx2.get("node_id", "")))
	var r2 := CampaignBaseDefense.process_assault_turn(5)
	var good_battle := str((r2.get("created", []) as Array)[0])
	CampaignBaseDefense.deserialize_assaults({"assaults": {
		"not_a_dict": 7,
		"": {"base_id": base2, "created_turn": 5, "deadline_turn": 7},
		"battle_ghost": {"base_id": "base_nope", "created_turn": 5, "deadline_turn": 7},
		"battle_nobattle": {"base_id": base2, "created_turn": 5, "deadline_turn": 7},
		"battle_neg": {"base_id": base2, "created_turn": 5, "deadline_turn": -2},
		"battle_flip": {"base_id": base2, "created_turn": 9, "deadline_turn": 4},
		good_battle: {"base_id": base2, "created_turn": 5, "deadline_turn": 7},
	}})
	_assert_eq(CampaignBaseDefense.get_assaults().size(), 1, "T10: Only the valid row survives")
	_assert_eq(str(CampaignBaseDefense.get_assault(good_battle).get("base_id", "")), base2,
		"T10: Valid row intact")
	_assert_true(CampaignBattle.is_active(good_battle), "T10: Battle untouched by malformed load")
	_assert_eq(str(CampaignBase.get_base(base2).get("controller", "")), "federation",
		"T10: Base untouched by malformed load")
	_assert_eq(CampaignForce.get_state(attacker2), CampaignForce.ForceState.ACTIVE,
		"T10: Forces untouched by malformed load")


# ---------------------------------------------------------------------------
# T11: Expired-but-unresolved assaults stay recoverable, never vanish.
# (DISABLED attacker defers under AUDIT_ONLY, so the record survives to
# prove recoverability; the ACTIVE-attacker application path is covered by
# the auto-resolve suite.)
# ---------------------------------------------------------------------------
func _test_expired_unresolved_recoverable() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("t11", Vector2i(4, 4))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var attacker_id := _add_force("zeon_t11", "zeon", str(ctx.get("node_id", "")))

	var r := CampaignBaseDefense.process_assault_turn(5)
	var battle_id := str((r.get("created", []) as Array)[0])
	CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DISABLED)
	CampaignBaseDefense.process_assault_turn(9)
	_assert_true(CampaignBaseDefense.is_assault_expired(battle_id), "T11: Assault expired")
	_assert_true((CampaignBaseDefense.process_assault_turn(9).get("auto_resolved", []) as Array).is_empty(),
		"T11: Disabled attacker defers (no invented outcome)")
	_assert_true(SaveGameIO.save_run(), "T11: Save with expired assault succeeds")
	CampaignBaseDefense.reset_defense_state()
	_assert_true(SaveGameIO.load_run(), "T11: Load restores the expired assault")
	var rec := CampaignBaseDefense.get_assault(battle_id)
	_assert_false(rec.is_empty(), "T11: Expired record did not disappear")
	_assert_true(bool(rec.get("expired", false)), "T11: Expiry flag survived")
	_assert_true(CampaignBattle.is_active(battle_id), "T11: Battle still ACTIVE (nothing auto-resolved)")
	# A later scan neither duplicates nor silently drops it.
	var r2 := CampaignBaseDefense.process_assault_turn(9)
	_assert_true((r2.get("created", []) as Array).is_empty(), "T11: No duplicate created")
	_assert_false(CampaignBaseDefense.get_assault(battle_id).is_empty(),
		"T11: Record still present after another scan")


# ---------------------------------------------------------------------------
# R: Repeat-assault identity migration (legacy def_<base> preserved first,
# deterministic _s2/_s3 afterwards; open battles never duplicated; terminal
# history never returned as a fresh assault).
# ---------------------------------------------------------------------------
func _test_repeat_assault_identity() -> void:
	_setup_clean_campaign_environment()
	var ctx := _setup_player_base("rpt", Vector2i(4, 4))
	var node_id := str(ctx.get("node_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var attacker_id := _add_force("zeon_rpt", "zeon", node_id)

	var legacy_id := CampaignBattle.make_battle_id(1, "def_" + base_id)
	var r1 := CampaignBaseDefense.process_assault_turn(5)
	_assert_eq(r1.get("created", []), [legacy_id], "R: First assault keeps the legacy id")

	# Starting again while ACTIVE duplicates nothing.
	var again := CampaignBaseDefense.start_base_attack(base_id, attacker_id)
	_assert_true(bool(again.get("ok", false)), "R: Re-attack on ACTIVE assault accepted")
	_assert_eq(str(again.get("battle_id", "")), legacy_id, "R: Same battle id returned")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "R: Still a single battle")

	# After terminal resolution, the next assault gets a fresh unique id.
	_assert_true(CampaignBattle.resolve_battle(legacy_id), "R: First battle resolved")
	var r2 := CampaignBaseDefense.process_assault_turn(6)
	var created2: Array = r2.get("created", [])
	_assert_eq(created2.size(), 1, "R: Second assault created")
	var second_id := str(created2[0]) if not created2.is_empty() else ""
	_assert_true(second_id != legacy_id, "R: Second id differs from legacy")
	_assert_true(second_id.begins_with(legacy_id + "_s"), "R: Second id carries the _s suffix")
	_assert_true(CampaignBattle.is_active(second_id), "R: Second battle ACTIVE (never a stale success)")
	_assert_eq(CampaignBattle.get_state(legacy_id), CampaignBattle.BattleState.RESOLVED,
		"R: Historical battle record intact")

	# A third assault advances the suffix without collisions.
	_assert_true(CampaignBattle.resolve_battle(second_id), "R: Second battle resolved")
	var r3 := CampaignBaseDefense.process_assault_turn(7)
	var third_id := str((r3.get("created", []) as Array)[0])
	_assert_true(third_id != legacy_id and third_id != second_id, "R: Third id unique")
	_assert_eq(CampaignBattle.get_battles().size(), 3, "R: Three historical battles coexist")

	# PLANNED battles are launched in place, never duplicated or bypassed.
	_setup_clean_campaign_environment()
	var ctx2 := _setup_player_base("rpt2", Vector2i(5, 5))
	var node2 := str(ctx2.get("node_id", ""))
	var base2 := str(ctx2.get("base_id", ""))
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var attacker2 := _add_force("zeon_rpt2", "zeon", node2)
	var planned_id := CampaignBattle.make_battle_id(1, "def_" + base2)
	var defender2 := "force_garrison_" + node2
	CampaignForce.register_force(defender2, "PATROL", "federation", node2, base2, 1, 10)
	CampaignBattle.register_battle(planned_id, node2, [attacker2, defender2])
	var pl := CampaignBaseDefense.start_base_attack(base2, attacker2)
	_assert_true(bool(pl.get("ok", false)), "R: PLANNED battle adopted")
	_assert_eq(str(pl.get("battle_id", "")), planned_id, "R: Same PLANNED id returned")
	_assert_true(CampaignBattle.is_active(planned_id), "R: PLANNED battle launched ACTIVE")
	_assert_eq(CampaignBattle.get_battles().size(), 1, "R: No duplicate battle")

	# Save/load keeps legacy RESOLVED history and the ACTIVE suffix battle.
	_assert_true(SaveGameIO.save_run(), "R: Save with assault history succeeds")
	CampaignBaseDefense.reset_defense_state()
	_assert_true(SaveGameIO.load_run(), "R: Load restores assault history")
	_assert_eq(CampaignBattle.get_state(planned_id), CampaignBattle.BattleState.ACTIVE,
		"R: ACTIVE battle state survives load")


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
	print("S2-B ASSAULT SCHEDULING VERIFY (Phase 2A) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: S2-B assault scheduling contract strictly satisfied.")
	else:
		printerr("FAILED: S2-B assault scheduling has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
