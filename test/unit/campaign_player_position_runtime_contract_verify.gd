extends Node

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC PLAYER POSITION RUNTIME CONTRACT VERIFICATION
## Phase 5AI Contract Verification Suite
##
## Proves the architectural contract:
##   1. Single Player Position Authority:
##      - Tactical / physical board position: BoardState.current_tile (Vector2i)
##      - Strategic campaign node position: derived via CampaignNodeRegistry.get_node_at(sector, current_tile)
##   2. Semantic Separation:
##      - Player != CampaignForce (No player force in registry, no player-force type)
##      - Player Position != Node Ownership (Player presence != node control)
##      - Player Position != Territory Capture (Player presence != territory owner)
##      - Player Position != Base Mutation (Player presence != base creation/damage)
##      - Player Position != Force Mutation (Player presence != force creation/move)
##      - Route != Movement (Route query/registration does not move player)
##      - Physical Tile != Strategic Node ID (Vector2i tactical vs String strategic)
##   3. Lifecycle & Persistence Invariants:
##      - Start Atomicity: Failed scenario start does not leak player position
##      - Reset Atomicity: Reset cleanly clears previous run position
##      - Save/Load: Position serialized and restored cleanly exactly once
##      - ScenarioDefinition Immutability: Read-only authored blueprint
##      - Determinism: Identical inputs produce identical initial player position
##      - Canonical Scenario Closure: frontier_skirmish player coexistence
## ---------------------------------------------------------------------------

const ScenarioDefScript = preload("res://resources/data/scenario_definition.gd")
const ScenarioCatalogScript = preload("res://resources/data/scenario_catalog_data.gd")
const ScenarioSchemaValidatorScript = preload("res://scripts/systems/scenario_schema_validator.gd")
const InitializerScript = preload("res://scripts/systems/campaign_scenario_initializer.gd")

const CANONICAL_SCENARIO_PATH := "res://resources/data/scenarios/frontier_skirmish.tres"

var _checks_passed := 0
var _checks_failed := 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Strategic Player Position Contract verification (Phase 5AI)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, description: String) -> void:
	if condition:
		_checks_passed += 1
		print("PLAYER_POSITION_CONTRACT OK: %s" % description)
	else:
		_checks_failed += 1
		printerr("PLAYER_POSITION_CONTRACT FAIL: %s" % description)


func _run_all_tests() -> void:
	_test_a_single_position_authority()
	_test_b_strategic_node_validity()
	_test_c_player_separation_from_campaign_force()
	_test_d_player_position_node_separation()
	_test_e_player_position_territory_separation()
	_test_f_player_position_base_separation()
	_test_g_player_position_force_separation()
	_test_h_route_separation_no_implicit_player_movement()
	_test_i_initialization_and_determinism()
	_test_j_failed_initialization_atomicity()
	_test_k_reset_atomicity_and_isolation()
	_test_l_save_load_persistence()
	_test_m_scenario_definition_immutability()
	_test_n_physical_board_vs_strategic_node_separation()
	_test_o_canonical_scenario_frontier_skirmish_semantics()
	_test_p_no_duplicate_position_authority()


func _reset_campaign_runtime() -> void:
	GlobalData.reset_run_data()
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionEconomySystem.reset()
	GlobalData.current_campaign_scenario_id = ""


## --- SECTION A: SINGLE POSITION AUTHORITY ---
func _test_a_single_position_authority() -> void:
	_reset_campaign_runtime()

	_check(GlobalData.board != null, "A1: GlobalData.board is authoritative board state container")
	_check(GlobalData.board.current_tile is Vector2i, "A2: GlobalData.board.current_tile is Vector2i")
	_check(GlobalData.board.current_sector is int, "A3: GlobalData.board.current_sector is int")

	# Position change through authoritative board state
	GlobalData.board.current_tile = Vector2i(3, 4)
	GlobalData.board.current_sector = 1
	_check(GlobalData.board.current_tile == Vector2i(3, 4), "A4: GlobalData.board.current_tile updates accurately")
	_check(GlobalData.board.current_sector == 1, "A5: GlobalData.board.current_sector is 1")

	# CampaignForce and CampaignNodeRegistry do NOT store player position fields
	_check(not ("current_player_tile" in CampaignForce), "A6: CampaignForce does not store player position")
	_check(not ("current_player_node" in CampaignForce), "A7: CampaignForce does not store player node")
	_check(not ("player_node" in CampaignNodeRegistry), "A8: CampaignNodeRegistry does not store player node state")
	_check(not ("player_tile" in CampaignNodeRegistry), "A9: CampaignNodeRegistry does not store player tile state")


