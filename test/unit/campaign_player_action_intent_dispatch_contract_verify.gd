extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN PLAYER ACTION INTENT & DISPATCH BOUNDARY CONTRACT VERIFICATION
## Phase 5AM Contract Verification Suite
##
## Proves the architectural contract:
##   1. Thin Dispatch Boundary:
##      - CampaignPlayerDispatch routes action intents from UI/decision layer.
##      - Validates action recognition, node presence, and player co-location.
##      - Dispatcher is NOT a domain owner (zero execution of combat, capture,
##        supply, turns, or force/base mutations).
##   2. Rejection Contracts:
##      - "unknown_action" for unrecognized action IDs.
##      - "unknown_node" for non-existent node IDs.
##      - "player_not_at_node" when player is not located at targeted node.
##      - "action_not_implemented" when valid intent has no domain handler.
##   3. Zero Side-Effects:
##      - Calling dispatch for unimplemented actions causes zero mutation across
##        BoardState, NodeRegistry, Territory, Base, Force, Battle, Turn,
##        Heat/Wanted, Faction relations, and Economy.
##   4. Canonical Coexistence:
##      - frontier_skirmish depot facts remain completely intact under intent dispatch.
##   5. Player Separation:
##      - No Player CampaignForce is created or used.
## ---------------------------------------------------------------------------

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Player Action Intent & Dispatch Boundary Contract verification (Phase 5AM)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("ACTION_DISPATCH_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("ACTION_DISPATCH_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_valid_intent_shape()
	_test_b_unknown_action()
	_test_c_unknown_node()
	_test_d_player_not_at_node()
	_test_e_player_at_node_valid_intent()
	_test_f_unimplemented_action_result()
	_test_g_deterministic_result()
	_test_h_no_player_movement()
	_test_i_no_force_mutation()
	_test_j_no_territory_mutation()
	_test_k_no_base_mutation()
	_test_l_no_battle_creation()
	_test_m_no_turn_advancement()
	_test_n_no_heat_wanted_mutation()
	_test_o_no_faction_economy_mutation()
	_test_p_repeated_dispatch_no_state_drift()
	_test_q_canonical_depot_coexistence_intact()
	_test_r_no_player_campaign_force()
	_test_s_no_duplicate_action_authority()


func _reset_campaign_runtime() -> void:
	CampaignPlayerDispatch.clear_handlers()
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


## --- SECTION A: VALID INTENT SHAPE ---
func _test_a_valid_intent_shape() -> void:
	_reset_campaign_runtime()

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_1", {"source": "ui"})
	_check(str(intent.get("action_id", "")) == "investigate", "A1: Intent contains action_id")
	_check(str(intent.get("node_id", "")) == "node_city_1", "A2: Intent contains node_id")
	_check(intent.has("payload") and (intent.get("payload") is Dictionary), "A3: Intent contains payload dictionary")


## --- SECTION B: UNKNOWN ACTION ---
func _test_b_unknown_action() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_b")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var snap_before := _snap_campaign_state()
	var intent := CampaignPlayerDispatch.create_intent("super_laser_orbital_bombardment", "node_city_b")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)
	var snap_after := _snap_campaign_state()

	_check(not bool(res.get("ok", true)), "B1: Unknown action rejected (ok=false)")
	_check(str(res.get("reason", "")) == "unknown_action", "B2: Reason is 'unknown_action'")
	_check(snap_after == snap_before, "B3: Unknown action dispatch leaves campaign state untouched")


## --- SECTION C: UNKNOWN NODE ---
func _test_c_unknown_node() -> void:
	_reset_campaign_runtime()

	var snap_before := _snap_campaign_state()
	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_phantom_location")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)
	var snap_after := _snap_campaign_state()

	_check(not bool(res.get("ok", true)), "C1: Unknown node rejected (ok=false)")
	_check(str(res.get("reason", "")) == "unknown_node", "C2: Reason is 'unknown_node'")
	_check(snap_after == snap_before, "C3: Unknown node leaves campaign state untouched")


