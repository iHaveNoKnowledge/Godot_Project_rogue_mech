extends Node

func _ready() -> void:
	print("--- BEGIN RESPAWN AND COMBAT ENTRY VERIFY TEST ---")
	test_rebuild_and_combat_readiness()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func test_rebuild_and_combat_readiness() -> void:
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()

	# Simulate mech destruction in battle
	GlobalData.hangar.hangar_mechs.clear()
	GlobalData.hangar.active_hangar_mech_id = ""
	GlobalData.narrative.mech_less = true
	GlobalData.fuel.mech_energy = 0.0
	GlobalData.board.board_mp = 0
	GlobalData.fuel.traversal_mode = "pilot"

	assert_true(GlobalData.narrative.mech_less == true, "Simulated mechless state")

	# Assemble a new frame
	GlobalData.weapons.equipped_frames["body"] = {"id": "frame_standard_body", "name": "Standard Body Frame", "hp": 100.0}
	GlobalData.weapons.equipped_frames["leg_left"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"id": "frame_standard_leg", "name": "Standard Leg Frame", "hp": 80.0}

	var new_mech := HangarManager.build("Rebuilt Vanguard", 1)
	assert_true(not new_mech.is_empty(), "Assembled new mech")
	assert_true(GlobalData.narrative.mech_less == false, "mech_less cleared upon build")
	assert_true(GlobalData.fuel.mech_energy > 0.0, "mech_energy recharged on build")

	# Test Hangar Roster registration
	var hangar_script = load("res://scripts/ui/hangar_controller.gd")
	var hangar = Control.new()
	hangar.set_script(hangar_script)
	add_child(hangar)
	hangar._build_ui_layout()

	var roster_panel: HangarRosterPanel = hangar.roster_panel
	roster_panel.build_register_dialog(1)
	roster_panel.register_dialog_active_check.button_pressed = true
	roster_panel._confirm_register(1)

	assert_true(GlobalData.fuel.traversal_mode == "convoy", "Traversal mode restored to convoy")
	assert_true(GlobalData.board.board_mp >= 4, "Movement points granted")
	assert_true(GlobalData.fuel.mech_energy == GlobalData.fuel.mech_max_energy, "Battery fully charged")

	# Test BoardManager _ready state synchronization
	var board_mgr_script = load("res://scripts/board/board_manager.gd")
	var bm = Node3D.new()
	bm.set_script(board_mgr_script)
	add_child(bm)

	assert_true(GlobalData.narrative.mech_less == false, "BoardManager confirmed player has a functional mech")
	assert_true(GlobalData.board.board_mp > 0, "BoardManager has available MP")

	bm.queue_free()
	hangar.queue_free()
