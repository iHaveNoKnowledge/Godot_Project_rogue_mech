class_name HangarEquipPanel
extends RefCounted

## Equip / unequip flow for a selected part: the EQUIP SELECTION button handler
## plus the shared equip/unequip paths used by the ACTION MENU popup. Extracted
## from hangar_controller.gd.
##
## Handles frames, weapons (hands + back carry with the field-pack cap check),
## and armor (catalog craft-and-equip + owned instances). All state mutations
## go through GlobalData; UI repaint (stats, part list, 3D previews, save) runs
## through controller seams so everything stays in one place.

var controller: Node

# Cross-mech swap confirmation: a weapon/armor model may only be equipped on ONE
# mech, so equipping one that another parked mech already carries strips it off
# that berth. Before doing that the player is asked to confirm — the pending
# operation is stored here and only runs when the dialog's SWAP button fires.
var swap_confirm_modal: Control = null
var _pending_swap_action: Callable = Callable()


# Requests confirmation before a part is stripped off another mech. `kind` is a
# display label ("Weapon"/"Armor"), `continuation` is the equip operation to run
# once the player confirms (it performs the actual transfer + equip).
func _request_swap_confirm(kind: String, part_name: String, from_mech: String, continuation: Callable) -> void:
	# Build the modal FIRST: it starts with _close_swap_confirm(), which would
	# otherwise wipe the continuation we're about to store.
	_build_swap_confirm_modal(kind, part_name, from_mech)
	_pending_swap_action = continuation


func _build_swap_confirm_modal(kind: String, part_name: String, from_mech: String) -> void:
	_close_swap_confirm()
	var modal := PanelContainer.new()
	modal.name = "SwapConfirmDialog"
	modal.anchor_left = 0.5
	modal.anchor_right = 0.5
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -260
	modal.offset_right = 260
	modal.offset_top = -110
	modal.offset_bottom = 110

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	modal.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	modal.add_child(vbox)

	var title := Label.new()
	title.text = "SWAP %s BETWEEN MECHS" % kind.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var body := Label.new()
	body.text = "%s is currently equipped on %s.\nEquipping it here will MOVE it off that mech\n(no duplicate copy is created). Proceed?" % [part_name, from_mech]
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	body.add_theme_font_size_override("font_size", 12)
	vbox.add_child(body)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = "SWAP & EQUIP"
	ok_btn.custom_minimum_size = Vector2(120, 34)
	ok_btn.pressed.connect(_confirm_swap_action)
	btn_row.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 34)
	cancel_btn.pressed.connect(_close_swap_confirm)
	btn_row.add_child(cancel_btn)

	if controller.root_control:
		controller.root_control.add_child(modal)
	else:
		controller.add_child(modal)
	swap_confirm_modal = modal


func _confirm_swap_action() -> void:
	var action := _pending_swap_action
	_close_swap_confirm()
	if action.is_valid():
		action.call()


func _close_swap_confirm() -> void:
	if swap_confirm_modal and is_instance_valid(swap_confirm_modal):
		swap_confirm_modal.queue_free()
	swap_confirm_modal = null
	_pending_swap_action = Callable()


func equip_part(slot: String, info: Dictionary) -> void:
	# Weapon slots (hands / back carry) are mode-independent: clicking a weapon
	# hand tab never changes current_mode, so equipping a weapon must NOT be
	# hijacked by a leftover mode. (REGISTER drops the player into frame mode,
	# so equipping weapons on a freshly registered mech would otherwise run the
	# frame branch below and the weapon would never reach the loadout.)
	if slot.begins_with("weapon"):
		var wpath = info.get("path", "")
		if wpath == "" or not ResourceLoader.exists(wpath):
			controller.status_message_label.text = "Weapon not found in stash."
			return
		# Equip the CLICKED copy: pass its instance uid so only that copy becomes
		# the equipped one (same-model copies never share the [E] badge). Falls
		# back to the path when the entry predates per-instance tracking.
		var wref := str(info.get("uid", wpath))
		# One physical copy = one berth. Equipping a copy another parked mech
		# carries MOVES it to the new slot instead of duplicating it; a free
		# spare copy (same model, different uid) equips without a swap.
		var swap_owner := _weapon_swap_owner(wref, wpath)
		if swap_owner != "":
			_request_swap_confirm("Weapon", info.get("name", "Weapon"), swap_owner,
				func(): _perform_weapon_equip(slot, info, wref))
			return
		_perform_weapon_equip(slot, info, wref)
		return

	if controller.current_mode == "attachment":
		_perform_attachment_mod_toggle(slot, info)
		return

	# Inner frames: only reachable for non-weapon slots, so a leftover frame
	# mode never hijacks weapon equips (see the weapon branch above).
	if controller.current_mode == "frame":
		# A frame model exists once per fleet: equipping one another berth
		# already uses MOVES it off that berth (no duplicate copies). Ask before
		# stripping it, mirroring the weapon/armor swap rule.
		var frame_owner := _frame_swap_owner(slot, info)
		if frame_owner != "":
			_request_swap_confirm("Frame", info.get("name", "Inner Frame"), frame_owner,
				func(): _perform_frame_equip(slot, info))
			return
		_perform_frame_equip(slot, info)
		return


