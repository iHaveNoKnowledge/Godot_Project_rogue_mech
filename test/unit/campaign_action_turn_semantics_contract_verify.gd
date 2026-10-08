extends Node

## ---------------------------------------------------------------------------
## PHASE 5AQ: CAMPAIGN ACTION / TURN SEMANTICS CONTRACT VERIFICATION
##
## Proves the architectural separation between Action Handlers, Player Dispatch,
## Movement, and CampaignTurnExecutive.
##
## Contracts Verified:
##   1. Turn Authority: CampaignTurnExecutive is the sole authority for turn progression.
##   2. Dispatch Boundary: CampaignPlayerDispatch routes intents and never advances turn.
##   3. Action Domain Handlers: Investigate and Resupply execute domain logic without
##      advancing or mutating campaign turns.
##   4. Movement Systems: Strategic player and force movements mutate position/topology
##      without advancing campaign turns.
##   5. Read-Only Actions: Inspection / Investigation cause zero state and zero turn mutation.
##   6. No Double / Implicit Turn Advancement: Actions alone never tick turn; explicit
##      turn progression ticks exactly once per execution.
##   7. Multi-Action & Turn Sequences: Combinations of [Action -> Turn -> Action]
##      preserve temporal integrity and produce deterministic turn counter values.
##   8. Future Action Pluggability: Generic routing allows future actions (trade, capture,
##      attack, defend) to register without modifying turn advancement logic.
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")

var _passed_count: int = 0
var _failed_count: int = 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Action / Turn Semantics Contract verification (Phase 5AQ)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("ACTION_TURN_SEMANTICS OK: %s" % test_name)
	else:
		_failed_count += 1
		printerr("ACTION_TURN_SEMANTICS FAIL: %s" % test_name)


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE 5AQ SUMMARY: Passed: %d, Failed: %d" % [_passed_count, _failed_count])
	print("----------------------------------------------------------------------")
	if _failed_count == 0:
		print("ALL CAMPAIGN ACTION / TURN SEMANTICS CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
	else:
		printerr("CAMPAIGN ACTION / TURN SEMANTICS CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()


func _run_all_tests() -> void:
	_test_a_sole_turn_authority()
	_test_b_dispatch_zero_turn_advancement()
	_test_c_action_handlers_zero_turn_advancement()
	_test_d_movement_zero_turn_advancement()
	_test_e_read_only_preservation()
	_test_f_no_double_no_implicit_advance()
	_test_g_interleaved_action_turn_sequence()
	_test_h_future_action_turn_boundary_compatibility()


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


## --- SECTION A: SOLE TURN AUTHORITY (CampaignTurnExecutive) ---
func _test_a_sole_turn_authority() -> void:
	_reset_campaign_runtime()

	_check(CampaignTurnExecutive.get_turn() == 0, "A1: Initial campaign turn is 0")

	var receipt1 := CampaignTurnExecutive.advance_campaign_turn("test_advance")
	_check(bool(receipt1.get("ok", false)), "A2: Turn advance returns ok=true")
	_check(CampaignTurnExecutive.get_turn() == 1, "A3: Turn counter incremented to 1")
	_check(int(receipt1.get("turn", 0)) == 1, "A4: Receipt reports turn 1")

	var receipt2 := CampaignTurnExecutive.advance_campaign_turn("test_advance_2")
	_check(CampaignTurnExecutive.get_turn() == 2, "A5: Second turn advance increments to 2")
	_check(int(receipt2.get("turn", 0)) == 2, "A6: Receipt reports turn 2")


## --- SECTION B: DISPATCH ZERO TURN ADVANCEMENT ---
func _test_b_dispatch_zero_turn_advancement() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_alpha")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)

	var turn_before := CampaignTurnExecutive.get_turn()

	# 1. Validation only
	var intent_inv := CampaignPlayerDispatch.create_intent("investigate", "node_alpha")
	var val_res := CampaignPlayerDispatch.validate_intent(intent_inv)
	_check(bool(val_res.get("ok", false)), "B1: Intent validation succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "B2: Validation causes 0 turn advance")

	# 2. Unknown action dispatch
	var intent_unk := CampaignPlayerDispatch.create_intent("unknown_action_xyz", "node_alpha")
	var unk_res := CampaignPlayerDispatch.dispatch_intent(intent_unk)
	_check(not bool(unk_res.get("ok", true)), "B3: Unknown action dispatch rejected")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "B4: Unknown action causes 0 turn advance")

	# 3. Unimplemented action dispatch
	var intent_unimpl := CampaignPlayerDispatch.create_intent("attack", "node_alpha")
	var unimpl_res := CampaignPlayerDispatch.dispatch_intent(intent_unimpl)
	_check(not bool(unimpl_res.get("ok", true)), "B5: Unimplemented action dispatch rejected")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "B6: Unimplemented action causes 0 turn advance")

	# 4. Unknown node dispatch
	var intent_bad_node := CampaignPlayerDispatch.create_intent("investigate", "nonexistent_node")
	var bad_node_res := CampaignPlayerDispatch.dispatch_intent(intent_bad_node)
	_check(not bool(bad_node_res.get("ok", true)), "B7: Bad node dispatch rejected")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "B8: Bad node dispatch causes 0 turn advance")


