extends Node

## ---------------------------------------------------------------------------
## SCENARIO SCHEMA VALIDATOR VERIFICATION — Phase 5AC
##
## Tests that ScenarioSchemaValidator reliably rejects structurally invalid
## authored ScenarioDefinition data and protects runtime campaign state.
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")

var _checks_passed := 0
var _checks_failed := 0


func _ready() -> void:
	print("Running ScenarioSchemaValidator verification...")
	_run_all_tests()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("SCHEMA_VALIDATOR OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("SCHEMA_VALIDATOR FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_top_level_contracts()
	_test_faction_validation()
	_test_force_validation()
	_test_node_validation()
	_test_territory_validation()
	_test_base_validation()
	_test_relationship_validation()
	_test_strategic_rules_validation()
	_test_cross_reference_validation()
	_test_immutability()
	_test_empty_canonical_catalog()
	_test_initializer_safety()


func _make_valid_base_scenario() -> ScenarioDefinition:
	var s = ScenarioDefScript.new()
	s.scenario_id = "canonical_test_scenario"
	s.display_name = "Canonical Test Scenario"
	s.description = "A valid test scenario description."
	s.faction_setup = ["federation", "zeon"]
	s.initial_node_specs = [
		{ "id": "node_hub_1", "node_type": "city", "strategic_importance": 5 }
	]
	s.initial_territory_specs = [
		{ "id": "terr_sector_a", "members": ["node_hub_1"], "controller": "federation", "state": 1 }
	]
	s.initial_base_specs = [
		{ "id": "base_alpha", "node_id": "node_hub_1", "base_type": "OUTPOST", "controller": "federation", "state": 0 }
	]
	s.initial_force_specs = [
		{
			"slug": "alpha_recon",
			"force_type": "PATROL",
			"faction": "federation",
			"node_id": "node_hub_1",
			"unit_count": 2,
			"strength": 20,
			"base_id": "base_alpha"
		}
	]
	s.initial_relationships = {
		"federation:zeon": 0
	}
	s.strategic_rules = {
		"turn_limit": 25,
		"victory_condition": "secure_sector_a"
	}
	return s


# 1. Top-Level
func _test_top_level_contracts() -> void:
	# Null scenario
	var null_res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(null)
	_check(null_res.valid == false, "1.1: Null scenario is rejected")
	_check(null_res.errors.size() > 0, "1.2: Null scenario produces error")

	# Valid empty scenario (only id and display_name provided)
	var empty_s = ScenarioDefScript.new()
	empty_s.scenario_id = "valid_empty_scenario"
	empty_s.display_name = "Valid Empty Scenario"
	var empty_res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(empty_s)
	_check(empty_res.valid == true, "1.3: Valid empty ScenarioDefinition passes validation")
	_check(empty_res.errors.is_empty(), "1.4: Valid empty ScenarioDefinition has zero errors")

	# Missing / empty scenario_id
	var no_id_s = ScenarioDefScript.new()
	no_id_s.scenario_id = ""
	no_id_s.display_name = "No ID"
	var no_id_res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(no_id_s)
	_check(no_id_res.valid == false, "1.5: Missing scenario_id is rejected")

	# Invalid characters in scenario_id
	var bad_id_s = ScenarioDefScript.new()
	bad_id_s.scenario_id = "bad ID with spaces!"
	bad_id_s.display_name = "Bad ID"
	var bad_id_res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(bad_id_s)
	_check(bad_id_res.valid == false, "1.6: scenario_id with spaces or punctuation is rejected")

	# Missing display_name
	var no_name_s = ScenarioDefScript.new()
	no_name_s.scenario_id = "valid_id"
	no_name_s.display_name = ""
	var no_name_res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(no_name_s)
	_check(no_name_res.valid == false, "1.7: Empty display_name is rejected")


# 2. Factions
func _test_faction_validation() -> void:
	var s := _make_valid_base_scenario()
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == true, "2.1: Valid base scenario passes")

	# Unknown faction
	s.faction_setup = ["federation", "martian_pirates"]
	var unk_res := ScenarioSchemaValidatorScript.validate_scenario(s)
	_check(unk_res.valid == false, "2.2: Unknown faction is rejected")

	# Duplicate faction in setup
	s.faction_setup = ["federation", "zeon", "federation"]
	var dup_res := ScenarioSchemaValidatorScript.validate_scenario(s)
	_check(dup_res.valid == false, "2.3: Duplicate faction in faction_setup is rejected")


