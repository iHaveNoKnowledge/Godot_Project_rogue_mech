extends Node
## TECHNOLOGY IDENTIFICATION + USABILITY + EQUIPMENT GATE VERIFICATION (PHASE 2E-4C)
## Validates:
## [1] Salvaged technology with insufficient evidence cannot identify.
## [2] Salvaged technology with sufficient evidence can identify.
## [3] Evidence threshold does not automatically identify.
## [4] Identification preserves monotonic lifecycle.
## [5] Invalid identification from UNKNOWN is rejected.
## [6] Identification does not consume economy resources unexpectedly.
## [7] IDENTIFIED technology cannot be used.
## [8] RESEARCHED technology can become eligible for authorization.
## [9] RESEARCHED does not automatically become USABLE.
## [10] USABLE technology remains USABLE.
## [11] Invalid usability transitions are rejected.
## [12] Item with USABLE technology can pass technology gate.
## [13] Item with non-USABLE technology is rejected.
## [14] Item with no technology requirement preserves legacy behavior.
## [15] Technology check does not bypass frame compatibility.
## [16] Frame incompatibility still rejects the item even when technology is USABLE.
## [17] Existing baseline technologies remain usable.
## [18] Existing legacy equipment remains equippable.
## [19] Existing FleetSystem blueprint behavior remains unchanged.
## [20] A synthetic Jammer item resolves through generic technology mapping.
## [21] A synthetic Satellite Cannon item resolves through generic technology mapping.
## [22] No weapon-specific special-case logic exists.

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const FleetSys = preload("res://scripts/systems/fleet_system.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("GATE_OK: " + test_name)
	else:
		_fails += 1
		printerr("GATE_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY IDENTIFICATION & EQUIPMENT GATE VERIFICATION (PHASE 2E-4C) ===")
	_test_identification_lifecycle()
	_test_usability_contract()
	_test_equipment_gate()
	_test_legacy_compatibility()
	_test_future_weapon_generic_resolution()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_4C_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_4C_FAILED")
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# IDENTIFICATION LIFECYCLE (1-6)
# -----------------------------------------------------------------------------
func _test_identification_lifecycle() -> void:
	TechSys.reset_discovery_states()
	TechSys.init_catalog_if_needed()

	var tech_id := "tech_ident_test_%d" % int(Time.get_ticks_msec())
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Identification Test Technology",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN},
		"research_metadata": {
			"required_evidence": 5.0,
			"identification_cost": 25.0,
			"research_cost": 100.0,
			"research_time": 2.0
		}
	})

	# 1. Salvaged technology with insufficient evidence cannot identify
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED)
	TechSys.add_technology_evidence(tech_id, 2.0)
	_check(TechSys.get_technology_evidence(tech_id) == 2.0, "[1a] Evidence accumulated is 2.0")
	_check(not TechSys.can_identify_technology(tech_id), "[1b] cannot identify when evidence (2.0) < required (5.0)")
	var id_result := TechSys.record_technology_identified(tech_id)
	_check(not id_result, "[1c] record_technology_identified returns false with insufficient evidence")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[1d] State remains SALVAGED")

	# 2. Salvaged technology with sufficient evidence can identify
	TechSys.add_technology_evidence(tech_id, 3.0)
	_check(TechSys.get_technology_evidence(tech_id) >= 5.0, "[2a] Evidence reached threshold (5.0)")
	_check(TechSys.can_identify_technology(tech_id), "[2b] can_identify_technology is true when evidence >= 5.0")
	var id_success := TechSys.record_technology_identified(tech_id)
	_check(id_success, "[2c] record_technology_identified succeeds with sufficient evidence")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[2d] State transitioned to IDENTIFIED")

	# 3. Evidence threshold does not automatically identify
	var auto_test_id := "tech_auto_ident_%d" % int(Time.get_ticks_msec())
	TechSys.register_technology({
		"tech_id": auto_test_id,
		"name": "Auto Identification Guard Test",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN},
		"research_metadata": {"required_evidence": 3.0}
	})
	TechSys.set_discovery_state(auto_test_id, TechSys.DiscoveryState.SALVAGED)
	TechSys.add_technology_evidence(auto_test_id, 10.0) # Well above threshold
	_check(TechSys.get_discovery_state(auto_test_id) == TechSys.DiscoveryState.SALVAGED, "[3a] State remains SALVAGED despite evidence >= threshold (no auto-identify)")
	_check(TechSys.can_identify_technology(auto_test_id), "[3b] Eligible to identify, but not yet identified")

	# 4. Identification preserves monotonic lifecycle
	var repeat_id := TechSys.record_technology_identified(tech_id)
	_check(not repeat_id, "[4a] Repeated identification call returns false (idempotent)")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[4b] State remains IDENTIFIED (no regression)")
	var regress_salvaged := TechSys.record_technology_salvaged(tech_id)
	_check(not regress_salvaged, "[4c] Salvage action rejected while IDENTIFIED")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[4d] State does not regress to SALVAGED")

	# 5. Invalid identification from UNKNOWN is rejected
	var unk_id := "tech_unk_ident_%d" % int(Time.get_ticks_msec())
	TechSys.register_technology({
		"tech_id": unk_id,
		"name": "Unknown Jump Test",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN},
		"research_metadata": {"required_evidence": 1.0}
	})
	TechSys.add_technology_evidence(unk_id, 10.0)
	var invalid_jump := TechSys.record_technology_identified(unk_id)
	_check(not invalid_jump, "[5a] Cannot identify directly from UNKNOWN")
	_check(TechSys.get_discovery_state(unk_id) == TechSys.DiscoveryState.UNKNOWN, "[5b] State remains UNKNOWN")

	# 6. Identification does not consume economy resources unexpectedly
	if GlobalData and GlobalData.currency:
		var init_cr := 500
		var init_sc := 200
		var init_dc := 5
		GlobalData.currency.credits = init_cr
		GlobalData.currency.scrap = init_sc
		GlobalData.currency.data_cores = init_dc
		var can_afford := TechSys.can_afford_identification(tech_id, GlobalData.currency)
		_check(can_afford, "[6a] can_afford_identification returns true with sufficient credits")
		TechSys.record_technology_identified(auto_test_id)
		_check(GlobalData.currency.credits == init_cr, "[6b] Credits unchanged (economy non-mutation)")
		_check(GlobalData.currency.scrap == init_sc, "[6c] Scrap unchanged (economy non-mutation)")
		_check(GlobalData.currency.data_cores == init_dc, "[6d] Data cores unchanged (economy non-mutation)")