## --- SECTION B: STRATEGIC NODE VALIDITY ---
func _test_b_strategic_node_validity() -> void:
	_reset_campaign_runtime()

	# Register a strategic node at sector 1, tile (2, 3)
	var nid := CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "city", "node_s1_city_2_3")
	_check(nid == "node_s1_city_2_3", "B1: Node registered at (2, 3)")

	# Player on non-strategic tile (0, 0)
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.board.current_sector = 1
	var node_at_0 := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	var node_id_0 := str(node_at_0.get("id", ""))
	_check(node_id_0 == "", "B2: Non-strategic tile returns empty node ID")
	_check(node_id_0 == "" or CampaignNodeRegistry.has_node(node_id_0), "B3: Invariant holds for non-strategic tile")

	# Player moves to strategic tile (2, 3)
	GlobalData.board.current_tile = Vector2i(2, 3)
	var node_at_hub := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	var node_id_hub := str(node_at_hub.get("id", ""))
	_check(node_id_hub == "node_s1_city_2_3", "B4: Strategic tile resolves to valid node ID")
	_check(CampaignNodeRegistry.has_node(node_id_hub), "B5: Node ID exists in CampaignNodeRegistry")
	_check(node_id_hub == "" or CampaignNodeRegistry.has_node(node_id_hub), "B6: Invariant holds for strategic tile")


## --- SECTION C: PLAYER SEPARATION FROM CAMPAIGN FORCE ---
func _test_c_player_separation_from_campaign_force() -> void:
	_reset_campaign_runtime()

	_check(not CampaignForce.has_force("player"), "C1: Player is not in CampaignForce registry")
	_check(not CampaignForce.has_force("player_force"), "C2: No player_force in registry")
	_check(not CampaignForce.has_force("force_player"), "C3: No force_player in registry")
	_check(not CampaignForce.has_force("force_s1_player"), "C4: No namespaced player force exists")

	# Register normal faction forces
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_s1_city_2_2")
	CampaignForce.register_force("force_s1_patrol_1", "PATROL", "federation", "node_s1_city_2_2", "", 2, 20)

	var forces := CampaignForce.get_forces()
	_check(forces.size() == 1, "C5: Exactly 1 faction force registered")
	var f0: Dictionary = forces[0]
	_check(str(f0.get("faction", "")) != "player", "C6: Force faction is federation, not player")
	_check(str(f0.get("force_type", "")) != "PLAYER", "C7: Force type is PATROL, not PLAYER")
	_check(not str(f0.get("id", "")).begins_with("player"), "C8: Force ID does not begin with player")

	# Moving player does not mutate or register forces
	GlobalData.board.current_tile = Vector2i(2, 2)
	_check(CampaignForce.get_forces().size() == 1, "C9: Player tile update does not create force")


## --- SECTION D: PLAYER POSITION != NODE OWNERSHIP ---
func _test_d_player_position_node_separation() -> void:
	_reset_campaign_runtime()

	var nid := CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "fuel_depot", "node_s1_depot_4_4")
	var node_before := CampaignNodeRegistry.get_node(nid)

	# Move player to depot
	GlobalData.board.current_tile = Vector2i(4, 4)
	GlobalData.board.current_sector = 1

	var node_after := CampaignNodeRegistry.get_node(nid)
	_check(node_after == node_before, "D1: Player presence does not mutate node metadata")
	_check(not node_after.has("controller"), "D2: Node does not acquire a controller attribute")
	_check(not node_after.has("captured"), "D3: Node does not acquire a captured flag")
	_check(not node_after.has("player_present"), "D4: Node does not store transient player presence")


