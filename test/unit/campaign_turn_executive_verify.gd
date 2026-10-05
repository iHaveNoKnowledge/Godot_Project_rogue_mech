extends Node
## PHASE 1 CAMPAIGN TURN EXECUTIVE VERIFY (Campaign V2).
##
## Proves the turn contract: monotonic counter, deterministic exactly-once
## phases, re-entry guard, reset/new-run isolation, save round-trip with
## schema-1 backward compatibility, and day_boundary=false counter-only turns.
## Real-save safety: the pre-existing user save is backed up on entry and
## restored at the end (sector_progression_verify convention).

var _fails := 0
var _checks := 0
var _backup := ""
var _day_ended_count := 0
var _turn_completed_count := 0
var _nested_result := {}
var _economy_snap := {}
var _rival_snap := {}
var _era_snap := {}


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CAMPAIGN-TURN OK: " + name)
	else:
		_fails += 1
		printerr("CAMPAIGN-TURN FAIL: " + name)


func _on_day_ended() -> void:
	_day_ended_count += 1


func _on_turn_completed(_turn: int, _reason: String) -> void:
	_turn_completed_count += 1


func _on_day_ended_nested() -> void:
	# Fires mid-execution (compatibility phase): a nested turn must be refused.
	_nested_result = CampaignTurnExecutive.advance_campaign_turn("nested_probe", {})


func _snapshot_world() -> void:
	_economy_snap = {}
	for fac in ["federation", "zeon", "outland", "scavenger"]:
		_economy_snap[fac] = FactionEconomySystem.get_economy(fac).duplicate(true)
	_rival_snap = RivalProgressionSystem.serialize_rival_state()
	_era_snap = EraProgressionSystem.serialize_era_state()


func _restore_world() -> void:
	for fac in _economy_snap:
		var eco := FactionEconomySystem.get_economy(str(fac))
		eco.clear()
		for k in (_economy_snap[fac] as Dictionary):
			eco[k] = ((_economy_snap[fac] as Dictionary)[k] as Variant)
	RivalProgressionSystem.deserialize_rival_state(_rival_snap)
	EraProgressionSystem.deserialize_era_state(_era_snap)
	GlobalData.reset_run_data()


func _normalize() -> void:
	GlobalData.reset_run_data()
	RivalProgressionSystem.reset()
	EraProgressionSystem.reset()


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	_snapshot_world()
	_normalize()
	_test_counter()
	_test_exactly_once()
	_test_day_boundary_off()
	_test_reentry()
	_test_reset_and_isolation()
	_test_deserialize_edges()
	_test_save_round_trip()
	_restore_world()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_TURN_EXECUTIVE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_TURN_EXECUTIVE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_TURN_EXECUTIVE_TESTS_PASSED")
		get_tree().quit(0)


# TEST A — monotonic counter.
func _test_counter() -> void:
	CampaignTurnExecutive.reset()
	_check(CampaignTurnExecutive.get_turn() == 0, "counter starts at 0 after reset")
	var r1 := CampaignTurnExecutive.advance_campaign_turn("probe_a", {})
	_check(bool(r1.get("ok", false)) and CampaignTurnExecutive.get_turn() == 1, "first turn ok and counter == 1")
	var r2 := CampaignTurnExecutive.advance_campaign_turn("probe_a", {})
	_check(bool(r2.get("ok", false)) and CampaignTurnExecutive.get_turn() == 2, "second turn ok and counter == 2")
	_check(int(r1.get("turn", -1)) == 1 and int(r2.get("turn", -1)) == 2, "receipts carry their own turn ids")


# TEST B — exactly-once: one invocation runs each day-phase exactly once.
func _test_exactly_once() -> void:
	CampaignTurnExecutive.reset()
	var before := {}
	for p in CampaignTurnExecutive.PHASE_ORDER:
		before[p] = CampaignTurnExecutive.get_phase_call_count(p)
	_day_ended_count = 0
	_turn_completed_count = 0
	EventBus.board_day_ended.connect(_on_day_ended)
	EventBus.campaign_turn_completed.connect(_on_turn_completed)
	var fed_before := int(FactionEconomySystem.get_economy("federation").get("funds", 0))
	var parts_before := int(FactionEconomySystem.get_economy("federation").get("parts", 0))
	var pilots_before := (FactionEconomySystem.get_economy("federation").get("active_pilots", []) as Array).size()
	var r := CampaignTurnExecutive.advance_campaign_turn("board_day", {})
	var executed: Array = ["begin_turn", "faction_economy", "spy", "enemy_base",
		"board_day_compatibility", "rival", "era", "end_turn"]
	for p in executed:
		_check(CampaignTurnExecutive.get_phase_call_count(p) == int(before.get(p, 0)) + 1,
			"phase executed exactly once: " + p)
	_check(CampaignTurnExecutive.get_phase_call_count("scavenger") == int(before.get("scavenger", 0)),
		"scavenger phase skipped without board tiles (no fake tick)")
	_check(_day_ended_count == 1, "board_day_ended emitted exactly once (compatibility)")
	_check(_turn_completed_count == 1, "campaign_turn_completed emitted exactly once")
	var phases: Array = r.get("phases", [])
	_check(phases.size() == executed.size(), "receipt lists every executed phase once")
	var unique := {}
	for p in phases:
		unique[p] = true
	_check(unique.size() == phases.size(), "receipt has no duplicate phases")
	# advance_day_economy: +250 funds / +25 parts, then recruits one pilot
	# (-120) while under barracks capacity — so the exact funds delta depends
	# on whether a recruit fired; parts are untouched by recruitment.
	_check(int(FactionEconomySystem.get_economy("federation").get("parts", 0)) == parts_before + 25,
		"economy tick applied exactly once (+25 parts)")
	var pilots_after := (FactionEconomySystem.get_economy("federation").get("active_pilots", []) as Array).size()
	var recruited := pilots_after - pilots_before
	var expected_funds := fed_before + 250 - (120 if recruited > 0 else 0)
	_check(recruited <= 1
		and int(FactionEconomySystem.get_economy("federation").get("funds", 0)) == expected_funds,
		"economy tick applied exactly once (funds +250, at most one -120 recruit)")
	EventBus.board_day_ended.disconnect(_on_day_ended)
	EventBus.campaign_turn_completed.disconnect(_on_turn_completed)


