extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN TURN C4 INTEGRATION VERIFICATION — Phase C4-B4.
##
## Tests the turn-executive integration of the C4 strategic systems:
##   - Normal progression: heat dissipates by one step and detection ages
##     against the new authoritative turn at a documented phase point.
##   - Counter-only turns skip both C4 phases (no day semantics forced).
##   - Nested/reentrant invocation processes nothing twice (single decay,
##     single aging stage, no extra turn).
##   - Later turns keep decaying; counter-only turns never age intel.
##   - Isolation: player node, forces, bases, territories, battles, faction
##     relations, and tactical heat/patrols are untouched by C4 processing.
##   - Reset still clears heat, detection, and the turn counter.
## Threat stays a pure query: it runs no turn phase and is only read here
## to prove the integration leaves its contract intact.
## ---------------------------------------------------------------------------

const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")
const CampaignStrategicDetection = preload("res://scripts/systems/campaign_strategic_detection.gd")
const CampaignStrategicThreat = preload("res://scripts/systems/campaign_strategic_threat.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const CampaignBattle = preload("res://scripts/systems/campaign_battle.gd")

# Mirrors CampaignTurnExecutive.PHASE_ORDER (S2-B adds strategic_assault;
# C6-A adds campaign_supply after faction_economy).
const FULL_PHASES := ["begin_turn", "faction_economy", "campaign_supply", "spy",
	"enemy_base", "strategic_detection", "strategic_heat", "strategic_assault",
	"board_day_compatibility", "rival", "era", "end_turn"]

var _checks := 0
var _fails := 0
var _backup := ""
var _nested_result := {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C4_B4_TURN OK: %s" % message)
	else:
		_fails += 1
		printerr("C4_B4_TURN FAIL: %s" % message)


func _on_day_ended_nested() -> void:
	_nested_result = CampaignTurnExecutive.advance_campaign_turn("nested_b4_probe", {})


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN TURN C4 INTEGRATION VERIFY (Phase C4-B4) ---")
	print("======================================================================")

	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_test_normal_progression()
	_test_counter_only_skips_c4()
	_test_nested_reentry_single_processing()
	_test_isolation()
	_test_reset()

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
	print("PHASE C4-B4 SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL TURN C4 INTEGRATION (C4-B4) CHECKS PASSED!")
	else:
		printerr("C4-B4 TURN INTEGRATION VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _reset_c4() -> void:
	CampaignTurnExecutive.reset()
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()


func _test_normal_progression() -> void:
	_reset_c4()
	CampaignStrategicHeat.set_node_heat("node_a", 6)
	CampaignStrategicHeat.set_node_heat("node_b", 1)
	CampaignStrategicDetection.report_location("federation", "node_a", 0, "combat")

	var r1 := CampaignTurnExecutive.advance_campaign_turn("b4_probe", {})
	_check(bool(r1.get("ok", false)), "First turn ok")
	_check(CampaignTurnExecutive.get_turn() == 1, "Counter advanced to 1")
	_check((r1.get("phases", []) as Array) == FULL_PHASES, "Receipt phases match documented order")
	_check(int((r1.get("strategic_heat", {}) as Dictionary).get("decayed_nodes", -1)) == 2, "Heat receipt decayed both nodes")
	_check(int((r1.get("strategic_detection", {}) as Dictionary).get("degraded_count", -1)) == 1, "Detection receipt degraded one record")
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 5, "Heat decayed 6 -> 5 (one step)")
	_check(CampaignStrategicHeat.get_node_heat("node_b") == 0, "Heat decayed 1 -> 0 with entry erased")
	_check(not CampaignStrategicHeat.has_heat("node_b"), "Erased node reads no heat")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.SUSPECTED, "LOCATED@0 aged to SUSPECTED on turn 1")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "node_a", "Node retained through turn aging")

	var r2 := CampaignTurnExecutive.advance_campaign_turn("b4_probe", {})
	_check(bool(r2.get("ok", false)), "Second turn ok")
	_check(CampaignTurnExecutive.get_turn() == 2, "Counter advanced to 2")
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 4, "Heat decayed 5 -> 4 (one step per turn)")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.SUSPECTED, "SUSPECTED holds at age 2")

	var r3 := CampaignTurnExecutive.advance_campaign_turn("b4_probe", {})
	_check(CampaignTurnExecutive.get_turn() == 3, "Counter advanced to 3")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.UNKNOWN, "SUSPECTED expired at age 3")
	_check(CampaignStrategicDetection.get_last_known_node_id("federation") == "", "Node cleared on expiry")
	_check(bool(r3.get("ok", false)), "Third turn ok")


