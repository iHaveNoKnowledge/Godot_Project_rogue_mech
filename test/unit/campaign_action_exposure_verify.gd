extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN ACTION EXPOSURE VERIFICATION — Phase C4-B6.
##
## Tests the post-success exposure hooks that connect committed campaign
## actions to the strategic Heat / Detection authorities:
##   - Dispatch table (attack/capture/resupply/trade/investigate) fires
##     exactly once per successful execution; failures record nothing.
##   - Movement traces only changed hops entering hostile territory.
##   - Node attribution, faction attribution, suspicion-vs-location split,
##     turn neutrality, isolation, persistence, and reset behavior.
## Combat resolution has no connected production path (resolve_battle has
## zero production callers), so no hook exists there by design.
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignPlayerMovement = preload("res://scripts/systems/campaign_player_movement.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const FactionSystem = preload("res://scripts/systems/faction_system.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignBattle = preload("res://scripts/systems/campaign_battle.gd")
const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")
const CampaignStrategicDetection = preload("res://scripts/systems/campaign_strategic_detection.gd")
const CampaignStrategicThreat = preload("res://scripts/systems/campaign_strategic_threat.gd")

const CITY := "node_s1_city_2_2"
const SAFE := "node_s1_safehouse_2_3"
const DEPOT := "node_s1_fuel_depot_5_5"

var _checks := 0
var _fails := 0
var _backup := ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C4_B6_EXPOSURE OK: %s" % message)
	else:
		_fails += 1
		printerr("C4_B6_EXPOSURE FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN ACTION EXPOSURE VERIFY (Phase C4-B6) ---")
	print("======================================================================")

	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	# Gate 3A: attack dispatches now enter tactical combat; suppress the real
	# scene swap in headless runs (same pattern as the defend suite).
	GameManager.suppress_scene_change = true

	_test_attack_exposure()
	_test_capture_exposure()
	_test_resupply_trade_exposure()
	_test_investigate_no_exposure()
	_test_rejected_dispatch_no_exposure()
	_test_movement_exposure()
	_test_detection_boundaries()
	_test_turn_neutrality_and_isolation()
	_test_persistence_and_reset()

	GlobalData.reset_run_data()
	FactionSystem.reset_relations()
	CampaignBaseDefense.reset_defense_state()
	CampaignAttackBridge.reset_attack_state()
	GameManager.suppress_scene_change = false
	GameManager.transition_to(GameManager.State.BOARD)
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("----------------------------------------------------------------------")
	print("PHASE C4-B6 SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL ACTION EXPOSURE (C4-B6) CHECKS PASSED!")
	else:
		printerr("C4-B6 ACTION EXPOSURE VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionSystem.set_player_faction("federation")
	FactionSystem.set_relation("zeon", "federation", FactionSystem.Relation.HOSTILE)
	CampaignBaseDefense.reset_defense_state()
	CampaignAttackBridge.reset_attack_state()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot")
	CampaignNodeRegistry.register_route(CITY, SAFE)
	CampaignNodeRegistry.register_route(SAFE, DEPOT)
	CampaignTerritory.register_territory("terr_home", [CITY])
	CampaignTerritory.set_controlled("terr_home", "federation")
	CampaignTerritory.register_territory("terr_wild", [SAFE, DEPOT])
	CampaignTerritory.set_controlled("terr_wild", "zeon")


func _set_player(node_id: String) -> void:
	_check(CampaignPlayerMovement.set_current_node_id(node_id), "Test player positioned at %s" % node_id)


func _drain_fuel() -> void:
	GlobalData.fuel.mech_energy = 100.0
	GlobalData.fuel.convoy_fuel = 100.0


func _test_attack_exposure() -> void:
	_seed_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", CITY, "", 3, 10)
	_set_player(CITY)
	var turn := CampaignTurnExecutive.get_turn()
	var r := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", CITY))
	_check(bool(r.get("ok", false)), "Attack dispatch succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 3, "Attack records +3 heat at target node")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.LOCATED, "Defending faction LOCATED")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == CITY, "LOCATED node is the target node")
	_check(CampaignStrategicDetection.get_last_known_turn("zeon") == turn, "LOCATED stamped with live turn")
	_check(CampaignStrategicDetection.get_intelligence_source("zeon") == "direct_attack", "LOCATED source is direct_attack")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Player faction learns nothing")
	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Unrelated faction learns nothing")
	# A second successful dispatch is a second committed attack: exposure repeats (no cross-call dedup).
	var r2 := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", CITY))
	_check(bool(r2.get("ok", false)), "Repeated attack dispatch succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 6, "Each committed attack exposes once (heat 3 -> 6)")


func _test_capture_exposure() -> void:
	_seed_world()
	CampaignBase.register_base("base_cap", CITY, "OUTPOST", "zeon", "terr_home")
	_set_player(CITY)
	var turn := CampaignTurnExecutive.get_turn()
	var r := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("capture", CITY))
	_check(bool(r.get("ok", false)), "Capture dispatch succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 2, "Capture records +2 heat at target node")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Dislodged controller SUSPECTED (never LOCATED from takeover)")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == CITY, "Suspicion node is the target node")
	_check(CampaignStrategicDetection.get_last_known_turn("zeon") == turn, "Suspicion stamped with live turn")
	_check(CampaignStrategicDetection.get_intelligence_source("zeon") == "capture_takeover", "Suspicion source is capture_takeover")
	_check(CampaignStrategicDetection.get_detection_state("federation") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Claim faction gains no intel from its own capture")
	# Recapture while already owned is rejected: no further trace.
	var r2 := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("capture", CITY))
	_check(not bool(r2.get("ok", true)), "Double capture rejected")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 2, "Rejected recapture adds no heat")


func _test_resupply_trade_exposure() -> void:
	_seed_world()
	# Allied cover: no heat, no suspicion.
	_set_player(CITY)
	_drain_fuel()
	var r1 := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("resupply", CITY))
	_check(bool(r1.get("ok", false)), "Allied resupply succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 0, "Allied resupply leaves zero heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Allied resupply informs nobody")
	# Non-allied ground: heat + suspicion evaluation (pre-seeded heat 2 -> 3 meets threshold).
	_set_player(DEPOT)
	_drain_fuel()
	CampaignStrategicHeat.set_node_heat(DEPOT, 2)
	var r2 := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("resupply", DEPOT))
	_check(bool(r2.get("ok", false)), "Wild resupply succeeds")
	_check(CampaignStrategicHeat.get_node_heat(DEPOT) == 3, "Wild resupply records +1 heat")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Threshold heat elevates controller suspicion")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == DEPOT, "Suspicion node is the operation node")
	_check(not CampaignStrategicDetection.is_located("zeon"), "Heat never promotes to LOCATED")
	# Below-threshold trace: heat without suspicion (SAFEHOUSE trades, wild ground).
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	_set_player(SAFE)
	var r3 := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("trade", SAFE,
			{"operation": "sell", "item_id": "scrap", "quantity": 1}))
	# Sell requires owned scrap; fresh run starts at 0 -> rejected, no trace.
	_check(not bool(r3.get("ok", true)), "Scrapless trade sell rejected")
	_check(CampaignStrategicHeat.get_node_heat(SAFE) == 0, "Rejected trade leaves zero heat")
	GlobalData.currency.credits = 1000
	var r4 := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("trade", SAFE,
			{"operation": "buy", "item_id": "scrap", "quantity": 2}))
	_check(bool(r4.get("ok", false)), "Funded trade buy succeeds")
	_check(CampaignStrategicHeat.get_node_heat(SAFE) == 1, "Wild trade records +1 heat")
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Sub-threshold heat informs nobody")


