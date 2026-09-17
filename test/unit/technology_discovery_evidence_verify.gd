extends Node
## PLAYER TECHNOLOGY DISCOVERY & EVIDENCE VERIFICATION (PHASE 2E-3A)
## Validates clean separation of:
## 1. Technology Definition vs Physical Evidence vs Player Discovery State
## 2. Controlled transition UNKNOWN -> ENCOUNTERED
## 3. Repeated encounter is idempotent
## 4. Controlled transition ENCOUNTERED -> SALVAGED
## 5. Repeated salvage is idempotent
## 6. Invalid backward transitions are rejected
## 7. Invalid arbitrary jumps (UNKNOWN -> SALVAGED directly) are rejected
## 8. Faction technology does NOT alter player discovery state
## 9. Player discovery does NOT alter faction technology
## 10. Technology evidence references tech_id without becoming the technology itself
## 11. SalvageSystem collects physical salvage and drives evidence discovery
## 12. EventBus observation and salvage signals trigger discovery
## 13. Save/load persistence roundtrip and legacy compatibility

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const EraProgSys = preload("res://scripts/systems/era_progression_system.gd")
const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")
const SalvageSys = preload("res://scripts/systems/salvage_system.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("TECH_EVID_OK: " + test_name)
	else:
		_fails += 1
		printerr("TECH_EVID_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING PLAYER TECHNOLOGY DISCOVERY EVIDENCE VERIFICATION (PHASE 2E-3A) ===")
	_test_unknown_to_encountered()
	_test_repeated_encounter_idempotent()
	_test_encountered_to_salvaged()
	_test_repeated_salvage_idempotent()
	_test_invalid_backward_and_jump_transitions()
	_test_faction_technology_does_not_change_player_discovery()
	_test_player_discovery_does_not_change_faction_technology()
	_test_technology_evidence_separation()
	_test_salvage_system_workflow()
	_test_eventbus_observation_and_salvage()
	_test_save_load_roundtrip_and_backward_compatibility()
	_test_unknown_tech_id_handling()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_3A_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_3A_FAILED")
		get_tree().quit(1)


func _test_unknown_to_encountered() -> void:
	print("\n-- [1] UNKNOWN -> ENCOUNTERED Transition --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()

	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[1a] Starts in UNKNOWN state")
	_check(TechSys.get_discovery_state_name(tech_id) == "UNKNOWN", "[1b] State name reads UNKNOWN")

	var permitted := TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.ENCOUNTERED)
	_check(permitted, "[1c] can_transition_discovery_state allows UNKNOWN -> ENCOUNTERED")

	var transitioned := TechSys.record_technology_encountered(tech_id, {"source": "combat_sighting"})
	_check(transitioned, "[1d] record_technology_encountered returns true on new encounter")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[1e] Discovery state advanced to ENCOUNTERED")
	_check(TechSys.get_discovery_state_name(tech_id) == "ENCOUNTERED", "[1f] State name reads ENCOUNTERED")


func _test_repeated_encounter_idempotent() -> void:
	print("\n-- [2] Repeated Encounter Idempotence --")
	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[2a] Current state is ENCOUNTERED")

	var second_encounter := TechSys.record_technology_encountered(tech_id, {"source": "another_battle"})
	_check(not second_encounter, "[2b] Repeated encounter returns false (no duplicate transition)")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[2c] State remains ENCOUNTERED (no mutation)")

	var third_encounter := TechSys.record_technology_encountered(tech_id, {"source": "scout_report"})
	_check(not third_encounter, "[2d] Third encounter returns false")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[2e] State remains unchanged")


func _test_encountered_to_salvaged() -> void:
	print("\n-- [3] ENCOUNTERED -> SALVAGED Transition --")
	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[3a] Prerequisite state is ENCOUNTERED")

	var permitted := TechSys.can_transition_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED)
	_check(permitted, "[3b] can_transition_discovery_state allows ENCOUNTERED -> SALVAGED")

	var salvaged := TechSys.record_technology_salvaged(tech_id, {"source": "battlefield_wreckage"})
	_check(salvaged, "[3c] record_technology_salvaged returns true when advancing from ENCOUNTERED")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[3d] Discovery state advanced to SALVAGED")
	_check(TechSys.get_discovery_state_name(tech_id) == "SALVAGED", "[3e] State name reads SALVAGED")