# 3. Forces
func _test_force_validation() -> void:
	var s := _make_valid_base_scenario()

	# Duplicate force slug
	s.initial_force_specs.append({
		"slug": "alpha_recon", # duplicate
		"force_type": "CONVOY",
		"faction": "zeon",
		"node_id": "node_hub_1",
		"unit_count": 1,
		"strength": 10
	})
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.1: Duplicate force slug is rejected")

	# Unknown faction on force
	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["faction"] = "cyber_syndicate"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.2: Unknown faction on force is rejected")

	# Empty node_id
	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["node_id"] = ""
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.3: Empty node_id on force is rejected")

	# Invalid force type
	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["force_type"] = "DREADNOUGHT_TITAN"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.4: Invalid force_type is rejected")

	# Invalid unit_count (<= 0)
	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["unit_count"] = 0
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.5: Zero unit_count is rejected")

	s.initial_force_specs[0]["unit_count"] = -3
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.6: Negative unit_count is rejected")

	# Invalid strength (< 0)
	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["strength"] = -10
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.7: Negative strength is rejected")

	# Forbidden runtime fields on force
	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["orders"] = "attack_player"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.8: Forbidden runtime field 'orders' is rejected")

	s = _make_valid_base_scenario()
	s.initial_force_specs[0]["state"] = 1
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "3.9: Forbidden runtime field 'state' is rejected")


# 4. Nodes
func _test_node_validation() -> void:
	var s := _make_valid_base_scenario()

	# Duplicate node ID
	s.initial_node_specs.append({
		"id": "node_hub_1", # duplicate
		"node_type": "safehouse"
	})
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "4.1: Duplicate node id is rejected")

	# Invalid node type
	s = _make_valid_base_scenario()
	s.initial_node_specs[0]["node_type"] = "interstellar_orbital_station"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "4.2: Invalid node_type is rejected")

	# Invalid strategic importance (negative)
	s = _make_valid_base_scenario()
	s.initial_node_specs[0]["strategic_importance"] = -5
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "4.3: Negative strategic_importance is rejected")

	# Forbidden runtime fields on node
	s = _make_valid_base_scenario()
	s.initial_node_specs[0]["forces"] = ["force_alpha"]
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "4.4: Forbidden 'forces' array on node is rejected")

	s = _make_valid_base_scenario()
	s.initial_node_specs[0]["controller"] = "federation"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "4.5: Forbidden 'controller' ownership on node is rejected")


# 5. Territories
func _test_territory_validation() -> void:
	var s := _make_valid_base_scenario()

	# Duplicate territory id
	s.initial_territory_specs.append({
		"id": "terr_sector_a", # duplicate
		"members": ["node_hub_1"],
		"controller": "zeon"
	})
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "5.1: Duplicate territory id is rejected")

	# Invalid controller
	s = _make_valid_base_scenario()
	s.initial_territory_specs[0]["controller"] = "unknown_rebel_faction"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "5.2: Unknown territory controller is rejected")

	# Invalid member node ID
	s = _make_valid_base_scenario()
	s.initial_territory_specs[0]["members"] = ["unauthored_random_node"]
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "5.3: Dangling member node ID is rejected")

	# Territory without base remains valid
	s = _make_valid_base_scenario()
	s.initial_base_specs.clear()
	s.initial_force_specs[0].erase("base_id")
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == true, "5.4: Territory without base is completely valid")


# 6. Bases
func _test_base_validation() -> void:
	var s := _make_valid_base_scenario()

	# Duplicate base id
	s.initial_base_specs.append({
		"id": "base_alpha", # duplicate
		"node_id": "node_hub_1",
		"base_type": "OUTPOST"
	})
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "6.1: Duplicate base id is rejected")

	# Invalid base type
	s = _make_valid_base_scenario()
	s.initial_base_specs[0]["base_type"] = "DEATH_STAR"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "6.2: Invalid base_type is rejected")

	# Unknown base controller
	s = _make_valid_base_scenario()
	s.initial_base_specs[0]["controller"] = "alien_swarm"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "6.3: Unknown base controller is rejected")

	# Forbidden runtime fields on base
	s = _make_valid_base_scenario()
	s.initial_base_specs[0]["reinforcements"] = [1, 2, 3]
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "6.4: Forbidden 'reinforcements' queue on base is rejected")

	s = _make_valid_base_scenario()
	s.initial_base_specs[0]["supply"] = 500
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "6.5: Forbidden 'supply' inventory on base is rejected")


# 7. Relationships
func _test_relationship_validation() -> void:
	var s := _make_valid_base_scenario()

	# Unknown faction in key
	s.initial_relationships = { "federation:unknown_aliens": 0 }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "7.1: Unknown faction in relationships is rejected")

	# Self relationship
	s.initial_relationships = { "federation:federation": 3 }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "7.2: Self-relationship in relationships is rejected")

	# Malformed key (no delimiter)
	s.initial_relationships = { "federation_zeon": 0 }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "7.3: Malformed key without delimiter is rejected")

	# Invalid relation value
	s.initial_relationships = { "federation:zeon": 99 }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "7.4: Invalid relation value integer is rejected")


