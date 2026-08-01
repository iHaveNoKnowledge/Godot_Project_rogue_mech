extends Node

var chassis_id: String = "standard"
var equipped_parts: Dictionary = {}
var equipped_frames: Dictionary = {
	"head": {"name": "Standard Light Alloy Frame", "hp": 20.0, "weight": 2.0},
	"body": {"name": "Standard Core Structure", "hp": 40.0, "weight": 6.0},
	"arm_left": {"name": "Standard Articulated Arm Frame", "hp": 15.0, "weight": 3.0},
	"arm_right": {"name": "Standard Articulated Arm Frame", "hp": 15.0, "weight": 3.0},
	"leg_left": {"name": "Standard Actuator Leg Frame", "hp": 20.0, "weight": 4.0},
	"leg_right": {"name": "Standard Actuator Leg Frame", "hp": 20.0, "weight": 4.0}
}
var frame_upgrade_level: int = 1
var salvaged_armor_inventory: Array = [
	{"name": "Zaku Military Green Arm Guard", "slot": "arm_left", "hp": 35.0, "armor": 22.0, "weight": 5.5, "color": Color(0.2, 0.45, 0.25), "type": "Zaku Salvage"},
	{"name": "Zaku Military Green Chest Plate", "slot": "body", "hp": 75.0, "armor": 45.0, "weight": 16.0, "color": Color(0.2, 0.45, 0.25), "type": "Zaku Salvage"},
	{"name": "Heavy Tank Chobham Shield (R)", "slot": "arm_right", "hp": 55.0, "armor": 40.0, "weight": 12.0, "color": Color(0.25, 0.25, 0.3), "type": "Tank Salvage"},
	{"name": "Crimson Ace Visor Helmet", "slot": "head", "hp": 40.0, "armor": 30.0, "weight": 4.0, "color": Color(0.85, 0.1, 0.15), "type": "Ace Salvage"}
]
var part_damage: Dictionary = {}

var chassis_catalog: Dictionary = {
	"standard": {
		"name": "ZENISREV-01 (Standard Scout)",
		"speed": 7.0,
		"max_weight": 75.0,
		"color": Color(0.6, 0.65, 0.7)
	},
	"titan": {
		"name": "TITAN OVERLORD-X (Heavy Siege)",
		"speed": 4.5,
		"max_weight": 110.0,
		"color": Color(0.3, 0.15, 0.35)
	},
	"vanguard": {
		"name": "VANGUARD STRIKER-09 (High-Mobility Recon)",
		"speed": 10.5,
		"max_weight": 55.0,
		"color": Color(0.85, 0.85, 0.9)
	},
	"aegis": {
		"name": "AEGIS FORTRESS-04 (Heavy Defense Barrier)",
		"speed": 5.5,
		"max_weight": 95.0,
		"color": Color(0.2, 0.4, 0.5)
	},
	"brawler": {
		"name": "BERSERKER BRAWLER-X (Close Combat Specialist)",
		"speed": 8.0,
		"max_weight": 88.0,
		"color": Color(0.35, 0.40, 0.28)
	}
}

var board_grid: Array = []
var current_tile: Vector2i = Vector2i.ZERO
var heat: int = 0
var wanted_level: int = 0
var safehouse_upgrades: Array = []

var credits: int = 0
var spare_parts: int = 0
var data_cores: int = 0

var current_sector: int = 1
var max_sectors: int = 3

var enemy_forces: Dictionary = {
	"boss_current": 1, "boss_max": 1,
	"ace_current": 1, "ace_max": 2,
	"grunt_current": 10, "grunt_max": 20
}

var last_combat_squad_size: int = 1
var max_notoriety_multiplier: float = 1.0
var stalking_aces: Array[String] = []
var stalking_chance: float = 0.0

var ammo_inventory: Dictionary = {
	"kinetic": 300,
	"energy": 150,
	"explosive": 30,
	"missile": 12
}

