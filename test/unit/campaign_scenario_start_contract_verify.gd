extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN SCENARIO SELECTION & START CONTRACT VERIFICATION — Phase 5AE
##
## Verifies the complete lifecycle and contract:
##   Scenario Selection
##           ↓
##   Selected Scenario Identity
##           ↓
##   Scenario Definition Resolution
##           ↓
##   Schema Validation
##           ↓
##   Campaign Scenario Initialization
##           ↓
##   Campaign Runtime Start
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CANONICAL_CATALOG_PATH := "res://resources/data/scenario_definition_catalog.tres"

var _checks_passed := 0
var _checks_failed := 0


func _ready() -> void:
	print("Running Campaign Scenario Start Contract verification...")
	_run_all_tests()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("START_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("START_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_catalog_resolution_and_integrity()
	_test_valid_selection_and_identity()
	_test_missing_scenario_abort()
	_test_unknown_scenario_abort()
	_test_invalid_scenario_rejection_and_atomicity()
	_test_scenario_immutability()
	_test_board_seed_independence()
	_test_run_theme_independence()
	_test_player_invariant()
	_test_no_speculative_fallback()
	_test_repeat_start_behavior()
	_test_save_load_persistence()


# F — Catalog Integrity
func _test_catalog_resolution_and_integrity() -> void:
	_clear_all_state()
	_check(ResourceLoader.exists(CANONICAL_CATALOG_PATH), "F1: Canonical catalog resource exists")
	var catalog: ScenarioCatalogData = load(CANONICAL_CATALOG_PATH) as ScenarioCatalogData
	_check(catalog != null, "F2: Canonical catalog loads")
	_check(catalog.has_scenario("frontier_skirmish"), "F3: frontier_skirmish is registered in catalog")
	var res = catalog.get_scenario("frontier_skirmish")
	_check(res != null, "F4: frontier_skirmish resolves to non-null ScenarioDefinition")
	_check(res.scenario_id == "frontier_skirmish", "F5: Resolved scenario matches id")


# A & B — Valid Selection & Active Scenario Identity
func _test_valid_selection_and_identity() -> void:
	_clear_all_state()

	var receipt: Dictionary = RunStartSystem.start_campaign_scenario("frontier_skirmish")

	_check(receipt.get("ok", false) == true, "A1: start_campaign_scenario returns ok=true")
	_check(receipt.get("started", false) == true, "A2: start_campaign_scenario returns started=true")
	_check(receipt.get("reason", "") == "success", "A3: start_campaign_scenario reason is 'success'")
	_check(receipt.get("scenario_id", "") == "frontier_skirmish", "A4: Receipt scenario_id is 'frontier_skirmish'")

	# Runtime population created
	_check(CampaignNodeRegistry.get_nodes().size() == 4, "A5: Exactly 4 strategic nodes initialized")
	_check(CampaignTerritory.get_territories().size() == 2, "A6: Exactly 2 territories initialized")
	_check(CampaignBase.get_bases().size() == 2, "A7: Exactly 2 bases initialized")
	_check(CampaignForce.get_forces().size() == 3, "A8: Exactly 3 forces initialized")

	# Authored relationships applied
	_check(FactionSystem.get_relation("federation", "zeon") == 0, "A9: Federation <-> Zeon hostile relationship applied")
	_check(FactionSystem.get_relation("federation", "outland") == 1, "A10: Federation <-> Outland neutral relationship applied")
	_check(FactionSystem.get_relation("zeon", "outland") == 1, "A11: Zeon <-> Outland neutral relationship applied")

	# B: Active scenario identity
	_check(RunStartSystem.get_current_campaign_scenario_id() == "frontier_skirmish",
		"B1: RunStartSystem.get_current_campaign_scenario_id() returns 'frontier_skirmish'")
	_check(GlobalData.current_campaign_scenario_id == "frontier_skirmish",
		"B2: GlobalData.current_campaign_scenario_id is 'frontier_skirmish'")


# C — Missing Scenario Selection Abort
func _test_missing_scenario_abort() -> void:
	_clear_all_state()

	var receipt: Dictionary = RunStartSystem.start_campaign_scenario("")

	_check(receipt.get("ok", false) == false, "C1: Missing scenario_id returns ok=false")
	_check(receipt.get("started", false) == false, "C2: Missing scenario_id returns started=false")
	_check(receipt.get("reason", "") == "missing_scenario_id", "C3: Reason is 'missing_scenario_id'")

	# Atomicity: zero runtime state initialized
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "C4: Zero nodes created on missing selection")
	_check(CampaignTerritory.get_territories().is_empty(), "C5: Zero territories created on missing selection")
	_check(CampaignBase.get_bases().is_empty(), "C6: Zero bases created on missing selection")
	_check(CampaignForce.get_forces().is_empty(), "C7: Zero forces created on missing selection")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "", "C8: Active scenario_id remains empty")


