extends Node
## TECHNOLOGY RESEARCH LIFECYCLE VERIFICATION (PHASE 2E-3C)
## Validates the end-to-end technology research lifecycle:
## 1. Sequential valid forward transitions:
##    UNKNOWN -> ENCOUNTERED -> SALVAGED -> IDENTIFIED -> RESEARCHED -> USABLE
## 2. Rejection of illegal skipping and backward transitions
## 3. Observation isolation (UNKNOWN -> ENCOUNTERED only)
## 4. Salvage isolation (ENCOUNTERED -> SALVAGED only, no auto-identification)
## 5. Identification isolation (SALVAGED -> IDENTIFIED only, no auto-research)
## 6. Research progress model (0% -> 25% -> 50% -> 100%, no premature completion)
## 7. Research requirements & prerequisite gating
## 8. Usability boundary (RESEARCHED != USABLE, requires record_technology_usable)
## 9. Idempotency across repeated calls at every lifecycle stage
## 10. EventBus lifecycle signal emissions
## 11. Persistence roundtrip with full backward compatibility

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const SalvageSys = preload("res://scripts/systems/salvage_system.gd")
const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("RES_LIFE_OK: " + test_name)
	else:
		_fails += 1
		printerr("RES_LIFE_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY RESEARCH LIFECYCLE VERIFICATION (PHASE 2E-3C) ===")
	_test_sequential_lifecycle_transitions()
	_test_rejection_of_illegal_transitions()
	_test_observation_isolation()
	_test_salvage_isolation()
	_test_identification_isolation()
	_test_research_progress_and_completion()
	_test_research_prerequisite_gating()
	_test_usability_boundary()
	_test_lifecycle_idempotency()
	_test_eventbus_signal_emissions()
	_test_persistence_roundtrip()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_3C_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_3C_FAILED")
		get_tree().quit(1)


func _test_sequential_lifecycle_transitions() -> void:
	print("\n-- [1] Sequential Valid Forward Transitions --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()

	var tech_id := "tech_relic_excavation_core"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[1a] Starts at UNKNOWN")

	# 1. UNKNOWN -> ENCOUNTERED
	_check(TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.ENCOUNTERED), "[1b] can_transition permits UNKNOWN -> ENCOUNTERED")
	_check(TechSys.record_technology_encountered(tech_id, {"source": "test"}), "[1c] record_technology_encountered succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[1d] State is now ENCOUNTERED")

	# 2. ENCOUNTERED -> SALVAGED
	_check(TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED), "[1e] can_transition permits ENCOUNTERED -> SALVAGED")
	_check(TechSys.record_technology_salvaged(tech_id, {"source": "test", "evidence_amount": 2.0}), "[1f] record_technology_salvaged succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[1g] State is now SALVAGED")
	_check(TechSys.get_technology_evidence(tech_id) >= 2.0, "[1h] Evidence was recorded")

	# 3. SALVAGED -> IDENTIFIED
	_check(TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED), "[1i] can_transition permits SALVAGED -> IDENTIFIED")
	_check(TechSys.can_identify_technology(tech_id), "[1j] can_identify_technology is true with sufficient evidence")
	_check(TechSys.record_technology_identified(tech_id, {"source": "test"}), "[1k] record_technology_identified succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[1l] State is now IDENTIFIED")

	# 4. IDENTIFIED -> RESEARCHED
	_check(TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED), "[1m] can_transition permits IDENTIFIED -> RESEARCHED")
	_check(TechSys.can_start_research(tech_id), "[1n] can_start_research is true")
	TechSys.start_research(tech_id)
	TechSys.add_research_progress(tech_id, 100.0)
	_check(TechSys.can_complete_research(tech_id), "[1o] can_complete_research is true at 100% progress")
	_check(TechSys.complete_technology_research(tech_id), "[1p] complete_technology_research succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.RESEARCHED, "[1q] State is now RESEARCHED")

	# 5. RESEARCHED -> USABLE
	_check(TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.USABLE), "[1r] can_transition permits RESEARCHED -> USABLE")
	_check(TechSys.can_make_technology_usable(tech_id), "[1s] can_make_technology_usable is true")
	_check(TechSys.record_technology_usable(tech_id), "[1t] record_technology_usable succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.USABLE, "[1u] State is now USABLE")
	_check(TechSys.is_technology_usable(tech_id), "[1v] is_technology_usable returns true")


func _test_rejection_of_illegal_transitions() -> void:
	print("\n-- [2] Rejection of Illegal Transitions --")
	var tech_id := "tech_cryo_cooling"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	# Illegal skips from UNKNOWN
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED), "[2a] Reject UNKNOWN -> SALVAGED")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED), "[2b] Reject UNKNOWN -> IDENTIFIED")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED), "[2c] Reject UNKNOWN -> RESEARCHED")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.USABLE), "[2d] Reject UNKNOWN -> USABLE")

	# Illegal skips from ENCOUNTERED
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.ENCOUNTERED)
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED), "[2e] Reject ENCOUNTERED -> IDENTIFIED")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED), "[2f] Reject ENCOUNTERED -> RESEARCHED")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.USABLE), "[2g] Reject ENCOUNTERED -> USABLE")

	# Illegal skips from SALVAGED
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED)
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED), "[2h] Reject SALVAGED -> RESEARCHED")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.USABLE), "[2i] Reject SALVAGED -> USABLE")

	# Illegal skip from IDENTIFIED
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED)
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.USABLE), "[2j] Reject IDENTIFIED -> USABLE")

	# Regressions
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.USABLE)
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED), "[2k] Reject USABLE -> RESEARCHED regression")
	_check(not TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN), "[2l] Reject USABLE -> UNKNOWN regression")


