extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC PERSISTENCE VERIFICATION — Phase C4-B5.
##
## Tests Heat + Detection save/load through the real SaveGameIO disk path:
##   - Round-trip equivalence via save_run() / load_run().
##   - Legacy saves without C4 keys restore empty C4 state (no leakage).
##   - Wrong-typed C4 keys reject the whole load with zero state mutation
##     (established preflight policy, not a C4 special case).
##   - Valid-typed but out-of-range content sanitizes per each authority.
##   - Repeated save/load is stable; legacy-after-C4 leaks nothing.
##   - Turn, player node, aging, and Threat behavior unchanged by I/O.
## Threat is never serialized: post-load threat equals pre-save threat.
## ---------------------------------------------------------------------------

const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")
const CampaignStrategicDetection = preload("res://scripts/systems/campaign_strategic_detection.gd")
const CampaignStrategicThreat = preload("res://scripts/systems/campaign_strategic_threat.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")

var _checks := 0
var _fails := 0
var _backup := ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C4_B5_PERSIST OK: %s" % message)
	else:
		_fails += 1
		printerr("C4_B5_PERSIST FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN STRATEGIC PERSISTENCE VERIFY (Phase C4-B5) ---")
	print("======================================================================")

	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_test_round_trip()
	_test_legacy_compatibility()
	_test_malformed_payloads()
	_test_repeated_operations()
	_test_invariants()

	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("----------------------------------------------------------------------")
	print("PHASE C4-B5 SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL STRATEGIC PERSISTENCE (C4-B5) CHECKS PASSED!")
	else:
		printerr("C4-B5 STRATEGIC PERSISTENCE VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _read_save_dict() -> Dictionary:
	if not FileAccess.file_exists(GlobalData.SAVE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	if parsed is Dictionary:
		return parsed
	return {}


func _write_save_dict(d: Dictionary) -> void:
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.flush()
	f.close()


func _heat_snapshot() -> Dictionary:
	return CampaignStrategicHeat.serialize().duplicate(true)


func _detection_snapshot() -> Dictionary:
	return CampaignStrategicDetection.serialize().duplicate(true)


func _test_round_trip() -> void:
	GlobalData.reset_run_data()
	CampaignStrategicHeat.set_node_heat("node_a", 3)
	CampaignStrategicHeat.set_node_heat("node_b", 10)
	CampaignStrategicHeat.set_node_heat("node_c", 1)
	CampaignStrategicDetection.report_location("federation", "node_a", 5, "combat")
	CampaignStrategicDetection.report_suspicion("zeon", "node_b", 4, 6, "trace")
	var threat_before := CampaignStrategicThreat.get_node_threat("node_x", "federation", 5)

	_check(SaveGameIO.save_run(), "Round-trip save_run succeeds")
	var saved := _read_save_dict()
	_check((saved.get("campaign_strategic_heat", {}) as Dictionary).has("node_heats"), "Save carries campaign_strategic_heat payload")
	_check((saved.get("campaign_strategic_detection", {}) as Dictionary).has("faction_intelligence"), "Save carries campaign_strategic_detection payload")
	_check(not saved.has("campaign_strategic_threat"), "Threat results never serialized")

	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "Heat cleared before load")
	_check(SaveGameIO.load_run(), "Round-trip load_run succeeds")
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 3, "Heat node_a restored to 3")
	_check(CampaignStrategicHeat.get_node_heat("node_b") == 10, "Heat node_b restored to 10")
	_check(CampaignStrategicHeat.get_node_heat("node_c") == 1, "Heat node_c restored to 1")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.LOCATED, "Federation LOCATED restored")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_a", "Federation node restored")
	_check(CampaignStrategicDetection.get_last_known_turn("federation") == 5, "Federation turn restored")
	_check(CampaignStrategicDetection.get_intelligence_source("federation") == "combat", "Federation source restored")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Zeon SUSPECTED restored")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "node_b", "Zeon node restored")
	var threat_after := CampaignStrategicThreat.get_node_threat("node_x", "federation", 5)
	_check(JSON.stringify(threat_after) == JSON.stringify(threat_before), "Post-load threat equals pre-save threat")


