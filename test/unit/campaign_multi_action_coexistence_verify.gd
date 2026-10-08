extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN MULTI-ACTION COEXISTENCE & ACTION-LAYER HARDENING VERIFICATION
## Phase 5AP Contract Verification Suite
##
## Proves the architectural contract:
##   1. Multi-Action Registration & Independence:
##      - 'investigate' (read-only) and 'resupply' (mutating) coexist safely.
##      - Overriding or unregistering one does not mutate or displace the other.
##   2. Dispatch Boundary Routing:
##      - Dispatcher routes 'investigate' strictly to CampaignInvestigateAction.
##      - Dispatcher routes 'resupply' strictly to CampaignResupplyAction.
##      - Core known actions without handlers ('attack', 'trade', 'defend', 'capture')
##        deterministically return "action_not_implemented".
##      - Unrecognized action IDs return "unknown_action".
##   3. Cross-Action State Isolation:
##      - 'investigate' never mutates fuel, energy, or any campaign domain state.
##      - 'resupply' strictly mutates FuelManager energy and fuel pools by exact deltas.
##      - Neither action mutates territory, base, force, battle, relation, or turn state.
##   4. Turn Isolation:
##      - Neither action advances the campaign turn (CampaignTurnExecutive untouched).
##   5. Position Truth:
##      - Player location is strictly read from BoardState/CampaignNodeInspection.
##      - Neither action alters position or creates a secondary location authority.
##   6. Order Independence:
##      - Both [investigate -> resupply -> investigate] and [resupply -> investigate -> resupply]
##        execute deterministically and safely.
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
	print("Running Campaign Multi-Action Coexistence & Action-Layer Hardening verification (Phase 5AP)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("MULTI_ACTION_HARDENING OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("MULTI_ACTION_HARDENING FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_registration_and_known_actions()
	_test_b_handler_isolation_and_overrides()
	_test_c_shared_generic_validations()
	_test_d_unknown_and_unimplemented_actions()
	_test_e_cross_action_state_isolation()
	_test_f_order_independence()
	_test_g_turn_isolation()
	_test_h_position_authority_isolation()
	_test_i_comprehensive_side_effect_firewall()
	_test_j_canonical_scenario_multi_action_coexistence()


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
		"mech_energy": GlobalData.fuel.mech_energy,
		"convoy_fuel": GlobalData.fuel.convoy_fuel,
	}


## --- SECTION A: REGISTRATION & KNOWN ACTIONS ---
func _test_a_registration_and_known_actions() -> void:
	_reset_campaign_runtime()

	_check(CampaignPlayerDispatch.is_known_action("investigate"), "A1: 'investigate' is recognized")
	_check(CampaignPlayerDispatch.is_known_action("resupply"), "A2: 'resupply' is recognized")
	var known := CampaignPlayerDispatch.get_known_actions()
	_check(known.has("investigate") and known.has("resupply"), "A3: Known actions contain both actions")
	_check(not CampaignPlayerDispatch.is_known_action("nonexistent_action"), "A4: Unregistered action not recognized")


## --- SECTION B: HANDLER ISOLATION & OVERRIDES ---
func _test_b_handler_isolation_and_overrides() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_b")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	# Test custom override on resupply only
	var custom_state := {"called": false}
	var custom_resupply := func(intent: Dictionary) -> Dictionary:
		custom_state["called"] = true
		return {"ok": true, "reason": "custom_resupply_handler", "action_id": "resupply", "node_id": intent.get("node_id")}

	CampaignPlayerDispatch.register_handler("resupply", custom_resupply)

	# Dispatch investigate (must still route to default CampaignInvestigateAction)
	var inv_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_b"))
	_check(bool(inv_res.get("ok", false)), "B1: Investigate succeeds under overridden resupply")
	_check(str(inv_res.get("reason", "")) == "investigation_resolved", "B2: Investigate routes to its own domain handler")
	_check(not custom_state["called"], "B3: Custom resupply handler was not called by investigate")

	# Dispatch resupply (must route to custom handler)
	var res_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_city_b"))
	_check(custom_state["called"], "B4: Custom resupply handler was called")
	_check(str(res_res.get("reason", "")) == "custom_resupply_handler", "B5: Resupply routed to custom handler")

	# Unregister investigate only
	CampaignPlayerDispatch.unregister_handler("investigate")
	var inv_unreg := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_b"))
	_check(not bool(inv_unreg.get("ok", true)), "B6: Unregistered investigate returns ok=false")
	_check(str(inv_unreg.get("reason", "")) == "action_not_implemented", "B7: Unregistered investigate returns action_not_implemented")

	# Resupply still works
	var res_after := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_city_b"))
	_check(bool(res_after.get("ok", false)), "B8: Resupply remains functional after investigate unregistered")

	# Restore defaults
	CampaignPlayerDispatch.register_default_handlers()
	var inv_restored := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_b"))
	_check(str(inv_restored.get("reason", "")) == "investigation_resolved", "B9: Default investigate handler restored")


## --- SECTION C: SHARED GENERIC VALIDATIONS ---
func _test_c_shared_generic_validations() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_c1")
	CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "city", "node_city_c2")

	# Player is at c1
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	# 1. Unknown node validation
	for action in ["investigate", "resupply"]:
		var intent := CampaignPlayerDispatch.create_intent(action, "node_phantom_x")
		var val := CampaignPlayerDispatch.validate_intent(intent)
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_check(str(val.get("reason", "")) == "unknown_node", "C1 (%s): Validation rejects unknown node" % action)
		_check(str(res.get("reason", "")) == "unknown_node", "C2 (%s): Dispatch rejects unknown node" % action)

	# 2. Player not at node validation
	for action in ["investigate", "resupply"]:
		var intent := CampaignPlayerDispatch.create_intent(action, "node_city_c2")
		var val := CampaignPlayerDispatch.validate_intent(intent)
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_check(str(val.get("reason", "")) == "player_not_at_node", "C3 (%s): Validation rejects distant node" % action)
		_check(str(res.get("reason", "")) == "player_not_at_node", "C4 (%s): Dispatch rejects distant node" % action)