# 8. Strategic Rules (Strict Whitelist & Scalar Enforcement)
func _test_strategic_rules_validation() -> void:
	var s := _make_valid_base_scenario()

	# Supported scalar rules
	s.strategic_rules = {
		"turn_limit": 30,
		"victory_condition": "hold_the_line",
		"defeat_condition": "all_forces_destroyed"
	}
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == true, "8.1: Supported scalar strategic rules pass")

	# Unsupported rule key
	s.strategic_rules = { "arbitrary_custom_hack": 100 }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "8.2: Unsupported strategic rule key is rejected")

	# Nested Dictionary rejection (anti-escape-hatch)
	s.strategic_rules = { "turn_limit": { "nested_sub_rule": 5 } }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "8.3: Nested Dictionary in strategic_rules is rejected")

	# Nested Array rejection
	s.strategic_rules = { "victory_condition": ["win_a", "win_b"] }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "8.4: Nested Array in strategic_rules is rejected")

	# Runtime Object / Resource rejection
	s.strategic_rules = { "turn_limit": ScenarioDefScript.new() }
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "8.5: Resource/Object in strategic_rules is rejected")


# 9. Cross References
func _test_cross_reference_validation() -> void:
	var s := _make_valid_base_scenario()

	# Dangling base reference from force
	s.initial_force_specs[0]["base_id"] = "nonexistent_base_xyz"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "9.1: Dangling base reference is rejected")

	# Dangling territory reference from base
	s = _make_valid_base_scenario()
	s.initial_base_specs[0]["territory_id"] = "nonexistent_territory_xyz"
	_check(ScenarioSchemaValidatorScript.validate_scenario(s).valid == false, "9.2: Dangling territory reference from base is rejected")


# 10. Immutability
func _test_immutability() -> void:
	var s := _make_valid_base_scenario()
	var orig_id := s.scenario_id
	var orig_forces_size := s.initial_force_specs.size()
	var orig_strength: int = s.initial_force_specs[0]["strength"]

	var res := ScenarioSchemaValidatorScript.validate_scenario(s)
	_check(res.valid == true, "10.1: Scenario is valid")
	_check(s.scenario_id == orig_id, "10.2: ScenarioDefinition.scenario_id is unmutated")
	_check(s.initial_force_specs.size() == orig_forces_size, "10.3: Force specs array size is unmutated")
	_check(s.initial_force_specs[0]["strength"] == orig_strength, "10.4: Force specs data is unmutated")


# 11. Empty Canonical Catalog
func _test_empty_canonical_catalog() -> void:
	var cat = ScenarioCatalogScript.new()
	cat.scenarios = []
	var res := ScenarioSchemaValidatorScript.validate_catalog(cat)
	_check(res.valid == true, "11.1: Empty canonical scenario catalog is valid")
	_check(res.errors.is_empty(), "11.2: Empty canonical scenario catalog produces zero errors")


# 12. Initializer Safety
func _test_initializer_safety() -> void:
	CampaignForce.clear()
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()

	# Invalid scenario rejected before initialization
	var bad_s = ScenarioDefScript.new()
	bad_s.scenario_id = "bad_scenario"
	bad_s.display_name = "Bad Scenario"
	bad_s.initial_force_specs = [
		{ "slug": "bad_force", "force_type": "INVALID_TYPE", "faction": "unknown", "node_id": "", "unit_count": -1, "strength": -10 }
	]

	_check(InitializerScript.can_apply(bad_s) == false, "12.1: can_apply returns false for invalid scenario")
	var apply_res := InitializerScript.apply_scenario(bad_s, 1)
	_check(apply_res.get("ok", true) == false, "12.2: apply_scenario returns ok=false on invalid scenario")
	_check(apply_res.get("applied", true) == false, "12.3: apply_scenario reports applied=false")
	_check(CampaignForce.get_forces().is_empty(), "12.4: Zero forces created when invalid scenario is rejected")

	# Valid scenario passes
	var good_s := _make_valid_base_scenario()
	_check(InitializerScript.can_apply(good_s) == true, "12.5: can_apply returns true for valid scenario")
	var good_res := InitializerScript.apply_scenario(good_s, 1)
	_check(good_res.get("ok", false) == true, "12.6: apply_scenario returns ok=true on valid scenario")
	_check(good_res.get("applied", false) == true, "12.7: apply_scenario reports applied=true")
	_check(CampaignForce.get_forces().size() == 1, "12.8: Force registered from valid scenario")


func _print_summary() -> void:
	print("==================================================")
	print("SCENARIO SCHEMA VALIDATOR VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("SCENARIO_SCHEMA_VALIDATOR_VERIFICATION_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_SCENARIO_SCHEMA_VALIDATOR_TESTS_PASSED")
		get_tree().quit(0)
