extends Node
## TECHNOLOGY RESEARCH SCHEMA & ECONOMY BOUNDARY VERIFICATION (PHASE 2E-4A)
## Validates:
## 1. Explicit research_metadata is preserved in register_technology() and get_technology_definition().
## 2. Default research_metadata is cleanly populated when omitted.
## 3. Partial custom metadata overrides specific fields while falling back to defaults for others.
## 4. Existing catalog baseline technologies return valid metadata schemas.
## 5. TechnologySystem does not directly mutate GlobalData.currency during research lifecycle actions.
## 6. can_afford_research and can_afford_identification read-only queries work without side effects.
## 7. FleetSystem legacy blueprint research remains independent and authoritative for data-core projects.
## 8. End-to-end lifecycle progression works cleanly with custom metadata.

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FleetSys = preload("res://scripts/systems/fleet_system.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("SCHEMA_ECON_OK: " + test_name)
	else:
		_fails += 1
		printerr("SCHEMA_ECON_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY RESEARCH SCHEMA & ECONOMY BOUNDARY VERIFICATION (PHASE 2E-4A) ===")
	_test_explicit_research_metadata_registration()
	_test_default_research_metadata_fallback()
	_test_partial_metadata_override()
	_test_existing_catalog_technologies_metadata()
	_test_economy_boundary_non_mutation()
	_test_fleet_system_legacy_data_cores_isolation()
	_test_lifecycle_transitions_with_custom_metadata()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_4A_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_4A_FAILED")
		get_tree().quit(1)


func _test_explicit_research_metadata_registration() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_custom_schema_test"
	var custom_meta := {
		"research_cost": 350.0,
		"research_time": 5.0,
		"required_evidence": 4.0,
		"required_materials": {"superconductor": 2, "quantum_lens": 1},
		"required_facility": "orbital_lab",
		"identification_cost": 75.0,
		"prerequisites": ["tech_beam_weaponry"]
	}
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Custom Schema Test Tech",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"era_phase_req": 2,
		"origin_lineage": TechSys.LINEAGE_COMMON,
		"tags": ["energy", "custom", "test"],
		"prerequisites": ["tech_beam_weaponry"],
		"research_metadata": custom_meta
	})

	var def := TechSys.get_technology_definition(test_id)
	_check(def.has("research_metadata"), "[1a] Definition retains research_metadata dictionary")
	var saved_meta: Dictionary = def.get("research_metadata", {})
	_check(saved_meta.get("research_cost") == 350.0, "[1b] Preserved explicit research_cost")
	_check(saved_meta.get("research_time") == 5.0, "[1c] Preserved explicit research_time")
	_check(saved_meta.get("required_evidence") == 4.0, "[1d] Preserved explicit required_evidence")
	_check(saved_meta.get("required_facility") == "orbital_lab", "[1e] Preserved explicit required_facility")
	_check(saved_meta.get("identification_cost") == 75.0, "[1f] Preserved explicit identification_cost")
	_check(saved_meta.get("required_materials").get("superconductor") == 2, "[1g] Preserved explicit required_materials")

	var meta := TechSys.get_research_metadata(test_id)
	_check(meta.get("research_cost") == 350.0, "[1h] get_research_metadata returns custom research_cost")
	_check(meta.get("research_time") == 5.0, "[1i] get_research_metadata returns custom research_time")
	_check(meta.get("required_evidence") == 4.0, "[1j] get_research_metadata returns custom required_evidence")
	_check(meta.get("required_facility") == "orbital_lab", "[1k] get_research_metadata returns custom required_facility")
	_check(meta.get("identification_cost") == 75.0, "[1l] get_research_metadata returns custom identification_cost")


func _test_default_research_metadata_fallback() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_default_schema_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Default Schema Test Tech",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"tags": ["ballistic", "default"],
		"prerequisites": ["tech_ballistic_conventional"]
	})

	var def := TechSys.get_technology_definition(test_id)
	_check(def.has("research_metadata"), "[2a] Registered def has research_metadata key")
	_check((def.get("research_metadata") as Dictionary).is_empty(), "[2b] Omitted metadata registers as empty dictionary")

	var meta := TechSys.get_research_metadata(test_id)
	_check(meta.get("research_cost") == 100.0, "[2c] Default research_cost is 100.0")
	_check(meta.get("research_time") == 1.0, "[2d] Default research_time is 1.0")
	_check(meta.get("required_evidence") == 1.0, "[2e] Default required_evidence is 1.0")
	_check((meta.get("required_materials") as Dictionary).is_empty(), "[2f] Default required_materials is empty")
	_check(meta.get("required_facility") == "", "[2g] Default required_facility is empty string")
	_check(meta.get("identification_cost") == 0.0, "[2h] Default identification_cost is 0.0")
	_check(meta.get("prerequisites") == ["tech_ballistic_conventional"], "[2i] Prerequisites fallback to top-level definition prerequisites")


