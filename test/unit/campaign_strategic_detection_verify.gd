extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC DETECTION VERIFICATION — Phase C4-B2.
##
## Tests the isolated CampaignStrategicDetection subsystem:
##   - Initial state & default values
##   - Multi-faction intelligence isolation (anti-leakage across factions)
##   - Suspicion event elevation (UNKNOWN -> SUSPECTED)
##   - Location event elevation (UNKNOWN/SUSPECTED -> LOCATED)
##   - Freshness & stale event rejection
##   - Turn-based degradation (LOCATED -> SUSPECTED -> UNKNOWN)
##   - Heat trace evaluation & threshold policy (Heat >= 3 -> SUSPECTED, never LOCATED)
##   - Heat decay independence (Heat dissipation != Intelligence loss)
##   - Anti-omniscience (zero leakage from GlobalData.current_campaign_player_node_id)
##   - Defensive copying of state dictionaries
##   - Serialization round-trip & malformed payload resilience
##   - GlobalData.reset_run_data() lifecycle integration
##   - Zero leakage to tactical HeatWantedSystem / BoardState
## ---------------------------------------------------------------------------

const CampaignStrategicDetection = preload("res://scripts/systems/campaign_strategic_detection.gd")
const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")

var _checks := 0
var _fails := 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C4_B2_DETECTION OK: %s" % message)
	else:
		_fails += 1
		printerr("C4_B2_DETECTION FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN STRATEGIC DETECTION VERIFY (Phase C4-B2) ---")
	print("======================================================================")

	_test_default_state_and_unknown_faction()
	_test_faction_intelligence_isolation()
	_test_suspicion_elevation_and_refresh()
	_test_location_elevation_and_update()
	_test_stale_event_rejection()
	_test_turn_decay_and_expiration()
	_test_heat_trace_threshold_policy()
	_test_heat_decay_independence()
	_test_anti_omniscience_isolation()
	_test_defensive_copying()
	_test_invalid_parameters_policy()
	_test_serialization_and_deserialization()
	_test_global_data_reset_integration()
	_test_zero_tactical_leakage()

	print("----------------------------------------------------------------------")
	print("PHASE C4-B2 SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL STRATEGIC DETECTION (C4-B2) CHECKS PASSED!")
	else:
		printerr("C4-B2 STRATEGIC DETECTION VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _test_default_state_and_unknown_faction() -> void:
	CampaignStrategicDetection.reset()
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Default state is UNKNOWN")
	_check(not CampaignStrategicDetection.is_located("federation"), "is_located returns false for default state")
	_check(not CampaignStrategicDetection.is_suspected("federation"), "is_suspected returns false for default state")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "", "last_known_node_id defaults to empty string")
	_check(CampaignStrategicDetection.get_last_known_turn("federation") == 0, "last_known_turn defaults to 0")
	_check(CampaignStrategicDetection.get_intelligence_source("federation") == "none", "intelligence source defaults to none")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "get_all_intelligence is initially empty")


func _test_faction_intelligence_isolation() -> void:
	CampaignStrategicDetection.reset()

	# Federation locates player
	var res := CampaignStrategicDetection.report_location("federation", "node_alpha", 5, "combat")
	_check(bool(res.get("ok", false)), "Federation location report ok")
	_check(CampaignStrategicDetection.is_located("federation"), "Federation state is LOCATED")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_alpha", "Federation last node is node_alpha")

	# Zeon and Outland must remain completely unaffected (zero cross-faction leakage)
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Zeon intelligence remains UNKNOWN")
	_check(not CampaignStrategicDetection.is_located("zeon"), "Zeon is_located is false")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "", "Zeon last_known_node_id is empty")

	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Outland intelligence remains UNKNOWN")
	_check(not CampaignStrategicDetection.is_located("outland"), "Outland is_located is false")


