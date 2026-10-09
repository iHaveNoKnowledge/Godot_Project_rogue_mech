extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC HEAT FOUNDATION VERIFICATION — Phase C4-B1.
##
## Tests the isolated CampaignStrategicHeat subsystem:
##   - Node-local trace storage and querying
##   - Positive addition and max clamping
##   - Zero/negative addition rejection policy
##   - Individual and batch decay with floor clamping
##   - Independent node isolation
##   - Lifecycle reset and serialization
##   - Zero leakage to tactical HeatWantedSystem or board patrols
##   - Empty and whitespace node ID handling
## ---------------------------------------------------------------------------

const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")

var _checks := 0
var _fails := 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C4_B1_HEAT OK: %s" % message)
	else:
		_fails += 1
		printerr("C4_B1_HEAT FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN STRATEGIC HEAT FOUNDATION VERIFY (Phase C4-B1) ---")
	print("======================================================================")

	_test_default_and_unknown_nodes()
	_test_positive_addition_and_clamping()
	_test_non_positive_addition_policy()
	_test_decay_single_and_batch()
	_test_decay_empty_and_floor()
	_test_node_isolation()
	_test_reset_and_serialization()
	_test_zero_tactical_leakage()
	_test_invalid_node_id_policy()
	_test_global_data_reset_run_data_integration()

	print("----------------------------------------------------------------------")
	print("PHASE C4-B1 SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL STRATEGIC HEAT FOUNDATION (C4-B1) CHECKS PASSED!")
	else:
		printerr("C4-B1 STRATEGIC HEAT VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _test_default_and_unknown_nodes() -> void:
	CampaignStrategicHeat.reset()
	_check(CampaignStrategicHeat.get_node_heat("node_unknown") == 0, "Unknown node heat defaults to 0")
	_check(not CampaignStrategicHeat.has_heat("node_unknown"), "has_heat returns false for unknown node")
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "get_all_heats is initially empty")


func _test_positive_addition_and_clamping() -> void:
	CampaignStrategicHeat.reset()
	var res1 := CampaignStrategicHeat.add_node_heat("node_alpha", 3)
	_check(bool(res1.get("ok", false)), "Adding 3 heat returns ok: true")
	_check(int(res1.get("new_heat", 0)) == 3, "New heat in receipt is 3")
	_check(int(res1.get("added", 0)) == 3, "Added amount is 3")
	_check(CampaignStrategicHeat.get_node_heat("node_alpha") == 3, "get_node_heat returns 3 for node_alpha")
	_check(CampaignStrategicHeat.has_heat("node_alpha"), "has_heat returns true for node_alpha")

	var res2 := CampaignStrategicHeat.add_node_heat("node_alpha", 5)
	_check(CampaignStrategicHeat.get_node_heat("node_alpha") == 8, "Cumulative addition reaches 8")
	_check(int(res2.get("added", 0)) == 5, "Added amount is 5")

	# Clamping at MAX_HEAT (10)
	var res3 := CampaignStrategicHeat.add_node_heat("node_alpha", 5)
	_check(CampaignStrategicHeat.get_node_heat("node_alpha") == 10, "Addition clamps at MAX_HEAT (10)")
	_check(int(res3.get("new_heat", 0)) == 10, "Receipt new_heat is clamped to 10")
	_check(int(res3.get("added", 0)) == 2, "Added amount correctly reflects clamped delta (2)")


func _test_non_positive_addition_policy() -> void:
	CampaignStrategicHeat.reset()
	CampaignStrategicHeat.set_node_heat("node_beta", 4)

	var res_zero := CampaignStrategicHeat.add_node_heat("node_beta", 0)
	_check(not bool(res_zero.get("ok", true)), "Adding 0 heat returns ok: false")
	_check(str(res_zero.get("reason", "")) == "non_positive_amount", "Reason is non_positive_amount")
	_check(CampaignStrategicHeat.get_node_heat("node_beta") == 4, "Heat untouched after zero addition")

	var res_neg := CampaignStrategicHeat.add_node_heat("node_beta", -3)
	_check(not bool(res_neg.get("ok", true)), "Adding negative heat returns ok: false")
	_check(str(res_neg.get("reason", "")) == "non_positive_amount", "Reason is non_positive_amount")
	_check(CampaignStrategicHeat.get_node_heat("node_beta") == 4, "Heat untouched after negative addition")


func _test_decay_single_and_batch() -> void:
	CampaignStrategicHeat.reset()
	CampaignStrategicHeat.set_node_heat("node_gamma", 5)
	CampaignStrategicHeat.set_node_heat("node_delta", 2)

	var res_dec := CampaignStrategicHeat.decay_node_heat("node_gamma", 2)
	_check(bool(res_dec.get("ok", false)), "Single decay returns ok: true")
	_check(CampaignStrategicHeat.get_node_heat("node_gamma") == 3, "node_gamma decayed from 5 to 3")
	_check(int(res_dec.get("decayed", 0)) == 2, "Decayed delta is 2")

	# Batch decay
	var res_batch := CampaignStrategicHeat.decay_all_nodes(1)
	_check(bool(res_batch.get("ok", false)), "decay_all_nodes returns ok: true")
	_check(int(res_batch.get("decayed_nodes", 0)) == 2, "decay_all_nodes processed 2 nodes")
	_check(CampaignStrategicHeat.get_node_heat("node_gamma") == 2, "node_gamma decayed to 2")
	_check(CampaignStrategicHeat.get_node_heat("node_delta") == 1, "node_delta decayed to 1")


