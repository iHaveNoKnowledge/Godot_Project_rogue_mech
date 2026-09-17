extends Node
## TECHNOLOGY FOUNDATION VERIFICATION (PHASE 2D)
## Validates the authoritative TechnologySystem:
## 1. Technology definition registration
## 2. Technology lookup & catalog queries
## 3. Generation metadata (not a power level)
## 4. Technology family metadata (neutral taxonomy)
## 5. Era association & plausibility queries
## 6. Unknown discovery state as safe default
## 7. Discovery state progression (UNKNOWN -> USABLE)
## 8. Direct compatibility evaluation
## 9. Bridged compatibility evaluation
## 10. Incompatible technology evaluation
## 11. Old Valkren frame + bridge module compatibility
## 12. New frame (Valkryon) + native technology compatibility
## 13. Mixed-generation equipment coexistence
## 14. Technology compatibility independent of FrameSet completion
## 15. Technology metadata does not alter existing damage math
## 16. Technology metadata does not alter authoritative weight calculation
## 17. Save/load compatibility & round-trip persistence

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const FrameModSys = preload("res://scripts/systems/frame_module_system.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("TECH_OK: " + test_name)
	else:
		_fails += 1
		printerr("TECH_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY FOUNDATION VERIFICATION (PHASE 2D) ===")
	_test_registration_and_lookup()
	_test_generation_and_family_metadata()
	_test_era_plausibility()
	_test_discovery_state_progression()
	_test_direct_compatibility()
	_test_bridged_compatibility_and_modernization()
	_test_incompatible_technology()
	_test_valkryon_native_compatibility()
	_test_mixed_generation_coexistence()
	_test_frameset_independence()
	_test_damage_and_weight_invariance()
	_test_save_load_compatibility()

	print("\n=== TECHNOLOGY TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_TECHNOLOGY_FOUNDATION_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("SOME_TECHNOLOGY_TESTS_FAILED")
		get_tree().quit(1)


func _test_registration_and_lookup() -> void:
	print("\n-- [1-2] Registration & Lookup --")
	TechSys.init_catalog_if_needed()

	_check(TechSys.has_technology("tech_ballistic_conventional"), "[1a] Default ballistic tech is registered")
	_check(TechSys.has_technology("tech_beam_weaponry"), "[1b] Default beam tech is registered")
	_check(TechSys.has_technology("tech_valkryon_actuator_chassis"), "[1c] Valkryon actuator tech is registered")

	var def := TechSys.get_technology_definition("tech_ballistic_conventional")
	_check(def.get("tech_id", "") == "tech_ballistic_conventional", "[2a] Definition lookup returns correct tech_id")
	_check(def.get("name", "") != "", "[2b] Definition contains readable name")

	# Register custom test tech dynamically
	TechSys.register_technology({
		"tech_id": "tech_test_experimental_sensor",
		"name": "Experimental Micro-Radar Array",
		"generation": 2,
		"technology_family": TechSys.FAMILY_INTERFACE,
		"era_phase_req": 2,
		"origin_lineage": TechSys.LINEAGE_COMMON,
		"tags": ["sensor", "radar"],
		"prerequisites": [],
		"compatibility_requirements": {"min_generation": 2},
		"description": "Test dynamic registration"
	})
	_check(TechSys.has_technology("tech_test_experimental_sensor"), "[2c] Dynamic technology registration succeeds")
	var dyn_def := TechSys.get_technology_definition("tech_test_experimental_sensor")
	_check(dyn_def.get("generation", 0) == 2, "[2d] Dynamic definition preserves generation")


func _test_generation_and_family_metadata() -> void:
	print("\n-- [3-4] Generation & Family Metadata --")
	var ballistics := TechSys.get_technologies_by_family(TechSys.FAMILY_BALLISTIC)
	_check(ballistics.size() >= 1, "[3a] get_technologies_by_family returns ballistic list")

	var gen1_list := TechSys.get_technologies_by_generation(1)
	var gen2_list := TechSys.get_technologies_by_generation(2)
	var gen3_list := TechSys.get_technologies_by_generation(3)

	_check(gen1_list.size() >= 3, "[3b] Generation 1 baseline has multiple technologies")
	_check(gen2_list.size() >= 2, "[3c] Generation 2 contains modern technologies")
	_check(gen3_list.size() >= 2, "[3d] Generation 3 contains advanced technologies")

	# Verify generation describes lineage, not an automatic damage multiplier
	var b_def := TechSys.get_technology_definition("tech_ballistic_conventional")
	_check(not b_def.has("damage_multiplier"), "[4a] Generation definition does not hardcode damage_multiplier")
	_check(not b_def.has("power_level"), "[4b] Generation definition does not hardcode power_level")


func _test_era_plausibility() -> void:
	print("\n-- [5] Era Plausibility Queries --")
	# Era 1 (Tactical): Gen 1 plausible, Gen 2 & 3 not plausible by default
	_check(TechSys.is_technology_plausible_in_era("tech_ballistic_conventional", 1), "[5a] Gen 1 plausible in Era 1")
	_check(not TechSys.is_technology_plausible_in_era("tech_beam_weaponry", 1), "[5b] Gen 2 not plausible in Era 1")
	_check(not TechSys.is_technology_plausible_in_era("tech_valkryon_actuator_chassis", 1), "[5c] Gen 3 not plausible in Era 1")

	# Era 2 (Energy): Gen 1 & Gen 2 plausible
	_check(TechSys.is_technology_plausible_in_era("tech_ballistic_conventional", 2), "[5d] Gen 1 remains plausible in Era 2 (no obsolescence)")
	_check(TechSys.is_technology_plausible_in_era("tech_beam_weaponry", 2), "[5e] Gen 2 is plausible in Era 2")
	_check(not TechSys.is_technology_plausible_in_era("tech_valkryon_actuator_chassis", 2), "[5f] Gen 3 not plausible in Era 2")

	# Era 3 (Advanced): All plausible
	_check(TechSys.is_technology_plausible_in_era("tech_valkryon_actuator_chassis", 3), "[5g] Gen 3 is plausible in Era 3")
	_check(TechSys.is_technology_plausible_in_era("tech_ballistic_conventional", 3), "[5h] Gen 1 still coexists in Era 3")


func _test_discovery_state_progression() -> void:
	print("\n-- [6-7] Discovery State Progression --")
	TechSys.reset_discovery_states()

	# Unknown is default
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "[6a] Default state for unresearched tech is UNKNOWN")
	_check(TechSys.get_discovery_state_name("tech_beam_weaponry") == "UNKNOWN", "[6b] Discovery state name reports UNKNOWN")
	_check(not TechSys.is_technology_usable("tech_beam_weaponry"), "[6c] UNKNOWN tech is not usable")

	# Advance: UNKNOWN -> ENCOUNTERED
	var adv1 := TechSys.advance_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.ENCOUNTERED)
	_check(adv1, "[7a] Advancing to ENCOUNTERED succeeds")
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.ENCOUNTERED, "[7b] Current state is ENCOUNTERED")
	_check(not TechSys.is_technology_usable("tech_beam_weaponry"), "[7c] ENCOUNTERED tech is still not usable")

	# Advance: ENCOUNTERED -> SALVAGED
	TechSys.advance_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.SALVAGED)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[7d] Current state is SALVAGED")

	# Advance: SALVAGED -> IDENTIFIED
	TechSys.advance_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.IDENTIFIED)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.IDENTIFIED, "[7e] Current state is IDENTIFIED")

	# Advance: IDENTIFIED -> RESEARCHED
	TechSys.advance_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.RESEARCHED)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.RESEARCHED, "[7f] Current state is RESEARCHED")

	# Advance: RESEARCHED -> USABLE
	TechSys.advance_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.USABLE)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.USABLE, "[7g] Current state is USABLE")
	_check(TechSys.is_technology_usable("tech_beam_weaponry"), "[7h] USABLE reports true")

	# Monotonic safety: Cannot advance to a lower state with advance_discovery_state
	var regressed := TechSys.advance_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.ENCOUNTERED)
	_check(not regressed, "[7i] advance_discovery_state refuses regression")
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.USABLE, "[7j] State remains USABLE after rejected regression")