func _perform_attachment_mod_toggle(slot: String, info: Dictionary) -> void:
	var mod_id := str(info.get("id", ""))
	if mod_id == "":
		return
	var equipped_mods := GlobalData.get_equipped_frame_mods_for_slot(slot)
	var found_idx := -1
	for i in range(GlobalData.weapons.attachments.size()):
		var att = GlobalData.weapons.attachments[i]
		if str(att.get("slot", "")) == slot and str(att.get("id", "")) == mod_id:
			found_idx = i
			break

	if found_idx >= 0:
		# Unequip
		GlobalData.weapons.attachments.remove_at(found_idx)
		controller.status_message_label.text = "Unequipped %s from %s frame." % [info.get("name", "Mod"), slot.to_upper()]
	else:
		# Equip
		var max_sockets := GlobalData.get_slot_frame_sockets(slot)
		if equipped_mods.size() >= max_sockets:
			controller.status_message_label.text = "Cannot equip: all %d sockets are full on %s frame!" % [max_sockets, slot.to_upper()]
			return
		var new_att := info.duplicate(true)
		new_att["slot"] = slot
		GlobalData.weapons.attachments.append(new_att)
		controller.status_message_label.text = "Equipped %s on %s frame! (Sockets: %d/%d)" % [info.get("name", "Mod"), slot.to_upper(), equipped_mods.size() + 1, max_sockets]

	if controller.garage_panel:
		controller.garage_panel.update_all_slots_preview()
	controller.part_list_panel.populate(slot)
	controller.stats_panel.update()
	if controller.persist_panel:
		controller.persist_panel.save_custom_mecha_data()

	var inst := info
	if not info.has("uid"):
		# Catalog template: crafting it costs scrap + credits and produces a new
		# instance (the catalog itself is never mutated).
		var pid = info.get("id", "")
		if pid == "":
			controller.status_message_label.text = "Cannot acquire armor: unknown catalog entry."
			return
		var entry := ArmorSystem.get_armor_catalog_entry(pid)
		if entry.is_empty():
			controller.status_message_label.text = "Cannot acquire armor: unknown catalog entry."
			return
		if ArmorSystem.entry_is_blueprint_locked(entry):
			controller.status_message_label.text = "Cannot equip: research this blueprint at the Research Base first."
			return
		var s_cost := ArmorSystem.get_armor_scrap_cost(entry)
		var c_cost := ArmorSystem.get_armor_credit_cost(entry)
		if GlobalData.currency.scrap < s_cost:
			controller.status_message_label.text = "Not enough scrap to craft this armor! (%d scrap needed)" % s_cost
			return
		if GlobalData.currency.credits < c_cost:
			controller.status_message_label.text = "Not enough credits to craft this armor! (%d cr needed)" % c_cost
			return
		inst = ArmorSystem.try_craft_armor_from_catalog(pid)
		if inst.is_empty():
			controller.status_message_label.text = "Failed to craft armor."
			return
		controller.status_message_label.text = "Armor crafted and equipped!"
	# One physical plate = one mech: an armor instance already worn by another
	# parked berth transfers here (that mech's slot is emptied) so the same
	# plate is never equipped twice. Ask before stripping it off that mech.
	if inst.has("uid"):
		var swap_owner := _armor_swap_owner(str(inst["uid"]))
		if swap_owner != "":
			_request_swap_confirm("Armor", inst.get("name", "Armor Plate"), swap_owner,
				func(): _perform_armor_equip(slot, inst))
			return
	_perform_armor_equip(slot, inst)


