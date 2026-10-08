extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN NODE INTERACTION & ENCOUNTER BOUNDARY CONTRACT VERIFICATION
## Phase 5AJ Contract Verification Suite
##
## Proves the architectural contract:
##   1. Node Query Purity:
##      - CampaignNodeRegistry query APIs are pure observation operations.
##      - Zero side effects on forces, territories, bases, battles, turns, heat, or relations.
##   2. Player / Node Projection:
##      - Player position (BoardState.current_tile) resolves to strategic node only when
##        physically located at a cell hosting a strategic facility.
##      - Non-strategic tiles (empty, hazard, event, plain) safely resolve to {} without error.
##   3. Node Type Semantics:
##      - Node type is descriptive metadata (CITY, SAFEHOUSE, ENEMY_BASE, etc.).
##      - Node type does NOT imply base existence, active combat, or supply transfers.
##   4. Non-Implications of Node Entry / Presence:
##      - Player presence != territory capture / contest
##      - Player presence != force creation / movement / mutation
##      - Player presence != base creation / destruction
##      - Player presence != combat / battle launch
##      - Player presence != turn advance
##      - Player presence != heat / wanted escalation
##      - Player presence != faction relation mutation
##      - Player presence != supply consumption / transfer
##      - Player presence != event / encounter resolution
##   5. Canonical Multi-Entity Coexistence:
##      - frontier_skirmish facts (Depot in Zeon territory, Outland force at Depot,
##        player at Depot) coexist without automatic state changes.
##   6. Structural Guards:
##      - ScenarioDefinition remains immutable.
##      - No duplicate interaction manager or second topology authority.
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")
const InspectionPanelScript = preload("res://scripts/ui/campaign_node_inspection_panel.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	await get_tree().process_frame
	print("Running Campaign Node Interaction & Encounter Boundary Contract verification (Phase 5AJ)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await _run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("NODE_INTERACTION_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("NODE_INTERACTION_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_node_query_purity()
	_test_b_player_node_projection()
	_test_c_empty_projection_on_non_strategic_tiles()
	_test_d_node_type_semantics_vs_runtime_state()
	_test_e_player_entry_non_implications()
	_test_f_territory_separation()
	_test_g_base_separation()
	_test_h_force_separation()
	_test_i_player_separation_from_campaign_force()
	_test_j_route_separation_topology_only()
	_test_k_turn_separation_no_implicit_advance()
	_test_l_scenario_definition_immutability()
	_test_m_canonical_scenario_frontier_skirmish_semantics()
	await _test_n_inspection_panel_read_only_purity()
	_test_o_no_duplicate_interaction_authority()


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


func _snap_campaign_state() -> Dictionary:
	return {
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"territories": JSON.stringify(CampaignTerritory.serialize()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"turn": CampaignTurnExecutive.get_turn(),
		"heat": GlobalData.board.heat,
		"wanted": GlobalData.board.wanted_level,
		"relations": JSON.stringify(FactionSystem.serialize_relations()),
		"player_tile": str(GlobalData.board.current_tile),
	}


## --- SECTION A: NODE QUERY PURITY ---
func _test_a_node_query_purity() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_1")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse", "node_safe_1")
	CampaignNodeRegistry.register_route("node_city_1", "node_safe_1")
	CampaignTerritory.register_territory("terr_1", ["node_city_1", "node_safe_1"])
	CampaignTerritory.set_controlled("terr_1", "federation")
	CampaignBase.register_base("base_1", "node_city_1", "OUTPOST", "federation", "terr_1")
	CampaignForce.register_force("force_1", "PATROL", "federation", "node_city_1", "base_1", 2, 20)

	var snap_before := _snap_campaign_state()

	# Execute all query APIs multiple times
	var _n1 := CampaignNodeRegistry.get_node("node_city_1")
	var _n2 := CampaignNodeRegistry.get_node_at(1, Vector2i(2, 2))
	var _has1 := CampaignNodeRegistry.has_node("node_city_1")
	var _all_nodes := CampaignNodeRegistry.get_nodes()
	var _has_r := CampaignNodeRegistry.has_route("route_node_city_1__node_safe_1")
	var _r := CampaignNodeRegistry.get_route("route_node_city_1__node_safe_1")
	var _all_routes := CampaignNodeRegistry.get_routes()
	var _rf := CampaignNodeRegistry.get_routes_for("node_city_1")

	var snap_after := _snap_campaign_state()
	_check(snap_after == snap_before, "A1: CampaignNodeRegistry query operations produce zero side effects")
	_check(snap_after["forces"] == snap_before["forces"], "A2: Force registry untouched by node queries")
	_check(snap_after["territories"] == snap_before["territories"], "A3: Territory registry untouched by node queries")
	_check(snap_after["bases"] == snap_before["bases"], "A4: Base registry untouched by node queries")
	_check(snap_after["turn"] == snap_before["turn"], "A5: CampaignTurnExecutive untouched by node queries")


## --- SECTION B: PLAYER / NODE PROJECTION ---
func _test_b_player_node_projection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 5), "fuel_depot", "node_depot_4_5")

	# Position player on strategic tile (4, 5)
	GlobalData.board.current_tile = Vector2i(4, 5)
	GlobalData.board.current_sector = 1

	var node := CampaignNodeRegistry.get_node_at(GlobalData.board.current_sector, GlobalData.board.current_tile)
	_check(not node.is_empty(), "B1: Strategic tile resolves to non-empty node dict")
	_check(str(node.get("id", "")) == "node_depot_4_5", "B2: Resolved node ID matches 'node_depot_4_5'")
	_check(str(node.get("node_type", "")) == "FUEL_DEPOT", "B3: Resolved node_type matches 'FUEL_DEPOT'")
	_check(Vector2i(node.get("tile", Vector2i.ZERO)) == Vector2i(4, 5), "B4: Resolved tile matches (4, 5)")


## --- SECTION C: EMPTY PROJECTION ON NON-STRATEGIC TILES ---
func _test_c_empty_projection_on_non_strategic_tiles() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 5), "fuel_depot", "node_depot_4_5")

	# Position player on a non-strategic / plain wilderness tile
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.current_sector = 1

	var snap_before := _snap_campaign_state()
	var node := CampaignNodeRegistry.get_node_at(GlobalData.board.current_sector, GlobalData.board.current_tile)
	var snap_after := _snap_campaign_state()

	_check(node.is_empty(), "C1: Non-strategic tile returns empty node dictionary")
	_check(snap_after == snap_before, "C2: Non-strategic tile query causes zero side effects or fallbacks")


