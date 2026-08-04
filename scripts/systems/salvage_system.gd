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