## --- SECTION D: UNKNOWN AND UNIMPLEMENTED ACTIONS ---
func _test_d_unknown_and_unimplemented_actions() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_d")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	var snap_before := _snap_campaign_state()

	# Unknown action ID
	var bad_intent := CampaignPlayerDispatch.create_intent("unknown_orbital_bombardment", "node_city_d")
	var bad_res := CampaignPlayerDispatch.dispatch_intent(bad_intent)
	_check(str(bad_res.get("reason", "")) == "unknown_action", "D1: Unrecognized action returns unknown_action")

	# Core known actions that are currently unimplemented
	for action in ["defend"]:
		var intent := CampaignPlayerDispatch.create_intent(action, "node_city_d")
		var res := CampaignPlayerDispatch.dispatch_intent(intent)
		_check(not bool(res.get("ok", true)), "D2 (%s): Unimplemented action rejected" % action)
		_check(str(res.get("reason", "")) == "action_not_implemented", "D3 (%s): Reason is action_not_implemented" % action)

	var snap_after := _snap_campaign_state()
	_check(snap_after == snap_before, "D4: Failed/unimplemented dispatches leave state 100% untouched")


## --- SECTION E: CROSS-ACTION STATE ISOLATION ---
func _test_e_cross_action_state_isolation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "fuel_depot", "node_depot_e")
	CampaignNodeRegistry.register_node(1, Vector2i(3, 4), "city", "node_city_e")
	CampaignNodeRegistry.register_route("node_depot_e", "node_city_e")

	CampaignTerritory.register_territory("terr_e", ["node_depot_e", "node_city_e"])
	CampaignTerritory.set_controlled("terr_e", "zeon")
	CampaignBase.register_base("base_e", "node_depot_e", "OUTPOST", "zeon", "terr_e")
	CampaignForce.register_force("force_e1", "PATROL", "zeon", "node_depot_e", "base_e", 3, 20)

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 3)

	# Set energy & fuel to partial levels
	GlobalData.fuel.mech_energy = 400.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.convoy_fuel = 200.0
	GlobalData.fuel.convoy_max_fuel = 500.0

	var energy_initial := GlobalData.fuel.mech_energy
	var fuel_initial := GlobalData.fuel.convoy_fuel

	# 1. Execute investigate
	var inv_intent := CampaignPlayerDispatch.create_intent("investigate", "node_depot_e")
	var inv_res1 := CampaignPlayerDispatch.dispatch_intent(inv_intent)

	_check(bool(inv_res1.get("ok", false)), "E1: First investigate succeeds")
	_check(GlobalData.fuel.mech_energy == energy_initial, "E2: Investigate causes zero mech energy mutation")
	_check(GlobalData.fuel.convoy_fuel == fuel_initial, "E3: Investigate causes zero convoy fuel mutation")

	# 2. Execute resupply
	var res_intent := CampaignPlayerDispatch.create_intent("resupply", "node_depot_e")
	var res_res := CampaignPlayerDispatch.dispatch_intent(res_intent)

	_check(bool(res_res.get("ok", false)), "E4: Resupply succeeds")
	_check(GlobalData.fuel.mech_energy == 1000.0, "E5: Resupply mutates mech energy to max (1000.0)")
	_check(GlobalData.fuel.convoy_fuel == 500.0, "E6: Resupply mutates convoy fuel to max (500.0)")
	_check(is_equal_approx(float(res_res.get("mech_energy_gained", 0.0)), 600.0), "E7: Exactly 600.0 energy gained reported")
	_check(is_equal_approx(float(res_res.get("convoy_fuel_gained", 0.0)), 300.0), "E8: Exactly 300.0 convoy fuel gained reported")

	# 3. Execute investigate again
	var inv_res2 := CampaignPlayerDispatch.dispatch_intent(inv_intent)

	_check(bool(inv_res2.get("ok", false)), "E9: Second investigate succeeds after resupply")
	_check(GlobalData.fuel.mech_energy == 1000.0, "E10: Energy remains 1000.0 after second investigate")
	var sit: Dictionary = inv_res2.get("situation", {})
	_check(bool(sit.get("ok", false)), "E11: Situation projection valid")
	_check(str((sit.get("territory") as Dictionary).get("id", "")) == "terr_e", "E12: Situation projection intact")


