extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN RUNTIME STATE INITIALIZATION & MUTATION BOUNDARY VERIFICATION
## Phase 5AF Contract Verification Suite
##
## Verifies the architectural contract:
##   AUTHORED SCENARIO DATA
##           ↓
##   CAMPAIGN RUNTIME INITIAL STATE
##           ↓
##   RUNTIME MUTATION
##
## Proves:
##   A. Scenario → runtime materialization
##   B. Runtime mutation does not mutate ScenarioDefinition
##   C. Reset isolation across consecutive starts
##   D. Scenario identity authoritative ownership
##   E. Board seed separation and immutability
##   F. RunTheme separation
##   G. Turn separation (current_turn vs strategic_rules.turn_limit)
##   H. Relationship separation (FactionSystem vs initial_relationships)
##   I. Force runtime independence (CampaignForce mutation isolation)
##   J. Territory runtime independence (CampaignTerritory mutation isolation)
##   K. Base runtime independence (CampaignBase mutation isolation)
##   L. Player invariant (no player CampaignForce created)
##   M. Failure isolation (atomic rollback on invalid starts)
##   N. Startup order & active boundary enforcement
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
	print("Running Campaign Runtime State Contract verification (Phase 5AF)...")
	_run_all_tests()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("RUNTIME_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("RUNTIME_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_scenario_runtime_materialization()
	_test_b_runtime_mutation_does_not_mutate_scenario_definition()
	_test_c_reset_isolation()
	_test_d_scenario_identity()
	_test_e_board_seed_separation()
	_test_f_run_theme_separation()
	_test_g_turn_separation()
	_test_h_relationship_separation()
	_test_i_force_runtime_independence()
	_test_j_territory_runtime_independence()
	_test_k_base_runtime_independence()
	_test_l_player_invariant()
	_test_m_failure_isolation()
	_test_n_startup_order_and_active_boundary()


func _clear_all_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionEconomySystem.reset()
	GlobalData.current_campaign_scenario_id = ""


# A. Scenario → runtime materialization
func _test_a_scenario_runtime_materialization() -> void:
	_clear_all_state()

	var receipt: Dictionary = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(receipt.get("ok", false) == true, "A1: start_campaign_scenario returns ok=true")
	_check(receipt.get("started", false) == true, "A2: start_campaign_scenario returns started=true")

	# Strategic nodes materialized
	_check(CampaignNodeRegistry.has_node("node_frontier_safehouse"), "A3: node_frontier_safehouse registered")
	_check(CampaignNodeRegistry.has_node("node_frontier_city"), "A4: node_frontier_city registered")
	_check(CampaignNodeRegistry.has_node("node_frontier_depot"), "A5: node_frontier_depot registered")
	_check(CampaignNodeRegistry.has_node("node_frontier_outpost"), "A6: node_frontier_outpost registered")
	var node_safe: Dictionary = CampaignNodeRegistry.get_node("node_frontier_safehouse")
	_check(str(node_safe.get("node_type", "")) == "SAFEHOUSE", "A7: node_frontier_safehouse has node_type SAFEHOUSE")

	# Territories materialized
	_check(CampaignTerritory.has_territory("terr_frontier_sector_alpha"), "A8: terr_frontier_sector_alpha registered")
	_check(CampaignTerritory.has_territory("terr_frontier_sector_beta"), "A9: terr_frontier_sector_beta registered")
	var t_alpha: Dictionary = CampaignTerritory.get_territory("terr_frontier_sector_alpha")
	var t_beta: Dictionary = CampaignTerritory.get_territory("terr_frontier_sector_beta")
	_check(str(t_alpha.get("controller", "")) == "federation", "A10: terr_frontier_sector_alpha controlled by federation")
	_check(str(t_beta.get("controller", "")) == "zeon", "A11: terr_frontier_sector_beta controlled by zeon")

	# Bases materialized
	_check(CampaignBase.has_base("base_frontier_garrison"), "A12: base_frontier_garrison registered")
	_check(CampaignBase.has_base("base_frontier_stronghold"), "A13: base_frontier_stronghold registered")
	var b_gar: Dictionary = CampaignBase.get_base("base_frontier_garrison")
	_check(int(b_gar.get("state", -1)) == CampaignBase.BaseState.ACTIVE, "A14: base_frontier_garrison state is ACTIVE")
	_check(str(b_gar.get("controller", "")) == "federation", "A15: base_frontier_garrison controller is federation")

	# Forces materialized
	_check(CampaignForce.has_force("force_s1_fed_vanguard"), "A16: force_s1_fed_vanguard registered")
	_check(CampaignForce.has_force("force_s1_zeon_raiders"), "A17: force_s1_zeon_raiders registered")
	_check(CampaignForce.has_force("force_s1_outland_scavengers"), "A18: force_s1_outland_scavengers registered")
	var f_fed: Dictionary = CampaignForce.get_force("force_s1_fed_vanguard")
	_check(int(f_fed.get("strength", 0)) == 25, "A19: force_s1_fed_vanguard initial strength is 25")
	_check(int(f_fed.get("unit_count", 0)) == 2, "A20: force_s1_fed_vanguard initial unit_count is 2")
	_check(int(f_fed.get("state", -1)) == CampaignForce.ForceState.ACTIVE, "A21: force_s1_fed_vanguard state is ACTIVE")

	# Relationships materialized
	_check(FactionSystem.is_hostile("federation", "zeon"), "A22: federation vs zeon is HOSTILE")
	_check(FactionSystem.is_neutral("federation", "outland"), "A23: federation vs outland is NEUTRAL")
	_check(FactionSystem.is_neutral("zeon", "outland"), "A24: zeon vs outland is NEUTRAL")


# B. Runtime mutation does not mutate ScenarioDefinition
func _test_b_runtime_mutation_does_not_mutate_scenario_definition() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var orig_forces := scenario.get_initial_force_specs()
	var orig_nodes := scenario.get_initial_node_specs()
	var orig_territories := scenario.get_initial_territory_specs()
	var orig_bases := scenario.get_initial_base_specs()
	var orig_rels := scenario.get_initial_relationships()
	var orig_rules := scenario.get_strategic_rules()

	# Perform runtime mutations
	CampaignForce.set_composition("force_s1_fed_vanguard", 1, 10)
	CampaignForce.set_node("force_s1_fed_vanguard", "node_frontier_depot")
	CampaignForce.set_state("force_s1_fed_vanguard", CampaignForce.ForceState.DISABLED)

	CampaignTerritory.set_controlled("terr_frontier_sector_alpha", "zeon")
	CampaignBase.set_state("base_frontier_garrison", CampaignBase.BaseState.DESTROYED)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.ALLIED)
	CampaignTurnExecutive.advance_campaign_turn("test_advance")

	# Verify runtime actually mutated
	var mutated_f := CampaignForce.get_force("force_s1_fed_vanguard")
	_check(int(mutated_f.get("strength", 0)) == 10, "B1: Runtime force strength mutated to 10")
	_check(str(mutated_f.get("node_id", "")) == "node_frontier_depot", "B2: Runtime force node mutated to node_frontier_depot")
	_check(int(mutated_f.get("state", 0)) == CampaignForce.ForceState.DISABLED, "B3: Runtime force state mutated to DISABLED")
	_check(str(CampaignTerritory.get_territory("terr_frontier_sector_alpha").get("controller", "")) == "zeon", "B4: Runtime territory controller mutated to zeon")
	_check(int(CampaignBase.get_base("base_frontier_garrison").get("state", 0)) == CampaignBase.BaseState.DESTROYED, "B5: Runtime base state mutated to DESTROYED")
	_check(FactionSystem.is_allied("federation", "zeon"), "B6: Runtime relationship mutated to ALLIED")
	_check(CampaignTurnExecutive.get_turn() == 1, "B7: Runtime turn advanced to 1")

	# Verify ScenarioDefinition remains completely UNCHANGED
	var check_forces := scenario.get_initial_force_specs()
	_check(check_forces.size() == orig_forces.size(), "B8: Scenario force specs size unmutated")
	_check(int(check_forces[0]["strength"]) == 25, "B9: Scenario force 0 strength unmutated (still 25)")
	_check(str(check_forces[0]["node_id"]) == "node_frontier_city", "B10: Scenario force 0 node_id unmutated")
	_check(not check_forces[0].has("state"), "B11: Scenario force 0 has no runtime state field injected")

	var check_terr := scenario.get_initial_territory_specs()
	_check(str(check_terr[0]["controller"]) == "federation", "B12: Scenario territory 0 controller unmutated (still federation)")

	var check_bases := scenario.get_initial_base_specs()
	_check(int(check_bases[0]["state"]) == 0, "B13: Scenario base 0 state unmutated (still 0)")

	var check_rels := scenario.get_initial_relationships()
	_check(int(check_rels["federation:zeon"]) == 0, "B14: Scenario initial_relationships unmutated (still 0/HOSTILE)")

	var check_rules := scenario.get_strategic_rules()
	_check(int(check_rules["turn_limit"]) == 30, "B15: Scenario strategic turn_limit unmutated (still 30)")