func _test_repeated_salvage_idempotent() -> void:
	print("\n-- [4] Repeated Salvage Idempotence --")
	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[4a] Current state is SALVAGED")

	var second_salvage := TechSys.record_technology_salvaged(tech_id, {"source": "second_wreck"})
	_check(not second_salvage, "[4b] Repeated salvage returns false (idempotent)")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[4c] State remains SALVAGED")

	var encounter_while_salvaged := TechSys.record_technology_encountered(tech_id)
	_check(not encounter_while_salvaged, "[4d] Encountering technology already SALVAGED returns false")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[4e] State does NOT regress back to ENCOUNTERED")


func _test_invalid_backward_and_jump_transitions() -> void:
	print("\n-- [5] Invalid Backward & Arbitrary Jump Transitions --")
	var tech_salvaged := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_salvaged) == TechSys.DiscoveryState.SALVAGED, "[5a] Starting at SALVAGED")

	# Backward transitions from SALVAGED
	_check(not TechSys.can_transition_discovery_state(tech_salvaged, TechSys.DiscoveryState.ENCOUNTERED), "[5b] can_transition rejects SALVAGED -> ENCOUNTERED")
	_check(not TechSys.transition_discovery_state(tech_salvaged, TechSys.DiscoveryState.ENCOUNTERED), "[5c] transition_discovery_state rejects SALVAGED -> ENCOUNTERED")
	_check(not TechSys.can_transition_discovery_state(tech_salvaged, TechSys.DiscoveryState.UNKNOWN), "[5d] can_transition rejects SALVAGED -> UNKNOWN")
	_check(not TechSys.transition_discovery_state(tech_salvaged, TechSys.DiscoveryState.UNKNOWN), "[5e] transition_discovery_state rejects SALVAGED -> UNKNOWN")
	_check(TechSys.get_discovery_state(tech_salvaged) == TechSys.DiscoveryState.SALVAGED, "[5f] State preserved at SALVAGED")

	# Test arbitrary jumps on an UNKNOWN technology
	var fresh_tech := "tech_high_energy_barrier"
	TechSys.set_discovery_state(fresh_tech, TechSys.DiscoveryState.UNKNOWN)
	_check(TechSys.get_discovery_state(fresh_tech) == TechSys.DiscoveryState.UNKNOWN, "[5g] Fresh tech starts UNKNOWN")

	# Jump directly UNKNOWN -> SALVAGED without ENCOUNTERED
	_check(not TechSys.can_transition_discovery_state(fresh_tech, TechSys.DiscoveryState.SALVAGED), "[5h] can_transition rejects UNKNOWN -> SALVAGED jump")
	_check(not TechSys.transition_discovery_state(fresh_tech, TechSys.DiscoveryState.SALVAGED), "[5i] transition_discovery_state rejects UNKNOWN -> SALVAGED jump")
	_check(not TechSys.record_technology_salvaged(fresh_tech), "[5j] record_technology_salvaged rejects UNKNOWN technology directly")
	_check(TechSys.get_discovery_state(fresh_tech) == TechSys.DiscoveryState.UNKNOWN, "[5k] Fresh tech remains UNKNOWN")

	# Jumps to future unapproved states in Phase 2E-3A
	_check(not TechSys.can_transition_discovery_state(fresh_tech, TechSys.DiscoveryState.IDENTIFIED), "[5l] IDENTIFIED transition rejected in Phase 2E-3A")
	_check(not TechSys.can_transition_discovery_state(fresh_tech, TechSys.DiscoveryState.RESEARCHED), "[5m] RESEARCHED transition rejected in Phase 2E-3A")
	_check(not TechSys.can_transition_discovery_state(fresh_tech, TechSys.DiscoveryState.USABLE), "[5n] USABLE transition rejected in Phase 2E-3A")


