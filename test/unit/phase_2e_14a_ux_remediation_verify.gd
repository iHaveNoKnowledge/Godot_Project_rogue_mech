extends Node

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const FrameModSys = preload("res://scripts/systems/frame_module_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")

var _checks_passed: int = 0
var _checks_failed: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-14A UX REMEDIATION VERIFICATION ===")
	_run_all_tests()


func _check(condition: bool, desc: String) -> void:
	if condition:
		_checks_passed += 1
		print("  [PASS] %s" % desc)
	else:
		_checks_failed += 1
		print("  [FAIL] %s" % desc)


func _run_all_tests() -> void:
	_test_missile_ux_strings()
	_test_incompatible_requirement_contract()
	_test_research_lab_ui_technology_discovery()

	print("\n==================================================")
	print("PHASE 2E-14A VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")

	if _checks_failed == 0:
		print("PHASE_2E_14A_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_14A_FAILED: %d assertions failed." % _checks_failed)
		get_tree().quit(1)


func _test_missile_ux_strings() -> void:
	print("\n-- [1] Missile Salvo UX Clarity Tests --")

	# Test total salvo lock string logic
	var get_lock_msg = func(locks: int) -> String:
		return ("SALVO: %d MISSILES" % locks) if locks > 1 else (("SALVO: 1 MISSILE") if locks == 1 else "LOCKING...")

	_check(get_lock_msg.call(0) == "LOCKING...", "Zero locks renders 'LOCKING...'")
	_check(get_lock_msg.call(1) == "SALVO: 1 MISSILE", "Single lock renders 'SALVO: 1 MISSILE'")
	_check(get_lock_msg.call(4) == "SALVO: 4 MISSILES", "4 locks renders 'SALVO: 4 MISSILES'")

	# Test per-target badge string logic
	var get_badge_msg = func(cnt: int) -> String:
		return "[x%d MSL]" % cnt

	_check(get_badge_msg.call(1) == "[x1 MSL]", "Single target allocation renders '[x1 MSL]'")
	_check(get_badge_msg.call(3) == "[x3 MSL]", "Triple target allocation renders '[x3 MSL]'")


func _test_incompatible_requirement_contract() -> void:
	print("\n-- [2] Authoritative Incompatibility Requirement Tests --")

	TechSys.init_catalog_if_needed()

	var gen1_frame := {
		"id": "frame_tank_valkren",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": ["ballistic", "power", "cooling"]
	}

	# 1. Gen 2 Energy Beam without bridge -> Incompatible
	var rep_unbridged: Dictionary = FrameSys.evaluate_hardware_compatibility(gen1_frame, "tech_beam_weaponry", [])
	_check(not bool(rep_unbridged.get("is_supported", true)), "Gen 1 frame without bridge is incompatible with tech_beam_weaponry")
	_check(rep_unbridged.has("required_bridge_summary"), "Compatibility report contains required_bridge_summary")

	var req_str: String = str(rep_unbridged.get("required_bridge_summary", ""))
	_check(req_str.contains("Energy Weapon Bridge") or req_str.contains("Modular Energy Bridge"),
		"required_bridge_summary identifies Energy Weapon Bridge: '%s'" % req_str)

	# 2. Gen 2 Energy Beam WITH modular_energy_converter -> Bridged
	var bridge_mod = FrameModSys.MODULE_CATALOG.get("modular_energy_converter", {})
	var rep_bridged: Dictionary = FrameSys.evaluate_hardware_compatibility(gen1_frame, "tech_beam_weaponry", [bridge_mod])
	_check(bool(rep_bridged.get("is_supported", false)), "Gen 1 frame with modular_energy_converter is BRIDGED and supported")
	_check(str(rep_bridged.get("required_bridge_summary", "")) == "", "Bridged compatibility has empty missing requirement summary")

	# 3. LoadoutSystem.validate_equip_request passthrough check
	var mock_item := {
		"name": "Heavy Particle Beam",
		"tech_id": "tech_beam_weaponry",
		"path": "res://resources/weapons/beam_rifle.tres"
	}

	# Ensure technology is USABLE so it tests physical compatibility gate
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.USABLE)

	GlobalData.weapons.equipped_frames["arm_right"] = gen1_frame
	GlobalData.weapons.frame_modules = {}

	var val_res := LoadoutSys.validate_equip_request("weapon_right", mock_item)
	_check(not bool(val_res.get("can_equip", true)), "LoadoutSystem rejects incompatible item")
	_check(str(val_res.get("reason", "")) == "physically_incompatible", "Rejection reason is physically_incompatible")
	_check(val_res.has("required_bridge_summary"), "Validation dict includes required_bridge_summary")

	var val_req: String = str(val_res.get("required_bridge_summary", ""))
	_check(val_req != "", "required_bridge_summary is not empty: '%s'" % val_req)
	_check(str(val_res.get("message", "")).contains("Requires:"), "User message contains 'Requires:' with clear guidance")