func _test_legacy_compatibility() -> void:
	GlobalData.reset_run_data()
	CampaignStrategicHeat.set_node_heat("node_stale", 9)
	CampaignStrategicDetection.report_location("federation", "node_stale", 9, "combat")
	_check(SaveGameIO.save_run(), "Legacy-base save_run succeeds")
	# Forge a pre-C4 save: drop both C4 keys (and schema stamp for true legacy).
	var d := _read_save_dict()
	d.erase("campaign_strategic_heat")
	d.erase("campaign_strategic_detection")
	_write_save_dict(d)
	_check(SaveGameIO.load_run(), "C4-less save loads successfully")
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "Missing heat key restores empty heat (no leak)")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Missing detection key restores empty intel (no leak)")
	# Partial presence: heat only.
	_check(SaveGameIO.save_run(), "Second save succeeds")
	var d2 := _read_save_dict()
	d2.erase("campaign_strategic_detection")
	_write_save_dict(d2)
	CampaignStrategicHeat.set_node_heat("node_junk", 4)
	CampaignStrategicDetection.report_location("zeon", "node_junk", 3, "combat")
	_check(SaveGameIO.load_run(), "Heat-only save loads successfully")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Missing detection key stays empty beside valid heat")
	# True legacy: no schema stamp either.
	var d3 := _read_save_dict()
	d3.erase("campaign_strategic_heat")
	d3.erase("campaign_strategic_detection")
	d3.erase("schema_version")
	_write_save_dict(d3)
	_check(SaveGameIO.load_run(), "Schema-less legacy save loads successfully")
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "Legacy load leaves heat empty")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Legacy load leaves intel empty")


func _test_malformed_payloads() -> void:
	GlobalData.reset_run_data()
	CampaignStrategicHeat.set_node_heat("node_keep", 5)
	CampaignStrategicDetection.report_location("federation", "node_keep", 7, "combat")
	_check(SaveGameIO.save_run(), "Malformed-base save_run succeeds")
	# Wrong-typed heat key: whole load rejected, runtime untouched.
	var bad_heat := _read_save_dict()
	bad_heat["campaign_strategic_heat"] = [1, 2, 3]
	_write_save_dict(bad_heat)
	_check(not SaveGameIO.load_run(), "Wrong-typed heat key rejects the load")
	_check(CampaignStrategicHeat.get_node_heat("node_keep") == 5, "Heat intact after rejected load")
	_check(CampaignStrategicDetection.is_located("federation"), "Intel intact after rejected load")
	# Wrong-typed detection key: same whole-load policy.
	var bad_det := _read_save_dict()
	bad_det["campaign_strategic_heat"] = {"node_heats": {"node_keep": 5}}
	bad_det["campaign_strategic_detection"] = "not-a-dict"
	_write_save_dict(bad_det)
	_check(not SaveGameIO.load_run(), "Wrong-typed detection key rejects the load")
	_check(CampaignStrategicHeat.get_node_heat("node_keep") == 5, "Heat intact after second rejection")
	# Valid-typed but out-of-range content sanitizes per authority contracts.
	var wild := _read_save_dict()
	wild["campaign_strategic_heat"] = {"node_heats": {"node_big": 999, "node_neg": -50, "   ": 4}}
	wild["campaign_strategic_detection"] = {"faction_intelligence": {
		"federation": {"state": 999, "last_known_node_id": "node_x", "last_known_turn": -5},
		"   ": {"state": 1, "last_known_node_id": "node_y"},
	}}
	_write_save_dict(wild)
	_check(SaveGameIO.load_run(), "Sanitizable payload still loads")
	_check(CampaignStrategicHeat.get_node_heat("node_big") == 10, "Heat 999 clamps to 10 on load")
	_check(CampaignStrategicHeat.get_node_heat("node_neg") == 0, "Negative heat dropped on load")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Invalid enum sanitizes to UNKNOWN")
	# Empty-but-valid payloads load as empty.
	var empty_valid := _read_save_dict()
	empty_valid["campaign_strategic_heat"] = {"node_heats": {}}
	empty_valid["campaign_strategic_detection"] = {"faction_intelligence": {}}
	_write_save_dict(empty_valid)
	_check(SaveGameIO.load_run(), "Empty-but-valid payloads load")
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "Empty heat payload restores empty")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Empty intel payload restores empty")
	# Unknown extra fields tolerated; known values intact.
	var extra := _read_save_dict()
	extra["campaign_strategic_heat"] = {"node_heats": {"node_e": 4}, "future_field": 1}
	extra["campaign_strategic_detection"] = {"faction_intelligence": {
		"zeon": {"state": 1, "last_known_node_id": "node_e", "last_known_turn": 2, "source": "trace", "extra_note": "x"}}}
	_write_save_dict(extra)
	_check(SaveGameIO.load_run(), "Payload with unknown fields loads")
	_check(CampaignStrategicHeat.get_node_heat("node_e") == 4, "Known heat intact beside unknown fields")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "node_e", "Known intel intact beside unknown fields")


