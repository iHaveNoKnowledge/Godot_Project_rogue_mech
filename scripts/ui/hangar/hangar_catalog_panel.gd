class_name HangarCatalogPanel
extends RefCounted

## Hangar catalog browser + live hover-stats preview, extracted from
## hangar_controller.gd.
##
## Catalog: a modal listing every chassis model, every craftable armor template
## and the owned weapon stash (build_window / close_window / apply_chassis).
## Opens from the hangar sub-menu ("catalog").
##
## Hover stats: the plain-text stat card under the cursor on the customize part
## list, refreshed every frame from the controller's _process
## (refresh_hover_stats). Pure read-only text built per mode.
##
## Reads controller state (current_mode, selected_slot, catalogs, part list)
## and calls back into it for equipment/durability checks and 3D previews.

var controller: Node

var catalog_window: Control = null
var hover_stats_label: Label = null
var hover_hp_bar_box: VBoxContainer = null
var _last_hover_index: int = -1


# Hover-preview label on the right panel (shows the item under the cursor),
# with its small "--- HOVER INFO ---" section title.
func build_hover_stats_label(right_box: VBoxContainer) -> void:
	var hover_title = Label.new()
	hover_title.text = "--- HOVER INFO ---"
	hover_title.add_theme_font_size_override("font_size", 12)
	hover_title.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6))
	right_box.add_child(hover_title)

	hover_stats_label = Label.new()
	hover_stats_label.text = "Point at an item in the list to preview its stats."
	hover_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_stats_label.add_theme_font_size_override("font_size", 11)
	right_box.add_child(hover_stats_label)

	hover_hp_bar_box = VBoxContainer.new()
	hover_hp_bar_box.add_theme_constant_override("separation", 3)
	right_box.add_child(hover_hp_bar_box)


func close_window() -> void:
	if catalog_window and is_instance_valid(catalog_window):
		catalog_window.queue_free()
	catalog_window = null


# Applies a chassis model chosen from the catalog (chassis selection was moved
# out of the customize page into the catalog).
func apply_chassis(key: String) -> void:
	if not GlobalData.chassis_catalog.has(key):
		return
	controller.selected_chassis_key = key
	GlobalData.weapons.chassis_id = key
	var info: Dictionary = GlobalData.chassis_catalog[key]
	if controller.status_message_label:
		controller.status_message_label.text = "Chassis model set to %s!" % info.get("name", key)
	GlobalData.save_run()
	controller.refresh_panel.after_chassis_change(info)
	AudioManager.play_ui_confirm()
	# Rebuild so the [CURRENT]/ACTIVE marker moves to the new selection.
	build_window()


