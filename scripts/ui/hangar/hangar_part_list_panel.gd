class_name HangarPartListPanel
extends RefCounted

## Part list populate + selection logic for the hangar customize page. Extracted
## from hangar_controller.gd.
##
## Builds the per-slot item list (upgrade / attachment / frame / weapon / armor
## modes), drives the stats label for the selected row, resolves the selected
## part's info for the ACTION MENU popup, and answers equipped/durability
## queries shared with the catalog panel. The controller owns the ItemList /
## stats Label nodes; this panel fills and reacts to them.

var controller: Node

# Selection state (moved out of the controller with this cluster).
var _is_populating: bool = false
var _last_selected_item_index: int = -1


func populate(slot: String) -> void:
	controller.action_panel.close()
	controller.part_item_list.clear()
	_last_selected_item_index = -1
	controller.visible_salvage_indices.clear()
	controller.visible_frame_indices.clear()
	controller.visible_weapon_indices.clear()
	_is_populating = true  # Block 3D preview during auto-populate

	_update_currently_equipped_display(slot)

	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		controller.part_item_list.add_item("Upgrade Inner Frame to Level %d (%d cr)" % [
			GlobalData.weapons.frame_upgrade_level + 1, cost
		])
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)
		_is_populating = false
		return

	if controller.current_mode == "attachment":
		if slot not in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
			controller.part_item_list.add_item("Select a body section first")
		else:
			var capacity = controller.garage_panel.get_attachment_capacity(slot)
			for info in controller.attachment_catalog:
				var prefix = "[E] " if controller.garage_panel.has_attachment(info["id"], slot) else "    "
				controller.part_item_list.add_item("%s%s (%.1fkg / %.1fkg capacity)" % [prefix, info["name"], info["weight"], capacity])
			if controller.part_item_list.item_count > 0:
				controller.part_item_list.select(0)
				_last_selected_item_index = 0
				on_item_selected(0)
		_is_populating = false
		return

	var is_destroyed = GlobalData.weapons.part_damage.get(slot + "_frame", 0.0) >= 1.0

	if controller.current_mode == "frame" and controller.frame_catalog.has(slot):
		var items = controller.frame_catalog[slot]
		var frows: Array = []
		for f_idx in range(items.size()):
			var info = items[f_idx]
			var is_eq = is_item_equipped(slot, info)
			if is_eq and is_destroyed:
				continue
			var other_user := other_mech_frame_user(slot, info) if not is_eq else ""
			frows.append({"idx": f_idx, "eq": is_eq, "other": other_user})
		# Sort order: [[Currently equipped: Rank 0] -> [Free spares: Rank 1] -> [Taken by other mechs: Rank 2]]
		frows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var rank_a: int = 0 if a["eq"] else (2 if a["other"] != "" else 1)
			var rank_b: int = 0 if b["eq"] else (2 if b["other"] != "" else 1)
			if rank_a != rank_b:
				return rank_a < rank_b
			return int(a["idx"]) < int(b["idx"]))
		for row in frows:
			var f_idx: int = row["idx"]
			var info = items[f_idx]
			var is_eq: bool = row["eq"]
			var other_user: String = str(row["other"])
			var prefix := "[E] " if is_eq else ("" if other_user == "" else "[E·%s] " % other_user)
			var fname = info.get("name", "Frame Part")
			var fhp = float(info.get("hp", 20.0))
			var fwt = float(info.get("weight", 3.0))
			var state_tag = " [DESTROYED]" if (is_eq and is_destroyed) else ""
			var dur_pct = instance_durability(slot, info)
			var cur_fhp = fhp * dur_pct
			var hp_str = "HP: %.0f/%.0f" % [cur_fhp, fhp] if is_eq and dur_pct < 0.999 else "HP: %.0f" % fhp
			var label_str = "%s%s (%s, %.1fkg)%s" % [prefix, fname, hp_str, fwt, state_tag]
			controller.part_item_list.add_item(label_str)
			controller.visible_frame_indices.append(f_idx)
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)
	elif slot.begins_with("weapon"):
		if slot == "weapon_left" or slot == "weapon_right":
			var hand := "left" if slot == "weapon_left" else "right"
			var arm_slot := "arm_left" if hand == "left" else "arm_right"
			if float(GlobalData.weapons.part_damage.get(arm_slot + "_frame", 0.0)) >= 1.0:
				controller.visible_weapon_indices.clear()
				controller.part_item_list.add_item("ARM DESTROYED — cannot equip a weapon to this hand. Repair or replace the arm.")
				_is_populating = false
				return
		controller.visible_weapon_indices.clear()
		var wrows: Array = []
		for index in range(GlobalData.weapons.weapon_inventory.size()):
			var inv = GlobalData.weapons.weapon_inventory[index]
			var is_eq = weapon_in_loadout(slot, inv)
			var other_user := other_mech_weapon_user(slot, str(inv.get("uid", "")), str(inv.get("path", ""))) if not is_eq else ""
			wrows.append({"idx": index, "eq": is_eq, "other": other_user})
		# Sort order: [[Currently equipped: Rank 0] -> [Free spares: Rank 1] -> [Taken by other mechs: Rank 2]]
		wrows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var rank_a: int = 0 if a["eq"] else (2 if a["other"] != "" else 1)
			var rank_b: int = 0 if b["eq"] else (2 if b["other"] != "" else 1)
			if rank_a != rank_b:
				return rank_a < rank_b
			return int(a["idx"]) < int(b["idx"]))
		for row in wrows:
			var index: int = row["idx"]
			var inv = GlobalData.weapons.weapon_inventory[index]
			var is_eq: bool = row["eq"]
			var other_user: String = str(row["other"])
			var wname = inv.get("name", "Weapon")
			var wdur = GlobalData.get_durability_ratio(inv)
			var prefix := "[E] " if is_eq else ("" if other_user == "" else "[E·%s] " % other_user)
			var label_str = "%s%s (DUR: %.0f%%)" % [prefix, wname, wdur * 100.0]
			controller.part_item_list.add_item(label_str)
			controller.visible_weapon_indices.append(index)
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)
	elif controller.armor_catalog.has(slot):
		controller.visible_salvage_indices.clear()
		var shown_uids := {}
		var equipped_uid := ""
		var eq_part = GlobalData.weapons.equipped_parts.get(slot)
		if eq_part is Dictionary:
			equipped_uid = str(eq_part.get("uid", ""))
		var arows: Array = []
		for inst_index in range(GlobalData.weapons.armor_inventory.size()):
			var inst = GlobalData.weapons.armor_inventory[inst_index]
			var uid = str(inst.get("uid", ""))
			if str(inst.get("slot", "")) != slot and uid != equipped_uid:
				continue
			if uid in shown_uids and uid != "":
				continue
			if uid != "":
				shown_uids[uid] = true
			var is_eq = is_item_equipped(slot, inst)
			if is_eq and (GlobalData.weapons.part_damage.get(slot, 0.0) >= 1.0 or GlobalData.weapons.part_damage.get(slot + "_frame", 0.0) >= 1.0):
				continue
			var other_user := other_mech_armor_user(uid) if not is_eq else ""
			arows.append({"idx": inst_index, "eq": is_eq, "other": other_user})
		# Sort order: [[Currently equipped: Rank 0] -> [Free spares: Rank 1] -> [Taken by other mechs: Rank 2]]
		arows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var rank_a: int = 0 if a["eq"] else (2 if a["other"] != "" else 1)
			var rank_b: int = 0 if b["eq"] else (2 if b["other"] != "" else 1)
			if rank_a != rank_b:
				return rank_a < rank_b
			return int(a["idx"]) < int(b["idx"]))
		for row in arows:
			var inst_index: int = int(row["idx"])
			var inst = GlobalData.weapons.armor_inventory[inst_index]
			var is_eq: bool = row["eq"]
			var other_user: String = str(row["other"])
			var prefix := "[E] " if is_eq else ("" if other_user == "" else "[E·%s] " % other_user)
			var state_tag = " [DESTROYED]" if (is_eq and is_destroyed) else ""
			var dur_pct = instance_durability(slot, inst)
			var inst_label = "%s%s [%s] (%.0f%%)%s" % [prefix, inst.get("name", "Armor"), inst.get("type", "Instance"), dur_pct * 100.0, state_tag]
			controller.part_item_list.add_item(inst_label)
			controller.visible_salvage_indices.append(inst_index)
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)

	_is_populating = false  # Restore flag


