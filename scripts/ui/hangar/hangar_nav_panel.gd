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
	# Entering the hangar shows the landing sub-menu first — the customize page
	# only appears once the driver picks a topic (CUSTOMIZE / UPGRADE / etc).
	show_hangar_menu()


func switch_custom_mode(mode: String) -> void:
	controller.current_mode = mode
	controller.part_list_panel.populate(controller.selected_slot)


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
	if controller.sub_toggle_container:
		controller.sub_toggle_container.visible = not controller.selected_slot.begins_with("weapon")
	if controller.roster_panel_ui:
		controller.roster_panel_ui.refresh_badge()
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
	if controller.roster_panel_ui:
		controller.roster_panel_ui.show_page()
	controller.garage_panel.call_deferred("update_all_slots_preview")


func _init_scrap_editor() -> void:
	if controller.scrap_editor != null:
		return
	controller.scrap_editor = preload("res://scripts/ui/scrap_repair_editor.gd").new()
	controller.scrap_editor.applied.connect(controller._on_scrap_editor_applied)
	controller.scrap_editor.closed.connect(controller._on_scrap_editor_closed)
	controller.add_child(controller.scrap_editor)