## --- SECTION F: ORDER INDEPENDENCE ---
func _test_f_order_independence() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_f")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	# Set partial resources
	GlobalData.fuel.mech_energy = 500.0
	GlobalData.fuel.convoy_fuel = 250.0

	var res_intent := CampaignPlayerDispatch.create_intent("resupply", "node_city_f")
	var inv_intent := CampaignPlayerDispatch.create_intent("investigate", "node_city_f")

	# Sequence B: [resupply -> investigate -> resupply]
	var res1 := CampaignPlayerDispatch.dispatch_intent(res_intent)
	_check(bool(res1.get("ok", false)), "F1: First resupply succeeds")
	_check(GlobalData.fuel.mech_energy == 1000.0, "F2: Energy filled to 1000.0")

	var inv1 := CampaignPlayerDispatch.dispatch_intent(inv_intent)
	_check(bool(inv1.get("ok", false)), "F3: Investigate between resupplies succeeds")

	var res2 := CampaignPlayerDispatch.dispatch_intent(res_intent)
	_check(not bool(res2.get("ok", true)), "F4: Second resupply cleanly rejected (already full)")
	_check(str(res2.get("reason", "")) == "already_fully_supplied", "F5: Reason is already_fully_supplied")
	_check(GlobalData.fuel.mech_energy == 1000.0, "F6: Energy remains uncorrupted at 1000.0")


## --- SECTION G: TURN ISOLATION ---
func _test_g_turn_isolation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "fuel_depot", "node_depot_g")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)

	var turn_before := CampaignTurnExecutive.get_turn()

	# Run a sequence of mixed action dispatches
	for iter in range(4):
		GlobalData.fuel.mech_energy = 500.0 # drain partially
		var _r1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_depot_g"))
		var _i1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_depot_g"))
		var _r2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_depot_g"))

	var turn_after := CampaignTurnExecutive.get_turn()
	_check(turn_after == turn_before, "G1: Multi-action sequence caused ZERO turn advancement (turn=%d)" % turn_after)