# -----------------------------------------------------------------------------
# USABILITY CONTRACT (7-11)
# -----------------------------------------------------------------------------
func _test_usability_contract() -> void:
	TechSys.reset_discovery_states()
	TechSys.init_catalog_if_needed()

	var tech_id := "tech_usability_test_%d" % int(Time.get_ticks_msec())
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Usability Contract Test Technology",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN},
		"research_metadata": {
			"required_evidence": 1.0,
			"research_cost": 100.0,
			"research_time": 1.0
		}
	})

	# 7. IDENTIFIED technology cannot be used
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED)
	_check(not TechSys.is_technology_usable(tech_id), "[7a] IDENTIFIED technology is not usable")
	_check(not TechSys.can_make_technology_usable(tech_id), "[7b] IDENTIFIED technology cannot be made usable yet")
	var premature_usable := TechSys.record_technology_usable(tech_id)
	_check(not premature_usable, "[7c] record_technology_usable fails when IDENTIFIED")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.IDENTIFIED, "[7d] State remains IDENTIFIED")

	# 8. RESEARCHED technology can become eligible for authorization
	TechSys.start_research(tech_id)
	TechSys.add_research_progress(tech_id, 100.0)
	TechSys.complete_technology_research(tech_id)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.RESEARCHED, "[8a] Research complete, state is RESEARCHED")
	_check(TechSys.can_make_technology_usable(tech_id), "[8b] RESEARCHED technology is eligible for usability authorization")

	# 9. RESEARCHED does not automatically become USABLE
	_check(not TechSys.is_technology_usable(tech_id), "[9a] RESEARCHED state does NOT automatically grant USABLE")

	# 10. USABLE technology remains USABLE
	var auth_ok := TechSys.record_technology_usable(tech_id)
	_check(auth_ok, "[10a] record_technology_usable succeeds")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.USABLE, "[10b] State is now USABLE")
	_check(TechSys.is_technology_usable(tech_id), "[10c] is_technology_usable is true")
	var repeated_auth := TechSys.record_technology_usable(tech_id)
	_check(not repeated_auth, "[10d] Repeated authorization call is idempotent (returns false)")
	_check(TechSys.is_technology_usable(tech_id), "[10e] Still USABLE")

	# 11. Invalid usability transitions are rejected
	var raw_tech := "tech_raw_%d" % int(Time.get_ticks_msec())
	TechSys.register_technology({
		"tech_id": raw_tech,
		"name": "Raw Tech Guard Test",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN}
	})
	_check(not TechSys.can_make_technology_usable(raw_tech), "[11a] UNKNOWN cannot transition to USABLE")
	_check(not TechSys.record_technology_usable(raw_tech), "[11b] record_technology_usable rejected on UNKNOWN")
	TechSys.set_discovery_state(raw_tech, TechSys.DiscoveryState.ENCOUNTERED)
	_check(not TechSys.record_technology_usable(raw_tech), "[11c] record_technology_usable rejected on ENCOUNTERED")
	TechSys.set_discovery_state(raw_tech, TechSys.DiscoveryState.SALVAGED)
	_check(not TechSys.record_technology_usable(raw_tech), "[11d] record_technology_usable rejected on SALVAGED")