# C. Reset isolation
func _test_c_reset_isolation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Heavy runtime mutation
	CampaignForce.set_composition("force_s1_fed_vanguard", 0, 0)
	CampaignForce.set_state("force_s1_fed_vanguard", CampaignForce.ForceState.DESTROYED)
	CampaignTerritory.set_controlled("terr_frontier_sector_alpha", "zeon")
	CampaignBase.set_state("base_frontier_garrison", CampaignBase.BaseState.DESTROYED)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.ALLIED)
	CampaignTurnExecutive.advance_campaign_turn("test")

	# Mutate economy
	var zeon_eco := FactionEconomySystem.get_economy("zeon")
	zeon_eco["funds"] = 99999

	# Restart scenario
	var restart_receipt := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(restart_receipt.get("ok", false) == true, "C1: Restart scenario succeeds")

	# Verify all mutated runtime state is wiped and restored to authored specs
	var f_restored := CampaignForce.get_force("force_s1_fed_vanguard")
	_check(int(f_restored.get("strength", 0)) == 25, "C2: Force strength cleanly restored to authored 25")
	_check(int(f_restored.get("state", -1)) == CampaignForce.ForceState.ACTIVE, "C3: Force state cleanly restored to ACTIVE")

	var t_restored := CampaignTerritory.get_territory("terr_frontier_sector_alpha")
	_check(str(t_restored.get("controller", "")) == "federation", "C4: Territory controller restored to federation")

	var b_restored := CampaignBase.get_base("base_frontier_garrison")
	_check(int(b_restored.get("state", -1)) == CampaignBase.BaseState.ACTIVE, "C5: Base state restored to ACTIVE")

	_check(FactionSystem.is_hostile("federation", "zeon"), "C6: Faction relationship restored to HOSTILE")
	_check(CampaignTurnExecutive.get_turn() == 0, "C7: Campaign turn reset to 0")

	var zeon_eco_restored := FactionEconomySystem.get_economy("zeon")
	_check(int(zeon_eco_restored.get("funds", 0)) == 2200, "C8: Faction economy reset to default funds (2200, not 99999)")