# Performs the weapon equip (including a cross-mech transfer). Runs directly when
# no other mech holds the weapon, or as the SWAP confirmation continuation.
# `wref` is the clicked instance's uid (preferred) or the weapon path fallback.
func _perform_weapon_equip(slot: String, info: Dictionary, wref: String) -> void:
	var wpath := str(info.get("path", ""))
	var moved_note := ""
	if slot != "weapon_carry" and _arm_destroyed("left" if slot == "weapon_left" else "right"):
		# A destroyed arm cannot hold a weapon: the arm is gone (frame HP 0), so
		# there is no hand to grip the gun. Same rule as combat — a broken arm
		# cannot fire or wield anything.
		controller.status_message_label.text = "Cannot equip: that arm is destroyed! Repair or replace it first."
		return
	if slot == "weapon_carry":
		var equipped := LoadoutSystem.weapon_equipped_slot_ref(wref)
		# With separate instances, another copy may already be on the pack while
		# a spare instance is still available — only reject when there is no
		# free copy left to add.
		if equipped == "carry" and not LoadoutSystem.has_spare_weapon(wpath):
			controller.status_message_label.text = "This weapon is already on the back pack (no spare copies)."
			return
		# Only a MOVED weapon (last free copy) frees its old slot's weight; a
		# spare copy adds new weight instead.
		var spare := LoadoutSystem.has_spare_weapon(wpath)
		var freed_path: String = wpath if (equipped != "" and not spare) else ""
		if controller.garage_panel.would_exceed_field_pack(wpath, "", freed_path):
			controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
			return
		var from_mech := _transfer_weapon_from_other_mechs(wref, wpath)
		if from_mech != "":
			moved_note = " (SWAPPED from %s — that mech no longer carries it)" % from_mech
		elif equipped != "" and not spare:
			moved_note = " (moved from %s hand)" % equipped
		LoadoutSystem.add_carry_weapon(wref)
	else:
		var hand = "left" if slot == "weapon_left" else "right"
		var equipped := LoadoutSystem.weapon_equipped_slot_ref(wref)
		if equipped == hand:
			controller.status_message_label.text = "This weapon is already equipped in the %s hand." % hand
			return
		var replaced_path = str(GlobalData.weapons.weapon_loadout.get(hand, ""))
		# Only a MOVED weapon (last free copy) frees its old slot's weight.
		var spare := LoadoutSystem.has_spare_weapon(wpath)
		var freed_path: String = wpath if (equipped != "" and not spare) else ""
		if controller.garage_panel.would_exceed_field_pack(wpath, replaced_path, freed_path):
			controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
			return
		var from_mech := _transfer_weapon_from_other_mechs(wref, wpath)
		if from_mech != "":
			moved_note = " (SWAPPED from %s — that mech no longer carries it)" % from_mech
		elif equipped != "" and not spare:
			moved_note = " (moved from %s)" % ("back carry" if equipped == "carry" else ("right hand" if equipped == "right" else "left hand"))
		LoadoutSystem.set_hand_weapon(hand, wref)
	if moved_note != "":
		controller.status_message_label.text = "Equipped %s%s" % [info.get("name", "Weapon"), moved_note]
	controller.persist_panel.commit_and_save()
	controller.garage_panel.apply_armor_preview(slot, info)
	controller.stats_panel.update()
	controller.part_list_panel.populate(slot)
	controller.garage_panel.update_all_slots_preview()
	AudioManager.play_ui_confirm()


# Performs the armor equip (including a cross-mech transfer). Runs directly when
# no other mech wears the plate, or as the SWAP confirmation continuation.
# True when the mech's arm on the given side is destroyed (its inner frame
# HP is gone — part_damage["arm_*_frame"] >= 1.0). A destroyed arm cannot hold
# a weapon, so equipping a hand weapon to it is blocked.
func _arm_destroyed(hand: String) -> bool:
	var slot := "arm_left" if hand == "left" else "arm_right"
	return float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)) >= 1.0