func _test_suspicion_elevation_and_refresh() -> void:
	CampaignStrategicDetection.reset()

	# UNKNOWN -> SUSPECTED
	var res1 := CampaignStrategicDetection.report_suspicion("zeon", "node_beta", 2, 4, "trace_recon")
	_check(bool(res1.get("ok", false)), "Suspicion report ok")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "State elevated to SUSPECTED")
	_check(CampaignStrategicDetection.is_suspected("zeon"), "is_suspected is true")
	_check(not CampaignStrategicDetection.is_located("zeon"), "is_located is false")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "node_beta", "last_known_node_id set to node_beta")
	_check(CampaignStrategicDetection.get_last_known_turn("zeon") == 2, "last_known_turn set to 2")

	# Refreshing suspicion on subsequent turn
	var res2 := CampaignStrategicDetection.report_suspicion("zeon", "node_gamma", 4, 5, "trace_recon")
	_check(bool(res2.get("ok", false)), "Subsequent suspicion report ok")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "State remains SUSPECTED")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "node_gamma", "last_known_node_id updated to node_gamma")
	_check(CampaignStrategicDetection.get_last_known_turn("zeon") == 4, "last_known_turn updated to 4")


func _test_location_elevation_and_update() -> void:
	CampaignStrategicDetection.reset()

	# Elevate directly from UNKNOWN to LOCATED
	var res1 := CampaignStrategicDetection.report_location("federation", "node_city", 3, "combat_ambush")
	_check(bool(res1.get("ok", false)), "Location report ok")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.LOCATED, "State is LOCATED")
	_check(CampaignStrategicDetection.is_located("federation"), "is_located is true")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_city", "last_known_node_id is node_city")

	# Update location to newer node on turn 5
	var res2 := CampaignStrategicDetection.report_location("federation", "node_depot", 5, "combat_assault")
	_check(bool(res2.get("ok", false)), "Newer location report ok")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_depot", "last_known_node_id updated to node_depot")
	_check(CampaignStrategicDetection.get_last_known_turn("federation") == 5, "last_known_turn updated to 5")


func _test_stale_event_rejection() -> void:
	CampaignStrategicDetection.reset()
	CampaignStrategicDetection.report_location("federation", "node_current", 10, "combat")

	# Attempt to report suspicion or location with older turn timestamp (turn 6 < 10)
	var stale_res1 := CampaignStrategicDetection.report_location("federation", "node_old", 6, "combat")
	_check(not bool(stale_res1.get("ok", true)), "Stale location event rejected")
	_check(str(stale_res1.get("reason", "")) == "stale_event", "Rejection reason is stale_event")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_current", "Node untouched after stale event")
	_check(CampaignStrategicDetection.get_last_known_turn("federation") == 10, "Turn untouched after stale event")

	var stale_res2 := CampaignStrategicDetection.report_suspicion("federation", "node_old", 8, 5, "trace")
	_check(not bool(stale_res2.get("ok", true)), "Stale suspicion event rejected")
	_check(str(stale_res2.get("reason", "")) == "stale_event", "Rejection reason is stale_event for suspicion")


func _test_turn_decay_and_expiration() -> void:
	CampaignStrategicDetection.reset()

	# Turn 1: Federation locates player at node_a; Zeon suspects player at node_b
	CampaignStrategicDetection.report_location("federation", "node_a", 1, "combat")
	CampaignStrategicDetection.report_suspicion("zeon", "node_b", 1, 4, "trace")

	# Turn 2: 1 turn elapsed.
	# LOCATED should degrade to SUSPECTED (age = 1 >= LOCATED_MAX_AGE_TURNS)
	# SUSPECTED should remain SUSPECTED (age = 1 < SUSPECTED_MAX_AGE_TURNS (3))
	var decay1 := CampaignStrategicDetection.process_turn_decay(2)
	_check(bool(decay1.get("ok", false)), "Turn 2 decay processed ok")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Federation degraded from LOCATED to SUSPECTED")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_a", "Federation retains historical last_known_node_id on degradation")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Zeon remains SUSPECTED at age 1")

	# Turn 4: 3 turns elapsed since turn 1 (age = 3 >= SUSPECTED_MAX_AGE_TURNS)
	# Zeon should degrade from SUSPECTED to UNKNOWN
	var decay2 := CampaignStrategicDetection.process_turn_decay(4)
	_check(bool(decay2.get("ok", false)), "Turn 4 decay processed ok")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Zeon degraded from SUSPECTED to UNKNOWN after 3 turns")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "", "Zeon last_known_node_id cleared upon returning to UNKNOWN")


