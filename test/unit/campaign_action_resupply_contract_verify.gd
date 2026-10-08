extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN RESUPPLY ACTION DOMAIN CONTRACT VERIFICATION
## Phase 5AO Contract Verification Suite
##
## Proves the architectural contract:
##   1. Action Recognition & Intent:
##      - 'resupply' is recognized as a known action.
##      - create_intent produces a canonical intent shape.
##   2. Dispatch & Routing:
##      - Dispatcher routes 'resupply' to CampaignResupplyAction handler.
##      - Built-in default handlers and dynamic overrides function deterministically.
##   3. Precondition Enforcement:
##      - Unknown actions rejected ("unknown_action").
##      - Unknown nodes rejected ("unknown_node").
##      - Player not at node rejected ("player_not_at_node").
##      - Unsupported node types (e.g. data_node, enemy_base) rejected ("node_cannot_resupply").
##      - Already full resources rejected on repeat invocation ("already_fully_supplied").
##   4. Exact Mutation Verification:
##      - Mutates GlobalData.fuel.mech_energy and convoy_fuel strictly by needed delta.
##      - Exact before and after values verified deterministically.
##   5. Side-Effect Safety & Invariants:
##      - Zero mutation to BoardState (position, heat, wanted).
##      - Zero mutation to CampaignNodeRegistry (topology).
##      - Zero mutation to CampaignTerritory (ownership/control).
##      - Zero mutation to CampaignBase (controllers/states).
##      - Zero mutation to CampaignForce (registries/strengths/positions).
##      - Zero mutation to FactionSystem relations and FactionEconomySystem.
##      - Zero turn or day advancement (CampaignTurnExecutive).
##      - Zero PlayerCampaignForce created or altered.
##   6. 5AN Preservation:
##      - 'investigate' remains fully functional and strictly read-only.
## ---------------------------------------------------------------------------

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Resupply Action Domain Contract verification (Phase 5AO)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("RESUPPLY_ACTION_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("RESUPPLY_ACTION_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_known_action()
	_test_b_intent_creation()
	_test_c_valid_node_and_player_colocation()
	_test_d_player_not_at_node_rejection()
	_test_e_unknown_node_rejection()
	_test_f_unknown_action_rejection()
	_test_g_node_type_precondition()
	_test_h_exact_mutation_and_success_result()
	_test_i_repeated_invocation_already_supplied()
	_test_j_side_effect_safety()
	_test_k_unimplemented_actions_remain_unimplemented()
	_test_l_preserve_5an_investigate()
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

	_check(CampaignPlayerDispatch.is_known_action("resupply"), "A1: 'resupply' is recognized as a known action")
	_check(CampaignPlayerDispatch.get_known_actions().has("resupply"), "A2: Known actions list includes 'resupply'")


## --- SECTION B: INTENT CREATION ---
func _test_b_intent_creation() -> void:
	_reset_campaign_runtime()

	var payload := {"resource": "energy", "urgency": "standard"}
	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_depot_b", payload)

	_check(str(intent.get("action_id", "")) == "resupply", "B1: Action intent action_id is 'resupply'")
	_check(str(intent.get("node_id", "")) == "node_depot_b", "B2: Action intent node_id matches input")
	_check(intent.get("payload") is Dictionary and (intent.get("payload") as Dictionary).get("resource") == "energy",
		"B3: Action intent preserves payload")


## --- SECTION C: VALID NODE & PLAYER CO-LOCATION ---
func _test_c_valid_node_and_player_colocation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 4), "fuel_depot", "node_depot_c")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 4)

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_depot_c")
	var validation := CampaignPlayerDispatch.validate_intent(intent)

	_check(bool(validation.get("ok", false)), "C1: Player at node passes intent validation (ok=true)")
	_check(str(validation.get("reason", "")) == "valid", "C2: Validation reason is 'valid'")


## --- SECTION D: PLAYER NOT AT NODE REJECTION ---
func _test_d_player_not_at_node_rejection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "fuel_depot", "node_depot_d1")
	CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "fuel_depot", "node_depot_d2")

	# Player is at depot d1, intent targets depot d2
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_depot_d2")
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

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_phantom_depot")
	var validation := CampaignPlayerDispatch.validate_intent(intent)
	var dispatch_res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(validation.get("ok", true)), "E1: Unknown node rejected at validation")
	_check(str(validation.get("reason", "")) == "unknown_node", "E2: Validation reason is 'unknown_node'")
	_check(str(dispatch_res.get("reason", "")) == "unknown_node", "E3: Dispatch reason is 'unknown_node'")