func _perform_armor_equip(slot: String, inst: Dictionary) -> void:
	var swap_note := ""
	if inst.has("uid"):
		var from_mech := _transfer_armor_from_other_mechs(str(inst["uid"]))
		if from_mech != "":
			swap_note = " (SWAPPED from %s — that mech no longer wears it)" % from_mech
	if not ArmorSystem.equip_armor_instance(inst["uid"], slot):
		controller.status_message_label.text = "Failed to equip armor."
		return
	if swap_note != "":
		controller.status_message_label.text = "Armor equipped%s" % swap_note
	controller.persist_panel.commit_and_save()
	controller.garage_panel.apply_armor_preview(slot, inst)
	controller.stats_panel.update()
	controller.part_list_panel.populate(slot)
	AudioManager.play_ui_confirm()


# Salvage-armor equip from the on_equip_pressed path. Runs directly when the
# plate is free, or as the SWAP confirmation continuation.
func _perform_salvage_armor_equip() -> void:
	var swap_note := ""
	if controller.selected_salvage_info.has("uid"):
		var from_mech := _transfer_armor_from_other_mechs(str(controller.selected_salvage_info["uid"]))
		if from_mech != "":
			swap_note = " (SWAPPED from %s — that mech no longer wears it)" % from_mech
	if not controller.selected_salvage_info.has("uid") or not ArmorSystem.equip_armor_instance(controller.selected_salvage_info["uid"], controller.selected_slot):
		controller.status_message_label.text = "Failed to equip armor instance."
		return
	controller.status_message_label.text = "Equipped & Saved: %s!%s" % [controller.selected_salvage_info.get("name", "Armor Plate"), swap_note]
	GlobalData.save_run()
	controller.stats_panel.update()
	controller.garage_panel.update_all_slots_preview()


# Weapon equip from the on_equip_pressed path (selected part resource). Runs
# directly when the model is free, or as the SWAP confirmation continuation.
func _perform_selected_weapon_equip(res: Resource) -> void:
	var wpath = controller.selected_part_path
	# Prefer the SELECTED instance's uid so exactly that copy becomes equipped.
	var wref := str(controller.selected_weapon_uid if controller.selected_weapon_uid != "" else wpath)
	var equipped := LoadoutSystem.weapon_equipped_slot_ref(wref)
	var moved_note := ""
	var hand := "left" if controller.selected_slot == "weapon_left" else "right"
	var spare := LoadoutSystem.has_spare_weapon(wpath)
	if controller.selected_slot == "weapon_carry":
		if equipped == "carry" and not spare:
			controller.status_message_label.text = "This weapon is already on the back pack (no spare copies)."
			return
		var freed_path: String = wpath if (equipped != "" and not spare) else ""
		if controller.garage_panel.would_exceed_field_pack(wpath, "", freed_path):
			controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
			return
		var from_mech := _transfer_weapon_from_other_mechs(wref, wpath)
		if from_mech != "":
			moved_note = " (SWAPPED from %s — that mech no longer carries it)" % from_mech
		elif equipped != "" and not spare:
			moved_note = " (moved from %s hand)" % equipped
		LoadoutSystem.add_carry_weapon(wref)
		controller.status_message_label.text = "Added to Back Carry: %s!%s" % [(res.weapon_name if "weapon_name" in res else "Weapon"), moved_note]
	elif _arm_destroyed(hand):
		# A destroyed arm cannot hold a weapon (same rule as combat: a broken
		# arm cannot fire or wield). Block the equip before the transfer logic.
		controller.status_message_label.text = "Cannot equip: that arm is destroyed! Repair or replace it first."
		return
	else:
		if equipped == hand:
			controller.status_message_label.text = "This weapon is already equipped in the %s hand." % hand
			return
		var replaced_path = str(GlobalData.weapons.weapon_loadout.get(hand, ""))
		var freed_path: String = wpath if (equipped != "" and not spare) else ""
		if controller.garage_panel.would_exceed_field_pack(wpath, replaced_path, freed_path):
			controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
			return
		var from_mech := _transfer_weapon_from_other_mechs(wref, wpath)
		if from_mech != "":
			moved_note = " (SWAPPED from %s — that mech no longer carries it)" % from_mech
		elif equipped != "" and not spare:
			moved_note = " (moved from %s)" % ("back carry" if equipped == "carry" else ("right hand" if equipped == "right" else "left hand"))
		LoadoutSystem.set_hand_weapon(hand, wref)
		controller.status_message_label.text = "Equipped %s on %s hand!%s" % [(res.weapon_name if "weapon_name" in res else "Weapon"), hand, moved_note]
	GlobalData.save_run()
	controller.stats_panel.update()
	controller.garage_panel.update_all_slots_preview()
	controller.part_list_panel.populate(controller.selected_slot)


