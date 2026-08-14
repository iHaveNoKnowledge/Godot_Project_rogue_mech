class_name HangarNavPanel
extends RefCounted
# Owns the hangar's submenu (landing list) + page navigation:
#   * show_hangar()         — entry point: open the editor on the piloted mech
#   * show_hangar_menu()    — landing screen: the long vertical sub-menu list
#   * select_submenu(id)    — dispatch to roster / customize / upgrade / craft / catalog / emergency
#   * show_customize_page() — the mech center (garage left, part list left, stats right)
#   * switch_custom_mode()  — swap the left-side slot filter mode
#   * on_back_to_menu_pressed() — from any page back to the landing menu
#
# All scene nodes stay owned by the controller; this panel only reads/writes
# them through `controller.` so the seam matches the other Hangar*Panel scripts.

var controller  # hangar_controller.gd


# "" = landing menu, otherwise the id of the active submenu page.
var current_submenu: String = ""


# Entry point: show the editor on the mech the player is currently piloting.
func show_hangar() -> void:
	controller.visible = true
	controller.get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Open the editor on the mech the player is currently piloting.
	controller._customize_mech_id = GlobalData.active_hangar_mech_id
	controller.stats_panel.update()
	AudioManager.play_hangar_music()
	controller.garage_panel.call_deferred("update_all_slots_preview")
	# Repaint the wounded-pilot warning from the live roster on entry.
	if controller.wounded_banner:
		controller.wounded_banner.refresh()
	# Entering the hangar shows the landing sub-menu first — the customize page
	# only appears once the driver picks a topic (CUSTOMIZE / UPGRADE / etc).
	show_hangar_menu()


func switch_custom_mode(mode: String) -> void:
	controller.current_mode = mode
	controller.part_list_panel.populate(controller.selected_slot)


# Build the landing sub-menu rail (the long vertical list shown first after
# entering the hangar) into `root`. Each entry opens its own page.
func build_landing_rail(root: Control) -> void:
	# Hangar sub-menu rail: the landing screen. A long vertical list on the left
	# shown first after entering the hangar; each entry opens its own page.
	var submenu_panel = PanelContainer.new()
	submenu_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	submenu_panel.offset_top = 90
	submenu_panel.offset_bottom = -20
	submenu_panel.offset_left = 20
	submenu_panel.custom_minimum_size = Vector2(250, 0)
	controller.submenu_rail = submenu_panel
	root.add_child(submenu_panel)

	var style_rail = StyleBoxFlat.new()
	style_rail.bg_color = Color(0.08, 0.1, 0.15, 0.92)
	style_rail.corner_radius_top_left = 8
	style_rail.corner_radius_top_right = 8
	style_rail.corner_radius_bottom_left = 8
	style_rail.corner_radius_bottom_right = 8
	style_rail.content_margin_left = 14
	style_rail.content_margin_right = 14
	style_rail.content_margin_top = 14
	style_rail.content_margin_bottom = 14
	submenu_panel.add_theme_stylebox_override("panel", style_rail)

	var rail_box = VBoxContainer.new()
	rail_box.add_theme_constant_override("separation", 8)
	submenu_panel.add_child(rail_box)

	var rail_title = Label.new()
	rail_title.text = "HANGAR MENU"
	rail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail_title.add_theme_font_size_override("font_size", 18)
	rail_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	rail_box.add_child(rail_title)

	var rail_sep = HSeparator.new()
	rail_box.add_child(rail_sep)

	var submenu_items = [
		{"id": "roster", "label": "ROSTER (จัดเก็บหุ่น)"},
		{"id": "pilots", "label": "PILOTS (นักบินในกองยาน)"},
		{"id": "customize", "label": "CUSTOMIZE (แต่งหุ่น)"},
		{"id": "emergency", "label": "EMERGENCY REPAIR (ซ่อมแซม)"},
		{"id": "upgrade", "label": "UPGRADE (อัพเกรด)"},
		{"id": "craft", "label": "CRAFT (คราฟ)"},
		{"id": "catalog", "label": "CATALOG (แคตตาล็อก)"},
	]
	for item in submenu_items:
		var sbtn = Button.new()
		sbtn.text = item["label"]
		sbtn.custom_minimum_size = Vector2(0, 34)
		sbtn.focus_mode = Control.FOCUS_NONE
		sbtn.pressed.connect(func(): select_submenu(item["id"]))
		rail_box.add_child(sbtn)

	var rail_spacer = Control.new()
	rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_box.add_child(rail_spacer)

	var rail_exit = Button.new()
	rail_exit.text = "EXIT HANGAR"
	rail_exit.custom_minimum_size = Vector2(0, 40)
	rail_exit.focus_mode = Control.FOCUS_NONE
	rail_exit.pressed.connect(func(): if controller.exit_panel: controller.exit_panel.close())
	rail_box.add_child(rail_exit)


