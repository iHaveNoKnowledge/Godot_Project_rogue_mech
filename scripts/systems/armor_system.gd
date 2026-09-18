class_name ArmorSystem
extends RefCounted

# -----------------------------------------------------------------------------
# ARMOR INSTANCE INVENTORY
# Owned armor-piece inventory logic extracted from GlobalData. Each owned armor
# piece is a unique instance (uid) with its own durability and upgrade level.
# `GlobalData.weapons.part_damage[slot]` remains the live combat damage cache of the
# currently equipped instance; instance.durability is the persistent source for
# everything sitting in the inventory (equipped included, kept in sync).
# GlobalData keeps thin facades for all existing callers.
# -----------------------------------------------------------------------------


static func ensure_default_equipped_parts() -> void:
	for slot in GlobalData.MECHA_SLOTS:
		var current = GlobalData.weapons.equipped_parts.get(slot)
		var is_valid := false
		if current is Dictionary and not current.is_empty():
			if current.has("name") and current.has("uid") and (current.has("hp") or current.has("max_hp")):
				is_valid = true
			elif current.has("uid"):
				var found = get_armor_instance(str(current["uid"]))
				if not found.is_empty() and found.has("name"):
					GlobalData.weapons.equipped_parts[slot] = found
					is_valid = true
		elif current is Resource:
			is_valid = true

		if not is_valid:
			if GlobalData.armor_catalog.has(slot) and GlobalData.armor_catalog[slot].size() > 0:
				var pid = str(GlobalData.armor_catalog[slot][0].get("id", ""))
				if pid != "":
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
	GlobalData.weapons.armor_inventory.append(instance)
	return instance


static func get_armor_instance(uid: String) -> Dictionary:
	for inst in GlobalData.weapons.armor_inventory:
		if inst.get("uid", "") == uid:
			return inst
	return {}


# Extracts hp/armor/weight floats from a catalog entry (shared by cost formulas).
static func _get_armor_cost_stats(entry: Dictionary) -> Dictionary:
	return {
		"hp": GlobalData.weapons.part_stat(entry, "hp", 30.0),
		"armor": GlobalData.weapons.part_stat(entry, "armor", 15.0),
		"weight": GlobalData.weapons.part_stat(entry, "weight", 4.0)
	}


# Scrap material cost to craft a catalog armor entry (derived from its stats).
static func get_armor_scrap_cost(entry: Dictionary) -> int:
	var s := _get_armor_cost_stats(entry)
	return maxi(1, int(ceil((s.hp + s.armor * 1.5 + s.weight * 2.0) / 20.0)))


# Credit cost to craft a catalog armor entry (derived from its stats).
static func get_armor_credit_cost(entry: Dictionary) -> int:
	var s := _get_armor_cost_stats(entry)
	return maxi(1, int(ceil((s.hp + s.armor + s.weight) / 15.0)))


# True when a catalog armor entry is a valkyrion-tier part that must first be
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
	if GlobalData.currency.scrap < get_armor_scrap_cost(entry) or GlobalData.currency.credits < get_armor_credit_cost(entry):
		return {}
	GlobalData.currency.scrap -= get_armor_scrap_cost(entry)
	GlobalData.currency.credits -= get_armor_credit_cost(entry)
	return make_armor_instance_from_catalog(part_id)


## Validates whether an armor equip request satisfies technology and physical compatibility gates.
## Delegates to LoadoutSystem's unified equipment validator.
static func validate_equip_request(slot: String, item_data: Variant, context: Dictionary = {}) -> Dictionary:
	var loadout_sys = load("res://scripts/systems/loadout_system.gd")
	if loadout_sys:
		return loadout_sys.validate_equip_request(slot, item_data, context)
	return {
		"can_equip": true,
		"allowed": true,
		"technology_allowed": true,
		"physically_compatible": true,
		"is_legacy_neutral": true,
		"reason": "ok",
		"tech_id": "",
		"state_name": "USABLE",
		"message": "Ready to equip"
	}


