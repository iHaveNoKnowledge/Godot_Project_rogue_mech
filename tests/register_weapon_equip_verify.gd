extends Node

## Headless regression test for the reported bug: after REGISTER assembles a new
## mech into an empty berth, equipping (and unequipping) weapons on the freshly
## registered mech must actually install/remove them — both in the working set
## and in the berth's roster snapshot — even when the same weapon model is still
## carried by the previous mech and the hangar is still in frame mode (which is
## exactly the state REGISTER leaves the player in).
## Run: godot --headless --path . res://tests/register_weapon_equip_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_driver_register_weapon_equip()
	await _verify_fleet_register_weapon_equip()
	print("REGISTER_WEAPON_EQUIP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _verify_driver_register_weapon_equip() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var rp = ctrl.roster_panel_ui
	var old_active_id := GlobalData.active_hangar_mech_id
	_check(old_active_id != "", "an active mech exists before REGISTER")

	# Start the REGISTER assembly for the empty SLOT 02 and equip a walking chassis.
	rp.register_mech(2)
	await get_tree().process_frame
	GlobalData.equipped_frames["body"] = (GlobalData.frame_catalog["body"][0] as Dictionary).duplicate()
	GlobalData.equipped_frames["leg_left"] = (GlobalData.frame_catalog["leg_left"][0] as Dictionary).duplicate()
	GlobalData.equipped_frames["leg_right"] = (GlobalData.frame_catalog["leg_right"][0] as Dictionary).duplicate()
	ctrl.persist_panel.commit_and_save()
	rp.refresh_pending_register()
	if rp.pending_register_button:
		rp.pending_register_button.pressed.emit()
		await get_tree().process_frame
	_check(rp.register_dialog != null and is_instance_valid(rp.register_dialog), "register name dialog opens")

	# Confirm the name-only dialog (REGISTER has no pilot pick) — the new mech
	# becomes active.
	if rp.register_dialog_edit:
		rp.register_dialog_edit.text = "Reg Mech"
	rp._confirm_register(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var new_id: String = ctrl.get_editing_mech_id()
	_check(new_id != "" and new_id != old_active_id, "editing target is the freshly registered mech")
	_check(GlobalData.active_hangar_mech_id == new_id, "driver build makes the registered mech active")
	# REGISTER drops the player on the customize page still in FRAME mode — the
	# exact state that used to hijack weapon equips.
	_check(ctrl.current_mode == "frame", "hangar stays in frame mode after REGISTER (the bug trigger)")

	# The registered mech starts unarmed (assembly began from a blank slate).
	_check(str(GlobalData.weapon_loadout.get("left", "")) == "", "registered mech starts with an empty left hand")

	# Equip the beam rifle (which the OLD active mech still carries) on the new
	# mech's right hand. It must transfer (with the swap confirm) and end up in
	# BOTH the working set and the new mech's roster snapshot.
	var rifle_path := GlobalData.DEFAULT_LEFT_WEAPON_PATH
	var ep = ctrl.equip_panel
	ep.equip_part("weapon_right", {"path": rifle_path, "name": "Beam Rifle"})
	await get_tree().process_frame
	# The old mech holds the rifle -> the swap dialog opens (never a silent fail).
	_check(ep.swap_confirm_modal != null and is_instance_valid(ep.swap_confirm_modal), "cross-mech weapon equip opens the swap dialog")
	var ok := _find_button_by_text(ep.swap_confirm_modal, "SWAP & EQUIP")
	if ok:
		ok.pressed.emit()
	await get_tree().process_frame

	_check(LoadoutSystem.ref_to_path(GlobalData.weapon_loadout.get("right", "")) == rifle_path, "working set holds the rifle on the right hand after confirming")
	var new_mech := _find_mech(new_id)
	_check(not new_mech.is_empty(), "registered mech entry found in the roster")
	if not new_mech.is_empty():
		var snap_loadout: Dictionary = new_mech.get("weapon_loadout", {})
		_check(LoadoutSystem.ref_to_path(snap_loadout.get("right", "")) == rifle_path, "registered mech's roster snapshot holds the rifle after equipping")
	var old_mech := _find_mech(old_active_id)
	if not old_mech.is_empty():
		var old_loadout: Dictionary = old_mech.get("weapon_loadout", {})
		_check(LoadoutSystem.ref_to_path(old_loadout.get("left", "")) != rifle_path, "old mech no longer carries the transferred rifle")

	# The working set must STILL match the registered mech after the transfer
	# (persisting to the wrong berth would leave the rifle only on the snapshot).
	HangarManager.load_mech_state(new_id)
	_check(LoadoutSystem.ref_to_path(GlobalData.weapon_loadout.get("right", "")) == rifle_path, "reloading the registered mech shows the rifle equipped")

	# UNEQUIP must work too while still in frame mode: the weapon leaves the
	# loadout (it used to erase a frames-dict key and silently keep the weapon).
	ep.unequip_part("weapon_right")
	await get_tree().process_frame
	_check(str(GlobalData.weapon_loadout.get("right", "")) == "", "unequip removes the rifle from the working set in frame mode")
	HangarManager.load_mech_state(new_id)
	_check(str(GlobalData.weapon_loadout.get("right", "")) == "", "unequip removes the rifle from the registered mech's snapshot")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_fleet_register_weapon_equip() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var rp = ctrl.roster_panel_ui
	var old_active_id := GlobalData.active_hangar_mech_id

	rp.register_mech(2)
	await get_tree().process_frame
	GlobalData.equipped_frames["body"] = (GlobalData.frame_catalog["body"][0] as Dictionary).duplicate()
	GlobalData.equipped_frames["leg_left"] = (GlobalData.frame_catalog["leg_left"][0] as Dictionary).duplicate()
	GlobalData.equipped_frames["leg_right"] = (GlobalData.frame_catalog["leg_right"][0] as Dictionary).duplicate()
	ctrl.persist_panel.commit_and_save()
	rp.refresh_pending_register()
	if rp.pending_register_button:
		rp.pending_register_button.pressed.emit()
		await get_tree().process_frame
	if rp.register_dialog_edit:
		rp.register_dialog_edit.text = "Fleet Mech"
	rp._confirm_register(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var new_id: String = ctrl.get_editing_mech_id()
	_check(new_id != "" and new_id != old_active_id, "fleet build: editing target is the registered mech")

	# Equip a weapon on the registered mech's LEFT hand (from the working set's
	# empty state) and verify the snapshot + working set both update.
	var shotgun_path := GlobalData.DEFAULT_CARRY_WEAPON_PATH
	var ep = ctrl.equip_panel
	ep.equip_part("weapon_left", {"path": shotgun_path, "name": "Shotgun"})
	await get_tree().process_frame
	if ep.swap_confirm_modal != null and is_instance_valid(ep.swap_confirm_modal):
		var ok := _find_button_by_text(ep.swap_confirm_modal, "SWAP & EQUIP")
		if ok:
			ok.pressed.emit()
		await get_tree().process_frame
	_check(LoadoutSystem.ref_to_path(GlobalData.weapon_loadout.get("left", "")) == shotgun_path, "fleet build: working set holds the shotgun")
	var new_mech := _find_mech(new_id)
	if not new_mech.is_empty():
		var snap_loadout: Dictionary = new_mech.get("weapon_loadout", {})
		_check(LoadoutSystem.ref_to_path(snap_loadout.get("left", "")) == shotgun_path, "fleet build: registered mech's snapshot holds the shotgun")

	ctrl.queue_free()
	await get_tree().process_frame


# --- helpers ---------------------------------------------------------------

func _find_mech(mech_id: String) -> Dictionary:
	for m in GlobalData.hangar_mechs:
		if m is Dictionary and str(m.get("id", "")) == mech_id:
			return m
	return {}


func _find_button_by_text(parent: Node, text: String) -> Button:
	if parent == null:
		return null
	for child in parent.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button_by_text(child, text)
		if found:
			return found
	return null
