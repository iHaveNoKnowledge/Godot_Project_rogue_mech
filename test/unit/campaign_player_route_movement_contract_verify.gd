extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC PLAYER ROUTE MOVEMENT CONTRACT VERIFICATION
## Phase 5AK Contract Verification Suite
##
## Proves the architectural contract:
##   1. Single Player Movement Authority:
##      - CampaignPlayerMovement is the dedicated, stateless authority for player route movement.
##      - Topology remains solely in CampaignNodeRegistry.
##      - Physical position remains solely in BoardState (GlobalData.board).
##   2. Derived Strategic Position:
##      - Player current node is derived via CampaignNodeRegistry.get_node_at(sector, current_tile).
##   3. Validation & Atomicity:
##      - Unknown destination, missing source node, or missing route fail safely with ok=false and zero mutation.
##      - Same-node movement is a deterministic no-op: ok=true, changed=false.
##      - Valid route movement updates GlobalData.board.current_tile/current_sector atomically.
##   4. Non-Implication & Semantic Separation:
##      - Movement does NOT create or mutate CampaignForce (Player != CampaignForce).
##      - Movement does NOT mutate CampaignTerritory, CampaignBase, or CampaignBattle.
##      - Movement does NOT advance CampaignTurnExecutive.
##      - Movement does NOT mutate FactionSystem, FactionEconomySystem, or HeatWantedSystem.
##      - Movement does NOT consume supply or trigger combat/encounters.
##   5. Persistence & Determinism:
##      - Movement survives SaveGameIO.save_run / load_run via standard physical position fields.
##      - Authored ScenarioDefinition remains strictly immutable.
##      - Canonical scenario (frontier_skirmish) multi-faction coexistence verified.
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Strategic Player Route Movement Contract verification (Phase 5AK)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("PLAYER_MOVEMENT_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("PLAYER_MOVEMENT_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_single_movement_authority()
	_test_b_current_node_resolution()
	_test_c_destination_validation()
	_test_d_route_validation()
	_test_e_valid_movement()
	_test_f_physical_position_update()
	_test_g_strategic_projection()
	_test_h_atomic_failure()
	_test_i_same_node_behavior()
	_test_j_player_force_separation()
	_test_k_territory_separation()
	_test_l_base_separation()
	_test_m_combat_separation()
	_test_n_turn_separation()
	_test_o_heat_wanted_separation()
	_test_p_faction_economy_separation()
	_test_q_route_purity()
	_test_r_save_load_persistence()
	_test_s_scenario_definition_immutability()
	_test_t_canonical_scenario_coexistence()


func _reset_campaign_runtime() -> void:
	GlobalData.reset_run_data()
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionEconomySystem.reset()
	GlobalData.current_campaign_scenario_id = ""


func _setup_test_topology() -> void:
	_reset_campaign_runtime()
	# Register Node A (City at 2, 2), Node B (Supply Depot at 2, 3), Node C (Safehouse at 5, 5) in sector 1
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_s1_city_2_2")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "supply_depot", "node_s1_depot_2_3")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "safehouse", "node_s1_safehouse_5_5")

	# Connect A <-> B with a route. C is isolated (no route to A or B).
	CampaignNodeRegistry.register_route("node_s1_city_2_2", "node_s1_depot_2_3")

	# Position player at Node A
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)


## --- SECTION A: SINGLE MOVEMENT AUTHORITY ---
func _test_a_single_movement_authority() -> void:
	_setup_test_topology()

	_check(CampaignPlayerMovement != null, "A1: CampaignPlayerMovement class exists")
	_check(not ("_nodes" in CampaignPlayerMovement), "A2: CampaignPlayerMovement has no duplicate nodes registry")
	_check(not ("_routes" in CampaignPlayerMovement), "A3: CampaignPlayerMovement has no duplicate routes registry")
	_check(not ("current_tile" in CampaignPlayerMovement), "A4: CampaignPlayerMovement has no duplicate current_tile state")
	_check(not ("current_sector" in CampaignPlayerMovement), "A5: CampaignPlayerMovement has no duplicate current_sector state")