# TEST F2 — counter-only turn never forces day semantics.
func _test_day_boundary_off() -> void:
	CampaignTurnExecutive.reset()
	var eco_before := CampaignTurnExecutive.get_phase_call_count("faction_economy")
	_day_ended_count = 0
	_turn_completed_count = 0
	EventBus.board_day_ended.connect(_on_day_ended)
	EventBus.campaign_turn_completed.connect(_on_turn_completed)
	var r := CampaignTurnExecutive.advance_campaign_turn("fine_grained", {"day_boundary": false})
	_check(CampaignTurnExecutive.get_turn() == 1, "counter-only turn still increments")
	_check(CampaignTurnExecutive.get_phase_call_count("faction_economy") == eco_before,
		"counter-only turn runs no economy tick")
	_check(_day_ended_count == 0, "counter-only turn emits no board_day_ended")
	_check(_turn_completed_count == 1, "counter-only turn still completes")
	_check(bool(r.get("compatibility_skipped", false)), "receipt marks compatibility skipped")
	var phases: Array = r.get("phases", [])
	_check(phases == ["begin_turn", "end_turn"], "counter-only receipt has begin/end only")
	EventBus.board_day_ended.disconnect(_on_day_ended)
	EventBus.campaign_turn_completed.disconnect(_on_turn_completed)


# TEST C — re-entry guard through the real mid-execution signal.
func _test_reentry() -> void:
	CampaignTurnExecutive.reset()
	_check(not CampaignTurnExecutive.is_executing(), "idle outside execution")
	_nested_result = {}
	EventBus.board_day_ended.connect(_on_day_ended_nested)
	var turn_before := CampaignTurnExecutive.get_turn()
	var r := CampaignTurnExecutive.advance_campaign_turn("reentry_probe", {})
	EventBus.board_day_ended.disconnect(_on_day_ended_nested)
	_check(bool(r.get("ok", false)), "outer turn completes despite nested attempt")
	_check(_nested_result.get("ok", true) == false
		and str(_nested_result.get("error", "")) == "reentrant",
		"nested turn rejected with explicit reentrant error")
	_check(CampaignTurnExecutive.get_turn() == turn_before + 1,
		"nested attempt added no extra turn")
	_check(not CampaignTurnExecutive.is_executing(), "guard released after turn")


# TEST D/F — reset and new-run isolation via the established primitive.
func _test_reset_and_isolation() -> void:
	CampaignTurnExecutive.reset()
	for i in range(5):
		CampaignTurnExecutive.advance_campaign_turn("isolation_a", {"day_boundary": false})
	_check(CampaignTurnExecutive.get_turn() == 5, "run A advanced to 5")
	GlobalData.reset_run_data()
	_check(CampaignTurnExecutive.get_turn() == 0, "reset_run_data clears campaign turn (run B starts at 0)")
	for i in range(3):
		CampaignTurnExecutive.advance_campaign_turn("isolation_b", {"day_boundary": false})
	_check(CampaignTurnExecutive.get_turn() == 3, "run B advances independently")
	CampaignTurnExecutive.reset()
	_check(CampaignTurnExecutive.get_turn() == 0
		and CampaignTurnExecutive.get_last_receipt().is_empty(),
		"reset clears counter and receipt")


# TEST E1 — deserialize edges (legacy/malformed payloads).
func _test_deserialize_edges() -> void:
	CampaignTurnExecutive.deserialize_campaign_turn({}.get("campaign_turn", 0))
	_check(CampaignTurnExecutive.get_turn() == 0, "missing field restores as 0 (legacy save)")
	CampaignTurnExecutive.deserialize_campaign_turn("not-a-number")
	_check(CampaignTurnExecutive.get_turn() == 0, "wrong-typed value restores as 0")
	CampaignTurnExecutive.deserialize_campaign_turn(-4)
	_check(CampaignTurnExecutive.get_turn() == 0, "negative value clamps to 0")
	CampaignTurnExecutive.deserialize_campaign_turn(17.0)
	_check(CampaignTurnExecutive.get_turn() == 17, "JSON float number restores as int")
	CampaignTurnExecutive.reset()


# TEST E2 — full save/load round trip through SaveGameIO (schema 1 kept).
func _test_save_round_trip() -> void:
	CampaignTurnExecutive.reset()
	CampaignTurnExecutive.deserialize_campaign_turn(17)
	_check(SaveGameIO.save_run(), "save_run reports success with campaign turn set")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(d is Dictionary and int((d as Dictionary).get("campaign_turn", -1)) == 17,
		"save file carries campaign_turn == 17")
	_check(int((d as Dictionary).get("schema_version", -1)) == SaveGameIO.CURRENT_SCHEMA_VERSION,
		"schema version unchanged (no bump for plain int field)")
	CampaignTurnExecutive.reset()
	_check(CampaignTurnExecutive.get_turn() == 0, "counter cleared before load")
	_check(SaveGameIO.load_run(), "load_run reports success")
	_check(CampaignTurnExecutive.get_turn() == 17, "load restores campaign_turn == 17")
	CampaignTurnExecutive.reset()