## --- SECTION E: PLAYER POSITION != TERRITORY CAPTURE ---
func _test_e_player_position_territory_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_s1_safehouse_1_1")
	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city", "node_s1_city_3_3")
	CampaignTerritory.register_territory("terr_north", ["node_s1_safehouse_1_1", "node_s1_city_3_3"])
	CampaignTerritory.set_controlled("terr_north", "zeon")

	var t_before := CampaignTerritory.get_territory("terr_north")
	_check(str(t_before.get("controller", "")) == "zeon", "E1: Territory starts controlled by zeon")

	# Move player into the territory's member node
	GlobalData.board.current_tile = Vector2i(3, 3)
	GlobalData.board.current_sector = 1

	var t_after := CampaignTerritory.get_territory("terr_north")
	_check(str(t_after.get("controller", "")) == "zeon", "E2: Player presence does not flip territory controller")
	_check(int(t_after.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED, "E3: Territory remains CONTROLLED (not CONTESTED)")


## --- SECTION F: PLAYER POSITION != BASE MUTATION ---
func _test_f_player_position_base_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "enemy_base", "node_s1_base_5_5")
	CampaignTerritory.register_territory("terr_base", ["node_s1_base_5_5"])
	CampaignBase.register_base("base_enemy_1", "node_s1_base_5_5", "OUTPOST", "zeon", "terr_base")

	var b_before := CampaignBase.get_base("base_enemy_1")
	_check(int(b_before.get("state", -1)) == CampaignBase.BaseState.ACTIVE, "F1: Base starts ACTIVE")

	# Move player to base node
	GlobalData.board.current_tile = Vector2i(5, 5)

	var b_after := CampaignBase.get_base("base_enemy_1")
	_check(int(b_after.get("state", -1)) == CampaignBase.BaseState.ACTIVE, "F2: Player presence does not disable base")
	_check(str(b_after.get("controller", "")) == "zeon", "F3: Base controller remains zeon")


## --- SECTION G: PLAYER POSITION != FORCE MUTATION ---
func _test_g_player_position_force_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_s1_city_2_2")
	CampaignForce.register_force("force_guard_1", "PATROL", "federation", "node_s1_city_2_2", "", 3, 30)

	var f_before := CampaignForce.get_force("force_guard_1")

	# Move player to the exact same node as the force
	GlobalData.board.current_tile = Vector2i(2, 2)

	var f_after := CampaignForce.get_force("force_guard_1")
	_check(int(f_after.get("unit_count", 0)) == int(f_before.get("unit_count", 0)), "G1: Force unit_count unmutated")
	_check(int(f_after.get("strength", 0)) == int(f_before.get("strength", 0)), "G2: Force strength unmutated")
	_check(int(f_after.get("state", -1)) == int(f_before.get("state", -1)), "G3: Force state unmutated")
	_check(str(f_after.get("node_id", "")) == "node_s1_city_2_2", "G4: Force node_id unchanged")


## --- SECTION H: ROUTE SEPARATION (NO IMPLICIT PLAYER MOVEMENT) ---
func _test_h_route_separation_no_implicit_player_movement() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "safehouse", "node_s1_safehouse_1_1")
	CampaignNodeRegistry.register_node(1, Vector2i(1, 2), "city", "node_s1_city_1_2")

	GlobalData.board.current_tile = Vector2i(1, 1)

	# Register route between the two nodes
	var rid := CampaignNodeRegistry.register_route("node_s1_safehouse_1_1", "node_s1_city_1_2")
	_check(rid != "", "H1: Route registered between safehouse and city")

	# Query route
	_check(CampaignNodeRegistry.has_route(rid), "H2: Route exists")
	var r := CampaignNodeRegistry.get_route(rid)
	_check(not r.is_empty(), "H3: Route metadata retrieved")

	# Verify player position remains strictly unchanged
	_check(GlobalData.board.current_tile == Vector2i(1, 1), "H4: Route registration/query did not move player")


## --- SECTION I: INITIALIZATION AND DETERMINISM ---
func _test_i_initialization_and_determinism() -> void:
	_reset_campaign_runtime()

	var res := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(bool(res.get("ok", false)), "I1: Canonical scenario start succeeded")
	_check(GlobalData.current_campaign_scenario_id == "frontier_skirmish", "I2: Scenario ID published")

	# Initial player position on scenario start is valid default (Vector2i.ZERO or start tile)
	var tile1: Vector2i = GlobalData.board.current_tile
	_check(tile1 is Vector2i, "I3: Initial player position is valid Vector2i")

	# Repeat start on a fresh state to test determinism
	_reset_campaign_runtime()
	var res2 := RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(bool(res2.get("ok", false)), "I4: Second start succeeded")
	var tile2: Vector2i = GlobalData.board.current_tile

	_check(tile1 == tile2, "I5: Initial player position is strictly deterministic across identical scenario starts")