func _test_repeated_operations() -> void:
	GlobalData.reset_run_data()
	CampaignStrategicHeat.set_node_heat("node_r", 6)
	CampaignStrategicDetection.report_suspicion("outland", "node_r", 2, 5, "trace")
	_check(SaveGameIO.save_run(), "First save succeeds")
	var first_text := FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	_check(SaveGameIO.save_run(), "Second save succeeds")
	_check(FileAccess.get_file_as_string(GlobalData.SAVE_PATH) == first_text, "Repeated saves are byte-identical")
	_check(SaveGameIO.load_run(), "First load succeeds")
	var heat_once := _heat_snapshot()
	var det_once := _detection_snapshot()
	_check(SaveGameIO.load_run(), "Second load succeeds")
	_check(JSON.stringify(_heat_snapshot()) == JSON.stringify(heat_once), "Repeated loads duplicate no heat")
	_check(JSON.stringify(_detection_snapshot()) == JSON.stringify(det_once), "Repeated loads duplicate no intel")
	_check(CampaignStrategicHeat.get_node_heat("node_r") == 6, "Heat value stable across loads")
	# Legacy load after a C4 save leaks nothing (fresh pre-C4 file).
	var d := _read_save_dict()
	d.erase("campaign_strategic_heat")
	d.erase("campaign_strategic_detection")
	_write_save_dict(d)
	_check(SaveGameIO.load_run(), "Legacy load after C4 save succeeds")
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "No heat leaks into legacy load")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "No intel leaks into legacy load")


func _test_invariants() -> void:
	GlobalData.reset_run_data()
	CampaignTurnExecutive.deserialize_campaign_turn(7)
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	GlobalData.current_campaign_player_node_id = "node_s1_city_2_2"
	CampaignStrategicHeat.set_node_heat("node_s1_city_2_2", 8)
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 7, "combat")
	var turn_before := CampaignTurnExecutive.get_turn()
	_check(SaveGameIO.save_run(), "Invariant save succeeds")
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	GlobalData.current_campaign_player_node_id = ""
	_check(SaveGameIO.load_run(), "Invariant load succeeds")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "Turn unchanged by save/load")
	_check(CampaignStrategicHeat.get_node_heat("node_s1_city_2_2") == 8, "Heat restored without decay on load")
	_check(CampaignStrategicDetection.is_located("federation"), "Intel restored without aging on load")
	_check(CampaignStrategicDetection.get_last_known_turn("federation") == 7, "Intel turn preserved exactly")
	_check(GlobalData.current_campaign_player_node_id == "node_s1_city_2_2", "Player node restored via existing contract")
	var threat := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 7)
	_check(int(threat.get("threat_level", -1)) == 1, "Post-load threat deterministic from restored state")
	var heats := CampaignStrategicHeat.get_all_heats()
	(heats as Dictionary).clear()
	_check(not CampaignStrategicHeat.get_all_heats().is_empty(), "Restored heat protected from caller mutation")
	GlobalData.current_campaign_player_node_id = ""
	CampaignNodeRegistry.clear()
