extends Node
## PHASE 5X CAMPAIGN FORCE INITIAL POPULATION v1 VERIFY.
##
## Proves the deterministic initial population contract for CampaignForce:
##   - Fresh Run: initial population exists upon initialization (A)
##   - Deterministic Count: identical count across fresh runs (B)
##   - Deterministic IDs: identical IDs across fresh runs (C)
##   - Valid Types: all force types valid under CampaignForce (D)
##   - Valid Factions: all factions valid under FactionSystem (E)
##   - Valid Nodes: all nodes exist in CampaignNodeRegistry (F)
##   - Valid Bases: any base link exists in CampaignBase (G)
##   - Composition: unit_count and strength match specifications (H)
##   - Idempotency: repeated initialization produces no duplicate records (I)
##   - Reset: GlobalData.reset_run_data clears forces cleanly (J)
##   - Reinitialize: clean population recreates identically after reset (K)
##   - Save/Load: roundtrip preserves initial forces and prevents re-init duplication (L)
##   - Movement Integration: initial force can move via CampaignForceMovement (M)
##   - Inspection Integration: initial force visible via CampaignNodeInspectionPanel (N)
##   - Turn Integration: End Turn creates no duplicate forces (O)
##   - Turn Mutation Guard: End Turn does not alter force identity/composition (P)
##   - No Player Force: no player force fabricated (Q)
##   - No Patrol Bridge: board_patrols not bridged to CampaignForce (R)
##   - No Tactical Bridge: no combat session / tactical spawn dependency (S)
##   - No Supply state (T)
##   - No Detection state (U)
##   - No Orders state (V)
##   - Source Guards: no forbidden producers or duplicate classes (W, X)

const CITY := "node_s1_city_2_2"
const FUEL := "node_s1_fuel_depot_2_3"
const SAFE := "node_s1_safehouse_3_2"
const LAB := "node_s1_research_lab_3_3"

const MovePanelScript = preload("res://scripts/ui/campaign_force_movement_panel.gd")
const InspectPanelScript = preload("res://scripts/ui/campaign_node_inspection_panel.gd")
const TurnPanelScript = preload("res://scripts/ui/campaign_turn_panel.gd")
const CampaignForceInitializer = preload("res://scripts/systems/campaign_force_initializer.gd")

var _fails: int = 0
var _checks: int = 0
var _backup: String = ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("INIT_POP OK: " + name)
	else:
		_fails += 1
		printerr("INIT_POP FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()

	_run_all_tests()

	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)

	print("CAMPAIGN_FORCE_INITIAL_POPULATION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_INITIAL_POPULATION_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_FORCE_INITIAL_POPULATION_TESTS_PASSED")
		get_tree().quit(0)


func _seed_topology() -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "fuel_depot")
	CampaignNodeRegistry.register_node(1, Vector2i(3, 2), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "research_lab")

	CampaignNodeRegistry.register_route(CITY, FUEL)
	CampaignNodeRegistry.register_route(CITY, SAFE)
	CampaignNodeRegistry.register_route(SAFE, LAB)

	CampaignBase.register_base("base_s1_city_post", CITY, "OUTPOST", "zeon")


func _run_all_tests() -> void:
	_test_fresh_run_and_determinism()
	_test_idempotency_and_reset()
	_test_save_load_lifecycle()
	_test_movement_and_inspection_ui()
	_test_turn_integration_and_mutation_guards()
	_test_semantic_invariants()
	_test_source_guards()


