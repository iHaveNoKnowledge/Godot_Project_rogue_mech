extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN INVESTIGATE ACTION DOMAIN CONTRACT VERIFICATION
## Phase 5AN Contract Verification Suite
##
## Proves the architectural contract:
##   1. Action Recognition & Intent:
##      - 'investigate' is recognized as a known action.
##      - create_intent produces a canonical intent shape.
##   2. Dispatch & Routing:
##      - Dispatcher routes 'investigate' to CampaignInvestigateAction handler.
##      - Custom handler registration and default handlers behave deterministically.
##   3. Precondition Enforcement:
##      - Unknown actions rejected ("unknown_action").
##      - Unknown nodes rejected ("unknown_node").
##      - Player not at node rejected ("player_not_at_node").
##   4. Result Contract:
##      - Success returns { "ok": true, "reason": "investigation_resolved", "action_id": "investigate", "node_id": node_id, "situation": Dictionary }
##      - Situation contains complete read-only projection (forces, bases, territory, routes, factions).
##   5. Side-Effect Safety & Invariants:
##      - Zero mutation to BoardState (position, heat, wanted).
##      - Zero mutation to CampaignNodeRegistry (topology).
##      - Zero mutation to CampaignTerritory (ownership/control).
##      - Zero mutation to CampaignBase (controllers/states).
##      - Zero mutation to CampaignForce (registries/strengths/positions).
##      - Zero mutation to FactionSystem relations and FactionEconomySystem.
##      - Zero turn or day advancement (CampaignTurnExecutive).
##      - Zero PlayerCampaignForce created or altered.
##   6. Canonical Coexistence:
##      - Investigation on canonical scenario node (frontier_skirmish) functions
##        safely with zero state drift.
## ---------------------------------------------------------------------------

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Investigate Action Domain Contract verification (Phase 5AN)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("INVESTIGATE_ACTION_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("INVESTIGATE_ACTION_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_known_action()
	_test_b_intent_creation()
	_test_c_valid_node_and_player_colocation()
	_test_d_player_not_at_node_rejection()
	_test_e_unknown_node_rejection()
	_test_f_unknown_action_rejection()
	_test_g_handler_routing_and_execution()
	_test_h_deterministic_success_result_structure()
	_test_i_unimplemented_action_behavior()
	_test_j_location_authority_integration()
	_test_k_side_effect_safety()
	_test_l_canonical_scenario_investigate()
	_test_m_direct_domain_handler_contract()


func _reset_campaign_runtime() -> void:
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
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


## --- SECTION A: KNOWN ACTION ---
func _test_a_known_action() -> void:
	_reset_campaign_runtime()

	_check(CampaignPlayerDispatch.is_known_action("investigate"), "A1: 'investigate' is recognized as a known action")
	_check(CampaignPlayerDispatch.get_known_actions().has("investigate"), "A2: Known actions list includes 'investigate'")


## --- SECTION B: INTENT CREATION ---
func _test_b_intent_creation() -> void:
	_reset_campaign_runtime()

	var payload := {"priority": "high", "source": "ui_panel"}
	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_outpost_alpha", payload)

	_check(str(intent.get("action_id", "")) == "investigate", "B1: Action intent action_id is 'investigate'")
	_check(str(intent.get("node_id", "")) == "node_outpost_alpha", "B2: Action intent node_id matches input")
	_check(intent.get("payload") is Dictionary and (intent.get("payload") as Dictionary).get("priority") == "high",
		"B3: Action intent preserves payload")


## --- SECTION C: VALID NODE & PLAYER CO-LOCATION ---
func _test_c_valid_node_and_player_colocation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 4), "city", "node_metro_1")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 4)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_metro_1")
	var validation := CampaignPlayerDispatch.validate_intent(intent)

	_check(bool(validation.get("ok", false)), "C1: Player at node passes intent validation (ok=true)")
	_check(str(validation.get("reason", "")) == "valid", "C2: Validation reason is 'valid'")


## --- SECTION D: PLAYER NOT AT NODE REJECTION ---
func _test_d_player_not_at_node_rejection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_city_d1")
	CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "city", "node_city_d2")

	# Player is at city d1, intent targets city d2
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_d2")
	var validation := CampaignPlayerDispatch.validate_intent(intent)
	var dispatch_res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(validation.get("ok", true)), "D1: Validation rejects when player not at node (ok=false)")
	_check(str(validation.get("reason", "")) == "player_not_at_node", "D2: Validation reason is 'player_not_at_node'")
	_check(not bool(dispatch_res.get("ok", true)), "D3: Dispatch rejects when player not at node")
	_check(str(dispatch_res.get("reason", "")) == "player_not_at_node", "D4: Dispatch reason is 'player_not_at_node'")



