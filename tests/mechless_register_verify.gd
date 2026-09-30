extends Node

## On-foot REGISTER flow verify (c035ef2): assembling frames from the convoy
## inventory must work while pilot-only (mech_less), clear the flag, and park
## the built chassis in the roster. Uses the same scene-based harness as
## hangar_panels_verify: failures are COUNTED (never fail-fast), so a script
## error can no longer mask the whole suite as "passed".

var _fails := 0
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		printerr("FAIL: " + msg)


func _ready() -> void:
	print("--- BEGIN MECHLESS REGISTER VERIFY TEST ---")
	await _run()
	print("MECHLESS_REGISTER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ctrl.roster_panel_ui != null, "Roster panel exists")

	# Simulate total destruction (On Foot / Mechless state). Seeded AFTER the
	# hangar boot: scene initialization loads the seed berth's state, which
	# would otherwise resurrect the roster we are about to empty.
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.hangar.active_hangar_mech_id = ""
	GlobalData.narrative.mech_less = true

	_check(GlobalData.narrative.mech_less == true, "Player starts in mech_less (on foot) state")
	_check(GlobalData.hangar.hangar_mechs.is_empty(), "Hangar mechs roster is completely empty")

	# Equip required frames for a walking chassis
	GlobalData.weapons.equipped_frames["body"] = {"id": "frame_standard_body", "name": "Standard Body Frame", "hp": 100.0}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}

	# Verify HangarManager.build works even when previously mechless
	var built_mech := HangarManager.build("Rebuilt Vanguard", 1)
	_check(not built_mech.is_empty(), "Successfully built and registered mech while on foot")
	_check(GlobalData.narrative.mech_less == false, "mech_less cleared to false after building mech")
	_check(GlobalData.hangar.hangar_mechs.size() == 1, "Roster now has 1 active mech")
	# build() itself does not seat the pilot (reserve-vs-active is the caller's
	# decision, the UI confirm auto-seats via its checkbox). The empty active
	# seat is transient: ensure_roster heals it to the only parked mech.
	_check(GlobalData.hangar.active_hangar_mech_id == "", "build() leaves the seat to the caller (empty active berth)")
	HangarManager.ensure_roster()
	_check(GlobalData.hangar.active_hangar_mech_id == str(built_mech.get("id", "")), "ensure_roster seats the rebuilt mech as the active berth")

	ctrl.queue_free()
	await get_tree().process_frame
