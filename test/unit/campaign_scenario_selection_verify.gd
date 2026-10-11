extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN SCENARIO SELECTION VERIFICATION — Phase 5AE.
##
## Proves the selection contract on the real canonical catalog plus
## synthetic fixtures: catalog enumeration by stable ID, selection with
## existence + schema validation, safe unknown/missing/malformed handling,
## empty-catalog safety, cancellation purity, preview purity, deterministic
## repeat selection, turn/C4/save neutrality, pending-ID hand-off to the
## existing entry contract, and no parallel selection registry.
## ---------------------------------------------------------------------------

const SelectionScript = preload("res://scripts/systems/campaign_scenario_selection.gd")
const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")

const CANONICAL_ID := "frontier_skirmish"

var _checks_passed := 0
var _checks_failed := 0


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("SCENARIO_SELECTION OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("SCENARIO_SELECTION FAIL: %s" % description)


func _ready() -> void:
	print("Running Scenario Selection verification (Phase 5AE)...")
	SelectionScript.clear_selection()
	_test_catalog_enumeration()
	_test_valid_selection()
	_test_unknown_and_malformed()
	_test_empty_catalog()
	_test_cancellation_purity()
	_test_preview_purity()
	_test_repeated_selection_determinism()
	_test_turn_and_c4_neutrality()
	_test_confirm_handoff()
	_test_no_parallel_registry()
	SelectionScript.clear_selection()
	_print_summary()


func _snap_world() -> Dictionary:
	return {
		"nodes": JSON.stringify(CampaignNodeRegistry.get_nodes()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"territories": JSON.stringify(CampaignTerritory.serialize()),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"turn": CampaignTurnExecutive.get_turn(),
		"heat": JSON.stringify(CampaignStrategicHeat.serialize()),
		"detection": JSON.stringify(CampaignStrategicDetection.serialize()),
		"player_node": str(GlobalData.current_campaign_player_node_id),
		"pending": SelectionScript.get_pending_scenario_id(),
	}


func _clear_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
	CampaignTurnExecutive.reset()
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	SelectionScript.clear_selection()


func _make_second_scenario() -> Resource:
	var s = ScenarioDefScript.new()
	s.scenario_id = "second_probe"
	s.display_name = "Second Probe"
	s.description = "Synthetic second entry for extensibility checks."
	return s


func _make_invalid_scenario() -> Resource:
	var s = ScenarioDefScript.new()
	s.scenario_id = "bad_probe"
	s.display_name = "Bad Probe"
	s.faction_setup = ["no_such_faction"]
	return s


func _make_catalog(entries: Array) -> Resource:
	var cat = ScenarioCatalogScript.new()
	cat.scenarios = entries
	return cat


# 1. Catalog enumeration through the existing contract.
func _test_catalog_enumeration() -> void:
	_clear_world()
	var listed: Array = SelectionScript.list_selectable_scenarios()
	_check(listed.size() == 1, "1.1: Canonical catalog lists exactly one scenario")
	var entry: Dictionary = listed[0]
	_check(str(entry.get("scenario_id", "")) == CANONICAL_ID, "1.2: Entry keyed by stable ID")
	_check(str(entry.get("display_name", "")) == "Frontier Skirmish", "1.3: Display metadata surfaced")
	_check(bool(entry.get("valid", false)) == true, "1.4: Canonical entry flagged valid")
	# Multi-entry catalog stays ordered and per-entry validated.
	var cat = _make_catalog([load("res://resources/data/scenarios/frontier_skirmish.tres"), _make_second_scenario(), _make_invalid_scenario()])
	var multi: Array = SelectionScript.list_selectable_scenarios(cat)
	_check(multi.size() == 3, "1.5: Custom catalog lists all entries in order")
	_check(str(multi[0].get("scenario_id", "")) == CANONICAL_ID and bool(multi[0].get("valid", false)) == true, "1.6: First entry intact and valid")
	_check(str(multi[1].get("scenario_id", "")) == "second_probe" and bool(multi[1].get("valid", false)) == true, "1.7: Second valid entry listed")
	_check(str(multi[2].get("scenario_id", "")) == "bad_probe" and bool(multi[2].get("valid", false)) == false, "1.8: Invalid entry listed but flagged invalid")


# 2-3. Valid selection resolves the intended definition.
func _test_valid_selection() -> void:
	_clear_world()
	var r: Dictionary = SelectionScript.select_scenario(CANONICAL_ID)
	_check(bool(r.get("ok", false)) == true, "2.1: Valid scenario selects")
	_check(str(r.get("scenario_id", "")) == CANONICAL_ID, "2.2: Selection echoes stable ID")
	_check(SelectionScript.get_pending_scenario_id() == CANONICAL_ID, "2.3: Pending ID stored")
	var disp: Dictionary = SelectionScript.get_scenario_display(CANONICAL_ID)
	_check(str(disp.get("display_name", "")) == "Frontier Skirmish", "2.4: Display lookup uses existing metadata")
	SelectionScript.clear_selection()


# 4-5. Unknown, missing, and malformed inputs fail safely.
func _test_unknown_and_malformed() -> void:
	_clear_world()
	var r1: Dictionary = SelectionScript.select_scenario("no_such_scenario")
	_check(bool(r1.get("ok", true)) == false and str(r1.get("reason", "")) == "unknown_scenario", "4.1: Unknown ID rejected")
	var r2: Dictionary = SelectionScript.select_scenario("")
	_check(bool(r2.get("ok", true)) == false and str(r2.get("reason", "")) == "missing_scenario_id", "4.2: Empty ID rejected")
	var r3: Dictionary = SelectionScript.select_scenario("bad_probe", _make_catalog([_make_invalid_scenario()]))
	_check(bool(r3.get("ok", true)) == false and str(r3.get("reason", "")) == "validation_failed", "5.1: Invalid definition rejected")
	_check((r3.get("errors", []) as Array).size() > 0, "5.2: Validation errors surfaced")
	_check(SelectionScript.get_pending_scenario_id() == "", "5.3: Failed selection stores nothing")
	_check(SelectionScript.get_scenario_display("no_such_scenario").is_empty(), "5.4: Display lookup of unknown ID is empty")


# 6. Empty catalog is safe.
func _test_empty_catalog() -> void:
	_clear_world()
	var empty_cat = _make_catalog([])
	_check(SelectionScript.list_selectable_scenarios(empty_cat).is_empty(), "6.1: Empty catalog lists nothing")
	var r: Dictionary = SelectionScript.select_scenario(CANONICAL_ID, empty_cat)
	_check(bool(r.get("ok", true)) == false and str(r.get("reason", "")) == "unknown_scenario", "6.2: Selection from empty catalog rejected")


# 7. Cancellation leaves campaign state unchanged.
func _test_cancellation_purity() -> void:
	_clear_world()
	var before := _snap_world()
	_check(bool(SelectionScript.select_scenario(CANONICAL_ID).get("ok", false)), "7.1: Selection succeeds first")
	SelectionScript.clear_selection()
	_check(SelectionScript.get_pending_scenario_id() == "", "7.2: Pending cleared")
	_check(_snap_world() == before, "7.3: Cancel leaves all campaign state unchanged")
	var r: Dictionary = SelectionScript.confirm_selection()
	_check(bool(r.get("ok", true)) == false and str(r.get("reason", "")) == "missing_selection", "7.4: Confirm with nothing pending rejected")


# 8. Preview/listing never mutates.
func _test_preview_purity() -> void:
	_clear_world()
	var before := _snap_world()
	SelectionScript.list_selectable_scenarios()
	SelectionScript.get_scenario_display(CANONICAL_ID)
	SelectionScript.select_scenario("no_such_scenario")
	_check(_snap_world() == before, "8.1: Preview and failed selection mutate nothing")


# 9. Deterministic repeat selection; no duplicate runtime state.
func _test_repeated_selection_determinism() -> void:
	_clear_world()
	var r1: Dictionary = SelectionScript.select_scenario(CANONICAL_ID)
	var r2: Dictionary = SelectionScript.select_scenario(CANONICAL_ID)
	_check(JSON.stringify(r1) == JSON.stringify(r2), "9.1: Repeated selection is deterministic")
	var c1: Dictionary = SelectionScript.confirm_selection()
	_check(bool(c1.get("started", false)) == true, "9.2: First confirm starts")
	_check(CampaignForce.get_forces().size() == 3, "9.3: Exactly 3 forces after start")
	_check(SelectionScript.get_pending_scenario_id() == "", "9.4: Pending cleared on successful start")
	var c2: Dictionary = SelectionScript.confirm_selection()
	_check(bool(c2.get("ok", true)) == false, "9.5: Second confirm without selection rejected (no double start)")
	SelectionScript.select_scenario(CANONICAL_ID)
	var c3: Dictionary = SelectionScript.confirm_selection()
	_check(bool(c3.get("started", false)) == true, "9.6: Reselect + confirm restarts cleanly")
	_check(CampaignForce.get_forces().size() == 3, "9.7: No duplicate forces across restarts")


# 10. Turns and C4 Heat/Detection untouched by selection flow.
func _test_turn_and_c4_neutrality() -> void:
	_clear_world()
	CampaignStrategicHeat.set_node_heat("node_probe", 4)
	CampaignStrategicDetection.report_location("federation", "node_probe", 2, "combat")
	SelectionScript.select_scenario(CANONICAL_ID)
	_check(CampaignTurnExecutive.get_turn() == 0, "10.1: Selection advances no turn")
	_check(CampaignStrategicHeat.get_node_heat("node_probe") == 4, "10.2: Selection mutates no heat")
	_check(CampaignStrategicDetection.is_located("federation"), "10.3: Selection mutates no intel")
	SelectionScript.clear_selection()


# 11. C4 + save neutrality across a full successful start.
func _test_c4_save_neutrality() -> void:
	_clear_world()
	SelectionScript.select_scenario(CANONICAL_ID)
	SelectionScript.confirm_selection()
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "11.1: Start creates no heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "11.2: Start creates no intel")
	_check(SaveGameIO.save_run(), "11.3: Save succeeds after start")
	_check(SaveGameIO.load_run(), "11.4: Load succeeds after start")
	_check(str(GlobalData.current_campaign_scenario_id) == CANONICAL_ID, "11.5: Scenario identity survives save/load")


# 12. Hand-off carries the validated ID into the entry contract.
func _test_confirm_handoff() -> void:
	_clear_world()
	SelectionScript.select_scenario(CANONICAL_ID)
	var r: Dictionary = SelectionScript.confirm_selection()
	_check(str(r.get("scenario_id", "")) == CANONICAL_ID, "12.1: Entry receipt carries the selected ID")
	_check(str(GlobalData.current_campaign_scenario_id) == CANONICAL_ID, "12.2: Run identity publishes the selected ID")
	# Confirm against an emptied catalog keeps pending and starts nothing.
	SelectionScript.select_scenario(CANONICAL_ID)
	var bad: Dictionary = SelectionScript.confirm_selection(_make_catalog([]))
	_check(bool(bad.get("ok", true)) == false and str(bad.get("reason", "")) == "unknown_scenario", "12.3: Confirm re-validates against the given catalog")
	_check(SelectionScript.get_pending_scenario_id() == CANONICAL_ID, "12.4: Failed confirm keeps pending for retry")
	_check(CampaignForce.get_forces().size() == 3, "12.5: Failed confirm starts no new runtime (prior start intact)")


# 13 + guards. No parallel registry; source-level architecture checks.
func _test_no_parallel_registry() -> void:
	_clear_world()
	_check(SelectionScript.get_pending_scenario_id() == "", "13.1: No selection stored at rest")
	var listed: Array = SelectionScript.list_selectable_scenarios()
	_check(listed.size() == 1 and str(listed[0].get("scenario_id", "")) == CANONICAL_ID, "13.2: Single source of truth is the catalog")
	var code := _read_source("res://scripts/systems/campaign_scenario_selection.gd")
	_check(not code.contains("apply_scenario("), "13.3: Selection never initializes runtime directly")
	_check(code.contains("start_campaign_scenario("), "13.4: Entry flows through the existing contract")
	var menu := _read_source("res://scripts/ui/main_menu_controller.gd")
	_check(menu.contains("CampaignScenarioSelection"), "13.5: Main menu routes through selection")
	_check(not menu.contains("RunStartSystem.start_campaign_scenario("), "13.6: No direct start bypass remains in the menu")


func _read_source(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


func _print_summary() -> void:
	print("==================================================")
	print("CAMPAIGN SCENARIO SELECTION VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CAMPAIGN_SCENARIO_SELECTION_VERIFICATION_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_SCENARIO_SELECTION_TESTS_PASSED")
		get_tree().quit(0)