func _test_observation_isolation() -> void:
	print("\n-- [3] Observation Isolation --")
	var tech_id := "tech_beam_weaponry"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	# Trigger observation event via EventBus
	if EventBus:
		EventBus.technology_observed.emit(tech_id, {"source": "test_combat"})

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[3a] Observation only advances to ENCOUNTERED")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.SALVAGED, "[3b] Observation does NOT advance to SALVAGED")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.IDENTIFIED, "[3c] Observation does NOT advance to IDENTIFIED")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.RESEARCHED, "[3d] Observation does NOT advance to RESEARCHED")
	_check(not TechSys.is_technology_usable(tech_id), "[3e] Observed tech is NOT usable")


func _test_salvage_isolation() -> void:
	print("\n-- [4] Salvage Isolation --")
	var tech_id := "tech_valkryon_actuator_chassis"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.ENCOUNTERED)

	var salvage_sys := SalvageSys.new()
	salvage_sys.collect_salvage({
		"salvage_id": "chassis_debris",
		"tech_id": tech_id,
		"name": "Damaged Actuator Joint"
	})

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[4a] Salvage collection advances ENCOUNTERED -> SALVAGED")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.IDENTIFIED, "[4b] Salvage does NOT automatically IDENTIFY")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.RESEARCHED, "[4c] Salvage does NOT automatically RESEARCH")
	_check(not TechSys.is_technology_usable(tech_id), "[4d] Salvaged tech is NOT usable")

	salvage_sys.free()


func _test_identification_isolation() -> void:
	print("\n-- [5] Identification Isolation --")
	var tech_id := "tech_modular_energy_interface"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED)
	TechSys.add_technology_evidence(tech_id, 2.0)

	_check(TechSys.record_technology_identified(tech_id), "[5a] Identification succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[5b] State is strictly IDENTIFIED")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.RESEARCHED, "[5c] Identification does NOT automatically RESEARCH")
	_check(not TechSys.is_technology_usable(tech_id), "[5d] Identified tech is NOT usable")
	_check(TechSys.get_research_progress(tech_id) == 0.0, "[5e] Research progress starts at 0%")


