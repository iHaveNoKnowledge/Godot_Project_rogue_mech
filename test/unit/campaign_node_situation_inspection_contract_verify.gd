extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN NODE SITUATION / STRATEGIC INSPECTION CONTRACT VERIFICATION
## Phase 5AL Contract Verification Suite
##
## Proves the architectural contract:
##   1. Read-Only Inspection Authority:
##      - CampaignNodeInspection provides pure observation projections.
##      - Zero state mutation across all campaign systems.
##   2. Projection Model:
##      - Node identity & topology from CampaignNodeRegistry
##      - Territory membership & state from CampaignTerritory
##      - Base state from CampaignBase
##      - Force presence from CampaignForce (sorted deterministically)
##      - Player presence derived from BoardState.current_tile & sector
##   3. Non-Implication & Isolation:
##      - Inspection does not capture territory, destroy bases, or damage forces
##      - Inspection does not advance turn, change heat, or alter relations
##      - Inspection does not create battles or trigger combat
##   4. Canonical Coexistence:
##      - frontier_skirmish depot facts (Zeon territory, Outland scavenger force,
##        player presence) coexist without implicit state mutation.
##   5. Save/Load & Determinism:
##      - Save/load restores exact projection without saving redundant inspection state.
## ---------------------------------------------------------------------------

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Node Situation / Strategic Inspection Contract verification (Phase 5AL)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("NODE_INSPECTION_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("NODE_INSPECTION_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_valid_node_inspection()
	_test_b_unknown_node_inspection()
	_test_c_node_metadata_authority()
	_test_d_territory_projection()
	_test_e_base_projection()
	_test_f_force_projection()
	_test_g_multiple_forces_projection()
	_test_h_player_presence_derived()
	_test_i_player_absence_on_other_nodes()
	_test_j_canonical_depot_coexistence()
	_test_k_no_territory_mutation()
	_test_l_no_base_mutation()
	_test_m_no_force_mutation()
	_test_n_no_player_movement()
	_test_o_no_turn_mutation()
	_test_p_no_heat_wanted_mutation()
	_test_q_no_faction_mutation()
	_test_r_no_battle_creation()
	_test_s_repeated_inspection_idempotence()
	_test_t_determinism()
	_test_u_save_load_consistency()
	_test_v_no_duplicate_authority()


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
		"player_sector": GlobalData.board.current_sector,
	}


## --- SECTION A: VALID NODE INSPECTION ---
func _test_a_valid_node_inspection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_a")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse", "node_safe_a")
	CampaignNodeRegistry.register_route("node_city_a", "node_safe_a")

	var result := CampaignNodeInspection.inspect_node("node_city_a")
	_check(bool(result.get("ok", false)), "A1: Valid node inspects with ok=true")
	_check(str(result.get("reason", "")) == "inspected", "A2: Reason is 'inspected'")
	_check(not (result.get("node", {}) as Dictionary).is_empty(), "A3: Node dictionary populated")
	_check((result.get("routes", []) as Array) == ["node_safe_a"], "A4: Routes contains neighbor node_safe_a")


## --- SECTION B: UNKNOWN NODE INSPECTION ---
func _test_b_unknown_node_inspection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_a")

	var snap_before := _snap_campaign_state()
	var result := CampaignNodeInspection.inspect_node("non_existent_node")
	var snap_after := _snap_campaign_state()

	_check(not bool(result.get("ok", true)), "B1: Unknown node returns ok=false")
	_check(str(result.get("reason", "")) == "unknown_node", "B2: Unknown node reason is 'unknown_node'")
	_check((result.get("node", {}) as Dictionary).is_empty(), "B3: Node dictionary is empty on failure")
	_check(snap_after == snap_before, "B4: Unknown node inspection leaves runtime state untouched")