# A full hangar catalog: every craftable armor template across all slots plus
# the weapons you own, so the driver can browse/craft in one place.
func build_window() -> void:
	controller.action_panel.close()
	controller.craft_panel.close_window()
	close_window()

	var modal = PanelContainer.new()
	modal.name = "CatalogWindow"
	# Dock to the left side of the screen so the 3D Mecha in center/right is clearly visible
	modal.anchor_left = 0.0
	modal.anchor_right = 0.0
	modal.anchor_top = 0.0
	modal.anchor_bottom = 1.0
	modal.offset_left = 20
	modal.offset_right = 540
	modal.offset_top = 40
	modal.offset_bottom = -40

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.94)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = controller._highlight_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	modal.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	modal.add_child(vbox)

	var title = Label.new()
	title.text = "CATALOG — CHASSIS, ARMOR & WEAPONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "Scrap: %d   Credits: %d   Data Cores: %d" % [GlobalData.currency.scrap, GlobalData.currency.credits, GlobalData.currency.data_cores]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	vbox.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	# Chassis models now live here (the CHASSIS tab was moved out of the
	# customize page into the catalog).
	var chassis_title = Label.new()
	chassis_title.text = "=== CHASSIS (MODEL) ==="
	chassis_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	chassis_title.add_theme_font_size_override("font_size", 13)
	rows.add_child(chassis_title)

	for key in GlobalData.chassis_catalog:
		var cinfo: Dictionary = GlobalData.chassis_catalog[key]
		var is_current: bool = key == GlobalData.weapons.chassis_id
		var crow = HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		rows.add_child(crow)

		var clbl = Label.new()
		clbl.text = "%s%s  (load %.0fkg, %.1f m/s)" % [
			("[CURRENT] " if is_current else ""),
			cinfo.get("name", key),
			cinfo.get("max_weight", 75.0),
			cinfo.get("speed", 10.0),
		]
		clbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		crow.add_child(clbl)

		var sel_btn = Button.new()
		if is_current:
			sel_btn.text = "ACTIVE"
			sel_btn.disabled = true
		else:
			sel_btn.text = "SELECT"
			sel_btn.pressed.connect(func(): apply_chassis(key))
		sel_btn.custom_minimum_size = Vector2(100, 30)
		crow.add_child(sel_btn)

	var chass_sep = HSeparator.new()
	rows.add_child(chass_sep)

	for slot in GlobalData.MECHA_SLOTS:
		if not controller.armor_catalog.has(slot):
			continue
		var sec_title = Label.new()
		sec_title.text = "=== %s ===" % slot.to_upper()
		sec_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
		sec_title.add_theme_font_size_override("font_size", 13)
		rows.add_child(sec_title)

		for info in controller.armor_catalog[slot]:
			var s_cost := ArmorSystem.get_armor_scrap_cost(info)
			var c_cost := ArmorSystem.get_armor_credit_cost(info)
			var blueprint_locked := ArmorSystem.entry_is_blueprint_locked(info)

			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			rows.add_child(row)

			var info_lbl = Label.new()
			var bp_tag = "  [BP]" if blueprint_locked else ""
			info_lbl.text = "%s%s [%s]\n%.1fkg (%.0f HP / %.0f def)" % [
				info.get("name", "Armor"), bp_tag, info.get("type", "?"),
				GlobalData.weapons.part_stat(info, "weight", 0.0),
				GlobalData.weapons.part_stat(info, "max_hp", 0.0),
				GlobalData.weapons.part_stat(info, "armor", 0.0)
			]
			info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(info_lbl)

			# Live 3D Preview button
			var prev_btn = Button.new()
			prev_btn.text = "PREVIEW"
			prev_btn.custom_minimum_size = Vector2(75, 30)
			prev_btn.pressed.connect(func():
				controller.garage_panel.update_camera_focus(slot)
				controller.garage_panel.apply_armor_preview(slot, info)
			)
			row.add_child(prev_btn)

			var craft_btn = Button.new()
			if blueprint_locked:
				craft_btn.text = "LOCKED"
				craft_btn.disabled = true
			else:
				craft_btn.text = "CRAFT (%ds/%dc)" % [s_cost, c_cost]
				craft_btn.disabled = GlobalData.currency.scrap < s_cost or GlobalData.currency.credits < c_cost
				craft_btn.pressed.connect(func(): controller.craft_panel.craft_armor(info))
			craft_btn.custom_minimum_size = Vector2(130, 30)
			row.add_child(craft_btn)


	var wsec = Label.new()
	wsec.text = "=== WEAPON STASH (OWNED) ==="
	wsec.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	wsec.add_theme_font_size_override("font_size", 13)
	rows.add_child(wsec)

	if GlobalData.weapons.weapon_inventory.is_empty():
		var none = Label.new()
		none.text = "No weapons owned yet."
		rows.add_child(none)
	for inv in GlobalData.weapons.weapon_inventory:
		var wpath := str(inv.get("path", ""))
		var wname := str(inv.get("name", "Weapon"))
		# Each inventory entry is one physical copy (no x2 count merging).
		var owned := LoadoutSystem.count_owned_weapon(wpath) if wpath != "" else 1
		var type_str := "?"
		var wt := 0.0
		if wpath != "" and ResourceLoader.exists(wpath):
			var res = load(wpath)
			if res:
				type_str = HangarPartText.weapon_type_label(res.weapon_type) if "weapon_type" in res else "?"
				wt = float(res.weight) if "weight" in res and res.weight != null else 0.0
		var wrow = HBoxContainer.new()
		rows.add_child(wrow)
		var wlbl = Label.new()
		if owned > 1:
			wlbl.text = "%s  (x%d owned)  (%s, %.1fkg)" % [wname, owned, type_str, wt]
		else:
			wlbl.text = "%s  (%s, %.1fkg)" % [wname, type_str, wt]
		wlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrow.add_child(wlbl)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var close_btn = Button.new()
	close_btn.text = "CLOSE CATALOG"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(func(): close_window())
	vbox.add_child(close_btn)

	if controller.root_control:
		controller.root_control.add_child(modal)
	else:
		controller.add_child(modal)
	catalog_window = modal


# --- HOVER STATS (right-side preview of the item under the cursor) ---

func force_refresh_hover_stats() -> void:
	_last_hover_index = -1
	refresh_hover_stats()