func _test_investigate_no_exposure() -> void:
	_seed_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", CITY, "", 3, 10)
	_set_player(CITY)
	var r := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("investigate", CITY))
	_check(bool(r.get("ok", false)), "Investigate dispatch succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 0, "Covert recon leaves zero heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Investigate changes zero intel")


func _test_rejected_dispatch_no_exposure() -> void:
	_seed_world()
	_set_player(CITY)
	var bad_action := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("bombard", CITY))
	_check(not bool(bad_action.get("ok", true)), "Unknown action rejected")
	var wrong_node := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", SAFE))
	_check(not bool(wrong_node.get("ok", true)), "Player-not-at-node rejected")
	var no_handler := CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("defend", CITY))
	_check(not bool(no_handler.get("ok", true)), "Handler-less action rejected")
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "Rejected dispatches leave zero heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Rejected dispatches inform nobody")


func _test_movement_exposure() -> void:
	_seed_world()
	_set_player(CITY)
	# Entering hostile-controlled territory leaves a trace; no detection.
	var r := CampaignPlayerMovement.move_player_to_node(SAFE)
	_check(bool(r.get("ok", false)), "Movement into hostile territory succeeds")
	_check(CampaignStrategicHeat.get_node_heat(SAFE) == 1, "Hostile entry records +1 heat at destination")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 0, "Source node gains no heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Movement reports zero detection")
	# Returning to allied ground leaves no trace.
	var back := CampaignPlayerMovement.move_player_to_node(CITY)
	_check(bool(back.get("ok", false)), "Return movement succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 0, "Allied entry leaves zero heat")
	# Same-node no-op records nothing.
	var same := CampaignPlayerMovement.move_player_to_node(CITY)
	_check(bool(same.get("ok", false)) and not bool(same.get("changed", true)), "Same-node move is a no-op success")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == 0, "No-op move records no trace")
	# Failed move records nothing and moves nobody.
	var bad := CampaignPlayerMovement.move_player_to_node("node_nope")
	_check(not bool(bad.get("ok", true)), "Unknown destination rejected")
	_check(CampaignPlayerMovement.get_current_node_id() == CITY, "Failed move keeps position")
	_check(CampaignStrategicHeat.get_all_heats().size() == 1, "Failed move adds no new trace")
	# Validation-only check records nothing.
	var probe := CampaignPlayerMovement.can_move_to_node(SAFE)
	_check(bool(probe.get("ok", false)), "Validation check succeeds")
	_check(CampaignStrategicHeat.get_node_heat(SAFE) == 1, "Validation check adds no trace")