func _test_fresh_run_and_determinism() -> void:
	_seed_topology()
	var created_ids := CampaignForceInitializer.initialize_campaign_forces(1)

	# A — Fresh Run
	_check(not created_ids.is_empty(), "A: initial force population exists upon initialization")
	_check(CampaignForce.get_forces().size() == created_ids.size(), "A: all created forces registered in CampaignForce")

	# B — Deterministic Count
	_check(created_ids.size() == 3, "B: deterministic initial count is exactly 3")

	# C — Deterministic IDs
	_check(created_ids.has("force_s1_patrol_alpha"), "C: contains force_s1_patrol_alpha")
	_check(created_ids.has("force_s1_convoy_beta"), "C: contains force_s1_convoy_beta")
	_check(created_ids.has("force_s1_scavenger_gamma"), "C: contains force_s1_scavenger_gamma")

	# D — Valid Types
	for fid in created_ids:
		var f := CampaignForce.get_force(fid)
		var ftype := str(f.get("force_type", ""))
		_check(CampaignForce.is_valid_type(ftype), "D: force %s has valid force_type %s" % [fid, ftype])

	# E — Valid Factions
	for fid in created_ids:
		var f := CampaignForce.get_force(fid)
		var faction := str(f.get("faction", ""))
		_check(FactionSystem.has_faction(faction), "E: force %s has canonical faction %s" % [fid, faction])

	# F — Valid Nodes
	for fid in created_ids:
		var f := CampaignForce.get_force(fid)
		var nid := str(f.get("node_id", ""))
		_check(nid != "" and CampaignNodeRegistry.has_node(nid), "F: force %s placed on real node %s" % [fid, nid])

	# G — Valid Bases
	for fid in created_ids:
		var f := CampaignForce.get_force(fid)
		var bid := str(f.get("base_id", ""))
		if bid != "":
			_check(CampaignBase.has_base(bid), "G: force %s references registered base %s" % [fid, bid])
		else:
			_check(true, "G: force %s has empty base link" % fid)

	# H — Composition
	var f_alpha := CampaignForce.get_force("force_s1_patrol_alpha")
	_check(int(f_alpha.get("unit_count", 0)) == 2 and int(f_alpha.get("strength", 0)) == 20,
		"H: patrol_alpha composition matches spec (unit_count=2, strength=20)")
	var f_beta := CampaignForce.get_force("force_s1_convoy_beta")
	_check(int(f_beta.get("unit_count", 0)) == 3 and int(f_beta.get("strength", 0)) == 30,
		"H: convoy_beta composition matches spec (unit_count=3, strength=30)")
	var f_gamma := CampaignForce.get_force("force_s1_scavenger_gamma")
	_check(int(f_gamma.get("unit_count", 0)) == 1 and int(f_gamma.get("strength", 0)) == 10,
		"H: scavenger_gamma composition matches spec (unit_count=1, strength=10)")


func _test_idempotency_and_reset() -> void:
	# I — No Duplicate on repeated initialization
	var second_run_ids := CampaignForceInitializer.initialize_campaign_forces(1)
	_check(second_run_ids.size() == 3, "I: repeated initialization returns same 3 IDs")
	_check(CampaignForce.get_forces().size() == 3, "I: total forces in registry remains exactly 3 without duplication")

	# J — Reset
	GlobalData.reset_run_data()
	_check(CampaignForce.get_forces().is_empty(), "J: GlobalData.reset_run_data clears campaign forces")

	# K — Reinitialize
	_seed_topology()
	var reinit_ids := CampaignForceInitializer.initialize_campaign_forces(1)
	_check(reinit_ids.size() == 3, "K: reinitializing fresh run recreates 3 forces")
	_check(reinit_ids.has("force_s1_patrol_alpha"), "K: reinit contains force_s1_patrol_alpha")


func _test_save_load_lifecycle() -> void:
	# L — Save/Load
	_seed_topology()
	CampaignForceInitializer.initialize_campaign_forces(1)
	_check(SaveGameIO.save_run(), "L: save_run reports success with initial forces")

	CampaignForce.clear()
	_check(CampaignForce.get_forces().is_empty(), "L: CampaignForce cleared before load")

	_check(SaveGameIO.load_run(), "L: load_run reports success")
	_check(CampaignForce.get_forces().size() == 3, "L: loaded run restored all 3 initial forces")
	_check(CampaignForce.has_force("force_s1_patrol_alpha"), "L: restored patrol_alpha")

	# Verify initializer called after load does not duplicate or mutate
	var post_load_ids := CampaignForceInitializer.initialize_campaign_forces(1)
	_check(post_load_ids.size() == 3, "L: initializer post-load returns 3 IDs")
	_check(CampaignForce.get_forces().size() == 3, "L: post-load forces count remains exactly 3")


func _test_movement_and_inspection_ui() -> void:
	_seed_topology()
	CampaignForceInitializer.initialize_campaign_forces(1)

	# M — Movement Integration
	var move_res := CampaignForceMovement.move_force("force_s1_patrol_alpha", FUEL)
	_check(bool(move_res.get("ok", false)), "M: initial force patrol_alpha moved along route to FUEL")
	var f_alpha_moved := CampaignForce.get_force("force_s1_patrol_alpha")
	_check(str(f_alpha_moved.get("node_id", "")) == FUEL, "M: patrol_alpha node_id updated to destination")

	# N — Inspection Integration
	var inspect_panel: Control = InspectPanelScript.new()
	add_child(inspect_panel)
	var insp: Dictionary = inspect_panel.inspect_node(FUEL)
	_check(insp.has("forces"), "N: inspect_node returns forces array")
	var forces_at_fuel: Array = insp.get("forces", [])
	var found_alpha := false
	for f in forces_at_fuel:
		if str(f.get("id", "")) == "force_s1_patrol_alpha":
			found_alpha = true
	_check(found_alpha, "N: inspection panel displays initial force at FUEL node")
	inspect_panel.queue_free()

	# X — Fresh Movement Panel Integration
	var move_panel: Control = MovePanelScript.new()
	add_child(move_panel)
	var available_forces: Array = move_panel.refresh_forces()
	_check(available_forces.size() == 3, "X: fresh movement panel lists all 3 canonical forces")
	_check(available_forces.has("force_s1_patrol_alpha"), "X: movement panel contains patrol_alpha")
	move_panel.queue_free()