func _test_partial_metadata_override() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_partial_schema_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Partial Schema Test Tech",
		"generation": 1,
		"technology_family": TechSys.FAMILY_COOLING,
		"era_phase_req": 1,
		"origin_lineage": TechSys.LINEAGE_COMMON,
		"tags": ["cooling", "partial"],
		"prerequisites": [],
		"research_metadata": {
			"research_cost": 220.0,
			"identification_cost": 45.0
		}
	})

	var meta := TechSys.get_research_metadata(test_id)
	_check(meta.get("research_cost") == 220.0, "[3a] Overridden research_cost returns 220.0")
	_check(meta.get("identification_cost") == 45.0, "[3b] Overridden identification_cost returns 45.0")
	_check(meta.get("research_time") == 1.0, "[3c] Unspecified research_time falls back to 1.0")
	_check(meta.get("required_evidence") == 1.0, "[3d] Unspecified required_evidence falls back to 1.0")
	_check((meta.get("required_materials") as Dictionary).is_empty(), "[3e] Unspecified required_materials falls back to empty dict")


func _test_existing_catalog_technologies_metadata() -> void:
	TechSys.reset_discovery_states()
	TechSys.init_catalog_if_needed()
	var baseline_techs := [
		"tech_ballistic_conventional",
		"tech_combustion_power",
		"tech_passive_cooling",
		"tech_hydraulic_actuation",
		"tech_reinforced_plating",
		"tech_relic_excavation_core",
		"tech_modular_energy_interface",
		"tech_beam_weaponry",
		"tech_cryo_cooling",
		"tech_valkryon_actuator_chassis",
		"tech_high_energy_barrier"
	]
	var all_valid := true
	for tid in baseline_techs:
		var meta := TechSys.get_research_metadata(tid)
		if meta.is_empty() or not meta.has("research_cost") or not meta.has("required_evidence"):
			all_valid = false
			break
	_check(all_valid, "[4a] All baseline catalog technologies expose valid research metadata schemas")


func _test_economy_boundary_non_mutation() -> void:
	TechSys.reset_discovery_states()
	var tech_id := "tech_econ_test"
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Econ Test Tech",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"tags": ["test"],
		"prerequisites": [],
		"research_metadata": {
			"research_cost": 300.0,
			"identification_cost": 50.0
		}
	})

	# Set baseline currency
	if GlobalData and GlobalData.currency:
		GlobalData.currency.credits = 500
		GlobalData.currency.scrap = 200
		GlobalData.currency.data_cores = 10

	# Test read-only query can_afford_research
	_check(TechSys.can_afford_research(tech_id, GlobalData.currency), "[5a] can_afford_research returns true when credits >= 300")
	var poor_currency := {"credits": 100}
	_check(not TechSys.can_afford_research(tech_id, poor_currency), "[5b] can_afford_research returns false when credits < 300")

	# Test read-only query can_afford_identification
	_check(TechSys.can_afford_identification(tech_id, GlobalData.currency), "[5c] can_afford_identification returns true when credits >= 50")
	var broke_currency := {"credits": 20}
	_check(not TechSys.can_afford_identification(tech_id, broke_currency), "[5d] can_afford_identification returns false when credits < 50")

	# Execute full lifecycle steps and verify currencies NEVER change automatically
	TechSys.record_technology_encountered(tech_id)
	TechSys.record_technology_salvaged(tech_id)
	TechSys.add_technology_evidence(tech_id, 2.0)
	TechSys.record_technology_identified(tech_id)
	TechSys.start_research(tech_id)
	TechSys.add_research_progress(tech_id, 100.0)
	TechSys.complete_technology_research(tech_id)
	TechSys.record_technology_usable(tech_id)

	_check(TechSys.is_technology_usable(tech_id), "[5e] Technology successfully reached USABLE state")
	if GlobalData and GlobalData.currency:
		_check(GlobalData.currency.credits == 500, "[5f] GlobalData.currency.credits remains 500 (NO automated mutation)")
		_check(GlobalData.currency.scrap == 200, "[5g] GlobalData.currency.scrap remains 200 (NO automated mutation)")
		_check(GlobalData.currency.data_cores == 10, "[5h] GlobalData.currency.data_cores remains 10 (NO automated mutation)")


