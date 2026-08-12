class_name HangarSlotPanel
extends RefCounted
# Owns the hangar's slot tab selection flow:
#   * select(slot) — switch the editing focus to a mecha body section / weapon
#                    hand: close the craftery, toggle the mode buttons + ammo
#                    loadout box, and refresh the garage camera, part list,
#                    stats and 3D selection highlight.
#
# The slot_tab_buttons dict stays on the controller (the garage panel reads it
# for highlight/blink); this panel only owns the selection behavior.

var controller  # hangar_controller.gd


# Switch the editing focus to `slot` and repaint every dependent widget.
func select(slot: String) -> void:
	controller.selected_slot = slot
	if controller.craft_panel:
		controller.craft_panel.close_window()
	controller.sub_toggle_container.visible = not slot.begins_with("weapon")
	if controller.ammo_panel:
		controller.ammo_panel.ammo_loadout_box.visible = slot.begins_with("weapon")
		if controller.ammo_panel.ammo_loadout_box.visible:
			controller.ammo_panel.refresh()
	controller.garage_panel.update_camera_focus(slot)
	controller.part_list_panel.populate(slot)
	controller.stats_panel.update()
	controller.garage_panel.update_selection_highlight(slot)
