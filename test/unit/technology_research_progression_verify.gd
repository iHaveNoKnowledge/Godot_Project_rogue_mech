extends Node
## TECHNOLOGY RESEARCH PROGRESSION VERIFICATION (PHASE 2E-4B)
## Validates:
## 1. Technology research receives approved progression through ResearchProgressionSystem.
## 2. Research progress accumulates accurately based on research_time metadata.
## 3. Progression does not advance when no active project exists.
## 4. Technology cannot progress before reaching IDENTIFIED state.
## 5. Technology prerequisites remain strictly enforced prior to research start.
## 6. Research completion preserves the existing lifecycle (IDENTIFIED -> 100% -> RESEARCHED).
## 7. RESEARCHED does not automatically become USABLE (requires explicit authorization).
## 8. FleetSystem legacy blueprint research remains independent, functional, and intact.
## 9. Board-day progression (1 point) advances research without double-counting.
## 10. Combat-victory progression (2 points) advances research without double-counting.
## 11. Existing save data roundtrips active project and accumulated progress cleanly.
## 12. Progression never consumes currency, scrap, or data cores.

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FleetSys = preload("res://scripts/systems/fleet_system.gd")
const ResProgSys = preload("res://scripts/systems/research_progression_system.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("RES_PROG_OK: " + test_name)
	else:
		_fails += 1
		printerr("RES_PROG_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY RESEARCH PROGRESSION VERIFICATION (PHASE 2E-4B) ===")
	_test_no_active_project_progression()
	_test_state_gate_before_identified()
	_test_progress_accumulation_math()
	_test_prerequisites_enforced()
	_test_completion_and_usability_boundaries()
	_test_fleetsystem_blueprint_isolation()
	await _test_board_day_progression_no_double_counting()
	await _test_combat_victory_progression_no_double_counting()
	_test_save_load_roundtrip()
	_test_economy_non_mutation_during_progression()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_4B_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_4B_FAILED")
		get_tree().quit(1)


func _test_no_active_project_progression() -> void:
	TechSys.reset_discovery_states()
	_check(TechSys.get_active_research_project() == "", "[1a] Active research project is initially empty")

	var res := TechSys.advance_active_research(1.0)
	_check(not res.get("success", true), "[1b] Advance fails gracefully when no active project")
	_check(res.get("reason") == "no_active_project", "[1c] Reason is no_active_project")

	var dispatch_res := ResProgSys.dispatch_progression("board_day", 1.0)
	_check(not dispatch_res.get("technology", {}).get("success", true), "[1d] Dispatch reports technology non-progression when empty")


func _test_state_gate_before_identified() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_gate_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Gate Test Tech",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": TechSys.LINEAGE_VALKREN,
		"tags": ["test"],
		"prerequisites": [],
		"research_metadata": {
			"research_time": 2.0
		}
	})

	_check(not TechSys.can_start_research(test_id), "[2a] Cannot start research while UNKNOWN")
	TechSys.record_technology_encountered(test_id)
	_check(not TechSys.can_start_research(test_id), "[2b] Cannot start research while ENCOUNTERED")

	TechSys.record_technology_salvaged(test_id)
	_check(not TechSys.can_start_research(test_id), "[2c] Cannot start research while SALVAGED")

	# Force advance on un-identified technology returns failure
	_check(not TechSys.add_research_progress(test_id, 25.0), "[2d] add_research_progress fails when state is SALVAGED")

	TechSys.add_technology_evidence(test_id, 1.0)
	TechSys.record_technology_identified(test_id)
	_check(TechSys.can_start_research(test_id), "[2e] Can start research once IDENTIFIED")
	_check(TechSys.start_research(test_id), "[2f] start_research succeeds")
	_check(TechSys.get_active_research_project() == test_id, "[2g] Active research project is now test_id")


func _test_progress_accumulation_math() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_math_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Math Test Tech",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"era_phase_req": 2,
		"origin_lineage": TechSys.LINEAGE_COMMON,
		"tags": ["test"],
		"prerequisites": [],
		"research_metadata": {
			"research_time": 4.0 # 4 points needed -> 25% per 1.0 point
		}
	})

	TechSys.record_technology_encountered(test_id)
	TechSys.record_technology_salvaged(test_id)
	TechSys.add_technology_evidence(test_id, 1.0)
	TechSys.record_technology_identified(test_id)
	TechSys.start_research(test_id)

	_check(TechSys.get_research_progress(test_id) == 0.0, "[3a] Initial research progress is 0.0%")

	# 1 point progression on research_time = 4.0 should add 25.0%
	var res1 := TechSys.advance_active_research(1.0)
	_check(res1.get("success"), "[3b] First advance succeeds")
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 25.0), "[3c] Progress is 25.0% after 1 point")

	# Another 1 point progression should bring it to 50.0%
	ResProgSys.dispatch_progression("board_day", 1.0)
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 50.0), "[3d] Progress is 50.0% after 2nd point")

	# 2 points progression (e.g. combat victory) should add 50.0%, reaching 100.0%
	ResProgSys.dispatch_progression("combat_victory", 2.0)
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 100.0), "[3e] Progress reached 100.0% after combat victory")
	_check(TechSys.can_complete_research(test_id), "[3f] can_complete_research is true at 100.0%")