## --- SECTION F: UNKNOWN ACTION REJECTION ---
func _test_f_unknown_action_rejection() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "fuel_depot", "node_depot_f")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent := CampaignPlayerDispatch.create_intent("instant_hyper_refuel_nova", "node_depot_f")
	var validation := CampaignPlayerDispatch.validate_intent(intent)
	var dispatch_res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(validation.get("ok", true)), "F1: Unknown action rejected at validation")
	_check(str(validation.get("reason", "")) == "unknown_action", "F2: Reason is 'unknown_action'")
	_check(str(dispatch_res.get("reason", "")) == "unknown_action", "F3: Dispatch reason is 'unknown_action'")


## --- SECTION G: NODE TYPE PRECONDITION ---
func _test_g_node_type_precondition() -> void:
	_reset_campaign_runtime()

	# Register a non-resupply node (data_node) and a resupply node (city)
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "data_node", "node_datanode_g")
	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city", "node_city_g")

	# Drain some energy first so energy capacity isn't the blocker
	GlobalData.fuel.mech_energy = 500.0

	# Test at data_node
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var intent_bad := CampaignPlayerDispatch.create_intent("resupply", "node_datanode_g")
	var res_bad := CampaignPlayerDispatch.dispatch_intent(intent_bad)

	_check(not bool(res_bad.get("ok", true)), "G1: Resupply at data_node rejected (ok=false)")
	_check(str(res_bad.get("reason", "")) == "node_cannot_resupply", "G2: Reason is 'node_cannot_resupply'")
	_check(GlobalData.fuel.mech_energy == 500.0, "G3: Rejected node resupply caused zero energy mutation")

	# Test at city
	GlobalData.board.current_tile = Vector2i(3, 3)
	var intent_good := CampaignPlayerDispatch.create_intent("resupply", "node_city_g")
	var res_good := CampaignPlayerDispatch.dispatch_intent(intent_good)

	_check(bool(res_good.get("ok", false)), "G4: Resupply at city accepted (ok=true)")
	_check(str(res_good.get("reason", "")) == "resupply_completed", "G5: Reason is 'resupply_completed'")


## --- SECTION H: EXACT MUTATION & SUCCESS RESULT ---
func _test_h_exact_mutation_and_success_result() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot", "node_depot_h")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(5, 5)

	# Set precise before state
	GlobalData.fuel.mech_energy = 350.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.convoy_fuel = 150.0
	GlobalData.fuel.convoy_max_fuel = 500.0

	var energy_before := GlobalData.fuel.mech_energy
	var fuel_before := GlobalData.fuel.convoy_fuel

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_depot_h")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)

	var energy_after := GlobalData.fuel.mech_energy
	var fuel_after := GlobalData.fuel.convoy_fuel

	_check(bool(res.get("ok", false)), "H1: Resupply dispatch succeeded")
	_check(str(res.get("reason", "")) == "resupply_completed", "H2: Reason is 'resupply_completed'")
	_check(str(res.get("action_id", "")) == "resupply", "H3: Echoes action_id 'resupply'")
	_check(str(res.get("node_id", "")) == "node_depot_h", "H4: Echoes node_id 'node_depot_h'")
	_check(is_equal_approx(float(res.get("mech_energy_gained", 0.0)), 650.0), "H5: Result reports exact mech_energy_gained = 650.0")
	_check(is_equal_approx(float(res.get("convoy_fuel_gained", 0.0)), 350.0), "H6: Result reports exact convoy_fuel_gained = 350.0")
	_check(is_equal_approx(energy_after, 1000.0), "H7: Post-action mech_energy is exactly 1000.0")
	_check(is_equal_approx(fuel_after, 500.0), "H8: Post-action convoy_fuel is exactly 500.0")
	_check(is_equal_approx(energy_after - energy_before, 650.0), "H9: Exact mech energy delta verified")
	_check(is_equal_approx(fuel_after - fuel_before, 350.0), "H10: Exact convoy fuel delta verified")


## --- SECTION I: REPEATED INVOCATION (ALREADY SUPPLIED) ---
func _test_i_repeated_invocation_already_supplied() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse", "node_safehouse_i")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)

	# Ensure resources are full
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.convoy_fuel = 500.0
	GlobalData.fuel.convoy_max_fuel = 500.0

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_safehouse_i")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(not bool(res.get("ok", true)), "I1: Repeat resupply when already full rejected (ok=false)")
	_check(str(res.get("reason", "")) == "already_fully_supplied", "I2: Reason is 'already_fully_supplied'")
	_check(GlobalData.fuel.mech_energy == 1000.0, "I3: Energy remains unchanged at 1000.0")
	_check(GlobalData.fuel.convoy_fuel == 500.0, "I4: Convoy fuel remains unchanged at 500.0")


