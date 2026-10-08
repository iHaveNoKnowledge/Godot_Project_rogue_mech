extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN TURN RUNTIME CONTRACT VERIFICATION
## Phase 5AG Contract Verification Suite
##
## Proves the architectural contract:
##   Campaign Turn 0
##         ↓
##   player/campaign action boundary
##         ↓
##   advance campaign turn
##         ↓
##   Turn N + 1
##         ↓
##   future domain hooks
##
## Verified Sections:
##   A. Single authority (CampaignTurnExecutive is sole authoritative turn owner)
##   B. Initial turn (Successful scenario start establishes turn 0)
##   C. Exactly one increment (One advance_campaign_turn call increments once)
##   D. Repeated advancement (N calls produce exactly N increments)
##   E. Failed start isolation (Invalid/missing/unknown scenarios do not advance or leak turn)
##   F. Reset isolation (Fresh start does not inherit previous turn)
##   G. Save/load determinism (Exact restoration without increment)
##   H. No ScenarioDefinition mutation (Authored rules uncoupled from runtime turn)
##   I. No implicit strategic simulation (Forces, territories, bases, battles untouched)
##   J. Player separation (Player is not a CampaignForce)
##   K. Determinism (Identical starting conditions produce identical turns)
##   L. No second turn authority (No duplicate runtime campaign turn storage)
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")
const TurnPanelScript = preload("res://scripts/ui/campaign_turn_panel.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"
const CANONICAL_CATALOG_PATH := "res://resources/data/scenario_definition_catalog.tres"

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Turn Runtime Contract verification (Phase 5AG)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("TURN_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("TURN_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_single_authority()
	_test_b_initial_turn()
	_test_c_exactly_one_increment()
	_test_d_repeated_advancement()
	_test_e_failed_start_isolation()
	_test_f_reset_isolation()
	_test_g_save_load()
	_test_h_no_scenario_definition_mutation()
	_test_i_no_implicit_strategic_simulation()
	_test_j_player_separation()
	_test_k_determinism()
	_test_l_no_second_turn_authority()


func _clear_all_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionEconomySystem.reset()
	GlobalData.current_campaign_scenario_id = ""


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)


func _code_without_comments(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# =============================================================================
# A — SINGLE AUTHORITY
# =============================================================================
func _test_a_single_authority() -> void:
	_clear_all_state()

	# CampaignTurnExecutive owns get_turn() and advance_campaign_turn()
	_check(CampaignTurnExecutive.get_turn() == 0, "A1: CampaignTurnExecutive exposes authoritative turn")
	var exec_inst = CampaignTurnExecutive.new()
	_check(exec_inst.has_method("advance_campaign_turn"), "A2: CampaignTurnExecutive exposes advance_campaign_turn")
	_check(exec_inst.has_method("serialize_turn"), "A3: CampaignTurnExecutive exposes serialize_turn")
	_check(exec_inst.has_method("deserialize_campaign_turn"), "A4: CampaignTurnExecutive exposes deserialize_campaign_turn")

	# UI delegates read strictly to CampaignTurnExecutive
	var panel = TurnPanelScript.new()
	_check(panel.get_current_turn() == CampaignTurnExecutive.get_turn(), "A5: CampaignTurnPanel reads from CampaignTurnExecutive")
	panel.free()

	# CampaignTurnExecutive has zero coupling to CampaignForce, CampaignTerritory, CampaignBase, CampaignBattle
	var source_code := _code_without_comments("res://scripts/systems/campaign_turn_executive.gd")
	_check(not source_code.contains("CampaignForce"), "A6: CampaignTurnExecutive has no CampaignForce coupling")
	_check(not source_code.contains("CampaignTerritory"), "A7: CampaignTurnExecutive has no CampaignTerritory coupling")
	_check(not source_code.contains("CampaignBase"), "A8: CampaignTurnExecutive has no CampaignBase coupling")
	_check(not source_code.contains("CampaignBattle"), "A9: CampaignTurnExecutive has no CampaignBattle coupling")
	_check(not source_code.contains("CampaignNodeRegistry"), "A10: CampaignTurnExecutive has no CampaignNodeRegistry coupling")


# =============================================================================
# B — INITIAL TURN
# =============================================================================
func _test_b_initial_turn() -> void:
	_clear_all_state()

	var res: Dictionary = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res.get("ok", false) == true, "B1: Scenario start succeeded")
	_check(CampaignTurnExecutive.get_turn() == 0, "B2: Authoritative campaign turn is exactly 0 upon successful start")
	_check(not CampaignTurnExecutive.is_executing(), "B3: Turn executive is not in executing state after start")


# =============================================================================
# C — EXACTLY ONE INCREMENT
# =============================================================================
func _test_c_exactly_one_increment() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var initial_turn: int = CampaignTurnExecutive.get_turn()
	var receipt: Dictionary = CampaignTurnExecutive.advance_campaign_turn("test_single_advance")

	_check(receipt.get("ok", false) == true, "C1: advance_campaign_turn returned ok=true")
	_check(int(receipt.get("turn", -1)) == initial_turn + 1, "C2: Receipt indicates turn incremented by exactly 1")
	_check(CampaignTurnExecutive.get_turn() == initial_turn + 1, "C3: Authoritative counter incremented by exactly 1")


# =============================================================================
# D — REPEATED ADVANCEMENT
# =============================================================================
func _test_d_repeated_advancement() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var N: int = 7
	for i in range(N):
		var before: int = CampaignTurnExecutive.get_turn()
		var r: Dictionary = CampaignTurnExecutive.advance_campaign_turn("step_%d" % i)
		_check(r.get("ok", false) == true and int(r.get("turn", -1)) == before + 1,
			"D%d: Turn incremented monotonically to %d" % [i + 1, before + 1])

	_check(CampaignTurnExecutive.get_turn() == N, "D_final: N calls produced exactly N increments (turn=%d)" % N)


# =============================================================================
# E — FAILED START ISOLATION
# =============================================================================
func _test_e_failed_start_isolation() -> void:
	_clear_all_state()

	# 1. Missing scenario ID
	var res_empty: Dictionary = RunStartSystem.start_campaign_scenario("")
	_check(res_empty.get("ok", false) == false, "E1: Empty scenario ID fails")
	_check(CampaignTurnExecutive.get_turn() == 0, "E2: Turn remains 0 after empty scenario ID")

	# 2. Unknown scenario ID
	var res_unknown: Dictionary = RunStartSystem.start_campaign_scenario("non_existent_scenario_xyz")
	_check(res_unknown.get("ok", false) == false, "E3: Unknown scenario ID fails")
	_check(CampaignTurnExecutive.get_turn() == 0, "E4: Turn remains 0 after unknown scenario ID")

	# 3. Invalid scenario resource (validation failure)
	var invalid_def = ScenarioDefScript.new()
	invalid_def.scenario_id = "invalid_empty_def"
	var catalog = ScenarioCatalogScript.new()
	catalog.scenarios.append(invalid_def)
	var res_invalid: Dictionary = RunStartSystem.start_campaign_scenario("invalid_empty_def", catalog)
	_check(res_invalid.get("ok", false) == false, "E5: Validation failure fails")
	_check(CampaignTurnExecutive.get_turn() == 0, "E6: Turn remains 0 after validation failure")


# =============================================================================
# F — RESET ISOLATION
# =============================================================================
func _test_f_reset_isolation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Advance run 1 to turn 4
	for i in range(4):
		CampaignTurnExecutive.advance_campaign_turn("run1_turn")
	_check(CampaignTurnExecutive.get_turn() == 4, "F1: Run 1 reached turn 4")

	# Start a fresh campaign
	var res2: Dictionary = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res2.get("ok", false) == true, "F2: Fresh campaign start succeeded")
	_check(CampaignTurnExecutive.get_turn() == 0, "F3: Fresh campaign start reset turn to 0, no turn leak")


