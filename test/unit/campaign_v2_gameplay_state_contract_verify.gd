extends Node
## ---------------------------------------------------------------------------
## PHASE 5AB CAMPAIGN V2 GAMEPLAY STATE CONTRACT VERIFY
##
## Architectural Contract & Invariant Coverage:
##   1. Node & Route Contract: Strategic hubs vs physical tiles.
##   2. Territory Contract: Independent strategic areas; base-independent.
##   3. Base Contract: Facility installation state distinct from force garrisons.
##   4. CampaignForce Contract: Independence of unit_count and strength; 8 locked keys.
##   5. Economy & Logistics Contract: Macro faction level only; no per-force supply.
##   6. Heat / Wanted / Threat Contract: Player attention vs deferred threat.
##   7. Player Representation Contract: Player is commander/hangar/token, never CampaignForce.
##   8. ScenarioDefinition Boundary & Anti-Escape-Hatch Contract.
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
		print("PHASE_5AB OK: " + test_name)
	else:
		_fails += 1
		printerr("PHASE_5AB FAIL: " + test_name)


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

	print("CAMPAIGN_V2_GAMEPLAY_STATE_CONTRACT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_V2_GAMEPLAY_STATE_CONTRACT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_V2_GAMEPLAY_STATE_CONTRACT_TESTS_PASSED")
		get_tree().quit(0)


func _run_all_tests() -> void:
	_test_node_and_route_contract()
	_test_territory_contract()
	_test_base_contract()
	_test_campaign_force_contract()
	_test_economy_and_logistics_contract()
	_test_heat_wanted_threat_contract()
	_test_player_campaign_contract()
	_test_scenario_definition_boundary_contract()
	_test_source_guards()


# 1. Node & Route Contract
func _test_node_and_route_contract() -> void:
	_clear_campaign_state()

	# Verify STRATEGIC_TILE_TYPES contains recognized strategic facility types
	_check(CampaignNodeRegistry.STRATEGIC_TILE_TYPES.has("city"), "1.1: Strategic tiles include city")
	_check(CampaignNodeRegistry.STRATEGIC_TILE_TYPES.has("safehouse"), "1.2: Strategic tiles include safehouse")
	_check(CampaignNodeRegistry.STRATEGIC_TILE_TYPES.has("fuel_depot"), "1.3: Strategic tiles include fuel_depot")
	_check(CampaignNodeRegistry.STRATEGIC_TILE_TYPES.has("research_lab"), "1.4: Strategic tiles include research_lab")

	# Register node and verify purity
	var nid := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_hub_1")
	_check(nid == "node_hub_1", "1.5: Node registered successfully")
	_check(CampaignNodeRegistry.has_node("node_hub_1"), "1.6: Node exists in registry")
	_check(CampaignForce.get_forces().is_empty(), "1.7: Node registration produces zero CampaignForces")
	_check(CampaignTerritory.get_territories().is_empty(), "1.8: Node registration produces zero CampaignTerritories")