# D. Scenario identity
func _test_d_scenario_identity() -> void:
	_clear_all_state()
	_check(GlobalData.current_campaign_scenario_id == "", "D1: Initial scenario_id is empty")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "", "D2: RunStartSystem reports empty scenario_id")

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(GlobalData.current_campaign_scenario_id == "frontier_skirmish", "D3: GlobalData.current_campaign_scenario_id set to frontier_skirmish")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "frontier_skirmish", "D4: RunStartSystem reports active scenario_id")

	# Clearing resets scenario identity
	_clear_all_state()
	_check(GlobalData.current_campaign_scenario_id == "", "D5: Cleared scenario_id is empty again")


# E. Board seed separation
func _test_e_board_seed_separation() -> void:
	_clear_all_state()
	GlobalData.board.board_seed = 424242

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(GlobalData.board.board_seed == 424242, "E1: board_seed preserved across scenario start")

	GlobalData.board.board_seed = 848484
	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	_check(not ("board_seed" in scenario), "E2: ScenarioDefinition does not contain board_seed property")
	_check(GlobalData.board.board_seed == 848484, "E3: BoardState maintains sole authoritative ownership of board_seed")


# F. RunTheme separation
func _test_f_run_theme_separation() -> void:
	_clear_all_state()
	GlobalData.narrative.theme_id = "test_custom_theme"

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(GlobalData.narrative.theme_id == "test_custom_theme", "F1: start_campaign_scenario does not overwrite narrative.theme_id")


