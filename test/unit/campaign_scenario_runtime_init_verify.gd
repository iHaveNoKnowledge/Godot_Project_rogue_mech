extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN SCENARIO RUNTIME INIT VERIFICATION — Phase 5AF.
##
## Proves the selected-scenario → validated-start → runtime-init →
## published-identity → turn-simulation contract using real authorities:
##   RunStartSystem.start_campaign_scenario (entry, validation, atomicity)
##   CampaignScenarioInitializer.apply_scenario (runtime translation)
##   CampaignTurnExecutive.advance_campaign_turn (day-boundary simulation)
##   CampaignNodeInspection-free entry gating via main-menu source guards
## Covers: successful init, repeat-init stability, failure atomicity,
## definition immutability, turn boundaries, C4 neutrality, save/load
## identity, and menu gating — without new runtime authorities.
## ---------------------------------------------------------------------------

const CANONICAL_ID := "frontier_skirmish"

var _checks_passed := 0
var _checks_failed := 0


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("RUNTIME_INIT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("RUNTIME_INIT FAIL: %s" % description)


func _ready() -> void:
	print("Running Scenario Runtime Init verification (Phase 5AF)...")
	_test_successful_initialization()
	_test_repeat_init_stability()
	_test_failure_atomicity()
	_test_definition_immutability()
	_test_turn_boundaries()
	_test_c4_neutrality()
	_test_save_load_identity()
	_test_menu_entry_guards()
	_print_summary()


func _clear_runtime() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
	CampaignTurnExecutive.reset()
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	GlobalData.current_campaign_id = ""
	GlobalData.current_campaign_scenario_id = ""
	GlobalData.current_campaign_player_node_id = ""


func _snap_runtime() -> Dictionary:
	return {
		"nodes": JSON.stringify(CampaignNodeRegistry.get_nodes()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"territories": JSON.stringify(CampaignTerritory.serialize()),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"turn": CampaignTurnExecutive.get_turn(),
		"heat": JSON.stringify(CampaignStrategicHeat.serialize()),
		"detection": JSON.stringify(CampaignStrategicDetection.serialize()),
		"scenario_id": str(GlobalData.current_campaign_scenario_id),
		"campaign_id": str(GlobalData.current_campaign_id),
		"player_node": str(GlobalData.current_campaign_player_node_id),
	}


# 1-4. Successful start publishes identity and translates the definition.
func _test_successful_initialization() -> void:
	_clear_runtime()
	var r: Dictionary = RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	_check(bool(r.get("ok", false)) == true, "1.1: Valid scenario starts")
	_check(bool(r.get("started", false)) == true, "1.2: Receipt reports started=true")
	_check(str(r.get("scenario_id", "")) == CANONICAL_ID, "1.3: Receipt carries the selected ID")
	_check((r.get("forces_created", []) as Array).size() == 3, "1.4: Exactly 3 forces created")
	_check((r.get("nodes_created", []) as Array).size() == 4, "1.5: Exactly 4 nodes created")
	_check((r.get("territories_created", []) as Array).size() == 2, "1.6: Exactly 2 territories created")
	_check((r.get("bases_created", []) as Array).size() == 2, "1.7: Exactly 2 bases created")
	_check(CampaignForce.has_force("force_s1_fed_vanguard"), "1.8: Federation vanguard force registered")
	_check(CampaignForce.has_force("force_s1_zeon_raiders"), "1.9: Zeon raiders force registered")
	_check(CampaignTerritory.get_controller("terr_frontier_sector_alpha") == "federation", "1.10: Sector Alpha controller matches definition")
	_check(CampaignTerritory.get_controller("terr_frontier_sector_beta") == "zeon", "1.11: Sector Beta controller matches definition")
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.HOSTILE, "1.12: Authored HOSTILE relation applied")
	_check(FactionSystem.get_relation("federation", "outland") == FactionSystem.Relation.NEUTRAL, "1.13: Authored NEUTRAL relation applied")
	_check(str(GlobalData.current_campaign_scenario_id) == CANONICAL_ID, "1.14: Run identity publishes scenario ID")
	_check(str(GlobalData.current_campaign_id) != "", "1.15: Campaign instance ID published")
	_check(str(GlobalData.current_campaign_faction_id) == "federation", "1.16: Player faction defaults to federation")
	var created: Array = r.get("nodes_created", [])
	_check(not created.is_empty() and str(GlobalData.current_campaign_player_node_id) == str(created[0]), "1.17: Player node falls back to first created node")


# 5. Repeat init is stable: same entities, no duplicates.
func _test_repeat_init_stability() -> void:
	_clear_runtime()
	var r1: Dictionary = RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	var r2: Dictionary = RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	_check(bool(r2.get("started", false)) == true, "5.1: Repeat start succeeds")
	_check(CampaignForce.get_forces().size() == 3, "5.2: No duplicate forces across restarts")
	_check(CampaignBase.get_bases().size() == 2, "5.3: No duplicate bases across restarts")
	_check(CampaignNodeRegistry.get_nodes().size() == 4, "5.4: No duplicate nodes across restarts")
	_check(JSON.stringify(r1.get("forces_created", [])) == JSON.stringify(r2.get("forces_created", [])), "5.5: Created ID lists identical across restarts")


# 6-8. Failures publish nothing and leave no partial state.
func _test_failure_atomicity() -> void:
	_clear_runtime()
	CampaignForce.register_force("force_probe", "PATROL", "zeon", "", "", 1, 5)
	var before := _snap_runtime()
	var bad_id: Dictionary = RunStartSystem.start_campaign_scenario("no_such_scenario")
	_check(bool(bad_id.get("ok", true)) == false, "6.1: Unknown scenario ID rejected")
	_check(str(GlobalData.current_campaign_scenario_id) == "", "6.2: Failed start publishes no identity")
	_check(_snap_runtime() == before, "6.3: Failed validation leaves prior runtime untouched")
	var bad_def: Dictionary = RunStartSystem.start_campaign_scenario("")
	_check(bool(bad_def.get("ok", true)) == false, "6.4: Empty scenario ID rejected")
	_check(_snap_runtime() == before, "6.5: Empty ID leaves runtime untouched")
	_clear_runtime()


# 11. Authoring data survives runtime translation byte-identical.
func _test_definition_immutability() -> void:
	_clear_runtime()
	var s = load("res://resources/data/scenarios/frontier_skirmish.tres")
	var before := JSON.stringify({
		"forces": s.get_initial_force_specs(),
		"nodes": s.get_initial_node_specs(),
		"routes": s.get_initial_route_specs(),
		"territories": s.get_initial_territory_specs(),
		"bases": s.get_initial_base_specs(),
		"rels": s.get_initial_relationships(),
		"rules": s.get_strategic_rules(),
	})
	RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	var after := JSON.stringify({
		"forces": s.get_initial_force_specs(),
		"nodes": s.get_initial_node_specs(),
		"routes": s.get_initial_route_specs(),
		"territories": s.get_initial_territory_specs(),
		"bases": s.get_initial_base_specs(),
		"rels": s.get_initial_relationships(),
		"rules": s.get_strategic_rules(),
	})
	_check(before == after, "11.1: Canonical definition byte-identical after start")


# 13-17. Turn boundaries: selection/start advance nothing; day boundary simulates.
func _test_turn_boundaries() -> void:
	_clear_runtime()
	_check(CampaignTurnExecutive.get_turn() == 0, "13.1: Turn starts at 0")
	RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	_check(CampaignTurnExecutive.get_turn() == 0, "13.2: Successful init advances no turn")
	var r := CampaignTurnExecutive.advance_campaign_turn("runtime_probe", {})
	_check(bool(r.get("ok", false)) == true, "15.1: Day boundary advances via executive")
	_check(CampaignTurnExecutive.get_turn() == 1, "15.2: Counter advances exactly once")
	_check((r.get("phases", []) as Array).has("strategic_detection"), "16.1: Detection phase runs in day order")
	_check((r.get("phases", []) as Array).has("strategic_heat"), "16.2: Heat phase runs in day order")
	var r2 := CampaignTurnExecutive.advance_campaign_turn("runtime_probe", {})
	_check(bool(r2.get("ok", false)) == true and CampaignTurnExecutive.get_turn() == 2, "17.1: Re-entry-free repeat advances cleanly")


# 12/18. C4 neutrality: seeded C4 survives start; start creates none.
func _test_c4_neutrality() -> void:
	_clear_runtime()
	CampaignStrategicHeat.set_node_heat("node_probe", 4)
	CampaignStrategicDetection.report_location("federation", "node_probe", 0, "combat")
	RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	_check(CampaignStrategicHeat.get_node_heat("node_probe") == 4, "12.1: Start preserves unrelated heat")
	_check(CampaignStrategicDetection.is_located("federation"), "12.2: Start preserves unrelated intel")
	_clear_runtime()
	RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "18.1: Start creates no heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "18.2: Start creates no intel")


# 19-20. Save/load preserves identity; menu gates entry on success.
func _test_save_load_identity() -> void:
	_clear_runtime()
	RunStartSystem.start_campaign_scenario(CANONICAL_ID)
	_check(SaveGameIO.save_run(), "20.1: Save succeeds after start")
	CampaignNodeRegistry.clear()
	CampaignForce.clear()
	GlobalData.current_campaign_scenario_id = ""
	_check(SaveGameIO.load_run(), "20.2: Load succeeds")
	_check(str(GlobalData.current_campaign_scenario_id) == CANONICAL_ID, "20.3: Scenario identity survives save/load")
	_check(CampaignForce.get_forces().size() == 3, "20.4: Runtime forces survive save/load")


func _test_menu_entry_guards() -> void:
	var code := _read_source("res://scripts/ui/main_menu_controller.gd")
	_check(code.contains("CampaignScenarioSelection"), "9.1: Menu routes through selection authority")
	_check(not code.contains("RunStartSystem.start_campaign_scenario("), "9.2: No direct start bypass in menu")
	_check(code.contains("enter_node_map()"), "9.3: Node map entry exists")
	_check(code.contains("confirm_selection()"), "9.4: Entry flows through confirm_selection")


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
	print("CAMPAIGN SCENARIO RUNTIME INIT VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CAMPAIGN_SCENARIO_RUNTIME_INIT_VERIFICATION_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_SCENARIO_RUNTIME_INIT_TESTS_PASSED")
		get_tree().quit(0)
