extends Node

var salvaged_weapons: Array[WeaponPart] = []
var salvaged_ammo: Dictionary = {}


func tag_for_salvage(weapon: WeaponPart) -> void:
	if not salvaged_weapons.has(weapon):
		salvaged_weapons.append(weapon)


func untag_salvage(weapon: WeaponPart) -> void:
	salvaged_weapons.erase(weapon)


func is_tagged(weapon: WeaponPart) -> bool:
	return salvaged_weapons.has(weapon)


func salvage_all() -> void:
	# Salvaged weapons are added to the central weapon_inventory stash so they
	# can be equipped from the Hangar (via the weapon tabs). Old save files may
	# still reference equipped_parts["salvaged_weapons"]; that slot is obsolete.
	for weapon in salvaged_weapons:
		GlobalData.register_weapon(weapon.resource_path, weapon.weapon_name)
	GlobalData.save_run()
	salvaged_weapons.clear()


func get_salvaged_count() -> int:
	return salvaged_weapons.size()


func reset() -> void:
	salvaged_weapons.clear()
	salvaged_ammo.clear()


func spawn_enemy_armor_salvage(enemy_type: String, _pos: Vector3) -> void:
	var slots = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	var slot = slots[randi() % slots.size()]

	var item = {
		"name": "Enemy Armor Plate",
		"slot": slot,
		"hp": 40.0,
		"armor": 25.0,
		"weight": 7.0,
		"color": Color(0.3, 0.4, 0.3),
		"type": "Enemy Salvage"
	}

	match enemy_type:
		"rusher_simple", "ranged_simple", "rusher_full", "ranged_full":
			item["name"] = "Zaku Green " + slot.replace("_", " ").capitalize() + " Plate"
			item["color"] = Color(0.2, 0.45, 0.25)
			item["type"] = "Zaku Salvage"
		"tank_full", "heavy_full":
			item["name"] = "Heavy Tank " + slot.replace("_", " ").capitalize() + " Chobham"
			item["hp"] = 70.0
			item["armor"] = 45.0
			item["weight"] = 14.0
			item["color"] = Color(0.25, 0.25, 0.3)
			item["type"] = "Tank Salvage"
		"boss_overlord":
			item["name"] = "Crimson Ace " + slot.replace("_", " ").capitalize() + " Chrome"
			item["hp"] = 90.0
			item["armor"] = 60.0
			item["weight"] = 12.0
			item["color"] = Color(0.85, 0.1, 0.15)
			item["type"] = "Boss Ace Salvage"

	GlobalData.salvaged_armor_inventory.append(item)
