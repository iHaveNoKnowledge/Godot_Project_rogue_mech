extends Node

## Headless verification of the hangar cross-mech SWAP confirmation dialog:
## equipping a part that another parked mech already carries opens a confirm
## modal instead of silently stripping the part. Confirming performs the swap;
## cancelling leaves both mechs untouched.
## Run: godot --headless --path . res://tests/swap_confirm_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_weapon_swap()
	await _verify_weapon_cancel()
	await _verify_armor_swap()
	print("SWAP_CONFIRM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


# Two berths: the active mech (edited) plus a spare. The spare's loadout holds a
# beam rifle; equipping that same rifle onto the edited mech's right hand must
# pop the SWAP dialog and NOT move anything until the player confirms.
func _verify_weapon_swap() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var active_id := GlobalData.active_hangar_mech_id
	var spare := GlobalData.build_hangar_mech("Spare", 0)
	var spare_id := str(spare.get("id", ""))
	_check(spare_id != "" and spare_id != active_id, "spare berth exists for the swap test")
	# Give the spare a CLEAN loadout carrying only the rifle on its right hand
	# (build() snapshots the working set, so wipe it first for determinism). The
	# edited mech's loadout is emptied too, so the rifle exists ONLY on the spare.
	_set_spare_loadout(spare_id, {"left": "", "right": GlobalData.DEFAULT_LEFT_WEAPON_PATH, "carry": []})
	GlobalData.weapon_loadout = {"left": "", "right": "", "carry": [], "ammo": {}}
	ctrl.set_editing_mech_id(active_id)
	var ep = ctrl.equip_panel

	# Equipping the same model onto the edited mech opens the confirm dialog and
	# does NOT transfer yet (the spare still carries the rifle).
	var rifle := {"path": GlobalData.DEFAULT_LEFT_WEAPON_PATH, "name": "Beam Rifle"}
	ep.equip_part("weapon_right", rifle)
	await get_tree().process_frame
	_check(ep.swap_confirm_modal != null and is_instance_valid(ep.swap_confirm_modal), "swap dialog opens before a cross-mech weapon transfer")
	_check(_spare_loadout_slot(spare_id, "right") == GlobalData.DEFAULT_LEFT_WEAPON_PATH, "spare still carries the rifle while the dialog is open")
	_check(GlobalData.ref_to_path(GlobalData.weapon_loadout.get("right", "")) != GlobalData.DEFAULT_LEFT_WEAPON_PATH, "edited mech does not take the rifle before confirming")

	# Confirm → the transfer actually happens (spare frees it, edited mech holds it).
	var ok := _find_button_by_text(ep.swap_confirm_modal, "SWAP & EQUIP")
	_check(ok != null, "swap dialog has a confirm button")
	if ok:
		ok.pressed.emit()
	await get_tree().process_frame
	_check(ep.swap_confirm_modal == null or not is_instance_valid(ep.swap_confirm_modal), "swap dialog closes after confirming")
	_check(GlobalData.ref_to_path(GlobalData.weapon_loadout.get("right", "")) == GlobalData.DEFAULT_LEFT_WEAPON_PATH, "edited mech now carries the rifle after confirming")
	_check(_spare_loadout_slot(spare_id, "right") == "", "spare no longer carries the rifle after the swap")

	ctrl.queue_free()
	await get_tree().process_frame


# Cancelling the dialog must leave both mechs completely untouched.
func _verify_weapon_cancel() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var active_id := GlobalData.active_hangar_mech_id
	var spare := GlobalData.build_hangar_mech("Spare", 0)
	var spare_id := str(spare.get("id", ""))
	# The spare carries the shotgun on its back pack; the edited mech does not.
	_set_spare_loadout(spare_id, {"left": "", "right": "", "carry": [GlobalData.DEFAULT_CARRY_WEAPON_PATH]})
	GlobalData.weapon_loadout = {"left": "", "right": "", "carry": [], "ammo": {}}
	ctrl.set_editing_mech_id(active_id)
	var ep = ctrl.equip_panel

	ep.equip_part("weapon_left", {"path": GlobalData.DEFAULT_CARRY_WEAPON_PATH, "name": "Shotgun"})
	await get_tree().process_frame
	_check(ep.swap_confirm_modal != null and is_instance_valid(ep.swap_confirm_modal), "cancel path: dialog opens for a carry weapon held by the spare")
	var cancel := _find_button_by_text(ep.swap_confirm_modal, "CANCEL")
	_check(cancel != null, "swap dialog has a cancel button")
	if cancel:
		cancel.pressed.emit()
	await get_tree().process_frame
	_check(ep.swap_confirm_modal == null or not is_instance_valid(ep.swap_confirm_modal), "cancel path: dialog closes on cancel")
	_check(GlobalData.ref_to_path(GlobalData.weapon_loadout.get("left", "")) != GlobalData.DEFAULT_CARRY_WEAPON_PATH, "cancel path: edited mech takes nothing")
	_check(_spare_carry_has(spare_id, GlobalData.DEFAULT_CARRY_WEAPON_PATH), "cancel path: spare keeps its weapon")

	ctrl.queue_free()
	await get_tree().process_frame


# Armor: an instance worn by the spare berth triggers the same confirm dialog.
func _verify_armor_swap() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var active_id := GlobalData.active_hangar_mech_id
	var spare := GlobalData.build_hangar_mech("Spare", 0)
	var spare_id := str(spare.get("id", ""))
	# Mint an armor instance and park it on the spare's body slot only.
	var body_entry: Dictionary = GlobalData.armor_catalog["body"][0]
	GlobalData.scrap = 500
	GlobalData.credits = 500
	var inst := GlobalData.try_craft_armor_from_catalog(str(body_entry.get("id", "")))
	var uid := str(inst.get("uid", ""))
	_check(uid != "", "armor instance created for the armor swap test")
	_set_spare_parts(spare_id, {"body": {"uid": uid, "equipped": true}})
	ctrl.set_editing_mech_id(active_id)
	var ep = ctrl.equip_panel

	ep.equip_part("body", inst)
	await get_tree().process_frame
	_check(ep.swap_confirm_modal != null and is_instance_valid(ep.swap_confirm_modal), "armor swap opens the confirm dialog")
	var ok := _find_button_by_text(ep.swap_confirm_modal, "SWAP & EQUIP")
	if ok:
		ok.pressed.emit()
	await get_tree().process_frame
	_check(str(GlobalData.equipped_parts.get("body", {}).get("uid", "")) == uid, "armor transfers to the edited mech after confirming")
	_check(not _spare_parts_have(spare_id, uid), "spare no longer wears the plate after the swap")

	ctrl.queue_free()
	await get_tree().process_frame


# --- helpers ---------------------------------------------------------------

func _set_spare_loadout(mech_id: String, loadout: Dictionary) -> void:
	for m in GlobalData.hangar_mechs:
		if str(m.get("id", "")) == mech_id:
			m["weapon_loadout"] = loadout.duplicate(true)
			return


func _spare_loadout_slot(mech_id: String, slot: String) -> String:
	for m in GlobalData.hangar_mechs:
		if str(m.get("id", "")) == mech_id:
			var loadout: Dictionary = m.get("weapon_loadout", {})
			return GlobalData.ref_to_path(loadout.get(slot, ""))
	return ""


func _spare_carry_has(mech_id: String, path: String) -> bool:
	for m in GlobalData.hangar_mechs:
		if str(m.get("id", "")) == mech_id:
			var carry: Array = m.get("weapon_loadout", {}).get("carry", [])
			return carry is Array and path in carry
	return false


func _set_spare_parts(mech_id: String, parts: Dictionary) -> void:
	for m in GlobalData.hangar_mechs:
		if str(m.get("id", "")) == mech_id:
			m["parts"] = parts.duplicate(true)
			return


func _spare_parts_have(mech_id: String, uid: String) -> bool:
	for m in GlobalData.hangar_mechs:
		if str(m.get("id", "")) == mech_id:
			var parts: Dictionary = m.get("parts", {})
			for slot in parts:
				var part = parts[slot]
				if part is Dictionary and str(part.get("uid", "")) == uid:
					return true
	return false


func _find_button_by_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button_by_text(child, text)
		if found:
			return found
	return null