## --- SECTION D: PLAYER NOT AT NODE ---
func _test_d_player_not_at_node() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_d1")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot", "node_depot_d2")

	# Player is physically at node_city_d1
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	# Action intent targets distant node_depot_d2
	var snap_before := _snap_campaign_state()
	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_depot_d2")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)
	var snap_after := _snap_campaign_state()

	_check(not bool(res.get("ok", true)), "D1: Remote node action rejected (ok=false)")
	_check(str(res.get("reason", "")) == "player_not_at_node", "D2: Reason is 'player_not_at_node'")
	_check(snap_after == snap_before, "D3: Remote action rejection leaves state untouched")


## --- SECTION E: PLAYER AT NODE (VALID INTENT) ---
func _test_e_player_at_node_valid_intent() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_e")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_e")
	var val := CampaignPlayerDispatch.validate_intent(intent)

	_check(bool(val.get("ok", false)), "E1: Intent at player node validates successfully")
	_check(str(val.get("reason", "")) == "valid", "E2: Validation reason is 'valid'")


## --- SECTION F: UNIMPLEMENTED ACTION ---
func _test_f_unimplemented_action_result() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_f")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_f")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(res.get("ok", true)), "F1: Unimplemented action rejected (ok=false)")
	_check(str(res.get("reason", "")) == "action_not_implemented", "F2: Reason is 'action_not_implemented'")
	_check(str(res.get("action_id", "")) == "investigate", "F3: Result echoes action_id")
	_check(str(res.get("node_id", "")) == "node_city_f", "F4: Result echoes node_id")


## --- SECTION G: DETERMINISTIC RESULT ---
func _test_g_deterministic_result() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city", "node_city_g")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 3)

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_city_g")
	var res1 := CampaignPlayerDispatch.dispatch_intent(intent)
	var res2 := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(JSON.stringify(res1) == JSON.stringify(res2), "G1: Repeated dispatch produces bit-identical result dictionary")


## --- SECTION H: NO PLAYER MOVEMENT ---
func _test_h_no_player_movement() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_h")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var pos_before: Vector2i = GlobalData.board.current_tile
	var intent := CampaignPlayerDispatch.create_intent("attack", "node_city_h")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(GlobalData.board.current_tile == pos_before, "H1: Player physical position unmutated by dispatch")


## --- SECTION I: NO FORCE MUTATION ---
func _test_i_no_force_mutation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_i")
	CampaignForce.register_force("force_i1", "PATROL", "zeon", "node_city_i", "", 3, 30)
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var forces_before := CampaignForce.get_forces()
	var intent := CampaignPlayerDispatch.create_intent("attack", "node_city_i")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)
	var forces_after := CampaignForce.get_forces()

	_check(forces_after == forces_before, "I1: Force registry unmutated by action dispatch")


## --- SECTION J: NO TERRITORY MUTATION ---
func _test_j_no_territory_mutation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_j")
	CampaignTerritory.register_territory("terr_j", ["node_city_j"])
	CampaignTerritory.set_controlled("terr_j", "zeon")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var terr_before := CampaignTerritory.serialize()
	var intent := CampaignPlayerDispatch.create_intent("capture", "node_city_j")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)
	var terr_after := CampaignTerritory.serialize()

	_check(terr_after == terr_before, "J1: Territory state unmutated by action dispatch")


## --- SECTION K: NO BASE MUTATION ---
func _test_k_no_base_mutation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_k")
	CampaignTerritory.register_territory("terr_k", ["node_city_k"])
	CampaignBase.register_base("base_k", "node_city_k", "OUTPOST", "zeon", "terr_k")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var bases_before := CampaignBase.get_bases()
	var intent := CampaignPlayerDispatch.create_intent("attack", "node_city_k")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)
	var bases_after := CampaignBase.get_bases()

	_check(bases_after == bases_before, "K1: Base state unmutated by action dispatch")


