extends Node
## TECHNOLOGY DIFFUSION VERIFICATION (PHASE 2E-1)
## Validates the World Technology Diffusion Data Model & Query Engine:
## 1. Diffusion category taxonomy & metadata registration
## 2. Timeline authority query (EraProgressionSystem integration)
## 3. Era phase diffusion queries & coexistence (no obsolescence)
## 4. World availability vs. world diffusion distinction
## 5. Prototype-only technology & active prototype tracking
## 6. Strict separation between World State and Player Discovery
## 7. Faction access queries & RivalProgressionSystem integration
## 8. Missing diffusion requirements evaluation
## 9. Runtime diffusion activation & overrides
## 10. Save / load serialization & deserialization

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const EraProgSys = preload("res://scripts/systems/era_progression_system.gd")
const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("DIFF_OK: " + test_name)
	else:
		_fails += 1
		printerr("DIFF_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY DIFFUSION VERIFICATION (PHASE 2E-1) ===")
	_test_diffusion_metadata_and_categories()
	_test_era_diffusion_and_coexistence()
	_test_world_availability_and_prototypes()
	_test_strict_separation_player_knowledge()
	_test_faction_access_queries()
	_test_missing_diffusion_requirements()
	_test_runtime_activation_and_overrides()
	_test_serialization_and_save_load()

	print("\n=== TECHNOLOGY DIFFUSION TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_TECHNOLOGY_DIFFUSION_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("SOME_TECHNOLOGY_DIFFUSION_TESTS_FAILED")
		get_tree().quit(1)


func _test_diffusion_metadata_and_categories() -> void:
	print("\n-- [1] Diffusion Metadata & Categories --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()

	var def_ballistic := TechSys.get_technology_definition("tech_ballistic_conventional")
	_check(def_ballistic.has("diffusion_metadata"), "[1a] Definition contains diffusion_metadata")
	var diff_ballistic: Dictionary = def_ballistic.get("diffusion_metadata", {})
	_check(diff_ballistic.get("category", "") == TechSys.CATEGORY_CONVENTIONAL, "[1b] Ballistics categorized as conventional")
	_check(bool(diff_ballistic.get("default_diffused", false)), "[1c] Conventional ballistics is default_diffused")

	var def_bridge := TechSys.get_technology_definition("tech_modular_energy_interface")
	var diff_bridge: Dictionary = def_bridge.get("diffusion_metadata", {})
	_check(diff_bridge.get("category", "") == TechSys.CATEGORY_MIXED, "[1d] Modular energy interface categorized as mixed")

	var def_beam := TechSys.get_technology_definition("tech_beam_weaponry")
	var diff_beam: Dictionary = def_beam.get("diffusion_metadata", {})
	_check(diff_beam.get("category", "") == TechSys.CATEGORY_EXPERIMENTAL, "[1e] Beam weaponry categorized as experimental")
	_check(bool(diff_beam.get("prototype_only", false)), "[1f] Beam weaponry is prototype_only")

	var conventionals := TechSys.get_technologies_by_diffusion_category(TechSys.CATEGORY_CONVENTIONAL)
	_check(conventionals.size() >= 4, "[1g] Conventional category query returns at least 4 baseline techs")

	var mixeds := TechSys.get_technologies_by_diffusion_category(TechSys.CATEGORY_MIXED)
	_check(mixeds.size() >= 2, "[1h] Mixed category query returns transitional/bridge techs")

	var experimentals := TechSys.get_technologies_by_diffusion_category(TechSys.CATEGORY_EXPERIMENTAL)
	_check(experimentals.size() >= 3, "[1i] Experimental category query returns prototype/advanced techs")


func _test_era_diffusion_and_coexistence() -> void:
	print("\n-- [2] Era Diffusion & Technological Coexistence --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()

	_check(EraProgSys.current_phase == EraProgSys.EraPhase.PHASE_1_TACTICAL, "[2a] Baseline Era is Phase 1 Tactical")

	# In Era 1:
	_check(TechSys.is_technology_diffused_in_world("tech_ballistic_conventional"), "[2b] Gen 1 ballistics is diffused in Era 1")
	_check(TechSys.is_technology_diffused_in_world("tech_combustion_power"), "[2c] Gen 1 combustion is diffused in Era 1")
	_check(not TechSys.is_technology_diffused_in_world("tech_modular_energy_interface"), "[2d] Gen 2 interface not diffused in Era 1")
	_check(not TechSys.is_technology_diffused_in_world("tech_valkryon_actuator_chassis"), "[2e] Gen 3 chassis not diffused in Era 1")

	# Advance to Era 2 (Turn 16):
	EraProgSys.advance_war_turn(15)
	_check(EraProgSys.current_phase == EraProgSys.EraPhase.PHASE_2_ENERGY, "[2f] War calendar reaches Phase 2 Energy")

	# In Era 2: Gen 2 interface diffuses, AND Gen 1 remains diffused (Coexistence!)
	_check(TechSys.is_technology_diffused_in_world("tech_modular_energy_interface"), "[2g] Gen 2 interface diffuses in Era 2")
	_check(TechSys.is_technology_diffused_in_world("tech_ballistic_conventional"), "[2h] Gen 1 ballistics remains diffused in Era 2 (no obsolescence)")
	_check(TechSys.is_technology_diffused_in_world("tech_combustion_power"), "[2i] Gen 1 combustion remains diffused in Era 2")
	_check(not TechSys.is_technology_diffused_in_world("tech_valkryon_actuator_chassis"), "[2j] Gen 3 chassis still not diffused in Era 2")

	# Hypothetical phase query:
	var phase1_diffused := TechSys.get_diffused_technologies_for_phase(1)
	var phase2_diffused := TechSys.get_diffused_technologies_for_phase(2)
	_check(phase1_diffused.size() < phase2_diffused.size(), "[2k] Phase 2 has more diffused technologies than Phase 1")
	_check(phase1_diffused.size() >= 4, "[2l] Phase 1 hypothetical has all conventional baselines")

	EraProgSys.reset()


func _test_world_availability_and_prototypes() -> void:
	print("\n-- [3] World Availability vs Prototype Tracking --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# tech_beam_weaponry is prototype_only
	_check(not TechSys.is_technology_diffused_in_world("tech_beam_weaponry"), "[3a] Beam tech is not widely diffused")
	_check(not TechSys.is_technology_prototype_active("tech_beam_weaponry"), "[3b] Beam prototype is initially inactive")

	# Activate prototype directly in world:
	TechSys.set_technology_prototype_active("tech_beam_weaponry", true)
	_check(TechSys.is_technology_prototype_active("tech_beam_weaponry"), "[3c] Prototype active flag is true")
	_check(TechSys.is_technology_available_in_world("tech_beam_weaponry"), "[3d] Technology is available in world via prototype")
	_check(not TechSys.is_technology_diffused_in_world("tech_beam_weaponry"), "[3e] Technology is STILL not generally diffused")

	# Clear direct prototype flag:
	TechSys.set_technology_prototype_active("tech_beam_weaponry", false)
	_check(not TechSys.is_technology_prototype_active("tech_beam_weaponry"), "[3f] Direct prototype flag cleared")

	# Activate through RivalProgressionSystem active_prototype:
	RivalProgSys.active_prototype = {
		"name": "Test Prototype",
		"tech_id": "tech_beam_weaponry"
	}
	_check(TechSys.is_technology_prototype_active("tech_beam_weaponry"), "[3g] TechnologySystem detects active prototype from RivalProgressionSystem")
	_check(TechSys.is_technology_available_in_world("tech_beam_weaponry"), "[3h] Available in world while fielded by Rival")

	RivalProgSys.reset()


func _test_strict_separation_player_knowledge() -> void:
	print("\n-- [4] Strict Separation of World State & Player Knowledge --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	TechSys.reset_discovery_states()
	EraProgSys.reset()

	# 1. World has diffused technology, but player has UNKNOWN
	TechSys.set_discovery_state("tech_combustion_power", TechSys.DiscoveryState.UNKNOWN)
	_check(TechSys.is_technology_diffused_in_world("tech_combustion_power"), "[4a] World has combustion diffused")
	_check(TechSys.get_discovery_state("tech_combustion_power") == TechSys.DiscoveryState.UNKNOWN, "[4b] Player knowledge remains UNKNOWN independently")

	# 2. Player discovers and researches a technology, world diffusion does NOT automatically change
	_check(not TechSys.is_technology_diffused_in_world("tech_beam_weaponry"), "[4c] Beam tech is not diffused in world")
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.USABLE)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.USABLE, "[4d] Player unlocked USABLE for beam")
	_check(not TechSys.is_technology_diffused_in_world("tech_beam_weaponry"), "[4e] World diffusion is untouched by player USABLE state")

	# 3. Resetting player discovery does not alter world diffusion
	TechSys.reset_discovery_states()
	_check(TechSys.is_technology_diffused_in_world("tech_ballistic_conventional"), "[4f] World diffusion untouched by player discovery reset")


func _test_faction_access_queries() -> void:
	print("\n-- [5] Faction Access Queries --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# In Era 1, all factions have conventional ballistics
	var rival_techs := TechSys.get_faction_available_technologies(TechSys.FACTION_RIVAL)
	var convoy_techs := TechSys.get_faction_available_technologies(TechSys.FACTION_CONVOY)
	_check(rival_techs.size() >= 4, "[5a] Rival has conventional tech access in Era 1")
	_check(convoy_techs.size() >= 4, "[5b] Convoy has conventional tech access in Era 1")

	# Grant faction-specific tech:
	TechSys.grant_faction_technology(TechSys.FACTION_CONVOY, "tech_beam_weaponry")
	var updated_convoy := TechSys.get_faction_available_technologies(TechSys.FACTION_CONVOY)
	var convoy_has_beam := false
	for t in updated_convoy:
		if t.get("tech_id", "") == "tech_beam_weaponry":
			convoy_has_beam = true
			break
	_check(convoy_has_beam, "[5c] Convoy has access to explicitly granted tech")

	# Check Rival lab tier unlock:
	RivalProgSys.lab_tier = 2
	var updated_rival := TechSys.get_faction_available_technologies(TechSys.FACTION_RIVAL)
	var rival_has_beam := false
	for t in updated_rival:
		if t.get("tech_id", "") == "tech_beam_weaponry":
			rival_has_beam = true
			break
	_check(rival_has_beam, "[5d] Rival lab tier 2 unlocks beam weaponry for rival")

	RivalProgSys.reset()


func _test_missing_diffusion_requirements() -> void:
	print("\n-- [6] Missing Diffusion Requirements Evaluation --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()

	var reqs_beam := TechSys.get_missing_diffusion_requirements("tech_beam_weaponry")
	_check(reqs_beam.has("insufficient_era_phase"), "[6a] Beam tech reports insufficient era phase in Era 1")
	_check(reqs_beam.has("prototype_only_not_diffused"), "[6b] Beam tech reports prototype_only requirement")

	var reqs_ballistic := TechSys.get_missing_diffusion_requirements("tech_ballistic_conventional")
	_check(reqs_ballistic.is_empty(), "[6c] Diffused tech has 0 missing requirements")


func _test_runtime_activation_and_overrides() -> void:
	print("\n-- [7] Runtime Diffusion Activation & Overrides --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()

	_check(not TechSys.is_technology_diffused_in_world("tech_valkryon_actuator_chassis"), "[7a] Gen 3 chassis not diffused initially")

	# Force-activate in world:
	var ok := TechSys.activate_technology_diffusion("tech_valkryon_actuator_chassis")
	_check(ok, "[7b] Activation call returned true")
	_check(TechSys.is_technology_diffused_in_world("tech_valkryon_actuator_chassis"), "[7c] Gen 3 chassis is now diffused via override")

	# Deactivate:
	TechSys.deactivate_technology_diffusion("tech_valkryon_actuator_chassis")
	_check(not TechSys.is_technology_diffused_in_world("tech_valkryon_actuator_chassis"), "[7d] Gen 3 chassis deactivated")

	TechSys.reset_world_diffusion_state()


func _test_serialization_and_save_load() -> void:
	print("\n-- [8] Serialization & Save/Load Integration --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()

	TechSys.activate_technology_diffusion("tech_cryo_cooling")
	TechSys.set_technology_prototype_active("tech_high_energy_barrier", true)
	TechSys.grant_faction_technology(TechSys.FACTION_CONVOY, "tech_beam_weaponry")

	var serialized: Dictionary = TechSys.serialize_world_diffusion_state()
	_check(serialized.has("overrides"), "[8a] Serialized state contains overrides")
	_check(serialized.has("prototypes"), "[8b] Serialized state contains prototypes")
	_check(serialized.has("faction_technologies"), "[8c] Serialized state contains faction_technologies")

	# Reset and verify restoration:
	TechSys.reset_world_diffusion_state()
	_check(not TechSys.is_technology_prototype_active("tech_high_energy_barrier"), "[8d] State cleared on reset")

	TechSys.deserialize_world_diffusion_state(serialized)
	_check(TechSys.is_technology_diffused_in_world("tech_cryo_cooling"), "[8e] Override restored from serialized state")
	_check(TechSys.is_technology_prototype_active("tech_high_energy_barrier"), "[8f] Prototype restored from serialized state")

	var convoy_techs := TechSys.get_faction_available_technologies(TechSys.FACTION_CONVOY)
	var has_beam := false
	for t in convoy_techs:
		if t.get("tech_id", "") == "tech_beam_weaponry":
			has_beam = true
			break
	_check(has_beam, "[8g] Faction grant restored from serialized state")

	# Test empty / malformed deserialization safe default:
	TechSys.deserialize_world_diffusion_state({})
	_check(not TechSys.is_technology_prototype_active("tech_high_energy_barrier"), "[8h] Empty dictionary safely clears state")
