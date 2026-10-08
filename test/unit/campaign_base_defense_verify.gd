class_name CampaignBaseDefenseVerify
extends Node

## ---------------------------------------------------------------------------
## 5AV — BASE DEFENSE / BASE ATTACK / INTERVENTION BOUNDARY VERIFICATION
##
## Verifies:
##   TEST A: Base attack creates/links active CampaignBattle.
##   TEST B: Ownership isolation (Base controller & Territory controller unchanged).
##   TEST C: Battle identity (attacker force, defender garrison, battle ID coherence).
##   TEST D: No instant capture or destruction (Base remains ACTIVE and owned).
##   TEST E: Player intervention eligibility & execution (Player present at base node).
##   TEST F: Remote player intervention rejection (player_not_at_node).
##   TEST G: Inactive battle intervention rejection (battle_not_active).
##   TEST H: Attacker precondition validation (unknown base, remote force, friendly attacker).
##   TEST I: Turn isolation (Zero turn advancement across all attack and intervention flows).
##   TEST J: Atomic failure invariance (Zero state mutation across all failure paths).
##   TEST K: Compatibility with 5AT Capture and 5AU Attack actions.
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignBaseDefense = preload("res://scripts/systems/campaign_base_defense.gd")
const CampaignAttackAction = preload("res://scripts/systems/campaign_attack_action.gd")
const CampaignCaptureAction = preload("res://scripts/systems/campaign_capture_action.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0


func _ready() -> void:
	print("--- BEGIN CAMPAIGN BASE DEFENSE & INTERVENTION VERIFY (Phase 5AV) ---")
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
		if GlobalData.currency != null:
			GlobalData.currency.credits = 500
			GlobalData.currency.scrap = 50
			GlobalData.currency.data_cores = 3
		if GlobalData.fuel != null:
			GlobalData.fuel.mech_energy = 80.0
			GlobalData.fuel.mech_max_energy = 100.0
			GlobalData.fuel.convoy_fuel = 60.0
			GlobalData.fuel.convoy_max_fuel = 80.0
		GlobalData.fuel_inventory.clear()
		GlobalData.fuel_inventory["fuel_canister"] = 2


func _take_state_snapshot() -> Dictionary:
	return {
		"credits": GlobalData.currency.credits if GlobalData and GlobalData.currency else 0,
		"scrap": GlobalData.currency.scrap if GlobalData and GlobalData.currency else 0,
		"data_cores": GlobalData.currency.data_cores if GlobalData and GlobalData.currency else 0,
		"fuel_inventory": GlobalData.fuel_inventory.duplicate(true) if GlobalData else {},
		"mech_energy": GlobalData.fuel.mech_energy if GlobalData and GlobalData.fuel else 0.0,
		"convoy_fuel": GlobalData.fuel.convoy_fuel if GlobalData and GlobalData.fuel else 0.0,
		"current_tile": GlobalData.board.current_tile if GlobalData and GlobalData.board else Vector2i(-1, -1),
		"current_sector": GlobalData.board.current_sector if GlobalData and GlobalData.board else -1,
		"turn": CampaignTurnExecutive.get_turn(),
	}


func _run_all_tests() -> void:
	_test_base_attack_creates_battle()
	_test_ownership_isolation()
	_test_battle_identity()
	_test_no_instant_capture()
	_test_player_intervention_eligibility_and_execution()
	_test_remote_player_intervention_rejection()
	_test_inactive_battle_intervention_rejection()
	_test_attacker_precondition_validation()
	_test_turn_isolation()
	_test_atomic_failure_invariance()
	_test_compatibility_5at_5au()


# ---------------------------------------------------------------------------
# TEST A: Base Attack Creates Active CampaignBattle
# ---------------------------------------------------------------------------
func _test_base_attack_creates_battle() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "enemy_base")
	var terr_id := CampaignTerritory.register_territory("terr_fed_outpost", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_fed_outpost", node_id, "OUTPOST", "federation", terr_id)

	var force_id := CampaignForce.register_force("force_zeon_raider", "PATROL", "zeon", node_id)

	var result := CampaignBaseDefense.start_base_attack(base_id, force_id)
	_assert_true(bool(result.get("ok", false)), "TEST A: Base attack succeeds")
	_assert_eq(str(result.get("reason", "")), "base_attack_started", "TEST A: Reason is base_attack_started")

	var battle_id := str(result.get("battle_id", ""))
	_assert_true(CampaignBattle.has_battle(battle_id), "TEST A: Battle exists in CampaignBattle")
	_assert_true(CampaignBattle.is_active(battle_id), "TEST A: Battle is in ACTIVE state")
	_assert_true(CampaignBaseDefense.is_base_under_attack(base_id), "TEST A: Base is reported as under attack")


# ---------------------------------------------------------------------------
# TEST B: Ownership Isolation
# ---------------------------------------------------------------------------
func _test_ownership_isolation() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_defense_iso", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_defense_iso", node_id, "OUTPOST", "federation", terr_id)

	var force_id := CampaignForce.register_force("force_zeon_iso", "PATROL", "zeon", node_id)

	var base_before := CampaignBase.get_base(base_id)
	var terr_before := CampaignTerritory.get_controller(terr_id)

	var result := CampaignBaseDefense.start_base_attack(base_id, force_id)
	_assert_true(bool(result.get("ok", false)), "TEST B: Base attack initiated")

	var base_after := CampaignBase.get_base(base_id)
	var terr_after := CampaignTerritory.get_controller(terr_id)

	_assert_eq(str(base_after.get("controller", "")), str(base_before.get("controller", "")), "TEST B: Base controller unchanged")
	_assert_eq(terr_after, terr_before, "TEST B: Territory controller unchanged")
	_assert_eq(str(base_after.get("controller", "")), "federation", "TEST B: Base controller is still federation")


