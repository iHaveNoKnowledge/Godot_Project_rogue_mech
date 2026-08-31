extends RefCounted
class_name BackpackSystem

## Backpack — Cargo / Booster / Combat (per PLAN.md)

const BACKPACKS: Dictionary = {
	"cargo": {"name": "Cargo Backpack", "capacity": 40.0, "weight": 8.0, "color": Color(0.55, 0.45, 0.25)},
	"booster": {"name": "Booster Pack", "roller_bonus": 0.3, "weight": 6.0, "color": Color(0.4, 0.9, 1.0)},
	"combat": {"name": "Combat Pack", "armor": 25.0, "weight": 10.0, "color": Color(0.45, 0.45, 0.5)},
}

static func get_backpack_def(id: String) -> Dictionary:
	return BACKPACKS.get(id, {}).duplicate(true)


static func equip(slot: String, backpack_id: String) -> bool:
	var def = get_backpack_def(backpack_id)
	if def.is_empty():
		return false
	def["id"] = backpack_id
	def["uid"] = "bp_%d" % randi()
	def["slot"] = slot
	GlobalData.weapons.attachments.append(def)
	GlobalData.save_run()
	return true