## --- SECTION B: CURRENT NODE RESOLUTION ---
func _test_b_current_node_resolution() -> void:
	_setup_test_topology()

	var cur: String = CampaignPlayerMovement.get_current_node_id()
	_check(cur == "node_s1_city_2_2", "B1: get_current_node_id resolves to node_s1_city_2_2 from BoardState")

	# Move physical tile to a non-strategic tile
	GlobalData.board.current_tile = Vector2i(0, 0)
	var non_strat: String = CampaignPlayerMovement.get_current_node_id()
	_check(non_strat == "", "B2: get_current_node_id returns empty string on non-strategic tile")


## --- SECTION C: DESTINATION VALIDATION ---
func _test_c_destination_validation() -> void:
	_setup_test_topology()

	var res_empty: Dictionary = CampaignPlayerMovement.move_player_to_node("")
	_check(not res_empty.get("ok", true), "C1: Empty destination node fails with ok=false")
	_check(str(res_empty.get("reason", "")) == "unknown_destination", "C2: Empty destination reason is unknown_destination")

	var res_unknown: Dictionary = CampaignPlayerMovement.move_player_to_node("node_non_existent")
	_check(not res_unknown.get("ok", true), "C3: Non-existent destination node fails with ok=false")
	_check(str(res_unknown.get("reason", "")) == "unknown_destination", "C4: Non-existent destination reason is unknown_destination")


## --- SECTION D: ROUTE VALIDATION ---
func _test_d_route_validation() -> void:
	_setup_test_topology()

	# A (city) to C (safehouse) has no route
	var res: Dictionary = CampaignPlayerMovement.move_player_to_node("node_s1_safehouse_5_5")
	_check(not res.get("ok", true), "D1: Unconnected node movement fails with ok=false")
	_check(str(res.get("reason", "")) == "no_route", "D2: Unconnected node failure reason is no_route")
	_check(GlobalData.board.current_tile == Vector2i(2, 2), "D3: Player tile unchanged after unrouted move attempt")


## --- SECTION E: VALID MOVEMENT ---
func _test_e_valid_movement() -> void:
	_setup_test_topology()

	# A (city) to B (depot) has a registered route
	var can_res: Dictionary = CampaignPlayerMovement.can_move_to_node("node_s1_depot_2_3")
	_check(bool(can_res.get("ok", false)), "E1: can_move_to_node reports ok=true for connected node")

	var move_res: Dictionary = CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")
	_check(bool(move_res.get("ok", false)), "E2: move_player_to_node reports ok=true for connected node")
	_check(bool(move_res.get("changed", false)), "E3: move_player_to_node reports changed=true")
	_check(str(move_res.get("from_node_id", "")) == "node_s1_city_2_2", "E4: from_node_id matches origin")
	_check(str(move_res.get("to_node_id", "")) == "node_s1_depot_2_3", "E5: to_node_id matches destination")
	_check(str(move_res.get("reason", "")) == "moved", "E6: reason is 'moved'")


## --- SECTION F: PHYSICAL POSITION UPDATE ---
func _test_f_physical_position_update() -> void:
	_setup_test_topology()

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")
	_check(GlobalData.board.current_tile == Vector2i(2, 3), "F1: BoardState.current_tile updated to (2, 3)")
	_check(GlobalData.board.current_sector == 1, "F2: BoardState.current_sector is 1")


## --- SECTION G: STRATEGIC PROJECTION ---
func _test_g_strategic_projection() -> void:
	_setup_test_topology()

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")
	var node_at := CampaignNodeRegistry.get_node_at(GlobalData.board.current_sector, GlobalData.board.current_tile)
	_check(str(node_at.get("id", "")) == "node_s1_depot_2_3", "G1: Strategic node projection resolves to destination node")
	_check(str(node_at.get("node_type", "")) == "SUPPLY_DEPOT", "G2: Destination node_type is SUPPLY_DEPOT")