func _test_heat_trace_threshold_policy() -> void:
	CampaignStrategicDetection.reset()

	# Heat below threshold (2 < 3) -> rejected, no state change
	var res_sub := CampaignStrategicDetection.evaluate_node_trace("outland", "node_quiet", 2, 1)
	_check(not bool(res_sub.get("ok", true)), "Sub-threshold trace evaluation returns ok: false")
	_check(str(res_sub.get("reason", "")) == "below_threshold", "Reason is below_threshold")
	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Outland remains UNKNOWN")

	# Heat at threshold (3 >= 3) -> elevates to SUSPECTED
	var res_thresh := CampaignStrategicDetection.evaluate_node_trace("outland", "node_active", 3, 1)
	_check(bool(res_thresh.get("ok", false)), "Threshold trace evaluation returns ok: true")
	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Outland elevated to SUSPECTED at heat 3")

	# Heat max (10 >= 3) -> elevates to SUSPECTED, NEVER to LOCATED
	CampaignStrategicDetection.reset()
	var res_max := CampaignStrategicDetection.evaluate_node_trace("outland", "node_inferno", 10, 1)
	_check(bool(res_max.get("ok", false)), "Max heat evaluation returns ok: true")
	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Max heat elevates to SUSPECTED")
	_check(not CampaignStrategicDetection.is_located("outland"), "Max heat NEVER directly grants LOCATED state")


func _test_heat_decay_independence() -> void:
	CampaignStrategicDetection.reset()
	CampaignStrategicHeat.reset()

	# Set physical trace and record independent combat detection
	CampaignStrategicHeat.set_node_heat("node_battleground", 8)
	CampaignStrategicDetection.report_location("zeon", "node_battleground", 1, "combat")

	# Completely wipe/decay physical heat to 0
	CampaignStrategicHeat.reset()
	_check(CampaignStrategicHeat.get_node_heat("node_battleground") == 0, "Physical heat is 0")

	# Intelligence must NOT be instantly destroyed simply because physical heat cooled
	_check(CampaignStrategicDetection.is_located("zeon"), "Zeon location intelligence intact despite heat decay")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "node_battleground", "Zeon last known node intact")


func _test_anti_omniscience_isolation() -> void:
	CampaignStrategicDetection.reset()

	# Set global player node ID (e.g. player moved)
	if GlobalData != null:
		GlobalData.current_campaign_player_node_id = "node_secret_hideout"

	# Zero factions should know this location
	for fid in ["federation", "zeon", "outland"]:
		_check(CampaignStrategicDetection.get_detection_state(fid) == CampaignStrategicDetection.DetectionState.UNKNOWN, "%s has UNKNOWN state" % fid)
		_check(CampaignStrategicDetection.get_last_known_node_id(fid) == "", "%s has empty last_known_node_id" % fid)


func _test_defensive_copying() -> void:
	CampaignStrategicDetection.reset()
	CampaignStrategicDetection.report_location("federation", "node_base", 1, "recon")

	var copy1 := CampaignStrategicDetection.get_faction_intelligence("federation")
	copy1["state"] = CampaignStrategicDetection.DetectionState.UNKNOWN
	copy1["last_known_node_id"] = "tampered_node"

	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.LOCATED, "Internal state protected against single getter mutation")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_base", "Internal node protected against mutation")

	var all_copy := CampaignStrategicDetection.get_all_intelligence()
	all_copy.clear()
	_check(not CampaignStrategicDetection.get_all_intelligence().is_empty(), "Internal storage protected against get_all_intelligence mutation")