## --- SECTION C: ACTION HANDLERS ZERO TURN ADVANCEMENT ---
func _test_c_action_handlers_zero_turn_advancement() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "fuel_depot", "node_depot")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 3)
	GlobalData.fuel.mech_energy = 400.0
	GlobalData.fuel.convoy_fuel = 200.0

	var turn_start := CampaignTurnExecutive.get_turn()

	# 1. Investigate direct call
	var intent_inv := CampaignPlayerDispatch.create_intent("investigate", "node_depot")
	var inv_direct := CampaignInvestigateAction.handle_investigate(intent_inv)
	_check(bool(inv_direct.get("ok", false)), "C1: Direct investigate succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "C2: Direct investigate causes 0 turn advance")

	# 2. Investigate via dispatch
	var inv_dispatched := CampaignPlayerDispatch.dispatch_intent(intent_inv)
	_check(bool(inv_dispatched.get("ok", false)), "C3: Dispatched investigate succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "C4: Dispatched investigate causes 0 turn advance")

	# 3. Resupply direct call
	var intent_res := CampaignPlayerDispatch.create_intent("resupply", "node_depot")
	var res_direct := CampaignResupplyAction.handle_resupply(intent_res)
	_check(bool(res_direct.get("ok", false)), "C5: Direct resupply succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "C6: Direct resupply causes 0 turn advance")

	# 4. Resupply via dispatch (after spending some fuel)
	GlobalData.fuel.mech_energy = 500.0
	var res_dispatched := CampaignPlayerDispatch.dispatch_intent(intent_res)
	_check(bool(res_dispatched.get("ok", false)), "C7: Dispatched resupply succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "C8: Dispatched resupply causes 0 turn advance")


## --- SECTION D: MOVEMENT ZERO TURN ADVANCEMENT ---
func _test_d_movement_zero_turn_advancement() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "start", "node_start")
	CampaignNodeRegistry.register_node(1, Vector2i(1, 0), "city", "node_city")
	CampaignNodeRegistry.register_route("node_start", "node_city")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(0, 0)

	var turn_start := CampaignTurnExecutive.get_turn()

	# 1. Player movement validation
	var can_move := CampaignPlayerMovement.can_move_to_node("node_city")
	_check(bool(can_move.get("ok", false)), "D1: Player can_move_to_node valid")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "D2: Movement query causes 0 turn advance")

	# 2. Player movement execution
	var move_res := CampaignPlayerMovement.move_player_to_node("node_city")
	_check(bool(move_res.get("ok", false)), "D3: Player movement succeeds")
	_check(CampaignPlayerMovement.get_current_node_id() == "node_city", "D4: Player reached destination")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "D5: Player movement causes 0 turn advance")

	# 3. Force movement
	CampaignForce.register_force("force_test", "PATROL", "", "node_city", "", 1, 100)
	var force_move := CampaignForceMovement.move_force("force_test", "node_start")
	_check(bool(force_move.get("ok", false)), "D6: Force movement succeeds")
	_check(str(CampaignForce.get_force("force_test").get("node_id", "")) == "node_start", "D7: Force at destination")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "D8: Force movement causes 0 turn advance")


## --- SECTION E: READ-ONLY PRESERVATION ---
func _test_e_read_only_preservation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse", "node_safe")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(4, 4)

	var turn_before := CampaignTurnExecutive.get_turn()
	var energy_before := GlobalData.fuel.mech_energy
	var pos_before := GlobalData.board.current_tile

	# Node situation inspection
	var insp := CampaignNodeInspection.inspect_node("node_safe")
	_check(bool(insp.get("ok", false)), "E1: Node inspection succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "E2: Inspection does not advance turn")
	_check(is_equal_approx(GlobalData.fuel.mech_energy, energy_before), "E3: Inspection preserves energy")
	_check(GlobalData.board.current_tile == pos_before, "E4: Inspection preserves position")

	# Investigate action
	var inv := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_safe"))
	_check(bool(inv.get("ok", false)), "E5: Investigate dispatch succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "E6: Investigate does not advance turn")
	_check(is_equal_approx(GlobalData.fuel.mech_energy, energy_before), "E7: Investigate preserves energy")
	_check(GlobalData.board.current_tile == pos_before, "E8: Investigate preserves position")


## --- SECTION F: NO DOUBLE & NO IMPLICIT ADVANCE ---
func _test_f_no_double_no_implicit_advance() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "supply_depot", "node_sup")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)
	GlobalData.fuel.mech_energy = 300.0

	# 10 player actions in a row
	for i in range(5):
		CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_sup"))
	_check(CampaignTurnExecutive.get_turn() == 0, "F1: 5 investigate dispatches result in exactly 0 turn advances")

	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_sup"))
	_check(CampaignTurnExecutive.get_turn() == 0, "F2: Resupply dispatch results in exactly 0 turn advances")

	# Explicit turn advance (exactly 1)
	var rec := CampaignTurnExecutive.advance_campaign_turn("player_turn_completed")
	_check(bool(rec.get("ok", false)), "F3: Explicit turn advancement succeeded")
	_check(CampaignTurnExecutive.get_turn() == 1, "F4: Exactly 1 turn advanced (turn=1)")

	# Calling advance again
	var rec2 := CampaignTurnExecutive.advance_campaign_turn("player_turn_completed_2")
	_check(CampaignTurnExecutive.get_turn() == 2, "F5: Exactly 2 turns advanced (turn=2)")


