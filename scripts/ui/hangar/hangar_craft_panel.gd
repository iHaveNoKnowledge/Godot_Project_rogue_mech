class_name HangarCraftPanel
extends RefCounted

## "Craftery" window: crafts a brand-new owned armor instance from a catalog
## template, never touching anything already in the equip list / inventory.
## Extracted from hangar_controller.gd.
##
## Builds a modal listing the craftable templates for the selected slot; the
## craft button validates scrap/credits + blueprint lock, crafts via GlobalData,
## then repaints the equip list + total stats through the controller's
## refresh_panel.after_craft seam. `controller` is also the node the modal is added to.

var controller: Node

var craft_window: Control = null


func open() -> void:
	if not controller.armor_catalog.has(controller.selected_slot):
		if controller.status_message_label:
			controller.status_message_label.text = "Select an armor section first, then open the Craftery."
		return
	controller.action_panel.close()
	close_window()
	build_window()


func close_window() -> void:
	if craft_window and is_instance_valid(craft_window):
		craft_window.queue_free()
	craft_window = null


func build_window() -> void:
	var modal = PanelContainer.new()
	modal.name = "CraftWindow"
	modal.anchor_left = 0.0
	modal.anchor_right = 0.0
	modal.anchor_top = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = 340
	modal.offset_right = 900
	modal.offset_top = -260
	modal.offset_bottom = 260

	var style = StyleBoxFlat.new()
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

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	modal.add_child(vbox)

	var title = Label.new()
	title.text = "🏭 CRAFTERY — CRAFT ARMOR FOR %s" % controller.selected_slot.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", controller._highlight_color)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "Scrap: %d   Credits: %d   Data Cores: %d" % [GlobalData.currency.scrap, GlobalData.currency.credits, GlobalData.currency.data_cores]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	vbox.add_child(hint)

	var bp_hint = Label.new()
	bp_hint.text = "[BLUEPRINT] parts require researching their blueprint at the Research Base first."
	bp_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bp_hint.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	bp_hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(bp_hint)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for info in controller.armor_catalog[controller.selected_slot]:
		var s_cost := ArmorSystem.get_armor_scrap_cost(info)
		var c_cost := ArmorSystem.get_armor_credit_cost(info)
		var blueprint_locked := ArmorSystem.entry_is_blueprint_locked(info)
		var can_afford := GlobalData.currency.scrap >= s_cost and GlobalData.currency.credits >= c_cost

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)

		var info_lbl = Label.new()
		var bp_tag = "  [BLUEPRINT]" if blueprint_locked else ""
		info_lbl.text = "%s%s [%s]  %.1fkg   (%.0f HP / %.0f armor)" % [
			info.get("name", "Armor"), bp_tag, info.get("type", "?"),
			GlobalData.weapons.part_stat(info, "weight", 0.0),
			GlobalData.weapons.part_stat(info, "max_hp", 0.0),
			GlobalData.weapons.part_stat(info, "armor", 0.0)
		]
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info_lbl)

		var craft_btn = Button.new()
		if blueprint_locked:
			craft_btn.text = "RESEARCH TO UNLOCK"
			craft_btn.disabled = true
		else:
			craft_btn.text = "CRAFT  %d scrap / %d cr" % [s_cost, c_cost]
			craft_btn.disabled = not can_afford
			craft_btn.pressed.connect(func(): craft_armor(info))
		craft_btn.custom_minimum_size = Vector2(160, 32)
		row.add_child(craft_btn)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn = Button.new()
	close_btn.text = "CLOSE CRAFTERY"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(func(): close_window())
	vbox.add_child(close_btn)

	if controller.root_control:
		controller.root_control.add_child(modal)
	else:
		controller.add_child(modal)
	craft_window = modal


func craft_armor(info: Dictionary) -> void:
	var pid = info.get("id", "")
	if pid == "":
		if controller.status_message_label:
			controller.status_message_label.text = "Cannot craft: unknown template."
		return
	if ArmorSystem.entry_is_blueprint_locked(info):
		if controller.status_message_label:
			controller.status_message_label.text = "This valkyrion part requires its blueprint researched first."
		return
	var s_cost := ArmorSystem.get_armor_scrap_cost(info)
	var c_cost := ArmorSystem.get_armor_credit_cost(info)
	if GlobalData.currency.scrap < s_cost or GlobalData.currency.credits < c_cost:
		if controller.status_message_label:
			controller.status_message_label.text = "Not enough scrap/credits to craft this armor."
		return
	var inst := ArmorSystem.try_craft_armor_from_catalog(pid)
	if inst.is_empty():
		if controller.status_message_label:
			controller.status_message_label.text = "Failed to craft armor."
		return
	if controller.status_message_label:
		controller.status_message_label.text = "Crafted %s! It is now in the Equip list." % inst.get("name", "Armor")
	GlobalData.save_run()
	close_window()
	controller.refresh_panel.after_craft(controller.selected_slot)
	AudioManager.play_ui_confirm()
