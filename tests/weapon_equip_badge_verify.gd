extends Node

## Verifies the per-instance weapon/armor equip badge + sort order + tier UI:
##   1. Equipping ONE copy of a model marks ONLY that copy with "[E]" — same-
##      model siblings (own uid each) never share the badge (the old bug where
##      every same-name row showed [E]).
##   2. Equipped / other-mech-taken rows sort to the BOTTOM of the list so free
##      spares read first (weapons and armor).
##   3. The upgrade tier ladder (1 -> 1.1 -> ... -> 1.4 -> 2) text/pips helpers
##      and the hangar right-side TIER box reflect the selected part's tier.
## Run: godot --headless --path . res://tests/weapon_equip_badge_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame

	await _verify_tier_ladder()
	await _verify_weapon_badge_is_per_instance()
	await _verify_weapon_sort_equipped_last()
	await _verify_armor_sort_equipped_last()
	await _verify_tier_box_ui()
	print("WEAPON_EQUIP_BADGE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# The 1 -> 1.1 -> ... -> 1.4 -> 2 ladder (four sub-steps per whole tier).
func _verify_tier_ladder() -> void:
	_check(GlobalData.part_tier_text(1) == "1", "upgrade level 1 shows tier 1")
	_check(GlobalData.part_tier_text(2) == "1.1", "upgrade level 2 shows tier 1.1")
	_check(GlobalData.part_tier_text(3) == "1.2", "upgrade level 3 shows tier 1.2")
	_check(GlobalData.part_tier_text(5) == "1.4", "upgrade level 5 shows tier 1.4")
	_check(GlobalData.part_tier_text(6) == "2", "upgrade level 6 rolls over to tier 2")
	_check(GlobalData.part_tier_text(7) == "2.1", "upgrade level 7 shows tier 2.1")
	_check(GlobalData.part_tier_pips_filled(1) == 0, "tier 1 has no pips filled")
	_check(GlobalData.part_tier_pips_filled(2) == 1, "tier 1.1 fills one pip")
	_check(GlobalData.part_tier_pips_filled(5) == 4, "tier 1.4 fills all four pips")
	_check(GlobalData.part_tier_pips_filled(6) == 0, "tier 2 restarts the pips")
	_check(GlobalData.part_tier_pips_text(1) == "○○○○", "tier 1 shows four empty pips")
	_check(GlobalData.part_tier_pips_text(3) == "●●○○", "tier 1.2 shows two filled pips")
	_check(GlobalData.get_part_upgrade_cost(1) == 50, "first upgrade costs 50 cr")
	_check(GlobalData.get_part_upgrade_cost(2) == 75, "second upgrade costs 75 cr")


# Two pile bunkers in the stash: equipping ONE must badge exactly that copy.
func _verify_weapon_badge_is_per_instance() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	ctrl.current_mode = "armor"
	ctrl.selected_slot = "weapon_left"

	var pile := "res://resources/mech/stock/weapon_pile_bunker.tres"
	LoadoutSystem.register_weapon(pile, "Pile Bunker")
	LoadoutSystem.register_weapon(pile, "Pile Bunker")
	await get_tree().process_frame
	_check(LoadoutSystem.count_owned_weapon(pile) == 2, "setup: two pile bunker copies owned")

	# Before equipping: no pile row shows [E] (the beam rifle on the left hand
	# is the only equipped weapon in this slot).
	ctrl.part_list_panel.populate("weapon_left")
	var rows_before := _weapon_row_texts(ctrl, "Pile Bunker")
	_check(rows_before.size() == 2, "both pile copies appear as separate rows")
	var eq_before := 0
	for r in rows_before:
		if r.begins_with("[E] "):
			eq_before += 1
	_check(eq_before == 0, "no pile copy shows [E] before equipping")

	# Equip ONE copy through the real equip path (passes the clicked instance).
	var inst_a: Dictionary = {}
	var inst_b: Dictionary = {}
	for entry in GlobalData.weapons.weapon_inventory:
		if str(entry.get("path", "")) == pile:
			if inst_a.is_empty():
				inst_a = entry
			else:
				inst_b = entry
	ctrl.equip_panel.equip_part("weapon_left", inst_a)
	await get_tree().process_frame
	ctrl.part_list_panel.populate("weapon_left")

	# Exactly ONE pile row shows [E], and it is the EQUIPPED copy's row.
	var rows := _weapon_row_texts(ctrl, "Pile Bunker")
	var eq_idx := -1
	for i in range(rows.size()):
		if rows[i].begins_with("[E] "):
			eq_idx = i
	_check(eq_idx >= 0, "one pile copy shows [E] after equipping")
	_check(eq_idx >= 0 and (rows.size() == 1 or rows[(eq_idx + 1) % rows.size()].begins_with("[E] ") == false), "the sibling copy does NOT show [E]")
	var equipped_uid := str(GlobalData.weapons.weapon_loadout.get("left", ""))
	_check(equipped_uid == str(inst_a.get("uid", "")), "the loadout holds the clicked copy's uid")
	_check(equipped_uid != str(inst_b.get("uid", "")), "the other copy's uid is untouched")
	# The [E] pile row (raw display index) must map to the equipped instance.
	var eq_raw := -1
	for i in range(ctrl.part_item_list.item_count):
		var text: String = ctrl.part_item_list.get_item_text(i)
		if text.begins_with("[E] ") and text.contains("Pile Bunker"):
			eq_raw = i
	_check(eq_raw >= 0, "the equipped pile row exists in the raw list")
	if eq_raw >= 0:
		var inv_idx: int = ctrl.visible_weapon_indices[eq_raw]
		var shown: Dictionary = GlobalData.weapons.weapon_inventory[inv_idx]
		_check(str(shown.get("uid", "")) == equipped_uid, "the [E] row maps to the equipped instance")

	ctrl.queue_free()
	await get_tree().process_frame


# With both copies free, equipping one must sort the equipped row to the BOTTOM.
func _verify_weapon_sort_equipped_last() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	ctrl.current_mode = "armor"
	ctrl.selected_slot = "weapon_left"
	var pile := "res://resources/mech/stock/weapon_pile_bunker.tres"
	LoadoutSystem.register_weapon(pile, "Pile Bunker")
	LoadoutSystem.register_weapon(pile, "Pile Bunker")
	await get_tree().process_frame

	var inst_a: Dictionary = {}
	for entry in GlobalData.weapons.weapon_inventory:
		if str(entry.get("path", "")) == pile:
			inst_a = entry
			break
	ctrl.equip_panel.equip_part("weapon_left", inst_a)
	await get_tree().process_frame
	ctrl.part_list_panel.populate("weapon_left")

	var rows := _weapon_row_texts(ctrl, "Pile Bunker")
	var first_eq := -1
	var last_free := -1
	for i in range(rows.size()):
		if rows[i].begins_with("[E] "):
			first_eq = i
		else:
			last_free = i
	_check(first_eq > last_free, "the equipped pile copy sorts to the BOTTOM (free spare reads first)")

	ctrl.queue_free()
	await get_tree().process_frame


# Armor: the equipped plate sorts to the bottom of its slot list.
func _verify_armor_sort_equipped_last() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	ctrl.current_mode = "armor"
	ctrl.selected_slot = "body"
	var entries: Array = GlobalData.armor_catalog.get("body", [])
	_check(not entries.is_empty(), "body armor catalog has entries")
	if entries.is_empty():
		ctrl.queue_free()
		await get_tree().process_frame
		return
	var inst1: Dictionary = ArmorSystem.make_armor_instance_from_catalog(entries[0]["id"])
	var inst2: Dictionary = ArmorSystem.make_armor_instance_from_catalog(entries[0]["id"])
	GlobalData.weapons.armor_inventory.append(inst1)
	GlobalData.weapons.armor_inventory.append(inst2)
	await get_tree().process_frame
	ctrl.equip_panel.equip_part("body", inst1)
	await get_tree().process_frame
	ctrl.part_list_panel.populate("body")

	# Both rows are the same model; the equipped one is [E] and comes LAST.
	var eq_pos := -1
	var free_pos := -1
	for i in range(ctrl.part_item_list.item_count):
		var text: String = ctrl.part_item_list.get_item_text(i)
		if text.begins_with("[E] "):
			eq_pos = i
		else:
			free_pos = i
	_check(eq_pos > free_pos, "the equipped armor plate sorts to the BOTTOM of its slot list")

	ctrl.queue_free()
	await get_tree().process_frame


# The right-side TIER box reflects the selected part's upgrade tier.
func _verify_tier_box_ui() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ctrl.tier_label != null and ctrl.tier_pips_label != null, "hangar builds the TIER box")

	# Armor instance tier: select an instance with upgrade_level 3 -> "1.2".
	ctrl.current_mode = "armor"
	ctrl.selected_slot = "body"
	var entries: Array = GlobalData.armor_catalog.get("body", [])
	if not entries.is_empty():
		var inst: Dictionary = ArmorSystem.make_armor_instance_from_catalog(entries[0]["id"])
		inst["upgrade_level"] = 3
		GlobalData.weapons.armor_inventory.append(inst)
		await get_tree().process_frame
		ctrl.part_list_panel.populate("body")
		_check(ctrl.tier_label.text == "1.2", "armor tier box shows 1.2 for upgrade level 3 (got %s)" % ctrl.tier_label.text)
		_check(ctrl.tier_pips_label.text == "●●○○", "armor tier box fills two pips")

	# Frame tier: the EQUIPPED frame copy carries the tier (catalog stays static).
	ctrl.current_mode = "frame"
	ctrl.selected_slot = "body"
	if ctrl.frame_catalog.has("body") and not (ctrl.frame_catalog["body"] as Array).is_empty():
		var frame_info: Dictionary = (ctrl.frame_catalog["body"][0] as Dictionary).duplicate()
		frame_info["upgrade_level"] = 5
		GlobalData.weapons.equipped_frames["body"] = frame_info
		ctrl.part_list_panel.populate("body")
		_check(ctrl.tier_label.text == "1.4", "frame tier box shows 1.4 for an upgraded equipped frame (got %s)" % ctrl.tier_label.text)
		_check(ctrl.tier_pips_label.text == "●●●●", "frame tier box fills all four pips")

	ctrl.queue_free()
	await get_tree().process_frame


# The display texts of every stash row for the given weapon display name.
func _weapon_row_texts(ctrl: Node, wname: String) -> Array:
	var result: Array = []
	for i in range(ctrl.part_item_list.item_count):
		var text: String = ctrl.part_item_list.get_item_text(i)
		if text.contains(wname) and text.contains("(DUR:"):
			result.append(text)
	return result