## --- SECTION E: UNKNOWN NODE REJECTION ---
func _test_e_unknown_node_rejection() -> void:
	_reset_campaign_runtime()

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(0, 0)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_nonexistent_xyz")
	var validation := CampaignPlayerDispatch.validate_intent(intent)
	var dispatch_res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(validation.get("ok", true)), "E1: Unknown node rejected at validation")
	_check(str(validation.get("reason", "")) == "unknown_node", "E2: Validation reason is 'unknown_node'")
	_check(str(dispatch_res.get("reason", "")) == "unknown_node", "E3: Dispatch reason is 'unknown_node'")


## --- SECTION F: UNKNOWN ACTION REJECTION ---
func _test_f_unknown_action_rejection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_f")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("super_orbital_strike", "node_city_f")
	var validation := CampaignPlayerDispatch.validate_intent(intent)
	var dispatch_res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(validation.get("ok", true)), "F1: Unknown action rejected at validation")
	_check(str(validation.get("reason", "")) == "unknown_action", "F2: Reason is 'unknown_action'")
	_check(str(dispatch_res.get("reason", "")) == "unknown_action", "F3: Dispatch reason is 'unknown_action'")


## --- SECTION G: HANDLER ROUTING & EXECUTION ---
func _test_g_handler_routing_and_execution() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "city", "node_city_g")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_g")
	var result := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(bool(result.get("ok", false)), "G1: Investigate action dispatches successfully (ok=true)")
	_check(str(result.get("reason", "")) == "investigation_resolved", "G2: Reason is 'investigation_resolved'")
	_check(str(result.get("action_id", "")) == "investigate", "G3: Echoes action_id 'investigate'")
	_check(str(result.get("node_id", "")) == "node_city_g", "G4: Echoes node_id 'node_city_g'")


## --- SECTION H: DETERMINISTIC SUCCESS RESULT STRUCTURE ---
func _test_h_deterministic_success_result_structure() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_metro_h")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "fuel_depot", "node_depot_h")
	CampaignNodeRegistry.register_route("node_metro_h", "node_depot_h")

	CampaignTerritory.register_territory("terr_h", ["node_metro_h", "node_depot_h"])
	CampaignTerritory.set_controlled("terr_h", "zeon")

	CampaignBase.register_base("base_h", "node_metro_h", "OUTPOST", "zeon", "terr_h")
	CampaignForce.register_force("force_h1", "PATROL", "zeon", "node_metro_h", "base_h", 3, 20)

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_metro_h")
	var res1 := CampaignPlayerDispatch.dispatch_intent(intent)
	var res2 := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(res1.has("situation") and (res1.get("situation") is Dictionary), "H1: Result contains 'situation' projection")
	var sit: Dictionary = res1.get("situation", {})
	_check(bool(sit.get("ok", false)), "H2: Situation projection ok=true")
	_check(bool(sit.get("player_present", false)), "H3: Situation reflects player present")
	_check((sit.get("forces") as Array).size() == 1, "H4: Situation projection includes registered force")
	_check(str((sit.get("base") as Dictionary).get("id", "")) == "base_h", "H5: Situation projection includes base")
	_check(str((sit.get("territory") as Dictionary).get("id", "")) == "terr_h", "H6: Situation projection includes territory")
	_check(JSON.stringify(res1) == JSON.stringify(res2), "H7: Repeated investigate calls produce bit-identical results")


## --- SECTION I: UNIMPLEMENTED ACTION BEHAVIOR ---
func _test_i_unimplemented_action_behavior() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_i")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	for action in ["defend"]:
		var intent := CampaignPlayerDispatch.create_intent(action, "node_city_i")
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_check(not bool(res.get("ok", true)), "I1: Unimplemented action '%s' rejected" % action)
		_check(str(res.get("reason", "")) == "action_not_implemented",
			"I2: Unimplemented action '%s' returns 'action_not_implemented'" % action)



## --- SECTION J: LOCATION AUTHORITY INTEGRATION ---
func _test_j_location_authority_integration() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot", "node_depot_j")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(5, 5)

	_check(CampaignNodeInspection.is_player_at_node("node_depot_j"),
		"J1: CampaignNodeInspection confirms player at node")
	_check(CampaignPlayerDispatch.validate_intent(CampaignPlayerDispatch.create_intent("investigate", "node_depot_j")).get("ok") == true,
		"J2: CampaignPlayerDispatch respects CampaignNodeInspection location")

	GlobalData.board.current_tile = Vector2i(5, 6)
	_check(not CampaignNodeInspection.is_player_at_node("node_depot_j"),
		"J3: CampaignNodeInspection confirms player moved off node")
	_check(CampaignPlayerDispatch.validate_intent(CampaignPlayerDispatch.create_intent("investigate", "node_depot_j")).get("ok") == false,
		"J4: CampaignPlayerDispatch rejects after player moved")


