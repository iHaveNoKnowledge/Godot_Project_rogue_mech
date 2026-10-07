extends Node

## ---------------------------------------------------------------------------
## CANONICAL SCENARIO VERIFICATION — Phase 5AD
##
## Proves that Canonical Scenario #1 (frontier_skirmish.tres) is:
##   1. Fully loadable as an authored ScenarioDefinition resource.
##   2. 100% valid under ScenarioSchemaValidator with zero errors.
##   3. Properly registered as the single canonical scenario in the catalog.
##   4. Translates correctly into runtime state via CampaignScenarioInitializer.
##   5. Preserves all architectural invariants (no Player Force, no speculative fixtures).
##   6. Remains completely immutable across validation and runtime translation.
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
	print("Running Canonical Scenario verification...")
	_run_all_tests()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("CANONICAL_SCENARIO OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("CANONICAL_SCENARIO FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_resource_exists_and_identity()
	_test_schema_validation()
	_test_catalog_registration()
	_test_cross_references()
	_test_semantic_consistency()
	_test_initializer_can_apply()
	_test_runtime_translation()
	_test_authoring_immutability()


# A & B — Resource loading & Identity
func _test_resource_exists_and_identity() -> void:
	_check(ResourceLoader.exists(CANONICAL_SCENARIO_PATH), "A1: Canonical scenario resource exists at path")
	var s = load(CANONICAL_SCENARIO_PATH)
	_check(s != null, "A2: Canonical scenario loads successfully")
	_check(s.get_script() == ScenarioDefScript, "A3: Resource script is ScenarioDefinition")

	# Identity
	_check(s.scenario_id == "frontier_skirmish", "B1: scenario_id is 'frontier_skirmish'")
	_check(s.display_name == "Frontier Skirmish", "B2: display_name is 'Frontier Skirmish'")
	_check(not s.description.strip_edges().is_empty(), "B3: description is non-empty")
	_check(s.get_data_classification() == "CANONICAL", "B4: Data classification is CANONICAL")
	_check(s.is_canonical() == true, "B5: is_canonical() returns true")


# C — Schema Validation
func _test_schema_validation() -> void:
	var s = load(CANONICAL_SCENARIO_PATH)
	var cat = load(CANONICAL_CATALOG_PATH)

	var res: Dictionary = ScenarioSchemaValidatorScript.validate_scenario(s, cat)
	_check(res.get("valid", false) == true, "C1: ScenarioSchemaValidator validates scenario as true")
	_check((res.get("errors", []) as Array).is_empty(), "C2: Zero validation errors reported")
	if not (res.get("errors", []) as Array).is_empty():
		for err in res.get("errors", []):
			printerr("  Unexpected validation error: ", err)


# D — Catalog Registration
func _test_catalog_registration() -> void:
	_check(ResourceLoader.exists(CANONICAL_CATALOG_PATH), "D1: Canonical catalog resource exists")
	var cat = load(CANONICAL_CATALOG_PATH)
	_check(cat != null, "D2: Canonical catalog loads successfully")
	_check(cat.get_script() == ScenarioCatalogScript, "D3: Catalog is instance of ScenarioCatalogData")
	_check(cat.get_scenario_count() == 1, "D4: Catalog contains exactly one canonical scenario")
	_check(cat.has_scenario("frontier_skirmish"), "D5: Catalog contains 'frontier_skirmish'")

	var retrieved = cat.get_scenario("frontier_skirmish")
	_check(retrieved != null, "D6: Scenario retrieved from catalog is non-null")
	_check(retrieved.scenario_id == "frontier_skirmish", "D7: Retrieved scenario matches identity")

	var cat_validation := ScenarioSchemaValidatorScript.validate_catalog(cat)
	_check(cat_validation.get("valid", false) == true, "D8: ScenarioSchemaValidator validates catalog as valid")
	_check((cat_validation.get("errors", []) as Array).is_empty(), "D9: Catalog validation produces zero errors")


# E — Cross References
func _test_cross_references() -> void:
	var s = load(CANONICAL_SCENARIO_PATH)

	# Factions
	for fac in s.faction_setup:
		_check(FactionSystem.has_faction(str(fac)), "E1: Faction '%s' is registered in FactionSystem" % str(fac))

	# Nodes collect
	var node_ids: Dictionary = {}
	for n in s.initial_node_specs:
		node_ids[str(n["id"])] = true

	# Bases references
	var base_ids: Dictionary = {}
	for b in s.initial_base_specs:
		base_ids[str(b["id"])] = true
		_check(node_ids.has(str(b["node_id"])), "E2: Base '%s' references valid node '%s'" % [str(b["id"]), str(b["node_id"])])
		_check(FactionSystem.has_faction(str(b["controller"])), "E3: Base controller '%s' exists" % str(b["controller"]))

	# Territories references
	for t in s.initial_territory_specs:
		var members: Array = t.get("nodes", t.get("members", []))
		for m in members:
			_check(node_ids.has(str(m)), "E4: Territory '%s' member '%s' exists in nodes" % [str(t["id"]), str(m)])
		_check(FactionSystem.has_faction(str(t["controller"])), "E5: Territory controller '%s' exists" % str(t["controller"]))

	# Forces references
	for f in s.initial_force_specs:
		_check(FactionSystem.has_faction(str(f["faction"])), "E6: Force faction '%s' exists" % str(f["faction"]))
		_check(node_ids.has(str(f["node_id"])), "E7: Force node '%s' exists" % str(f["node_id"]))
		if f.has("base_id") and str(f["base_id"]) != "":
			_check(base_ids.has(str(f["base_id"])), "E8: Force base '%s' exists" % str(f["base_id"]))


# S — Semantic Consistency (Phase 5AD-R)
func _test_semantic_consistency() -> void:
	var s = load(CANONICAL_SCENARIO_PATH)

	# S1: Faction IDs vs force_type distinction
	# Scenario factions are: federation, zeon, outland (NO scavenger faction)
	_check(s.faction_setup.size() == 3, "S1: Exactly 3 participating factions")
	_check(s.faction_setup.has("federation"), "S1a: Participating faction 'federation'")
	_check(s.faction_setup.has("zeon"), "S1b: Participating faction 'zeon'")
	_check(s.faction_setup.has("outland"), "S1c: Participating faction 'outland'")
	_check(not s.faction_setup.has("scavenger"), "S1d: 'scavenger' is NOT a participating faction")

	for f in s.initial_force_specs:
		_check(s.faction_setup.has(str(f["faction"])), "S2: Force faction '%s' is an intentional participating faction" % str(f["faction"]))
		if str(f.get("slug", "")) == "outland_scavengers":
			_check(str(f["faction"]) == "outland", "S3a: Outland force faction is 'outland'")
			_check(str(f["force_type"]) == "SCAVENGER", "S3b: Outland force doctrine is SCAVENGER (force_type != faction)")

	# S4: Territory and node semantics
	var alpha_terr: Dictionary = {}
	var beta_terr: Dictionary = {}
	for t in s.initial_territory_specs:
		if str(t["id"]) == "terr_frontier_sector_alpha":
			alpha_terr = t
		elif str(t["id"]) == "terr_frontier_sector_beta":
			beta_terr = t

	_check(alpha_terr.get("controller") == "federation", "S4a: Sector Alpha controlled by federation")
	var alpha_nodes: Array = alpha_terr.get("nodes", alpha_terr.get("members", []))
	_check(alpha_nodes.has("node_frontier_safehouse") and alpha_nodes.has("node_frontier_city"), "S4b: Sector Alpha contains safehouse and city")

	_check(beta_terr.get("controller") == "zeon", "S4c: Sector Beta controlled by zeon")
	var beta_nodes: Array = beta_terr.get("nodes", beta_terr.get("members", []))
	_check(beta_nodes.has("node_frontier_depot") and beta_nodes.has("node_frontier_outpost"), "S4d: Sector Beta contains depot and outpost")

	# S5: Bases & controllers
	for b in s.initial_base_specs:
		if str(b["id"]) == "base_frontier_garrison":
			_check(str(b["controller"]) == "federation", "S5a: Garrison base controlled by federation")
			_check(str(b["node_id"]) == "node_frontier_city", "S5b: Garrison base located at city in Sector Alpha")
		elif str(b["id"]) == "base_frontier_stronghold":
			_check(str(b["controller"]) == "zeon", "S5c: Stronghold base controlled by zeon")
			_check(str(b["node_id"]) == "node_frontier_outpost", "S5d: Stronghold base located at outpost in Sector Beta")

	# S6: Relationships
	var rels: Dictionary = s.initial_relationships
	_check(rels.get("federation:zeon", -1) == 0, "S6a: Federation <-> Zeon is HOSTILE (0)")
	_check(rels.get("federation:outland", -1) == 1, "S6b: Federation <-> Outland is NEUTRAL (1)")
	_check(rels.get("zeon:outland", -1) == 1, "S6c: Zeon <-> Outland is NEUTRAL (1)")
	for rel_key in rels:
		_check(rels[rel_key] != 2, "S6d: No factions have ALLIED status (%s != 2)" % str(rel_key))

	# S7: Strategic rules coherence
	var rules: Dictionary = s.strategic_rules
	_check(rules.get("turn_limit", 0) == 30, "S7a: Turn limit is 30")
	_check(rules.get("victory_condition", "") == "secure_frontier_sector", "S7b: Victory condition is 'secure_frontier_sector'")
	_check(rules.get("defeat_condition", "") == "turn_limit_exceeded", "S7c: Defeat condition is 'turn_limit_exceeded' (replaces misleading all_allies_destroyed)")


# F — Initializer can_apply
func _test_initializer_can_apply() -> void:
	var s = load(CANONICAL_SCENARIO_PATH)
	_check(InitializerScript.can_apply(s) == true, "F1: CampaignScenarioInitializer.can_apply returns true")


# G — Runtime Translation
func _test_runtime_translation() -> void:
	_clear_campaign_state()

	var s = load(CANONICAL_SCENARIO_PATH)
	var result: Dictionary = InitializerScript.apply_scenario(s, 1)

	_check(result.get("ok", false) == true, "G1: apply_scenario reports ok=true")
	_check(result.get("applied", false) == true, "G2: apply_scenario reports applied=true")
	_check(result.get("reason", "") == "success", "G3: apply_scenario reason is 'success'")

	# Translated nodes
	var nodes_created: Array = result.get("nodes_created", [])
	_check(nodes_created.size() == 4, "G4: Exactly 4 strategic nodes created")
	for nid in ["node_frontier_safehouse", "node_frontier_city", "node_frontier_depot", "node_frontier_outpost"]:
		_check(CampaignNodeRegistry.has_node(nid), "G5: Node '%s' registered in CampaignNodeRegistry" % nid)

	# Translated territories
	var territories_created: Array = result.get("territories_created", [])
	_check(territories_created.size() == 2, "G6: Exactly 2 territories created")
	_check(CampaignTerritory.has_territory("terr_frontier_sector_alpha"), "G7: Sector Alpha territory registered")
	_check(CampaignTerritory.has_territory("terr_frontier_sector_beta"), "G8: Sector Beta territory registered")

	# Translated bases
	var bases_created: Array = result.get("bases_created", [])
	_check(bases_created.size() == 2, "G9: Exactly 2 bases created")
	_check(CampaignBase.has_base("base_frontier_garrison"), "G10: Federation garrison base registered")
	_check(CampaignBase.has_base("base_frontier_stronghold"), "G11: Zeon stronghold base registered")

	# Translated forces
	var forces_created: Array = result.get("forces_created", [])
	_check(forces_created.size() == 3, "G12: Exactly 3 forces created")
	_check(CampaignForce.has_force("force_s1_fed_vanguard"), "G13: Federation vanguard force registered")
	_check(CampaignForce.has_force("force_s1_zeon_raiders"), "G14: Zeon raiders force registered")
	_check(CampaignForce.has_force("force_s1_outland_scavengers"), "G15: Outland scavengers force registered")

	# Verify composition and attributes
	var fed_f := CampaignForce.get_force("force_s1_fed_vanguard")
	_check(fed_f.get("faction") == "federation", "G16: Federation force faction matches")
	_check(fed_f.get("unit_count") == 2, "G17: Federation force unit_count matches")
	_check(fed_f.get("strength") == 25, "G18: Federation force strength matches")

	# Invariants
	_check(not CampaignForce.has_force("force_s1_player"), "G19: No Player CampaignForce exists")
	_check(CampaignForce.get_forces().size() == 3, "G20: Total CampaignForce count is exactly 3")


# H — Immutability
func _test_authoring_immutability() -> void:
	var s = load(CANONICAL_SCENARIO_PATH)
	_check(s.scenario_id == "frontier_skirmish", "H1: scenario_id unmutated")
	_check(s.initial_force_specs.size() == 3, "H2: initial_force_specs count unmutated")
	_check(s.initial_node_specs.size() == 4, "H3: initial_node_specs count unmutated")
	_check(s.initial_territory_specs.size() == 2, "H4: initial_territory_specs count unmutated")
	_check(s.initial_base_specs.size() == 2, "H5: initial_base_specs count unmutated")


func _clear_campaign_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()


func _print_summary() -> void:
	print("==================================================")
	print("CANONICAL SCENARIO VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CANONICAL_SCENARIO_VERIFICATION_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CANONICAL_SCENARIO_TESTS_PASSED")
		get_tree().quit(0)