## --- SECTION H: ATOMIC FAILURE ---
func _test_h_atomic_failure() -> void:
	_setup_test_topology()

	var tile_before: Vector2i = GlobalData.board.current_tile
	var sector_before: int = GlobalData.board.current_sector

	var fail_res: Dictionary = CampaignPlayerMovement.move_player_to_node("node_s1_safehouse_5_5")
	_check(not fail_res.get("ok", true), "H1: Move failed as expected")
	_check(GlobalData.board.current_tile == tile_before, "H2: current_tile untouched on failed move")
	_check(GlobalData.board.current_sector == sector_before, "H3: current_sector untouched on failed move")

	# Also test when player is on non-strategic tile
	GlobalData.board.current_tile = Vector2i(10, 10)
	var fail_nonstrat: Dictionary = CampaignPlayerMovement.move_player_to_node("node_s1_city_2_2")
	_check(not fail_nonstrat.get("ok", true), "H4: Move from non-strategic tile fails")
	_check(str(fail_nonstrat.get("reason", "")) == "no_source_node", "H5: Reason is no_source_node")
	_check(GlobalData.board.current_tile == Vector2i(10, 10), "H6: Position unchanged on no_source_node failure")


## --- SECTION I: SAME-NODE BEHAVIOR ---
func _test_i_same_node_behavior() -> void:
	_setup_test_topology()

	var res: Dictionary = CampaignPlayerMovement.move_player_to_node("node_s1_city_2_2")
	_check(bool(res.get("ok", false)), "I1: Same-node move returns ok=true")
	_check(not bool(res.get("changed", true)), "I2: Same-node move returns changed=false")
	_check(str(res.get("reason", "")) == "same_node", "I3: Same-node move reason is 'same_node'")
	_check(GlobalData.board.current_tile == Vector2i(2, 2), "I4: Player position remains at original node")


## --- SECTION J: PLAYER/FORCE SEPARATION ---
func _test_j_player_force_separation() -> void:
	_setup_test_topology()

	CampaignForce.register_force("force_test_patrol", "PATROL", "federation", "node_s1_city_2_2", "", 2, 20)
	var forces_before := CampaignForce.get_forces()

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")

	var forces_after := CampaignForce.get_forces()
	_check(forces_after.size() == forces_before.size(), "J1: Force count unchanged by player movement")
	_check(not CampaignForce.has_force("player"), "J2: No player force created in CampaignForce registry")

	var patrol := CampaignForce.get_force("force_test_patrol")
	_check(str(patrol.get("node_id", "")) == "node_s1_city_2_2", "J3: Faction force not moved by player movement")
	_check(int(patrol.get("strength", 0)) == 20, "J4: Faction force strength unmutated")


## --- SECTION K: TERRITORY SEPARATION ---
func _test_k_territory_separation() -> void:
	_setup_test_topology()

	CampaignTerritory.register_territory("terr_alpha", ["node_s1_city_2_2", "node_s1_depot_2_3"])
	CampaignTerritory.set_controlled("terr_alpha", "federation")

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")

	_check(CampaignTerritory.get_controller("terr_alpha") == "federation", "K1: Territory controller unmutated by player move")
	_check(not CampaignTerritory.is_contested("terr_alpha"), "K2: Territory remains non-contested after player move")


## --- SECTION L: BASE SEPARATION ---
func _test_l_base_separation() -> void:
	_setup_test_topology()

	CampaignBase.register_base("base_depot_outpost", "node_s1_depot_2_3", "OUTPOST", "zeon", "")
	var base_before := CampaignBase.get_base("base_depot_outpost")

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")

	var base_after := CampaignBase.get_base("base_depot_outpost")
	_check(int(base_after.get("state", -1)) == int(base_before.get("state", -1)), "L1: Base state unmutated by player arrival")
	_check(str(base_after.get("controller", "")) == "zeon", "L2: Base controller unmutated by player arrival")


