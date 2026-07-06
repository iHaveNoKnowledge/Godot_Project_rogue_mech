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
	for weapon in salvaged_weapons:
		if GlobalData.equipped_parts.has("weapon_" + weapon.weapon_name):
			continue
	GlobalData.equipped_parts["salvaged_weapons"] = salvaged_weapons.duplicate()
	salvaged_weapons.clear()


func get_salvaged_count() -> int:
	return salvaged_weapons.size()


func reset() -> void:
	salvaged_weapons.clear()
	salvaged_ammo.clear()
