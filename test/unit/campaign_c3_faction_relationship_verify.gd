extends Node

## ---------------------------------------------------------------------------
## VALKREN CAMPAIGN V2 — C3: FACTION / RELATIONSHIP FOUNDATION VERIFICATION
##
## Verifies:
##   1. Faction Identity Authority: Singular registry in FactionSystem, deterministic IDs.
##   2. Faction Relationship Authority: Symmetric matrix, self-allied, missing=neutral.
##   3. Player Faction Context: Canonical resolution, persistence, fallback compatibility.
##   4. Ownership Separation: Base/Territory/Force controllers remain domain-owned.
##   5. Action Domain Compatibility: Capture, Attack, and BaseDefense use canonical player faction.
##   6. Persistence & Reset Isolation: Player faction and relations survive save/load & clean reset.
## ---------------------------------------------------------------------------

const FactionSystem = preload("res://scripts/systems/faction_system.gd")
const RunStartSystem = preload("res://scripts/systems/run_start_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBattle = preload("res://scripts/systems/campaign_battle.gd")
const CampaignCaptureAction = preload("res://scripts/systems/campaign_capture_action.gd")
const CampaignAttackAction = preload("res://scripts/systems/campaign_attack_action.gd")
const CampaignBaseDefense = preload("res://scripts/systems/campaign_base_defense.gd")

var _passed_count: int = 0
var _failed_count: int = 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Faction & Relationship Foundation Verification (C3)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("CAMPAIGN_C3 OK: %s" % test_name)
	else:
		_failed_count += 1
		printerr("CAMPAIGN_C3 FAIL: %s" % test_name)


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE C3 SUMMARY: Passed: %d, Failed: %d" % [_passed_count, _failed_count])
	print("----------------------------------------------------------------------")
	if _failed_count == 0:
		print("ALL CAMPAIGN FACTION & RELATIONSHIP (C3) CHECKS PASSED!")


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
	_test_faction_identity()
	_test_faction_relationship_matrix()
	_test_player_faction_context()
	_test_ownership_separation()
	_test_action_caller_compatibility()
	_test_faction_persistence_and_isolation()


func _test_faction_identity() -> void:
	print("\n--- Test: Faction Identity Authority ---")
	_clear_all_state()
	var registered := FactionSystem.get_registered_factions()
	_check(registered.size() == 4, "Exactly 4 canonical factions registered")
	_check(registered.has("federation"), "Registered contains federation")
	_check(registered.has("zeon"), "Registered contains zeon")
	_check(registered.has("outland"), "Registered contains outland")
	_check(registered.has("scavenger"), "Registered contains scavenger")

	_check(FactionSystem.has_faction("federation"), "has_faction(federation) == true")
	_check(FactionSystem.has_faction("zeon"), "has_faction(zeon) == true")
	_check(not FactionSystem.has_faction("unknown_faction_xyz"), "has_faction(unknown) == false")
	_check(not FactionSystem.has_faction(""), "has_faction('') == false")

	var fed_def := FactionSystem.get_faction_def("federation")
	_check(fed_def.get("id") == "federation", "get_faction_def(federation) has id 'federation'")
	_check(fed_def.has("name") and fed_def.has("color"), "get_faction_def has display name and color metadata")


func _test_faction_relationship_matrix() -> void:
	print("\n--- Test: Faction Relationship Matrix & Semantics ---")
	_clear_all_state()

	# Default missing relation is NEUTRAL
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.NEUTRAL, "Unset pair defaults to NEUTRAL")
	_check(FactionSystem.is_neutral("federation", "zeon"), "is_neutral returns true for unset pair")

	# Self-relation is always ALLIED
	_check(FactionSystem.get_relation("federation", "federation") == FactionSystem.Relation.ALLIED, "Self-relation is ALLIED")
	_check(FactionSystem.is_allied("federation", "federation"), "is_allied returns true for self-pair")
	_check(not FactionSystem.set_relation("federation", "federation", FactionSystem.Relation.HOSTILE), "Setting self-relation is rejected")

	# Set relation and verify symmetric read
	var set_ok := FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	_check(set_ok, "set_relation(federation, zeon, HOSTILE) succeeds")
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.HOSTILE, "get_relation(federation, zeon) == HOSTILE")
	_check(FactionSystem.get_relation("zeon", "federation") == FactionSystem.Relation.HOSTILE, "get_relation(zeon, federation) == HOSTILE (Symmetric)")
	_check(FactionSystem.is_hostile("federation", "zeon"), "is_hostile(federation, zeon) == true")
	_check(FactionSystem.is_hostile("zeon", "federation"), "is_hostile(zeon, federation) == true")

	# Unknown faction handling
	_check(FactionSystem.get_relation("federation", "unknown_faction") == FactionSystem.Relation.NEUTRAL, "Query with unknown faction returns NEUTRAL safe default")
	_check(not FactionSystem.set_relation("federation", "unknown_faction", FactionSystem.Relation.HOSTILE), "set_relation with unknown faction is rejected")

	# Update relation to COOPERATIVE
	FactionSystem.set_relation("federation", "outland", FactionSystem.Relation.COOPERATIVE)
	_check(FactionSystem.is_cooperative("federation", "outland"), "is_cooperative(federation, outland) == true")
	_check(FactionSystem.is_cooperative("outland", "federation"), "is_cooperative(outland, federation) == true (Symmetric)")