# D — Unknown Scenario Selection Abort
func _test_unknown_scenario_abort() -> void:
	_clear_all_state()

	var receipt: Dictionary = RunStartSystem.start_campaign_scenario("does_not_exist")

	_check(receipt.get("ok", false) == false, "D1: Unknown scenario returns ok=false")
	_check(receipt.get("started", false) == false, "D2: Unknown scenario returns started=false")
	_check(receipt.get("reason", "") == "unknown_scenario", "D3: Reason is 'unknown_scenario'")

	# Atomicity: zero runtime state initialized
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "D4: Zero nodes created on unknown scenario")
	_check(CampaignTerritory.get_territories().is_empty(), "D5: Zero territories created on unknown scenario")
	_check(CampaignBase.get_bases().is_empty(), "D6: Zero bases created on unknown scenario")
	_check(CampaignForce.get_forces().is_empty(), "D7: Zero forces created on unknown scenario")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "", "D8: Active scenario_id remains empty")


# E — Invalid Scenario Rejection & Atomicity
func _test_invalid_scenario_rejection_and_atomicity() -> void:
	_clear_all_state()

	# Construct a test fixture invalid scenario definition (violates schema: missing nodes referenced by base)
	var invalid_def = ScenarioDefScript.new()
	invalid_def.scenario_id = "test_invalid_scenario"
	invalid_def.display_name = "Test Invalid"
	invalid_def.description = "Test invalid scenario definition"
	invalid_def.faction_setup = ["federation", "unknown_pirates"]
	invalid_def.initial_node_specs = []
	invalid_def.initial_base_specs = []
	invalid_def.initial_force_specs = []
	invalid_def.initial_territory_specs = []
	invalid_def.initial_relationships = {}
	invalid_def.strategic_rules = {}

	# Create a custom test catalog containing only the invalid scenario
	var test_cat = ScenarioCatalogScript.new()
	test_cat.scenarios = [invalid_def]

	var receipt: Dictionary = RunStartSystem.start_campaign_scenario("test_invalid_scenario", test_cat)

	_check(receipt.get("ok", false) == false, "E1: Invalid scenario returns ok=false")
	_check(receipt.get("started", false) == false, "E2: Invalid scenario returns started=false")
	_check(receipt.get("reason", "") == "validation_failed", "E3: Reason is 'validation_failed'")
	_check(not (receipt.get("errors", []) as Array).is_empty(), "E4: Structured validation errors returned")

	# Atomicity: zero runtime state published
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "E5: Zero nodes published on validation failure")
	_check(CampaignTerritory.get_territories().is_empty(), "E6: Zero territories published on validation failure")
	_check(CampaignBase.get_bases().is_empty(), "E7: Zero bases published on validation failure")
	_check(CampaignForce.get_forces().is_empty(), "E8: Zero forces published on validation failure")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "", "E9: Active scenario_id remains empty")


# G — ScenarioDefinition Immutability
func _test_scenario_immutability() -> void:
	_clear_all_state()

	var s = load(CANONICAL_SCENARIO_PATH)
	var orig_id: String = s.scenario_id
	var orig_nodes_count: int = s.initial_node_specs.size()
	var orig_forces_count: int = s.initial_force_specs.size()
	var orig_territories_count: int = s.initial_territory_specs.size()
	var orig_bases_count: int = s.initial_base_specs.size()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Verify authored Resource was NOT mutated during or after start
	_check(s.scenario_id == orig_id, "G1: ScenarioDefinition.scenario_id unmutated")
	_check(s.initial_node_specs.size() == orig_nodes_count, "G2: initial_node_specs count unmutated")
	_check(s.initial_force_specs.size() == orig_forces_count, "G3: initial_force_specs count unmutated")
	_check(s.initial_territory_specs.size() == orig_territories_count, "G4: initial_territory_specs count unmutated")
	_check(s.initial_base_specs.size() == orig_bases_count, "G5: initial_base_specs count unmutated")