var weapon_inventory: Array = [
	{"path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "slot": "left_hand", "count": 1},
	{"path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "slot": "right_hand", "count": 1},
	{"path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "slot": "carry", "count": 1}
]

const SAVE_PATH := "user://savegame.json"


func get_reserve_ammo(ammo_type: String) -> int:
	return ammo_inventory.get(ammo_type.to_lower(), 0)


func add_reserve_ammo(ammo_type: String, amount: int) -> void:
	var type = ammo_type.to_lower()
	ammo_inventory[type] = ammo_inventory.get(type, 0) + amount


func consume_reserve_ammo(ammo_type: String, amount: int) -> int:
	var type = ammo_type.to_lower()
	var current = get_reserve_ammo(type)
	var taken = mini(current, amount)
	ammo_inventory[type] = current - taken
	return taken


func register_weapon(path: String, weapon_name: String, slot: String = "stored") -> void:
	for entry in weapon_inventory:
		if entry.get("path", "") == path:
			entry["count"] = entry.get("count", 1) + 1
			return
	weapon_inventory.append({
		"path": path,
		"name": weapon_name,
		"slot": slot,
		"count": 1
	})


func reset_run_data() -> void:
	equipped_parts.clear()
	part_damage.clear()
	board_grid.clear()
	current_tile = Vector2i.ZERO
	heat = 0
	wanted_level = 0
	safehouse_upgrades.clear()
	credits = 100
	spare_parts = 10
	data_cores = 0
	current_sector = 1
	enemy_forces = {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}
	last_combat_squad_size = 1
	max_notoriety_multiplier = 1.0
	stalking_aces.clear()
	stalking_chance = 0.0

	ammo_inventory = {
		"kinetic": 300,
		"energy": 150,
		"explosive": 30,
		"missile": 12
	}
	weapon_inventory = [
		{"path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "slot": "left_hand", "count": 1},
		{"path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "slot": "right_hand", "count": 1},
		{"path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "slot": "carry", "count": 1}
	]


func save_run() -> void:
	var data := {
		"chassis": chassis_id,
		"parts": _serialize_parts(),
		"damage": part_damage.duplicate(),
		"position": {"x": current_tile.x, "y": current_tile.y},
		"heat": heat,
		"wanted": wanted_level,
		"credits": credits,
		"spare_parts": spare_parts,
		"data_cores": data_cores,
		"sector": current_sector,
		"enemy_forces": enemy_forces.duplicate(),
		"last_combat_squad_size": last_combat_squad_size,
		"max_notoriety_multiplier": max_notoriety_multiplier,
		"stalking_aces": stalking_aces,
		"stalking_chance": stalking_chance,
		"ammo_inventory": ammo_inventory.duplicate(),
		"weapon_inventory": weapon_inventory.duplicate()
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_run() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		return false
	_restore_from_dict(data)
	return true


func _restore_from_dict(data: Dictionary) -> void:
	chassis_id = data.get("chassis", "standard")
	part_damage = data.get("damage", {})
	heat = data.get("heat", 0)
	wanted_level = data.get("wanted", 0)
	credits = data.get("credits", 0)
	spare_parts = data.get("spare_parts", 0)
	data_cores = data.get("data_cores", 0)
	current_sector = data.get("sector", 1)
	
	var pos = data.get("position", {"x": 0, "y": 0})
	current_tile = Vector2i(pos.x, pos.y)
	var parts_dict: Dictionary = data.get("parts", {})
	equipped_parts.clear()
	for slot in parts_dict:
		var p_val = parts_dict[slot]
		if p_val is String and ResourceLoader.exists(p_val):
			equipped_parts[slot] = load(p_val)
		else:
			equipped_parts[slot] = p_val
		
	enemy_forces = data.get("enemy_forces", {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}).duplicate()
	last_combat_squad_size = data.get("last_combat_squad_size", 1)
	max_notoriety_multiplier = data.get("max_notoriety_multiplier", 1.0)
	
	stalking_aces.clear()
	var loaded_aces = data.get("stalking_aces", [])
	if loaded_aces is Array:
		stalking_aces.assign(loaded_aces)
		
	stalking_chance = data.get("stalking_chance", 0.0)

	var loaded_ammo = data.get("ammo_inventory", {})
	if loaded_ammo is Dictionary and not loaded_ammo.is_empty():
		ammo_inventory = loaded_ammo.duplicate()

	var loaded_weapons = data.get("weapon_inventory", [])
	if loaded_weapons is Array and not loaded_weapons.is_empty():
		weapon_inventory = loaded_weapons.duplicate()


func _serialize_parts() -> Dictionary:
	var result := {}
	for slot in equipped_parts:
		var item = equipped_parts[slot]
		if item is Resource and "resource_path" in item and item.resource_path != "":
			result[slot] = item.resource_path
		elif item is Dictionary:
			result[slot] = item.get("path", item.get("name", "Custom Armor"))
		else:
			result[slot] = str(item)
	return result