func _update_currently_equipped_display(slot: String) -> void:
	if controller.currently_equipped_box == null or controller.currently_equipped_label == null:
		return

	if slot.begins_with("weapon"):
		if slot == "weapon_carry":
			var carry_list := LoadoutSystem.get_carry_weapons()
			if not carry_list.is_empty():
				var names: Array[String] = []
				for cw in carry_list:
					var wname: String = cw.weapon_name if (cw and cw.weapon_name != "") else "Weapon"
					var dur: float = 1.0
					for inv in GlobalData.weapons.weapon_inventory:
						if str(inv.get("path", "")) == cw.resource_path or str(inv.get("name", "")) == wname:
							dur = GlobalData.get_durability_ratio(inv)
							break
					names.append("%s (%.0f%%)" % [wname, dur * 100.0])
				controller.currently_equipped_label.text = ", ".join(names)
				controller.currently_equipped_sublabel.text = "Back Carry: %d/%d items | Field Pack: %.1f / %.1f kg" % [
					carry_list.size(), 3, LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
				]
			else:
				controller.currently_equipped_label.text = "(No Back Carry Weapons)"
				controller.currently_equipped_sublabel.text = "Select weapons from inventory below (Max 3)"
		else:
			var hand := "left" if slot == "weapon_left" else "right"
			var hand_label := "Left Hand" if hand == "left" else "Right Hand"
			var uid := LoadoutSystem.get_equipped_weapon_uid(hand)
			var w_name := ""
			var w_dur := 1.0
			var w_wt := 0.0
			var w_dmg_type := ""
			for inv in GlobalData.weapons.weapon_inventory:
				if str(inv.get("uid", "")) == uid:
					w_name = str(inv.get("name", "Weapon"))
					w_dur = GlobalData.get_durability_ratio(inv)
					var wpath = str(inv.get("path", ""))
					if wpath != "" and ResourceLoader.exists(wpath):
						var res = load(wpath)
						if res:
							if "weight" in res and res.weight != null:
								w_wt = float(res.weight)
							if "damage_type" in res and res.damage_type != null:
								w_dmg_type = str(res.damage_type)
					break
			if w_name != "":
				controller.currently_equipped_label.text = w_name
				var dmg_str := (" | %s" % w_dmg_type.capitalize()) if w_dmg_type != "" else ""
				controller.currently_equipped_sublabel.text = "%s | DUR: %.0f%%%s | Wt: %.1fkg" % [hand_label, w_dur * 100.0, dmg_str, w_wt]
			else:
				controller.currently_equipped_label.text = "(No Weapon - %s)" % hand_label
				controller.currently_equipped_sublabel.text = "Select a weapon from inventory below"
		return

	if controller.current_mode == "upgrade":
		controller.currently_equipped_label.text = "Inner Frame Reactor: Level %d" % GlobalData.weapons.frame_upgrade_level
		controller.currently_equipped_sublabel.text = "+%d HP/slot | Dash Speed: +%.1fm/s" % [
			int(GlobalData.weapons.frame_upgrade_level * GlobalData.FRAME_UPGRADE_HP_BONUS),
			GlobalData.weapons.frame_upgrade_level * 1.5
		]
		return

	if controller.current_mode == "attachment":
		var atts = GlobalData.weapons.attachments
		var count := 0
		var used_wt := 0.0
		for a in atts:
			if a is Dictionary and a.get("slot", "") == slot:
				count += 1
				used_wt += float(a.get("weight", 0.0))
		var capacity: float = float(controller.garage_panel.get_attachment_capacity(slot)) if controller.garage_panel else 20.0
		if count > 0:
			controller.currently_equipped_label.text = "%d Attachment Module(s)" % count
			controller.currently_equipped_sublabel.text = "Load: %.1f / %.1f kg capacity" % [used_wt, capacity]
		else:
			controller.currently_equipped_label.text = "(No Attachments)"
			controller.currently_equipped_sublabel.text = "Slot capacity: %.1f kg" % capacity
		return

	if controller.current_mode == "frame":
		var f = GlobalData.weapons.equipped_frames.get(slot)
		if f is Dictionary and not f.is_empty():
			var fname = str(f.get("name", f.get("part_name", "Inner Frame")))
			var fhp = float(f.get("hp", 20.0))
			var fwt = float(f.get("weight", 3.0))
			var frame_dmg = clampf(float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
			var is_destroyed = frame_dmg >= 1.0
			var cur_fhp = fhp * (1.0 - frame_dmg)
			var hp_text = "HP: %.0f / %.0f (%.0f%%)" % [cur_fhp, fhp, (1.0 - frame_dmg) * 100.0] if frame_dmg > 0.001 else "HP: %.0f / %.0f" % [fhp, fhp]
			controller.currently_equipped_label.text = fname + (" [DESTROYED]" if is_destroyed else "")
			controller.currently_equipped_sublabel.text = "%s | Weight: %.1f kg" % [hp_text, fwt]
		else:
			controller.currently_equipped_label.text = "(No Frame Installed)"
			controller.currently_equipped_sublabel.text = "Select a frame from the list below"
		return

	if controller.armor_catalog.has(slot):
		var p = GlobalData.weapons.equipped_parts.get(slot)
		if p is Dictionary and not p.is_empty():
			var pname = str(p.get("name", p.get("part_name", "Armor Plate")))
			var is_destroyed = float(GlobalData.weapons.part_damage.get(slot, 0.0)) >= 1.0 or float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)) >= 1.0
			var dur_pct = instance_durability(slot, p)
			var ac = float(p.get("armor_class", p.get("armor", 1.0)))
			var wt = float(p.get("weight", 4.0))
			controller.currently_equipped_label.text = pname + (" [DESTROYED]" if is_destroyed else "")
			controller.currently_equipped_sublabel.text = "DUR: %.0f%% | Armor: %.1f | Wt: %.1fkg" % [dur_pct * 100.0, ac, wt]
		else:
			controller.currently_equipped_label.text = "(No Armor Equipped)"
			controller.currently_equipped_sublabel.text = "Select an armor plate from inventory below"
		return


