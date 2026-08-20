class_name RunStartSystem
extends RefCounted

# -----------------------------------------------------------------------------
# RANDOM RUN START
# Rolls and installs the starting loadout for a new run from the current theme's
# start config. Extracted from GlobalData so the run-state autoload stays
# focused on state; GlobalData keeps a thin roll_random_start() facade.
# -----------------------------------------------------------------------------


# Picks a weighted-random chassis key from a theme's chassis_weights.
static func roll_weighted_chassis(theme: Dictionary) -> String:
	var weights: Dictionary = theme.get("start", {}).get("chassis_weights", {})
	var total := 0
	for key in weights:
		total += int(weights[key])
	if total <= 0:
		return "standard"
	var roll := randi() % total
	for key in weights:
		roll -= int(weights[key])
		if roll < 0:
			return key
	return "standard"


# Picks a random catalog part id for an armor slot (lowest tier always exists).
static func roll_armor_part(slot: String) -> String:
	if GlobalData.armor_catalog.has(slot) and GlobalData.armor_catalog[slot].size() > 0:
		return str(GlobalData.armor_catalog[slot][0].get("id", ""))
	return ""


# Picks a frame id for a slot weighted by part_tier_weights.
# frame_catalog[slot] is ordered: [standard, gundam, medium, heavy] per slot.
static func roll_frame(slot: String, tier_weights: Dictionary) -> String:
	var entries: Array = GlobalData.frame_catalog.get(slot, [])
	if entries.is_empty():
		return ""
	var tier_order := ["standard", "gundam", "medium", "heavy"]
	var total := 0
	for tier in tier_order:
		total += int(tier_weights.get(tier, 0))
	if total <= 0:
		return str(entries[0].get("id", ""))
	var roll := randi() % total
	var index := 0
	for tier in tier_order:
		var w := int(tier_weights.get(tier, 0))
		if roll < w:
			index = tier_order.find(tier)
			break
		roll -= w
	index = clampi(index, 0, entries.size() - 1)
	return str(entries[index].get("id", ""))


# Rolls and installs a random starting loadout for the current theme.
static func roll_random_start() -> void:
	var theme = ThemeSystem.get_run_theme()
	if theme.is_empty():
		return
	var start: Dictionary = theme.get("start", {})

	# Chassis.
	GlobalData.chassis_id = roll_weighted_chassis(theme)

	# Armor + frames per slot.
	GlobalData.equipped_parts.clear()
	GlobalData.part_damage.clear()
	GlobalData.armor_inventory.clear()
	GlobalData.equipped_frames.clear()
	var tier_weights: Dictionary = start.get("part_tier_weights", {})
	for slot in GlobalData.MECHA_SLOTS:
		var armor_id := roll_armor_part(slot)
		if armor_id != "":
			var inst := ArmorSystem.make_armor_instance_from_catalog(armor_id)
			if not inst.is_empty():
				ArmorSystem.equip_armor_instance(inst["uid"], slot)
		var frame_id := roll_frame(slot, tier_weights)
		if frame_id != "":
			GlobalData.equipped_frames[slot] = ArmorSystem.get_frame_catalog_entry(frame_id)
	GlobalData._ensure_default_frames()

	# Weapons.
	var pool: Array = start.get("weapon_pool", [])
	if pool.is_empty():
		pool = [GlobalData.DEFAULT_LEFT_WEAPON_PATH, GlobalData.DEFAULT_RIGHT_WEAPON_PATH, GlobalData.DEFAULT_CARRY_WEAPON_PATH]
	var valid: Array = []
	for p in pool:
		if p is String and ResourceLoader.exists(p):
			valid.append(p)
	# A weapon model may only be equipped once (left hand, right hand, back
	# carry), so the rolled left-hand pick must stay distinct from the fixed
	# right-hand and back-carry defaults.
	var right_path := GlobalData.DEFAULT_RIGHT_WEAPON_PATH
	var carry_path := GlobalData.DEFAULT_CARRY_WEAPON_PATH
	var left_pool: Array = []
	for p in valid:
		if str(p) != right_path and str(p) != carry_path:
			left_pool.append(p)
	if left_pool.is_empty():
		left_pool = valid
	var left_path: String = left_pool[randi() % left_pool.size()] if not left_pool.is_empty() else GlobalData.DEFAULT_LEFT_WEAPON_PATH
	# Each copy is a stash INSTANCE; the loadout references the copies by uid so
	# equipping one copy never marks its same-model siblings as equipped.
	GlobalData.weapon_inventory.clear()
	var left_uid := ""
	var right_uid := ""
	var carry_uid := ""
	for path in [left_path, right_path, carry_path]:
		if path is String and path != "":
			var uid := LoadoutSystem.register_weapon(path, "Starter")
			if left_uid == "" and str(path) == left_path:
				left_uid = uid
			elif right_uid == "" and str(path) == right_path:
				right_uid = uid
			elif carry_uid == "" and str(path) == carry_path:
				carry_uid = uid
	GlobalData.weapon_loadout["left"] = left_uid
	GlobalData.weapon_loadout["right"] = right_uid
	GlobalData.weapon_loadout["carry"] = [carry_uid]

	# Allies.
	GlobalData.fleet_roster.clear()
	var allies: Dictionary = start.get("allies", {})
	var templates: Array = allies.get("templates", [])
	var min_a := int(allies.get("min", 0))
	var max_a := int(allies.get("max", min_a))
	if not templates.is_empty():
		var count := randi_range(min_a, max_a)
		var shuffled := templates.duplicate()
		shuffled.shuffle()
		for tpl in shuffled.slice(0, count):
			FleetSystem.add_ally_unit(str(tpl))

	# Resources.
	var credits_range: Array = start.get("credits", [100, 150])
	var scrap_range: Array = start.get("scrap", [0, 10])
	var cores_range: Array = start.get("data_cores", [0, 0])
	GlobalData.credits = randi_range(int(credits_range[0]), int(credits_range[1]))
	GlobalData.scrap = randi_range(int(scrap_range[0]), int(scrap_range[1]))
	GlobalData.data_cores = randi_range(int(cores_range[0]), int(cores_range[1]))
	HangarManager.ensure_roster()
	HangarManager.save_active()
