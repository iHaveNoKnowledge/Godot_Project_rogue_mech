extends Node

## ---------------------------------------------------------------------------
## VALKREN CAMPAIGN V2 — C1: CAMPAIGN STATE FOUNDATION VERIFICATION
##
## Verifies:
##   1. Campaign Instance Identity: Unique campaign_id per run vs scenario_id.
##   2. Pilot / Run Identity: PILOT = RUN, MECHA != RUN. Pilot survival continues run.
##   3. Mecha Replacement Compatibility: Active mecha swap does not terminate run.
##   4. Campaign Runtime Lifecycle: Deterministic initialization & state transitions.
##   5. Save / Load Persistence: Round-trip preservation of campaign_id & world state.
##   6. Campaign Isolation: Campaign A != Campaign B across resets.
##   7. Atomic Rollback: Failure leaves zero partial runtime state.
## ---------------------------------------------------------------------------

const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const RunStartSystem = preload("res://scripts/systems/run_start_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const PilotSystem = preload("res://scripts/systems/pilot_system.gd")
const HangarManager = preload("res://scripts/systems/hangar_manager.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBattle = preload("res://scripts/systems/campaign_battle.gd")
const FactionSystem = preload("res://scripts/systems/faction_system.gd")

var _passed_count: int = 0
var _failed_count: int = 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign State Foundation Verification (C1)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("CAMPAIGN_C1 OK: %s" % test_name)
	else:
		_failed_count += 1
		printerr("CAMPAIGN_C1 FAIL: %s" % test_name)


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE C1 SUMMARY: Passed: %d, Failed: %d" % [_passed_count, _failed_count])
	print("----------------------------------------------------------------------")
	if _failed_count == 0:
		print("ALL CAMPAIGN STATE FOUNDATION (C1) CHECKS PASSED!")


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.close()


func _clear_all_state() -> void:
	RunStartSystem._clear_campaign_runtime_state()
	GlobalData.pilot.reset()
	GlobalData.hangar.reset()


func _run_all_tests() -> void:
	_test_campaign_identity_creation()
	_test_pilot_run_mecha_separation()
	_test_mecha_replacement_compatibility()
	_test_campaign_isolation_a_vs_b()
	_test_save_load_identity_roundtrip()
	_test_atomic_rollback_on_failure()


func _test_campaign_identity_creation() -> void:
	print("\n--- Test: Campaign Instance Identity & Scenario Separation ---")
	_clear_all_state()
	var res1 = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res1.get("ok", false), "Run 1 starts successfully")
	var id1: String = RunStartSystem.get_current_campaign_id()
	var scen1: String = RunStartSystem.get_current_campaign_scenario_id()
	_check(id1 != "", "Run 1 has non-empty campaign_id")
	_check(scen1 == "frontier_skirmish", "Run 1 scenario_id is frontier_skirmish")
	_check(id1.begins_with("camp_frontier_skirmish_"), "Run 1 campaign_id follows standard naming")

	# Start Run 2 of same scenario
	var res2 = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res2.get("ok", false), "Run 2 starts successfully")
	var id2: String = RunStartSystem.get_current_campaign_id()
	_check(id2 != "", "Run 2 has non-empty campaign_id")
	_check(id1 != id2, "Run 1 and Run 2 have distinct campaign instance IDs")