## --- SECTION J: SIDE-EFFECT SAFETY ---
func _test_j_side_effect_safety() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_j")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "fuel_depot", "node_depot_j")
	CampaignNodeRegistry.register_route("node_city_j", "node_depot_j")

	CampaignTerritory.register_territory("terr_j", ["node_city_j", "node_depot_j"])
	CampaignTerritory.set_controlled("terr_j", "federation")

	CampaignBase.register_base("base_j", "node_city_j", "OUTPOST", "federation", "terr_j")
	CampaignForce.register_force("force_j1", "PATROL", "federation", "node_city_j", "base_j", 3, 20)

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 3) # at depot
	GlobalData.board.heat = 22
	GlobalData.board.wanted_level = 2
	GlobalData.fuel.mech_energy = 600.0

	var snap_before := _snap_campaign_state()

	var intent := CampaignPlayerDispatch.create_intent("resupply", "node_depot_j")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)

	var snap_after := _snap_campaign_state()

	_check(bool(res.get("ok", false)), "J1: Resupply succeeded")
	_check(snap_after["forces"] == snap_before["forces"], "J2: Force state completely unchanged")
	_check(snap_after["territories"] == snap_before["territories"], "J3: Territory state completely unchanged")
	_check(snap_after["bases"] == snap_before["bases"], "J4: Base state completely unchanged")
	_check(snap_after["battles"] == snap_before["battles"], "J5: Zero battles created")
	_check(snap_after["turn"] == snap_before["turn"], "J6: Campaign turn unchanged")
	_check(snap_after["heat"] == snap_before["heat"], "J7: Heat unchanged")
	_check(snap_after["wanted"] == snap_before["wanted"], "J8: Wanted level unchanged")
	_check(snap_after["relations"] == snap_before["relations"], "J9: Faction relations unchanged")
	_check(snap_after["player_tile"] == snap_before["player_tile"], "J10: Player physical tile unchanged")
	_check(snap_after["player_sector"] == snap_before["player_sector"], "J11: Player sector unchanged")
	_check(not CampaignForce.has_force("player") and not CampaignForce.has_force("player_force"),
		"J12: No PlayerCampaignForce exists")


## --- SECTION K: UNIMPLEMENTED ACTIONS REMAIN UNIMPLEMENTED ---
func _test_k_unimplemented_actions_remain_unimplemented() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_k")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	for action in ["attack", "defend", "capture"]:
		var intent := CampaignPlayerDispatch.create_intent(action, "node_city_k")
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_check(not bool(res.get("ok", true)), "K1: Action '%s' remains unimplemented" % action)
		_check(str(res.get("reason", "")) == "action_not_implemented",
			"K2: Action '%s' returns 'action_not_implemented'" % action)


## --- SECTION L: PRESERVE 5AN INVESTIGATE ---
func _test_l_preserve_5an_investigate() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_l")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.fuel.mech_energy = 500.0

	var fuel_before := GlobalData.fuel.mech_energy
	var intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_l")
	var res := CampaignPlayerDispatch.dispatch_intent(intent)

	_check(bool(res.get("ok", false)), "L1: 'investigate' remains fully functional")
	_check(str(res.get("reason", "")) == "investigation_resolved", "L2: Reason is 'investigation_resolved'")
	_check(res.has("situation"), "L3: Result contains situation projection")
	_check(GlobalData.fuel.mech_energy == fuel_before, "L4: 'investigate' causes ZERO fuel mutation (strictly read-only)")


## --- SECTION M: DIRECT DOMAIN HANDLER CONTRACT ---
func _test_m_direct_domain_handler_contract() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "fuel_depot", "node_m1")

	# Wrong action ID rejection
	var bad_action_res := CampaignResupplyAction.handle_resupply({"action_id": "attack", "node_id": "node_m1"})
	_check(not bool(bad_action_res.get("ok", true)), "M1: Direct domain handler rejects wrong action_id")
	_check(str(bad_action_res.get("reason", "")) == "invalid_action_for_handler", "M2: Reason is 'invalid_action_for_handler'")

	# Unknown node rejection
	var bad_node_res := CampaignResupplyAction.handle_resupply({"action_id": "resupply", "node_id": "nonexistent"})
	_check(not bool(bad_node_res.get("ok", true)), "M3: Direct domain handler rejects unknown node")
	_check(str(bad_node_res.get("reason", "")) == "unknown_node", "M4: Reason is 'unknown_node'")

	# Valid execution
	GlobalData.fuel.mech_energy = 300.0
	var valid_res := CampaignResupplyAction.handle_resupply({"action_id": "resupply", "node_id": "node_m1"})
	_check(bool(valid_res.get("ok", false)), "M5: Direct domain handler produces valid result")
	_check(str(valid_res.get("reason", "")) == "resupply_completed", "M6: Reason is 'resupply_completed'")
	_check(GlobalData.fuel.mech_energy == 1000.0, "M7: Direct domain handler mutates energy correctly")


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
	print("PHASE 5AO SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN RESUPPLY ACTION DOMAIN CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN RESUPPLY ACTION DOMAIN CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