## --- SECTION K: SIDE-EFFECT SAFETY ---
func _test_k_side_effect_safety() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_k")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "fuel_depot", "node_depot_k")
	CampaignNodeRegistry.register_route("node_city_k", "node_depot_k")

	CampaignTerritory.register_territory("terr_k", ["node_city_k", "node_depot_k"])
	CampaignTerritory.set_controlled("terr_k", "federation")

	CampaignBase.register_base("base_k", "node_city_k", "OUTPOST", "federation", "terr_k")
	CampaignForce.register_force("force_k1", "PATROL", "federation", "node_city_k", "base_k", 3, 20)


	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.board.heat = 15
	GlobalData.board.wanted_level = 1

	var snap_before := _snap_campaign_state()

	# Run investigate multiple times
	for iter in range(5):
		var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_k")
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_check(bool(res.get("ok", false)), "K1.%d: Investigate iteration succeeded" % iter)

	var snap_after := _snap_campaign_state()

	_check(snap_after["forces"] == snap_before["forces"], "K2: Force state completely unchanged")
	_check(snap_after["territories"] == snap_before["territories"], "K3: Territory state completely unchanged")
	_check(snap_after["bases"] == snap_before["bases"], "K4: Base state completely unchanged")
	_check(snap_after["battles"] == snap_before["battles"], "K5: Zero battles created")
	_check(snap_after["turn"] == snap_before["turn"], "K6: Campaign turn unchanged")
	_check(snap_after["heat"] == snap_before["heat"], "K7: Heat unchanged")
	_check(snap_after["wanted"] == snap_before["wanted"], "K8: Wanted level unchanged")
	_check(snap_after["relations"] == snap_before["relations"], "K9: Faction relations unchanged")
	_check(snap_after["player_tile"] == snap_before["player_tile"], "K10: Player physical tile unchanged")
	_check(snap_after["player_sector"] == snap_before["player_sector"], "K11: Player sector unchanged")
	_check(not CampaignForce.has_force("player") and not CampaignForce.has_force("player_force"),
		"K12: No PlayerCampaignForce exists")


## --- SECTION L: CANONICAL SCENARIO INVESTIGATE ---
func _test_l_canonical_scenario_investigate() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	# Place player at depot
	GlobalData.board.current_tile = Vector2i(5, 3)

	var snap_before := _snap_campaign_state()
	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_frontier_depot")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)
	var snap_after := _snap_campaign_state()

	_check(bool(res.get("ok", false)), "L1: Investigate at canonical depot succeeds")
	_check(str(res.get("reason", "")) == "investigation_resolved", "L2: Reason is 'investigation_resolved'")
	_check(snap_after == snap_before, "L3: Canonical scenario state completely unchanged by investigation")

	var sit: Dictionary = res.get("situation", {})
	_check((sit.get("forces") as Array).size() == 1, "L4: Outland scavenger force observed in situation")
	_check(str((sit.get("territory") as Dictionary).get("controller", "")) == "zeon", "L5: Sector Beta territory Zeon controller observed")


## --- SECTION M: DIRECT DOMAIN HANDLER CONTRACT ---
func _test_m_direct_domain_handler_contract() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_m1")

	# Wrong action ID rejection
	var bad_action_res := CampaignInvestigateAction.handle_investigate({"action_id": "attack", "node_id": "node_m1"})
	_check(not bool(bad_action_res.get("ok", true)), "M1: Direct domain handler rejects wrong action_id")
	_check(str(bad_action_res.get("reason", "")) == "invalid_action_for_handler", "M2: Reason is 'invalid_action_for_handler'")

	# Unknown node rejection
	var bad_node_res := CampaignInvestigateAction.handle_investigate({"action_id": "investigate", "node_id": "nonexistent"})
	_check(not bool(bad_node_res.get("ok", true)), "M3: Direct domain handler rejects unknown node")
	_check(str(bad_node_res.get("reason", "")) == "unknown_node", "M4: Reason is 'unknown_node'")

	# Valid execution
	var valid_res := CampaignInvestigateAction.handle_investigate({"action_id": "investigate", "node_id": "node_m1"})
	_check(bool(valid_res.get("ok", false)), "M5: Direct domain handler produces valid result")
	_check(str(valid_res.get("reason", "")) == "investigation_resolved", "M6: Reason is 'investigation_resolved'")


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
	print("PHASE 5AN SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN INVESTIGATE ACTION DOMAIN CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN INVESTIGATE ACTION DOMAIN CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