func _test_turn_integration_and_mutation_guards() -> void:
	_seed_topology()
	CampaignForceInitializer.initialize_campaign_forces(1)
	var pre_forces := CampaignForce.get_forces()

	# O — Turn Integration: End Turn does not duplicate forces
	var turn_receipt := CampaignTurnExecutive.advance_campaign_turn("test_5x_turn", {})
	_check(bool(turn_receipt.get("ok", false)), "O: campaign turn advanced successfully")
	_check(CampaignForce.get_forces().size() == 3, "O: End Turn does not produce or duplicate forces")

	# P — Turn Mutation Guard: End Turn does not alter force attributes
	var post_forces := CampaignForce.get_forces()
	for i in range(pre_forces.size()):
		var pre: Dictionary = pre_forces[i]
		var fid := str(pre.get("id", ""))
		var post := CampaignForce.get_force(fid)
		_check(str(pre.get("node_id", "")) == str(post.get("node_id", "")),
			"P: force %s node_id unchanged across turn" % fid)
		_check(int(pre.get("unit_count", 0)) == int(post.get("unit_count", 0)),
			"P: force %s unit_count unchanged across turn" % fid)
		_check(int(pre.get("strength", 0)) == int(post.get("strength", 0)),
			"P: force %s strength unchanged across turn" % fid)
		_check(int(pre.get("state", 0)) == int(post.get("state", 0)),
			"P: force %s state unchanged across turn" % fid)


func _test_semantic_invariants() -> void:
	# Q — No Player Force
	for f in CampaignForce.get_forces():
		var fid := str(f.get("id", ""))
		_check(not fid.begins_with("player") and not fid.contains("player"),
			"Q: force %s is not a fabricated player force" % fid)

	# R — No Patrol Bridge
	GlobalData.board.board_patrols = [{"id": 9999, "faction": "hostile", "tier": 1}]
	var ids_before := CampaignForce.get_forces().size()
	CampaignForceInitializer.initialize_campaign_forces(1)
	var ids_after := CampaignForce.get_forces().size()
	_check(ids_before == ids_after, "R: board_patrols has no bridge or effect on CampaignForce")
	_check(not CampaignForce.has_force("force_s1_9999"), "R: no patrol ID bridged to CampaignForce")

	# S — No Tactical Bridge / CombatSession dependencies
	_check(not ClassDB.class_exists("CombatSession"), "S: no CombatSession class dependency")

	# T — No Supply State
	for f in CampaignForce.get_forces():
		_check(not f.has("supply") and not f.has("logistics"), "T: no supply state in %s" % f.get("id"))

	# U — No Detection State
	for f in CampaignForce.get_forces():
		_check(not f.has("detection") and not f.has("stealth"), "U: no detection state in %s" % f.get("id"))

	# V — No Orders State
	for f in CampaignForce.get_forces():
		_check(not f.has("orders") and not f.has("mission") and not f.has("ai"),
			"V: no orders or AI state in %s" % f.get("id"))


func _test_source_guards() -> void:
	# W — Source Guard: check that forbidden scripts do not register CampaignForce
	var forbidden_scripts := [
		"res://scripts/ui/campaign_turn_panel.gd",
		"res://scripts/ui/campaign_force_movement_panel.gd",
		"res://scripts/ui/campaign_node_inspection_panel.gd",
		"res://scripts/systems/campaign_turn_executive.gd",
		"res://scripts/systems/patrol_system.gd",
		"res://scripts/systems/spawn_manager.gd",
		"res://scripts/main/game_manager.gd",
	]
	for path in forbidden_scripts:
		if FileAccess.file_exists(path):
			var content := FileAccess.get_file_as_string(path)
			_check(not content.contains("register_force("),
				"W: script %s does not call register_force" % path)

	# Source guard: No CampaignForce2 or PlayerForce
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_force_2.gd"),
		"W: no CampaignForce2 file exists")
	_check(not FileAccess.file_exists("res://scripts/systems/player_force.gd"),
		"W: no PlayerForce file exists")