# Frame equip from the equip_part path. Runs directly when the model is free,
# or as the SWAP confirmation continuation (which strips it off another mech
# first so the model is never installed on two berths at once).
func _perform_frame_equip(slot: String, info: Dictionary) -> void:
	_transfer_frame_from_other_mechs(slot, info)
	var fdata: Dictionary = info.duplicate()
	# A fresh install starts at base tier (upgrades apply to this copy).
	fdata["upgrade_level"] = 1
	GlobalData.weapons.equipped_frames[slot] = fdata
	# A brand-new frame is installed: it starts at full HP, so wipe any frame
	# damage that belonged to the PREVIOUS frame in this slot.
	GlobalData.weapons.part_damage.erase(slot + "_frame")
	GlobalData.weapons.part_hit_meta.erase(slot)
	controller.persist_panel.commit_and_save()
	controller.stats_panel.update()
	controller.part_list_panel.populate(slot)
	controller.garage_panel.update_all_slots_preview()
	AudioManager.play_ui_confirm()


# Frame equip from the on_equip_pressed path (selected_frame_info). Runs
# directly when the model is free, or as the SWAP confirmation continuation.
func _perform_selected_frame_equip() -> void:
	_transfer_frame_from_other_mechs(controller.selected_slot, controller.selected_frame_info)
	var fdata: Dictionary = controller.selected_frame_info.duplicate()
	fdata["upgrade_level"] = 1
	GlobalData.weapons.equipped_frames[controller.selected_slot] = fdata
	GlobalData.weapons.part_damage.erase(controller.selected_slot + "_frame")
	GlobalData.weapons.part_hit_meta.erase(controller.selected_slot)
	var fname = controller.selected_frame_info.get("name", "Frame")
	controller.status_message_label.text = "Equipped Inner Frame: %s!" % fname
	GlobalData.save_run()
	controller.stats_panel.update()
	controller.part_list_panel.populate(controller.selected_slot)
	controller.garage_panel.update_all_slots_preview()


# Which OTHER parked mech currently carries this weapon copy? Matched by the
# clicked instance uid FIRST: a free spare copy is never "owned" by another
# berth even when a different copy of the same model is equipped there. Only
# legacy path refs fall back to a model-level check, and only when no spare
# copy exists anywhere in the fleet. Pure lookup (no mutation); returns the
# mech's display name or "" when the copy is free.
func _weapon_swap_owner(wref: String, wpath: String) -> String:
	if wref != "" and not wref.begins_with("res://"):
		var by_uid := _weapon_swap_owner_by_uid(wref)
		if by_uid != "":
			return by_uid
		return ""
	return _weapon_swap_owner_by_path(wpath)


# Exact-instance lookup: the OTHER parked mech whose loadout holds THIS uid.
func _weapon_swap_owner_by_uid(uid: String) -> String:
	if uid == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if str(loadout.get("left", "")) == uid or str(loadout.get("right", "")) == uid:
			return str(mech.get("name", "another mech"))
		var carry = loadout.get("carry", [])
		if carry is Array and uid in carry:
			return str(mech.get("name", "another mech"))
	return ""


# Legacy path fallback: the model only reads as taken when every owned copy is
# already carried by the fleet (no spare left to take instead of stripping).
func _weapon_swap_owner_by_path(path: String) -> String:
	if path == "":
		return ""
	if LoadoutSystem.has_fleet_spare_weapon(path, controller.get_editing_mech_id()):
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if LoadoutSystem.weapon_slot_in_loadout(loadout, path) != "":
			return str(mech.get("name", "another mech"))
	return ""


# Which OTHER parked mech currently wears this armor instance (by uid)? Pure
# lookup (no mutation) used to decide whether a cross-mech swap needs confirming.
# Returns the mech's display name or "" when the plate is free.
func _armor_swap_owner(uid: String) -> String:
	if uid == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == editing_id:
			continue
		var parts = mech.get("parts", {})
		if not (parts is Dictionary):
			continue
		for slot in parts:
			var part = parts[slot]
			if part is Dictionary and str(part.get("uid", "")) == uid:
				return str(mech.get("name", "another mech"))
	return ""


