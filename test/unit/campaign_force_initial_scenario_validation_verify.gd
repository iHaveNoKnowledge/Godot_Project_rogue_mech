extends Node
## PHASE 5Y CAMPAIGN INITIAL FORCE SCENARIO VALIDATION & PLACEMENT VERIFY.
##
## Proves the architectural contract established in Phase 5Y (Outcome C):
##   - A. Initial population count (explicit initialization)
##   - B. IDs deterministic
##   - C. Faction correctness (FactionSystem validated)
##   - D. Force type correctness (CampaignForce validated)
##   - E. Node placement correctness (CampaignNodeRegistry validated)
##   - F. Unit count correctness
##   - G. Strength correctness
##   - H. Per-sector behavior (namespaced deterministic IDs)
##   - I. Repeated initialization idempotency
##   - J. Save/load persistence
##   - K. Turn execution does not repopulate or alter forces
##   - L. Movement does not repopulate
##   - M. Inspection does not repopulate (read-only)
##   - N. Reset/restart behavior: live run start leaves CampaignForce unpopulated (no speculative auto-injection)
##   - O. No speculative data claimed as canonical (explicit fixture classification locked)

const CITY := "node_s1_city_2_2"
const FUEL := "node_s1_fuel_depot_2_3"
const SAFE := "node_s1_safehouse_3_2"
const LAB := "node_s1_research_lab_3_3"

const MovePanelScript = preload("res://scripts/ui/campaign_force_movement_panel.gd")
const InspectPanelScript = preload("res://scripts/ui/campaign_node_inspection_panel.gd")
const CampaignForceInitializer = preload("res://scripts/systems/campaign_force_initializer.gd")

var _fails: int = 0
var _checks: int = 0
var _backup: String = ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SCENARIO_VALIDATION OK: " + name)
	else:
		_fails += 1
		printerr("SCENARIO_VALIDATION FAIL: " + name)


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

	print("CAMPAIGN_FORCE_SCENARIO_VALIDATION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_SCENARIO_VALIDATION_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_FORCE_SCENARIO_VALIDATION_TESTS_PASSED")
		get_tree().quit(0)