# ---------------------------------------------------------------------------
# TEST C: Battle Identity
# ---------------------------------------------------------------------------
func _test_battle_identity() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "enemy_base")
	var terr_id := CampaignTerritory.register_territory("terr_c", [node_id])
	CampaignTerritory.set_controlled(terr_id, "zeon")
	var base_id := CampaignBase.register_base("base_zeon_c", node_id, "OUTPOST", "zeon", terr_id)

	var force_id := CampaignForce.register_force("force_outland_invader", "PATROL", "outland", node_id)

	var result := CampaignBaseDefense.start_base_attack(base_id, force_id)
	_assert_true(bool(result.get("ok", false)), "TEST C: Attack initiated")

	var battle_id := str(result.get("battle_id", ""))
	var battle := CampaignBattle.get_battle(battle_id)

	_assert_eq(str(battle.get("node_id", "")), node_id, "TEST C: Battle node ID matches base node")
	var parts: Array = battle.get("participants", [])
	_assert_true(parts.has(force_id), "TEST C: Attacker force is participant")
	_assert_true(parts.has("force_garrison_" + node_id), "TEST C: Defender garrison is participant")


# ---------------------------------------------------------------------------
# TEST D: No Instant Capture or Destruction
# ---------------------------------------------------------------------------
func _test_no_instant_capture() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "enemy_base")
	var terr_id := CampaignTerritory.register_territory("terr_d", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_d", node_id, "OUTPOST", "federation", terr_id)

	var force_id := CampaignForce.register_force("force_attacker_d", "PATROL", "zeon", node_id)

	CampaignBaseDefense.start_base_attack(base_id, force_id)

	_assert_eq(CampaignBase.get_state(base_id), CampaignBase.BaseState.ACTIVE, "TEST D: Base remains in ACTIVE state")
	_assert_eq(str(CampaignBase.get_base(base_id).get("controller", "")), "federation", "TEST D: Base not captured")


# ---------------------------------------------------------------------------
# TEST E: Player Intervention Eligibility & Execution
# ---------------------------------------------------------------------------
func _test_player_intervention_eligibility_and_execution() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_intervene", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_intervene", node_id, "OUTPOST", "federation", terr_id)

	var force_id := CampaignForce.register_force("force_zeon_assault", "PATROL", "zeon", node_id)

	var attack_res := CampaignBaseDefense.start_base_attack(base_id, force_id)
	var battle_id := str(attack_res.get("battle_id", ""))

	# Position player at the base
	GlobalData.board.current_tile = Vector2i(7, 7)

	var can_res := CampaignBaseDefense.can_intervene(battle_id)
	_assert_true(bool(can_res.get("ok", false)), "TEST E: Player can intervene when present")
	_assert_eq(str(can_res.get("reason", "")), "intervention_eligible", "TEST E: Reason is intervention_eligible")

	var int_res := CampaignBaseDefense.intervene(battle_id)
	_assert_true(bool(int_res.get("ok", false)), "TEST E: Intervention starts cleanly")
	_assert_eq(str(int_res.get("reason", "")), "intervention_started", "TEST E: Reason is intervention_started")

	# Battle MUST remain active (not auto-resolved)
	_assert_true(CampaignBattle.is_active(battle_id), "TEST E: Battle remains ACTIVE during intervention")
	_assert_true(CampaignBattle.get_session_ref(battle_id) != "", "TEST E: Session reference attached to battle")