# One physical copy = one berth. When equipping a copy another parked mech
# already carries, strip it from that mech so the weapon TRANSFERS to the berth
# being edited instead of existing on both machines. Matched by the clicked
# instance uid FIRST (only that exact copy moves); legacy path refs fall back
# to the model level and only strip when no spare copy exists anywhere in the
# fleet. Returns the name of the mech it was taken from ("" when free).
func _transfer_weapon_from_other_mechs(wref: String, wpath: String) -> String:
	if wref != "" and not wref.begins_with("res://"):
		return _transfer_weapon_from_other_mechs_by_uid(wref)
	return _transfer_weapon_from_other_mechs_by_path(wpath)


# Strips the exact instance (uid) off whichever OTHER parked mech holds it.
func _transfer_weapon_from_other_mechs_by_uid(uid: String) -> String:
	if uid == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if str(loadout.get("left", "")) == uid:
			loadout["left"] = ""
			return str(mech.get("name", "another mech"))
		if str(loadout.get("right", "")) == uid:
			loadout["right"] = ""
			return str(mech.get("name", "another mech"))
		var carry = loadout.get("carry", [])
		if carry is Array and uid in carry:
			var stripped: Array = []
			for ref in carry:
				if str(ref) != uid:
					stripped.append(ref)
			loadout["carry"] = stripped
			return str(mech.get("name", "another mech"))
	return ""


# Legacy path fallback: strip ONE physical copy off the first other mech, but
# only when no spare copy remains anywhere in the fleet (a spare means the
# equip takes a free copy instead of moving another mech's).
func _transfer_weapon_from_other_mechs_by_path(path: String) -> String:
	if path == "":
		return ""
	if LoadoutSystem.has_fleet_spare_weapon(path, controller.get_editing_mech_id()):
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		var slot := LoadoutSystem.weapon_slot_in_loadout(loadout, path)
		if slot == "":
			continue
		if slot == "left":
			loadout["left"] = ""
		elif slot == "right":
			loadout["right"] = ""
		else:
			var carry = loadout.get("carry", [])
			if carry is Array:
				var stripped: Array = []
				var removed := false
				for ref in carry:
					if not removed and LoadoutSystem.ref_to_path(ref) == path:
						removed = true
						continue
					stripped.append(ref)
				loadout["carry"] = stripped
		return str(mech.get("name", "another mech"))
	return ""


# An armor instance (matched by uid) may only be equipped on ONE mech. When a
# parked mech's parts snapshot already wears this plate, empty that berth's slot
# so the instance transfers to the berth being edited. Returns the name of the
# mech it was taken from ("" when the plate wasn't equipped anywhere else).
func _transfer_armor_from_other_mechs(uid: String) -> String:
	if uid == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == editing_id:
			continue
		var parts = mech.get("parts", {})
		if not (parts is Dictionary):
			continue
		# Find the slot first, then erase AFTER the loop — mutating a Dictionary
		# while iterating its keys is undefined in GDScript.
		var worn_slot := ""
		for slot in parts:
			var part = parts[slot]
			if part is Dictionary and str(part.get("uid", "")) == uid:
				worn_slot = slot
				break
		if worn_slot != "":
			parts.erase(worn_slot)
			return str(mech.get("name", "another mech"))
	return ""


