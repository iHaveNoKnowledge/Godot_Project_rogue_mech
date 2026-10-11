extends Node
## ---------------------------------------------------------------------------
## CANONICAL SCENARIO PURITY VERIFICATION — Phase 5AD.
##
## Proves the 5AD contract on the REAL canonical scenario
## (res://resources/data/scenarios/frontier_skirmish.tres) and its catalog:
##   1. Exactly one canonical scenario exists, deterministically loadable.
##   2. Repeated validation yields byte-identical results.
##   3. Validation is pure: registries, relations, turn counter, C4 Heat /
##      Detection, and player-node state are all byte-identical afterwards
##      (seeded C4 state is preserved, not erased).
##   4. Invalid input fails with actionable error codes, never crashes.
## Structural validity itself (duplicates, dangling refs, forbidden fields)
## is covered by campaign_scenario_schema_validator_verify and
## campaign_canonical_scenario_verify; this suite covers only the purity
## and singularity guarantees those suites do not assert.
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CANONICAL_CATALOG_PATH := "res://resources/data/scenario_definition_catalog.tres"

var _checks_passed := 0
var _checks_failed := 0


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("CANONICAL_PURITY OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("CANONICAL_PURITY FAIL: %s" % description)


func _snap_world() -> Dictionary:
	return {
		"nodes": JSON.stringify(CampaignNodeRegistry.get_nodes()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"territories": JSON.stringify(CampaignTerritory.serialize()),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"relations": JSON.stringify(FactionSystem.serialize_relations()),
		"turn": CampaignTurnExecutive.get_turn(),
		"heat": JSON.stringify(CampaignStrategicHeat.serialize()),
		"detection": JSON.stringify(CampaignStrategicDetection.serialize()),
		"player_node": str(GlobalData.current_campaign_player_node_id),
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


func _ready() -> void:
	print("Running Canonical Scenario purity verification (Phase 5AD)...")
	_clear_world()
	_test_singularity_and_loading()
	_test_repeated_validation_determinism()
	_test_validation_purity()
	_test_invalid_input_safety()
	_clear_world()
	_print_summary()


func _test_singularity_and_loading() -> void:
	_check(ResourceLoader.exists(CANONICAL_SCENARIO_PATH), "A1: Canonical scenario resource exists")
	var s1 = load(CANONICAL_SCENARIO_PATH)
	var s2 = load(CANONICAL_SCENARIO_PATH)
	_check(s1 != null and s2 != null, "A2: Canonical scenario loads repeatedly")
	_check(s1.get_script() == ScenarioDefScript, "A3: Resource script is ScenarioDefinition")
	_check(str(s1.get("scenario_id")) == "frontier_skirmish", "A4: Stable canonical id on every load")
	_check(ResourceLoader.exists(CANONICAL_CATALOG_PATH), "A5: Catalog resource exists")
	var c1 = load(CANONICAL_CATALOG_PATH)
	var c2 = load(CANONICAL_CATALOG_PATH)
	_check(c1.get_scenario_count() == 1 and c2.get_scenario_count() == 1, "A6: Catalog holds exactly one scenario on every load")
	_check(str(c1.get_scenario("frontier_skirmish").get("scenario_id")) == "frontier_skirmish", "A7: Single entry resolves to the canonical id")


func _test_repeated_validation_determinism() -> void:
	var s = load(CANONICAL_SCENARIO_PATH)
	var cat = load(CANONICAL_CATALOG_PATH)
	var r1: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(s, cat)
	var r2: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(s, cat)
	_check(bool(r1.get("valid", false)), "B1: Canonical scenario validates")
	_check((r1.get("errors", []) as Array).is_empty(), "B2: Zero validation errors")
	_check(JSON.stringify(r1) == JSON.stringify(r2), "B3: Repeated validation is byte-identical")
	var c1: Dictionary = ScenarioSchemaValidatorScript.validate_catalog(cat)
	var c2: Dictionary = ScenarioSchemaValidatorScript.validate_catalog(cat)
	_check(bool(c1.get("valid", false)), "B4: Catalog validates")
	_check(JSON.stringify(c1) == JSON.stringify(c2), "B5: Repeated catalog validation is byte-identical")
	_check(r1.has("warnings") and r1.get("warnings") is Array, "B6: Result carries a warnings array")


func _test_validation_purity() -> void:
	# Seed live state (including C4) that validation must neither mutate nor erase.
	CampaignStrategicHeat.set_node_heat("node_probe", 5)
	CampaignStrategicDetection.report_location("federation", "node_probe", 3, "combat")
	var before := _snap_world()
	var s = load(CANONICAL_SCENARIO_PATH)
	var cat = load(CANONICAL_CATALOG_PATH)
	ScenarioSchemaValidatorScript.validate_scenario(s, cat)
	ScenarioSchemaValidatorScript.validate_catalog(cat)
	ScenarioSchemaValidatorScript.validate_scenario(s, cat)
	var after := _snap_world()
	for k in before:
		_check(str(after.get(k, "")) == str(before.get(k, "")), "C: '%s' unchanged by validation" % str(k))
	_check(CampaignStrategicHeat.get_node_heat("node_probe") == 5, "C: Seeded heat preserved (not erased)")
	_check(CampaignStrategicDetection.is_located("federation"), "C: Seeded intel preserved (not erased)")
	_check(CampaignTurnExecutive.get_turn() == int(before.get("turn", -1)), "C: Turn counter unadvanced by validation")


func _test_invalid_input_safety() -> void:
	var null_res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(null)
	_check(bool(null_res.get("valid", true)) == false, "D1: Null scenario rejected without crash")
	var codes: Array = []
	for err in null_res.get("errors", []):
		codes.append(str((err as Dictionary).get("code", "")))
	_check(codes.has("NULL_SCENARIO"), "D2: Actionable NULL_SCENARIO error code reported")


func _print_summary() -> void:
	print("==================================================")
	print("CANONICAL SCENARIO PURITY VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CANONICAL_SCENARIO_PURITY_VERIFICATION_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CANONICAL_SCENARIO_PURITY_TESTS_PASSED")
		get_tree().quit(0)