# ---------------------------------------------------------------------------
# TEST F: Remote Player Intervention Rejection
# ---------------------------------------------------------------------------
func _test_remote_player_intervention_rejection() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(8, 8), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_remote_int", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_remote_int", node_id, "OUTPOST", "federation", terr_id)

	var force_id := CampaignForce.register_force("force_zeon_remote", "PATROL", "zeon", node_id)

	var attack_res := CampaignBaseDefense.start_base_attack(base_id, force_id)
	var battle_id := str(attack_res.get("battle_id", ""))

	# Player is at (0, 0)
	GlobalData.board.current_tile = Vector2i(0, 0)

	var can_res := CampaignBaseDefense.can_intervene(battle_id)
	_assert_false(bool(can_res.get("ok", false)), "TEST F: Remote intervention rejected")
	_assert_eq(str(can_res.get("reason", "")), "player_not_at_node", "TEST F: Reason is player_not_at_node")

	var int_res := CampaignBaseDefense.intervene(battle_id)
	_assert_false(bool(int_res.get("ok", false)), "TEST F: Remote execute rejected")
	_assert_eq(str(int_res.get("reason", "")), "player_not_at_node", "TEST F: Reason is player_not_at_node")


# ---------------------------------------------------------------------------
# TEST G: Inactive Battle Intervention Rejection
# ---------------------------------------------------------------------------
func _test_inactive_battle_intervention_rejection() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(6, 6), "safehouse")
	GlobalData.board.current_tile = Vector2i(6, 6)

	var force_a := CampaignForce.register_force("force_res_a", "PATROL", "zeon", node_id)
	var force_b := CampaignForce.register_force("force_res_b", "PATROL", "federation", node_id)

	var battle_id := CampaignBattle.register_battle("battle_resolved_test", node_id, [force_a, force_b])
	CampaignBattle.prepare_launch(battle_id)
	CampaignBattle.resolve_battle(battle_id)

	var can_res := CampaignBaseDefense.can_intervene(battle_id)
	_assert_false(bool(can_res.get("ok", false)), "TEST G: Resolved battle cannot be intervened")
	_assert_eq(str(can_res.get("reason", "")), "battle_not_active", "TEST G: Reason is battle_not_active")


# ---------------------------------------------------------------------------
# TEST H: Attacker Precondition Validation
# ---------------------------------------------------------------------------
func _test_attacker_precondition_validation() -> void:
	_setup_clean_campaign_environment()

	var node_a := CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse")
	var node_b := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "safehouse")

	var terr_id := CampaignTerritory.register_territory("terr_h", [node_a])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_h", node_a, "OUTPOST", "federation", terr_id)

	# 1. Unknown base
	var r1 := CampaignBaseDefense.start_base_attack("base_nonexistent", "force_xyz")
	_assert_false(bool(r1.get("ok", false)), "TEST H1: Unknown base rejected")
	_assert_eq(str(r1.get("reason", "")), "unknown_base", "TEST H1: Reason is unknown_base")

	# 2. Unknown attacker force
	var r2 := CampaignBaseDefense.start_base_attack(base_id, "force_nonexistent")
	_assert_false(bool(r2.get("ok", false)), "TEST H2: Unknown attacker force rejected")
	_assert_eq(str(r2.get("reason", "")), "unknown_attacker_force", "TEST H2: Reason is unknown_attacker_force")

	# 3. Attacker at different node
	var force_remote := CampaignForce.register_force("force_remote_h", "PATROL", "zeon", node_b)
	var r3 := CampaignBaseDefense.start_base_attack(base_id, force_remote)
	_assert_false(bool(r3.get("ok", false)), "TEST H3: Remote force rejected")
	_assert_eq(str(r3.get("reason", "")), "attacker_not_at_base_node", "TEST H3: Reason is attacker_not_at_base_node")

	# 4. Friendly attacker (same faction as base)
	var force_friendly := CampaignForce.register_force("force_friendly_h", "PATROL", "federation", node_a)
	var r4 := CampaignBaseDefense.start_base_attack(base_id, force_friendly)
	_assert_false(bool(r4.get("ok", false)), "TEST H4: Friendly attacker rejected")
	_assert_eq(str(r4.get("reason", "")), "attacker_not_hostile", "TEST H4: Reason is attacker_not_hostile")


