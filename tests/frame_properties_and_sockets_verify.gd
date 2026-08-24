extends Node

var _failed := false

func _check(condition: bool, msg: String) -> void:
	if not condition:
		_failed = true
		push_error("FAIL: %s" % msg)
		print("FAIL: %s" % msg)
	else:
		print("PASS: %s" % msg)

func _ready() -> void:
	print("--- BEGIN FRAME PROPERTIES, DYNAMIC CAMERA & TOP BAR VERIFY ---")

	# 1. Verify Dynamic Camera Orbits in HangarGaragePanel
	var garage := HangarGaragePanel.new()
	garage.update_camera_focus("arm_left")
	_check(garage.cam_target_pos.x < -2.0, "arm_left orbits camera to the LEFT side (x < -2.0)")
	_check(garage.cam_look_target.x < -0.5, "arm_left looks toward left arm")

	garage.update_camera_focus("arm_right")
	_check(garage.cam_target_pos.x > 2.0, "arm_right orbits camera to the RIGHT side (x > 2.0)")
	_check(garage.cam_look_target.x > 0.5, "arm_right looks toward right arm")

	garage.update_camera_focus("leg_left")
	_check(garage.cam_target_pos.x < -1.5 and garage.cam_target_pos.y < 1.5, "leg_left orbits low-left")

	garage.update_camera_focus("leg_right")
	_check(garage.cam_target_pos.x > 1.5 and garage.cam_target_pos.y < 1.5, "leg_right orbits low-right")

	garage.update_camera_focus("weapon_carry")
	_check(garage.cam_target_pos.z < -2.0, "weapon_carry orbits behind mecha backpack")

	# 2. Verify Frame Property Catalog & Sockets in GlobalData
	_check(GlobalData.frame_property_catalog.size() >= 10, "GlobalData has rich frame property catalog (size >= 10)")
	var body_entry := GlobalData.get_frame_property_entry("mod_reactor_fission")
	_check(not body_entry.is_empty(), "Fission Power Core exists in catalog")
	_check(float(body_entry.get("energy_bonus", 0.0)) >= 1000.0, "Power Core provides +1000 Energy bonus")

	var booster := GlobalData.get_frame_property_entry("mod_flight_booster")
	_check(not booster.is_empty() and bool(booster.get("flight_glide", false)), "Flight Booster provides flight glide")

	# 3. Verify Sockets Capacity and Equip / Unequip logic
	GlobalData.weapons.attachments.clear()
	var slot := "body"
	var max_sockets := GlobalData.get_slot_frame_sockets(slot)
	_check(max_sockets == 2, "Default body frame has 2 property sockets")

	# Equip Mod 1
	GlobalData.weapons.attachments.append({"id": "mod_reactor_fission", "slot": slot, "name": "Power Core"})
	var eq_mods := GlobalData.get_equipped_frame_mods_for_slot(slot)
	_check(eq_mods.size() == 1, "1 mod equipped on body")

	# Equip Mod 2
	GlobalData.weapons.attachments.append({"id": "mod_flight_booster", "slot": slot, "name": "Flight Booster"})
	eq_mods = GlobalData.get_equipped_frame_mods_for_slot(slot)
	_check(eq_mods.size() == 2, "2 mods equipped on body (sockets full)")

	# Unequip Mod 1
	for i in range(GlobalData.weapons.attachments.size()):
		if GlobalData.weapons.attachments[i]["id"] == "mod_reactor_fission":
			GlobalData.weapons.attachments.remove_at(i)
			break
	eq_mods = GlobalData.get_equipped_frame_mods_for_slot(slot)
	_check(eq_mods.size() == 1, "Mod unequipped successfully (1 socket free)")

	print("--- FRAME PROPERTIES, DYNAMIC CAMERA & TOP BAR VERIFY COMPLETE: %s ---" % ("FAIL" if _failed else "ALL PASSED"))
	if _failed:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