## --- SECTION M: COMBAT SEPARATION ---
func _test_m_combat_separation() -> void:
	_setup_test_topology()

	# Destination has a hostile force and hostile base
	CampaignForce.register_force("force_hostile", "RAIDER", "zeon", "node_s1_depot_2_3", "", 3, 30)
	CampaignBase.register_base("base_hostile", "node_s1_depot_2_3", "OUTPOST", "zeon", "")
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")

	_check(CampaignBattle.get_battles().is_empty(), "M1: No CampaignBattle created upon entering node with hostile force/base")
	_check(not GlobalData.in_combat, "M2: GlobalData.in_combat remains false")


## --- SECTION N: TURN SEPARATION ---
func _test_n_turn_separation() -> void:
	_setup_test_topology()

	var turn_before := CampaignTurnExecutive.get_turn()
	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")
	var turn_after := CampaignTurnExecutive.get_turn()

	_check(turn_after == turn_before, "N1: CampaignTurnExecutive turn counter NOT incremented by player movement")


## --- SECTION O: HEAT/WANTED SEPARATION ---
func _test_o_heat_wanted_separation() -> void:
	_setup_test_topology()

	GlobalData.board.heat = 2
	GlobalData.board.wanted_level = 3

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")

	_check(GlobalData.board.heat == 2, "O1: Board heat unmutated by player route movement")
	_check(GlobalData.board.wanted_level == 3, "O2: Board wanted level unmutated by player route movement")


## --- SECTION P: FACTION/ECONOMY SEPARATION ---
func _test_p_faction_economy_separation() -> void:
	_setup_test_topology()

	FactionSystem.set_relation("federation", "outland", FactionSystem.Relation.NEUTRAL)
	var fed_rel_before := FactionSystem.get_relation("federation", "outland")

	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")

	var fed_rel_after := FactionSystem.get_relation("federation", "outland")
	_check(fed_rel_after == fed_rel_before, "P1: Faction relations unmutated by player movement")


## --- SECTION Q: ROUTE PURITY ---
func _test_q_route_purity() -> void:
	_setup_test_topology()

	var routes_before := CampaignNodeRegistry.get_routes()
	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")
	var routes_after := CampaignNodeRegistry.get_routes()

	_check(routes_after.size() == routes_before.size(), "Q1: Routes count unmutated by player route movement")
	_check(CampaignNodeRegistry.has_route("route_node_s1_city_2_2__node_s1_depot_2_3"), "Q2: Route remains intact in registry")


## --- SECTION R: SAVE/LOAD PERSISTENCE ---
func _test_r_save_load_persistence() -> void:
	_setup_test_topology()

	# Move player to Node B (depot)
	CampaignPlayerMovement.move_player_to_node("node_s1_depot_2_3")
	_check(GlobalData.board.current_tile == Vector2i(2, 3), "R1: Player at depot before save")

	# Save run
	var saved := SaveGameIO.save_run()
	_check(saved, "R2: SaveGameIO.save_run succeeded")

	# Inspect save payload to ensure no redundant strategic position keys were introduced
	var raw := FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	var parsed = JSON.parse_string(raw)
	_check(parsed is Dictionary, "R3: Save file parsed as Dictionary")
	var save_dict: Dictionary = parsed if parsed is Dictionary else {}
	var board_saved: Dictionary = save_dict.get("board", {})
	_check(not board_saved.has("current_campaign_node_id"), "R4: Save payload does not store redundant current_campaign_node_id")

	# Clear runtime and simulate loading
	GlobalData.board.current_tile = Vector2i(0, 0)
	var loaded := SaveGameIO.load_run()
	_check(loaded, "R5: SaveGameIO.load_run succeeded")
	_check(GlobalData.board.current_tile == Vector2i(2, 3), "R6: Player tile restored to (2, 3)")

	# Re-query node projection
	var cur_node: String = CampaignPlayerMovement.get_current_node_id()
	_check(cur_node == "node_s1_depot_2_3", "R7: Derived node projection resolves to depot after load")