# Build the sub-toggle bar (Armor Plating vs Inner Skeleton Frame vs Power
# Upgrade) into `root`. Each button swaps the part-list mode via
# switch_custom_mode().
func build_mode_toggles(root: Control) -> void:
	controller.sub_toggle_container = HBoxContainer.new()
	controller.sub_toggle_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	controller.sub_toggle_container.offset_top = 86
	controller.sub_toggle_container.add_theme_constant_override("separation", 8)
	root.add_child(controller.sub_toggle_container)

	var btn_armor = Button.new()
	btn_armor.text = "🛡️ OUTER ARMOR (SCAVENGER)"
	btn_armor.custom_minimum_size = Vector2(170, 32)
	btn_armor.pressed.connect(func(): switch_custom_mode("armor"))
	controller.sub_toggle_container.add_child(btn_armor)

	var btn_frame = Button.new()
	btn_frame.text = "⚙️ INNER SKELETON FRAME"
	btn_frame.custom_minimum_size = Vector2(170, 32)
	btn_frame.pressed.connect(func(): switch_custom_mode("frame"))
	controller.sub_toggle_container.add_child(btn_frame)

	var btn_attachment = Button.new()
	btn_attachment.text = "🔩 FREE ATTACHMENT"
	btn_attachment.custom_minimum_size = Vector2(170, 32)
	btn_attachment.pressed.connect(func(): switch_custom_mode("attachment"))
	controller.sub_toggle_container.add_child(btn_attachment)

	controller.frame_upgrade_button = Button.new()
	controller.frame_upgrade_button.text = "⚡ REACTOR POWER UPGRADE"
	controller.frame_upgrade_button.custom_minimum_size = Vector2(180, 32)
	controller.frame_upgrade_button.pressed.connect(func(): switch_custom_mode("upgrade"))
	controller.sub_toggle_container.add_child(controller.frame_upgrade_button)


# --- HANGAR SUB-MENU (landing list: CUSTOMIZE / EMERGENCY REPAIR / UPGRADE / CRAFT / CATALOG) ---

# Landing screen: the long vertical sub-menu list. Every page widget is hidden
# until the driver picks a topic.
func show_hangar_menu() -> void:
	current_submenu = ""
	if controller.craft_panel:
		controller.craft_panel.close_window()
	if controller.catalog_panel:
		controller.catalog_panel.close_window()
	if controller.scrap_editor != null and is_instance_valid(controller.scrap_editor) and controller.scrap_editor.visible:
		controller.scrap_editor.close()
	if controller.submenu_rail:
		controller.submenu_rail.visible = true
	if controller.back_to_menu_button:
		controller.back_to_menu_button.visible = false
	if controller.tab_container:
		controller.tab_container.visible = false
	if controller.sub_toggle_container:
		controller.sub_toggle_container.visible = false
	if controller.left_panel:
		controller.left_panel.visible = false
	if controller.right_panel:
		controller.right_panel.visible = false
	if controller.roster_panel_ui:
		controller.roster_panel_ui.hide_page()
		# Leaving the hangar menu drops any in-progress frame assembly.
		controller.roster_panel_ui.close_pending_register()
	if controller.pilots_panel_ui:
		controller.pilots_panel_ui.hide_page()
	if controller.root_control:
		var label := controller.root_control.find_child("SelectionLabel", true, false) as Label
		if label:
			label.text = "HANGAR MENU"
	if controller.garage_panel:
		controller.garage_panel.clear_selection_blink()


# The customize page (mech center, part list left, stats right). Also the base
# surface for upgrade/craft/catalog which open their windows over it.
func show_customize_page() -> void:
	if controller.submenu_rail:
		controller.submenu_rail.visible = false
	if controller.back_to_menu_button:
		controller.back_to_menu_button.visible = true
	if controller.tab_container:
		controller.tab_container.visible = true
	if controller.left_panel:
		controller.left_panel.visible = true
	if controller.right_panel:
		controller.right_panel.visible = true
	if controller.roster_panel_ui:
		controller.roster_panel_ui.set_panel_visible(false)
		controller.roster_panel_ui.set_badge_visible(true)
	if controller.pilots_panel_ui:
		controller.pilots_panel_ui.hide_page()
	if controller.sub_toggle_container:
		controller.sub_toggle_container.visible = not controller.selected_slot.begins_with("weapon")
	if controller.roster_panel_ui:
		controller.roster_panel_ui.refresh_badge()
	# Refresh the right-panel stats (incl. the PILOT line) so the page is never
	# shown with a stale driver readout.
	if controller.stats_panel:
		controller.stats_panel.update()
	controller.part_list_panel.populate(controller.selected_slot)
	controller.garage_panel.update_selection_highlight(controller.selected_slot)