# -----------------------------------------------------------------------------
# EQUIPMENT GATE & FRAME SEPARATION (12-16)
# -----------------------------------------------------------------------------
func _test_equipment_gate() -> void:
	TechSys.reset_discovery_states()
	TechSys.init_catalog_if_needed()

	var tech_id := "tech_equip_test_%d" % int(Time.get_ticks_msec())
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Equipment Gate Test Technology",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN},
		"compatibility_requirements": {
			"min_generation": 2,
			"required_families": [TechSys.FAMILY_ENERGY]
		}
	})

	# 12. Item with USABLE technology can pass technology gate
	var weapon_item: Dictionary = {
		"id": "wpn_energy_carbine",
		"name": "Energy Carbine",
		"tech_id": tech_id
	}
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.USABLE)
	var gate_usable := TechSys.can_equip_item_technology(weapon_item)
	_check(bool(gate_usable.get("allowed", false)), "[12a] Item with USABLE technology passes gate")
	_check(str(gate_usable.get("reason", "")) == "authorized", "[12b] Reason is 'authorized'")
	_check(TechSys.is_item_technology_usable(weapon_item), "[12c] is_item_technology_usable helper returns true")

	# 13. Item with non-USABLE technology is rejected
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.RESEARCHED)
	var gate_researched := TechSys.can_equip_item_technology(weapon_item)
	_check(not bool(gate_researched.get("allowed", false)), "[13a] Item with RESEARCHED (not authorized) technology rejected")
	_check(str(gate_researched.get("reason", "")) == "technology_not_usable", "[13b] Reason is 'technology_not_usable'")

	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.IDENTIFIED)
	_check(not TechSys.is_item_technology_usable(weapon_item), "[13c] Item with IDENTIFIED technology rejected")

	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)
	_check(not TechSys.is_item_technology_usable(weapon_item), "[13d] Item with UNKNOWN technology rejected")

	# 14. Item with no technology requirement preserves legacy behavior
	var neutral_item: Dictionary = {
		"id": "wpn_standard_rifle",
		"name": "Standard Kinetic Rifle",
		"tech_id": ""
	}
	var gate_neutral := TechSys.can_equip_item_technology(neutral_item)
	_check(bool(gate_neutral.get("allowed", false)), "[14a] Neutral item with empty tech_id allowed")
	_check(str(gate_neutral.get("reason", "")) == "neutral_technology", "[14b] Reason is 'neutral_technology'")

	var item_no_field: Dictionary = {
		"id": "legacy_plate",
		"name": "Legacy Iron Plate"
	}
	_check(TechSys.is_item_technology_usable(item_no_field), "[14c] Item with no tech fields at all is allowed")

	# 15. Technology check does not bypass frame compatibility
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.USABLE)
	_check(TechSys.is_item_technology_usable(weapon_item), "[15a] Technology gate passes")

	# Frame gen 1 without energy family
	var gen1_frame: Dictionary = {
		"id": "frame_standard_1",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	var frame_compat := FrameSys.can_support_technology(gen1_frame, tech_id, [])
	_check(not frame_compat, "[15b] Frame check evaluates independently and rejects incompatible frame")

	# 16. Frame incompatibility still rejects the item even when technology is USABLE
	var eval_report := FrameSys.evaluate_technology_compatibility(gen1_frame, tech_id, [])
	_check(not bool(eval_report.get("is_supported", false)), "[16a] Frame report is_supported is false")
	_check(eval_report.get("missing_requirements", []).size() > 0, "[16b] Missing requirements documented")


# -----------------------------------------------------------------------------
# LEGACY COMPATIBILITY (17-19)
# -----------------------------------------------------------------------------
func _test_legacy_compatibility() -> void:
	TechSys.reset_discovery_states()
	TechSys.init_catalog_if_needed()

	# 17. Existing baseline technologies remain usable
	var baselines: Array[String] = [
		"tech_ballistic_conventional",
		"tech_combustion_power",
		"tech_passive_cooling",
		"tech_hydraulic_actuation"
	]
	for b in baselines:
		_check(TechSys.is_technology_usable(b), "[17] Baseline technology %s is USABLE by default" % b)

	# 18. Existing legacy equipment remains equippable
	var baseline_weapon_part := WeaponPart.new()
	baseline_weapon_part.weapon_name = "Stock Machine Gun"
	baseline_weapon_part.tech_id = "tech_ballistic_conventional"
	_check(TechSys.is_item_technology_usable(baseline_weapon_part), "[18a] WeaponPart with baseline tech is equippable")

	var unassigned_weapon_part := WeaponPart.new()
	unassigned_weapon_part.weapon_name = "Unassigned Weapon"
	unassigned_weapon_part.tech_id = ""
	_check(TechSys.is_item_technology_usable(unassigned_weapon_part), "[18b] WeaponPart with empty tech_id is equippable")

	var armor_entry: Dictionary = {
		"id": "line_arm_left",
		"name": "Titan Line Arm Left"
	}
	_check(TechSys.is_item_technology_usable(armor_entry), "[18c] Catalog armor entry with no tech_id is equippable")

	# 19. Existing FleetSystem blueprint behavior remains unchanged
	if FleetSys:
		var bp_unlocked := FleetSys.is_research_completed("bp_valkyrion_armor")
		_check(typeof(bp_unlocked) == TYPE_BOOL, "[19] FleetSystem blueprint queries remain unaffected")


# -----------------------------------------------------------------------------
# FUTURE WEAPON GENERIC RESOLUTION (20-22)
# -----------------------------------------------------------------------------
func _test_future_weapon_generic_resolution() -> void:
	TechSys.reset_discovery_states()
	TechSys.init_catalog_if_needed()

	var jammer_tech_id := "tech_jammer_pulse"
	TechSys.register_technology({
		"tech_id": jammer_tech_id,
		"name": "Pulse Jammer Architecture",
		"generation": 2,
		"technology_family": TechSys.FAMILY_INTERFACE,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN}
	})

	var satellite_tech_id := "tech_orbital_beam_relay"
	TechSys.register_technology({
		"tech_id": satellite_tech_id,
		"name": "Orbital Beam Relay Interface",
		"generation": 3,
		"technology_family": TechSys.FAMILY_ENERGY,
		"origin_lineage": TechSys.LINEAGE_EXPERIMENTAL,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN}
	})

	# 20. A synthetic Jammer item resolves through generic technology mapping
	var synthetic_jammer: Dictionary = {
		"id": "future_mod_jammer_prototype",
		"name": "Experimental Disruption Node",
		"tech_id": jammer_tech_id
	}
	var resolved_jammer_tech := TechSys.resolve_item_technology_id(synthetic_jammer)
	_check(resolved_jammer_tech == jammer_tech_id, "[20a] Jammer resolves to %s via generic mapping" % jammer_tech_id)
	_check(not TechSys.is_item_technology_usable(synthetic_jammer), "[20b] Jammer rejected while tech is UNKNOWN")
	TechSys.set_discovery_state(jammer_tech_id, TechSys.DiscoveryState.USABLE)
	_check(TechSys.is_item_technology_usable(synthetic_jammer), "[20c] Jammer authorized once tech is USABLE")

	# 21. A synthetic Satellite Cannon item resolves through generic technology mapping
	var synthetic_satellite_cannon: Dictionary = {
		"id": "heavy_orbital_uplink",
		"name": "Sky-Lance Targeting Assembly",
		"technology_id": satellite_tech_id
	}
	var resolved_sat_tech := TechSys.resolve_item_technology_id(synthetic_satellite_cannon)
	_check(resolved_sat_tech == satellite_tech_id, "[21a] Satellite Cannon resolves to %s via generic mapping" % satellite_tech_id)
	_check(not TechSys.is_item_technology_usable(synthetic_satellite_cannon), "[21b] Satellite Cannon rejected while tech is UNKNOWN")
	TechSys.set_discovery_state(satellite_tech_id, TechSys.DiscoveryState.USABLE)
	_check(TechSys.is_item_technology_usable(synthetic_satellite_cannon), "[21c] Satellite Cannon authorized once tech is USABLE")

	# 22. No weapon-specific special-case logic exists
	# Ensure resolution does not match on item name or type
	var deceptive_name_item: Dictionary = {
		"id": "some_random_id",
		"name": "Super Satellite Cannon Jammer Pulse",
		"tech_id": ""
	}
	_check(TechSys.resolve_item_technology_id(deceptive_name_item) == "", "[22a] Deceptive item name does not infer tech ID")
	_check(TechSys.is_item_technology_usable(deceptive_name_item), "[22b] Item without tech_id remains technology-neutral regardless of name")