## --- SECTION D: NODE TYPE SEMANTICS VS RUNTIME STATE ---
func _test_d_node_type_semantics_vs_runtime_state() -> void:
	_reset_campaign_runtime()

	# Register an enemy base node type and a supply depot node type
	CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "enemy_base", "node_eb_6_6")
	CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "supply_depot", "node_sup_8_8")

	var eb_node := CampaignNodeRegistry.get_node("node_eb_6_6")
	_check(str(eb_node.get("node_type", "")) == "ENEMY_BASE", "D1: Node type is ENEMY_BASE")
	_check(not eb_node.has("state"), "D2: Node does not have runtime base state")
	_check(not eb_node.has("controller"), "D3: Node does not have territory controller")
	_check(CampaignBase.get_bases().is_empty(), "D4: ENEMY_BASE node type does NOT create CampaignBase entity")
	_check(CampaignBattle.get_battles().is_empty(), "D5: ENEMY_BASE node type does NOT create CampaignBattle")

	var sup_node := CampaignNodeRegistry.get_node("node_sup_8_8")
	_check(str(sup_node.get("node_type", "")) == "SUPPLY_DEPOT", "D6: Node type is SUPPLY_DEPOT")
	_check(not sup_node.has("supply_amount"), "D7: SUPPLY_DEPOT node does not store supply amounts")