func on_back_to_menu_pressed() -> void:
	if controller.craft_panel:
		controller.craft_panel.close_window()
	if controller.catalog_panel:
		controller.catalog_panel.close_window()
	if controller.scrap_editor != null and is_instance_valid(controller.scrap_editor) and controller.scrap_editor.visible:
		controller.scrap_editor.close()
	show_hangar_menu()


func select_submenu(id: String) -> void:
	current_submenu = id
	if controller.craft_panel:
		controller.craft_panel.close_window()
	if controller.catalog_panel:
		controller.catalog_panel.close_window()
	match id:
		"emergency":
			# Emergency scrap repair is a full-screen overlay opened straight from
			# the landing menu; the menu stays behind so closing the editor
			# returns the driver to the hangar menu.
			_init_scrap_editor()
			var first_slot := ""
			for slot in GlobalData.MECHA_SLOTS:
				if GlobalData.get_emergency_repair_scrap_cost(slot) > 0:
					first_slot = slot
					break
			controller.scrap_editor.open(first_slot)
		"upgrade":
			show_customize_page()
			switch_custom_mode("upgrade")
		"craft":
			show_customize_page()
			if not controller.armor_catalog.has(controller.selected_slot):
				controller.selected_slot = "body"
				controller.garage_panel.update_selection_highlight(controller.selected_slot)
				controller.part_list_panel.populate(controller.selected_slot)
			if controller.craft_panel:
				controller.craft_panel.open()
		"catalog":
			show_customize_page()
			if controller.catalog_panel:
				controller.catalog_panel.build_window()
		"roster":
			_show_roster_page()
		"pilots":
			_show_pilots_page()
		_:
			# "customize" (and any fallback): restore the standard editing view.
			show_customize_page()


func _show_roster_page() -> void:
	current_submenu = "roster"
	if controller.craft_panel:
		controller.craft_panel.close_window()
	if controller.catalog_panel:
		controller.catalog_panel.close_window()
	if controller.scrap_editor != null and is_instance_valid(controller.scrap_editor) and controller.scrap_editor.visible:
		controller.scrap_editor.close()
	if controller.submenu_rail:
		controller.submenu_rail.visible = false
	if controller.back_to_menu_button:
		controller.back_to_menu_button.visible = true
	if controller.tab_container:
		controller.tab_container.visible = false
	if controller.sub_toggle_container:
		controller.sub_toggle_container.visible = false
	if controller.left_panel:
		controller.left_panel.visible = false
	if controller.right_panel:
		controller.right_panel.visible = false
	if controller.pilots_panel_ui:
		controller.pilots_panel_ui.hide_page()
	if controller.roster_panel_ui:
		controller.roster_panel_ui.show_page()
	controller.garage_panel.call_deferred("update_all_slots_preview")


# PILOTS page: full-panel list of every pilot in the convoy (see
# HangarPilotsPanel). Mirrors the roster page so the two never show together.
func _show_pilots_page() -> void:
	current_submenu = "pilots"
	if controller.craft_panel:
		controller.craft_panel.close_window()
	if controller.catalog_panel:
		controller.catalog_panel.close_window()
	if controller.scrap_editor != null and is_instance_valid(controller.scrap_editor) and controller.scrap_editor.visible:
		controller.scrap_editor.close()
	if controller.submenu_rail:
		controller.submenu_rail.visible = false
	if controller.back_to_menu_button:
		controller.back_to_menu_button.visible = true
	if controller.tab_container:
		controller.tab_container.visible = false
	if controller.sub_toggle_container:
		controller.sub_toggle_container.visible = false
	if controller.left_panel:
		controller.left_panel.visible = false
	if controller.right_panel:
		controller.right_panel.visible = false
	if controller.roster_panel_ui:
		controller.roster_panel_ui.hide_page()
	if controller.pilots_panel_ui:
		controller.pilots_panel_ui.show_page()
	controller.garage_panel.call_deferred("update_all_slots_preview")


func _init_scrap_editor() -> void:
	if controller.scrap_editor != null:
		return
	controller.scrap_editor = preload("res://scripts/ui/scrap_repair_editor.gd").new()
	controller.scrap_editor.applied.connect(func(_slot: String): if controller.scrap_panel: controller.scrap_panel.refresh())
	controller.scrap_editor.closed.connect(func(): if controller.scrap_panel: controller.scrap_panel.refresh())
	controller.add_child(controller.scrap_editor)