## --- SECTION C: NODE METADATA AUTHORITY ---
func _test_c_node_metadata_authority() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(5, 7), "fuel_depot", "node_fuel_c")
	var result := CampaignNodeInspection.inspect_node("node_fuel_c")
	var node: Dictionary = result.get("node", {})

	_check(str(node.get("id", "")) == "node_fuel_c", "C1: Node ID matches registry")
	_check(str(node.get("node_type", "")) == "FUEL_DEPOT", "C2: Node type matches registry")
	_check(Vector2i(node.get("tile", Vector2i.ZERO)) == Vector2i(5, 7), "C3: Node tile matches registry")
	_check(int(node.get("sector", -1)) == 1, "C4: Node sector matches registry")


## --- SECTION D: TERRITORY PROJECTION ---
func _test_d_territory_projection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_d")
	CampaignTerritory.register_territory("terr_d", ["node_city_d"])
	CampaignTerritory.set_controlled("terr_d", "federation")

	var result := CampaignNodeInspection.inspect_node("node_city_d")
	var terr: Dictionary = result.get("territory", {})

	_check(not terr.is_empty(), "D1: Territory dictionary populated")
	_check(str(terr.get("id", "")) == "terr_d", "D2: Territory ID is terr_d")
	_check(str(terr.get("controller", "")) == "federation", "D3: Territory controller is federation")
	_check(int(terr.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED, "D4: Territory state is CONTROLLED")


## --- SECTION E: BASE PROJECTION ---
func _test_e_base_projection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_e")
	CampaignTerritory.register_territory("terr_e", ["node_city_e"])
	CampaignBase.register_base("base_alpha", "node_city_e", "OUTPOST", "zeon", "terr_e")

	var result := CampaignNodeInspection.inspect_node("node_city_e")
	var base: Dictionary = result.get("base", {})

	_check(not base.is_empty(), "E1: Base dictionary populated")
	_check(str(base.get("id", "")) == "base_alpha", "E2: Base ID is base_alpha")
	_check(str(base.get("base_type", "")) == "OUTPOST", "E3: Base type is OUTPOST")
	_check(str(base.get("controller", "")) == "zeon", "E4: Base controller is zeon")
	_check(int(base.get("state", -1)) == CampaignBase.BaseState.ACTIVE, "E5: Base state is ACTIVE")


## --- SECTION F: FORCE PROJECTION ---
func _test_f_force_projection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_f")
	CampaignForce.register_force("force_f1", "PATROL", "federation", "node_city_f", "", 3, 30)

	var result := CampaignNodeInspection.inspect_node("node_city_f")
	var forces: Array = result.get("forces", [])

	_check(forces.size() == 1, "F1: Exactly 1 force projected")
	var f: Dictionary = forces[0]
	_check(str(f.get("id", "")) == "force_f1", "F2: Force ID is force_f1")
	_check(str(f.get("faction", "")) == "federation", "F3: Force faction is federation")
	_check(int(f.get("unit_count", 0)) == 3, "F4: Force unit count is 3")
	_check(int(f.get("strength", 0)) == 30, "F5: Force strength is 30")


## --- SECTION G: MULTIPLE FORCES PROJECTION ---
func _test_g_multiple_forces_projection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_g")
	CampaignForce.register_force("force_z", "CONVOY", "zeon", "node_city_g", "", 1, 10)
	CampaignForce.register_force("force_a", "PATROL", "federation", "node_city_g", "", 2, 20)

	var result := CampaignNodeInspection.inspect_node("node_city_g")
	var forces: Array = result.get("forces", [])

	_check(forces.size() == 2, "G1: Both forces projected")
	# Check deterministic sorting by ID
	_check(str(forces[0].get("id", "")) == "force_a" and str(forces[1].get("id", "")) == "force_z",
		"G2: Forces sorted deterministically by ID (force_a, force_z)")
	var factions: Array = result.get("factions_present", [])
	_check(factions == ["federation", "zeon"], "G3: Factions present lists federation and zeon sorted")


## --- SECTION H: PLAYER PRESENCE DERIVED ---
func _test_h_player_presence_derived() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse", "node_safe_h")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)

	var result := CampaignNodeInspection.inspect_node("node_safe_h")
	_check(bool(result.get("player_present", false)), "H1: player_present is true when player tile matches node tile")
	_check(CampaignNodeInspection.is_player_at_node("node_safe_h"), "H2: is_player_at_node returns true")
	_check(CampaignNodeInspection.get_current_player_node_id() == "node_safe_h", "H3: get_current_player_node_id returns node_safe_h")


## --- SECTION I: PLAYER ABSENCE ON OTHER NODES ---
func _test_i_player_absence_on_other_nodes() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse", "node_safe_h")
	CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "city", "node_city_i")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)

	var result := CampaignNodeInspection.inspect_node("node_city_i")
	_check(not bool(result.get("player_present", true)), "I1: player_present is false for other nodes")
	_check(not CampaignNodeInspection.is_player_at_node("node_city_i"), "I2: is_player_at_node returns false for node_city_i")