func _seed_topology(sector: int = 1) -> void:
	CampaignNodeRegistry.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTerritory.clear()

	CampaignNodeRegistry.register_node(sector, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(sector, Vector2i(2, 3), "fuel_depot")
	CampaignNodeRegistry.register_node(sector, Vector2i(3, 2), "safehouse")
	CampaignNodeRegistry.register_node(sector, Vector2i(3, 3), "research_lab")

	var city_id := "node_s%d_city_2_2" % sector
	var fuel_id := "node_s%d_fuel_depot_2_3" % sector
	var safe_id := "node_s%d_safehouse_3_2" % sector
	var lab_id := "node_s%d_research_lab_3_3" % sector

	CampaignNodeRegistry.register_route(city_id, fuel_id)
	CampaignNodeRegistry.register_route(city_id, safe_id)
	CampaignNodeRegistry.register_route(safe_id, lab_id)


func _run_all_tests() -> void:
	_test_outcome_c_classification()
	_test_live_run_unpopulated_policy()
	_test_explicit_population_and_determinism()
	_test_per_sector_behavior()
	_test_idempotency_and_persistence()
	_test_lifecycle_isolation()
	_test_source_guards()


# O — Outcome C: Audit confirms no canonical scenario data exists;
# fixture data is explicitly classified as SPECULATIVE_DEVELOPMENT_FIXTURE.
func _test_outcome_c_classification() -> void:
	_check(not CampaignForceInitializer.is_canonical_scenario_data(),
		"O: CampaignForceInitializer explicitly declares data is not canonical")
	_check(CampaignForceInitializer.get_data_classification() == "SPECULATIVE_DEVELOPMENT_FIXTURE",
		"O: data classification is SPECULATIVE_DEVELOPMENT_FIXTURE")


# N — Reset & Run Start: live run start leaves CampaignForce unpopulated.
# Production runs must not silently inject speculative dummy forces.
func _test_live_run_unpopulated_policy() -> void:
	GlobalData.reset_run_data()
	_check(CampaignForce.get_forces().is_empty(),
		"N: GlobalData.reset_run_data leaves CampaignForce empty")

	RunStartSystem.roll_random_start()
	_check(CampaignForce.get_forces().is_empty(),
		"N: RunStartSystem.roll_random_start does not auto-inject speculative forces into live runs")


# A–G — Explicit initialization contract validation:
# Validates count, IDs, types, factions, nodes, unit count, and strength.
func _test_explicit_population_and_determinism() -> void:
	_seed_topology(1)
	var created_ids: Array = CampaignForceInitializer.initialize_campaign_forces(1)

	# A. Count
	_check(created_ids.size() == 3, "A: fixture initialization creates exactly 3 forces")
	_check(CampaignForce.get_forces().size() == 3, "A: CampaignForce holds all 3 registered forces")

	# B. Deterministic IDs
	_check(created_ids.has("force_s1_patrol_alpha"), "B: contains deterministic force_s1_patrol_alpha")
	_check(created_ids.has("force_s1_convoy_beta"), "B: contains deterministic force_s1_convoy_beta")
	_check(created_ids.has("force_s1_scavenger_gamma"), "B: contains deterministic force_s1_scavenger_gamma")

	# C. Faction correctness
	for fid in created_ids:
		var f: Dictionary = CampaignForce.get_force(fid)
		var fac := str(f.get("faction", ""))
		_check(FactionSystem.has_faction(fac), "C: force %s has valid canonical faction %s" % [fid, fac])

	# D. Force type correctness
	for fid in created_ids:
		var f: Dictionary = CampaignForce.get_force(fid)
		var ftype := str(f.get("force_type", ""))
		_check(CampaignForce.is_valid_type(ftype), "D: force %s has valid force_type %s" % [fid, ftype])

	# E. Node placement correctness
	for fid in created_ids:
		var f: Dictionary = CampaignForce.get_force(fid)
		var nid := str(f.get("node_id", ""))
		_check(nid != "" and CampaignNodeRegistry.has_node(nid), "E: force %s placed on real registered node %s" % [fid, nid])

	# F. Unit count correctness
	for fid in created_ids:
		var f: Dictionary = CampaignForce.get_force(fid)
		_check(int(f.get("unit_count", 0)) > 0, "F: force %s unit_count > 0" % fid)

	# G. Strength correctness
	for fid in created_ids:
		var f: Dictionary = CampaignForce.get_force(fid)
		_check(int(f.get("strength", 0)) > 0, "G: force %s strength > 0" % fid)


# H — Per-sector behavior:
# Sector parameter is respected; IDs are properly namespaced.
func _test_per_sector_behavior() -> void:
	_seed_topology(2)
	var s2_ids: Array = CampaignForceInitializer.initialize_campaign_forces(2)
	_check(s2_ids.has("force_s2_patrol_alpha"), "H: sector 2 namespaced patrol_alpha")
	_check(s2_ids.has("force_s2_convoy_beta"), "H: sector 2 namespaced convoy_beta")
	_check(s2_ids.has("force_s2_scavenger_gamma"), "H: sector 2 namespaced scavenger_gamma")


# I, J — Repeated initialization idempotency & Save/Load roundtrip.
func _test_idempotency_and_persistence() -> void:
	_seed_topology(1)
	CampaignForceInitializer.initialize_campaign_forces(1)
	var count_before := CampaignForce.get_forces().size()

	# I. Repeated initialization
	var second_run_ids: Array = CampaignForceInitializer.initialize_campaign_forces(1)
	_check(second_run_ids.size() == count_before, "I: repeated initialization produces identical count")
	_check(CampaignForce.get_forces().size() == count_before, "I: no duplicate forces created on repeated call")

	# J. Save/Load persistence
	_check(SaveGameIO.save_run(), "J: save_run succeeds")
	CampaignForce.clear()
	_check(CampaignForce.get_forces().is_empty(), "J: forces cleared from memory")
	_check(SaveGameIO.load_run(), "J: load_run succeeds")
	_check(CampaignForce.get_forces().size() == count_before, "J: all forces restored from save")
	_check(CampaignForce.has_force("force_s1_patrol_alpha"), "J: restored force_s1_patrol_alpha")


# K–M — Lifecycle isolation: Turn, Movement, Inspection do not repopulate.
func _test_lifecycle_isolation() -> void:
	_seed_topology(1)
	CampaignForceInitializer.initialize_campaign_forces(1)
	var initial_count := CampaignForce.get_forces().size()

	# K. Turn does not repopulate
	CampaignTurnExecutive.advance_campaign_turn("phase_5y_probe", {})
	_check(CampaignForce.get_forces().size() == initial_count,
		"K: campaign turn advance does not spawn or repopulate forces")

	# L. Movement does not repopulate
	var move_res: Dictionary = CampaignForceMovement.move_force("force_s1_patrol_alpha", FUEL)
	_check(bool(move_res.get("ok", false)), "L: movement executed")
	_check(CampaignForce.get_forces().size() == initial_count,
		"L: movement does not spawn or repopulate forces")

	# M. Inspection does not repopulate
	var inspect_panel: Control = InspectPanelScript.new()
	add_child(inspect_panel)
	var insp: Dictionary = inspect_panel.inspect_node(FUEL)
	_check(insp.has("forces"), "M: inspection returns forces")
	_check(CampaignForce.get_forces().size() == initial_count,
		"M: node inspection does not spawn or repopulate forces")
	inspect_panel.queue_free()


# Source guards: verify no parallel producers or duplicate classes.
func _test_source_guards() -> void:
	var forbidden := [
		"res://scripts/ui/campaign_turn_panel.gd",
		"res://scripts/ui/campaign_force_movement_panel.gd",
		"res://scripts/ui/campaign_node_inspection_panel.gd",
		"res://scripts/systems/campaign_turn_executive.gd",
		"res://scripts/systems/patrol_system.gd",
		"res://scripts/systems/spawn_manager.gd",
		"res://scripts/main/game_manager.gd",
		"res://scripts/systems/run_start_system.gd",
	]
	for path in forbidden:
		if FileAccess.file_exists(path):
			var content := FileAccess.get_file_as_string(path)
			_check(not content.contains("CampaignForceInitializer.initialize_campaign_forces("),
				"Source guard: script %s does not call initialize_campaign_forces" % path)

	_check(not FileAccess.file_exists("res://scripts/systems/campaign_force_2.gd"),
		"Source guard: no CampaignForce2 file")
	_check(not FileAccess.file_exists("res://scripts/systems/player_force.gd"),
		"Source guard: no PlayerForce file")