## --- SECTION G: INTERLEAVED ACTION & TURN SEQUENCE ---
func _test_g_interleaved_action_turn_sequence() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "start", "node_n1")
	CampaignNodeRegistry.register_node(1, Vector2i(1, 0), "fuel_depot", "node_n2")
	CampaignNodeRegistry.register_route("node_n1", "node_n2")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.fuel.mech_energy = 200.0

	_check(CampaignTurnExecutive.get_turn() == 0, "G1: Starts at Turn 0")

	# Step 1: Investigate node_n1
	var inv1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_n1"))
	_check(bool(inv1.get("ok", false)), "G2: Turn 0: Investigate node_n1 ok")
	_check(CampaignTurnExecutive.get_turn() == 0, "G3: Still Turn 0 after investigate")

	# Step 2: Move to node_n2
	var mov := CampaignPlayerMovement.move_player_to_node("node_n2")
	_check(bool(mov.get("ok", false)), "G4: Turn 0: Move to node_n2 ok")
	_check(CampaignTurnExecutive.get_turn() == 0, "G5: Still Turn 0 after move")

	# Step 3: Resupply at node_n2
	var res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_n2"))
	_check(bool(res.get("ok", false)), "G6: Turn 0: Resupply at node_n2 ok")
	_check(is_equal_approx(GlobalData.fuel.mech_energy, 1000.0), "G7: Fuel restored to 1000.0")
	_check(CampaignTurnExecutive.get_turn() == 0, "G8: Still Turn 0 after resupply")

	# Step 4: Advance Turn 0 -> Turn 1
	CampaignTurnExecutive.advance_campaign_turn("end_turn_1")
	_check(CampaignTurnExecutive.get_turn() == 1, "G9: Advanced to Turn 1")

	# Step 5: Investigate at Turn 1
	var inv2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_n2"))
	_check(bool(inv2.get("ok", false)), "G10: Turn 1: Investigate node_n2 ok")
	_check(CampaignTurnExecutive.get_turn() == 1, "G11: Still Turn 1 after investigate")

	# Step 6: Advance Turn 1 -> Turn 2
	CampaignTurnExecutive.advance_campaign_turn("end_turn_2")
	_check(CampaignTurnExecutive.get_turn() == 2, "G12: Advanced to Turn 2")


## --- SECTION H: FUTURE ACTION TURN BOUNDARY COMPATIBILITY ---
func _test_h_future_action_turn_boundary_compatibility() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "city", "node_capitol")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(5, 5)

	var turn_start := CampaignTurnExecutive.get_turn()

	# Simulate registering future domain handlers without modifying CampaignTurnExecutive
	var trade_executed := {"called": false}
	var mock_trade_handler := func(intent: Dictionary) -> Dictionary:
		trade_executed["called"] = true
		return {"ok": true, "reason": "trade_resolved", "action_id": "trade", "node_id": intent.get("node_id")}

	var capture_executed := {"called": false}
	var mock_capture_handler := func(intent: Dictionary) -> Dictionary:
		capture_executed["called"] = true
		return {"ok": true, "reason": "capture_resolved", "action_id": "capture", "node_id": intent.get("node_id")}

	CampaignPlayerDispatch.register_handler("trade", mock_trade_handler)
	CampaignPlayerDispatch.register_handler("capture", mock_capture_handler)

	# Dispatch future actions
	var trade_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_capitol"))
	_check(bool(trade_res.get("ok", false)), "H1: Future trade action dispatches cleanly")
	_check(trade_executed["called"], "H2: Trade handler was invoked")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "H3: Trade handler causes 0 turn advance")

	var cap_res := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("capture", "node_capitol"))
	_check(bool(cap_res.get("ok", false)), "H4: Future capture action dispatches cleanly")
	_check(capture_executed["called"], "H5: Capture handler was invoked")
	_check(CampaignTurnExecutive.get_turn() == turn_start, "H6: Capture handler causes 0 turn advance")
	# Clean up mock handlers
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
