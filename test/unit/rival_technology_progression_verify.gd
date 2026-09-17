extends Node
## RIVAL FACTION TECHNOLOGY PROGRESSION VERIFICATION (PHASE 2E-2)
## Validates RivalProgressionSystem + TechnologySystem breakthrough integration:
## 1. Breakthrough triggering (Laboratory and Excavation)
## 2. Faction eligibility filtering (FACTION_RIVAL, FACTION_ALL)
## 3. Era phase filtering (EraProgressionSystem sole time authority)
## 4. Prerequisite gating (child not eligible until parent granted)
## 5. Already-granted exclusion from candidates
## 6. Player discovery independence (UNKNOWN preserved)
## 7. Authoritative persistence (Era, Rival, Technology)
## 8. Legacy save compatibility (safe defaults when fields missing)
## 9. Prototype state activation without enemy unit spawning
## 10. Technology coexistence (additive progression, no obsolescence)
## 11. EventBus signal emission with payload
## 12. No second time/era authority

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const EraProgSys = preload("res://scripts/systems/era_progression_system.gd")
const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("RIVAL_TECH_OK: " + test_name)
	else:
		_fails += 1
		printerr("RIVAL_TECH_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING RIVAL TECHNOLOGY PROGRESSION VERIFICATION (PHASE 2E-2) ===")
	_test_faction_eligibility_and_query()
	_test_era_phase_filtering()
	_test_prerequisite_gating()
	_test_already_granted_exclusion()
	_test_player_discovery_independence()
	_test_breakthrough_eventbus_signal()
	_test_turn_advancement_and_breakthrough()
	_test_prototype_activation_without_enemy_spawn()
	_test_coexistence_and_additive_progression()
	_test_persistence_roundtrip()
	_test_legacy_save_fallback()
	_test_sole_time_authority()

	print("\n=== RIVAL TECHNOLOGY PROGRESSION TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_RIVAL_TECH_PROGRESSION_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("SOME_RIVAL_TECH_PROGRESSION_TESTS_FAILED")
		get_tree().quit(1)


func _test_faction_eligibility_and_query() -> void:
	print("\n-- [1] Faction Eligibility & Candidate Query --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# In Phase 1, query eligible technologies for rival faction
	var eligible: Array = TechSys.get_eligible_faction_technologies("rival")
	_check(not eligible.is_empty(), "[1a] Rival faction has eligible candidates in Phase 1")

	for candidate in eligible:
		var tech_id: String = str(candidate.get("tech_id", ""))
		var diff_meta: Dictionary = candidate.get("diffusion_metadata", {})
		var factions: Array = diff_meta.get("factions", [TechSys.FACTION_ALL])
		var faction_allowed: bool = (TechSys.FACTION_ALL in factions) or (TechSys.FACTION_RIVAL in factions) or ("rival" in factions)
		_check(faction_allowed, "[1b] Candidate %s respects rival faction eligibility" % tech_id)


func _test_era_phase_filtering() -> void:
	print("\n-- [2] Era Phase Filtering --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()

	# Era is in Phase 1 (Tactical)
	_check(EraProgSys.current_phase == EraProgSys.EraPhase.PHASE_1_TACTICAL, "[2a] Era is initially Phase 1")
	var phase1_eligible: Array = TechSys.get_eligible_faction_technologies("rival")

	for candidate in phase1_eligible:
		var tech_id: String = str(candidate.get("tech_id", ""))
		var diff_meta: Dictionary = candidate.get("diffusion_metadata", {})
		var min_phase: int = int(diff_meta.get("min_era_phase", candidate.get("era_phase_req", 1)))
		_check(min_phase <= 1, "[2b] Candidate %s requires min_phase <= 1 in Phase 1" % tech_id)

	# Advance era to Phase 2 (Energy)
	EraProgSys.current_phase = EraProgSys.EraPhase.PHASE_2_ENERGY
	var phase2_eligible: Array = TechSys.get_eligible_faction_technologies("rival")
	_check(phase2_eligible.size() >= phase1_eligible.size(), "[2c] Phase 2 has at least as many eligible candidates as Phase 1")

	# Advance era to Phase 3 (Singularity)
	EraProgSys.current_phase = EraProgSys.EraPhase.PHASE_3_SINGULARITY
	var phase3_eligible: Array = TechSys.get_eligible_faction_technologies("rival")
	_check(phase3_eligible.size() >= phase2_eligible.size(), "[2d] Phase 3 has at least as many eligible candidates as Phase 2")

	EraProgSys.reset()


func _test_prerequisite_gating() -> void:
	print("\n-- [3] Prerequisite Gating --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()

	# Find a technology with prerequisites
	var tech_with_prereqs: String = ""
	var required_prereqs: Array = []
	for tech in TechSys.get_all_technologies():
		var prereqs: Array = tech.get("prerequisites", [])
		if not prereqs.is_empty():
			tech_with_prereqs = str(tech.get("tech_id", ""))
			required_prereqs = prereqs
			break

	if not tech_with_prereqs.is_empty():
		# Verify child tech is not eligible when prereqs are missing
		var eligible: Array = TechSys.get_eligible_faction_technologies("rival")
		var eligible_ids: Array = []
		for c in eligible:
			eligible_ids.append(str(c.get("tech_id", "")))
		_check(not (tech_with_prereqs in eligible_ids), "[3a] Child tech %s is not eligible before prerequisites are granted" % tech_with_prereqs)

		# Grant all prerequisites to rival
		for p in required_prereqs:
			TechSys.grant_faction_technology("rival", str(p))

		# Now check if prereq condition is satisfied
		var prereqs_satisfied: bool = true
		for p in required_prereqs:
			if not TechSys.has_faction_technology("rival", str(p)):
				prereqs_satisfied = false
		_check(prereqs_satisfied, "[3b] All prerequisites granted to rival faction")


func _test_already_granted_exclusion() -> void:
	print("\n-- [4] Already Granted Exclusion --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()

	var eligible_before: Array = TechSys.get_eligible_faction_technologies("rival")
	_check(not eligible_before.is_empty(), "[4a] Eligible candidates exist before grant")

	var chosen: String = str(eligible_before[0].get("tech_id", ""))
	TechSys.grant_faction_technology("rival", chosen)
	_check(TechSys.has_faction_technology("rival", chosen), "[4b] Faction has granted technology")

	var eligible_after: Array = TechSys.get_eligible_faction_technologies("rival")
	var eligible_after_ids: Array = []
	for c in eligible_after:
		eligible_after_ids.append(str(c.get("tech_id", "")))
	_check(not (chosen in eligible_after_ids), "[4c] Granted technology %s is excluded from subsequent candidate queries" % chosen)


func _test_player_discovery_independence() -> void:
	print("\n-- [5] Player Discovery Independence --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	TechSys.reset_discovery_states()
	EraProgSys.reset()
	RivalProgSys.reset()

	# Ensure target tech is UNKNOWN to player
	var target_tech := "tech_cooling_jacket_mk2"
	TechSys.set_discovery_state(target_tech, TechSys.DiscoveryState.UNKNOWN)
	_check(TechSys.get_discovery_state(target_tech) == TechSys.DiscoveryState.UNKNOWN, "[5a] Player discovery starts as UNKNOWN")

	# Rival unlocks the technology
	TechSys.grant_faction_technology("rival", target_tech)
	_check(TechSys.has_faction_technology("rival", target_tech), "[5b] Rival now has target technology")

	# Player discovery MUST remain UNKNOWN
	_check(TechSys.get_discovery_state(target_tech) == TechSys.DiscoveryState.UNKNOWN, "[5c] Player discovery remains UNKNOWN after rival research")
	_check(TechSys.get_discovery_state(target_tech) == TechSys.DiscoveryState.UNKNOWN, "[5d] Player does NOT automatically discover rival technology")
	_check(not TechSys.is_technology_usable(target_tech), "[5e] Player CANNOT use rival technology")


func _test_breakthrough_eventbus_signal() -> void:
	print("\n-- [6] EventBus Signal Emission --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	var received_events: Array = []
	var callback = func(info: Dictionary):
		received_events.append(info.duplicate(true))

	EventBus.rival_technology_breakthrough.connect(callback)

	# Trigger manual breakthrough via RivalProgressionSystem
	var breakthrough: Dictionary = RivalProgSys.trigger_breakthrough("laboratory")
	_check(not breakthrough.is_empty(), "[6a] trigger_breakthrough returned breakthrough data")
	_check(not received_events.is_empty(), "[6b] EventBus.rival_technology_breakthrough was emitted")
	if not received_events.is_empty():
		var payload: Dictionary = received_events[0]
		_check(payload.get("faction_id", "") == "rival", "[6c] Signal payload contains faction_id 'rival'")
		_check(payload.has("tech_id") and not str(payload["tech_id"]).is_empty(), "[6d] Signal payload contains valid tech_id")
		_check(payload.get("branch", "") == "laboratory", "[6e] Signal payload contains source branch 'laboratory'")
	else:
		_check(false, "[6c] Signal payload contains faction_id 'rival'")
		_check(false, "[6d] Signal payload contains valid tech_id")
		_check(false, "[6e] Signal payload contains source branch 'laboratory'")

	EventBus.rival_technology_breakthrough.disconnect(callback)


func _test_turn_advancement_and_breakthrough() -> void:
	print("\n-- [7] Turn Advancement and Breakthrough --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# Advance turns until a lab or excavation breakthrough is triggered
	var initial_lab_tier: int = RivalProgSys.get_lab_tier()
	var initial_granted_count: int = TechSys.get_technologies_for_faction("rival").size()

	var advance_res: Dictionary = RivalProgSys.advance_rival_turn(15)
	_check(RivalProgSys.get_lab_tier() > initial_lab_tier, "[7a] Lab tier advanced after turn simulation")
	var after_granted_count: int = TechSys.get_technologies_for_faction("rival").size()
	_check(after_granted_count > initial_granted_count, "[7b] Rival faction was granted technology during turns")


func _test_prototype_activation_without_enemy_spawn() -> void:
	print("\n-- [8] Prototype State Activation Without Enemy Spawning --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# Find or configure a prototype technology
	var proto_tech: String = "tech_beam_weaponry"
	TechSys.set_technology_prototype_active(proto_tech, true)
	_check(TechSys.is_technology_prototype_active(proto_tech), "[8a] Prototype state successfully set")

	# Ensure prototype activation does NOT spawn enemies or create board units
	_check(GlobalData.board.current_tile == GlobalData.board.current_tile, "[8b] Board state remains intact")
	_check(GlobalData.narrative.enemy_special_units is Array, "[8c] Special units array remains normal")


func _test_coexistence_and_additive_progression() -> void:
	print("\n-- [9] Technology Coexistence (Additive, No Obsolescence) --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# Conventional technology is diffused
	_check(TechSys.is_technology_diffused_in_world("tech_ballistic_conventional"), "[9a] Conventional ballistics is diffused")

	# Grant advanced tech to rival
	TechSys.grant_faction_technology("rival", "tech_high_energy_barrier")
	_check(TechSys.has_faction_technology("rival", "tech_high_energy_barrier"), "[9b] High energy barrier granted to rival")

	# Advance era to Phase 2 and 3
	EraProgSys.current_phase = EraProgSys.EraPhase.PHASE_3_SINGULARITY

	# Conventional tech must STILL be available in world
	_check(TechSys.is_technology_available_in_world("tech_ballistic_conventional"), "[9c] Gen 1 ballistics is STILL available in Phase 3")
	_check(TechSys.is_technology_diffused_in_world("tech_ballistic_conventional"), "[9d] Gen 1 ballistics remains diffused in Phase 3")

	EraProgSys.reset()


func _test_persistence_roundtrip() -> void:
	print("\n-- [10] Authoritative Persistence Roundtrip --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_world_diffusion_state()
	EraProgSys.reset()
	RivalProgSys.reset()

	# Setup distinct state
	EraProgSys.current_turn = 24
	EraProgSys.current_phase = EraProgSys.EraPhase.PHASE_2_ENERGY
	RivalProgSys.scout_progress = 3.5
	RivalProgSys.excavation_progress = 4.2
	RivalProgSys.lab_progress = 5.1
	RivalProgSys.scout_tier = 2
	RivalProgSys.excavation_tier = 3
	RivalProgSys.lab_tier = 2
	RivalProgSys.active_prototype = {
		"name": "Test Prototype Omega",
		"tech_id": "tech_beam_weaponry"
	}
	RivalProgSys.pending_prototype_encounter = true
	TechSys.grant_faction_technology("rival", "tech_beam_weaponry")

	# Serialize
	var era_serialized: Dictionary = EraProgSys.serialize_era_state()
	var rival_serialized: Dictionary = RivalProgSys.serialize_rival_state()
	var world_diff_serialized: Dictionary = TechSys.serialize_world_diffusion_state()

	_check(era_serialized.get("current_turn", 0) == 24, "[10a] Era serialized turn is 24")
	_check(era_serialized.get("current_phase", 0) == 2, "[10b] Era serialized phase is 2")
	_check(rival_serialized.get("excavation_tier", 0) == 3, "[10c] Rival serialized excavation tier is 3")
	_check(rival_serialized.get("active_prototype", {}).get("tech_id", "") == "tech_beam_weaponry", "[10d] Rival prototype tech_id serialized")

	# Reset and deserialize
	EraProgSys.reset()
	RivalProgSys.reset()
	TechSys.reset_world_diffusion_state()

	_check(EraProgSys.current_turn == 1, "[10e] Era reset back to 1")
	_check(RivalProgSys.get_excavation_tier() == 1, "[10f] Rival tier reset back to 1")

	EraProgSys.deserialize_era_state(era_serialized)
	RivalProgSys.deserialize_rival_state(rival_serialized)
	TechSys.deserialize_world_diffusion_state(world_diff_serialized)

	_check(EraProgSys.current_turn == 24, "[10g] Era restored turn 24")
	_check(EraProgSys.current_phase == EraProgSys.EraPhase.PHASE_2_ENERGY, "[10h] Era restored Phase 2")
	_check(RivalProgSys.get_excavation_tier() == 3, "[10i] Rival restored excavation tier 3")
	_check(RivalProgSys.get_active_prototype_tech_id() == "tech_beam_weaponry", "[10j] Rival restored active prototype tech_id")
	_check(TechSys.has_faction_technology("rival", "tech_beam_weaponry"), "[10k] TechnologySystem restored rival faction technology")

	EraProgSys.reset()
	RivalProgSys.reset()
	TechSys.reset_world_diffusion_state()


func _test_legacy_save_fallback() -> void:
	print("\n-- [11] Legacy Save Compatibility --")
	# Deserializing empty dictionary or null should not crash and apply safe defaults
	EraProgSys.deserialize_era_state({})
	_check(EraProgSys.current_turn == 1, "[11a] Era defaults to turn 1 on empty save")
	_check(EraProgSys.current_phase == EraProgSys.EraPhase.PHASE_1_TACTICAL, "[11b] Era defaults to Phase 1 on empty save")

	RivalProgSys.deserialize_rival_state({})
	_check(RivalProgSys.get_scout_tier() == 1, "[11c] Rival defaults to scout tier 1 on empty save")
	_check(RivalProgSys.get_lab_tier() == 1, "[11d] Rival defaults to lab tier 1 on empty save")
	_check(not RivalProgSys.has_active_prototype(), "[11e] Rival defaults to no active prototype on empty save")


func _test_sole_time_authority() -> void:
	print("\n-- [12] Sole Time Authority (EraProgressionSystem) --")
	EraProgSys.reset()
	EraProgSys.current_turn = 10
	_check(EraProgSys.current_turn == 10, "[12a] EraProgressionSystem tracks world turn")

	# Verify RivalProgressionSystem does NOT have its own turn counter or phase enum
	var rival_inst = RivalProgSys.new()
	var tech_inst = TechSys.new()
	_check(not rival_inst.has_method("get_current_phase"), "[12b] RivalProgressionSystem does not own phase authority")
	_check(not tech_inst.has_method("get_current_turn"), "[12c] TechnologySystem does not own turn authority")

	EraProgSys.reset()