# H — Board Seed Independence
func _test_board_seed_independence() -> void:
	_clear_all_state()

	GlobalData.board.board_seed = 42
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	_check(GlobalData.board.board_seed == 42, "H1: board_seed is preserved independently of scenario start")
	var s = load(CANONICAL_SCENARIO_PATH)
	_check(not ("board_seed" in s), "H2: ScenarioDefinition does not contain board_seed")


# I — RunTheme Independence
func _test_run_theme_independence() -> void:
	_clear_all_state()

	GlobalData.narrative.theme_id = "valkyrion_merc"
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	_check(GlobalData.narrative.theme_id == "valkyrion_merc", "I1: RunTheme is not mutated by scenario start")
	var s = load(CANONICAL_SCENARIO_PATH)
	_check(not ("theme_id" in s), "I2: ScenarioDefinition does not contain theme_id")


# J — Player Invariant
func _test_player_invariant() -> void:
	_clear_all_state()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	_check(not CampaignForce.has_force("force_s1_player"), "J1: No player CampaignForce exists")
	_check(not CampaignForce.has_force("player_force"), "J2: No player_force exists")
	for f in CampaignForce.get_forces():
		_check(f.get("force_type", "") != "PLAYER", "J3: Force type is not PLAYER (%s)" % f.get("id", ""))


# K — No Speculative Fallback
func _test_no_speculative_fallback() -> void:
	_clear_all_state()

	# Start unknown scenario
	var bad_res := RunStartSystem.start_campaign_scenario("missing_x")
	_check(bad_res.get("ok", false) == false, "K1: Unknown start rejected")
	_check(CampaignForce.get_forces().is_empty(), "K2: Zero forces created; no speculative fixture fallback")


# L — Repeat-Start Behavior
func _test_repeat_start_behavior() -> void:
	_clear_all_state()

	# Start 1
	var res1 := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res1.get("ok", false) == true, "L1: First start succeeded")
	_check(CampaignForce.get_forces().size() == 3, "L2: Exactly 3 forces after start 1")
	_check(CampaignNodeRegistry.get_nodes().size() == 4, "L3: Exactly 4 nodes after start 1")

	# Start 2 (repeat start)
	var res2 := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res2.get("ok", false) == true, "L4: Second start succeeded cleanly")
	_check(CampaignForce.get_forces().size() == 3, "L5: Exactly 3 forces after start 2 (no duplicates)")
	_check(CampaignNodeRegistry.get_nodes().size() == 4, "L6: Exactly 4 nodes after start 2 (no duplicates)")
	_check(CampaignTerritory.get_territories().size() == 2, "L7: Exactly 2 territories after start 2")
	_check(CampaignBase.get_bases().size() == 2, "L8: Exactly 2 bases after start 2")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "frontier_skirmish", "L9: Active scenario_id is 'frontier_skirmish'")


# M — Save / Load Persistence Boundary
func _test_save_load_persistence() -> void:
	_clear_all_state()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(GlobalData.current_campaign_scenario_id == "frontier_skirmish", "M1: Scenario ID active before save")

	# Save run
	var saved := GlobalData.save_run()
	_check(saved == true, "M2: GlobalData.save_run() succeeded")

	# Clear runtime state
	GlobalData.reset_run_data()
	_check(GlobalData.current_campaign_scenario_id == "", "M3: GlobalData.reset_run_data() cleared scenario_id")
	_check(CampaignForce.get_forces().is_empty(), "M4: Forces cleared by reset")

	# Load run
	var loaded := GlobalData.load_run()
	_check(loaded == true, "M5: GlobalData.load_run() succeeded")
	_check(GlobalData.current_campaign_scenario_id == "frontier_skirmish", "M6: Scenario ID restored from save")
	_check(CampaignForce.get_forces().size() == 3, "M7: Forces restored from save")
	_check(CampaignTerritory.get_territories().size() == 2, "M8: Territories restored from save")
	_check(CampaignBase.get_bases().size() == 2, "M9: Bases restored from save")


func _clear_all_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	GlobalData.current_campaign_scenario_id = ""


func _print_summary() -> void:
	print("==================================================")
	print("CAMPAIGN SCENARIO START CONTRACT SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CAMPAIGN_SCENARIO_START_CONTRACT_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_SCENARIO_START_CONTRACT_TESTS_PASSED")
		get_tree().quit(0)
