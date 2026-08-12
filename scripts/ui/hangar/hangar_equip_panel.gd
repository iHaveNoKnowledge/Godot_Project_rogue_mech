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
		controller._commit_editing_mech_and_save()
		controller._update_total_stats()
		controller._populate_part_list_for_slot(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_confirm()
		return

	if slot.begins_with("weapon"):
		var wpath = info.get("path", "")
		if wpath == "" or not ResourceLoader.exists(wpath):
			controller.status_message_label.text = "Weapon not found in stash."
			return
		if slot == "weapon_carry":
			var carried := GlobalData.count_carry_weapon(wpath)
			var owned := int(info.get("count", 1))
			if carried >= owned:
				controller.status_message_label.text = "You are already carrying every copy of this weapon."
				return
			if controller.garage_panel.would_exceed_field_pack(wpath):
				controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
				return
			GlobalData.add_carry_weapon(wpath)
		else:
			var hand = "left" if slot == "weapon_left" else "right"
			var replaced_path = str(GlobalData.weapon_loadout.get(hand, ""))
			if controller.garage_panel.would_exceed_field_pack(wpath, replaced_path):
				controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
				return
			GlobalData.set_hand_weapon(hand, wpath)
		controller._commit_editing_mech_and_save()
		controller.garage_panel.apply_armor_preview(slot, info)
		controller._update_total_stats()
		controller._populate_part_list_for_slot(slot)
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
	controller._commit_editing_mech_and_save()
	controller.garage_panel.apply_armor_preview(slot, inst)
	controller._update_total_stats()
	controller._populate_part_list_for_slot(slot)
	AudioManager.play_ui_confirm()


func unequip_part(slot: String) -> void:
	if controller.current_mode == "frame":
		GlobalData.equipped_frames.erase(slot)
		GlobalData.part_damage.erase(slot)
		GlobalData.part_damage.erase(slot + "_frame")
		controller._commit_editing_mech_and_save()
		controller._update_total_stats()
		controller._populate_part_list_for_slot(slot)
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
		controller._commit_editing_mech_and_save()
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
		controller._update_total_stats()
		controller._populate_part_list_for_slot(slot)
		controller.garage_panel.update_all_slots_preview()
		AudioManager.play_ui_click()
		return

	GlobalData.unequip_armor_instance(slot)
	controller._commit_editing_mech_and_save()
	var pmm = controller.garage_panel.get_part_mesh_manager()
	if pmm:
		pmm._show_inner_frame(slot)
	controller._update_total_stats()
	controller._populate_part_list_for_slot(slot)
	AudioManager.play_ui_click()


func on_equip_pressed() -> void:
	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		if GlobalData.try_spend_credits(cost):
			GlobalData.frame_upgrade_level += 1
			controller.status_message_label.text = "Frame Reactor Upgraded to Level %d!" % GlobalData.frame_upgrade_level
			GlobalData.save_run()
			controller._update_total_stats()
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
		controller._update_total_stats()
		return

	if not controller.selected_salvage_info.is_empty():
		if not controller.selected_salvage_info.has("uid") or not GlobalData.equip_armor_instance(controller.selected_salvage_info["uid"], controller.selected_slot):
			controller.status_message_label.text = "Failed to equip armor instance."
			return
		controller.status_message_label.text = "Equipped & Saved: %s!" % controller.selected_salvage_info.get("name", "Armor Plate")
		GlobalData.save_run()
		controller._update_total_stats()
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
		controller._update_total_stats()
		controller._populate_part_list_for_slot(controller.selected_slot)
		controller.garage_panel.update_all_slots_preview()
	elif controller.selected_part_path != "" and ResourceLoader.exists(controller.selected_part_path):
		var res = load(controller.selected_part_path)
		if res:
			if controller.selected_slot.begins_with("weapon"):
				# Weapons go into the central weapon_loadout (hands / back).
				var wpath = controller.selected_part_path
				if controller.selected_slot == "weapon_carry":
					if GlobalData.is_weapon_in_carry(wpath):
						controller.status_message_label.text = "Already in back carry!"
						return
					if controller.garage_panel.would_exceed_field_pack(wpath):
						controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
						return
					GlobalData.add_carry_weapon(wpath)
					controller.status_message_label.text = "Added to Back Carry: %s!" % (res.weapon_name if "weapon_name" in res else "Weapon")
				else:
					var hand = "left" if controller.selected_slot == "weapon_left" else "right"
					var replaced_path = str(GlobalData.weapon_loadout.get(hand, ""))
					if controller.garage_panel.would_exceed_field_pack(wpath, replaced_path):
						controller.status_message_label.text = "FIELD PACK full: exceeds carry capacity!"
						return
					GlobalData.set_hand_weapon(hand, wpath)
					controller.status_message_label.text = "Equipped %s on %s hand!" % [(res.weapon_name if "weapon_name" in res else "Weapon"), hand]
				GlobalData.save_run()
				controller._update_total_stats()
				controller.garage_panel.update_all_slots_preview()
				controller._populate_part_list_for_slot(controller.selected_slot)
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
			controller._update_total_stats()
			controller.garage_panel.update_all_slots_preview()