# G. Turn separation
func _test_g_turn_separation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var authored_limit: int = int(scenario.get_strategic_rules().get("turn_limit", 0))
	_check(authored_limit == 30, "G1: Authored turn limit is 30")
	_check(CampaignTurnExecutive.get_turn() == 0, "G2: Runtime turn starts at 0")

	for i in range(5):
		CampaignTurnExecutive.advance_campaign_turn("test_turn_%d" % i)

	_check(CampaignTurnExecutive.get_turn() == 5, "G3: Runtime turn advanced to 5")
	_check(int(scenario.get_strategic_rules().get("turn_limit", 0)) == 30, "G4: Authored turn limit remains 30, uncoupled from runtime turn")


# H. Relationship separation
func _test_h_relationship_separation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	_check(int(scenario.get_initial_relationships().get("federation:zeon", -1)) == 0, "H1: Authored fed:zeon relationship is 0")

	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.COOPERATIVE)
	_check(FactionSystem.is_cooperative("federation", "zeon"), "H2: Runtime relationship mutated to COOPERATIVE")
	_check(int(scenario.get_initial_relationships().get("federation:zeon", -1)) == 0, "H3: Authored fed:zeon relationship remains 0")


# I. Force runtime independence
func _test_i_force_runtime_independence() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var fid := "force_s1_zeon_raiders"
	_check(CampaignForce.has_force(fid), "I1: Force exists")

	# Runtime mutations
	CampaignForce.set_composition(fid, 1, 9)
	CampaignForce.set_node(fid, "node_frontier_safehouse")
	CampaignForce.set_state(fid, CampaignForce.ForceState.DISABLED)

	var runtime_force := CampaignForce.get_force(fid)
	_check(int(runtime_force["strength"]) == 9, "I2: Runtime force strength is 9")
	_check(str(runtime_force["node_id"]) == "node_frontier_safehouse", "I3: Runtime force node is node_frontier_safehouse")
	_check(int(runtime_force["state"]) == CampaignForce.ForceState.DISABLED, "I4: Runtime force state is DISABLED")

	# Authored scenario specs
	var authored_forces := scenario.get_initial_force_specs()
	var authored_zeon: Dictionary = {}
	for spec in authored_forces:
		if spec.get("slug") == "zeon_raiders":
			authored_zeon = spec
			break
	_check(not authored_zeon.is_empty(), "I5: Authored zeon spec found")
	_check(int(authored_zeon["strength"]) == 30, "I6: Authored strength unmutated at 30")
	_check(str(authored_zeon["node_id"]) == "node_frontier_outpost", "I7: Authored node_id unmutated at node_frontier_outpost")
	_check(int(authored_zeon["unit_count"]) == 3, "I8: Authored unit_count unmutated at 3")


# J. Territory runtime independence
func _test_j_territory_runtime_independence() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var tid := "terr_frontier_sector_alpha"
	_check(CampaignTerritory.has_territory(tid), "J1: Territory exists")

	CampaignTerritory.set_contested(tid, ["federation", "zeon"])
	var runtime_terr := CampaignTerritory.get_territory(tid)
	_check(int(runtime_terr["control"]) == CampaignTerritory.ControlState.CONTESTED, "J2: Runtime territory control is CONTESTED")
	_check(str(runtime_terr["controller"]) == "", "J3: Runtime territory controller is empty when contested")

	var authored_terr := scenario.get_initial_territory_specs()
	_check(str(authored_terr[0]["controller"]) == "federation", "J4: Authored territory controller remains federation")


# K. Base runtime independence
func _test_k_base_runtime_independence() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var bid := "base_frontier_stronghold"
	_check(CampaignBase.has_base(bid), "K1: Base exists")

	CampaignBase.set_state(bid, CampaignBase.BaseState.DISABLED)
	var runtime_base := CampaignBase.get_base(bid)
	_check(int(runtime_base["state"]) == CampaignBase.BaseState.DISABLED, "K2: Runtime base state is DISABLED")

	var authored_bases := scenario.get_initial_base_specs()
	var authored_stronghold: Dictionary = {}
	for spec in authored_bases:
		if spec.get("id") == bid:
			authored_stronghold = spec
			break
	_check(not authored_stronghold.is_empty(), "K3: Authored stronghold found")
	_check(int(authored_stronghold["state"]) == 0, "K4: Authored stronghold state remains ACTIVE (0)")


