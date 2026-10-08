class_name CampaignWorldFoundationVerify
extends Node

## ---------------------------------------------------------------------------
## 5AW — CAMPAIGN WORLD STATE / NODE-ROUTE-TIME FOUNDATION VERIFICATION
##
## Verifies:
##   TEST 1: Node identity determinism & registry authority.
##   TEST 2: Route model existence, undirected canonical IDs & traversal validation.
##   TEST 3: Player location authority (Single physical truth -> derived strategic node).
##   TEST 4: Turn authority isolation (CampaignTurnExecutive sole time authority).
##   TEST 5: Node / Base / Territory structural separation.
##   TEST 6: Force location & movement isolation.
##   TEST 7: Battle location model & lifecycle isolation.
##   TEST 8: Base Defense & Intervention boundary compatibility (5AV).
##   TEST 9: Attack action boundary compatibility (5AU).
##   TEST 10: Capture action ownership authority compatibility (5AT).
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignBaseDefense = preload("res://scripts/systems/campaign_base_defense.gd")
const CampaignAttackAction = preload("res://scripts/systems/campaign_attack_action.gd")
const CampaignCaptureAction = preload("res://scripts/systems/campaign_capture_action.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignForceMovement = preload("res://scripts/systems/campaign_force_movement.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0


func _ready() -> void:
	print("--- BEGIN CAMPAIGN WORLD FOUNDATION AUDIT VERIFY (Phase 5AW) ---")
	_run_all_tests()
	_print_summary()


func _assert_true(condition: bool, message: String) -> void:
	_total_assertions += 1
	if condition:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: " + message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_true(not condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_total_assertions += 1
	if actual == expected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("FAIL: %s | Expected: %s, Got: %s" % [message, str(expected), str(actual)])


func _setup_clean_campaign_environment() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()

	if GlobalData != null:
		if GlobalData.board != null:
			GlobalData.board.current_sector = 1
			GlobalData.board.current_tile = Vector2i(0, 0)


func _run_all_tests() -> void:
	_test_node_identity_determinism()
	_test_route_model_and_traversal()
	_test_player_location_authority()
	_test_turn_authority_isolation()
	_test_node_base_territory_separation()
	_test_force_location_and_movement()
	_test_battle_location_model()
	_test_base_defense_intervention_compatibility()
	_test_attack_action_compatibility()
	_test_capture_action_compatibility()


# ---------------------------------------------------------------------------
# TEST 1: Node Identity Determinism
# ---------------------------------------------------------------------------
func _test_node_identity_determinism() -> void:
	_setup_clean_campaign_environment()

	var nid1 := CampaignNodeRegistry.register_node(1, Vector2i(3, 4), "safehouse")
	var expected_id := CampaignNodeRegistry.make_node_id(1, "safehouse", Vector2i(3, 4))

	_assert_eq(nid1, expected_id, "T1: Generated node ID matches deterministic pattern")
	_assert_true(CampaignNodeRegistry.has_node(nid1), "T1: Registry contains node")

	var lookup := CampaignNodeRegistry.get_node_at(1, Vector2i(3, 4))
	_assert_eq(str(lookup.get("id", "")), nid1, "T1: Lookup by tile returns correct node")
	_assert_eq(str(lookup.get("node_type", "")), "SAFEHOUSE", "T1: Node type matches")


# ---------------------------------------------------------------------------
# TEST 2: Route Model and Traversal
# ---------------------------------------------------------------------------
func _test_route_model_and_traversal() -> void:
	_setup_clean_campaign_environment()

	var na := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse")
	var nb := CampaignNodeRegistry.register_node(1, Vector2i(2, 1), "supply_depot")

	var route_id := CampaignNodeRegistry.register_route(na, nb)
	_assert_true(route_id != "", "T2: Route registered successfully")
	_assert_true(CampaignNodeRegistry.has_route(route_id), "T2: Route exists in registry")

	# Canonical undirected lookup
	var reverse_id := CampaignNodeRegistry.make_route_id(nb, na)
	_assert_eq(reverse_id, route_id, "T2: Route ID is canonical undirected")


# ---------------------------------------------------------------------------
# TEST 3: Player Location Authority
# ---------------------------------------------------------------------------
func _test_player_location_authority() -> void:
	_setup_clean_campaign_environment()

	var n1 := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "safehouse")
	var n2 := CampaignNodeRegistry.register_node(1, Vector2i(5, 6), "city")
	CampaignNodeRegistry.register_route(n1, n2)

	GlobalData.board.current_tile = Vector2i(5, 5)

	_assert_eq(CampaignPlayerMovement.get_current_node_id(), n1, "T3: Strategic node derived from physical tile")
	_assert_true(CampaignNodeInspection.is_player_at_node(n1), "T3: Player confirmed at node N1")
	_assert_false(CampaignNodeInspection.is_player_at_node(n2), "T3: Player not at node N2")

	var move_res := CampaignPlayerMovement.move_player_to_node(n2)
	_assert_true(bool(move_res.get("ok", false)), "T3: Movement succeeds")
	_assert_eq(GlobalData.board.current_tile, Vector2i(5, 6), "T3: Physical tile updated atomically")
	_assert_eq(CampaignPlayerMovement.get_current_node_id(), n2, "T3: New node is N2")