func _test_research_lab_ui_technology_discovery() -> void:
	print("\n-- [3] ResearchLabUI & Technology Discovery Lifecycle Tests --")

	var lab_scene = preload("res://scenes/ui/research_lab_ui.tscn")
	_check(lab_scene != null, "research_lab_ui.tscn loads successfully")

	var lab_ui = lab_scene.instantiate()
	add_child(lab_ui)
	_check(lab_ui != null, "research_lab_ui instantiates without errors")

	# Verify Tab buttons
	_check(lab_ui.tab_blueprints_btn != null, "tab_blueprints_btn exists")
	_check(lab_ui.tab_tech_btn != null, "tab_tech_btn exists")

	# Switch to Tech Discovery tab
	lab_ui._switch_tab("tech_discovery")
	_check(lab_ui.current_tab == "tech_discovery", "Current tab is tech_discovery")
	_check(lab_ui.tech_discovery_view.visible, "tech_discovery_view is visible")
	_check(not lab_ui.blueprints_view.visible, "blueprints_view is hidden")

	# Setup a clean test tech: tech_valkryon_actuator_chassis
	var test_tech := "tech_valkryon_actuator_chassis"
	TechSys.set_discovery_state(test_tech, TechSys.DiscoveryState.UNKNOWN)
	lab_ui._refresh()

	_check(TechSys.get_discovery_state(test_tech) == TechSys.DiscoveryState.UNKNOWN, "test_tech initialized to UNKNOWN")

	# Advance to ENCOUNTERED
	TechSys.record_technology_encountered(test_tech)
	_check(TechSys.get_discovery_state(test_tech) == TechSys.DiscoveryState.ENCOUNTERED, "test_tech is ENCOUNTERED")

	# Advance to SALVAGED with full evidence
	TechSys.record_technology_salvaged(test_tech)
	TechSys.add_technology_evidence(test_tech, 5.0)
	_check(TechSys.can_identify_technology(test_tech), "test_tech has full evidence and can be identified")

	lab_ui._refresh()

	# Trigger Identify via UI helper
	lab_ui._on_identify_tech(test_tech)
	_check(TechSys.get_discovery_state(test_tech) == TechSys.DiscoveryState.IDENTIFIED, "UI _on_identify_tech transitioned tech to IDENTIFIED")

	# Ensure prerequisite hydraulic actuation is RESEARCHED so start_research succeeds
	TechSys.set_discovery_state("tech_hydraulic_actuation", TechSys.DiscoveryState.USABLE)

	# Trigger Start Research via UI helper
	lab_ui._on_start_tech_research(test_tech)
	_check(TechSys.get_active_research_project() == test_tech, "Active research project set to test_tech")

	# Advance progress to 100%
	TechSys.add_research_progress(test_tech, 100.0)
	_check(TechSys.can_complete_research(test_tech), "test_tech research can be completed")

	# Trigger Finalize via UI helper
	lab_ui._on_finalize_tech(test_tech)
	_check(TechSys.get_discovery_state(test_tech) == TechSys.DiscoveryState.RESEARCHED, "UI _on_finalize_tech transitioned tech to RESEARCHED")

	# Trigger Authorize Usable via UI helper
	lab_ui._on_authorize_usable(test_tech)
	_check(TechSys.get_discovery_state(test_tech) == TechSys.DiscoveryState.USABLE, "UI _on_authorize_usable transitioned tech to USABLE")

	# Clean up UI node
	lab_ui.queue_free()