func _test_direct_compatibility() -> void:
	print("\n-- [8] Direct Compatibility Evaluation --")
	# Conventional Valkren frame: Gen 1, lineage "valkren", supported families ["all"]
	var old_frame: Dictionary = {
		"id": "frame_body_01",
		"name": "Standard Steel Frame",
		"technology_lineage": TechSys.LINEAGE_VALKREN,
		"native_generation": 1,
		"supported_families": ["all"]
	}

	var rep := TechSys.evaluate_frame_technology_compatibility(old_frame, "tech_ballistic_conventional")
	_check(rep.get("status") == TechSys.CompatibilityStatus.DIRECT, "[8a] Gen 1 ballistic on Gen 1 frame is DIRECT")
	_check(rep.get("is_supported") == true, "[8b] DIRECT compatibility reports is_supported = true")
	_check(rep.get("missing_requirements", []).is_empty(), "[8c] DIRECT compatibility has 0 missing requirements")
	_check(FrameSys.can_support_technology(old_frame, "tech_ballistic_conventional"), "[8d] FrameSys.can_support_technology returns true for DIRECT")


func _test_bridged_compatibility_and_modernization() -> void:
	print("\n-- [9, 11] Bridged Compatibility (Modernizing Valkren) --")
	# Old Valkren frame (Gen 1) trying to mount Gen 2 Beam Weaponry
	var old_valkren: Dictionary = {
		"id": "frame_body_01",
		"name": "Old Valkren Frame",
		"technology_lineage": TechSys.LINEAGE_VALKREN,
		"native_generation": 1,
		"supported_families": ["all"]
	}

	# Without bridge module: Should fail because tech_beam_weaponry requires Gen 2 & energy_interface bridge tag
	var rep_unbridged := TechSys.evaluate_frame_technology_compatibility(old_valkren, "tech_beam_weaponry", [])
	_check(rep_unbridged.get("status") == TechSys.CompatibilityStatus.INCOMPATIBLE, "[9a] Old Valkren without bridge cannot support Gen 2 beam tech")
	_check(rep_unbridged.get("is_supported") == false, "[9b] Unbridged is_supported is false")

	# Install Technology Bridge: Modular Energy Converter
	var energy_bridge: Dictionary = {
		"id": "modular_energy_converter",
		"bridge_capabilities": {
			"bridges_generation_up_to": 2,
			"bridges_families": ["energy", "interface"],
			"bridge_tags": ["energy_interface"]
		}
	}

	var rep_bridged := TechSys.evaluate_frame_technology_compatibility(old_valkren, "tech_beam_weaponry", [energy_bridge])
	_check(rep_bridged.get("status") == TechSys.CompatibilityStatus.BRIDGED, "[11a] Old Valkren + Energy Bridge achieves BRIDGED status for Gen 2 beam")
	_check(rep_bridged.get("is_supported") == true, "[11b] BRIDGED is_supported is true")
	_check(rep_bridged.get("missing_requirements", []).is_empty(), "[11c] BRIDGED has no missing requirements")
	_check(FrameSys.can_support_technology(old_valkren, "tech_beam_weaponry", [energy_bridge]), "[11d] FrameSys queries support through installed bridges")

	# Test FrameModSys.bridges_technology helper
	_check(FrameModSys.bridges_technology("modular_energy_converter", "tech_beam_weaponry"), "[11e] FrameModSys identifies bridge capability for tech")


