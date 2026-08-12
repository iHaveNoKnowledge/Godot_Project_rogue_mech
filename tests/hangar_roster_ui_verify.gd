extends Node

var _fails := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		print("HROSTER OK: " + name)
	else:
		_fails += 1
		printerr("HROSTER FAIL: " + name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ctrl.nav_panel != null and ctrl.nav_panel.current_submenu == "", "hangar controller loaded")

	ctrl.nav_panel.select_submenu("roster")
	await get_tree().process_frame
	var rp = ctrl.roster_panel_ui
	_check(rp != null, "hangar controller builds a roster panel")
	_check(rp.roster_panel != null and rp.roster_panel.visible, "roster page opens from hangar menu")
	_check(rp.roster_slot_list != null and rp.roster_slot_list.get_child_count() > 0, "roster page lists berths")
	_check(rp.mech_slot_label != null and rp.mech_slot_label.visible, "mech-slot badge visible on roster page")
	_check(rp.mech_slot_label.text.begins_with("MECH SLOT"), "badge text is MECH SLOT x/y")

	ctrl.nav_panel.select_submenu("customize")
	await get_tree().process_frame
	_check(rp.roster_panel != null and not rp.roster_panel.visible, "customize page hides roster page")
	_check(rp.mech_prev_button != null and rp.mech_prev_button.visible, "customize page shows prev-slot button")
	_check(rp.mech_next_button != null and rp.mech_next_button.visible, "customize page shows next-slot button")
	_check(rp.mech_slot_label.text.begins_with("MECH SLOT"), "customize page keeps the slot badge")

	ctrl.nav_panel.show_hangar_menu()
	await get_tree().process_frame
	_check(not rp.mech_slot_label.visible, "hangar menu hides the slot badge")

	# Switching to an active slot with only one parked mech is a no-op (safe).
	var before: String = rp.mech_slot_label.text
	rp.cycle_hangar_mech(1)
	await get_tree().process_frame
	_check(rp.mech_slot_label.text == before, "cycling with one mech is a no-op")

	print("HANGAR_ROSTER_UI_VERIFY: fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