func _test_research_progress_and_completion() -> void:
	print("\n-- [6] Research Progress & Completion Model --")
	var tech_id := "tech_reinforced_plating"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED)

	_check(TechSys.start_research(tech_id), "[6a] Start research succeeds")
	_check(TechSys.get_research_progress(tech_id) == 0.0, "[6b] Initial progress is 0.0%")
	_check(not TechSys.can_complete_research(tech_id), "[6c] Cannot complete research at 0%")
	_check(not TechSys.complete_technology_research(tech_id), "[6d] complete_technology_research returns false at 0%")

	TechSys.add_research_progress(tech_id, 25.0)
	_check(is_equal_approx(TechSys.get_research_progress(tech_id), 25.0), "[6e] Progress is 25.0%")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[6f] State remains IDENTIFIED during progress")
	_check(not TechSys.can_complete_research(tech_id), "[6g] Cannot complete research at 25%")

	TechSys.add_research_progress(tech_id, 25.0)
	_check(is_equal_approx(TechSys.get_research_progress(tech_id), 50.0), "[6h] Progress is 50.0%")
	_check(not TechSys.can_complete_research(tech_id), "[6i] Cannot complete research at 50%")

	TechSys.add_research_progress(tech_id, 50.0)
	_check(is_equal_approx(TechSys.get_research_progress(tech_id), 100.0), "[6j] Progress is 100.0%")
	_check(TechSys.can_complete_research(tech_id), "[6k] can_complete_research is true at 100%")

	_check(TechSys.complete_technology_research(tech_id), "[6l] complete_technology_research succeeds at 100%")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.RESEARCHED, "[6m] State is now RESEARCHED")
	_check(TechSys.get_discovery_state_name(tech_id) == "RESEARCHED", "[6n] State name reads RESEARCHED")


func _test_research_prerequisite_gating() -> void:
	print("\n-- [7] Research Prerequisite Gating --")
	var child_tech := "tech_reinforced_plating" # requires tech_ballistic_conventional
	var parent_tech := "tech_ballistic_conventional"

	TechSys.set_discovery_state(child_tech, TechSys.DiscoveryState.IDENTIFIED)
	TechSys.set_discovery_state(parent_tech, TechSys.DiscoveryState.UNKNOWN)

	_check(not TechSys.can_start_research(child_tech), "[7a] Cannot start research when prerequisite is UNKNOWN")

	TechSys.set_discovery_state(parent_tech, TechSys.DiscoveryState.IDENTIFIED)
	_check(not TechSys.can_start_research(child_tech), "[7b] Cannot start research when prerequisite is only IDENTIFIED")

	TechSys.set_discovery_state(parent_tech, TechSys.DiscoveryState.RESEARCHED)
	_check(TechSys.can_start_research(child_tech), "[7c] Can start research once prerequisite is RESEARCHED")


func _test_usability_boundary() -> void:
	print("\n-- [8] Usability Boundary --")
	var tech_id := "tech_beam_weaponry"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED)

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.RESEARCHED, "[8a] Current state is RESEARCHED")
	_check(not TechSys.is_technology_usable(tech_id), "[8b] RESEARCHED technology is NOT usable by default")

	_check(TechSys.can_make_technology_usable(tech_id), "[8c] can_make_technology_usable is true")
	_check(TechSys.record_technology_usable(tech_id), "[8d] record_technology_usable succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.USABLE, "[8e] Discovery state is USABLE")
	_check(TechSys.is_technology_usable(tech_id), "[8f] is_technology_usable returns true")


func _test_lifecycle_idempotency() -> void:
	print("\n-- [9] Lifecycle Idempotency --")
	var tech_id := "tech_cryo_cooling"

	# Repeated encounters
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)
	_check(TechSys.record_technology_encountered(tech_id), "[9a] First encounter returns true")
	_check(not TechSys.record_technology_encountered(tech_id), "[9b] Repeated encounter returns false (idempotent)")

	# Repeated salvage
	_check(TechSys.record_technology_salvaged(tech_id), "[9c] First salvage returns true")
	_check(not TechSys.record_technology_salvaged(tech_id), "[9d] Repeated salvage returns false (idempotent)")

	# Repeated identification
	TechSys.add_technology_evidence(tech_id, 2.0)
	_check(TechSys.record_technology_identified(tech_id), "[9e] First identification returns true")
	_check(not TechSys.record_technology_identified(tech_id), "[9f] Repeated identification returns false (idempotent)")

	# Repeated research completion
	TechSys.add_research_progress(tech_id, 100.0)
	_check(TechSys.complete_technology_research(tech_id), "[9g] First research completion returns true")
	_check(not TechSys.complete_technology_research(tech_id), "[9h] Repeated research completion returns false (idempotent)")

	# Repeated usability
	_check(TechSys.record_technology_usable(tech_id), "[9i] First usability authorization returns true")
	_check(not TechSys.record_technology_usable(tech_id), "[9j] Repeated usability authorization returns false (idempotent)")