# A frame model exists once per fleet (it comes from the catalog, not a copy
# inventory). Which OTHER parked mech has this model installed in the same
# slot? Pure lookup (no mutation) used to decide whether a cross-mech swap
# needs confirming. Matches by catalog id, falling back to name.
func _frame_swap_owner(slot: String, info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	var info_id := str(info.get("id", ""))
	var info_name := str(info.get("name", info.get("part_name", ""))).to_lower()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var frames = mech.get("frames", {})
		if not (frames is Dictionary):
			continue
		var f = frames.get(slot)
		if not (f is Dictionary):
			continue
		if info_id != "" and str(f.get("id", "")) == info_id:
			return str(mech.get("name", "another mech"))
		if info_name != "" and str(f.get("name", f.get("part_name", ""))).to_lower() == info_name:
			return str(mech.get("name", "another mech"))
	return ""


# A frame model may only be installed on ONE berth. When equipping a model a
# parked mech's frames snapshot already holds in this slot, empty that berth's
# slot so the frame transfers here instead of existing on both mechs.
func _transfer_frame_from_other_mechs(slot: String, info: Dictionary) -> void:
	if info.is_empty():
		return
	var editing_id: String = controller.get_editing_mech_id()
	var info_id := str(info.get("id", ""))
	var info_name := str(info.get("name", info.get("part_name", ""))).to_lower()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var frames = mech.get("frames", {})
		if not (frames is Dictionary):
			continue
		var f = frames.get(slot)
		if not (f is Dictionary):
			continue
		var matches := false
		if info_id != "" and str(f.get("id", "")) == info_id:
			matches = true
		elif info_name != "" and str(f.get("name", f.get("part_name", ""))).to_lower() == info_name:
			matches = true
		if matches:
			frames.erase(slot)
			return


func unequip_part(slot: String) -> void:
	# Same mode-independence rule as equip_part(): weapon slots must be handled
	# before the frame-mode branch, or UNEQUIP on a weapon while in frame mode
	# would erase a frames-dict key and leave the weapon in the loadout.
	if slot.begins_with("weapon"):
		if slot == "weapon_carry":
			var wpath = controller.selected_part_path
			if wpath != "" and LoadoutSystem.is_weapon_in_carry(wpath):
				LoadoutSystem.remove_carry_weapon(wpath)
		else:
			var hand = "left" if slot == "weapon_left" else "right"
			LoadoutSystem.set_hand_weapon(hand, "")
		controller.persist_panel.commit_and_save()
		var mecha = controller.garage_panel.get_mecha_base()
		if mecha:
			for node_name in ["WeaponVisual_left", "WeaponVisual_right", "WeaponVisual_carry"]:
				var existing = mecha.get_node_or_null("ArmLeft/ForearmLeft/" + node_name)
				if existing == null:
					existing = mecha.get_node_or_null("ArmRight/ForearmRight/" + node_name)
				if existing == null:
					existing = mecha.get_node_or_null(node_name)
				if existing:
					existing.queue_free()
		controller.stats_panel.update()
		controller.part_list_panel.populate(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_click()
		return

	# Inner frames: only reachable for non-weapon slots (weapon slots are
	# handled by the branch above regardless of the leftover mode).
	if controller.current_mode == "frame":
		GlobalData.weapons.equipped_frames.erase(slot)
		GlobalData.weapons.part_damage.erase(slot)
		GlobalData.weapons.part_damage.erase(slot + "_frame")
		GlobalData.weapons.part_hit_meta.erase(slot)
		controller.persist_panel.commit_and_save()
		controller.stats_panel.update()
		controller.part_list_panel.populate(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_click()
		return

	ArmorSystem.unequip_armor_instance(slot)
	controller.persist_panel.commit_and_save()
	var pmm = controller.garage_panel.get_part_mesh_manager()
	if pmm:
		pmm._show_inner_frame(slot)
	controller.stats_panel.update()
	controller.part_list_panel.populate(slot)
	AudioManager.play_ui_click()


func update_currently_equipped() -> void:
	if controller and controller.part_list_panel:
		controller.part_list_panel._update_currently_equipped_display(controller.selected_slot)


func on_equip_pressed() -> void:
	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		if GlobalData.currency.try_spend_credits(cost):
			GlobalData.weapons.frame_upgrade_level += 1
			controller.status_message_label.text = "Frame Reactor Upgraded to Level %d!" % GlobalData.weapons.frame_upgrade_level
			GlobalData.save_run()
			controller.stats_panel.update()
		else:
			controller.status_message_label.text = "Insufficient Credits!"
		return

	if controller.current_mode == "attachment" and not controller.selected_attachment_info.is_empty():
		var attachment = controller.selected_attachment_info.duplicate(true)
		attachment["slot"] = controller.selected_slot
		attachment["position"] = controller.garage_panel.get_default_attachment_position(controller.selected_slot)
		attachment["rotation"] = Vector3.ZERO
		attachment["scale"] = Vector3.ONE
		if controller.garage_panel.get_attachment_weight(controller.selected_slot, attachment["id"]) + float(attachment["weight"]) > controller.garage_panel.get_attachment_capacity(controller.selected_slot):
			controller.status_message_label.text = "Attachment rejected: section capacity exceeded."
			return
		var total_capacity = float(LoadoutSystem.get_chassis_stats().get("max_weight", 75.0)) + LoadoutSystem.get_frame_upgrade_weight_bonus()
		if controller.garage_panel.get_total_load(attachment["id"], controller.selected_slot) + float(attachment["weight"]) > total_capacity:
			controller.status_message_label.text = "Attachment rejected: total Frame capacity exceeded."
			return
		var replaced := false
		for i in range(GlobalData.weapons.attachments.size()):
			if GlobalData.weapons.attachments[i].get("id", "") == attachment["id"] and GlobalData.weapons.attachments[i].get("slot", "") == controller.selected_slot:
				GlobalData.weapons.attachments[i] = attachment
				replaced = true
				break
		if not replaced:
			GlobalData.weapons.attachments.append(attachment)
		controller.status_message_label.text = "Mounted %s on %s. Drag it in 3D to reposition." % [attachment["name"], controller.selected_slot.to_upper()]
		GlobalData.save_run()
		controller.garage_panel.update_all_slots_preview()
		controller.stats_panel.update()
		return

	if not controller.selected_salvage_info.is_empty():
		# Same one-plate-per-mech rule as equip_part(): confirm before stripping
		# the instance from whichever other berth wears it.
		if controller.selected_salvage_info.has("uid"):
			var swap_owner := _armor_swap_owner(str(controller.selected_salvage_info["uid"]))
			if swap_owner != "":
				_request_swap_confirm("Armor", controller.selected_salvage_info.get("name", "Armor Plate"), swap_owner,
					func(): _perform_salvage_armor_equip())
				return
		_perform_salvage_armor_equip()
		return

	if controller.current_mode == "frame" and not controller.selected_frame_info.is_empty():
		var frame_owner := _frame_swap_owner(controller.selected_slot, controller.selected_frame_info)
		if frame_owner != "":
			_request_swap_confirm("Frame", controller.selected_frame_info.get("name", "Inner Frame"), frame_owner,
				func(): _perform_selected_frame_equip())
			return
		_perform_selected_frame_equip()
		return
	elif controller.selected_part_path != "" and ResourceLoader.exists(controller.selected_part_path):
		var res = load(controller.selected_part_path)
		if res:
			if controller.selected_slot.begins_with("weapon"):
				# Weapons go into the central weapon_loadout (hands / back). A weapon
				# model only exists once: equipping one that is already carried MOVES
				# it (same mech slot, or transferred from another parked mech).
				# If another parked mech holds it, ask before stripping it off them.
				var wpath = controller.selected_part_path
				# Prefer the selected INSTANCE's uid: a free spare copy (same
				# model, different uid) equips without a swap; only the exact
				# copy another berth holds triggers the move confirmation.
				var wref := str(controller.selected_weapon_uid if controller.selected_weapon_uid != "" else wpath)
				var swap_owner := _weapon_swap_owner(wref, wpath)
				if swap_owner != "":
					_request_swap_confirm("Weapon", (res.weapon_name if "weapon_name" in res else "Weapon"), swap_owner,
						func(): _perform_selected_weapon_equip(res))
					return
				_perform_selected_weapon_equip(res)
				return

			var part_data: Dictionary
			var pname = res.get("part_name") if ("part_name" in res and res.get("part_name") != null) else "Part"
			var php = res.get("max_hp") if ("max_hp" in res and res.get("max_hp") != null) else 100.0
			var pwt = res.get("weight") if ("weight" in res and res.get("weight") != null) else 0.0
			part_data = {
				"id": controller.selected_part_id,
				"name": str(pname),
				"hp": float(php),
				"weight": float(pwt),
				"path": controller.selected_part_path,
				"equipped": true
			}
			GlobalData.weapons.equipped_parts[controller.selected_slot] = part_data
			GlobalData.weapons.part_damage.erase(controller.selected_slot)
			GlobalData.weapons.part_hit_meta.erase(controller.selected_slot)
			controller.status_message_label.text = "Equipped & Saved Armor: %s!" % part_data["name"]
			GlobalData.save_run()
			controller.stats_panel.update()
			controller.garage_panel.update_all_slots_preview()
