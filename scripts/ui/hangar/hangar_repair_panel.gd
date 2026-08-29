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
# then clear the slot's part/frame damage and repaint. (0% permanent wear penalty in Hangar).
func repair_part() -> void:
	var repair_cost := RepairSystem.get_repair_cost(controller.selected_slot)
	if repair_cost <= 0:
		controller.status_message_label.text = "%s is fully functional!" % controller.selected_slot.to_upper()
		return
	if _block_without_credits(repair_cost):
		return

	GlobalData.weapons.part_damage.erase(controller.selected_slot)
	GlobalData.weapons.part_damage.erase(controller.selected_slot + "_frame")
	GlobalData.weapons.part_hit_meta.erase(controller.selected_slot)
	var msg := "Repaired %s!" % controller.selected_slot.to_upper()
	controller.status_message_label.text = msg
	if controller.has_method("show_toast"):
		controller.show_toast(msg, false)
	GlobalData.save_run()
	controller.refresh_after_part_mutation(controller.selected_slot)


# Repair every mecha slot at once, clearing all part damage (0% permanent wear penalty in Hangar).
func full_repair() -> void:
	var total_cost := 0
	for slot in GlobalData.MECHA_SLOTS:
		total_cost += RepairSystem.get_repair_cost(slot)

	if total_cost <= 0:
		controller.status_message_label.text = "All parts OK!"
		if controller.has_method("show_toast"):
			controller.show_toast("All parts OK!", false)
		return

	if _block_without_credits(total_cost):
		return

	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_hit_meta.clear()
	var msg := "Full Field Repair Complete!"
	controller.status_message_label.text = msg
	if controller.has_method("show_toast"):
		controller.show_toast(msg, false)
	GlobalData.save_run()
	controller.refresh_after_part_mutation()


# Full overhaul of the mecha: restores all frame and equipped armor durabilities to 100%.
func full_overhaul() -> void:
	var total_scrap := 25
	var total_credits := 120
	if GlobalData.currency.scrap < total_scrap:
		var err := "Need %d scrap for full overhaul!" % total_scrap
		controller.status_message_label.text = err
		if controller.has_method("show_toast"):
			controller.show_toast(err, true)
		return
	if GlobalData.currency.credits < total_credits:
		var err := "Need %d credits for full overhaul!" % total_credits
		controller.status_message_label.text = err
		if controller.has_method("show_toast"):
			controller.show_toast(err, true)
		return

	GlobalData.currency.try_spend_scrap(total_scrap)
	GlobalData.currency.try_spend_credits(total_credits)

	for slot in GlobalData.MECHA_SLOTS:
		GlobalData.restore_part_durability(slot, 1.0)
		GlobalData.restore_frame_durability(slot, 1.0)
	GlobalData.restore_weapon_durability("left", 1.0)
	GlobalData.restore_weapon_durability("right", 1.0)
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_hit_meta.clear()

	var msg := "Full Mecha Overhaul Complete! Durability restored to 100%."
	controller.status_message_label.text = msg
	if controller.has_method("show_toast"):
		controller.show_toast(msg, false)
	GlobalData.save_run()
	controller.refresh_after_part_mutation()


# Try to spend `cost` credits; on shortfall report the need and return true so
# the caller bails out before touching part damage.
func _block_without_credits(cost: int) -> bool:
	if GlobalData.currency.try_spend_credits(cost):
		return false
	var err := "Need %d credits!" % cost
	controller.status_message_label.text = err
	if controller.has_method("show_toast"):
		controller.show_toast(err, true)
	return true
