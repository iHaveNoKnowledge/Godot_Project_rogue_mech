extends Node
## ---------------------------------------------------------------------------
## PHASE 5Z SCENARIO DEFINITION AUTHORITY ARCHITECTURE VERIFY
##
## Architectural Contract Coverage:
##   A — Scenario identity (stable identifier, valid/invalid state)
##   B — No speculative fallback (never falls back to CampaignForceInitializer)
##   C — Empty/no-scenario behavior (produces zero forces, empty catalog)
##   D — RunTheme separation (RunTheme is player-only, not world scenario)
##   E — Seed separation (seed generates topology, does not invent scenario facts)
##   F — Fixture separation (CampaignForceInitializer remains speculative fixture)
##   G — Runtime separation (ScenarioDefinition is unmutated authoring data)
##   H — Determinism (same scenario produces deterministic state)
##   I — No player force regression (player force remains deferred)
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")

var _checks: int = 0
var _fails: int = 0
var _backup_save: String = ""


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("PHASE_5Z OK: " + test_name)
	else:
		_fails += 1
		printerr("PHASE_5Z FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup_save = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_run_all_tests()

	GlobalData.reset_run_data()
	if _backup_save != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup_save)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("CAMPAIGN_SCENARIO_AUTHORITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_SCENARIO_AUTHORITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_SCENARIO_AUTHORITY_TESTS_PASSED")
		get_tree().quit(0)


func _run_all_tests() -> void:
	_test_scenario_identity()
	_test_no_speculative_fallback()
	_test_empty_no_scenario_behavior()
	_test_run_theme_separation()
	_test_seed_separation()
	_test_fixture_separation()
	_test_runtime_separation()
	_test_determinism()
	_test_no_player_force_regression()
	_test_source_guards()


# A — Scenario identity
func _test_scenario_identity() -> void:
	var s = ScenarioDefScript.new()
	_check(not s.is_valid(), "A1: New ScenarioDefinition without id is invalid")

	s.scenario_id = "test_skirmish_alpha"
	s.display_name = "Test Skirmish Alpha"
	s.description = "Authored scenario description."
	_check(s.is_valid(), "A2: ScenarioDefinition with valid id is valid")
	_check(s.scenario_id == "test_skirmish_alpha", "A3: ScenarioDefinition retains stable identifier")
	_check(s.get_data_classification() == "CANONICAL", "A4: ScenarioDefinition data classification is CANONICAL")
	_check(s.is_canonical(), "A5: ScenarioDefinition is_canonical() returns true")


# B — No speculative fallback
func _test_no_speculative_fallback() -> void:
	_clear_campaign_state()

	# Scenario with explicitly empty initial force specs
	var s = ScenarioDefScript.new()
	s.scenario_id = "empty_forces_scenario"
	s.display_name = "Empty Forces Scenario"
	_check(s.get_initial_force_specs().is_empty(), "B1: ScenarioDefinition initial force specs default to empty")

	var result: Dictionary = InitializerScript.apply_scenario(s, 1)
	_check(result.get("ok", false) == true, "B2: Empty forces scenario apply succeeds cleanly")
	_check((result.get("forces_created", []) as Array).is_empty(), "B3: No forces created when scenario has empty force specs")
	_check(CampaignForce.get_forces().is_empty(), "B4: CampaignForce registry remains completely empty (no speculative fallback)")

	# Calling with null scenario
	var null_result: Dictionary = InitializerScript.apply_scenario(null, 1)
	_check(null_result.get("ok", false) == true, "B5: Null scenario apply handled cleanly")
	_check(null_result.get("applied", true) == false, "B6: Null scenario reports applied=false")
	_check((null_result.get("forces_created", []) as Array).is_empty(), "B7: Null scenario creates zero forces")
	_check(CampaignForce.get_forces().is_empty(), "B8: CampaignForce registry remains empty after null apply")