func _test_incompatible_technology() -> void:
	print("\n-- [10] Incompatible Technology Evaluation --")
	# Frame without adequate bridges trying to mount Gen 3 technology
	var old_valkren: Dictionary = {
		"id": "frame_body_01",
		"technology_lineage": TechSys.LINEAGE_VALKREN,
		"native_generation": 1,
		"supported_families": ["ballistic", "power"]
	}

	# Bridge only reaches Gen 2
	var gen2_bridge: Dictionary = {
		"bridge_capabilities": {
			"bridges_generation_up_to": 2,
			"bridges_families": ["energy"],
			"bridge_tags": ["energy_interface"]
		}
	}

	var rep := TechSys.evaluate_frame_technology_compatibility(old_valkren, "tech_valkryon_actuator_chassis", [gen2_bridge])
	_check(rep.get("status") == TechSys.CompatibilityStatus.INCOMPATIBLE, "[10a] Gen 2 bridge cannot bridge Gen 3 Valkryon tech")
	_check(rep.get("is_supported") == false, "[10b] Incompatible reports is_supported = false")
	_check(rep.get("missing_requirements", []).size() >= 1, "[10c] Missing requirements list contains reasons")


func _test_valkryon_native_compatibility() -> void:
	print("\n-- [12] Valkryon Advanced Frame Native Compatibility --")
	# Valkryon Frame: Gen 3 native, lineage "valkryon"
	var valkryon_frame: Dictionary = {
		"id": "frame_body_valkyrion",
		"name": "Valkryon Unified Spinal Core",
		"technology_lineage": TechSys.LINEAGE_VALKRYON,
		"native_generation": 3,
		"supported_families": ["all"]
	}

	# Valkryon natively supports Gen 3 Valkryon tech without any bridge modules!
	var rep := TechSys.evaluate_frame_technology_compatibility(valkryon_frame, "tech_valkryon_actuator_chassis")
	_check(rep.get("status") == TechSys.CompatibilityStatus.DIRECT, "[12a] Valkryon frame natively supports Gen 3 Valkryon tech DIRECTLY")
	_check(rep.get("is_supported") == true, "[12b] Valkryon is_supported is true without bridges")

	# Valkryon also natively supports Gen 1 and Gen 2 common tech
	var rep_gen1 := TechSys.evaluate_frame_technology_compatibility(valkryon_frame, "tech_ballistic_conventional")
	_check(rep_gen1.get("status") == TechSys.CompatibilityStatus.DIRECT, "[12c] Valkryon frame supports Gen 1 ballistics DIRECTLY")