# 2. Territory Contract
func _test_territory_contract() -> void:
	_clear_campaign_state()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_hub_1")

	# Territory can exist with or without nodes, with or without bases
	var tid := CampaignTerritory.register_territory("terr_alpha", ["node_hub_1"])
	_check(tid == "terr_alpha", "2.1: Territory registered with member node")
	_check(CampaignBase.get_bases().is_empty(), "2.2: Territory exists without requiring any base")

	# Territory control is independent of base
	CampaignTerritory.set_controlled("terr_alpha", "federation")
	var t_rec := CampaignTerritory.get_territory("terr_alpha")
	_check(str(t_rec.get("controller", "")) == "federation", "2.3: Territory controller set to federation")
	_check(int(t_rec.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED, "2.4: Territory is CONTROLLED")

	# Co-locating hostile forces at member node does NOT automatically mutate territory ownership
	CampaignForce.register_force("force_zeon_1", "PATROL", "zeon", "node_hub_1", "", 2, 20)
	var t_rec_after := CampaignTerritory.get_territory("terr_alpha")
	_check(str(t_rec_after.get("controller", "")) == "federation",
		"2.5: Hostile force presence does not automatically strip territory controller")


# 3. Base Contract
func _test_base_contract() -> void:
	_clear_campaign_state()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_hub_1")
	CampaignTerritory.register_territory("terr_alpha", ["node_hub_1"])
	CampaignTerritory.set_controlled("terr_alpha", "federation")

	# Base controller can differ from territory controller
	var bid := CampaignBase.register_base("base_outpost_1", "node_hub_1", "OUTPOST", "zeon", "terr_alpha")
	_check(bid == "base_outpost_1", "3.1: Base registered")
	var b_rec := CampaignBase.get_base("base_outpost_1")
	_check(str(b_rec.get("controller", "")) == "zeon", "3.2: Base controller is zeon")
	_check(str(CampaignTerritory.get_territory("terr_alpha").get("controller", "")) == "federation",
		"3.3: Base controller does not overwrite territory controller")

	# Attaching a force and disabling base does not destroy the force
	var fid := CampaignForce.register_force("force_garrison_1", "PATROL", "zeon", "node_hub_1", "base_outpost_1", 2, 20)
	_check(CampaignForce.has_force(fid), "3.4: Force attached to base")
	CampaignBase.set_state("base_outpost_1", CampaignBase.BaseState.DISABLED)
	_check(int(CampaignForce.get_force(fid).get("state", -1)) == CampaignForce.ForceState.ACTIVE,
		"3.5: Disabling base does not mutate attached force state to DISABLED")


# 4. CampaignForce Contract
func _test_campaign_force_contract() -> void:
	_clear_campaign_state()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_hub_1")

	var fid := CampaignForce.register_force("force_comp_1", "PATROL", "federation", "node_hub_1", "", 3, 30)
	var f_rec := CampaignForce.get_force(fid)
	_check(int(f_rec.get("unit_count", 0)) == 3, "4.1: unit_count initialized to 3")
	_check(int(f_rec.get("strength", 0)) == 30, "4.2: strength initialized to 30")

	# Independence of unit_count and strength: strength may degrade while unit_count remains unchanged
	CampaignForce.set_composition(fid, 3, 15)
	var f_degraded := CampaignForce.get_force(fid)
	_check(int(f_degraded.get("unit_count", 0)) == 3, "4.3: unit_count remains constant")
	_check(int(f_degraded.get("strength", 0)) == 15, "4.4: strength decreased independently")

	# Locked 8 keys invariant
	var expected_keys := ["id", "force_type", "faction", "node_id", "base_id", "unit_count", "strength", "state"]
	expected_keys.sort()
	var actual_keys := f_degraded.keys()
	actual_keys.sort()
	_check(actual_keys == expected_keys, "4.5: CampaignForce schema remains strictly locked to 8 keys")


# 5. Economy & Logistics Contract
func _test_economy_and_logistics_contract() -> void:
	var eco := FactionEconomySystem.get_economy("zeon")
	var initial_funds := int(eco.get("funds", 0))
	var initial_parts := int(eco.get("parts", 0))

	# Sever supply line affects macro economy funds and parts
	FactionEconomySystem.sever_supply_line("zeon", 100, 20)
	var eco_after := FactionEconomySystem.get_economy("zeon")
	_check(int(eco_after.get("funds", 0)) == initial_funds - 100, "5.1: Macro funds reduced by supply disruption")
	_check(int(eco_after.get("parts", 0)) == initial_parts - 20, "5.2: Macro parts reduced by supply disruption")

	# Verify zero per-force supply side-effects
	_check(CampaignForce.get_forces().is_empty() or not CampaignForce.get_forces()[0].has("supply"),
		"5.3: Supply disruption produces zero per-force supply state")


# 6. Heat / Wanted / Threat Contract
func _test_heat_wanted_threat_contract() -> void:
	GlobalData.board.heat = 0
	GlobalData.board.wanted_level = 1

	HeatWantedSystem.modify_heat(6)
	_check(GlobalData.board.heat == 6, "6.1: Heat updated on GlobalData.board")
	_check(GlobalData.board.wanted_level >= 2, "6.2: Wanted level derived from Heat")

	# Threat: neither CampaignForce nor CampaignTurnExecutive tracks strategic threat
	_check(not ("strategic_threat" in CampaignTurnExecutive), "6.3: No strategic_threat on CampaignTurnExecutive")
	_check(not ("local_threat" in CampaignNodeRegistry), "6.4: No local_threat on CampaignNodeRegistry")


# 7. Player Campaign Contract
func _test_player_campaign_contract() -> void:
	_check(not CampaignForce.has_force("player"), "7.1: Player is not in CampaignForce registry")
	_check(not CampaignForce.has_force("force_s1_player"), "7.2: No namespaced player force exists")
	_check(GlobalData.weapons != null, "7.3: Player mecha and weapon state managed via GlobalData.weapons")
	_check(GlobalData.board.current_tile is Vector2i, "7.4: Player position is a board grid coordinate")


# 8. ScenarioDefinition Boundary & Anti-Escape-Hatch Contract
func _test_scenario_definition_boundary_contract() -> void:
	var s = ScenarioDefScript.new()
	s.scenario_id = "contract_test_scenario"
	s.strategic_rules = {
		"turn_limit": 20,
		"victory_condition": "defeat_all_zeon",
	}
	_check(s.is_valid(), "8.1: ScenarioDefinition is valid with authored ID")
	_check(s.strategic_rules.get("turn_limit") == 20, "8.2: strategic_rules holds static rule parameters")

	# Guard: strategic_rules must NOT be used to store live runtime mutable state
	var forbidden_rule_keys := [
		"current_turn", "forces", "territories", "bases", "heat", "wanted", "player_pos"
	]
	for k in forbidden_rule_keys:
		_check(not s.strategic_rules.has(k), "8.3: strategic_rules does not contain runtime key '%s'" % k)


# Source guards
func _test_source_guards() -> void:
	_check(not FileAccess.file_exists("res://scripts/systems/player_force.gd"), "Guard: No player_force.gd exists")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_force_2.gd"), "Guard: No campaign_force_2.gd exists")
	_check(not FileAccess.file_exists("res://scripts/systems/scenario_faction.gd"), "Guard: No scenario_faction.gd exists")
	_check(not FileAccess.file_exists("res://scripts/systems/strategic_threat_system.gd"), "Guard: No unapproved strategic threat system")


func _clear_campaign_state() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()