func _test_detection_boundaries() -> void:
	_seed_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", CITY, "", 3, 10)
	_set_player(CITY)
	# Suspicion then location through the real dispatch path.
	CampaignStrategicHeat.set_node_heat(CITY, 5)
	CampaignStrategicDetection.evaluate_node_trace("zeon", CITY, 5, CampaignTurnExecutive.get_turn())
	_check(CampaignStrategicDetection.get_detection_state("zeon") == CampaignStrategicDetection.DetectionState.SUSPECTED, "Trace yields SUSPECTED, not LOCATED")
	CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", CITY))
	_check(CampaignStrategicDetection.is_located("zeon"), "Attack elevates SUSPECTED to LOCATED")
	_check(CampaignStrategicDetection.get_last_known_node_id("zeon") == CITY, "LOCATED node is the target node")
	_check(CampaignStrategicDetection.get_detection_state("outland") == CampaignStrategicDetection.DetectionState.UNKNOWN, "Third faction stays UNKNOWN throughout")


func _test_turn_neutrality_and_isolation() -> void:
	_seed_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", CITY, "", 3, 10)
	CampaignBase.register_base("base_iso", CITY, "OUTPOST", "zeon", "terr_home")
	_set_player(CITY)
	var turn_before := CampaignTurnExecutive.get_turn()
	var player_before := CampaignPlayerMovement.get_current_node_id()
	CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", CITY))
	_check(CampaignTurnExecutive.get_turn() == turn_before, "Hooks never advance the turn")
	_check(CampaignPlayerMovement.get_current_node_id() == player_before, "Hooks never move the player")
	_check(CampaignForce.get_state("force_z1") == CampaignForce.ForceState.ACTIVE, "Hooks never mutate force state")
	_check(str(CampaignBase.get_base("base_iso").get("controller", "")) == "zeon", "Hooks never mutate base control")
	_check(CampaignTerritory.get_controller("terr_home") == "federation", "Hooks never mutate territory")
	_check(FactionSystem.get_relation("zeon", "federation") == FactionSystem.Relation.HOSTILE, "Hooks never mutate relations")
	# Threat derives from hook outputs without any threat-side mutation.
	var t1 := CampaignStrategicThreat.get_node_threat(CITY, "federation", CampaignTurnExecutive.get_turn())
	var t2 := CampaignStrategicThreat.get_node_threat(CITY, "federation", CampaignTurnExecutive.get_turn())
	_check(JSON.stringify(t1) == JSON.stringify(t2), "Threat reads hook outputs deterministically")


func _test_persistence_and_reset() -> void:
	_seed_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", CITY, "", 3, 10)
	_set_player(CITY)
	CampaignPlayerDispatch.dispatch_intent(
		CampaignPlayerDispatch.create_intent("attack", CITY))
	_check(SaveGameIO.save_run(), "Post-hook save succeeds")
	var heat_before := CampaignStrategicHeat.get_node_heat(CITY)
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	_check(SaveGameIO.load_run(), "Post-hook load succeeds")
	_check(CampaignStrategicHeat.get_node_heat(CITY) == heat_before, "Hook heat survives save/load")
	_check(CampaignStrategicDetection.is_located("zeon"), "Hook intel survives save/load")
	GlobalData.reset_run_data()
	_check(CampaignStrategicHeat.get_all_heats().is_empty(), "Reset clears hook heat")
	_check(CampaignStrategicDetection.get_all_intelligence().is_empty(), "Reset clears hook intel")
	FactionSystem.reset_relations()