func refresh_hover_stats() -> void:
	if hover_stats_label == null:
		return
	var idx := hovered_list_index()
	if idx == _last_hover_index:
		return
	_last_hover_index = idx
	if hover_hp_bar_box:
		for child in hover_hp_bar_box.get_children():
			child.queue_free()
	if idx < 0:
		hover_stats_label.text = "Point at an item in the list to preview its stats."
		return
	hover_stats_label.text = stats_text_for_index(idx)
	_update_hover_hp_bar(idx)


func _update_hover_hp_bar(index: int) -> void:
	if hover_hp_bar_box == null:
		return
	if controller.current_mode == "frame" and controller.frame_catalog.has(controller.selected_slot):
		var frame_items = controller.frame_catalog[controller.selected_slot]
		if index >= 0 and index < frame_items.size():
			var info = frame_items[index]
			var is_eq = controller.part_list_panel.is_item_equipped(controller.selected_slot, info)
			var f_info = GlobalData.weapons.equipped_frames.get(controller.selected_slot, info) if is_eq else info
			var dur_ratio: float = GlobalData.get_frame_durability(controller.selected_slot) if is_eq else 1.0
			var fhp = float(f_info.get("hp", f_info.get("max_hp", 20.0)))
			hover_hp_bar_box.add_child(HPPartBar.create_row("Frame", fhp * dur_ratio, fhp, true, false, 200, 8, 11))
	elif controller.armor_catalog.has(controller.selected_slot):
		if index >= 0 and index < controller.visible_salvage_indices.size():
			var salvaged_idx = controller.visible_salvage_indices[index]
			var info = GlobalData.weapons.armor_inventory[salvaged_idx]
			var dur_pct = controller.part_list_panel.instance_durability(controller.selected_slot, info)
			var full_hp = float(GlobalData.part_stat(info, "max_hp", 30.0))
			hover_hp_bar_box.add_child(HPPartBar.create_row("Armor", full_hp * dur_pct, full_hp, false, false, 200, 8, 11))
	elif controller.selected_slot.begins_with("weapon") or controller.selected_slot.begins_with("shoulder"):
		if index >= 0 and index < controller.visible_weapon_indices.size():
			var inv = GlobalData.weapons.weapon_inventory[controller.visible_weapon_indices[index]]
			var wpath = inv.get("path", "")
			if wpath != "" and ResourceLoader.exists(wpath):
				var res = load(wpath)
				if res and int(res.weapon_type) == 5:
					var shp = float(res.shield_hp)
					var wdur = GlobalData.get_durability_ratio(inv)
					hover_hp_bar_box.add_child(HPPartBar.create_row("Shield", shp * wdur, shp, false, true, 200, 8, 11))


func hovered_list_index() -> int:
	var part_item_list = controller.part_item_list
	if part_item_list == null or not part_item_list.visible:
		return -1
	var mouse_pos: Vector2 = part_item_list.get_global_mouse_position()
	if not part_item_list.get_global_rect().has_point(mouse_pos):
		return -1
	return part_item_list.get_item_at_position(part_item_list.get_local_mouse_position())