## --- SECTION E: PLAYER ENTRY NON-IMPLICATIONS ---
func _test_e_player_entry_non_implications() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_2_2")
	CampaignTerritory.register_territory("terr_city", ["node_city_2_2"])
	CampaignTerritory.set_controlled("terr_city", "zeon")
	CampaignBase.register_base("base_zeon_city", "node_city_2_2", "OUTPOST", "zeon", "terr_city")
	CampaignForce.register_force("force_zeon_garrison", "PATROL", "zeon", "node_city_2_2", "base_zeon_city", 3, 30)

	var snap_before := _snap_campaign_state()

	# Simulate player moving / entering the strategic node cell
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.board.current_sector = 1

	# Query node projection at new position
	var proj := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	_check(str(proj.get("id", "")) == "node_city_2_2", "E1: Player projection resolves to node_city_2_2")

	# Verify non-implications:
	# 1. Territory control unchanged
	var terr := CampaignTerritory.get_territory("terr_city")
	_check(str(terr.get("controller", "")) == "zeon", "E2: Territory controller remains zeon (no auto capture)")
	_check(int(terr.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED, "E3: Territory remains CONTROLLED")

	# 2. Base state unchanged
	var base := CampaignBase.get_base("base_zeon_city")
	_check(int(base.get("state", -1)) == CampaignBase.BaseState.ACTIVE, "E4: Base remains ACTIVE (no auto destroy)")
	_check(str(base.get("controller", "")) == "zeon", "E5: Base controller remains zeon")

	# 3. Force state unchanged
	var force := CampaignForce.get_force("force_zeon_garrison")
	_check(int(force.get("unit_count", 0)) == 3, "E6: Force unit_count unchanged (no auto casualty)")
	_check(int(force.get("strength", 0)) == 30, "E7: Force strength unchanged (no auto attrition)")
	_check(int(force.get("state", -1)) == CampaignForce.ForceState.ACTIVE, "E8: Force state remains ACTIVE")

	# 4. Zero battles created
	_check(CampaignBattle.get_battles().is_empty(), "E9: Zero battles created (no automatic combat launch)")

	# 5. Turn counter unchanged
	_check(CampaignTurnExecutive.get_turn() == 0, "E10: CampaignTurnExecutive turn remains 0 (no auto turn advance)")

	# 6. Heat and wanted unchanged
	_check(GlobalData.board.heat == 0 and GlobalData.board.wanted_level == 1, "E11: Heat/wanted levels unchanged")

	# 7. Faction relations unchanged
	_check(JSON.stringify(FactionSystem.serialize_relations()) == snap_before["relations"], "E12: Faction relations unchanged")


## --- SECTION F: TERRITORY SEPARATION ---
func _test_f_territory_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_s1_safe_1_1")
	CampaignTerritory.register_territory("terr_alpha", ["node_s1_safe_1_1"])
	CampaignTerritory.set_controlled("terr_alpha", "federation")

	var members := CampaignTerritory.get_members("terr_alpha")
	_check(members.has("node_s1_safe_1_1"), "F1: Node is a geographic member of territory")

	var node := CampaignNodeRegistry.get_node("node_s1_safe_1_1")
	_check(not node.has("controller"), "F2: Node topology record does not store territory controller")
	_check(not node.has("territory"), "F3: Node topology record does not store territory ID")


## --- SECTION G: BASE SEPARATION ---
func _test_g_base_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "enemy_base", "node_eb_3_3")
	_check(CampaignNodeRegistry.has_node("node_eb_3_3"), "G1: Node exists in registry")
	_check(CampaignBase.get_bases().is_empty(), "G2: Node existence does not create a CampaignBase entity")
	_check(CampaignBase.get_base_at_node("node_eb_3_3").is_empty(), "G3: get_base_at_node returns empty dict")


## --- SECTION H: FORCE SEPARATION ---
func _test_h_force_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "city", "node_city_5_5")
	_check(CampaignForce.get_forces().is_empty(), "H1: Node creation produces zero CampaignForce records")
	_check(CampaignForce.get_forces_at_node("node_city_5_5").is_empty(), "H2: No forces at node")


## --- SECTION I: PLAYER SEPARATION FROM CAMPAIGN FORCE ---
func _test_i_player_separation_from_campaign_force() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_2_2")
	GlobalData.board.current_tile = Vector2i(2, 2)

	_check(not CampaignForce.has_force("player"), "I1: Player is not in CampaignForce registry")
	_check(not CampaignForce.has_force("force_player"), "I2: No force_player exists")
	_check(CampaignForce.get_forces().is_empty(), "I3: CampaignForce registry remains empty")


## --- SECTION J: ROUTE SEPARATION (TOPOLOGY ONLY) ---
func _test_j_route_separation_topology_only() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_a")
	CampaignNodeRegistry.register_node(1, Vector2i(1, 2), "city", "node_b")
	var rid := CampaignNodeRegistry.register_route("node_a", "node_b")

	var r := CampaignNodeRegistry.get_route(rid)
	_check(not r.is_empty(), "J1: Route registered")
	_check(r.keys().size() == 3, "J2: Route schema strictly contains only (id, a, b)")
	_check(not r.has("cost") and not r.has("mp_cost"), "J3: Route has no movement cost")
	_check(not r.has("patrol_intercept"), "J4: Route has no patrol intercept logic")


## --- SECTION K: TURN SEPARATION (NO IMPLICIT ADVANCE) ---
func _test_k_turn_separation_no_implicit_advance() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_2_2")
	_check(CampaignTurnExecutive.get_turn() == 0, "K1: Initial turn is 0")

	# Multiple tile moves and node queries
	GlobalData.board.current_tile = Vector2i(2, 2)
	var _n := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	GlobalData.board.current_tile = Vector2i(3, 3)
	var _n2 := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)

	_check(CampaignTurnExecutive.get_turn() == 0, "K2: Turn remains exactly 0 after player moves and node queries")


