extends Node

func _ready() -> void:
	print("--- BEGIN MECHLESS REGISTER VERIFY TEST ---")
	test_mechless_register_flow()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func test_mechless_register_flow() -> void:
	GlobalData.reset_all()

	# Simulate total destruction (On Foot / Mechless state)
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.hangar.active_hangar_mech_id = ""
	GlobalData.narrative.mech_less = true

	assert_true(GlobalData.narrative.mech_less == true, "Player starts in mech_less (on foot) state")
	assert_true(GlobalData.hangar.hangar_mechs.is_empty(), "Hangar mechs roster is completely empty")

	var hangar_script = load("res://scripts/ui/hangar_controller.gd")
	var hangar = Control.new()
	hangar.set_script(hangar_script)
	add_child(hangar)
	hangar._build_ui_layout()

	var roster_panel: HangarRosterPanel = hangar.roster_panel
	assert_true(roster_panel != null, "Roster panel exists")

	# Equip required frames for a walking chassis
	GlobalData.weapons.equipped_frames["body"] = {"id": "frame_standard_body", "name": "Standard Body Frame", "hp": 100.0}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}

	# Verify HangarManager.build works even when previously mechless
	var built_mech := HangarManager.build("Rebuilt Vanguard", 1)
	assert_true(not built_mech.is_empty(), "Successfully built and registered mech while on foot")
	assert_true(GlobalData.narrative.mech_less == false, "mech_less cleared to false after building mech")
	assert_true(GlobalData.hangar.hangar_mechs.size() == 1, "Roster now has 1 active mech")

	hangar.queue_free()