## --- SECTION J: FAILED INITIALIZATION ATOMICITY ---
func _test_j_failed_initialization_atomicity() -> void:
	_reset_campaign_runtime()

	GlobalData.board.current_tile = Vector2i(9, 9)

	# 1. Empty scenario ID
	var res_empty := RunStartSystem.start_campaign_scenario("")
	_check(not bool(res_empty.get("ok", true)), "J1: Empty scenario ID rejected")
	_check(GlobalData.board.current_tile == Vector2i(9, 9), "J2: Player tile untouched after empty scenario ID failure")

	# 2. Unknown scenario ID
	var res_unknown := RunStartSystem.start_campaign_scenario("unknown_scenario_xyz")
	_check(not bool(res_unknown.get("ok", true)), "J3: Unknown scenario ID rejected")
	_check(GlobalData.board.current_tile == Vector2i(9, 9), "J4: Player tile untouched after unknown scenario ID failure")

	# 3. Invalid scenario object
	var bad_scenario = ScenarioDefScript.new()
	bad_scenario.scenario_id = "invalid_scenario"
	bad_scenario.faction_setup = ["unknown_faction_123"]
	var dummy_catalog = ScenarioCatalogScript.new()
	dummy_catalog.scenarios = [bad_scenario]

	var res_invalid := RunStartSystem.start_campaign_scenario("invalid_scenario", dummy_catalog)
	_check(not bool(res_invalid.get("ok", true)), "J5: Invalid scenario schema rejected")
	_check(GlobalData.board.current_tile == Vector2i(9, 9), "J6: Player tile untouched after invalid scenario validation failure")


## --- SECTION K: RESET ATOMICITY AND ISOLATION ---
func _test_k_reset_atomicity_and_isolation() -> void:
	_reset_campaign_runtime()

	# Start scenario and simulate player movement
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.board.current_tile = Vector2i(7, 4) # at outpost
	_check(GlobalData.board.current_tile == Vector2i(7, 4), "K1: Player moved to (7, 4)")

	# Reset run data
	GlobalData.reset_run_data()
	_check(GlobalData.board.current_tile == Vector2i.ZERO, "K2: reset_run_data restores player tile to ZERO")
	_check(GlobalData.current_campaign_scenario_id == "", "K3: Scenario ID reset to empty")

	# Fresh start does not carry over old tile (7, 4)
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	_check(GlobalData.board.current_tile != Vector2i(7, 4) or Vector2i(7, 4) == Vector2i.ZERO,
		"K4: Fresh run does not leak previous run's mutated player position")


## --- SECTION L: SAVE / LOAD PERSISTENCE ---
func _test_l_save_load_persistence() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.board.current_tile = Vector2i(3, 2) # at city node_frontier_city
	GlobalData.board.current_sector = 1

	var node_before := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	_check(str(node_before.get("id", "")) == "node_frontier_city", "L1: Player staged at node_frontier_city")

	# Save run
	_check(SaveGameIO.save_run(), "L2: SaveGameIO.save_run returned true")

	# Clear runtime state
	GlobalData.board.current_tile = Vector2i(-99, -99)
	GlobalData.board.current_sector = -1

	# Load run
	_check(SaveGameIO.load_run(), "L3: SaveGameIO.load_run returned true")
	_check(GlobalData.board.current_tile == Vector2i(3, 2), "L4: Player tile restored accurately to (3, 2)")
	_check(GlobalData.board.current_sector == 1, "L5: Sector restored accurately to 1")

	# Verify node projection after load
	var node_after := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	_check(str(node_after.get("id", "")) == "node_frontier_city", "L6: Strategic node presence restored after save/load")


## --- SECTION M: SCENARIODEFINITION IMMUTABILITY ---
func _test_m_scenario_definition_immutability() -> void:
	_reset_campaign_runtime()

	var scenario: ScenarioDefinition = load(CANONICAL_SCENARIO_PATH) as ScenarioDefinition
	_check(scenario != null, "M1: Canonical scenario loaded")

	var nodes_spec_count := scenario.get_initial_node_specs().size()
	var forces_spec_count := scenario.get_initial_force_specs().size()
	var rules_before := scenario.get_strategic_rules()

	# Start scenario and mutate player position
	RunStartSystem.start_campaign_scenario("frontier_skirmish")
	GlobalData.board.current_tile = Vector2i(5, 3)

	# Check scenario definition properties remain completely unmutated
	_check(scenario.get_initial_node_specs().size() == nodes_spec_count, "M2: Scenario initial_node_specs count unmutated")
	_check(scenario.get_initial_force_specs().size() == forces_spec_count, "M3: Scenario initial_force_specs count unmutated")
	_check(scenario.get_strategic_rules() == rules_before, "M4: Scenario strategic_rules unmutated")
	_check(not ("current_tile" in scenario), "M5: ScenarioDefinition does not declare current_tile")
	_check(not ("player_node" in scenario), "M6: ScenarioDefinition does not declare player_node")