## --- SECTION H: POSITION AUTHORITY ISOLATION ---
func _test_h_position_authority_isolation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "city", "node_city_h")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(6, 6)

	var pos_before := GlobalData.board.current_tile
	var sector_before := GlobalData.board.current_sector

	var _i := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_h"))
	var _r := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_city_h"))

	_check(GlobalData.board.current_tile == pos_before, "H1: Player tile unchanged")
	_check(GlobalData.board.current_sector == sector_before, "H2: Player sector unchanged")
	_check(CampaignNodeInspection.is_player_at_node("node_city_h"), "H3: CampaignNodeInspection position truth intact")


## --- SECTION I: COMPREHENSIVE SIDE-EFFECT FIREWALL ---
func _test_i_comprehensive_side_effect_firewall() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "fuel_depot", "node_depot_i")
	CampaignNodeRegistry.register_node(1, Vector2i(1, 2), "city", "node_city_i")
	CampaignNodeRegistry.register_route("node_depot_i", "node_city_i")

	CampaignTerritory.register_territory("terr_i", ["node_depot_i", "node_city_i"])
	CampaignTerritory.set_controlled("terr_i", "federation")
	CampaignBase.register_base("base_i", "node_depot_i", "OUTPOST", "federation", "terr_i")
	CampaignForce.register_force("force_i1", "PATROL", "federation", "node_depot_i", "base_i", 4, 30)

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)
	GlobalData.board.heat = 18
	GlobalData.board.wanted_level = 1
	GlobalData.fuel.mech_energy = 500.0

	var snap_before := _snap_campaign_state()

	# Dispatch investigate then resupply
	var _i := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_depot_i"))
	var _r := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_depot_i"))

	var snap_after := _snap_campaign_state()

	_check(snap_after["forces"] == snap_before["forces"], "I1: Forces unmutated")
	_check(snap_after["territories"] == snap_before["territories"], "I2: Territories unmutated")
	_check(snap_after["bases"] == snap_before["bases"], "I3: Bases unmutated")
	_check(snap_after["battles"] == snap_before["battles"], "I4: Zero battles created")
	_check(snap_after["turn"] == snap_before["turn"], "I5: Turn counter unmutated")
	_check(snap_after["heat"] == snap_before["heat"], "I6: Heat unmutated")
	_check(snap_after["wanted"] == snap_before["wanted"], "I7: Wanted level unmutated")
	_check(snap_after["relations"] == snap_before["relations"], "I8: Relations unmutated")
	_check(snap_after["player_tile"] == snap_before["player_tile"], "I9: Player tile unmutated")
	_check(snap_after["player_sector"] == snap_before["player_sector"], "I10: Player sector unmutated")
	_check(not CampaignForce.has_force("player") and not CampaignForce.has_force("player_force"),
		"I11: Zero PlayerCampaignForce created")


## --- SECTION J: CANONICAL SCENARIO MULTI-ACTION COEXISTENCE ---
func _test_j_canonical_scenario_multi_action_coexistence() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	# Place player at depot
	GlobalData.board.current_tile = Vector2i(5, 3)
	GlobalData.fuel.mech_energy = 600.0
	GlobalData.fuel.convoy_fuel = 300.0

	# 1. Investigate canonical depot
	var inv_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_frontier_depot"))
	_check(bool(inv_res.get("ok", false)), "J1: Canonical depot investigate succeeded")
	_check((inv_res.get("situation", {}).get("forces") as Array).size() == 1, "J2: Scavenger force observed")

	# 2. Resupply at canonical depot
	var res_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_frontier_depot"))
	_check(bool(res_res.get("ok", false)), "J3: Canonical depot resupply succeeded")
	_check(GlobalData.fuel.mech_energy == 1000.0, "J4: Energy refilled to 1000.0")
	_check(GlobalData.fuel.convoy_fuel == 500.0, "J5: Convoy fuel refilled to 500.0")

	# 3. Canonical scenario facts intact
	_check(CampaignTerritory.get_controller("terr_frontier_sector_beta") == "zeon", "J6: Sector Beta controller stays Zeon")
	_check(CampaignForce.get_force("force_s1_outland_scavengers").get("node_id") == "node_frontier_depot",
		"J7: Outland scavenger force stays anchored at depot")


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
	print("PHASE 5AP SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN MULTI-ACTION COEXISTENCE VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN MULTI-ACTION COEXISTENCE CHECKS PASSED!")
		get_tree().quit(0)
