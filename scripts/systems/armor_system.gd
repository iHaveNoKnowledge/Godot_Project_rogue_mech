class_name ArmorSystem
extends RefCounted

# -----------------------------------------------------------------------------
# ARMOR INSTANCE INVENTORY
# Owned armor-piece inventory logic extracted from GlobalData. Each owned armor
# piece is a unique instance (uid) with its own durability and upgrade level.
# `GlobalData.part_damage[slot]` remains the live combat damage cache of the
# currently equipped instance; instance.durability is the persistent source for
# everything sitting in the inventory (equipped included, kept in sync).
# GlobalData keeps thin facades for all existing callers.
# -----------------------------------------------------------------------------


static func ensure_default_equipped_parts() -> void:
	if not GlobalData.equipped_parts.is_empty():
		return
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		if GlobalData.armor_catalog.has(slot) and GlobalData.armor_catalog[slot].size() > 0:
			var pid = GlobalData.armor_catalog[slot][0].get("id", "")
			if pid == "":
				continue
			var inst := make_armor_instance_from_catalog(pid)
			if not inst.is_empty():
				equip_armor_instance(inst["uid"], slot)


static func get_armor_catalog_entry(part_id: String) -> Dictionary:
	return GlobalData.get_armor_catalog_entry(part_id)


static func get_frame_catalog_entry(frame_id: String) -> Dictionary:
	return GlobalData.get_frame_catalog_entry(frame_id)


static func get_frame_catalog_entry_by_name(frame_name: String) -> Dictionary:
	return GlobalData.get_frame_catalog_entry_by_name(frame_name)


static func is_catalog_armor_id(part_id: String) -> bool:
	return GlobalData.is_catalog_armor_id(part_id)


static func is_catalog_frame_id(frame_id: String) -> bool:
	return GlobalData.is_catalog_frame_id(frame_id)


static func get_armor_catalog_slot(part_id: String) -> String:
	for slot in GlobalData.armor_catalog:
		for entry in GlobalData.armor_catalog[slot]:
			if entry.get("id", "") == part_id:
				return slot
	return ""


# Creates a fresh instance from a catalog template and adds it to armor_inventory.
static func make_armor_instance_from_catalog(part_id: String) -> Dictionary:
	var entry := ArmorSystem.get_armor_catalog_entry(part_id)
	if entry.is_empty():
		return {}
	var instance := entry.duplicate(true)
	instance["uid"] = GlobalData._new_uid("a")
	instance["db_id"] = entry.get("id", "")
	instance["slot"] = get_armor_catalog_slot(part_id)
	instance["durability"] = 1.0
	instance["upgrade_level"] = 1
	instance["equipped"] = false
	GlobalData.armor_inventory.append(instance)
	return instance


static func get_armor_instance(uid: String) -> Dictionary:
	for inst in GlobalData.armor_inventory:
		if inst.get("uid", "") == uid:
			return inst
	return {}


# Extracts hp/armor/weight floats from a catalog entry (shared by cost formulas).
static func _get_armor_cost_stats(entry: Dictionary) -> Dictionary:
	return {
		"hp": GlobalData.part_stat(entry, "hp", 30.0),
		"armor": GlobalData.part_stat(entry, "armor", 15.0),
		"weight": GlobalData.part_stat(entry, "weight", 4.0)
	}


# Scrap material cost to craft a catalog armor entry (derived from its stats).
static func get_armor_scrap_cost(entry: Dictionary) -> int:
	var s := _get_armor_cost_stats(entry)
	return maxi(1, int(ceil((s.hp + s.armor * 1.5 + s.weight * 2.0) / 20.0)))


# Credit cost to craft a catalog armor entry (derived from its stats).
static func get_armor_credit_cost(entry: Dictionary) -> int:
	var s := _get_armor_cost_stats(entry)
	return maxi(1, int(ceil((s.hp + s.armor + s.weight) / 15.0)))


# True when a catalog armor entry is a gundam-tier part that must first be
# researched (its matching research project completed) before it can be crafted.
static func entry_is_blueprint_locked(entry: Dictionary) -> bool:
	if not bool(entry.get("blueprint_only", false)):
		return false
	var blueprint_id := str(entry.get("blueprint_id", ""))
	return blueprint_id == "" or not FleetSystem.is_research_completed(blueprint_id)


# Attempts to craft a fresh armor instance from the catalog, spending scrap + credits.
# Returns the new instance on success, or an empty Dictionary on any failure
# (unknown id / insufficient scrap / insufficient credits / blueprint not researched).
static func try_craft_armor_from_catalog(part_id: String) -> Dictionary:
	var entry := ArmorSystem.get_armor_catalog_entry(part_id)
	if entry.is_empty():
		return {}
	if entry_is_blueprint_locked(entry):
		return {}
	if GlobalData.scrap < get_armor_scrap_cost(entry) or GlobalData.credits < get_armor_credit_cost(entry):
		return {}
	GlobalData.scrap -= get_armor_scrap_cost(entry)
	GlobalData.credits -= get_armor_credit_cost(entry)
	return make_armor_instance_from_catalog(part_id)


# Equips an owned instance into a slot, carrying its wear into the combat cache.
static func equip_armor_instance(uid: String, slot: String) -> bool:
	var inst := get_armor_instance(uid)
	if inst.is_empty():
		return false
	unequip_armor_instance(slot)
	inst["equipped"] = true
	inst["slot"] = slot
	GlobalData.equipped_parts[slot] = inst
	var dmg := 1.0 - GlobalData.get_durability_ratio(inst)
	if dmg <= 0.0:
		GlobalData.part_damage.erase(slot)
	else:
		GlobalData.part_damage[slot] = dmg
	return true


static func unequip_armor_instance(slot: String) -> void:
	var current = GlobalData.equipped_parts.get(slot)
	if current is Dictionary and current.has("uid"):
		var inst := get_armor_instance(str(current["uid"]))
		if not inst.is_empty():
			inst["durability"] = GlobalData.get_part_durability(slot)
			inst["equipped"] = false
	GlobalData.equipped_parts[slot] = null
	GlobalData.part_damage.erase(slot)
	# NOTE: frame damage (part_damage[slot + "_frame"]) belongs to the mech's
	# frame, not the armor being swapped out — swapping armor must NOT heal it.


# Writes the live combat damage cache back into the equipped instances' durability.
static func sync_equipped_armor_durability() -> void:
	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		if part is Dictionary and part.has("uid"):
			var inst := get_armor_instance(str(part["uid"]))
			if not inst.is_empty():
				inst["durability"] = GlobalData.get_part_durability(slot)