# Builds a plain-text stat card for a list row WITHOUT changing selection or the
# 3D preview. Mirrors the text of the controller's _on_part_item_selected.
func stats_text_for_index(index: int) -> String:
	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		return "INNER FRAME REACTOR LEVEL: %d -> %d\n\nEFFECTS:\n+25 FRAME HP per slot\n+15.0 kg MAX WEIGHT CAPACITY\n+1.5 m/s DASH THRUST SPEED\n\nUPGRADE COST: %d Credits" % [
			GlobalData.weapons.frame_upgrade_level, GlobalData.weapons.frame_upgrade_level + 1, cost
		]

	if controller.current_mode == "attachment":
		if index < 0 or index >= controller.attachment_catalog.size():
			return ""
		var info = controller.attachment_catalog[index]
		var capacity = controller.garage_panel.get_attachment_capacity(controller.selected_slot)
		var used = controller.garage_panel.get_attachment_weight(controller.selected_slot, info["id"])
		return "ATTACHMENT: %s\n\nTARGET SECTION: %s\nWEIGHT: %.1f kg\nSECTION CAPACITY: %.1f kg\nCURRENT LOAD: %.1f kg\nPOWER COST: %.1f" % [
			info["name"], controller.selected_slot.to_upper(), info["weight"], capacity, used, info["power_cost"]
		]

	if controller.current_mode == "frame" and controller.frame_catalog.has(controller.selected_slot):
		var frame_items = controller.frame_catalog[controller.selected_slot]
		if index < 0 or index >= frame_items.size():
			return ""
		var info = frame_items[index]
		var is_eq = controller.part_list_panel.is_item_equipped(controller.selected_slot, info)
		var f_info = GlobalData.weapons.equipped_frames.get(controller.selected_slot, info) if is_eq else info
		var fname = f_info.get("name", f_info.get("part_name", "Inner Frame"))
		var dur_ratio: float = 1.0
		if is_eq:
			dur_ratio = GlobalData.get_frame_durability(controller.selected_slot)
		var fcap = HangarPartText.frame_capability_text(f_info, dur_ratio)
		var upg := int(f_info.get("upgrade_level", 1))
		var tier_str := "  [Tier %s]" % GlobalData.part_tier_text(upg) if upg > 1 else ""
		if is_eq:
			var fhp = float(f_info.get("hp", f_info.get("max_hp", 20.0)))
			var cur_fhp = fhp * dur_ratio
			return "INNER FRAME PART: %s%s  [E]\nDURABILITY: %.0f%% (%.0f / %.0f HP)\n\n%s\n\nCurrently equipped." % [
				fname, tier_str, dur_ratio * 100.0, cur_fhp, fhp, fcap
			]
		return "INNER FRAME PART: %s%s\nDURABILITY: 100%%\n\n%s\n\nEquip to install fresh at 100%% HP." % [fname, tier_str, fcap]

	if controller.selected_slot.begins_with("weapon") or controller.selected_slot.begins_with("shoulder"):
		if index < 0 or index >= controller.visible_weapon_indices.size():
			return ""
		var inv = GlobalData.weapons.weapon_inventory[controller.visible_weapon_indices[index]]
		var wpath = inv.get("path", "")
		var wname = inv.get("name", "Weapon")
		var wdur = GlobalData.get_durability_ratio(inv)
		var wwt := 0.0
		var wtype := "Unknown"
		var wcap := ""
		if wpath != "" and ResourceLoader.exists(wpath):
			var res = load(wpath)
			if res:
				wwt = float(res.weight) if "weight" in res and res.weight != null else 0.0
				wtype = HangarPartText.weapon_type_label(res.weapon_type) if "weapon_type" in res else "Unknown"
				wcap = HangarPartText.weapon_capability_text(res)
		var owned := LoadoutSystem.count_owned_weapon(wpath)
		var w_upg := int(inv.get("upgrade_level", 1))
		var w_tier_str := "  [Tier %s, +%d%% DMG]" % [GlobalData.part_tier_text(w_upg), (w_upg - 1) * 10] if w_upg > 1 else ""
		if controller.selected_slot == "weapon_carry":
			var carried := LoadoutSystem.count_carry_weapon(wpath)
			return "BACK CARRY: %s%s\nDURABILITY: %.0f%%\n\n%s\nWEIGHT: %.1f kg\nOWNED: x%d | ON PACK: x%d\n\nFIELD PACK: %.1f / %.1f kg" % [
				wname, w_tier_str, wdur * 100.0, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
				wwt, owned, carried,
				LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
			]
		var hand = "left" if controller.selected_slot == "weapon_left" else "right"
		var eq = LoadoutSystem.get_equipped_weapon_uid(hand) == str(inv.get("uid", ""))
		return "%s HAND WEAPON: %s%s%s\nDURABILITY: %.0f%%\n\n%s\nWEIGHT: %.1f kg\nOWNED: x%d\n\nFIELD PACK: %.1f / %.1f kg" % [
			hand.to_upper(), "[E] " if eq else "", wname, w_tier_str, wdur * 100.0,
			wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
			wwt, owned,
			LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
		]

	if controller.armor_catalog.has(controller.selected_slot):
		if index >= 0 and index < controller.visible_salvage_indices.size():
			var inst = GlobalData.weapons.armor_inventory[controller.visible_salvage_indices[index]]
			var item_name = inst.get("name", inst.get("part_name", "Armor Instance"))
			var dur_pct = controller.part_list_panel.instance_durability(controller.selected_slot, inst)
			var acap = HangarPartText.armor_capability_text(inst, dur_pct)
			var is_eq = controller.part_list_panel.is_item_equipped(controller.selected_slot, inst)
			var a_upg := int(inst.get("upgrade_level", 1))
			var a_tier_str := "  [Tier %s]" % GlobalData.part_tier_text(a_upg) if a_upg > 1 else ""
			return "OWNED ARMOR: %s%s  %s\nDURABILITY: %.0f%%\n\n%s" % [
				item_name, a_tier_str, "[E]" if is_eq else "", dur_pct * 100.0, acap
			]
	return ""