# Equips an owned instance into a slot, carrying its wear into the combat cache.
static func equip_armor_instance(uid: String, slot: String) -> bool:
	var inst := get_armor_instance(uid)
	if inst.is_empty():
		return false
	var validation := validate_equip_request(slot, inst)
	if not bool(validation.get("can_equip", false)):
		return false
	unequip_armor_instance(slot)
	inst["equipped"] = true
	inst["slot"] = slot
	GlobalData.weapons.equipped_parts[slot] = inst
	var dmg := 1.0 - GlobalData.get_durability_ratio(inst)
	if dmg <= 0.0:
		GlobalData.weapons.part_damage.erase(slot)
		GlobalData.weapons.part_hit_meta.erase(slot)
	else:
		GlobalData.weapons.part_damage[slot] = dmg
	return true


static func unequip_armor_instance(slot: String) -> void:
	var current = GlobalData.weapons.equipped_parts.get(slot)
	if current is Dictionary and current.has("uid"):
		var inst := get_armor_instance(str(current["uid"]))
		if not inst.is_empty():
			inst["durability"] = GlobalData.get_part_durability(slot)
			inst["equipped"] = false
	GlobalData.weapons.equipped_parts[slot] = null
	GlobalData.weapons.part_damage.erase(slot)
	GlobalData.weapons.part_hit_meta.erase(slot)
	# NOTE: frame damage (part_damage[slot + "_frame"]) belongs to the mech's
	# frame, not the armor being swapped out — swapping armor must NOT heal it.


# Writes the live combat damage cache back into the equipped instances' durability.
static func sync_equipped_armor_durability() -> void:
	for slot in GlobalData.weapons.equipped_parts:
		var part = GlobalData.weapons.equipped_parts[slot]
		if part is Dictionary and part.has("uid"):
			var inst := get_armor_instance(str(part["uid"]))
			if not inst.is_empty():
				inst["durability"] = GlobalData.get_part_durability(slot)


# Degrades an armor instance's max durability (e.g. 0.03 on armor break, 0.02 on scrap patch).
# Minimum durability floor is 0.10 (10% HP) so a part never completely vanishes unless dismantled/scrapped.
static func degrade_armor_durability(uid: String, amount: float) -> float:
	var inst := get_armor_instance(uid)
	if inst.is_empty():
		for slot in GlobalData.weapons.equipped_parts:
			var p = GlobalData.weapons.equipped_parts[slot]
			if p is Dictionary and str(p.get("uid", "")) == uid:
				inst = p
				break
	if inst.is_empty():
		return 1.0
	var cur: float = float(inst.get("durability", 1.0))
	var new_dur: float = clampf(cur - amount, 0.0, 1.0)
	inst["durability"] = new_dur
	# Also sync equipped_parts if this instance is currently equipped
	for slot in GlobalData.weapons.equipped_parts:
		var p = GlobalData.weapons.equipped_parts[slot]
		if p is Dictionary and str(p.get("uid", "")) == uid and p != inst:
			p["durability"] = new_dur
	if new_dur <= 0.0:
		for slot in GlobalData.weapons.equipped_parts:
			var p = GlobalData.weapons.equipped_parts[slot]
			if p is Dictionary and str(p.get("uid", "")) == uid:
				GlobalData.shatter_and_destroy_armor(slot)
				break
	return new_dur


static func degrade_equipped_armor(slot: String, amount: float) -> float:
	var part = GlobalData.weapons.equipped_parts.get(slot)
	if part is Dictionary:
		if part.has("uid") and str(part["uid"]) != "":
			return degrade_armor_durability(str(part["uid"]), amount)
		GlobalData.degrade_part_durability(slot, amount)
		return float(part.get("durability", 1.0))
	return 1.0


## Returns DEF / damage mitigation multiplier based on armor durability.
## Scales defense directly by durability percentage (e.g. 80% durability = 80% DEF).
static func get_durability_def_multiplier(durability: float) -> float:
	return clampf(durability, 0.10, 1.0)