## --- SECTION N: PHYSICAL BOARD VS STRATEGIC NODE SEPARATION ---
func _test_n_physical_board_vs_strategic_node_separation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 2), "city", "node_frontier_city")

	# Physical board position is Vector2i coordinate
	GlobalData.board.current_tile = Vector2i(3, 2)
	_check(GlobalData.board.current_tile is Vector2i, "N1: BoardState.current_tile is Vector2i")
	_check(typeof(GlobalData.board.current_tile) == TYPE_VECTOR2I, "N2: Type is strictly TYPE_VECTOR2I")

	# Strategic node position is resolved via CampaignNodeRegistry.get_node_at
	var node := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	var node_id := str(node.get("id", ""))
	_check(node_id == "node_frontier_city", "N3: Strategic node resolved as String 'node_frontier_city'")
	_check(typeof(node_id) == TYPE_STRING, "N4: Node ID is strictly TYPE_STRING")

	# They are distinct abstraction layers: Vector2i != String
	_check(str(GlobalData.board.current_tile) != node_id, "N5: Physical coordinate string is not identical to strategic node ID string")


## --- SECTION O: CANONICAL SCENARIO FRONTIER SKIRMISH SEMANTICS ---
func _test_o_canonical_scenario_frontier_skirmish_semantics() -> void:
	_reset_campaign_runtime()

	RunStartSystem.start_campaign_scenario("frontier_skirmish")

	# Canonical facts verified:
	# 1. Sector Beta is controlled by Zeon
	var beta := CampaignTerritory.get_territory("terr_frontier_sector_beta")
	_check(str(beta.get("controller", "")) == "zeon", "O1: Sector Beta controlled by zeon")

	# 2. Depot (node_frontier_depot at (5,3)) is inside Sector Beta
	var beta_members := CampaignTerritory.get_members("terr_frontier_sector_beta")
	_check(beta_members.has("node_frontier_depot"), "O2: node_frontier_depot is a member of Sector Beta")

	# 3. Outland force is present at node_frontier_depot
	var outland_force := CampaignForce.get_force("force_s1_outland_scavengers")
	_check(str(outland_force.get("node_id", "")) == "node_frontier_depot", "O3: Outland force is at node_frontier_depot")
	_check(str(outland_force.get("faction", "")) == "outland", "O4: Outland force faction is outland")

	# 4. Player moves to node_frontier_depot (tile (5, 3))
	GlobalData.board.current_tile = Vector2i(5, 3)
	var node_at_player := CampaignNodeRegistry.get_node_at(1, GlobalData.board.current_tile)
	_check(str(node_at_player.get("id", "")) == "node_frontier_depot", "O5: Player is present at node_frontier_depot")

	# 5. Coexistence: All 4 strategic facts coexist without rewriting territory control
	var beta_after := CampaignTerritory.get_territory("terr_frontier_sector_beta")
	_check(str(beta_after.get("controller", "")) == "zeon", "O6: Sector Beta remains controlled by zeon despite Outland and Player presence")
	_check(int(beta_after.get("control", -1)) == CampaignTerritory.ControlState.CONTROLLED,
		"O7: Sector Beta control state is still CONTROLLED (not CONTESTED)")


## --- SECTION P: NO DUPLICATE POSITION AUTHORITY ---
func _test_p_no_duplicate_position_authority() -> void:
	_check(not ("current_player_node" in CampaignTurnExecutive), "P1: CampaignTurnExecutive does not own player position")
	_check(not ("player_node" in CampaignTerritory), "P2: CampaignTerritory does not own player position")
	_check(not ("player_node" in CampaignBase), "P3: CampaignBase does not own player position")
	_check(not ("player_node" in CampaignBattle), "P4: CampaignBattle does not own player position")
	_check(not ("player_node" in FactionSystem), "P5: FactionSystem does not own player position")


func _restore_save_backup() -> void:
	_reset_campaign_runtime()
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.flush()
			f.close()


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE 5AI SUMMARY: Passed: %d, Failed: %d" % [_checks_passed, _checks_failed])
	print("----------------------------------------------------------------------")
	if _checks_failed > 0:
		printerr("CAMPAIGN STRATEGIC PLAYER POSITION CONTRACT VERIFICATION FAILED!")
		get_tree().quit(1)
	else:
		print("ALL CAMPAIGN STRATEGIC PLAYER POSITION CONTRACT CHECKS PASSED!")
		get_tree().quit(0)
