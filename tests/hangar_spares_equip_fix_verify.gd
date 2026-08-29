extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running hangar_spares_equip_fix_verify ---")
	_test_armor_spares_equip_flow()

	print("HANGAR_SPARES_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_armor_spares_equip_flow() -> void:
	print("Testing Armor Spares selection, resolution, and equip flow in Hangar...")
	GlobalData.reset_run_data()

	var hangar_scene = preload("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)

	# 1. Clear currently equipped armor and armor inventory so spare is the only item
	GlobalData.weapons.equipped_parts.erase("arm_left")
	GlobalData.weapons.armor_inventory.clear()
	var spare_armor = {
		"id": "arm_left_001",
		"name": "Barbatos Left Shoulder Guard",
		"slot": "arm_left",
		"uid": "armor_test_barbatos_arm_l",
		"type": "Standard Armor",
		"hp": 25.0,
		"max_hp": 25.0,
		"armor": 15.0,
		"weight": 6.0,
		"equipped": false
	}
	GlobalData.weapons.armor_inventory.append(spare_armor)

	# 2. Simulate user selecting arm_left in OUTER ARMOR mode
	hangar.current_mode = "armor"
	hangar.selected_slot = "arm_left"
	hangar.part_list_panel.populate("arm_left")

	# Check that selected_salvage_info is populated with the spare armor (not frame)
	_check(not hangar.selected_salvage_info.is_empty(), "selected_salvage_info is populated after populate()")
	_check(hangar.selected_salvage_info.get("name") == "Barbatos Left Shoulder Guard", "selected_salvage_info is Barbatos Left Shoulder Guard")
	_check(hangar.selected_frame_info.is_empty(), "selected_frame_info is cleared in armor mode")

	# 3. Test resolve_info_for_index(0)
	var resolved_info = hangar.part_list_panel.resolve_info_for_index(0)
	_check(resolved_info.get("name") == "Barbatos Left Shoulder Guard", "resolve_info_for_index(0) returns Barbatos Left Shoulder Guard")
	_check(resolved_info.has("uid"), "resolved info has unique instance UID")

	# 4. Test Action Menu for inventory spare
	hangar.action_panel.show(resolved_info)
	var modal = hangar.root_control.get_node_or_null("PartActionModal")
	_check(modal != null, "Action Modal created")
	var vbox: VBoxContainer = modal.get_child(0) as VBoxContainer
	var title_lbl: Label = vbox.get_child(0) as Label if vbox else null
	_check(title_lbl != null and "BARBATOS" in title_lbl.text, "Action Modal title reflects armor name: " + (title_lbl.text if title_lbl else ""))

	var is_eq = hangar.part_list_panel.is_item_equipped("arm_left", resolved_info)
	_check(not is_eq, "Armor spare is initially not equipped")

	# 5. Equip the spare armor
	hangar.equip_panel.equip_part("arm_left", resolved_info)
	_check(hangar.part_list_panel.is_item_equipped("arm_left", resolved_info), "Armor spare is now equipped")
	_check(GlobalData.weapons.equipped_parts.get("arm_left", {}).get("uid") == spare_armor["uid"], "GlobalData equipped_parts arm_left has spare armor UID")

	# 6. Mode switching: switch to INNER FRAME mode
	hangar.nav_panel.switch_custom_mode("frame")
	_check(hangar.current_mode == "frame", "Switched to frame mode")
	_check(not hangar.selected_frame_info.is_empty(), "selected_frame_info populated in frame mode")
	_check(hangar.selected_salvage_info.is_empty(), "selected_salvage_info cleared in frame mode")

	# 7. Switch back to OUTER ARMOR mode
	hangar.nav_panel.switch_custom_mode("armor")
	_check(hangar.current_mode == "armor", "Switched back to armor mode")
	_check(not hangar.selected_salvage_info.is_empty(), "selected_salvage_info populated in armor mode")
	_check(hangar.selected_frame_info.is_empty(), "selected_frame_info cleared in armor mode")
	_check(hangar.selected_salvage_info.get("uid") == spare_armor["uid"], "selected_salvage_info is the equipped spare armor")

	hangar.action_panel.close()
	hangar.queue_free()