func _test_prerequisites_enforced() -> void:
	TechSys.reset_discovery_states()
	var parent_id := "tech_parent_test"
	var child_id := "tech_child_test"
	TechSys.register_technology({
		"tech_id": parent_id,
		"name": "Parent Tech",
		"generation": 1,
		"technology_family": TechSys.FAMILY_POWER,
		"prerequisites": []
	})
	TechSys.register_technology({
		"tech_id": child_id,
		"name": "Child Tech",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"prerequisites": [parent_id]
	})

	# Identify child tech
	TechSys.record_technology_encountered(child_id)
	TechSys.record_technology_salvaged(child_id)
	TechSys.add_technology_evidence(child_id, 1.0)
	TechSys.record_technology_identified(child_id)

	# Parent is UNKNOWN -> Child cannot start research
	_check(not TechSys.can_start_research(child_id), "[4a] Child cannot start research when parent is UNKNOWN")
	_check(not TechSys.start_research(child_id), "[4b] start_research returns false")

	# Advance parent to IDENTIFIED -> Child still cannot start research
	TechSys.record_technology_encountered(parent_id)
	TechSys.record_technology_salvaged(parent_id)
	TechSys.add_technology_evidence(parent_id, 1.0)
	TechSys.record_technology_identified(parent_id)
	_check(not TechSys.can_start_research(child_id), "[4c] Child cannot start research when parent is only IDENTIFIED")

	# Research parent to 100% and complete it -> Parent is RESEARCHED
	TechSys.start_research(parent_id)
	TechSys.add_research_progress(parent_id, 100.0)
	TechSys.complete_technology_research(parent_id)
	_check(TechSys.get_discovery_state(parent_id) == TechSys.DiscoveryState.RESEARCHED, "[4d] Parent is RESEARCHED")

	# Now child can start research
	_check(TechSys.can_start_research(child_id), "[4e] Child can start research once parent is RESEARCHED")
	_check(TechSys.start_research(child_id), "[4f] Child start_research succeeds")


func _test_completion_and_usability_boundaries() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_boundary_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Boundary Test Tech",
		"generation": 1,
		"technology_family": TechSys.FAMILY_COOLING,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 2.0
		}
	})

	TechSys.record_technology_encountered(test_id)
	TechSys.record_technology_salvaged(test_id)
	TechSys.add_technology_evidence(test_id, 1.0)
	TechSys.record_technology_identified(test_id)
	TechSys.start_research(test_id)

	# Progress to 100% without auto-finalize
	TechSys.advance_active_research(2.0, {"auto_finalize": false})
	_check(TechSys.get_research_progress(test_id) == 100.0, "[5a] Progress is 100.0%")
	_check(TechSys.get_discovery_state(test_id) == TechSys.DiscoveryState.IDENTIFIED, "[5b] State remains IDENTIFIED (no silent jump to RESEARCHED)")
	_check(not TechSys.is_technology_usable(test_id), "[5c] 100% progress does NOT make tech usable")

	# Complete research explicitly
	_check(TechSys.complete_technology_research(test_id), "[5d] complete_technology_research succeeds")
	_check(TechSys.get_discovery_state(test_id) == TechSys.DiscoveryState.RESEARCHED, "[5e] State is now RESEARCHED")
	_check(TechSys.get_active_research_project() == "", "[5f] Active research project cleared upon completion")
	_check(not TechSys.is_technology_usable(test_id), "[5g] RESEARCHED state is STILL not usable by default")

	# Explicit authorization to USABLE
	_check(TechSys.record_technology_usable(test_id), "[5h] record_technology_usable succeeds")
	_check(TechSys.is_technology_usable(test_id), "[5i] is_technology_usable is now true")