func _test_fleet_system_legacy_data_cores_isolation() -> void:
	if not GlobalData or not GlobalData.currency:
		return
	GlobalData.currency.data_cores = 5
	# Ensure FleetSystem blueprint research exists and is isolated
	var projects: Array = GlobalData.research_blueprints
	if not projects.is_empty():
		var first_bp: Dictionary = projects[0]
		var bp_id: String = str(first_bp.get("id", ""))
		var bp_cost: int = int(first_bp.get("data_cores", 1))
		# Clear state for bp_id
		GlobalData.hangar.research_projects.erase(bp_id)
		GlobalData.hangar.research_unlocked.erase(bp_id)

		var started := FleetSys.start_research(bp_id)
		_check(started, "[6a] FleetSystem.start_research started legacy blueprint successfully")
		_check(GlobalData.currency.data_cores == 5 - bp_cost, "[6b] FleetSystem consumed data_cores as intended for blueprint")
		_check(FleetSys.is_research_active(bp_id), "[6c] FleetSystem tracks active blueprint independently")

		# Verify TechnologySystem did NOT adopt or touch bp_id
		_check(not TechSys.has_technology(bp_id), "[6d] TechnologySystem does NOT register or own legacy blueprint ID")
		_check(TechSys.get_discovery_state(bp_id) == TechSys.DiscoveryState.UNKNOWN, "[6e] Blueprint is UNKNOWN in TechnologySystem")

		# Clean up
		GlobalData.hangar.research_projects.erase(bp_id)
		GlobalData.currency.data_cores = 5


func _test_lifecycle_transitions_with_custom_metadata() -> void:
	TechSys.reset_discovery_states()
	var tech_id := "tech_custom_barrier_test"
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Custom Barrier Test",
		"generation": 3,
		"technology_family": TechSys.FAMILY_ENERGY,
		"era_phase_req": 3,
		"origin_lineage": TechSys.LINEAGE_VALKRYON,
		"tags": ["energy", "barrier", "valkryon"],
		"prerequisites": [],
		"research_metadata": {
			"research_cost": 500.0,
			"research_time": 10.0,
			"required_evidence": 2.5,
			"required_materials": {"phase_core": 1},
			"identification_cost": 100.0
		}
	})

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[7a] Starts UNKNOWN")
	TechSys.record_technology_encountered(tech_id)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[7b] Transitioned to ENCOUNTERED")

	TechSys.record_technology_salvaged(tech_id)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[7c] Transitioned to SALVAGED")

	# Evidence currently at 1.0 (default from salvage), but required_evidence is 2.5
	_check(not TechSys.can_identify_technology(tech_id), "[7d] Cannot identify with 1.0 / 2.5 evidence")
	_check(not TechSys.record_technology_identified(tech_id), "[7e] record_technology_identified fails with insufficient evidence")

	# Add evidence to reach 3.0
	TechSys.add_technology_evidence(tech_id, 2.0)
	_check(TechSys.get_technology_evidence(tech_id) == 3.0, "[7f] Accumulated 3.0 evidence")
	_check(TechSys.can_identify_technology(tech_id), "[7g] can_identify_technology is now true (3.0 >= 2.5)")

	_check(TechSys.record_technology_identified(tech_id), "[7h] record_technology_identified succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[7i] State is IDENTIFIED")

	_check(TechSys.can_start_research(tech_id), "[7j] can_start_research is true")
	TechSys.start_research(tech_id)

	TechSys.add_research_progress(tech_id, 100.0)
	_check(TechSys.can_complete_research(tech_id), "[7k] can_complete_research is true at 100%")

	_check(TechSys.complete_technology_research(tech_id), "[7l] complete_technology_research succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.RESEARCHED, "[7m] State is RESEARCHED")

	_check(TechSys.record_technology_usable(tech_id), "[7n] record_technology_usable succeeds")
	_check(TechSys.is_technology_usable(tech_id), "[7o] State is USABLE")