# ---------------------------------------------------------------------------
# TEST I: Turn Isolation
# ---------------------------------------------------------------------------
func _test_turn_isolation() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_turn_i", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_turn_i", node_id, "OUTPOST", "federation", terr_id)
	var force_id := CampaignForce.register_force("force_zeon_turn", "PATROL", "zeon", node_id)
	GlobalData.board.current_tile = Vector2i(3, 3)

	var turn_before := CampaignTurnExecutive.get_turn()

	var r_attack := CampaignBaseDefense.start_base_attack(base_id, force_id)
	_assert_true(bool(r_attack.get("ok", false)), "TEST I: Attack starts")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "TEST I: Turn delta is 0 after attack start")

	var battle_id := str(r_attack.get("battle_id", ""))
	var r_int := CampaignBaseDefense.intervene(battle_id)
	_assert_true(bool(r_int.get("ok", false)), "TEST I: Intervention starts")
	_assert_eq(CampaignTurnExecutive.get_turn(), turn_before, "TEST I: Turn delta is 0 after intervention")


# ---------------------------------------------------------------------------
# TEST J: Atomic Failure Invariance
# ---------------------------------------------------------------------------
func _test_atomic_failure_invariance() -> void:
	_setup_clean_campaign_environment()

	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "safehouse")
	var terr_id := CampaignTerritory.register_territory("terr_atom_j", [node_id])
	CampaignTerritory.set_controlled(terr_id, "federation")
	var base_id := CampaignBase.register_base("base_atom_j", node_id, "OUTPOST", "federation", terr_id)

	var snapshot_before := _take_state_snapshot()

	var r := CampaignBaseDefense.start_base_attack(base_id, "force_nonexistent")
	_assert_false(bool(r.get("ok", false)), "TEST J: Invalid attack fails")

	var snapshot_after := _take_state_snapshot()
	_assert_eq(snapshot_after, snapshot_before, "TEST J: State snapshot completely intact")


# ---------------------------------------------------------------------------
# TEST K: Compatibility with 5AT Capture and 5AU Attack Actions
# ---------------------------------------------------------------------------
func _test_compatibility_5at_5au() -> void:
	_setup_clean_campaign_environment()

	# 1. 5AU Player Attack against enemy base
	var enemy_base_nid := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "enemy_base")
	var terr_zeon := CampaignTerritory.register_territory("terr_k_zeon", [enemy_base_nid])
	CampaignTerritory.set_controlled(terr_zeon, "zeon")
	CampaignBase.register_base("base_k_zeon", enemy_base_nid, "OUTPOST", "zeon", terr_zeon)

	GlobalData.board.current_tile = Vector2i(5, 5)

	var atk_intent := CampaignPlayerDispatch.create_intent("attack", enemy_base_nid)
	var atk_res := CampaignPlayerDispatch.dispatch_intent(atk_intent)
	_assert_true(bool(atk_res.get("ok", false)), "TEST K: 5AU Player Attack succeeds")

	# 2. 5AT Capture
	var cap_intent := CampaignPlayerDispatch.create_intent("capture", enemy_base_nid)
	var cap_res := CampaignPlayerDispatch.dispatch_intent(cap_intent)
	_assert_true(bool(cap_res.get("ok", false)), "TEST K: 5AT Capture succeeds")
	_assert_eq(str(CampaignBase.get_base("base_k_zeon").get("controller", "")), "federation", "TEST K: Base captured to federation")

	# 3. 5AV Base Defense when Zeon counter-attacks newly captured base
	var counter_force := CampaignForce.register_force("force_zeon_counter", "PATROL", "zeon", enemy_base_nid)
	var def_res := CampaignBaseDefense.start_base_attack("base_k_zeon", counter_force)
	_assert_true(bool(def_res.get("ok", false)), "TEST K: 5AV Base Defense battle starts against counter-attack")

	var def_battle_id := str(def_res.get("battle_id", ""))
	var int_res := CampaignBaseDefense.intervene(def_battle_id)
	_assert_true(bool(int_res.get("ok", false)), "TEST K: Player intervenes to defend base")


func _print_summary() -> void:
	print("---------------------------------------------------------------------------")
	print("CAMPAIGN BASE DEFENSE & INTERVENTION VERIFY (Phase 5AV) RESULTS:")
	print("  TOTAL ASSERTIONS : %d" % _total_assertions)
	print("  PASSED           : %d" % _passed_assertions)
	print("  FAILED           : %d" % _failed_assertions)
	print("---------------------------------------------------------------------------")
	if _failed_assertions == 0:
		print("PASSED: Phase 5AV Base Defense / Intervention Boundary Contract strictly satisfied.")
	else:
		printerr("FAILED: Phase 5AV Base Defense / Intervention Boundary Contract has %d failures!" % _failed_assertions)
	get_tree().quit(0 if _failed_assertions == 0 else 1)