## --- SECTION S: SCENARIODEFINITION IMMUTABILITY ---
func _test_s_scenario_definition_immutability() -> void:
	_reset_campaign_runtime()

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	_check(scenario != null, "S1: Canonical scenario loaded")
	var init_res := InitializerScript.apply_scenario(scenario)
	_check(bool(init_res.get("ok", false)), "S2: Canonical scenario initialized")

	# Connect city and safehouse with a route for test
	CampaignNodeRegistry.register_route("node_frontier_safehouse", "node_frontier_city")

	# Set player at safehouse
	GlobalData.board.current_sector = 1
	var safehouse_node := CampaignNodeRegistry.get_node("node_frontier_safehouse")
	GlobalData.board.current_tile = safehouse_node.get("tile", Vector2i.ZERO)

	# Execute move to city
	var move_res: Dictionary = CampaignPlayerMovement.move_player_to_node("node_frontier_city")
	_check(bool(move_res.get("ok", false)), "S3: Move player to canonical city succeeded")

	# Verify authored scenario specs are strictly unchanged
	_check(scenario.scenario_id == "frontier_skirmish", "S4: Authored scenario_id unmutated")
	_check(scenario.initial_force_specs.size() == 3, "S5: Authored force specs count unmutated")
	_check(scenario.initial_node_specs.size() == 4, "S6: Authored node specs count unmutated")
	_check(scenario.initial_territory_specs.size() == 2, "S7: Authored territory specs count unmutated")
	_check(scenario.initial_base_specs.size() == 2, "S8: Authored base specs count unmutated")


## --- SECTION T: CANONICAL SCENARIO COEXISTENCE ---
func _test_t_canonical_scenario_coexistence() -> void:
	_reset_campaign_runtime()

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	InitializerScript.apply_scenario(scenario)

	# Register route between node_frontier_city and node_frontier_depot
	CampaignNodeRegistry.register_route("node_frontier_city", "node_frontier_depot")

	# Position player at city in Sector Alpha (controlled by federation)
	var city_node := CampaignNodeRegistry.get_node("node_frontier_city")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = city_node.get("tile", Vector2i.ZERO)

	# Move player to node_frontier_depot in Sector Beta (controlled by Zeon, hosting Outland scavengers)
	var move_res: Dictionary = CampaignPlayerMovement.move_player_to_node("node_frontier_depot")
	_check(bool(move_res.get("ok", false)), "T1: Player successfully moved to frontier depot")

	# Verify Sector Beta territory control remains Zeon (no territory flip)
	_check(CampaignTerritory.get_controller("terr_frontier_sector_beta") == "zeon",
		"T2: Sector Beta controller remains Zeon after player arrival")

	# Verify Outland scavengers force remains at depot and unmutated
	var scav := CampaignForce.get_force("force_s1_outland_scavengers")
	_check(str(scav.get("node_id", "")) == "node_frontier_depot", "T3: Outland force node remains depot")
	_check(str(scav.get("faction", "")) == "outland", "T4: Outland force faction remains outland")
	_check(int(scav.get("unit_count", 0)) == 1, "T5: Outland force unit_count unmutated")
	_check(int(scav.get("strength", 0)) == 10, "T6: Outland force strength unmutated")

	# Verify zero battles created
	_check(CampaignBattle.get_battles().is_empty(), "T7: No battle created at depot")

	# Verify turn limit and turn counter
	_check(CampaignTurnExecutive.get_turn() == 0, "T8: Campaign turn remains 0")


func _restore_save_backup() -> void:
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
	print("==================================================")
	print("CAMPAIGN PLAYER ROUTE MOVEMENT CONTRACT SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")
	if _checks_failed > 0:
		printerr("CAMPAIGN_PLAYER_ROUTE_MOVEMENT_CONTRACT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_PLAYER_ROUTE_MOVEMENT_CONTRACT_TESTS_PASSED")
		get_tree().quit(0)
