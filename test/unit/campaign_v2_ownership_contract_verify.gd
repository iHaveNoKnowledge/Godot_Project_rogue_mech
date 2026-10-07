extends Node
## ---------------------------------------------------------------------------
## PHASE 5AA CAMPAIGN V2 SCENARIO CONTRACT & STATE OWNERSHIP VERIFY
##
## Architectural Contract & Ownership Locks:
##   1. ScenarioDefinition Schema: Authored starting facts only, no runtime state.
##   2. Faction Authority: FactionSystem is sole identity owner; no ScenarioFaction.
##   3. Board vs Topology Boundary: BoardGenerator is physical grid; CampaignNodeRegistry is topology.
##   4. Force Schema Lock: Exactly 8 keys; no individual supply/orders/detection/threat.
##   5. Threat & Heat Boundary: Heat/Wanted are player attention; strategic threat is deferred.
##   6. Economy & Logistics Boundary: Faction macro-level only; no per-force supply state.
##   7. Player Boundary: Player is Hangar/Pilot/Token; never CampaignForce.
##   8. Save/Load Boundary: Runtime dictionaries serialized; ScenarioDefinition is immutable.
##   9. Zero Speculative Data: Catalog empty; CampaignForceInitializer is test fixture.
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")

var _checks: int = 0
var _fails: int = 0
var _backup_save: String = ""


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("PHASE_5AA OK: " + test_name)
	else:
		_fails += 1
		printerr("PHASE_5AA FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup_save = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_run_all_tests()

	GlobalData.reset_run_data()
	if _backup_save != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup_save)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("CAMPAIGN_V2_OWNERSHIP_CONTRACT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_V2_OWNERSHIP_CONTRACT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_V2_OWNERSHIP_CONTRACT_TESTS_PASSED")
		get_tree().quit(0)


func _run_all_tests() -> void:
	_test_scenario_definition_boundary()
	_test_faction_authority_boundary()
	_test_board_vs_topology_boundary()
	_test_force_schema_locks()
	_test_threat_and_heat_boundary()
	_test_economy_and_logistics_boundary()
	_test_player_boundary()
	_test_save_load_boundary()
	_test_zero_speculative_data_lock()
	_test_source_guards()


# 1. ScenarioDefinition Schema: Authored starting facts only, no runtime state.
func _test_scenario_definition_boundary() -> void:
	var s = ScenarioDefScript.new()
	_check(s != null, "1.1: ScenarioDefinition instantiates")

	# Forbidden runtime fields on ScenarioDefinition
	var forbidden_runtime_props := [
		"current_turn", "turn", "current_heat", "heat", "wanted",
		"threat", "current_threat", "current_supply", "supply",
		"player_pos", "player_mecha", "hangar", "event_history",
		"active_battles", "casualties", "current_controller"
	]
	for prop in forbidden_runtime_props:
		_check(not (prop in s), "1.2: ScenarioDefinition does not contain runtime field '%s'" % prop)

	# Allowed authored fields
	var required_authored_props := [
		"scenario_id", "display_name", "description",
		"faction_setup", "initial_force_specs", "initial_node_specs",
		"initial_territory_specs", "initial_base_specs",
		"initial_relationships", "strategic_rules"
	]
	for prop in required_authored_props:
		_check(prop in s, "1.3: ScenarioDefinition contains authored contract field '%s'" % prop)


# 2. Faction Authority Boundary: FactionSystem is sole identity owner
func _test_faction_authority_boundary() -> void:
	var registered_factions: Array = FactionSystem.get_registered_factions()
	_check(registered_factions.size() >= 4, "2.1: FactionSystem provides canonical registered factions")
	_check(registered_factions.has("federation"), "2.2: FactionSystem contains 'federation'")
	_check(registered_factions.has("zeon"), "2.3: FactionSystem contains 'zeon'")
	_check(registered_factions.has("outland"), "2.4: FactionSystem contains 'outland'")
	_check(registered_factions.has("scavenger"), "2.5: FactionSystem contains 'scavenger'")

	# Ensure no parallel faction definition classes exist
	_check(not FileAccess.file_exists("res://scripts/systems/scenario_faction.gd"), "2.6: No ScenarioFaction class")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_faction.gd"), "2.7: No CampaignFaction class")
	_check(not FileAccess.file_exists("res://scripts/systems/faction_definition_2.gd"), "2.8: No FactionDefinition2 class")


# 3. Board vs Topology Boundary: BoardGenerator vs CampaignNodeRegistry
func _test_board_vs_topology_boundary() -> void:
	_clear_campaign_state()

	# BoardGenerator is physical grid generation
	var bg_script_path := "res://scripts/board/board_generator.gd"
	_check(FileAccess.file_exists(bg_script_path), "3.1: BoardGenerator script exists")
	var bg_content := FileAccess.get_file_as_string(bg_script_path)
	_check(not bg_content.contains("CampaignForce.register_force"),
		"3.2: BoardGenerator does not register CampaignForces")
	_check(not bg_content.contains("CampaignTerritory.register_territory"),
		"3.3: BoardGenerator does not register CampaignTerritories")

	# Strategic topology is CampaignNodeRegistry
	_check(CampaignNodeRegistry.get_nodes().is_empty(), "3.4: CampaignNodeRegistry is clean before registration")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_test_city")
	_check(CampaignNodeRegistry.has_node("node_test_city"), "3.5: CampaignNodeRegistry registers node")
	_check(CampaignForce.get_forces().is_empty(), "3.6: Registering node does not create CampaignForce")