func _test_counter_only_skips_c4() -> void:
	_reset_c4()
	CampaignStrategicHeat.set_node_heat("node_a", 5)
	CampaignStrategicDetection.report_location("federation", "node_a", 0, "combat")
	var r := CampaignTurnExecutive.advance_campaign_turn("fine_probe", {"day_boundary": false})
	_check(bool(r.get("ok", false)), "Counter-only turn ok")
	_check(CampaignTurnExecutive.get_turn() == 1, "Counter-only turn still increments")
	_check((r.get("phases", []) as Array) == ["begin_turn", "end_turn"], "Counter-only receipt has begin/end only")
	_check(bool(r.get("strategic_detection_skipped", false)), "Receipt marks detection skipped")
	_check(bool(r.get("strategic_heat_skipped", false)), "Receipt marks heat skipped")
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 5, "Counter-only turn decays no heat")
	_check(CampaignStrategicDetection.is_located("federation"), "Counter-only turn ages no intel")


func _test_nested_reentry_single_processing() -> void:
	_reset_c4()
	CampaignStrategicHeat.set_node_heat("node_a", 6)
	CampaignStrategicDetection.report_location("federation", "node_a", 0, "combat")
	_nested_result = {}
	EventBus.board_day_ended.connect(_on_day_ended_nested)
	var r := CampaignTurnExecutive.advance_campaign_turn("reentry_b4_probe", {})
	EventBus.board_day_ended.disconnect(_on_day_ended_nested)
	_check(bool(r.get("ok", false)), "Outer turn completes despite nested attempt")
	_check(str(_nested_result.get("error", "")) == "reentrant", "Nested turn rejected with reentrant error")
	_check(CampaignTurnExecutive.get_turn() == 1, "Nested attempt added no extra turn")
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 5, "Heat decayed exactly once for one logical turn")
	_check(int((r.get("strategic_detection", {}) as Dictionary).get("degraded_count", -1)) == 1, "Detection aged exactly one stage for one logical turn")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Single aging stage applied")


func _test_isolation() -> void:
	_reset_c4()
	CampaignStrategicHeat.set_node_heat("node_a", 4)
	CampaignStrategicDetection.report_suspicion("zeon", "node_a", 0, 4, "trace")
	GlobalData.current_campaign_player_node_id = "node_a"
	var player_before := GlobalData.current_campaign_player_node_id
	var forces_before := JSON.stringify(CampaignForce.get_forces())
	var bases_before := JSON.stringify(CampaignBase.get_bases())
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	var battles_before := JSON.stringify(CampaignBattle.get_battles())
	var tactical_heat_before := 0
	var patrols_before := 0
	if GlobalData.board != null:
		tactical_heat_before = int(GlobalData.board.heat)
		patrols_before = (GlobalData.board.board_patrols as Array).size()
	var threat_before := CampaignStrategicThreat.get_node_threat("node_x", "zeon", 0)

	CampaignTurnExecutive.advance_campaign_turn("isolation_b4_probe", {})

	_check(GlobalData.current_campaign_player_node_id == player_before, "Player node untouched by C4 processing")
	_check(JSON.stringify(CampaignForce.get_forces()) == forces_before, "Forces untouched by C4 processing")
	_check(JSON.stringify(CampaignBase.get_bases()) == bases_before, "Bases untouched by C4 processing")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before, "Territories untouched by C4 processing")
	_check(JSON.stringify(CampaignBattle.get_battles()) == battles_before, "Battles untouched by C4 processing")
	if GlobalData.board != null:
		_check(int(GlobalData.board.heat) == tactical_heat_before, "Tactical heat untouched by C4 processing")
		_check((GlobalData.board.board_patrols as Array).size() == patrols_before, "Patrols untouched by C4 processing")
	var threat_after := CampaignStrategicThreat.get_node_threat("node_x", "zeon", 0)
	_check(JSON.stringify(threat_after) == JSON.stringify(threat_before), "Threat query contract intact across the turn")
	_check(CampaignStrategicHeat.get_node_heat("node_a") == 3, "Heat still decayed its one step")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Detection still aged on schedule")
	GlobalData.current_campaign_player_node_id = ""


func _test_reset() -> void:
	_reset_c4()
	CampaignStrategicHeat.set_node_heat("node_a", 7)
	CampaignStrategicDetection.report_location("federation", "node_a", 0, "combat")
	CampaignTurnExecutive.advance_campaign_turn("reset_b4_probe", {})
	GlobalData.reset_run_data()
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "reset_run_data clears strategic heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "reset_run_data clears strategic detection")
	_check(CampaignTurnExecutive.get_turn() == 0, "reset_run_data clears campaign turn")
	_check(CampaignTurnExecutive.get_last_receipt().is_empty(), "reset_run_data clears turn receipt")
	_reset_c4()