func _test_faction_technology_does_not_change_player_discovery() -> void:
	print("\n-- [6] Faction Technology -> Player Discovery Independence --")
	TechSys.reset_discovery_states()
	TechSys.reset_world_diffusion_state()

	var tech_id := "tech_valkryon_actuator_chassis"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[6a] Player starts with UNKNOWN")

	# Rival unlocks technology through laboratory breakthrough
	TechSys.grant_faction_technology("rival", tech_id)
	_check(TechSys.has_faction_technology("rival", tech_id), "[6b] Rival possesses technology")

	# Player discovery state MUST remain strictly UNKNOWN
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[6c] Player discovery remains UNKNOWN after rival research")
	_check(TechSys.get_discovery_state_name(tech_id) == "UNKNOWN", "[6d] Player state name is UNKNOWN")
	_check(not TechSys.is_technology_usable(tech_id), "[6e] Technology is NOT usable by player")


func _test_player_discovery_does_not_change_faction_technology() -> void:
	print("\n-- [7] Player Discovery -> Faction Technology Independence --")
	var tech_id := "tech_cryo_cooling"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	# Neither faction possesses tech_cryo_cooling initially
	_check(not TechSys.has_faction_technology("rival", tech_id), "[7a] Rival does not possess tech")
	_check(not TechSys.has_faction_technology("convoy", tech_id), "[7b] Convoy does not possess tech")

	# Player discovers and salvages evidence
	TechSys.record_technology_encountered(tech_id)
	TechSys.record_technology_salvaged(tech_id)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[7c] Player discovery is now SALVAGED")

	# Faction technology lists remain completely unaltered
	_check(not TechSys.has_faction_technology("rival", tech_id), "[7d] Rival faction tech unaltered by player discovery")
	_check(not TechSys.has_faction_technology("convoy", tech_id), "[7e] Convoy faction tech unaltered by player discovery")
	_check(TechSys.get_technologies_for_faction("rival").find(tech_id) == -1, "[7f] Tech absent from rival faction list")


func _test_technology_evidence_separation() -> void:
	print("\n-- [8] Technology Evidence Separation (Definition vs Evidence) --")
	var tech_id := "tech_beam_weaponry"
	var def := TechSys.get_technology_definition(tech_id)
	_check(not def.is_empty(), "[8a] Canonical Technology Definition retrieved")
	_check(def.get("generation") == 2, "[8b] Definition generation is 2")
	_check(def.get("technology_family") == TechSys.FAMILY_ENERGY, "[8c] Definition family is energy")

	# Construct a physical salvage evidence piece referencing tech_id
	var salvage_item := {
		"salvage_id": "wreck_optic_assembly_01",
		"name": "Damaged Coherent Beam Emitter",
		"type": "component_salvage",
		"condition": 0.35,
		"weight": 14.5,
		"tech_id": tech_id
	}

	_check(TechSys.is_technology_evidence(salvage_item), "[8d] Item recognized as technology evidence")
	_check(TechSys.resolve_item_technology_id(salvage_item) == tech_id, "[8e] tech_id resolved from evidence item")

	# Mutating the physical salvage item does NOT mutate the technology definition
	salvage_item["condition"] = 0.0
	salvage_item["weight"] = 2.0
	var def_after := TechSys.get_technology_definition(tech_id)
	_check(def_after.get("generation") == 2, "[8f] Definition remains immutable after salvage item modification")
	_check(not def_after.has("condition"), "[8g] Technology definition does not absorb salvage item attributes")

	# Non-evidence item (plain scrap metal)
	var plain_item := {
		"id": "scrap_metal_plate",
		"name": "Twisted Armor Plating",
		"type": "scrap",
		"weight": 5.0
	}
	_check(not TechSys.is_technology_evidence(plain_item), "[8h] Plain item is NOT technology evidence")
	_check(TechSys.resolve_item_technology_id(plain_item) == "", "[8i] Plain item resolves empty tech_id")


