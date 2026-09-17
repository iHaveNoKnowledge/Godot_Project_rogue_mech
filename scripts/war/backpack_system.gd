extends RefCounted
class_name BackpackSystem

## ---------------------------------------------------------------------------
## BACKPACK SYSTEM — Dedicated First-Class Equipment Category
##
## Manages external Back Unit / Backpack equipment mounted on the Mecha.
## Distinct from Frame, Armor, Modules, and Generator.
## ---------------------------------------------------------------------------

const BACKPACKS: Dictionary = {
	"cargo": {
		"id": "cargo",
		"name": "Cargo Backpack",
		"type": "cargo",
		"weight": 8.0,
		"capacity": 40.0,
		"carry_bonus": 40.0,
		"roller_bonus": 0.0,
		"armor": 0.0,
		"heat_dissipation": 1.0,
		"energy_bonus": 0.0,
		"compatibility": ["all"],
		"special_effects": {},
		"color": Color(0.55, 0.45, 0.25),
	},
	"booster": {
		"id": "booster",
		"name": "Booster Pack",
		"type": "booster",
		"weight": 6.0,
		"capacity": 0.0,
		"carry_bonus": 0.0,
		"roller_bonus": 0.3,
		"armor": 0.0,
		"heat_dissipation": 1.0,
		"energy_bonus": 0.0,
		"compatibility": ["all"],
		"special_effects": {"dash_boost": 0.3},
		"color": Color(0.4, 0.9, 1.0),
	},
	"combat": {
		"id": "combat",
		"name": "Combat Pack",
		"type": "combat",
		"weight": 10.0,
		"capacity": 0.0,
		"carry_bonus": 0.0,
		"roller_bonus": 0.0,
		"armor": 25.0,
		"heat_dissipation": 1.15,
		"energy_bonus": 0.0,
		"compatibility": ["all"],
		"special_effects": {"armor_bonus": 25.0},
		"color": Color(0.45, 0.45, 0.5),
	},
}


static func get_backpack_def(id: String) -> Dictionary:
	return BACKPACKS.get(id, {}).duplicate(true)


## Returns the currently equipped backpack dictionary (or empty dict if none).
## Seamlessly checks dedicated storage first, with fallback to legacy attachments.
static func get_equipped_backpack() -> Dictionary:
	if GlobalData == null or GlobalData.weapons == null:
		return {}
	if "equipped_backpack" in GlobalData.weapons and not GlobalData.weapons.equipped_backpack.is_empty():
		return GlobalData.weapons.equipped_backpack

	# Backward compatibility fallback: check attachments
	if "attachments" in GlobalData.weapons and GlobalData.weapons.attachments is Array:
		for att in GlobalData.weapons.attachments:
			if att is Dictionary:
				var aid := str(att.get("id", ""))
				var aslot := str(att.get("slot", ""))
				if aid in BACKPACKS or aslot == "backpack":
					return att
	return {}


## Equips a backpack by ID into the dedicated weapons.equipped_backpack slot.
## slot parameter is preserved for backwards compatibility with legacy callers.
static func equip(slot_or_id: String, backpack_id: String = "") -> bool:
	if GlobalData == null or GlobalData.weapons == null:
		return false

	var target_id := backpack_id
	var target_slot := slot_or_id
	if target_id == "" and BACKPACKS.has(slot_or_id):
		target_id = slot_or_id
		target_slot = "backpack"

	var def = get_backpack_def(target_id)
	if def.is_empty():
		return false

	def["id"] = target_id
	def["uid"] = "bp_%d_%d" % [Time.get_ticks_usec(), randi() % 99999]
	def["slot"] = target_slot

	# Dedicated storage assignment
	GlobalData.weapons.equipped_backpack = def

	# Remove any legacy backpack lingering in attachments
	if "attachments" in GlobalData.weapons and GlobalData.weapons.attachments is Array:
		var erase_indices: Array[int] = []
		for i in range(GlobalData.weapons.attachments.size()):
			var att = GlobalData.weapons.attachments[i]
			if att is Dictionary and (str(att.get("id", "")) in BACKPACKS or str(att.get("slot", "")) == "backpack"):
				erase_indices.append(i)
		erase_indices.reverse()
		for idx in erase_indices:
			GlobalData.weapons.attachments.remove_at(idx)

	GlobalData.save_run()
	return true


static func unequip() -> void:
	if GlobalData == null or GlobalData.weapons == null:
		return
	GlobalData.weapons.equipped_backpack = {}

	# Clean up any legacy backpack in attachments
	if "attachments" in GlobalData.weapons and GlobalData.weapons.attachments is Array:
		var erase_indices: Array[int] = []
		for i in range(GlobalData.weapons.attachments.size()):
			var att = GlobalData.weapons.attachments[i]
			if att is Dictionary and (str(att.get("id", "")) in BACKPACKS or str(att.get("slot", "")) == "backpack"):
				erase_indices.append(i)
		erase_indices.reverse()
		for idx in erase_indices:
			GlobalData.weapons.attachments.remove_at(idx)

	GlobalData.save_run()


static func get_backpack_weight() -> float:
	var bp := get_equipped_backpack()
	if bp.is_empty():
		return 0.0
	return float(bp.get("weight", 0.0))


static func get_backpack_carry_bonus() -> float:
	var bp := get_equipped_backpack()
	if bp.is_empty():
		return 0.0
	return float(bp.get("carry_bonus", bp.get("capacity", 0.0)))


static func get_backpack_stat(stat_key: String, default_val: Variant = 0.0) -> Variant:
	var bp := get_equipped_backpack()
	if bp.is_empty():
		return default_val
	return bp.get(stat_key, default_val)
