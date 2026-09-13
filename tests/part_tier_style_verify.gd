extends Node

## Headless verification of tier-colored list borders (PartTierStyle):
##   1. Tier resolution: armor / frame / weapon / loot entries map to 0-3.
##   2. Tier colors are distinct per tier.
##   3. ItemList rows get a tinted bg + stripe icon; Buttons get a tier border.
## Run: godot --headless --path . res://tests/part_tier_style_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TIER_OK: " + name)
	else:
		_fails += 1
		printerr("TIER_FAIL: " + name)


func _ready() -> void:
	_verify_armor_tiers()
	_verify_frame_tiers()
	_verify_weapon_tiers()
	_verify_loot_tiers()
	_verify_colors_distinct()
	_verify_itemlist_styling()
	_verify_button_styling()
	await get_tree().process_frame

	print("PART_TIER_STYLE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_armor_tiers() -> void:
	_check(PartTierStyle.armor_tier({"type": "Standard Armor", "name": "Line Plate"}) == 0, "standard armor is T0")
	_check(PartTierStyle.armor_tier({"type": "Light Armor", "name": "Scout Plate"}) == 0, "light armor is T0")
	_check(PartTierStyle.armor_tier({"type": "Heavy Armor", "name": "Iron Plate"}) == 1, "heavy armor is T1")
	_check(PartTierStyle.armor_tier({"type": "Super Heavy Armor", "name": "Siege Plate"}) == 1, "super heavy armor is T1")
	_check(PartTierStyle.armor_tier({"type": "Light Plating", "name": "Strike Plate"}) == 2, "light plating is T2")
	_check(PartTierStyle.armor_tier({"type": "Wanzer Armor", "name": "Wanzer Plate"}) == 2, "wanzer armor is T2")
	_check(PartTierStyle.armor_tier({"type": "Valkyrion Armor", "name": "Valkyrion Plate"}) == 3, "valkyrion armor is T3")
	_check(PartTierStyle.armor_tier({}) == 0, "empty armor dict falls back to T0")


func _verify_frame_tiers() -> void:
	_check(PartTierStyle.frame_tier({"type": "Standard Frame"}) == 0, "standard frame is T0")
	_check(PartTierStyle.frame_tier({"type": "Heavy Frame"}) == 1, "heavy frame is T1")
	_check(PartTierStyle.frame_tier({"type": "Medium Frame"}) == 2, "medium frame is T2")
	_check(PartTierStyle.frame_tier({"type": "Valkyrion Frame"}) == 3, "valkyrion frame is T3")


func _verify_weapon_tiers() -> void:
	_check(PartTierStyle.weapon_tier({"rarity": 0}) == 0, "explicit rarity 0 stays T0")
	_check(PartTierStyle.weapon_tier({"rarity": 3}) == 3, "explicit rarity 3 stays T3")
	_check(PartTierStyle.weapon_tier({"rarity": 99}) == 3, "out-of-range rarity clamps to T3")
	_check(PartTierStyle.weapon_tier({"path": "res://resources/mech/stock/weapon_combat_knife.tres"}) == 0, "combat knife resolves to T0 via resource")
	_check(PartTierStyle.weapon_tier({"path": "res://resources/mech/stock/weapon_railgun.tres"}) == 3, "railgun resolves to T3 via resource")
	_check(PartTierStyle.weapon_tier({}) == 0, "empty weapon dict falls back to T0")


func _verify_loot_tiers() -> void:
	var railgun: WeaponPart = load("res://resources/mech/stock/weapon_railgun.tres")
	_check(PartTierStyle.loot_entry_tier({"type": "weapon", "weapon": railgun}) == 3, "railgun loot entry is T3")
	_check(PartTierStyle.loot_entry_tier({"type": "armor", "instance": {"type": "Valkyrion Armor", "name": "Plate"}}) == 3, "valkyrion loot entry is T3")
	_check(PartTierStyle.loot_entry_tier({"type": "armor", "instance": {"type": "Standard Armor", "name": "Plate"}}) == 0, "standard loot entry is T0")


func _verify_colors_distinct() -> void:
	var seen := {}
	var distinct := true
	for t in range(4):
		var c := PartTierStyle.tier_color(t)
		var key := "%d_%d_%d" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
		if seen.has(key):
			distinct = false
		seen[key] = true
	_check(distinct, "all 4 tier colors are distinct")
	_check(PartTierStyle.tier_name(0) == "COMMON" and PartTierStyle.tier_name(3) == "LEGENDARY", "tier names resolve (COMMON..LEGENDARY)")


func _verify_itemlist_styling() -> void:
	var list := ItemList.new()
	add_child(list)
	list.add_item("common row")
	list.add_item("legendary row")
	PartTierStyle.apply_itemlist_row(list, 0, 0)
	PartTierStyle.apply_itemlist_row(list, 1, 3)
	_check(list.get_item_custom_bg_color(0) == PartTierStyle.tier_bg_color(0), "T0 row gets the T0 bg tint")
	_check(list.get_item_custom_bg_color(1) == PartTierStyle.tier_bg_color(3), "T3 row gets the T3 bg tint")
	_check(list.get_item_icon(0) != null and list.get_item_icon(1) != null, "tier rows get a stripe icon (border look)")
	_check(list.get_item_icon(0) != list.get_item_icon(1), "T0 and T3 stripe icons differ")
	# Out-of-range rows are no-ops, never a crash.
	PartTierStyle.apply_itemlist_row(list, 99, 2)
	PartTierStyle.apply_itemlist_row(null, 0, 1)
	_check(true, "apply_itemlist_row ignores bad input without crashing")
	list.queue_free()


func _verify_button_styling() -> void:
	var btn := Button.new()
	add_child(btn)
	PartTierStyle.style_button(btn, 3)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal")
	_check(sb != null and sb is StyleBoxFlat, "tier button gets a StyleBoxFlat border")
	_check(sb != null and sb.border_color == PartTierStyle.tier_color(3), "T3 button border uses the T3 color")
	_check(sb != null and (sb.border_width_left >= 2 or sb.border_width_top >= 2), "tier button border is visible (>=2px)")
	btn.queue_free()
