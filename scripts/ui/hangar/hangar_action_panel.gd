class_name HangarActionPanel
extends RefCounted

## "ACTION MENU" popup for a selected part: EQUIP/UNEQUIP, REPAIR, UPGRADE,
## PAINT, CANCEL. Extracted from hangar_controller.gd.
##
## Builds a modal over the part list showing context-sensitive actions for the
## part under the cursor. The equip/unequip/repair/upgrade/paint side effects
## run through controller helpers so the state stays in one place. `controller`
## is also the node the modal is added to.

var controller: Node

var part_action_modal: Control = null


func close() -> void:
	# Free EVERY node named PartActionModal. A rapid double-click can briefly
	# create two stacked modals (old one queued for deletion), and
	# get_node_or_null would only find the stale one, leaving the popup stuck.
	if controller.root_control:
		for child in controller.root_control.get_children():
			if child.name == "PartActionModal":
				child.queue_free()
	var local_old = controller.get_node_or_null("PartActionModal")
	if local_old:
		local_old.queue_free()
	part_action_modal = null


func show(info: Dictionary) -> void:
	if info.is_empty():
		return
	close()

	var modal_panel = PanelContainer.new()
	modal_panel.name = "PartActionModal"
	modal_panel.anchor_left = 0.0
	modal_panel.anchor_right = 0.0
	modal_panel.anchor_top = 0.5
	modal_panel.anchor_bottom = 0.5
	modal_panel.offset_left = 340
	modal_panel.offset_right = 730
	modal_panel.offset_top = -140
	modal_panel.offset_bottom = 140

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = controller._accent_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	modal_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	modal_panel.add_child(vbox)

	var item_name = info.get("name", info.get("part_name", "PART OPTIONS"))
	var title = Label.new()
	title.text = "ACTION MENU: %s" % item_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var is_weapon_slot = controller.selected_slot.begins_with("weapon")
	var is_instance = info.has("uid")
	var wt_val = info.get("weight", 10.0)
	var details = Label.new()
	if is_weapon_slot:
		var wp = info.get("path", "")
		if wp != "" and ResourceLoader.exists(wp):
			var res = load(wp)
			if res:
				wt_val = float(res.weight) if "weight" in res and res.weight != null else 0.0
		var wdur = GlobalData.get_durability_ratio(info)
		details.text = "WEIGHT: %.1f kg   DURABILITY: %.0f%%" % [wt_val, wdur * 100.0]
	else:
		var full_hp = GlobalData.weapons.part_stat(info, "max_hp", 100.0)
		if controller.current_mode == "armor" and not is_instance:
			var s_cost := ArmorSystem.get_armor_scrap_cost(info)
			var c_cost := ArmorSystem.get_armor_credit_cost(info)
			details.text = "CRAFT COST: %d scrap + %d credits  |  WEIGHT: %.1f kg" % [s_cost, c_cost, wt_val]
		else:
			var dur_ratio = GlobalData.get_durability_ratio(info)
			if controller.part_list_panel.is_item_equipped(controller.selected_slot, info):
				dur_ratio = GlobalData.get_part_durability(controller.selected_slot)
			details.text = "DURABILITY: %.0f / %.0f HP  |  WEIGHT: %.1f kg" % [full_hp * dur_ratio, full_hp, wt_val]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(details)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	# 1. EQUIP / UNEQUIP CONTEXT BUTTON BASED ON BULLETPROOF EQUIPPED MATCH
	var is_eq = controller.part_list_panel.is_item_equipped(controller.selected_slot, info)

	var toggle_btn = Button.new()
	if is_eq:
		toggle_btn.text = "[ UNEQUIP ]"
		toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	elif controller.current_mode == "armor" and not is_instance:
		toggle_btn.text = "[ CRAFT & EQUIP ]"
		toggle_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		toggle_btn.text = "[ EQUIP ]"
		toggle_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))

	toggle_btn.custom_minimum_size = Vector2(180, 36)
	toggle_btn.pressed.connect(func():
		if is_eq:
			controller.equip_panel.unequip_part(controller.selected_slot)
		else:
			controller.equip_panel.equip_part(controller.selected_slot, info)
		close()
	)
	grid.add_child(toggle_btn)

	# 2. REPAIR — owned armor instances & inner frames only (never mutates the catalog)
	if not is_weapon_slot and (is_instance or controller.current_mode == "frame"):
		var repair_btn = Button.new()
		var repair_cost := RepairSystem.get_repair_cost(controller.selected_slot)
		repair_btn.text = "REPAIR (%d cr)" % repair_cost
		repair_btn.custom_minimum_size = Vector2(180, 36)
		repair_btn.pressed.connect(func():
			if GlobalData.try_spend_credits(repair_cost):
				if info.has("uid"):
					info["durability"] = 1.0
				GlobalData.weapons.part_damage.erase(controller.selected_slot)
				GlobalData.weapons.part_damage.erase(controller.selected_slot + "_frame")
				controller.status_message_label.text = "Part Repaired to 100% HP!"
				GlobalData.save_run()
				controller.stats_panel.update()
				if controller.current_mode == "frame":
					controller.garage_panel.update_all_slots_preview()
				else:
					controller.garage_panel.apply_armor_preview(controller.selected_slot, info)
			else:
				controller.status_message_label.text = "Insufficient Credits for repair!"
			close()
		)
		grid.add_child(repair_btn)

	# 3. UPGRADE — raises the part's upgrade tier (armor +15 HP, weapon +10%
	#    damage, frame +15 HP on the equipped copy). Shared 1 -> 1.1 -> ... -> 2
	#    ladder; the cost scales with the current tier.
	if is_instance or controller.current_mode == "frame":
		var cur_upg := int(info.get("upgrade_level", 1))
		if controller.current_mode == "frame":
			var fdict = GlobalData.weapons.equipped_frames.get(controller.selected_slot, {})
			if fdict is Dictionary:
				cur_upg = int(fdict.get("upgrade_level", 1))
		var cost := GlobalData.get_part_upgrade_cost(cur_upg)
		var upgrade_btn = Button.new()
		if is_weapon_slot:
			upgrade_btn.text = "UPGRADE (+10%% DMG → Tier %s, %d cr)" % [GlobalData.part_tier_text(cur_upg + 1), cost]
		else:
			upgrade_btn.text = "UPGRADE (+15 HP → Tier %s, %d cr)" % [GlobalData.part_tier_text(cur_upg + 1), cost]
		upgrade_btn.custom_minimum_size = Vector2(180, 36)
		upgrade_btn.pressed.connect(func():
			if GlobalData.try_spend_credits(cost):
				if is_weapon_slot:
					info["upgrade_level"] = int(info.get("upgrade_level", 1)) + 1
					info["durability"] = 1.0
					controller.status_message_label.text = "Weapon upgraded to Tier %s (+10%% damage)!" % GlobalData.part_tier_text(int(info["upgrade_level"]))
				elif controller.current_mode == "frame":
					# Frames: the upgrade applies to the EQUIPPED copy (the catalog
					# template is never mutated); requires the frame to be installed.
					var frame_dict = GlobalData.weapons.equipped_frames.get(controller.selected_slot)
					if frame_dict is Dictionary:
						var fhp := float(frame_dict.get("hp", frame_dict.get("max_hp", 20.0)))
						frame_dict["hp"] = fhp + 15.0
						frame_dict["max_hp"] = frame_dict["hp"]
						frame_dict["upgrade_level"] = int(frame_dict.get("upgrade_level", 1)) + 1
						GlobalData.weapons.part_damage.erase(controller.selected_slot + "_frame")
						controller.status_message_label.text = "Frame upgraded to Tier %s! Max HP increased to %.0f" % [GlobalData.part_tier_text(int(frame_dict["upgrade_level"])), frame_dict["hp"]]
					else:
						controller.status_message_label.text = "Equip this frame before upgrading it."
				else:
					var old_hp = float(info.get("hp", info.get("max_hp", 30.0)))
					info["hp"] = old_hp + 15.0
					info["max_hp"] = info["hp"]
					info["upgrade_level"] = int(info.get("upgrade_level", 1)) + 1
					info["durability"] = 1.0
					if GlobalData.weapons.equipped_parts.get(controller.selected_slot) == info:
						GlobalData.weapons.part_damage.erase(controller.selected_slot)
					controller.status_message_label.text = "Part upgraded to Tier %s! Max HP increased to %.0f" % [GlobalData.part_tier_text(int(info["upgrade_level"])), info["hp"]]
				GlobalData.save_run()
				controller.stats_panel.update()
				controller.update_tier_display(info, controller.selected_slot)
			else:
				controller.status_message_label.text = "Insufficient Credits for upgrade (%d cr needed)!" % cost
			close()
		)
		grid.add_child(upgrade_btn)

	# 4. PAINT — recolors this instance (the catalog template is never touched)
	if is_instance and not is_weapon_slot:
			var paint_btn = Button.new()
			paint_btn.text = "PAINT COLOR"
			paint_btn.custom_minimum_size = Vector2(180, 36)
			paint_btn.pressed.connect(func():
				var palette = [
					Color(0.25, 0.40, 0.60), # Mecha Navy Blue
					Color(0.80, 0.20, 0.20), # Crimson Ace Red
					Color(0.90, 0.90, 0.95), # Gundam White
					Color(0.20, 0.65, 0.35), # Zaku Green
					Color(0.85, 0.70, 0.20), # Gold Trim
					Color(0.20, 0.22, 0.26)  # Dark Steel Frame
				]
				var cur_col = info.get("color", Color(0.25, 0.40, 0.60))
				var next_idx = 0
				for i in range(palette.size()):
					if palette[i].is_equal_approx(cur_col):
						next_idx = (i + 1) % palette.size()
						break
				var new_color = palette[next_idx]
				info["color"] = new_color
				info["part_color"] = new_color
				controller.status_message_label.text = "Armor paint updated!"
				controller.garage_panel.apply_armor_preview(controller.selected_slot, info)
				# Only sync the equipped copy when the same instance is mounted;
				# .has() is true even for null/other instances, and Dictionary ==
				# compares by value (not reference) — match on the unique uid instead.
				var equipped = GlobalData.weapons.equipped_parts.get(controller.selected_slot)
				if equipped is Dictionary and info.has("uid") and equipped.get("uid", "") == str(info["uid"]):
					equipped["color"] = new_color
					equipped["part_color"] = new_color
				GlobalData.save_run()
			)
			grid.add_child(paint_btn)

	# 5. CANCEL
	var cancel_btn = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(370, 32)
	cancel_btn.pressed.connect(func(): close())
	vbox.add_child(cancel_btn)

	if controller.root_control:
		controller.root_control.add_child(modal_panel)
	else:
		controller.add_child(modal_panel)
	part_action_modal = modal_panel