func _test_mixed_generation_coexistence() -> void:
	print("\n-- [13] Mixed-Generation Equipment Coexistence --")
	# An old Valkren frame can carry Gen 1 ballistics AND Gen 2 beam tech (via bridge) simultaneously!
	var modernized_valkren: Dictionary = {
		"id": "frame_body_01",
		"technology_lineage": TechSys.LINEAGE_VALKREN,
		"native_generation": 1,
		"supported_families": ["all"]
	}
	var energy_bridge: Dictionary = {
		"bridge_capabilities": {
			"bridges_generation_up_to": 2,
			"bridges_families": ["energy"],
			"bridge_tags": ["energy_interface"]
		}
	}

	var can_gen1 := TechSys.can_frame_support_technology(modernized_valkren, "tech_ballistic_conventional", [energy_bridge])
	var can_gen2 := TechSys.can_frame_support_technology(modernized_valkren, "tech_beam_weaponry", [energy_bridge])

	_check(can_gen1 and can_gen2, "[13a] Modernized frame supports both Gen 1 ballistics and Gen 2 beam simultaneously")
	_check(TechSys.has_technology("tech_ballistic_conventional") and TechSys.has_technology("tech_beam_weaponry"), "[13b] Technologies coexist in catalog without overwriting")


func _test_frameset_independence() -> void:
	print("\n-- [14] Technology Compatibility Independent of FrameSet Completion --")
	# FrameSet is incidental; a mech with 0 set bonuses or broken sets must still evaluate technology strictly through frame & bridge capabilities
	var mixed_frame_data: Dictionary = {
		"id": "frame_body_custom",
		"frame_set_id": "none",
		"technology_lineage": TechSys.LINEAGE_VALKREN,
		"native_generation": 1,
		"supported_families": ["all"]
	}
	var bridge: Dictionary = {
		"bridge_capabilities": {
			"bridges_generation_up_to": 2,
			"bridges_families": ["energy"],
			"bridge_tags": ["energy_interface"]
		}
	}

	var rep := TechSys.evaluate_frame_technology_compatibility(mixed_frame_data, "tech_beam_weaponry", [bridge])
	_check(rep.get("status") == TechSys.CompatibilityStatus.BRIDGED, "[14a] Compatibility succeeds even with frame_set_id = 'none'")
	_check(rep.get("is_supported") == true, "[14b] Technology compatibility does NOT require a 6-piece or 2-piece set bonus")


func _test_damage_and_weight_invariance() -> void:
	print("\n-- [15-16] Damage Math & Weight Invariance --")
	# 1. Base catalog definition queries remain completely unmutated
	var cat_weight := FrameSys.get_frame_weight("frame_body_01")
	var cat_hp := FrameSys.get_frame_hp("frame_body_01")
	_check(cat_weight == 6.0, "[16a] Catalog frame weight remains exactly 6.0 kg (unmutated by technology layer)")
	_check(cat_hp == 40.0, "[15a] Catalog frame HP remains exactly 40.0 (unmutated by technology layer)")

	# 2. Total equipped frame queries remain authoritative and unmutated
	GlobalData.weapons.equipped_frames.clear()
	GlobalData.weapons.equipped_frames["body"] = {
		"id": "frame_body_01",
		"weight": 8.0,
		"hp": 90.0,
		"technology_lineage": TechSys.LINEAGE_VALKREN,
		"native_generation": 1
	}
	var total_weight := FrameSys.get_total_frame_weight()
	_check(total_weight == 8.0, "[16b] Total frame weight query operates normally")
	var eq_hp := FrameSys.get_frame_hp(GlobalData.weapons.equipped_frames["body"])
	_check(eq_hp == 90.0, "[15b] Equipped frame instance preserves custom HP (90.0)")


func _test_save_load_compatibility() -> void:
	print("\n-- [17] Save / Load Compatibility --")
	TechSys.reset_discovery_states()
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.SALVAGED)
	TechSys.set_discovery_state("tech_cryo_cooling", TechSys.DiscoveryState.RESEARCHED)

	var serialized := TechSys.serialize_discovery_states()
	_check(serialized.get("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[17a] Serialized discovery dictionary contains salvaged tech")
	_check(serialized.get("tech_cryo_cooling") == TechSys.DiscoveryState.RESEARCHED, "[17b] Serialized discovery dictionary contains researched tech")

	# Clear and restore
	TechSys.reset_discovery_states()
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "[17c] Reset clears state to UNKNOWN")

	TechSys.deserialize_discovery_states(serialized)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.SALVAGED, "[17d] Restored discovery state accurately preserves SALVAGED")
	_check(TechSys.get_discovery_state("tech_cryo_cooling") == TechSys.DiscoveryState.RESEARCHED, "[17e] Restored discovery state accurately preserves RESEARCHED")

	# Older save simulation: Empty or missing dictionary should safely fallback without crashing
	TechSys.deserialize_discovery_states({})
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "[17f] Missing/empty save data safely defaults to UNKNOWN")