func _test_salvage_system_workflow() -> void:
	print("\n-- [9] SalvageSystem Physical Acquisition Workflow --")
	var salvage_sys := SalvageSys.new()
	var tech_id := "tech_modular_energy_interface"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	var evidence_piece := {
		"salvage_id": "salvage_solid_state_converter_8",
		"name": "Burnt Solid-State Converter",
		"type": "relic_component",
		"tech_id": tech_id,
		"condition": 0.50
	}

	_check(SalvageSys.is_technology_evidence(evidence_piece), "[9a] SalvageSystem static helper identifies evidence")
	_check(SalvageSys.extract_tech_id(evidence_piece) == tech_id, "[9b] SalvageSystem static helper extracts tech_id")

	# Collecting salvage piece when tech is UNKNOWN triggers observation then salvage
	salvage_sys.collect_salvage(evidence_piece)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[9c] Salvage acquisition advanced UNKNOWN -> ENCOUNTERED -> SALVAGED")
	_check(salvage_sys.has_salvaged_evidence_for_tech(tech_id), "[9d] SalvageSystem records physical evidence presence")

	var recorded := salvage_sys.get_salvaged_evidence_for_tech(tech_id)
	_check(recorded.size() == 1, "[9e] Exactly one evidence item retrieved for tech")
	_check(recorded[0].get("salvage_id") == "salvage_solid_state_converter_8", "[9f] Retrieved evidence has matching salvage_id")

	# Repeated collection is idempotent on technology state
	salvage_sys.collect_salvage(evidence_piece)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[9g] Repeated collection leaves state at SALVAGED")

	salvage_sys.free()


func _test_eventbus_observation_and_salvage() -> void:
	print("\n-- [10] EventBus Observation & Salvage Signals --")
	var tech_id := "tech_passive_cooling"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	if EventBus:
		# 1. Observation event advances UNKNOWN -> ENCOUNTERED
		EventBus.technology_observed.emit(tech_id, {"source": "recon_drone", "sector": 4})
		_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[10a] EventBus.technology_observed advances UNKNOWN to ENCOUNTERED")

		# 2. Salvage event advances ENCOUNTERED -> SALVAGED
		EventBus.technology_salvaged.emit(tech_id, {"salvage_id": "radiator_core_01", "tech_id": tech_id})
		_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[10b] EventBus.technology_salvaged advances ENCOUNTERED to SALVAGED")
	else:
		_check(false, "[10a] EventBus autoload not found")


func _test_save_load_roundtrip_and_backward_compatibility() -> void:
	print("\n-- [11] Save/Load Persistence Roundtrip & Compatibility --")
	TechSys.reset_discovery_states()
	TechSys.set_discovery_state("tech_ballistic_conventional", TechSys.DiscoveryState.USABLE)
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.SALVAGED)
	TechSys.set_discovery_state("tech_high_energy_barrier", TechSys.DiscoveryState.ENCOUNTERED)

	var saved := TechSys.serialize_discovery_states()
	_check(saved.get("tech_ballistic_conventional") == TechSys.DiscoveryState.USABLE, "[11a] Serialized USABLE state")
	_check(saved.get("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[11b] Serialized SALVAGED state")
	_check(saved.get("tech_high_energy_barrier") == TechSys.DiscoveryState.ENCOUNTERED, "[11c] Serialized ENCOUNTERED state")

	TechSys.reset_discovery_states()
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "[11d] Reset clears in-memory state")

	TechSys.deserialize_discovery_states(saved)
	_check(TechSys.get_discovery_state("tech_ballistic_conventional") == TechSys.DiscoveryState.USABLE, "[11e] Restored USABLE state")
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[11f] Restored SALVAGED state")
	_check(TechSys.get_discovery_state("tech_high_energy_barrier") == TechSys.DiscoveryState.ENCOUNTERED, "[11g] Restored ENCOUNTERED state")

	# Legacy / empty save compatibility
	TechSys.deserialize_discovery_states({})
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "[11h] Legacy empty save safely resets to base defaults")


func _test_unknown_tech_id_handling() -> void:
	print("\n-- [12] Unknown Technology ID Robustness --")
	var bogus := "tech_nonexistent_xyz_999"
	_check(not TechSys.has_technology(bogus), "[12a] Bogus tech not registered")
	_check(not TechSys.record_technology_encountered(bogus), "[12b] record_technology_encountered rejects unregistered tech")
	_check(not TechSys.record_technology_salvaged(bogus), "[12c] record_technology_salvaged rejects unregistered tech")
	_check(not TechSys.can_transition_discovery_state(bogus, TechSys.DiscoveryState.ENCOUNTERED), "[12d] can_transition rejects unregistered tech")
	_check(not TechSys.transition_discovery_state(bogus, TechSys.DiscoveryState.ENCOUNTERED), "[12e] transition_discovery_state rejects unregistered tech")
	_check(TechSys.get_discovery_state(bogus) == TechSys.DiscoveryState.UNKNOWN, "[12f] Unregistered tech returns UNKNOWN")
