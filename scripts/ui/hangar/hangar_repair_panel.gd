class_name HangarRepairPanel
extends RefCounted
# Owns the hangar's field-repair handlers:
#   * repair_part()  — spend credits to clear damage on the selected slot
#   * full_repair()  — clear all part damage for the summed scrap cost
#
# Both repaint the shared status message, stats panel and 3D garage preview
# through `controller.` so the seam matches the other Hangar*Panel scripts.

var controller  # hangar_controller.gd


# Repair the currently selected slot: skip when undamaged, require credits,
# then clear the slot's part/frame damage and repaint.
func repair_part() -> void:
	var repair_cost := GlobalData.get_repair_cost(controller.selected_slot)
	if repair_cost <= 0:
		controller.status_message_label.text = "%s is fully functional!" % controller.selected_slot.to_upper()
		return
	if _block_without_credits(repair_cost):
		return
	GlobalData.part_damage.erase(controller.selected_slot)
	GlobalData.part_damage.erase(controller.selected_slot + "_frame")
	controller.status_message_label.text = "Repaired %s!" % controller.selected_slot.to_upper()
	controller.stats_panel.update()
	controller.garage_panel.update_all_slots_preview()


# Repair every mecha slot at once, clearing all part damage.
func full_repair() -> void:
	var total_cost := 0
	for slot in GlobalData.MECHA_SLOTS:
		total_cost += GlobalData.get_repair_cost(slot)

	if total_cost <= 0:
		controller.status_message_label.text = "All parts OK!"
		return

	if _block_without_credits(total_cost):
		return

	GlobalData.part_damage.clear()
	controller.status_message_label.text = "Full Repair Complete!"
	controller.stats_panel.update()
	controller.garage_panel.update_all_slots_preview()


# Try to spend `cost` credits; on shortfall report the need and return true so
# the caller bails out before touching part damage.
func _block_without_credits(cost: int) -> bool:
	if GlobalData.try_spend_credits(cost):
		return false
	controller.status_message_label.text = "Need %d credits!" % cost
	return true
