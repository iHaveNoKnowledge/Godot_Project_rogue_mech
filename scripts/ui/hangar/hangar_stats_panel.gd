class_name HangarStatsPanel
extends RefCounted

## Total mech stats aggregation for the hangar right sidebar: sums frame/armor/
## attachment/weapon weights and HP, then repaints the weight bar and the
## total-stats label. Extracted from hangar_controller.gd.
##
## Pure read of GlobalData plus two controller-owned UI nodes (weight_bar and
## total_stats_label); call update() after any equip/unequip/craft/repair.

var controller: Node


# The pilot driving the mech currently open in the editor (the berth whose
# state is loaded into the working set), e.g. "YOU (driver)" or "(no pilot)".
# The berth->pilot lookup lives in HangarManager (shared with the badge).
func _editing_pilot_name() -> String:
	var editing_id: String = ""
	if controller and controller.has_method("get_editing_mech_id"):
		editing_id = controller.get_editing_mech_id()
	return HangarManager.get_mech_pilot_name(editing_id)


func update() -> void:
	var chassis_info = GlobalData.chassis_catalog.get(GlobalData.weapons.chassis_id, GlobalData.chassis_catalog["standard"])
	var max_weight = chassis_info["max_weight"] + LoadoutSystem.get_frame_upgrade_weight_bonus()

	var total_frame_weight = 0.0
	var total_armor_weight = 0.0
	var total_frame_hp = 0.0
	var total_armor_hp = 0.0
	var total_attachment_weight = 0.0

	for slot in GlobalData.weapons.equipped_frames:
		var f = GlobalData.weapons.equipped_frames[slot]
		var max_fhp = f.get("hp", 0.0) + LoadoutSystem.get_frame_upgrade_hp_bonus()
		total_frame_weight += f.get("weight", 0.0)
		total_frame_hp += max_fhp * (1.0 - clampf(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0), 0.0, 1.0))

	for slot in GlobalData.weapons.equipped_parts:
		var p = GlobalData.weapons.equipped_parts[slot]
		if p and p.get("weight") != null:
			total_armor_weight += p.weight
		if p and (p.get("hp") != null or p.get("max_hp") != null):
			var max_ahp = float(p.get("hp", p.get("max_hp", 0.0)))
			total_armor_hp += max_ahp * (1.0 - clampf(GlobalData.weapons.part_damage.get(slot, 0.0), 0.0, 1.0))

	for attachment in GlobalData.weapons.attachments:
		total_attachment_weight += float(attachment.get("weight", 0.0))

	var total_weapon_weight = LoadoutSystem.get_loadout_weapon_weight()
	var total_weight = total_frame_weight + total_armor_weight + total_attachment_weight + total_weapon_weight

	var field_pack_weight = LoadoutSystem.get_field_pack_weight()
	var field_pack_capacity = LoadoutSystem.get_field_pack_capacity()

	if controller.weight_bar:
		controller.weight_bar.max_value = max_weight
		controller.weight_bar.value = total_weight

	if controller.total_stats_label:
		var penalty_text := ""
		var active_penalties := PartPenaltySystem.active_penalties()
		if not active_penalties.is_empty():
			penalty_text = "\n" + "\n".join(active_penalties)

		controller.total_stats_label.text = "PILOT: %s\nFRAME LVL: %d | FRAME HP: %.0f | ARMOR HP: %.0f\nFRAME W: %.1fkg | ARMOR W: %.1fkg | ATTACH W: %.1fkg | WEAPON W: %.1fkg\nTOTAL WEIGHT: %.1f / %.1f kg\nFIELD PACK: %.1f / %.1f kg\nCREDITS: %d cr   |   SCRAP: %d%s" % [
			_editing_pilot_name(), GlobalData.weapons.frame_upgrade_level, total_frame_hp, total_armor_hp,
			total_frame_weight, total_armor_weight, total_attachment_weight, total_weapon_weight,
			total_weight, max_weight,
			field_pack_weight, field_pack_capacity,
			GlobalData.currency.credits, GlobalData.currency.scrap,
			penalty_text
		]