## --- SECTION L: SCENARIODEFINITION IMMUTABILITY ---
func _test_l_scenario_definition_immutability() -> void:
	_reset_campaign_runtime()

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	_check(scenario != null, "L1: Canonical scenario loaded")

	var nodes_before := scenario.get_initial_node_specs()
	var forces_before := scenario.get_initial_force_specs()
	var terr_before := scenario.get_initial_territory_specs()
	var bases_before := scenario.get_initial_base_specs()

	# Start scenario, query nodes, move player
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.board.current_tile = Vector2i(5, 3) # at depot
	var _node := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)

	_check(scenario.get_initial_node_specs() == nodes_before, "L2: initial_node_specs unmutated")
	_check(scenario.get_initial_force_specs() == forces_before, "L3: initial_force_specs unmutated")
	_check(scenario.get_initial_territory_specs() == terr_before, "L4: initial_territory_specs unmutated")
	_check(scenario.get_initial_base_specs() == bases_before, "L5: initial_base_specs unmutated")


## --- SECTION M: CANONICAL SCENARIO FRONTIER SKIRMISH SEMANTICS ---
func _test_m_canonical_scenario_frontier_skirmish_semantics() -> void:
	_reset_campaign_runtime()

	var res := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(bool(res.get("ok", false)), "M1: Scenario started successfully")

	# Fact 1: Sector Beta is controlled by Zeon
	var beta := CampaignTerritory.get_territory("terr_frontier_sector_beta")
	_check(str(beta.get("controller", "")) == "zeon", "M2: Sector Beta controlled by zeon")

	# Fact 2: Depot is a member node of Sector Beta
	var beta_members := CampaignTerritory.get_members("terr_frontier_sector_beta")
	_check(beta_members.has("node_frontier_depot"), "M3: node_frontier_depot is inside Sector Beta")

	# Fact 3: Outland scavengers force is present at node_frontier_depot
	var outland_f := CampaignForce.get_force("force_s1_outland_scavengers")
	_check(str(outland_f.get("node_id", "")) == "node_frontier_depot", "M4: Outland force is at node_frontier_depot")

	# Fact 4: Player moves onto node_frontier_depot (tile (5, 3))
	GlobalData.board.current_tile = Vector2i(5, 3)
	var player_node := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	_check(str(player_node.get("id", "")) == "node_frontier_depot", "M5: Player projected at node_frontier_depot")

	# Fact 5: Coexistence without side-effects
	var beta_after := CampaignTerritory.get_territory("terr_frontier_sector_beta")
	_check(str(beta_after.get("controller", "")) == "zeon", "M6: Sector Beta controller remains zeon")
	_check(int(beta_after.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED,
		"M7: Sector Beta is not contested by Outland or Player presence")
	_check(CampaignBattle.get_battles().is_empty(), "M8: No battle started between Outland and Player at Depot")


## --- SECTION N: INSPECTION PANEL READ-ONLY PURITY ---
func _test_n_inspection_panel_read_only_purity() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var panel: Control = InspectionPanelScript.new()
	add_child(panel)
	await get_tree().process_frame

	var snap_before := _snap_campaign_state()

	# Inspect all scenario nodes via panel
	for nid in ["node_frontier_safehouse", "node_frontier_city", "node_frontier_depot", "node_frontier_outpost"]:
		var res: Dictionary = panel.inspect_node(nid)
		_check(bool(res.get("ok", false)), "N1: Inspected node %s" % nid)
		_check(str(panel.get_selected_node_id()) == nid, "N2: Panel selection matches %s" % nid)

	var snap_after := _snap_campaign_state()
	_check(snap_after == snap_before, "N3: Panel inspection operations produce zero side effects")

	panel.queue_free()


## --- SECTION O: NO DUPLICATE INTERACTION AUTHORITY ---
func _test_o_no_duplicate_interaction_authority() -> void:
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_node_interaction.gd"),
		"O1: No unapproved campaign_node_interaction.gd file exists")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_interaction_manager.gd"),
		"O2: No unapproved campaign_interaction_manager.gd file exists")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_encounter_manager.gd"),
		"O3: No unapproved campaign_encounter_manager.gd file exists")


func _restore_save_backup() -> void:
	_reset_campaign_runtime()
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.flush()
			f.close()


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE 5AJ SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN NODE INTERACTION & ENCOUNTER BOUNDARY CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN NODE INTERACTION & ENCOUNTER BOUNDARY CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