## --- SECTION J: CANONICAL DEPOT COEXISTENCE ---
func _test_j_canonical_depot_coexistence() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.board.current_tile = Vector2i(5, 3) # at depot

	var result := CampaignNodeInspection.inspect_node("node_frontier_depot")
	_check(bool(result.get("ok", false)), "J1: Canonical depot inspects successfully")

	# Territory check
	var terr: Dictionary = result.get("territory", {})
	_check(str(terr.get("id", "")) == "terr_frontier_sector_beta", "J2: Depot territory is terr_frontier_sector_beta")
	_check(str(terr.get("controller", "")) == "zeon", "J3: Territory controller is zeon")

	# Force check
	var forces: Array = result.get("forces", [])
	_check(forces.size() == 1, "J4: Outland scavenger force present at depot")
	_check(str(forces[0].get("faction", "")) == "outland", "J5: Force faction is outland")
	_check(str(forces[0].get("force_type", "")) == "SCAVENGER", "J6: Force type is SCAVENGER")

	# Player check
	_check(bool(result.get("player_present", false)), "J7: Player is present at depot")

	# Coexistence check
	_check(CampaignBattle.get_battles().is_empty(), "J8: Coexistence causes zero battle launches")
	_check(int(terr.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED, "J9: Territory remains CONTROLLED by Zeon")


## --- SECTION K: NO TERRITORY MUTATION ---
func _test_k_no_territory_mutation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var terr_before := CampaignTerritory.serialize()

	for nid in ["node_frontier_safehouse", "node_frontier_city", "node_frontier_depot", "node_frontier_outpost"]:
		var _res := CampaignNodeInspection.inspect_node(nid)

	var terr_after := CampaignTerritory.serialize()
	_check(terr_after == terr_before, "K1: Territory state completely unmutated by inspections")


## --- SECTION L: NO BASE MUTATION ---
func _test_l_no_base_mutation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var bases_before := CampaignBase.get_bases()

	for nid in ["node_frontier_safehouse", "node_frontier_city", "node_frontier_depot", "node_frontier_outpost"]:
		var _res := CampaignNodeInspection.inspect_node(nid)

	var bases_after := CampaignBase.get_bases()
	_check(bases_after == bases_before, "L1: Base state completely unmutated by inspections")


## --- SECTION M: NO FORCE MUTATION ---
func _test_m_no_force_mutation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var forces_before := CampaignForce.get_forces()

	for nid in ["node_frontier_safehouse", "node_frontier_city", "node_frontier_depot", "node_frontier_outpost"]:
		var _res := CampaignNodeInspection.inspect_node(nid)

	var forces_after := CampaignForce.get_forces()
	_check(forces_after == forces_before, "M1: Force state completely unmutated by inspections")


## --- SECTION N: NO PLAYER MOVEMENT ---
func _test_n_no_player_movement() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var pos_before: Vector2i = GlobalData.board.current_tile
	var sec_before: int = GlobalData.board.current_sector

	for nid in ["node_frontier_safehouse", "node_frontier_city", "node_frontier_depot", "node_frontier_outpost"]:
		var _res := CampaignNodeInspection.inspect_node(nid)

	_check(GlobalData.board.current_tile == pos_before, "N1: Player current_tile untouched by inspections")
	_check(GlobalData.board.current_sector == sec_before, "N2: Player current_sector untouched by inspections")


## --- SECTION O: NO TURN MUTATION ---
func _test_o_no_turn_mutation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var turn_before := CampaignTurnExecutive.get_turn()

	for i in range(5):
		var _res := CampaignNodeInspection.inspect_node("node_frontier_depot")

	_check(CampaignTurnExecutive.get_turn() == turn_before, "O1: CampaignTurnExecutive turn counter untouched")


## --- SECTION P: NO HEAT/WANTED MUTATION ---
func _test_p_no_heat_wanted_mutation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var heat_before := GlobalData.board.heat
	var wanted_before := GlobalData.board.wanted_level

	var _res := CampaignNodeInspection.inspect_node("node_frontier_depot")

	_check(GlobalData.board.heat == heat_before, "P1: Heat unchanged")
	_check(GlobalData.board.wanted_level == wanted_before, "P2: Wanted level unchanged")


## --- SECTION Q: NO FACTION MUTATION ---
func _test_q_no_faction_mutation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var rel_before := FactionSystem.serialize_relations()

	var _res := CampaignNodeInspection.inspect_node("node_frontier_depot")

	var rel_after := FactionSystem.serialize_relations()
	_check(rel_after == rel_before, "Q1: Faction relations unchanged")


## --- SECTION R: NO BATTLE CREATION ---
func _test_r_no_battle_creation() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var battles_before := CampaignBattle.get_battles()

	var _res := CampaignNodeInspection.inspect_node("node_frontier_depot")

	var battles_after := CampaignBattle.get_battles()
	_check(battles_after == battles_before and battles_after.is_empty(), "R1: Zero battles created")


## --- SECTION S: REPEATED INSPECTION IDEMPOTENCE ---
func _test_s_repeated_inspection_idempotence() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var res1 := CampaignNodeInspection.inspect_node("node_frontier_city")
	var res2 := CampaignNodeInspection.inspect_node("node_frontier_city")
	var res3 := CampaignNodeInspection.inspect_node("node_frontier_city")

	_check(JSON.stringify(res1) == JSON.stringify(res2) and JSON.stringify(res2) == JSON.stringify(res3),
		"S1: Repeated inspections return identical projection results")


## --- SECTION T: DETERMINISM ---
func _test_t_determinism() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var snap1 := JSON.stringify(CampaignNodeInspection.inspect_node("node_frontier_depot"))

	_reset_campaign_runtime()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var snap2 := JSON.stringify(CampaignNodeInspection.inspect_node("node_frontier_depot"))

	_check(snap1 == snap2, "T1: Re-initialized scenario produces bit-identical projection")


## --- SECTION U: SAVE / LOAD CONSISTENCY ---
func _test_u_save_load_consistency() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var proj_before := CampaignNodeInspection.inspect_node("node_frontier_city")

	_check(SaveGameIO.save_run(), "U1: Save run succeeds")
	var save_text := FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	var save_json: Dictionary = JSON.parse_string(save_text)
	_check(not save_json.has("inspection") and not save_json.has("current_node_situation"),
		"U2: No redundant inspection data in save payload")

	# Clear physical position and simulate restore
	GlobalData.board.current_tile = Vector2i(0, 0)
	_check(SaveGameIO.load_run(), "U3: Load run succeeds")

	var proj_after := CampaignNodeInspection.inspect_node("node_frontier_city")
	_check(JSON.stringify(proj_after) == JSON.stringify(proj_before),
		"U4: Projection after load is identical to projection before save")


## --- SECTION V: NO DUPLICATE AUTHORITY ---
func _test_v_no_duplicate_authority() -> void:
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_node_interaction.gd"),
		"V1: No unapproved campaign_node_interaction.gd")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_interaction_manager.gd"),
		"V2: No unapproved campaign_interaction_manager.gd")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_encounter_manager.gd"),
		"V3: No unapproved campaign_encounter_manager.gd")


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
	print("PHASE 5AL SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN NODE SITUATION INSPECTION CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN NODE SITUATION INSPECTION CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
