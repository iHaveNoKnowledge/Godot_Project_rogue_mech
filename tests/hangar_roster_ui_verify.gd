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

	_check(ctrl.has_method("_select_hangar_submenu"), "hangar controller loaded")

	ctrl._select_hangar_submenu("roster")
	await get_tree().process_frame
	_check(ctrl.roster_panel != null and ctrl.roster_panel.visible, "roster page opens from hangar menu")
	_check(ctrl.roster_slot_list != null and ctrl.roster_slot_list.get_child_count() > 0, "roster page lists berths")
	_check(ctrl.mech_slot_label != null and ctrl.mech_slot_label.visible, "mech-slot badge visible on roster page")
	_check(ctrl.mech_slot_label.text.begins_with("MECH SLOT"), "badge text is MECH SLOT x/y")

	ctrl._select_hangar_submenu("customize")
	await get_tree().process_frame
	_check(ctrl.roster_panel != null and not ctrl.roster_panel.visible, "customize page hides roster page")
	_check(ctrl.mech_prev_button != null and ctrl.mech_prev_button.visible, "customize page shows prev-slot button")
	_check(ctrl.mech_next_button != null and ctrl.mech_next_button.visible, "customize page shows next-slot button")
	_check(ctrl.mech_slot_label.text.begins_with("MECH SLOT"), "customize page keeps the slot badge")

	ctrl._show_hangar_menu()
	await get_tree().process_frame
	_check(not ctrl.mech_slot_label.visible, "hangar menu hides the slot badge")

	# Switching to an active slot with only one parked mech is a no-op (safe).
	var before: String = ctrl.mech_slot_label.text
	ctrl._cycle_hangar_mech(1)
	await get_tree().process_frame
	_check(ctrl.mech_slot_label.text == before, "cycling with one mech is a no-op")

	print("HANGAR_ROSTER_UI_VERIFY: fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