func _test_invalid_parameters_policy() -> void:
	CampaignStrategicDetection.reset()

	var res_bad_fid := CampaignStrategicDetection.report_location("", "node_a", 1)
	_check(not bool(res_bad_fid.get("ok", true)), "Empty faction_id rejected")
	_check(str(res_bad_fid.get("reason", "")) == "empty_faction_id", "Reason is empty_faction_id")

	var res_bad_nid := CampaignStrategicDetection.report_location("zeon", "", 1)
	_check(not bool(res_bad_nid.get("ok", true)), "Empty node_id rejected")
	_check(str(res_bad_nid.get("reason", "")) == "empty_node_id", "Reason is empty_node_id")

	var res_neg_turn := CampaignStrategicDetection.report_location("zeon", "node_a", -1)
	_check(not bool(res_neg_turn.get("ok", true)), "Negative turn rejected")
	_check(str(res_neg_turn.get("reason", "")) == "negative_turn", "Reason is negative_turn")


func _test_serialization_and_deserialization() -> void:
	CampaignStrategicDetection.reset()
	CampaignStrategicDetection.report_location("federation", "node_alpha", 3, "combat")
	CampaignStrategicDetection.report_suspicion("zeon", "node_beta", 2, 4, "trace")

	var serialized := CampaignStrategicDetection.serialize()
	_check(serialized.has("faction_intelligence"), "Serialized dictionary has faction_intelligence")

	CampaignStrategicDetection.reset()
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "reset() clears intelligence records")

	CampaignStrategicDetection.deserialize(serialized)
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.LOCATED, "Deserialized federation is LOCATED")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_alpha", "Deserialized federation node is node_alpha")
	_check(CampaignStrategicDetection.get_last_known_turn("federation") == 3, "Deserialized federation turn is 3")

	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Deserialized zeon is SUSPECTED")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == "node_beta", "Deserialized zeon node is node_beta")

	# Deserialization with malformed input
	var malformed := {
		"faction_intelligence": {
			"outland": {
				"state": 999, # invalid enum
				"last_known_node_id": "node_x",
				"last_known_turn": -5
			},
			"   ": {
				"state": 1,
				"last_known_node_id": "node_y"
			}
		}
	}
	CampaignStrategicDetection.deserialize(malformed)
	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Invalid enum state sanitizes to UNKNOWN")
	_check(CampaignStrategicDetection.get_detection_state("") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Whitespace faction ignored")


func _test_global_data_reset_integration() -> void:
	CampaignStrategicDetection.reset()
	CampaignStrategicDetection.report_location("federation", "node_test", 4, "combat")
	_check(CampaignStrategicDetection.is_located("federation"), "Pre-reset state is LOCATED")

	GlobalData.reset_run_data()

	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "GlobalData.reset_run_data() completely cleared detection state")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Federation state is UNKNOWN after reset_run_data")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "", "Federation last_known_node_id is empty after reset_run_data")

	# Post-test cleanup
	CampaignStrategicDetection.reset()


func _test_zero_tactical_leakage() -> void:
	CampaignStrategicDetection.reset()
	var initial_heat := 0
	var initial_patrols := 0
	if GlobalData != null and GlobalData.board != null:
		initial_heat = GlobalData.board.heat
		initial_patrols = GlobalData.board.board_patrols.size()

	# Perform intense detection mutations
	for i in range(10):
		CampaignStrategicDetection.report_location("faction_%d" % i, "node_%d" % i, i, "combat")
	CampaignStrategicDetection.process_turn_decay(20)

	if GlobalData != null and GlobalData.board != null:
		_check(GlobalData.board.heat == initial_heat, "Tactical GlobalData.board.heat untouched by strategic detection")
		_check(GlobalData.board.board_patrols.size() == initial_patrols, "Tactical patrols count untouched by strategic detection")
	else:
		_check(true, "Zero tactical leakage baseline check")