# L. Player invariant
func _test_l_player_invariant() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var forces := CampaignForce.get_forces()
	_check(forces.size() == 3, "L1: Exactly 3 forces registered")
	for f in forces:
		var fac := str(f.get("faction", "")).to_lower()
		_check(fac != "player", "L2: Force '%s' faction is not player" % f.get("id", ""))
		_check(fac != "", "L3: Force '%s' has non-empty faction" % f.get("id", ""))
		_check(not str(f.get("id", "")).begins_with("player"), "L4: Force id does not begin with player")


# M. Failure isolation
func _test_m_failure_isolation() -> void:
	_clear_all_state()

	# 1. Empty scenario id
	var res1 := RunStartSystem.start_campaign_scenario("")
	_check(res1.get("ok", true) == false, "M1: Empty scenario_id rejected")
	_check(res1.get("started", true) == false, "M2: Empty scenario_id started=false")
	_check(GlobalData.current_campaign_scenario_id == "", "M3: Empty scenario leaves scenario_id empty")
	_check(CampaignForce.get_forces().is_empty(), "M4: Zero forces registered")

	# 2. Unknown scenario id
	var res2 := RunStartSystem.start_campaign_scenario("nonexistent_unknown_scenario_xyz")
	_check(res2.get("ok", true) == false, "M5: Unknown scenario_id rejected")
	_check(res2.get("started", true) == false, "M6: Unknown scenario_id started=false")
	_check(GlobalData.current_campaign_scenario_id == "", "M7: Unknown scenario leaves scenario_id empty")
	_check(CampaignForce.get_forces().is_empty(), "M8: Zero forces registered")

	# 3. Invalid scenario object (validation failure)
	var bad_scenario = ScenarioDefScript.new()
	bad_scenario.scenario_id = "bad_scenario"
	bad_scenario.faction_setup = ["federation"]
	bad_scenario.initial_force_specs = [{
		"slug": "bad_force",
		"force_type": "INVALID_TYPE_XYZ",
		"faction": "federation",
		"node_id": "nonexistent_node",
		"unit_count": -5,
		"strength": -10,
	}]
	var test_catalog = ScenarioCatalogScript.new()
	test_catalog.scenarios = [bad_scenario]

	var res3 := RunStartSystem.start_campaign_scenario("bad_scenario", test_catalog)
	_check(res3.get("ok", true) == false, "M9: Invalid scenario validation rejected")
	_check(res3.get("started", true) == false, "M10: Invalid scenario started=false")
	_check(GlobalData.current_campaign_scenario_id == "", "M11: Invalid scenario leaves scenario_id empty")
	_check(CampaignForce.get_forces().is_empty(), "M12: No forces registered after failed validation")
	_check(CampaignTerritory.get_territories().is_empty(), "M13: No territories registered")
	_check(CampaignBase.get_bases().is_empty(), "M14: No bases registered")
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "M15: No nodes registered")


# N. Startup order & Active boundary
func _test_n_startup_order_and_active_boundary() -> void:
	_clear_all_state()

	# Start scenario successfully
	var res := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res.get("started", false) == true, "N1: Scenario started successfully")
	_check(GlobalData.current_campaign_scenario_id == "frontier_skirmish", "N2: Active scenario identity published")

	# Consumers can verify campaign active boundary
	var is_active: bool = (RunStartSystem.get_current_campaign_scenario_id() != "")
	_check(is_active == true, "N3: Campaign active state is true when scenario successfully initialized")

	# Clear runtime state
	_clear_all_state()
	var is_active_after_clear: bool = (RunStartSystem.get_current_campaign_scenario_id() != "")
	_check(is_active_after_clear == false, "N4: Campaign active state is false when runtime cleared")


func _print_summary() -> void:
	print("==================================================")
	print("CAMPAIGN RUNTIME STATE CONTRACT SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CAMPAIGN_RUNTIME_STATE_CONTRACT_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_RUNTIME_STATE_CONTRACT_TESTS_PASSED")
		get_tree().quit(0)