# 4. Force Schema Lock: Exactly 8 keys; no individual supply/orders/detection/threat
func _test_force_schema_locks() -> void:
	_clear_campaign_state()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_test_city")

	var fid := CampaignForce.register_force("force_s1_audit_1", "PATROL", "zeon", "node_test_city", "", 2, 20)
	_check(fid == "force_s1_audit_1", "4.1: Force registers successfully")

	var rec := CampaignForce.get_force(fid)
	var expected_keys := ["id", "force_type", "faction", "node_id", "base_id", "unit_count", "strength", "state"]
	expected_keys.sort()
	var actual_keys := rec.keys()
	actual_keys.sort()
	_check(actual_keys == expected_keys, "4.2: Force record schema matches locked 8 keys exactly")

	# Forbidden runtime fields on CampaignForce
	var forbidden_force_fields := [
		"supply", "supplies", "fuel", "detection", "detected", "order",
		"orders", "mission", "target", "threat", "casualties", "allegiance_history"
	]
	for f in forbidden_force_fields:
		_check(not rec.has(f), "4.3: CampaignForce has no '%s' field" % f)


# 5. Threat & Heat Boundary: Heat/Wanted are player attention; strategic threat is deferred
func _test_threat_and_heat_boundary() -> void:
	_check("heat" in GlobalData.board, "5.1: GlobalData.board owns heat")
	_check("wanted_level" in GlobalData.board, "5.2: GlobalData.board owns wanted_level")

	# Strategic threat is not on CampaignTurnExecutive
	_check(not ("threat" in CampaignTurnExecutive), "5.3: CampaignTurnExecutive has no threat property")
	_check(not ("strategic_threat" in CampaignTurnExecutive), "5.4: CampaignTurnExecutive has no strategic_threat")


# 6. Economy & Logistics Boundary: Faction macro-level only
func _test_economy_and_logistics_boundary() -> void:
	var eco := FactionEconomySystem.get_economy("federation")
	_check(eco.has("funds"), "6.1: Faction economy tracks funds")
	_check(eco.has("parts"), "6.2: Faction economy tracks parts")
	_check(eco.has("supply_status"), "6.3: Faction economy tracks supply_status")

	# Faction economy does not hold CampaignForce references
	_check(not eco.has("forces"), "6.4: Faction economy does not store CampaignForces")


# 7. Player Boundary: Player is Hangar/Pilot/Token; never CampaignForce
func _test_player_boundary() -> void:
	_check(not CampaignForce.has_force("player"), "7.1: CampaignForce('player') does not exist")
	_check(not CampaignForce.has_force("force_s1_player"), "7.2: No namespaced player force exists")
	_check(not FileAccess.file_exists("res://scripts/systems/player_force.gd"), "7.3: No player_force.gd exists")
	_check(GlobalData.weapons != null, "7.4: Player weapons/hangar state exists on GlobalData.weapons")
	_check(GlobalData.pilot != null, "7.5: Player pilot state exists on GlobalData.pilot")


# 8. Save/Load Boundary: Runtime dictionaries serialized; ScenarioDefinition is immutable
func _test_save_load_boundary() -> void:
	var save_keys := SaveGameIO.CURRENT_SCHEMA_VERSION
	_check(save_keys == 1, "8.1: Save schema version is 1")

	# Verify serialized campaign state is plain dictionary data
	var forces_snap = CampaignForce.serialize()
	_check(forces_snap is Dictionary, "8.2: CampaignForce.serialize returns Dictionary")
	var terr_snap = CampaignTerritory.serialize()
	_check(terr_snap is Dictionary, "8.3: CampaignTerritory.serialize returns Dictionary")
	var base_snap = CampaignBase.serialize()
	_check(base_snap is Dictionary, "8.4: CampaignBase.serialize returns Dictionary")


# 9. Zero Speculative Data Lock: Catalog empty; CampaignForceInitializer is test fixture
func _test_zero_speculative_data_lock() -> void:
	var catalog_res = load("res://resources/data/scenario_definition_catalog.tres")
	_check(catalog_res != null, "9.1: Scenario catalog resource loads")
	_check(catalog_res.is_empty(), "9.2: Canonical scenario catalog is explicitly empty")
	_check(CampaignForceInitializer.get_data_classification() == "SPECULATIVE_DEVELOPMENT_FIXTURE",
		"9.3: CampaignForceInitializer is SPECULATIVE_DEVELOPMENT_FIXTURE")
	_check(not CampaignForceInitializer.is_canonical_scenario_data(),
		"9.4: CampaignForceInitializer is not canonical scenario data")


# Source guards
func _test_source_guards() -> void:
	var forbidden_files := [
		"res://scripts/systems/player_force.gd",
		"res://scripts/systems/campaign_force_2.gd",
		"res://scripts/systems/scenario_faction.gd",
		"res://scripts/systems/faction_definition_2.gd",
	]
	for p in forbidden_files:
		_check(not FileAccess.file_exists(p), "Guard: %s does not exist" % p)


func _clear_campaign_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