func _test_fleetsystem_blueprint_isolation() -> void:
	if not GlobalData or not GlobalData.currency:
		return
	var bp_id := "bp_ally_gm"
	GlobalData.hangar.research_projects.clear()
	GlobalData.hangar.research_unlocked.clear()
	GlobalData.currency.data_cores = 10

	var started := FleetSys.start_research(bp_id)
	_check(started, "[6a] FleetSystem blueprint project started")
	_check(FleetSys.is_research_active(bp_id), "[6b] Blueprint is active in FleetSystem")

	var initial_bp_prog: int = int(GlobalData.hangar.research_projects[bp_id].get("progress", 0))
	_check(initial_bp_prog == 0, "[6c] Initial blueprint progress is 0")

	# Dispatch progression through ResProgSys
	var res := ResProgSys.dispatch_progression("board_day", 1.0)
	var new_bp_prog: int = int(GlobalData.hangar.research_projects[bp_id].get("progress", 0))
	_check(new_bp_prog == 1, "[6d] Blueprint advanced by 1 point via ResProgSys dispatch")

	# Clean up
	GlobalData.hangar.research_projects.clear()
	GlobalData.currency.data_cores = 10


func _test_board_day_progression_no_double_counting() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_board_prog_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Board Prog Test",
		"generation": 1,
		"technology_family": TechSys.FAMILY_BALLISTIC,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 10.0 # 10 points needed -> 10% per 1.0 point
		}
	})

	TechSys.record_technology_encountered(test_id)
	TechSys.record_technology_salvaged(test_id)
	TechSys.add_technology_evidence(test_id, 1.0)
	TechSys.record_technology_identified(test_id)
	TechSys.start_research(test_id)

	# Simulate EventBus.board_day_ended
	EventBus.board_day_ended.emit()
	await get_tree().process_frame

	# Should have received exactly 1 board day tick = 10% progress (NOT 20%)
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 10.0), "[7a] Board day ended advanced research by exactly 10% (no double-counting)")


func _test_combat_victory_progression_no_double_counting() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_combat_prog_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Combat Prog Test",
		"generation": 1,
		"technology_family": TechSys.FAMILY_ENERGY,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 10.0 # 10 points needed -> 20% per 2.0 points
		}
	})

	TechSys.record_technology_encountered(test_id)
	TechSys.record_technology_salvaged(test_id)
	TechSys.add_technology_evidence(test_id, 1.0)
	TechSys.record_technology_identified(test_id)
	TechSys.start_research(test_id)

	# Simulate EventBus.combat_ended(false) -> defeat should NOT advance research
	EventBus.combat_ended.emit(false)
	await get_tree().process_frame
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 0.0), "[8a] Defeat does not advance research progress")

	# Simulate EventBus.combat_ended(true) -> victory advances by 2 points = 20% progress
	EventBus.combat_ended.emit(true)
	await get_tree().process_frame
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 20.0), "[8b] Victory advances research by exactly 20% (no double-counting)")


func _test_save_load_roundtrip() -> void:
	TechSys.reset_discovery_states()
	var test_id := "tech_save_prog_test"
	TechSys.register_technology({
		"tech_id": test_id,
		"name": "Save Prog Test",
		"generation": 2,
		"technology_family": TechSys.FAMILY_INTERFACE,
		"prerequisites": [],
		"research_metadata": {
			"research_time": 5.0
		}
	})

	TechSys.record_technology_encountered(test_id)
	TechSys.record_technology_salvaged(test_id)
	TechSys.add_technology_evidence(test_id, 2.5)
	TechSys.record_technology_identified(test_id)
	TechSys.start_research(test_id)
	TechSys.advance_active_research(2.0) # 40% progress

	var saved := TechSys.serialize_discovery_states()
	_check(saved.get("__active_project") == test_id, "[9a] Saved data contains __active_project")
	_check(is_equal_approx(float(saved.get("__progress", {}).get(test_id, 0.0)), 40.0), "[9b] Saved data contains 40% progress")

	TechSys.reset_discovery_states()
	_check(TechSys.get_active_research_project() == "", "[9c] Reset clears active project")
	_check(TechSys.get_research_progress(test_id) == 0.0, "[9d] Reset clears progress")

	TechSys.deserialize_discovery_states(saved)
	_check(TechSys.get_active_research_project() == test_id, "[9e] Restored active project")
	_check(is_equal_approx(TechSys.get_research_progress(test_id), 40.0), "[9f] Restored 40% progress")
	_check(TechSys.get_discovery_state(test_id) == TechSys.DiscoveryState.IDENTIFIED, "[9g] Restored IDENTIFIED state")


func _test_economy_non_mutation_during_progression() -> void:
	if not GlobalData or not GlobalData.currency:
		return
	GlobalData.currency.credits = 1000
	GlobalData.currency.scrap = 500
	GlobalData.currency.data_cores = 25

	ResProgSys.advance_board_day(5.0)
	ResProgSys.advance_combat_victory(10.0)

	_check(GlobalData.currency.credits == 1000, "[10a] Credits completely unchanged after progression")
	_check(GlobalData.currency.scrap == 500, "[10b] Scrap completely unchanged after progression")
	_check(GlobalData.currency.data_cores == 25, "[10c] Data cores completely unchanged after progression")