## --- SECTION L: NO BATTLE CREATION ---
func _test_l_no_battle_creation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_l")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("attack", "node_city_l")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(CampaignBattle.get_battles().is_empty(), "L1: Zero battles created by action dispatch")


## --- SECTION M: NO TURN ADVANCEMENT ---
func _test_m_no_turn_advancement() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_m")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var turn_before := CampaignTurnExecutive.get_turn()
	for i in range(5):
		var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_m")
		var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(CampaignTurnExecutive.get_turn() == turn_before, "M1: Turn counter untouched after multiple dispatches")


## --- SECTION N: NO HEAT/WANTED MUTATION ---
func _test_n_no_heat_wanted_mutation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_n")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var heat_before := GlobalData.board.heat
	var wanted_before := GlobalData.board.wanted_level

	var intent := CampaignPlayerDispatch.create_intent("attack", "node_city_n")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(GlobalData.board.heat == heat_before, "N1: Heat unmutated")
	_check(GlobalData.board.wanted_level == wanted_before, "N2: Wanted level unmutated")


## --- SECTION O: NO FACTION/ECONOMY MUTATION ---
func _test_o_no_faction_economy_mutation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_o")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var rel_before := FactionSystem.serialize_relations()
	var econ_before := FactionEconomySystem.get_economy("zeon").duplicate(true)

	var intent := CampaignPlayerDispatch.create_intent("trade", "node_city_o")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	var rel_after := FactionSystem.serialize_relations()
	var econ_after := FactionEconomySystem.get_economy("zeon").duplicate(true)

	_check(rel_after == rel_before, "O1: Faction relations unmutated")
	_check(econ_after == econ_before, "O2: Faction economy unmutated")


## --- SECTION P: REPEATED DISPATCH NO STATE DRIFT ---
func _test_p_repeated_dispatch_no_state_drift() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_p")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var snap_before := _snap_campaign_state()

	for a in ["investigate", "attack", "resupply", "trade", "defend", "capture"]:
		var intent := CampaignPlayerDispatch.create_intent(a, "node_city_p")
		var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	var snap_after := _snap_campaign_state()
	_check(snap_after == snap_before, "P1: All core intents dispatched with zero cumulative state drift")


## --- SECTION Q: CANONICAL DEPOT COEXISTENCE INTACT ---
func _test_q_canonical_depot_coexistence_intact() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.board.current_tile = Vector2i(5, 3) # at depot

	var snap_before := _snap_campaign_state()
	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_frontier_depot")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)
	var snap_after := _snap_campaign_state()

	_check(str(res.get("reason", "")) == "action_not_implemented", "Q1: Canonical depot intent returns action_not_implemented")
	_check(snap_after == snap_before, "Q2: Canonical depot facts untouched by intent dispatch")
	_check(CampaignTerritory.get_controller("terr_frontier_sector_beta") == "zeon", "Q3: Sector Beta remains Zeon controlled")
	_check(CampaignForce.get_force("force_s1_outland_scavengers").get("node_id") == "node_frontier_depot",
		"Q4: Outland scavenger force remains at depot")


## --- SECTION R: NO PLAYER CAMPAIGN FORCE ---
func _test_r_no_player_campaign_force() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_r")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_r")
	var _res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not CampaignForce.has_force("player"), "R1: No 'player' in CampaignForce")
	_check(not CampaignForce.has_force("player_force"), "R2: No 'player_force' in CampaignForce")
	_check(CampaignForce.get_forces().is_empty(), "R3: CampaignForce registry remains completely empty")


## --- SECTION S: NO DUPLICATE ACTION AUTHORITY ---
func _test_s_no_duplicate_action_authority() -> void:
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_action_system.gd"),
		"S1: No unapproved campaign_action_system.gd")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_orchestrator.gd"),
		"S2: No unapproved campaign_orchestrator.gd")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_interaction_manager.gd"),
		"S3: No unapproved campaign_interaction_manager.gd")


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
	print("PHASE 5AM SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN PLAYER ACTION INTENT DISPATCH CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN PLAYER ACTION INTENT DISPATCH CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
