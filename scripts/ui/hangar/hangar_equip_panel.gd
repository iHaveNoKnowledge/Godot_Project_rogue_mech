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


func equip_part(slot: String, info: Dictionary) -> void:
	if controller.current_mode == "frame":
		GlobalData.equipped_frames[slot] = info.duplicate()
		# A brand-new frame is installed: it starts at full HP, so wipe any
		# frame damage that belonged to the PREVIOUS frame in this slot.
		GlobalData.part_damage.erase(slot + "_frame")
		controller.persist_panel.commit_and_save()
		controller.stats_panel.update()
		controller.part_list_panel.populate(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_confirm()
		return

	if slot.begins_with("weapon"):
		var wpath = info.get("path", "")
		if wpath == "" or not ResourceLoader.exists(wpath):
			controller.status_message_label.text = "Weapon not found in stash."
			return
		# A weapon model only exists once. Equipping one that is already carried
		# somewhere MOVES it to the new slot (or a new mech) instead of creating
		# a duplicate copy.
		var moved_note := ""
		if slot == "weapon_carry":
			var equipped := GlobalData.weapon_equipped_slot(wpath)
			if equipped == "carry":
				controller.status_message_label.text = "This weapon is already on the back pack."
				return
			# Moving off a hand frees that hand, so its weight leaves the pack too.
			var freed_path: String = wpath if equipped != "" else ""
			if controller.garage_panel.would_exceed_field_pack(wpath, "", freed_path):
				controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
				return
			var from_mech := _transfer_weapon_from_other_mechs(wpath)
			if from_mech != "":
				moved_note = " (transferred from %s)" % from_mech
			elif equipped != "":
				moved_note = " (moved from %s hand)" % equipped
			GlobalData.add_carry_weapon(wpath)
		else:
			var hand = "left" if slot == "weapon_left" else "right"
			var equipped := GlobalData.weapon_equipped_slot(wpath)
			if equipped == hand:
				controller.status_message_label.text = "This weapon is already equipped in the %s hand." % hand
				return
			var replaced_path = str(GlobalData.weapon_loadout.get(hand, ""))
			var freed_path: String = wpath if equipped != "" else ""
			if controller.garage_panel.would_exceed_field_pack(wpath, replaced_path, freed_path):
				controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
				return
			var from_mech := _transfer_weapon_from_other_mechs(wpath)
			if from_mech != "":
				moved_note = " (transferred from %s)" % from_mech
			elif equipped != "":
				moved_note = " (moved from %s)" % ("back carry" if equipped == "carry" else ("right hand" if equipped == "right" else "left hand"))
			GlobalData.set_hand_weapon(hand, wpath)
		if moved_note != "":
			controller.status_message_label.text = "Equipped %s%s" % [info.get("name", "Weapon"), moved_note]
		controller.persist_panel.commit_and_save()
		controller.garage_panel.apply_armor_preview(slot, info)
		controller.stats_panel.update()
		controller.part_list_panel.populate(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_confirm()
		return

	var inst := info
	if not info.has("uid"):
		# Catalog template: crafting it costs scrap + credits and produces a new
		# instance (the catalog itself is never mutated).
		var pid = info.get("id", "")
		if pid == "":
			controller.status_message_label.text = "Cannot acquire armor: unknown catalog entry."
			return
		var entry := GlobalData.get_armor_catalog_entry(pid)
		if entry.is_empty():
			controller.status_message_label.text = "Cannot acquire armor: unknown catalog entry."
			return
		if GlobalData.entry_is_blueprint_locked(entry):
			controller.status_message_label.text = "Cannot equip: research this blueprint at the Research Base first."
			return
		var s_cost := GlobalData.get_armor_scrap_cost(entry)
		var c_cost := GlobalData.get_armor_credit_cost(entry)
		if GlobalData.scrap < s_cost:
			controller.status_message_label.text = "Not enough scrap to craft this armor! (%d scrap needed)" % s_cost
			return
		if GlobalData.credits < c_cost:
			controller.status_message_label.text = "Not enough credits to craft this armor! (%d cr needed)" % c_cost
			return
		inst = GlobalData.try_craft_armor_from_catalog(pid)
		if inst.is_empty():
			controller.status_message_label.text = "Failed to craft armor."
			return
		controller.status_message_label.text = "Armor crafted and equipped!"
	if not GlobalData.equip_armor_instance(inst["uid"], slot):
		controller.status_message_label.text = "Failed to equip armor."
		return
	controller.persist_panel.commit_and_save()
	controller.garage_panel.apply_armor_preview(slot, inst)
	controller.stats_panel.update()
	controller.part_list_panel.populate(slot)
	AudioManager.play_ui_confirm()


# A weapon model may only be carried by ONE mech. When equipping `path` while
# another parked mech already has it in its loadout snapshot, strip it from that
# mech so the weapon TRANSFERS to the berth being edited instead of existing on
# both machines. Returns the name of the mech it was taken from ("" when the
# weapon wasn't equipped on any other mech).
func _transfer_weapon_from_other_mechs(path: String) -> String:
	if path == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar_mechs:
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
				carry.erase(path)
				loadout["carry"] = carry
		return str(mech.get("name", "another mech"))
	return ""


func unequip_part(slot: String) -> void:
	if controller.current_mode == "frame":
		GlobalData.equipped_frames.erase(slot)
		GlobalData.part_damage.erase(slot)
		GlobalData.part_damage.erase(slot + "_frame")
		controller.persist_panel.commit_and_save()
		controller.stats_panel.update()
		controller.part_list_panel.populate(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_click()
		return

	if slot.begins_with("weapon"):
		if slot == "weapon_carry":
			var wpath = controller.selected_part_path
			if wpath != "" and GlobalData.is_weapon_in_carry(wpath):
				GlobalData.remove_carry_weapon(wpath)
		else:
			var hand = "left" if slot == "weapon_left" else "right"
			GlobalData.set_hand_weapon(hand, "")
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

	GlobalData.unequip_armor_instance(slot)
	controller.persist_panel.commit_and_save()
	var pmm = controller.garage_panel.get_part_mesh_manager()
	if pmm:
		pmm._show_inner_frame(slot)
	controller.stats_panel.update()
	controller.part_list_panel.populate(slot)
	AudioManager.play_ui_click()


func on_equip_pressed() -> void:
	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		if GlobalData.try_spend_credits(cost):
			GlobalData.frame_upgrade_level += 1
			controller.status_message_label.text = "Frame Reactor Upgraded to Level %d!" % GlobalData.frame_upgrade_level
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
		var total_capacity = float(GlobalData.get_chassis_stats().get("max_weight", 75.0)) + GlobalData.get_frame_upgrade_weight_bonus()
		if controller.garage_panel.get_total_load(attachment["id"], controller.selected_slot) + float(attachment["weight"]) > total_capacity:
			controller.status_message_label.text = "Attachment rejected: total Frame capacity exceeded."
			return
		var replaced := false
		for i in range(GlobalData.attachments.size()):
			if GlobalData.attachments[i].get("id", "") == attachment["id"] and GlobalData.attachments[i].get("slot", "") == controller.selected_slot:
				GlobalData.attachments[i] = attachment
				replaced = true
				break
		if not replaced:
			GlobalData.attachments.append(attachment)
		controller.status_message_label.text = "Mounted %s on %s. Drag it in 3D to reposition." % [attachment["name"], controller.selected_slot.to_upper()]
		GlobalData.save_run()
		controller.garage_panel.update_all_slots_preview()
		controller.stats_panel.update()
		return

	if not controller.selected_salvage_info.is_empty():
		if not controller.selected_salvage_info.has("uid") or not GlobalData.equip_armor_instance(controller.selected_salvage_info["uid"], controller.selected_slot):
			controller.status_message_label.text = "Failed to equip armor instance."
			return
		controller.status_message_label.text = "Equipped & Saved: %s!" % controller.selected_salvage_info.get("name", "Armor Plate")
		GlobalData.save_run()
		controller.stats_panel.update()
		controller.garage_panel.update_all_slots_preview()
		return

	if controller.current_mode == "frame" and not controller.selected_frame_info.is_empty():
		GlobalData.equipped_frames[controller.selected_slot] = controller.selected_frame_info.duplicate()
		# A brand-new frame is installed: it starts at full HP, so wipe any
		# frame damage that belonged to the PREVIOUS frame in this slot.
		GlobalData.part_damage.erase(controller.selected_slot + "_frame")
		var fname = controller.selected_frame_info.get("name", "Frame")
		controller.status_message_label.text = "Equipped Inner Frame: %s!" % fname
		GlobalData.save_run()
		controller.stats_panel.update()
		controller.part_list_panel.populate(controller.selected_slot)
		controller.garage_panel.update_all_slots_preview()
	elif controller.selected_part_path != "" and ResourceLoader.exists(controller.selected_part_path):
		var res = load(controller.selected_part_path)
		if res:
			if controller.selected_slot.begins_with("weapon"):
				# Weapons go into the central weapon_loadout (hands / back). A weapon
				# model only exists once: equipping one that is already carried MOVES
				# it (same mech slot, or transferred from another parked mech).
				var wpath = controller.selected_part_path
				var equipped := GlobalData.weapon_equipped_slot(wpath)
				var moved_note := ""
				var hand := "left" if controller.selected_slot == "weapon_left" else "right"
				if controller.selected_slot == "weapon_carry":
					if equipped == "carry":
						controller.status_message_label.text = "This weapon is already on the back pack."
						return
					var freed_path: String = wpath if equipped != "" else ""
					if controller.garage_panel.would_exceed_field_pack(wpath, "", freed_path):
						controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
						return
					var from_mech := _transfer_weapon_from_other_mechs(wpath)
					if from_mech != "":
						moved_note = " (transferred from %s)" % from_mech
					elif equipped != "":
						moved_note = " (moved from %s hand)" % equipped
					GlobalData.add_carry_weapon(wpath)
					controller.status_message_label.text = "Added to Back Carry: %s!%s" % [(res.weapon_name if "weapon_name" in res else "Weapon"), moved_note]
				else:
					if equipped == hand:
						controller.status_message_label.text = "This weapon is already equipped in the %s hand." % hand
						return
					var replaced_path = str(GlobalData.weapon_loadout.get(hand, ""))
					var freed_path: String = wpath if equipped != "" else ""
					if controller.garage_panel.would_exceed_field_pack(wpath, replaced_path, freed_path):
						controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
						return
					var from_mech := _transfer_weapon_from_other_mechs(wpath)
					if from_mech != "":
						moved_note = " (transferred from %s)" % from_mech
					elif equipped != "":
						moved_note = " (moved from %s)" % ("back carry" if equipped == "carry" else ("right hand" if equipped == "right" else "left hand"))
					GlobalData.set_hand_weapon(hand, wpath)
					controller.status_message_label.text = "Equipped %s on %s hand!%s" % [(res.weapon_name if "weapon_name" in res else "Weapon"), hand, moved_note]
				GlobalData.save_run()
				controller.stats_panel.update()
				controller.garage_panel.update_all_slots_preview()
				controller.part_list_panel.populate(controller.selected_slot)
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
			GlobalData.equipped_parts[controller.selected_slot] = part_data
			GlobalData.part_damage.erase(controller.selected_slot)
			controller.status_message_label.text = "Equipped & Saved Armor: %s!" % part_data["name"]
			GlobalData.save_run()
			controller.stats_panel.update()
			controller.garage_panel.update_all_slots_preview()