func on_item_selected(index: int) -> void:
	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		controller.stats_label.text = "INNER FRAME REACTOR LEVEL: %d -> %d\n\nEFFECTS:\n+25 FRAME HP per slot\n+15.0 kg MAX WEIGHT CAPACITY\n+1.5 m/s DASH THRUST SPEED\n\nUPGRADE COST: %d Credits" % [
			GlobalData.weapons.frame_upgrade_level, GlobalData.weapons.frame_upgrade_level + 1, cost
		]
		controller.selected_salvage_info = {}
		controller.update_tier_display({"upgrade_level": GlobalData.weapons.frame_upgrade_level}, "")
		return

	if controller.current_mode == "attachment":
		if index < 0 or index >= controller.attachment_catalog.size(): return
		controller.selected_attachment_info = controller.attachment_catalog[index].duplicate(true)
		controller.selected_attachment_info["slot"] = controller.selected_slot
		var capacity = controller.garage_panel.get_attachment_capacity(controller.selected_slot)
		var used = controller.garage_panel.get_attachment_weight(controller.selected_slot, controller.selected_attachment_info["id"])
		controller.stats_label.text = "ATTACHMENT: %s\n\nTARGET SECTION: %s\nWEIGHT: %.1f kg\nSECTION CAPACITY: %.1f kg\nCURRENT LOAD: %.1f kg\nPOWER COST: %.1f\n\nDrag on the 3D Mecha to place this module." % [
			controller.selected_attachment_info["name"], controller.selected_slot.to_upper(), controller.selected_attachment_info["weight"], capacity, used, controller.selected_attachment_info["power_cost"]
		]
		return

	if controller.current_mode == "frame" and controller.frame_catalog.has(controller.selected_slot):
		var frame_items = controller.frame_catalog[controller.selected_slot]
		var f_idx = index
		if index >= 0 and index < controller.visible_frame_indices.size():
			f_idx = controller.visible_frame_indices[index]
		if f_idx >= 0 and f_idx < frame_items.size():
			controller.selected_frame_info = frame_items[f_idx]
			controller.selected_part_path = ""
			controller.selected_part_id = ""
			controller.selected_salvage_info = {}

			var fname = controller.selected_frame_info.get("name", controller.selected_frame_info.get("part_name", "Inner Frame"))
			var is_eq = is_item_equipped(controller.selected_slot, controller.selected_frame_info)
			var dur_ratio: float = 1.0
			if is_eq:
				dur_ratio = GlobalData.get_frame_durability(controller.selected_slot)
			var fcap = HangarPartText.frame_capability_text(controller.selected_frame_info, dur_ratio)
			if is_eq:
				var fhp = float(controller.selected_frame_info.get("hp", controller.selected_frame_info.get("max_hp", 20.0)))
				var cur_fhp = fhp * dur_ratio
				controller.stats_label.text = "INNER FRAME PART: %s  [E]\nDURABILITY: %.0f%% (%.0f / %.0f HP)\n\n%s\n\nThis frame is currently equipped." % [
					fname, dur_ratio * 100.0, cur_fhp, fhp, fcap
				]
			else:
				controller.stats_label.text = "INNER FRAME PART: %s\nDURABILITY: 100%%\n\n%s\n\nEquip this frame to install it fresh at 100%% HP." % [
					fname, fcap
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				controller.garage_panel.apply_frame_preview(controller.selected_slot, controller.selected_frame_info)
		controller.update_tier_display(controller.selected_frame_info, controller.selected_slot)
		controller.stats_panel.update()
		return

	if controller.selected_slot.begins_with("weapon"):
		if index >= 0 and index < controller.visible_weapon_indices.size():
			var inv_idx = controller.visible_weapon_indices[index]
			var inv = GlobalData.weapons.weapon_inventory[inv_idx]
			var wpath = inv.get("path", "")
			controller.selected_part_path = wpath
			controller.selected_part_id = wpath
			controller.selected_weapon_uid = str(inv.get("uid", ""))
			controller.selected_frame_info = {}
			controller.selected_salvage_info = {}

			var wname = inv.get("name", "Weapon")
			var wdur = GlobalData.get_durability_ratio(inv)
			var wwt := 0.0
			var wtype := "Unknown"
			var wcap := ""
			var res = null
			if wpath != "" and ResourceLoader.exists(wpath):
				res = load(wpath)
				if res:
					wwt = float(res.weight) if "weight" in res and res.weight != null else 0.0
					wtype = HangarPartText.weapon_type_label(res.weapon_type) if "weapon_type" in res else "Unknown"
					wcap = HangarPartText.weapon_capability_text(res)

			if controller.selected_slot == "weapon_carry":
				var eq = LoadoutSystem.is_weapon_in_carry(wpath)
				var carried := LoadoutSystem.count_carry_weapon(wpath)
				var owned := LoadoutSystem.count_owned_weapon(wpath)
				var prefix = "[E] " if eq else ""
				var copies := ""
				if owned > 1:
					copies = "\nOWNED: x%d | ON PACK: x%d" % [owned, carried]
				controller.stats_label.text = "BACK CARRY: %s%s\nDURABILITY: %.0f%%%s\n\n%s\nWEIGHT: %.1f kg\n\nAssigns a copy to the mech's back pack (FIELD PACK).\nFIELD PACK: %.1f / %.1f kg\nPick weapons from the stash below." % [
					prefix, wname, wdur * 100.0, copies, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
					wwt,
					LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
				]
			else:
				var hand = "left" if controller.selected_slot == "weapon_left" else "right"
				var eq = LoadoutSystem.get_equipped_weapon_uid(hand) == str(inv.get("uid", ""))
				var prefix = "[E] " if eq else ""
				controller.stats_label.text = "%s HAND WEAPON: %s%s\nDURABILITY: %.0f%%\n\n%s\nWEIGHT: %.1f kg\n\nEquip this weapon to the %s hand.\nFIELD PACK: %.1f / %.1f kg" % [
					hand.to_upper(), prefix, wname, wdur * 100.0, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
					wwt, hand,
					LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				controller.garage_panel.preview_weapon_on_hand(controller.selected_slot, inv)
			controller.update_tier_display(inv, controller.selected_slot)
		controller.stats_panel.update()
		return

	if controller.armor_catalog.has(controller.selected_slot):
		if index >= 0 and index < controller.visible_salvage_indices.size():
			var salvaged_idx = controller.visible_salvage_indices[index]
			controller.selected_salvage_info = GlobalData.weapons.armor_inventory[salvaged_idx]
			controller.selected_part_path = ""
			controller.selected_part_id = ""
			controller.selected_frame_info = {}

			var item_name = controller.selected_salvage_info.get("name", controller.selected_salvage_info.get("part_name", "Armor Instance"))
			var acap = HangarPartText.armor_capability_text(controller.selected_salvage_info, instance_durability(controller.selected_slot, controller.selected_salvage_info))

			var is_eq = is_item_equipped(controller.selected_slot, controller.selected_salvage_info)
			if is_eq:
				controller.stats_label.text = "OWNED ARMOR: %s  [E]\nDURABILITY: %.0f%%\n\n%s\n\nThis plate is currently equipped." % [
					item_name, instance_durability(controller.selected_slot, controller.selected_salvage_info) * 100.0, acap
				]
			else:
				var dur_pct = instance_durability(controller.selected_slot, controller.selected_salvage_info)
				controller.stats_label.text = "OWNED ARMOR: %s\nDURABILITY: %.0f%%\n\n%s\n\nEquip this plate to install it." % [
					item_name, dur_pct * 100.0, acap
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				controller.garage_panel.apply_salvage_preview(controller.selected_slot, controller.selected_salvage_info)
	controller.update_tier_display(controller.selected_salvage_info, controller.selected_slot)
	controller.stats_panel.update()


func on_item_clicked(index: int, _at_position: Vector2 = Vector2.ZERO, _mouse_button_index: int = 1) -> void:
	# Single click: select & close any open modal. The Action Popup opens on
	# double-click (item_activated) so a click never accidentally triggers it.
	if index != _last_selected_item_index:
		_last_selected_item_index = index
		on_item_selected(index)
	controller.action_panel.close()


func on_item_activated(index: int) -> void:
	# Double-click (or Enter): Open the Action Popup Modal!
	var info_to_show: Dictionary = resolve_info_for_index(index)
	if not info_to_show.is_empty():
		controller.action_panel.show(info_to_show)


func resolve_info_for_index(index: int) -> Dictionary:
	var info_to_show: Dictionary = {}
	if not controller.selected_salvage_info.is_empty():
		info_to_show = controller.selected_salvage_info
	elif not controller.selected_frame_info.is_empty():
		info_to_show = controller.selected_frame_info
	elif controller.current_mode == "frame" and controller.frame_catalog.has(controller.selected_slot):
		var items = controller.frame_catalog[controller.selected_slot]
		var f_idx = index
		if index >= 0 and index < controller.visible_frame_indices.size():
			f_idx = controller.visible_frame_indices[index]
		if f_idx >= 0 and f_idx < items.size():
			info_to_show = items[f_idx]
	elif controller.selected_slot.begins_with("weapon"):
		if index >= 0 and index < controller.visible_weapon_indices.size():
			var inv_idx = controller.visible_weapon_indices[index]
			info_to_show = GlobalData.weapons.weapon_inventory[inv_idx]
	elif controller.armor_catalog.has(controller.selected_slot):
		if index >= 0 and index < controller.visible_salvage_indices.size():
			info_to_show = GlobalData.weapons.armor_inventory[controller.visible_salvage_indices[index]]
	return info_to_show


func is_item_equipped(slot: String, info: Dictionary) -> bool:
	if info.is_empty():
		return false

	if slot.begins_with("weapon"):
		return weapon_in_loadout(slot, info)

	if controller.current_mode == "frame":
		var cur_frame = GlobalData.weapons.equipped_frames.get(slot, {})
		if cur_frame is Dictionary and not cur_frame.is_empty():
			var name_a = cur_frame.get("name", cur_frame.get("part_name", "")).to_lower()
			var name_b = info.get("name", info.get("part_name", "")).to_lower()
			if name_a != "" and name_b != "":
				return name_a == name_b
		return false
	else:
		var cur = GlobalData.weapons.equipped_parts.get(slot)
		if cur == null:
			return false

		# 0. Match by instance uid (authoritative for owned instances)
		if cur is Dictionary and cur.has("uid") and info.has("uid"):
			return cur["uid"] == info["uid"]

		# 1. Match by unique ID if available
		var cur_id = ""
		if cur is Dictionary:
			cur_id = cur.get("id", "")
		elif cur is Resource and "id" in cur:
			cur_id = cur.id
		var info_id = info.get("id", "")
		# Catalog IDs are authoritative. Do not fall back to path/name when both
		# entries share the same Resource path.
		if info_id != "":
			return cur_id != "" and cur_id == info_id
		if cur_id != "":
			return false

		# 2. Match by Resource file path
		var cur_path = ""
		if cur is Dictionary:
			cur_path = cur.get("path", "")
		elif cur is Resource:
			cur_path = cur.resource_path
		var info_path = info.get("path", "")
		if cur_path != "" and info_path != "" and cur_path == info_path:
			return true

		# 3. Match by Part Name
		var cur_name = ""
		if cur is Dictionary:
			cur_name = cur.get("name", cur.get("part_name", "")).to_lower()
		elif cur is Resource and "part_name" in cur:
			cur_name = cur.part_name.to_lower()
		var info_name = info.get("name", info.get("part_name", "")).to_lower()
		if cur_name != "" and info_name != "":
			return cur_name == info_name

		return false


# Current durability fraction (0..1) of an owned armor instance. Uses the live
# combat damage cache for the equipped one, otherwise the instance's persisted
# durability.
func instance_durability(slot: String, inst: Dictionary) -> float:
	if is_item_equipped(slot, inst):
		if controller.current_mode == "frame":
			return GlobalData.get_frame_durability(slot)
		return GlobalData.get_part_durability(slot)
	return GlobalData.get_durability_ratio(inst)


# Whether this weapon INSTANCE (matched by uid) is part of the current loadout
# for this weapon slot. Only the equipped copy's uid matches, so same-model
# copies never share the "[E]" badge.
func weapon_in_loadout(slot: String, inv: Dictionary) -> bool:
	var uid := str(inv.get("uid", ""))
	if uid == "":
		return false
	if slot == "weapon_carry":
		return LoadoutSystem.is_weapon_in_carry_by_uid(uid)
	var hand = "left" if slot == "weapon_left" else "right"
	return LoadoutSystem.get_equipped_weapon_uid(hand) == uid


# ---------------------------------------------------------------------------
# PARTS USED BY OTHER MECHS
# A parked mech's snapshot owns its equipped parts. The shared inventories
# (armor instances, weapon stash, frame catalog) are shown in EVERY mech's
# list, so a part that another berth already wears must be marked as taken —
# otherwise it reads as an unclaimed spare and gets "duplicated" by equipping.
# These helpers return the name of the other mech using a part, or "".
# ---------------------------------------------------------------------------

# A weapon COPY (matched by instance uid) counts as used by another mech when
# that EXACT copy sits in another berth's loadout (or another hand/carry on this mech).
func other_mech_weapon_user(slot: String, uid: String, path: String) -> String:
	# 1. Check current active mech's other weapon slots:
	var cur_loadout = GlobalData.weapons.weapon_loadout
	if cur_loadout is Dictionary and uid != "":
		if slot == "weapon_left":
			if str(cur_loadout.get("right", "")) == uid:
				return "R.Hand"
			var carry = cur_loadout.get("carry", [])
			if carry is Array and uid in carry:
				return "Back Carry"
		elif slot == "weapon_right":
			if str(cur_loadout.get("left", "")) == uid:
				return "L.Hand"
			var carry = cur_loadout.get("carry", [])
			if carry is Array and uid in carry:
				return "Back Carry"
		elif slot == "weapon_carry":
			if str(cur_loadout.get("left", "")) == uid:
				return "L.Hand"
			if str(cur_loadout.get("right", "")) == uid:
				return "R.Hand"

	# 2. Check other parked mechs in hangar:
	var editing_id: String = controller.get_editing_mech_id()
	if uid != "":
		var by_uid := _other_mech_weapon_uid_user(uid, editing_id)
		if by_uid != "":
			return by_uid
	if path == "":
		return ""
	if LoadoutSystem.has_fleet_spare_weapon(path, editing_id):
		return ""
	var first_user := ""
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if LoadoutSystem.weapon_slot_in_loadout(loadout, path) != "":
			if first_user == "":
				first_user = str(mech.get("name", "Mech"))
	return first_user


# The OTHER parked mech whose loadout holds this exact instance uid.
func _other_mech_weapon_uid_user(uid: String, editing_id: String) -> String:
	if uid == "":
		return ""
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if str(loadout.get("left", "")) == uid or str(loadout.get("right", "")) == uid:
			return str(mech.get("name", "Mech"))
		var carry = loadout.get("carry", [])
		if carry is Array and uid in carry:
			return str(mech.get("name", "Mech"))
	return ""


# An armor instance (matched by uid) is used by another mech when its parts
# snapshot references the same uid in any slot.
func other_mech_armor_user(uid: String) -> String:
	if uid == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var parts = mech.get("parts", {})
		if not (parts is Dictionary):
			continue
		for slot in parts:
			var part = parts[slot]
			if part is Dictionary and str(part.get("uid", "")) == uid:
				return str(mech.get("name", "Mech"))
	return ""


# A frame model (matched by id, falling back to name) is used by another mech
# when its frames snapshot holds the same entry in this slot.
func other_mech_frame_user(slot: String, info: Dictionary) -> String:
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
			return str(mech.get("name", "Mech"))
		if info_name != "" and str(f.get("name", f.get("part_name", ""))).to_lower() == info_name:
			return str(mech.get("name", "Mech"))
	return ""