# ---------------------------------------------------------------------------
# TEST 4: Turn Authority Isolation
# ---------------------------------------------------------------------------
func _test_turn_authority_isolation() -> void:
	_setup_clean_campaign_environment()

	_assert_eq(CampaignTurnExecutive.get_turn(), 0, "T4: Initial turn is 0")

	var t1 := CampaignTurnExecutive.advance_campaign_turn("test_advance")
	_assert_true(bool(t1.get("ok", false)), "T4: Turn advance succeeds")
	_assert_eq(CampaignTurnExecutive.get_turn(), 1, "T4: Turn advanced to 1")


# ---------------------------------------------------------------------------
# TEST 5: Node / Base / Territory Structural Separation
# ---------------------------------------------------------------------------
func _test_node_base_territory_separation() -> void:
	_setup_clean_campaign_environment()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "enemy_base")
	var tid := CampaignTerritory.register_territory("terr_sep", [nid])
	CampaignTerritory.set_controlled(tid, "zeon")
	var bid := CampaignBase.register_base("base_sep", nid, "OUTPOST", "zeon", tid)

	# Mutate base controller without mutating territory controller
	CampaignBase.set_controller(bid, "federation")

	_assert_eq(str(CampaignBase.get_base(bid).get("controller", "")), "federation", "T5: Base controller updated")
	_assert_eq(CampaignTerritory.get_controller(tid), "zeon", "T5: Territory controller remained zeon (distinct entity)")
	_assert_true(CampaignNodeRegistry.has_node(nid), "T5: Node topology remains distinct")


# ---------------------------------------------------------------------------
# TEST 6: Force Location and Movement Isolation
# ---------------------------------------------------------------------------
func _test_force_location_and_movement() -> void:
	_setup_clean_campaign_environment()

	var na := CampaignNodeRegistry.register_node(1, Vector2i(1, 2), "safehouse")
	var nb := CampaignNodeRegistry.register_node(1, Vector2i(1, 3), "safehouse")
	CampaignNodeRegistry.register_route(na, nb)

	var fid := CampaignForce.register_force("force_test_mov", "PATROL", "zeon", na)
	_assert_eq(str(CampaignForce.get_force(fid).get("node_id", "")), na, "T6: Force initially at NA")

	var res := CampaignForceMovement.move_force(fid, nb)
	_assert_true(bool(res.get("ok", false)), "T6: Force move succeeds")
	_assert_eq(str(CampaignForce.get_force(fid).get("node_id", "")), nb, "T6: Force now at NB")


