extends Node

## Verifies run-progression state fixes:
##  - frame_upgrade_level resets on new run and round-trips through save/load
##  - wanted_escalation floor resets, round-trips, and survives heat cool-downs

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PROG OK: " + name)
	else:
		_fails += 1
		printerr("PROG FAIL: " + name)


func _ready() -> void:
	# This test calls save_run() which writes the real user:// save — back it up
	# first and restore it at the end so a player's progress is never clobbered.
	var backup := ""
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	GlobalData.reset_run_data()

	# --- frame_upgrade_level resets for a brand-new run ---
	GlobalData.frame_upgrade_level = 7
	GlobalData.reset_run_data()
	_check(GlobalData.frame_upgrade_level == 1, "new run resets frame_upgrade_level to 1")

	# --- frame_upgrade_level round-trips through save/load ---
	GlobalData.frame_upgrade_level = 4
	GlobalData.board.current_sector = 3
	GlobalData.currency.credits = 999
	SaveGameIO.save_run()
	GlobalData.reset_run_data()
	_check(GlobalData.frame_upgrade_level == 1, "after reset, upgrade level back to 1")
	SaveGameIO.load_run()
	_check(GlobalData.frame_upgrade_level == 4, "upgrade level persists across save/load")
	_check(GlobalData.board.current_sector == 3, "sector round-trips too")

	# --- wanted_escalation resets on new run ---
	GlobalData.board.wanted_escalation = 5
	GlobalData.reset_run_data()
	_check(GlobalData.board.wanted_escalation == 0 and GlobalData.board.wanted_level == 0, "new run clears wanted escalation")

	# --- wanted_escalation floor survives heat cool-downs ---
	GlobalData.reset_run_data()
	HeatWantedSystem.escalate_wanted(1, 5)
	_check(GlobalData.board.wanted_level == 1, "escalate_wanted raises wanted_level to 1")
	HeatWantedSystem.escalate_wanted(3, 5)
	_check(GlobalData.board.wanted_level == 4, "escalate_wanted stacks to 4")
	HeatWantedSystem.escalate_wanted(5, 5)
	_check(GlobalData.board.wanted_level == 5, "escalate_wanted caps at 5")
	# Heat cools to 0 — the floor must keep wanted at 5 (not drop to heat-derived 0).
	HeatWantedSystem.modify_heat(-HeatWantedSystem.max_heat)
	_check(GlobalData.board.heat == 0, "heat cooled to zero")
	_check(GlobalData.board.wanted_level == 5, "wanted stays 5 after full heat cool-down (floor holds)")

	# --- wanted_escalation round-trips through save/load ---
	SaveGameIO.save_run()
	GlobalData.reset_run_data()
	SaveGameIO.load_run()
	_check(GlobalData.board.wanted_escalation == 5, "escalation floor persists across save/load")
	_check(GlobalData.board.wanted_level == 5, "wanted_level restored from escalation floor")

	# --- restore old saves without the new keys (backward compat) ---
	GlobalData.reset_run_data()
	SaveGameIO.restore_from_dict({})
	_check(GlobalData.frame_upgrade_level == 1, "legacy save defaults frame_upgrade_level to 1")
	_check(GlobalData.board.wanted_escalation == 0, "legacy save defaults wanted_escalation to 0")

	# Restore the player's original save file (if any).
	if backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(backup)

	print("PROGRESSION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
