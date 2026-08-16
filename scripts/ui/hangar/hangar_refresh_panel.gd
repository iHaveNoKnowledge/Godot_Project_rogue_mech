class_name HangarRefreshPanel
extends RefCounted
# Owns the hangar's post-change refresh helpers, called by other panels after
# the editing state changes:
#   * after_mech_change()   — roster panel: repaint the 3D preview + total
#                             stats, and optionally the slot's part list.
#   * after_chassis_change() — catalog panel: repaint stats + 3D preview with
#                             the newly applied chassis model.
#   * after_craft()          — craft panel: repopulate the slot's part list and
#                             refresh total stats.
#
# Everything is reached through `controller.` so the seam matches the other
# Hangar*Panel scripts.

var controller  # hangar_controller.gd


# Called by the roster panel after the edited berth changes: repaints the 3D
# preview + total stats, and (optionally) the current slot's part list — the
# same refresh set the old in-controller cycle/switch logic ran. The ammo
# panel must repaint too: the ammo-to-carry loadout is stored PER MECH (each
# berth snapshots its own weapon_loadout.ammo), so switching mechs shows a
# different carry loadout — without this refresh the panel kept the previous
# mech's numbers, making ammo look shared across all mechs.
func after_mech_change(repopulate_parts: bool) -> void:
	controller.garage_panel.update_all_slots_preview()
	controller.stats_panel.update()
	if controller.ammo_panel:
		controller.ammo_panel.refresh()
	if repopulate_parts:
		controller.part_list_panel.populate(controller.selected_slot)


# Called by the catalog panel after applying a chassis: repaints total stats
# + the 3D preview with the new model — same refresh set the old in-controller
# chassis apply ran.
func after_chassis_change(chassis_info: Dictionary) -> void:
	controller.stats_panel.update()
	controller.garage_panel.update_all_slots_preview()
	if not chassis_info.is_empty() and controller.garage_panel:
		controller.garage_panel.apply_chassis_preview(chassis_info)


# Called by the craft panel after a successful craft: repopulates the slot's
# part list and refreshes total stats — the same refresh set the old
# in-controller craft flow ran.
func after_craft(slot: String) -> void:
	controller.part_list_panel.populate(slot)
	controller.stats_panel.update()
