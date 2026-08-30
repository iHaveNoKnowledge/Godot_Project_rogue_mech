extends Node

func _ready() -> void:
	print("--- BEGIN REGISTER RESERVE MECH VERIFY TEST ---")
	test_register_as_reserve_mech()
	test_register_as_active_mech()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func test_register_as_reserve_mech() -> void:
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()

	var initial_mechs := HangarManager.get_mechs()
	assert_true(initial_mechs.size() == 1, "Starts with 1 active mech")
	var initial_active_id := GlobalData.hangar.active_hangar_mech_id
	assert_true(initial_active_id != "", "Has active mech id")

	# Setup Hangar controller & roster panel
	var hangar_script = load("res://scripts/ui/hangar_controller.gd")
	var hangar = Control.new()
	hangar.set_script(hangar_script)
	add_child(hangar)
	hangar._build_ui_layout()

	var roster_panel: HangarRosterPanel = hangar.roster_panel
	assert_true(roster_panel != null, "Roster panel exists")

	# Equip walking chassis
	GlobalData.weapons.equipped_frames["body"] = {"id": "frame_standard_body", "name": "Standard Body Frame", "hp": 100.0}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}

	# Open register dialog for Slot 2
	roster_panel.build_register_dialog(2)
	assert_true(roster_panel.register_dialog_active_check != null, "MakeActiveCheckBox exists in dialog")

	# Uncheck make_active (Register as Reserve Mech)
	roster_panel.register_dialog_active_check.button_pressed = false
	roster_panel.register_dialog_edit.text = "Spare Vanguard"
	roster_panel._confirm_register(2)

	var mechs := HangarManager.get_mechs()
	assert_true(mechs.size() == 2, "Now has 2 mechs in roster")

	# Verify active mech did NOT switch
	assert_true(GlobalData.hangar.active_hangar_mech_id == initial_active_id, "Active mech ID remained untouched on original mech")

	# Verify Slot 2 mech is a reserve with empty pilot
	var spare_mech: Dictionary = {}
	for m in mechs:
		if int(m.get("slot", 0)) == 2:
			spare_mech = m
			break
	assert_true(not spare_mech.is_empty(), "Spare mech found in Slot 2")
	assert_true(str(spare_mech.get("pilot", "")) == "", "Spare mech has no pilot assigned (pure reserve)")

	hangar.queue_free()


func test_register_as_active_mech() -> void:
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()

	var hangar_script = load("res://scripts/ui/hangar_controller.gd")
	var hangar = Control.new()
	hangar.set_script(hangar_script)
	add_child(hangar)
	hangar._build_ui_layout()

	var roster_panel: HangarRosterPanel = hangar.roster_panel

	GlobalData.weapons.equipped_frames["body"] = {"id": "frame_standard_body", "name": "Standard Body Frame", "hp": 100.0}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}

	roster_panel.build_register_dialog(2)
	roster_panel.register_dialog_active_check.button_pressed = true
	roster_panel.register_dialog_edit.text = "New Main Mech"
	roster_panel._confirm_register(2)

	var mechs := HangarManager.get_mechs()
	var new_main: Dictionary = {}
	for m in mechs:
		if int(m.get("slot", 0)) == 2:
			new_main = m
			break

	assert_true(not new_main.is_empty(), "New mech found in Slot 2")
	assert_true(GlobalData.hangar.active_hangar_mech_id == str(new_main.get("id", "")), "Active mech switched to new mech")
	assert_true(str(new_main.get("pilot", "")) == HangarManager.PLAYER_PILOT_ID, "Player pilot YOU assigned to new mech")

	hangar.queue_free()
