extends Node
## SHOULDER EQUIP VERIFY — end-to-end hangar shoulder install flow.
## Reproduces: "ติดตั้งอาวุธที่ไหล่ใน hangar ไม่ได้"
## Covers both entry points (ACTION MENU double-click -> equip_part,
## EQUIP SELECTION button -> on_equip_pressed), shoulder replacement with a
## tight pack, hand swaps (uid occupant subtracts), cross-mech shoulder
## transfer, the 3D garage preview, and roster persistence.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SHLDR OK: " + name)
	else:
		_fails += 1
		printerr("SHLDR FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GlobalData.reset_run_data()
	await _test_action_menu_shoulder_equip()
	await _test_equip_button_shoulder_equip()
	await _test_pack_excludes_shoulders_and_swap_math()
	await _test_cross_mech_shoulder_transfer()
	await _test_shoulder_survives_mech_switch()
	print("SHOULDER_EQUIP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("SHOULDER_EQUIP_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_SHOULDER_EQUIP_TESTS_PASSED")
		get_tree().quit(0)


func _make_hangar() -> Node:
	var hangar_scene: PackedScene = load("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)
	return hangar


func _missile_uid(path: String, label: String) -> String:
	var uid: String = LoadoutSystem.register_weapon(path, label)
	return uid


func _test_action_menu_shoulder_equip() -> void:
	print("-- ACTION MENU shoulder equip (double-click path) --")
	var hangar = _make_hangar()
	await get_tree().process_frame

	var missile_path := "res://resources/mech/stock/weapon_missile.tres"
	_check(ResourceLoader.exists(missile_path), "missile resource exists")
	var uid := _missile_uid(missile_path, "Test Missile")
	_check(uid != "", "missile registered with uid")

	hangar.selected_slot = "shoulder_left"
	hangar.part_list_panel.populate("shoulder_left")
	_check(hangar.part_item_list.item_count > 0, "shoulder_left list shows weapons")

	var resolved: Dictionary = hangar.part_list_panel.resolve_info_for_index(0)
	_check(not resolved.is_empty(), "resolve_info_for_index(0) returns weapon info")

	var target := {}
	for inv in GlobalData.weapons.weapon_inventory:
		if str(inv.get("uid", "")) == uid:
			target = inv
			break
	_check(not target.is_empty(), "registered missile found in stash")
	hangar.equip_panel.equip_part("shoulder_left", target)
	print("SHLDR status after equip: '%s'" % str(hangar.status_message_label.text))
	_check(LoadoutSystem.get_equipped_shoulder_uid("left") == uid, "shoulder_left holds the missile uid after equip_part")
	_check(hangar.part_list_panel.weapon_in_loadout("shoulder_left", target), "missile shows [E] on shoulder_left")

	var mecha = hangar.garage_panel.get_mecha_base()
	_check(mecha != null, "garage mecha exists")
	if mecha:
		hangar.garage_panel.update_all_slots_preview()
		var mount = mecha.get_node_or_null("ArmLeft/WeaponVisual_shoulder_left")
		if mount == null:
			mount = mecha.get_node_or_null("WeaponVisual_shoulder_left")
		_check(mount != null, "WeaponVisual_shoulder_left node mounted in garage")
		if mount:
			_check(mount.get_child_count() > 0, "shoulder_left mount has visible model children")

	hangar.queue_free()


func _test_equip_button_shoulder_equip() -> void:
	print("-- EQUIP SELECTION button shoulder equip --")
	GlobalData.reset_run_data()
	var hangar = _make_hangar()
	await get_tree().process_frame

	var missile_path := "res://resources/mech/stock/weapon_micro_missile.tres"
	if not ResourceLoader.exists(missile_path):
		missile_path = "res://resources/mech/stock/weapon_missile.tres"
	var uid := _missile_uid(missile_path, "Test Micro")
	_check(uid != "", "micro missile registered")

	hangar.selected_slot = "shoulder_right"
	hangar.part_list_panel.populate("shoulder_right")
	var row := -1
	for i in range(hangar.part_list_panel.controller.visible_weapon_indices.size()):
		var inv_idx: int = hangar.part_list_panel.controller.visible_weapon_indices[i]
		if str(GlobalData.weapons.weapon_inventory[inv_idx].get("uid", "")) == uid:
			row = i
			break
	_check(row >= 0, "registered missile row found in shoulder_right list")
	if row >= 0:
		hangar.part_list_panel.on_item_selected(row)
		_check(hangar.selected_weapon_uid == uid, "selecting row sets selected_weapon_uid")
		hangar.equip_panel.on_equip_pressed()
		print("SHLDR status after EQUIP button: '%s'" % str(hangar.status_message_label.text))
		_check(LoadoutSystem.get_equipped_shoulder_uid("right") == uid, "shoulder_right holds the missile uid after EQUIP SELECTION")

	hangar.queue_free()


func _test_pack_excludes_shoulders_and_swap_math() -> void:
	print("-- pack math: shoulders excluded, uid occupant subtracts --")
	GlobalData.reset_run_data()
	_check(not LoadoutSystem.pack_counts_slot("shoulder_left"), "shoulder_left is not a pack slot")
	_check(not LoadoutSystem.pack_counts_slot("shoulder_right"), "shoulder_right is not a pack slot")
	_check(LoadoutSystem.pack_counts_slot("left"), "left hand is a pack slot")
	_check(LoadoutSystem.pack_counts_slot("weapon_carry"), "weapon_carry is a pack slot")

	var pack_before := LoadoutSystem.get_field_pack_weight()
	var micro_uid := _missile_uid("res://resources/mech/stock/weapon_micro_missile.tres", "Pack Micro")
	LoadoutSystem.set_shoulder_weapon("left", micro_uid)
	_check(is_equal_approx(LoadoutSystem.get_field_pack_weight(), pack_before), "mounting a shoulder pod does not consume pack capacity")
	_check(LoadoutSystem.get_shoulder_weight() > 0.0, "shoulder weight tracked separately")
	_check(is_equal_approx(
		LoadoutSystem.get_loadout_weapons_total(),
		LoadoutSystem.get_hand_carry_weight() + LoadoutSystem.get_shoulder_weight()
	), "loadout total still includes shoulders for chassis weight")

	# Hand swap with a tight pack: replacing the 8kg rifle with the 18kg cannon
	# must subtract the uid occupant (51.46-8+18=61.46 <= 64 fits).
	var cannon_path := "res://resources/mech/stock/weapon_assault_cannon.tres"
	var cannon_uid := _missile_uid(cannon_path, "Pack Cannon")
	var cannon_inst := LoadoutSystem.get_weapon_instance(cannon_uid)
	_check(not cannon_inst.is_empty(), "cannon registered in stash")
	_check(not LoadoutSystem.pack_would_exceed("weapon_left", cannon_path, LoadoutSystem.get_equipped_weapon_uid("left"), "", ""),
		"hand swap subtracts the replaced uid occupant")
	LoadoutSystem.set_shoulder_weapon("left", "")


func _test_cross_mech_shoulder_transfer() -> void:
	print("-- cross-mech shoulder swap owner + transfer --")
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()
	var hangar = _make_hangar()
	await get_tree().process_frame

	var missile_path := "res://resources/mech/stock/weapon_missile.tres"
	var uid := _missile_uid(missile_path, "Shared Missile")
	var active_id := GlobalData.hangar.active_hangar_mech_id
	hangar.set_editing_mech_id(active_id)

	# Park a fake second mech whose SHOULDER holds this exact copy.
	var other := {
		"id": "mech_other_test",
		"name": "Test Mech 02",
		"slot": 2,
		"pilot": "",
		"weapon_loadout": {"left": "", "right": "", "shoulder_left": uid, "shoulder_right": "", "carry": [], "ammo": {}},
	}
	GlobalData.hangar.hangar_mechs.append(other)
	_check(hangar.equip_panel._weapon_swap_owner(uid, missile_path) == "Test Mech 02",
		"shoulder copy on another mech is reported as swap owner")
	_check(hangar.equip_panel._transfer_weapon_from_other_mechs(uid, missile_path) == "Test Mech 02",
		"shoulder copy transfers off the other mech")
	var stripped := true
	for mech in GlobalData.hangar.hangar_mechs:
		if mech is Dictionary and str(mech.get("id", "")) == "mech_other_test":
			var lo = mech.get("weapon_loadout", {})
			stripped = str(lo.get("shoulder_left", "")) == ""
	_check(stripped, "other mech shoulder_left emptied after transfer")

	for i in range(GlobalData.hangar.hangar_mechs.size() - 1, -1, -1):
		if str(GlobalData.hangar.hangar_mechs[i].get("id", "")) == "mech_other_test":
			GlobalData.hangar.hangar_mechs.remove_at(i)
	hangar.queue_free()


func _test_shoulder_survives_mech_switch() -> void:
	print("-- shoulder persists across roster save/switch --")
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()
	var missile_path := "res://resources/mech/stock/weapon_missile.tres"
	var uid := _missile_uid(missile_path, "Keep Missile")
	LoadoutSystem.set_shoulder_weapon("left", uid)
	_check(LoadoutSystem.get_equipped_shoulder_uid("left") == uid, "shoulder set before snapshot")

	var active_id := GlobalData.hangar.active_hangar_mech_id
	_check(HangarManager.save_active(), "save_active snapshots shoulder loadout")
	var snap: Dictionary = HangarManager.get_active_mech()
	var snap_loadout: Dictionary = snap.get("weapon_loadout", {})
	_check(str(snap_loadout.get("shoulder_left", "")) == uid, "roster snapshot keeps shoulder_left uid")

	LoadoutSystem.set_shoulder_weapon("left", "")
	_check(HangarManager.load_mech_state(active_id), "load_mech_state reloads active mech")
	_check(LoadoutSystem.get_equipped_shoulder_uid("left") == uid, "shoulder_left restored after reload")