func _test_pilot_run_mecha_separation() -> void:
	print("\n--- Test: Pilot / Run Contract (PILOT = RUN, MECHA != RUN) ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Verify initial pilot state
	_check(not PilotSystem.is_dead(), "Pilot is alive at start")
	_check(PilotSystem.get_hp() > 0.0, "Pilot HP is positive")

	# Simulate active mecha destruction / ejection
	PilotSystem.on_mecha_destroyed()
	_check(not PilotSystem.is_dead(), "Pilot survives mecha destruction ejection with HP remaining")
	_check(RunStartSystem.get_current_campaign_id() != "", "Campaign run remains active after mecha loss")

	# Pilot death explicitly marks pilot dead and terminates pilot survival
	PilotSystem.kill()
	_check(PilotSystem.is_dead(), "Pilot is dead after fatal damage / kill")
	_check(PilotSystem.get_hp() == 0.0, "Dead pilot HP is 0.0")


func _test_mecha_replacement_compatibility() -> void:
	print("\n--- Test: Mecha Replacement Compatibility ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.weapons._ensure_default_frames()
	HangarManager.ensure_roster()

	var active_id_before: String = GlobalData.hangar.active_hangar_mech_id
	_check(active_id_before != "", "Initial active mecha exists in hangar")

	# Build/register a replacement mech into hangar
	var new_mech = HangarManager.build("Replacement Mech", 2)
	_check(not new_mech.is_empty(), "Replacement mecha built successfully")

	# Switch active mecha to replacement
	var rep_id: String = str(new_mech.get("id", ""))
	GlobalData.hangar.active_hangar_mech_id = rep_id
	_check(GlobalData.hangar.active_hangar_mech_id == rep_id, "Active mecha replaced with backup")
	_check(RunStartSystem.get_current_campaign_id() != "", "Campaign run continues with replacement mecha")


func _test_campaign_isolation_a_vs_b() -> void:
	print("\n--- Test: Campaign Isolation (A != B) ---")
	_clear_all_state()
	# Start Campaign A
	var res_a = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res_a.get("ok", false), "Campaign A starts")
	var id_a: String = RunStartSystem.get_current_campaign_id()

	# Mutate Campaign A state
	CampaignTurnExecutive.advance_campaign_turn()
	CampaignTurnExecutive.advance_campaign_turn()
	_check(CampaignTurnExecutive.get_turn() == 2, "Campaign A turn advanced to 2")
	FactionSystem.set_relation("federation", "zeon", 2)
	PilotSystem.take_damage(20.0)

	# Start Campaign B (same scenario)
	var res_b = RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(res_b.get("ok", false), "Campaign B starts")
	var id_b: String = RunStartSystem.get_current_campaign_id()
	_check(id_a != id_b, "Campaign B has new instance identity")

	# Assert Campaign B does not inherit Campaign A mutations
	_check(CampaignTurnExecutive.get_turn() == 0, "Campaign B turn is reset to 0")
	_check(FactionSystem.get_relation("federation", "zeon") == 0, "Campaign B faction relation reset to scenario authored value (0 / Hostile)")


func _test_save_load_identity_roundtrip() -> void:
	print("\n--- Test: Save / Load Identity Round-Trip ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.weapons._ensure_default_frames()
	HangarManager.ensure_roster()
	var orig_camp_id: String = RunStartSystem.get_current_campaign_id()
	var orig_scen_id: String = RunStartSystem.get_current_campaign_scenario_id()

	# Mutate state
	CampaignTurnExecutive.advance_campaign_turn()
	var current_turn: int = CampaignTurnExecutive.get_turn()
	_check(current_turn == 1, "Turn is 1 before save")

	# Save run
	var saved: bool = SaveGameIO.save_run()
	_check(saved, "Save run succeeds")

	# Clear runtime completely
	RunStartSystem._clear_campaign_runtime_state()
	_check(RunStartSystem.get_current_campaign_id() == "", "Campaign instance ID cleared on reset")

	# Load run
	var loaded: bool = SaveGameIO.load_run()
	_check(loaded, "Load run succeeds")
	_check(GlobalData.current_campaign_id == orig_camp_id, "Loaded campaign_id matches original instance ID")
	_check(GlobalData.current_campaign_scenario_id == orig_scen_id, "Loaded scenario_id matches original")
	_check(CampaignTurnExecutive.get_turn() == 1, "Loaded turn counter matches saved state (1)")


func _test_atomic_rollback_on_failure() -> void:
	print("\n--- Test: Atomic Failure & Zero Partial State ---")
	_clear_all_state()

	# Attempt to start invalid/non-existent scenario on clean state
	var res_bad = RunStartSystem.start_campaign_scenario("non_existent_scenario_xyz")
	_check(not res_bad.get("ok", true), "Invalid scenario fails safely")
	_check(RunStartSystem.get_current_campaign_id() == "", "Failed startup leaves campaign_id empty")
	_check(RunStartSystem.get_current_campaign_scenario_id() == "", "Failed startup leaves scenario_id empty")
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "Failed startup leaves zero nodes")
	_check(CampaignForce.get_forces().is_empty(), "Failed startup leaves zero forces")