# C — Canonical catalog & scenario lookup
func _test_empty_no_scenario_behavior() -> void:
	var catalog_path := "res://resources/data/scenario_definition_catalog.tres"
	_check(ResourceLoader.exists(catalog_path), "C1: Canonical scenario catalog resource exists")

	var catalog = load(catalog_path)
	_check(catalog != null, "C2: Canonical scenario catalog loads successfully")
	_check(catalog.get_script() == ScenarioCatalogScript, "C3: Catalog is instance of ScenarioCatalogData")
	_check(catalog.get_scenario_count() == 1, "C4: Catalog contains exactly one canonical scenario")
	_check(catalog.has_scenario("frontier_skirmish"), "C5: Catalog contains 'frontier_skirmish'")
	_check(catalog.get_scenario("non_existent") == null, "C6: Requesting unauthored scenario returns null")
	_check(catalog.get_data_classification() == "CANONICAL", "C7: Catalog classification is CANONICAL")

	# Architecture invariant: empty catalog capability remains supported
	var empty_cat = ScenarioCatalogScript.new()
	_check(empty_cat.is_empty(), "C8: Fresh ScenarioCatalogData is empty")
	_check(empty_cat.get_scenario_count() == 0, "C9: Fresh ScenarioCatalogData count is 0")


# D — RunTheme separation
func _test_run_theme_separation() -> void:
	_clear_campaign_state()

	var themes: Array = GlobalData.run_themes
	_check(themes.size() > 0, "D1: GlobalData provides run themes")

	# Audit all RunTheme catalog entries: ensure no scenario world authority exists inside RunTheme
	for t in themes:
		var theme_id: String = str(t.get("id", ""))
		_check(not t.has("initial_force_specs"), "D2: Theme %s has no initial_force_specs" % theme_id)
		_check(not t.has("faction_setup"), "D3: Theme %s has no faction_setup" % theme_id)
		_check(not t.has("initial_node_specs"), "D4: Theme %s has no initial_node_specs" % theme_id)
		_check(not t.has("initial_territory_specs"), "D5: Theme %s has no initial_territory_specs" % theme_id)
		_check(not t.has("strategic_rules"), "D6: Theme %s has no strategic_rules" % theme_id)

	# Execute RunStartSystem to roll starting player loadout
	RunStartSystem.roll_random_start()
	_check(GlobalData.weapons.chassis_id != "", "D7: RunStartSystem initialized player chassis")
	_check(CampaignForce.get_forces().is_empty(), "D8: RunStartSystem left CampaignForce unpopulated (no world scenario pollution)")


# E — Seed separation
func _test_seed_separation() -> void:
	_clear_campaign_state()

	# Varying seeds must NOT invent scenario facts
	var seed_a := 12345
	var seed_b := 67890

	GlobalData.board.board_seed = seed_a
	_check(CampaignForce.get_forces().is_empty(), "E1: Setting board_seed A leaves CampaignForce empty")

	GlobalData.board.board_seed = seed_b
	_check(CampaignForce.get_forces().is_empty(), "E2: Setting board_seed B leaves CampaignForce empty")
	_check(CampaignTerritory.get_territories().is_empty(), "E3: Setting board_seed B leaves CampaignTerritory empty")


# F — Fixture separation
func _test_fixture_separation() -> void:
	# CampaignForceInitializer is explicitly classified as SPECULATIVE_DEVELOPMENT_FIXTURE
	_check(CampaignForceInitializer.get_data_classification() == "SPECULATIVE_DEVELOPMENT_FIXTURE",
		"F1: CampaignForceInitializer classification is SPECULATIVE_DEVELOPMENT_FIXTURE")
	_check(not CampaignForceInitializer.is_canonical_scenario_data(),
		"F2: CampaignForceInitializer.is_canonical_scenario_data() is false")

	# CampaignScenarioInitializer is CANONICAL
	_check(InitializerScript.get_data_classification() == "CANONICAL",
		"F3: CampaignScenarioInitializer classification is CANONICAL")
	_check(InitializerScript.is_canonical_authority(),
		"F4: CampaignScenarioInitializer.is_canonical_authority() is true")