# =============================================================================
# G — SAVE / LOAD
# =============================================================================
func _test_g_save_load() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Advance to turn 5
	for i in range(5):
		CampaignTurnExecutive.advance_campaign_turn("save_prep")
	_check(CampaignTurnExecutive.get_turn() == 5, "G1: Advanced to turn 5 before save")

	# Save run
	var saved: bool = SaveGameIO.save_run()
	_check(saved, "G2: SaveGameIO.save_run returned true")

	# Verify saved content
	var save_json = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(save_json is Dictionary and int((save_json as Dictionary).get("campaign_turn", -1)) == 5,
		"G3: Save payload contains authoritative campaign_turn=5")

	# Reset runtime state to 0
	CampaignTurnExecutive.reset()
	_check(CampaignTurnExecutive.get_turn() == 0, "G4: Turn executive reset to 0 before load")

	# Load run
	var loaded: bool = SaveGameIO.load_run()
	_check(loaded, "G5: SaveGameIO.load_run returned true")
	_check(CampaignTurnExecutive.get_turn() == 5, "G6: Loaded turn restored to exactly 5")

	# Ensure loading did NOT increment the turn
	_check(CampaignTurnExecutive.get_turn() == 5, "G7: Load operation did not increment turn counter")


# =============================================================================
# H — NO SCENARIODEFINITION MUTATION
# =============================================================================
func _test_h_no_scenario_definition_mutation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	var authored_rules_before: Dictionary = scenario.get_strategic_rules().duplicate(true)
	var authored_limit: int = int(authored_rules_before.get("turn_limit", 0))

	# Advance turns
	for i in range(3):
		CampaignTurnExecutive.advance_campaign_turn("check_scenario_immutability")

	var authored_rules_after: Dictionary = scenario.get_strategic_rules()
	_check(authored_rules_after == authored_rules_before, "H1: ScenarioDefinition strategic_rules dict unchanged")
	_check(int(authored_rules_after.get("turn_limit", 0)) == authored_limit, "H2: Authored turn_limit remains constant (%d)" % authored_limit)
	_check(not ("_campaign_turn" in scenario), "H3: ScenarioDefinition does not store _campaign_turn")
	_check(not ("current_turn" in scenario), "H4: ScenarioDefinition does not store current_turn")