func _test_player_faction_context() -> void:
	print("\n--- Test: Player Faction Context & Resolution ---")
	_clear_all_state()

	# Default player faction before scenario start
	_check(FactionSystem.get_player_faction() == "federation", "Default player faction falls back to 'federation'")

	# Explicitly set player faction to zeon
	var set_ok := FactionSystem.set_player_faction("zeon")
	_check(set_ok, "set_player_faction('zeon') succeeds")
	_check(FactionSystem.get_player_faction() == "zeon", "get_player_faction() returns 'zeon'")
	_check(GlobalData.current_campaign_faction_id == "zeon", "GlobalData.current_campaign_faction_id updated to 'zeon'")

	# Setting unknown player faction is rejected
	_check(not FactionSystem.set_player_faction("non_existent_faction"), "Setting unknown player faction rejected")
	_check(FactionSystem.get_player_faction() == "zeon", "Player faction unchanged after bad set attempt")

	# Reset restores fallback
	_clear_all_state()
	_check(GlobalData.current_campaign_faction_id == "", "Reset clears current_campaign_faction_id")
	_check(FactionSystem.get_player_faction() == "federation", "get_player_faction() falls back cleanly to 'federation'")


func _test_ownership_separation() -> void:
	print("\n--- Test: Ownership Separation (Faction != Base != Territory != Force) ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# In frontier_skirmish: base_frontier_garrison controller is federation
	var base := CampaignBase.get_base("base_frontier_garrison")
	_check(str(base.get("controller")) == "federation", "Base controller is federation")

	# Mutating faction relationship between federation and zeon does NOT mutate base controller
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.ALLIED)
	var base_after := CampaignBase.get_base("base_frontier_garrison")
	_check(str(base_after.get("controller")) == "federation", "Base controller remains federation after relation mutation")

	# Mutating base controller does NOT mutate faction relation
	CampaignBase.set_controller("base_frontier_garrison", "outland")
	_check(CampaignBase.get_base("base_frontier_garrison").get("controller") == "outland", "Base controller updated to outland")
	_check(FactionSystem.get_relation("federation", "zeon") == FactionSystem.Relation.ALLIED, "Faction relationship untouched by base controller change")

	# Force allegiance remains force-owned
	var force := CampaignForce.get_force("force_s1_fed_vanguard")
	_check(str(force.get("faction")) == "federation", "Force faction allegiance is federation")


func _test_action_caller_compatibility() -> void:
	print("\n--- Test: Action Caller Compatibility with Player Faction ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# When player faction is federation (default):
	_check(FactionSystem.get_player_faction() == "federation", "Player faction is federation")

	# Capture action on enemy outpost (node_frontier_outpost, base_frontier_stronghold owned by zeon)
	var cap_intent := {
		"action_id": "capture",
		"node_id": "node_frontier_outpost",
		"payload": {} # Omitting claim_faction to test default resolution
	}
	var cap_res = CampaignCaptureAction.handle_capture(cap_intent)
	_check(cap_res.get("ok", false), "Capture action succeeds using canonical player faction")
	_check(CampaignBase.get_base("base_frontier_stronghold").get("controller") == "federation", "Base captured by player faction (federation)")

	# Attack action evaluation
	# Outland force at node_frontier_depot is attackable by player (federation)
	_check(CampaignAttackAction.is_attackable_node("node_frontier_depot"), "Depot with outland force is attackable by player")

	# Base defense intervention
	# Place zeon force at city node where base_frontier_garrison is located
	CampaignForce.set_node("force_s1_zeon_raiders", "node_frontier_city")
	var def_res = CampaignBaseDefense.start_base_attack("base_frontier_garrison", "force_s1_zeon_raiders")
	_check(def_res.get("ok", false), "Base attack registered")
	var battle_id: String = str(def_res.get("battle_id", ""))
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 2) # node_frontier_city
	var int_check = CampaignBaseDefense.can_intervene(battle_id)
	_check(int_check.get("ok", false), "Player can intervene using canonical player faction")
	_check(int_check.get("player_faction") == "federation", "Intervention receipt reports canonical player faction")


func _test_faction_persistence_and_isolation() -> void:
	print("\n--- Test: Faction Persistence & Isolation ---")
	_clear_all_state()
	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Explicitly set player faction to outland and relations
	FactionSystem.set_player_faction("outland")
	FactionSystem.set_relation("outland", "zeon", FactionSystem.Relation.HOSTILE)

	# Save run
	var saved: bool = SaveGameIO.save_run()
	_check(saved, "Save run succeeds")

	# Clear runtime
	RunStartSystem._clear_campaign_runtime_state()
	_check(GlobalData.current_campaign_faction_id == "", "Reset clears player faction")
	_check(FactionSystem.get_relation("outland", "zeon") == FactionSystem.Relation.NEUTRAL, "Reset clears relation override back to default")

	# Load run
	var loaded: bool = SaveGameIO.load_run()
	_check(loaded, "Load run succeeds")
	_check(GlobalData.current_campaign_faction_id == "outland", "Loaded player faction restored to 'outland'")
	_check(FactionSystem.get_player_faction() == "outland", "FactionSystem.get_player_faction() returns 'outland'")
	_check(FactionSystem.get_relation("outland", "zeon") == FactionSystem.Relation.HOSTILE, "Loaded relation restored to HOSTILE")
