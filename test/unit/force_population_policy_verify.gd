extends Node
## PHASE 5F FORCE POPULATION POLICY VERIFY (Option A: no producer yet).
##
## Phase 5F audit result pinned here: NO existing entity qualifies as a
## CampaignForce without inventing identity or duplicating ownership —
## patrols (sector-local ids, stance labels, churn), rivals (run-local,
## unsaved, name-based), scavenger camps (board-meta, unsaved), convoy
## (transient traversal), enemy base (canonical Base, no garrison data),
## player hangar/fleet (protected 2E/2F), war teams (isolated).
## Therefore initial population is ZERO and there is deliberately NO
## production producer: register_force stays the explicit low-level
## authority for future phases. These tests guard that decision — any
## future phase adding auto-creation will trip them on purpose, forcing an
## explicit producer decision instead of a silent one.
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("POPULATION OK: " + name)
	else:
		_fails += 1
		printerr("POPULATION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_test_zero_at_start()
	_test_no_hidden_producers()
	_test_save_load_empty()
	_test_explicit_registration_still_works()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FORCE_POPULATION_POLICY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FORCE_POPULATION_POLICY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_POPULATION_TESTS_PASSED")
		get_tree().quit(0)


# A fresh run starts with zero forces (Outcome 15A).
func _test_zero_at_start() -> void:
	GlobalData.reset_run_data()
	_check(CampaignForce.get_forces().is_empty(),
		"new run starts with zero campaign forces")
	_check(CampaignBattle.get_battles().is_empty(),
		"new run starts with zero campaign battles")


# No lifecycle path silently produces forces: turns, patrol churn, hangar
# churn, battles, and base syncs all leave the registry empty.
func _test_no_hidden_producers() -> void:
	GlobalData.reset_run_data()
	CampaignTurnExecutive.advance_campaign_turn("population_probe", {})
	CampaignTurnExecutive.advance_campaign_turn("population_probe", {"day_boundary": false})
	_check(CampaignForce.get_forces().is_empty(),
		"campaign turns produce no forces")
	GlobalData.board.board_patrols.append({"id": 4242, "faction": "hostile"})
	GlobalData.hangar.fleet_roster.append({"template_id": "probe_unit"})
	_check(CampaignForce.get_forces().is_empty(),
		"patrol/hangar churn produces no forces")
	CampaignBase.register_base("probe_base", "", "OUTPOST")
	_check(CampaignForce.get_forces().is_empty(),
		"base registration produces no forces")
	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city")
	CampaignForce.register_force("probe_anchor", "RIVAL", "zeon")
	CampaignBattle.register_battle("probe_battle", "node_s1_city_1_1", ["probe_anchor"])
	CampaignBattle.prepare_launch("probe_battle")
	_check(CampaignForce.get_forces().size() == 1,
		"battle lifecycle produces no forces (only the explicit anchor exists)")
	GlobalData.reset_run_data()


# Empty population round-trips through save/load unchanged.
func _test_save_load_empty() -> void:
	GlobalData.reset_run_data()
	_check(SaveGameIO.save_run(), "save_run reports success")
	_check(SaveGameIO.load_run(), "load_run reports success")
	_check(CampaignForce.get_forces().is_empty(),
		"empty population survives save/load (no phantom forces)")
	GlobalData.reset_run_data()


# The explicit authority still works (policy is "no auto-producer", not "no forces").
func _test_explicit_registration_still_works() -> void:
	GlobalData.reset_run_data()
	_check(CampaignForce.register_force("force_explicit", "RIVAL", "zeon") == "force_explicit",
		"explicit registration remains the legitimate creation path")
	_check(SaveGameIO.save_run(), "save_run reports success")
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "load_run reports success")
	_check(CampaignForce.has_force("force_explicit"),
		"explicitly created force persists (producer-independent)")
	GlobalData.reset_run_data()