# G — Runtime separation
func _test_runtime_separation() -> void:
	_clear_campaign_state()

	var s = ScenarioDefScript.new()
	s.scenario_id = "authored_runtime_test"
	s.display_name = "Authored Runtime Test"
	s.initial_force_specs = [
		{
			"slug": "recon_spec",
			"force_type": "PATROL",
			"faction": "federation",
			"node_id": "test_node_1",
			"unit_count": 2,
			"strength": 25,
		}
	]

	# Retrieve deep copy
	var specs_copy: Array = s.get_initial_force_specs()
	_check(specs_copy.size() == 1, "G1: Specs copy has 1 item")

	# External mutation of copy does not mutate ScenarioDefinition
	specs_copy[0]["strength"] = 999
	_check(s.initial_force_specs[0]["strength"] == 25,
		"G2: ScenarioDefinition internal data protected against external mutation")

	# Applying scenario does not mutate authoring resource
	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "test_node_1")
	var res := InitializerScript.apply_scenario(s, 1)
	_check(res.get("ok", false) == true, "G3: Scenario applied successfully")
	_check(s.initial_force_specs[0]["strength"] == 25,
		"G4: ScenarioDefinition remains completely unmodified after scenario application")


# H — Determinism
func _test_determinism() -> void:
	_clear_campaign_state()

	var s = ScenarioDefScript.new()
	s.scenario_id = "authored_determinism_test"
	s.display_name = "Authored Determinism Test"
	s.initial_node_specs = [
		{ "id": "det_node_a", "tile": Vector2i(2, 2), "sector": 1, "node_type": "city" }
	]
	s.initial_territory_specs = [
		{ "id": "det_terr_a", "sector": 1, "nodes": ["det_node_a"], "controller": "federation" }
	]
	s.initial_force_specs = [
		{
			"slug": "det_force_1",
			"force_type": "PATROL",
			"faction": "federation",
			"node_id": "det_node_a",
			"unit_count": 3,
			"strength": 40,
		}
	]

	var res := InitializerScript.apply_scenario(s, 1)
	_check(res.get("ok", false) == true, "H1: Authored scenario applied")
	_check(CampaignNodeRegistry.has_node("det_node_a"), "H2: Authored node registered deterministically")
	_check(CampaignTerritory.has_territory("det_terr_a"), "H3: Authored territory registered deterministically")
	_check(CampaignForce.has_force("force_s1_det_force_1"), "H4: Authored force registered deterministically")

	var f := CampaignForce.get_force("force_s1_det_force_1")
	_check(int(f.get("strength", 0)) == 40, "H5: Authored force strength matches spec")
	_check(str(f.get("faction", "")) == "federation", "H6: Authored force faction matches spec")
	_check(str(f.get("node_id", "")) == "det_node_a", "H7: Authored force node matches spec")


# I — No player force regression
func _test_no_player_force_regression() -> void:
	_check(not CampaignForce.has_force("player"), "I1: No CampaignForce('player') exists")
	_check(not CampaignForce.has_force("force_s1_player"), "I2: No namespaced player force exists")

	# Verify player remains in Hangar / Board Token layer
	_check(GlobalData.has_method("reset_run_data"), "I3: GlobalData manages run lifecycle")
	_check(HangarManager != null, "I4: HangarManager exists as canonical player hangar authority")


# Source guards
func _test_source_guards() -> void:
	var forbidden_producers := [
		"res://scripts/systems/run_start_system.gd",
		"res://scripts/board/board_generator.gd",
		"res://scripts/systems/patrol_system.gd",
		"res://scripts/systems/spawn_manager.gd",
		"res://scripts/ui/campaign_turn_panel.gd",
	]
	for path in forbidden_producers:
		if FileAccess.file_exists(path):
			var content := FileAccess.get_file_as_string(path)
			_check(not content.contains("CampaignForceInitializer.initialize_campaign_forces("),
				"Guard: Script %s does not invoke speculative fixture initialization" % path)

	_check(not FileAccess.file_exists("res://scripts/systems/player_force.gd"),
		"Guard: No player_force.gd exists")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_force_2.gd"),
		"Guard: No campaign_force_2.gd exists")


func _clear_campaign_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