# =============================================================================
# I — NO IMPLICIT STRATEGIC SIMULATION
# =============================================================================
func _test_i_no_implicit_strategic_simulation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Snapshot all runtime domain state before advance
	var forces_snap := {}
	for force in CampaignForce.get_forces():
		var f_id: String = str(force.get("id", ""))
		forces_snap[f_id] = {
			"node_id": force.get("node_id", ""),
			"state": force.get("state", -1),
			"strength": force.get("strength", -1),
		}

	var terr_snap := {}
	for terr in CampaignTerritory.get_territories():
		var t_id: String = str(terr.get("id", ""))
		terr_snap[t_id] = {
			"controller": terr.get("controller", ""),
			"contested": terr.get("contested", false),
		}

	var base_snap := {}
	for base in CampaignBase.get_bases():
		var b_id: String = str(base.get("id", ""))
		base_snap[b_id] = {
			"state": base.get("state", -1),
			"controller": base.get("controller", ""),
		}

	var battles_before: Array = CampaignBattle.get_battles()

	# Advance turn
	var receipt := CampaignTurnExecutive.advance_campaign_turn("implicit_sim_probe")
	_check(receipt.get("ok", false) == true, "I1: advance_campaign_turn succeeded")

	# Verify forces were not moved or altered
	var forces_intact := true
	for f_id in forces_snap:
		var force_curr: Dictionary = CampaignForce.get_force(f_id)
		var snap: Dictionary = forces_snap[f_id]
		if force_curr.get("node_id", "") != snap["node_id"] \
			or force_curr.get("state", -1) != snap["state"] \
			or force_curr.get("strength", -1) != snap["strength"]:
			forces_intact = false
			break
	_check(forces_intact, "I2: Forces unchanged by advance_campaign_turn (no implicit movement/attrition)")

	# Verify territories were not flipped
	var terr_intact := true
	for t_id in terr_snap:
		var terr_curr: Dictionary = CampaignTerritory.get_territory(t_id)
		var snap: Dictionary = terr_snap[t_id]
		if terr_curr.get("controller", "") != snap["controller"] \
			or terr_curr.get("contested", false) != snap["contested"]:
			terr_intact = false
			break
	_check(terr_intact, "I3: Territories unchanged by advance_campaign_turn (no implicit capture/contest)")

	# Verify bases were not altered
	var bases_intact := true
	for b_id in base_snap:
		var base_curr: Dictionary = CampaignBase.get_base(b_id)
		var snap: Dictionary = base_snap[b_id]
		if base_curr.get("state", -1) != snap["state"] \
			or base_curr.get("controller", "") != snap["controller"]:
			bases_intact = false
			break
	_check(bases_intact, "I4: Bases unchanged by advance_campaign_turn (no implicit base damage/state flip)")

	# Verify no battles launched
	_check(CampaignBattle.get_battles().size() == battles_before.size(), "I5: Battles unchanged by advance_campaign_turn (no implicit battle launch)")