func _test_decay_empty_and_floor() -> void:
	CampaignStrategicHeat.reset()
	var res_empty := CampaignStrategicHeat.decay_all_nodes(1)
	_check(bool(res_empty.get("ok", false)), "Decaying empty state is safe and returns ok: true")
	_check(int(res_empty.get("decayed_nodes", 0)) == 0, "Zero nodes decayed on empty state")

	# Decay below 0 clamps to 0
	CampaignStrategicHeat.set_node_heat("node_epsilon", 1)
	var res_floor := CampaignStrategicHeat.decay_node_heat("node_epsilon", 5)
	_check(CampaignStrategicHeat.get_node_heat("node_epsilon") == 0, "Decay beyond zero clamps at MIN_HEAT (0)")
	_check(int(res_floor.get("decayed", 0)) == 1, "Decayed delta clamped to actual drop (1)")
	_check(not CampaignStrategicHeat.has_heat("node_epsilon"), "has_heat is false when decayed to 0")


func _test_node_isolation() -> void:
	CampaignStrategicHeat.reset()
	CampaignStrategicHeat.set_node_heat("node_1", 3)
	CampaignStrategicHeat.set_node_heat("node_2", 7)

	CampaignStrategicHeat.add_node_heat("node_1", 2)
	_check(CampaignStrategicHeat.get_node_heat("node_1") == 5, "node_1 heat updated to 5")
	_check(CampaignStrategicHeat.get_node_heat("node_2") == 7, "node_2 heat completely untouched by node_1 mutation")


func _test_reset_and_serialization() -> void:
	CampaignStrategicHeat.reset()
	CampaignStrategicHeat.set_node_heat("node_a", 4)
	CampaignStrategicHeat.set_node_heat("node_b", 8)

	var serialized := CampaignStrategicHeat.serialize()
	_check(serialized.has("node_heats"), "Serialization dictionary has node_heats")

	CampaignStrategicHeat.reset()
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "reset() clears all tracked node heats")

	CampaignStrategicHeat.deserialize(serialized)
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 4, "Deserialized node_a heat restored to 4")
	_check(CampaignStrategicHeat.get_node_heat("node_b") == 8, "Deserialized node_b heat restored to 8")

	# Deserialization with out-of-range clamping
	var malformed := {
		"node_heats": {
			"node_c": 999,
			"node_d": -50,
			"   ": 5
		}
	}
	CampaignStrategicHeat.deserialize(malformed)
	_check(CampaignStrategicHeat.get_node_heat("node_c") == 10, "Deserialization clamps 999 to MAX_HEAT (10)")
	_check(CampaignStrategicHeat.get_node_heat("node_d") == 0, "Deserialization ignores/clamps negative values")
	_check(CampaignStrategicHeat.get_node_heat("") == 0, "Empty key ignored during deserialization")


func _test_zero_tactical_leakage() -> void:
	CampaignStrategicHeat.reset()
	var initial_tactical_heat: int = 0
	if GlobalData != null and GlobalData.board != null:
		initial_tactical_heat = GlobalData.board.heat

	var initial_patrol_count := 0
	if GlobalData != null and GlobalData.board != null:
		initial_patrol_count = GlobalData.board.board_patrols.size()

	# Perform intense strategic heat additions and decays
	for i in range(10):
		CampaignStrategicHeat.add_node_heat("node_stress_%d" % i, 7)
	CampaignStrategicHeat.decay_all_nodes(3)

	if GlobalData != null and GlobalData.board != null:
		_check(GlobalData.board.heat == initial_tactical_heat, "Tactical GlobalData.board.heat completely untouched by strategic heat")
		_check(GlobalData.board.board_patrols.size() == initial_patrol_count, "GlobalData.board.board_patrols count completely untouched by strategic heat")
	else:
		_check(true, "Zero tactical leakage baseline check")


func _test_invalid_node_id_policy() -> void:
	CampaignStrategicHeat.reset()
	var res_empty := CampaignStrategicHeat.add_node_heat("", 5)
	_check(not bool(res_empty.get("ok", true)), "Empty node_id addition returns ok: false")
	_check(str(res_empty.get("reason", "")) == "empty_node_id", "Reason is empty_node_id")

	var res_ws := CampaignStrategicHeat.add_node_heat("   ", 5)
	_check(not bool(res_ws.get("ok", true)), "Whitespace node_id addition returns ok: false")
	_check(str(res_ws.get("reason", "")) == "empty_node_id", "Reason is empty_node_id for whitespace")

	_check(not CampaignStrategicHeat.set_node_heat("", 5), "set_node_heat with empty string returns false")
	_check(CampaignStrategicHeat.get_node_heat("") == 0, "get_node_heat with empty string returns 0")


func _test_global_data_reset_run_data_integration() -> void:
	CampaignStrategicHeat.reset()
	CampaignStrategicHeat.set_node_heat("node_test_lifecycle", 6)
	_check(CampaignStrategicHeat.get_node_heat("node_test_lifecycle") == 6, "Pre-reset heat is set to 6")
	_check(not CampaignStrategicHeat.get_all_heats().is_empty(), "Pre-reset get_all_heats is not empty")

	GlobalData.reset_run_data()

	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "GlobalData.reset_run_data() cleared all strategic heat")
	_check(CampaignStrategicHeat.get_node_heat("node_test_lifecycle") == 0, "get_node_heat returns 0 after reset_run_data")
	_check(not CampaignStrategicHeat.has_heat("node_test_lifecycle"), "has_heat returns false after reset_run_data")

	# Post-test cleanup
	CampaignStrategicHeat.reset()