func _test_eventbus_signal_emissions() -> void:
	print("\n-- [10] EventBus Signal Emissions --")
	var tech_id := "tech_modular_energy_interface"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED)
	TechSys.add_technology_evidence(tech_id, 2.0)

	var emitted := {
		"identified": false,
		"researched": false,
		"usable": false
	}

	var id_cb := func(tid: String, _data: Dictionary):
		if tid == tech_id:
			emitted["identified"] = true
	var res_cb := func(tid: String, _data: Dictionary):
		if tid == tech_id:
			emitted["researched"] = true
	var use_cb := func(tid: String, _data: Dictionary):
		if tid == tech_id:
			emitted["usable"] = true

	if EventBus:
		EventBus.technology_identified.connect(id_cb)
		EventBus.technology_researched.connect(res_cb)
		EventBus.technology_became_usable.connect(use_cb)

	TechSys.record_technology_identified(tech_id)
	_check(emitted["identified"], "[10a] EventBus.technology_identified emitted")

	TechSys.add_research_progress(tech_id, 100.0)
	TechSys.complete_technology_research(tech_id)
	_check(emitted["researched"], "[10b] EventBus.technology_researched emitted")

	TechSys.record_technology_usable(tech_id)
	_check(emitted["usable"], "[10c] EventBus.technology_became_usable emitted")

	if EventBus:
		EventBus.technology_identified.disconnect(id_cb)
		EventBus.technology_researched.disconnect(res_cb)
		EventBus.technology_became_usable.disconnect(use_cb)


func _test_persistence_roundtrip() -> void:
	print("\n-- [11] Persistence Roundtrip & Backward Compatibility --")
	TechSys.reset_discovery_states()
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.SALVAGED)
	TechSys.add_technology_evidence("tech_beam_weaponry", 3.5)

	TechSys.set_discovery_state("tech_cryo_cooling", TechSys.DiscoveryState.IDENTIFIED)
	TechSys.add_research_progress("tech_cryo_cooling", 65.0)

	TechSys.set_discovery_state("tech_reinforced_plating", TechSys.DiscoveryState.RESEARCHED)
	TechSys.set_discovery_state("tech_high_energy_barrier", TechSys.DiscoveryState.USABLE)

	var serialized := TechSys.serialize_discovery_states()
	_check(serialized.get("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[11a] Serialized flat state preserved for backward compatibility")
	_check(serialized.has("__evidence"), "[11b] Serialized contains __evidence")
	_check(serialized.has("__progress"), "[11c] Serialized contains __progress")

	# Reset and deserialize
	TechSys.reset_discovery_states()
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "[11d] Reset clears state")
	_check(TechSys.get_technology_evidence("tech_beam_weaponry") == 0.0, "[11e] Reset clears evidence")

	TechSys.deserialize_discovery_states(serialized)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[11f] Restored SALVAGED state")
	_check(is_equal_approx(TechSys.get_technology_evidence("tech_beam_weaponry"), 3.5), "[11g] Restored evidence points")
	_check(TechSys.get_discovery_state("tech_cryo_cooling") == TechSys.DiscoveryState.IDENTIFIED, "[11h] Restored IDENTIFIED state")
	_check(is_equal_approx(TechSys.get_research_progress("tech_cryo_cooling"), 65.0), "[11i] Restored research progress")
	_check(TechSys.get_discovery_state("tech_reinforced_plating") == TechSys.DiscoveryState.RESEARCHED, "[11j] Restored RESEARCHED state")
	_check(TechSys.get_discovery_state("tech_high_energy_barrier") == TechSys.DiscoveryState.USABLE, "[11k] Restored USABLE state")

	# Test legacy format deserialization
	var legacy_save := {
		"tech_beam_weaponry": TechSys.DiscoveryState.ENCOUNTERED,
		"tech_cryo_cooling": TechSys.DiscoveryState.USABLE
	}
	TechSys.deserialize_discovery_states(legacy_save)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.ENCOUNTERED, "[11l] Restored legacy ENCOUNTERED state")
	_check(TechSys.get_discovery_state("tech_cryo_cooling") == TechSys.DiscoveryState.USABLE, "[11m] Restored legacy USABLE state")
