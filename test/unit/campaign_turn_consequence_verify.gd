class_name CampaignTurnConsequenceVerify
extends Node

## ---------------------------------------------------------------------------
## PHASE 2F — TURN-CONSEQUENCE SURFACING VERIFICATION (presentation only)
##
## Verifies CampaignNodeMap.build_turn_consequence_lines, a pure read over an
## already-returned turn receipt:
##   T1. Spy event with a name surfaces its pre-formatted text; empty spy
##       surfaces nothing.
##   T2. Created assaults name their verified base; unknown battles fall back
##       without invention.
##   T3. Applied outcomes report held/lost truthfully per outcome value.
##   T4. Expiries resolved the same tick are not also reported as unresolved.
##   T5. Rival log entries surface verbatim; farmed counters never surface.
##   T6. Era change surfaces only when phase_changed is true.
##   T7. Enemy-base spawn/completion surface only when their flags are true.
##   T8. Failed turns and empty receipts yield no lines (no fabrication).
##   T9. A live quiet turn shows header only; rendering mutates nothing.
## ---------------------------------------------------------------------------

const CampaignNodeMapScene = preload("res://scenes/ui/campaign_node_map.tscn")
const CampaignNodeMapScript = preload("res://scripts/ui/campaign_node_map.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _save_backup := ""


func _ready() -> void:
	print("--- BEGIN PHASE 2F TURN-CONSEQUENCE VERIFY ---")
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


func _base_receipt() -> Dictionary:
	return {
		"ok": true, "turn": 6, "reason": "probe",
		"spy_event": {},
		"strategic_assault": {},
		"rival": {}, "era": {},
		"enemy_base_spawn_requested": false,
		"enemy_base_completed": false,
	}


func _run_all_tests() -> void:
	_test_spy_lines()
	_test_created_assault_lines()
	_test_applied_outcome_lines()
	_test_expiry_not_double_reported()
	_test_rival_lines()
	_test_era_lines()
	_test_enemy_base_lines()
	_test_failed_and_empty_receipts()
	_test_live_quiet_turn()


# ---------------------------------------------------------------------------
# T1: Spy.
# ---------------------------------------------------------------------------
func _test_spy_lines() -> void:
	_setup_clean_campaign_environment()
	var r := _base_receipt()
	_assert_true(CampaignNodeMapScript.build_turn_consequence_lines(r).is_empty(),
		"T1: Empty spy surfaces nothing")
	r["spy_event"] = {"name": "SPY CAUGHT", "effect": "none", "amount": 0,
		"desc": "Intercepted a spy! +20 credits."}
	var lines: Array = CampaignNodeMapScript.build_turn_consequence_lines(r)
	_assert_eq(lines.size(), 1, "T1: Spy surfaces exactly one line")
	_assert_true(str(lines[0]).contains("SPY CAUGHT"), "T1: Spy name preserved")
	_assert_true(str(lines[0]).contains("+20 credits"), "T1: Spy desc preserved")


# ---------------------------------------------------------------------------
# T2: Created assaults name verified bases.
# ---------------------------------------------------------------------------
func _test_created_assault_lines() -> void:
	_setup_clean_campaign_environment()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_t2", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	CampaignBase.register_base("base_t2", node_id, "OUTPOST", "federation", terr_id)
	var fa := CampaignForce.register_force("force_a_t2", "PATROL", "zeon", node_id)
	var fb := CampaignForce.register_force("force_b_t2", "PATROL", "federation", node_id)
	var battle_id := CampaignBattle.register_battle("battle_t2", node_id, [fa, fb])
	CampaignBattle.prepare_launch(battle_id)

	var r := _base_receipt()
	r["strategic_assault"] = {"created": [battle_id]}
	var lines: Array = CampaignNodeMapScript.build_turn_consequence_lines(r)
	_assert_eq(lines, ["New assault reported at base_t2."],
		"T2: Created assault names the verified base")

	var r2 := _base_receipt()
	r2["strategic_assault"] = {"created": ["battle_ghost"]}
	_assert_eq(CampaignNodeMapScript.build_turn_consequence_lines(r2),
		["New assault reported at battle_ghost."],
		"T2: Unknown battle falls back to its id without invention")


# ---------------------------------------------------------------------------
# T3: Applied outcomes report truthfully.
# ---------------------------------------------------------------------------
func _test_applied_outcome_lines() -> void:
	_setup_clean_campaign_environment()
	var r := _base_receipt()
	r["strategic_assault"] = {"auto_resolved": [
		{"battle_id": "battle_x", "outcome": "defender_success"},
		{"battle_id": "battle_y", "outcome": "attacker_success"},
	]}
	var lines: Array = CampaignNodeMapScript.build_turn_consequence_lines(r)
	_assert_eq(lines.size(), 2, "T3: Both outcomes reported, nothing lost")
	_assert_true(str(lines[0]).contains("hold"), "T3: Defender success reports holding")
	_assert_true(str(lines[1]).contains("disabled"), "T3: Attacker success reports disabling")


# ---------------------------------------------------------------------------
# T4: Expiry resolved same tick is not double-reported.
# ---------------------------------------------------------------------------
func _test_expiry_not_double_reported() -> void:
	_setup_clean_campaign_environment()
	var r := _base_receipt()
	r["strategic_assault"] = {
		"expired_marked": ["battle_x"],
		"auto_resolved": [{"battle_id": "battle_x", "outcome": "attacker_success"}],
	}
	var lines: Array = CampaignNodeMapScript.build_turn_consequence_lines(r)
	_assert_eq(lines.size(), 1, "T4: Resolved expiry reported once, not twice")
	_assert_false(str(lines[0]).contains("deadline"), "T4: No stale unresolved line")

	var r2 := _base_receipt()
	r2["strategic_assault"] = {"expired_marked": ["battle_z"]}
	_assert_eq(CampaignNodeMapScript.build_turn_consequence_lines(r2),
		["Assault at battle_z passed its deadline unresolved."],
		"T4: Genuinely unresolved expiry is reported")


# ---------------------------------------------------------------------------
# T5: Rival log verbatim; counters never surface.
# ---------------------------------------------------------------------------
func _test_rival_lines() -> void:
	_setup_clean_campaign_environment()
	var r := _base_receipt()
	r["rival"] = {"scout_farmed": 99, "excavation_progress": 5.5,
		"lab_progress": 1.1, "prototype_spawned": false,
		"event_log": ["Rival unearthed an ancient relic core!"]}
	var lines: Array = CampaignNodeMapScript.build_turn_consequence_lines(r)
	_assert_eq(lines, ["Rival unearthed an ancient relic core!"],
		"T5: Rival log surfaces verbatim, counters skipped")


# ---------------------------------------------------------------------------
# T6: Era surfaces only on phase change.
# ---------------------------------------------------------------------------
func _test_era_lines() -> void:
	_setup_clean_campaign_environment()
	var r := _base_receipt()
	r["era"] = {"phase_changed": false, "era_name": "Tactical Era"}
	_assert_true(CampaignNodeMapScript.build_turn_consequence_lines(r).is_empty(),
		"T6: Unchanged era surfaces nothing")
	r["era"] = {"phase_changed": true, "era_name": "Energy Era"}
	_assert_eq(CampaignNodeMapScript.build_turn_consequence_lines(r),
		["Entered new era: Energy Era."], "T6: Era change surfaces once")


# ---------------------------------------------------------------------------
# T7: Enemy-base flags.
# ---------------------------------------------------------------------------
func _test_enemy_base_lines() -> void:
	_setup_clean_campaign_environment()
	var r := _base_receipt()
	r["enemy_base_spawn_requested"] = true
	r["enemy_base_completed"] = true
	var lines: Array = CampaignNodeMapScript.build_turn_consequence_lines(r)
	_assert_eq(lines.size(), 2, "T7: Both enemy-base milestones surface")
	_assert_true(str(lines[0]).contains("signature detected"), "T7: Spawn line truthful")
	_assert_true(str(lines[1]).contains("completed its program"), "T7: Completion line truthful")


# ---------------------------------------------------------------------------
# T8: Failed/empty receipts yield nothing.
# ---------------------------------------------------------------------------
func _test_failed_and_empty_receipts() -> void:
	_setup_clean_campaign_environment()
	_assert_true(CampaignNodeMapScript.build_turn_consequence_lines(
		{"ok": false, "error": "reentrant"}).is_empty(),
		"T8: Failed turn yields no lines")
	_assert_true(CampaignNodeMapScript.build_turn_consequence_lines({}).is_empty(),
		"T8: Empty receipt yields no lines")


# ---------------------------------------------------------------------------
# T9: Live quiet turn shows header only and mutates nothing.
# ---------------------------------------------------------------------------
func _test_live_quiet_turn() -> void:
	_setup_clean_campaign_environment()
	var snap_before := {
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"turn": CampaignTurnExecutive.get_turn(),
	}
	var node_map = CampaignNodeMapScene.instantiate()
	add_child(node_map)
	var receipt: Dictionary = node_map.advance_turn()
	_assert_true(bool(receipt.get("ok", false)), "T9: Live turn advances")
	_assert_true(str(node_map._turn_status_label.text).begins_with("Turn 1 completed"),
		"T9: Header preserved verbatim")
	_assert_eq(JSON.stringify(CampaignBattle.get_battles()), snap_before["battles"],
		"T9: Presentation created no battles")
	_assert_eq(CampaignTurnExecutive.get_turn(), int(snap_before["turn"]) + 1,
		"T9: Turn advanced exactly once by the executive, not the UI")
	node_map.queue_free()


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
	print("PHASE 2F TURN-CONSEQUENCE VERIFY RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 2F turn-consequence contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 2F turn-consequence has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