# =============================================================================
# J — PLAYER SEPARATION
# =============================================================================
func _test_j_player_separation() -> void:
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	_check(not CampaignForce.has_force("player"), "J1: Player is not in CampaignForce registry")
	for f in CampaignForce.get_forces():
		var f_id: String = str(f.get("id", ""))
		_check(f.get("force_type", "") != "PLAYER", "J2: Force %s force_type != 'PLAYER'" % f_id)
		_check(not f_id.begins_with("player"), "J3: Force %s id does not begin with 'player'" % f_id)

	# Advancing turn does not create player force
	CampaignTurnExecutive.advance_campaign_turn("test_player_sep")
	_check(not CampaignForce.has_force("player"), "J4: Player force is still not in CampaignForce after turn advance")


# =============================================================================
# K — DETERMINISM
# =============================================================================
func _test_k_determinism() -> void:
	_clear_all_state()

	# Run 1 sequence
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var seq_1: Array[int] = [CampaignTurnExecutive.get_turn()]
	for i in range(3):
		CampaignTurnExecutive.advance_campaign_turn("det_step_%d" % i)
		seq_1.append(CampaignTurnExecutive.get_turn())

	_clear_all_state()

	# Run 2 sequence under identical initial condition
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	var seq_2: Array[int] = [CampaignTurnExecutive.get_turn()]
	for i in range(3):
		CampaignTurnExecutive.advance_campaign_turn("det_step_%d" % i)
		seq_2.append(CampaignTurnExecutive.get_turn())

	_check(seq_1 == [0, 1, 2, 3], "K1: Run 1 generated sequence [0, 1, 2, 3]")
	_check(seq_1 == seq_2, "K2: Deterministic sequence matches identically across runs")


# =============================================================================
# L — NO SECOND TURN AUTHORITY
# =============================================================================
func _test_l_no_second_turn_authority() -> void:
	_clear_all_state()

	# GlobalData has no campaign_turn property
	_check(not ("campaign_turn" in GlobalData), "L1: GlobalData does not declare campaign_turn")

	# BoardState has no campaign_turn property
	_check(not ("campaign_turn" in GlobalData.board), "L2: BoardState does not declare campaign_turn")

	# CampaignNodeRegistry, CampaignTerritory, CampaignBase, CampaignForce do not declare get_turn
	var reg_inst = CampaignNodeRegistry.new()
	var terr_inst = CampaignTerritory.new()
	var base_inst = CampaignBase.new()
	var force_inst = CampaignForce.new()
	_check(not reg_inst.has_method("get_turn"), "L3: CampaignNodeRegistry does not own turn")
	_check(not terr_inst.has_method("get_turn"), "L4: CampaignTerritory does not own turn")
	_check(not base_inst.has_method("get_turn"), "L5: CampaignBase does not own turn")
	_check(not force_inst.has_method("get_turn"), "L6: CampaignForce does not own turn")


# =============================================================================
# SUMMARY & EXIT
# =============================================================================
func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE 5AG SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN TURN RUNTIME CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN TURN RUNTIME CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