# ---------------------------------------------------------------------------
# TEST 7: Battle Location Model
# ---------------------------------------------------------------------------
func _test_battle_location_model() -> void:
	_setup_clean_campaign_environment()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "enemy_base")
	var fa := CampaignForce.register_force("force_bat_a", "PATROL", "zeon", nid)
	var fb := CampaignForce.register_force("force_bat_b", "PATROL", "federation", nid)

	var bid := CampaignBattle.register_battle("battle_loc_test", nid, [fa, fb])
	_assert_true(bid != "", "T7: Battle registered")

	var b := CampaignBattle.get_battle(bid)
	_assert_eq(str(b.get("node_id", "")), nid, "T7: Battle location identified by node_id")


# ---------------------------------------------------------------------------
# TEST 8: Base Defense & Intervention Compatibility (5AV)
# ---------------------------------------------------------------------------
func _test_base_defense_intervention_compatibility() -> void:
	_setup_clean_campaign_environment()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "safehouse")
	var tid := CampaignTerritory.register_territory("terr_def_5aw", [nid])
	CampaignTerritory.set_controlled(tid, "federation")
	var bid := CampaignBase.register_base("base_def_5aw", nid, "OUTPOST", "federation", tid)
	var attacker := CampaignForce.register_force("force_zeon_5aw", "PATROL", "zeon", nid)

	GlobalData.board.current_tile = Vector2i(3, 3)

	var def_res := CampaignBaseDefense.start_base_attack(bid, attacker)
	_assert_true(bool(def_res.get("ok", false)), "T8: Base attack starts")

	var battle_id := str(def_res.get("battle_id", ""))
	var int_res := CampaignBaseDefense.intervene(battle_id)
	_assert_true(bool(int_res.get("ok", false)), "T8: Player intervenes successfully")


# ---------------------------------------------------------------------------
# TEST 9: Attack Action Compatibility (5AU)
# ---------------------------------------------------------------------------
func _test_attack_action_compatibility() -> void:
	_setup_clean_campaign_environment()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "enemy_base")
	var tid := CampaignTerritory.register_territory("terr_atk_5aw", [nid])
	CampaignTerritory.set_controlled(tid, "zeon")
	CampaignBase.register_base("base_atk_5aw", nid, "OUTPOST", "zeon", tid)

	GlobalData.board.current_tile = Vector2i(4, 4)

	var intent := CampaignPlayerDispatch.create_intent("attack", nid)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(receipt.get("ok", false)), "T9: Attack action succeeds")
	_assert_eq(str(receipt.get("reason", "")), "attack_started", "T9: Reason is attack_started")


# ---------------------------------------------------------------------------
# TEST 10: Capture Action Compatibility (5AT)
# ---------------------------------------------------------------------------
func _test_capture_action_compatibility() -> void:
	_setup_clean_campaign_environment()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "enemy_base")
	var tid := CampaignTerritory.register_territory("terr_cap_5aw", [nid])
	CampaignTerritory.set_controlled(tid, "zeon")
	var bid := CampaignBase.register_base("base_cap_5aw", nid, "OUTPOST", "zeon", tid)

	GlobalData.board.current_tile = Vector2i(6, 6)

	var intent := CampaignPlayerDispatch.create_intent("capture", nid)
	var receipt := CampaignPlayerDispatch.dispatch_intent(intent)

	_assert_true(bool(receipt.get("ok", false)), "T10: Capture action succeeds")
	_assert_eq(str(CampaignBase.get_base(bid).get("controller", "")), "federation", "T10: Base controller mutated to federation")
	_assert_eq(CampaignTerritory.get_controller(tid), "federation", "T10: Territory controller mutated to federation")


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("CAMPAIGN WORLD FOUNDATION AUDIT VERIFY (Phase 5AW) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 5AW World State / Node-Route-Time Foundation strictly validated.")
	else:
		printerr("FAILED: Phase 5AW World State Foundation has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
