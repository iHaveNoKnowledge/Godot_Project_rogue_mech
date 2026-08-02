extends Node

var chassis_id: String = "standard"
var equipped_parts: Dictionary = {}
var attachments: Array = []

# ==============================================================================
# ARMOR CATALOG — Single source of truth for all stock armor parts.
# hangar_controller.gd reads this instead of duplicating the data.
# key: slot_name -> Array of armor info Dictionaries
# Each entry: {id, name, path, hp, armor, weight, color, type}
# ==============================================================================
var armor_catalog: Dictionary = {
	"head": [
		{"id": "head_001", "name": "Barbatos White Visor Plating", "path": "res://resources/mech/stock/head_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 4.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"},
		{"id": "head_002", "name": "Vanguard Light Recon Helmet",  "path": "res://resources/mech/stock/head_standard.tres",    "hp": 20.0, "armor": 12.0, "weight": 2.0, "color": Color(0.8, 0.85, 0.9), "type": "Light Plating"}
	],
	"body": [
		{"id": "body_001", "name": "Barbatos Chest Armor Plate",        "path": "res://resources/mech/stock/torso_standard.tres", "hp": 60.0,  "armor": 40.0, "weight": 14.0, "color": Color(0.9, 0.9, 0.95),    "type": "Standard Armor"},
		{"id": "body_002", "name": "Fortress Heavy Reactive Chestplate", "path": "res://resources/mech/stock/torso_standard.tres", "hp": 110.0, "armor": 75.0, "weight": 24.0, "color": Color(0.25, 0.2, 0.35), "type": "Heavy Armor"}
	],
	"arm_left": [
		{"id": "arm_left_001", "name": "Barbatos Left Shoulder Guard", "path": "res://resources/mech/stock/arm_left_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 6.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"arm_right": [
		{"id": "arm_right_001", "name": "Barbatos Right Shoulder Guard", "path": "res://resources/mech/stock/arm_right_standard.tres", "hp": 25.0, "armor": 15.0, "weight": 6.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"leg_left": [
		{"id": "leg_left_001", "name": "Barbatos Left Leg Armor Guard", "path": "res://resources/mech/stock/leg_left_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 8.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"leg_right": [
		{"id": "leg_right_001", "name": "Barbatos Right Leg Armor Guard", "path": "res://resources/mech/stock/leg_right_standard.tres", "hp": 30.0, "armor": 20.0, "weight": 8.0, "color": Color(0.9, 0.9, 0.95), "type": "Standard Armor"}
	],
	"weapon_right": [
		{"id": "wep_r_001", "name": "Beam Carbine",     "path": "res://resources/mech/stock/weapon_beam_carbine.tres",      "hp": 0.0, "armor": 0.0, "weight": 7.0, "type": "Beam Weapon"},
		{"id": "wep_r_002", "name": "Heavy Machine Gun","path": "res://resources/mech/stock/weapon_heavy_machine_gun.tres", "hp": 0.0, "armor": 0.0, "weight": 9.0, "type": "Kinetic Weapon"},
		{"id": "wep_r_003", "name": "Combat Shotgun",   "path": "res://resources/mech/stock/weapon_combat_shotgun.tres",   "hp": 0.0, "armor": 0.0, "weight": 8.0, "type": "Shotgun"}
	],
	"weapon_left": [
		{"id": "wep_l_001", "name": "Heat Blade",  "path": "res://resources/mech/stock/weapon_heat_blade.tres",  "hp": 0.0, "armor": 0.0, "weight": 5.0,  "type": "Melee Weapon"},
		{"id": "wep_l_002", "name": "Pile Bunker",  "path": "res://resources/mech/stock/weapon_pile_bunker.tres", "hp": 0.0, "armor": 0.0, "weight": 11.0, "type": "Melee Weapon"}
	]
}


func _ready() -> void:
	ensure_default_equipped_parts()


# Initialise equipped_parts from armor_catalog[slot][0] (first/default entry per slot).
# Uses armor_catalog as single source of truth — no duplicated data.
func ensure_default_equipped_parts() -> void:
	if not equipped_parts.is_empty():
		return
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		if armor_catalog.has(slot) and armor_catalog[slot].size() > 0:
			var starter_part = armor_catalog[slot][0].duplicate()
			starter_part["equipped"] = true
			equipped_parts[slot] = starter_part


# Default stock weapons that the player starts with on each hand / on the back.
const DEFAULT_LEFT_WEAPON_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const DEFAULT_RIGHT_WEAPON_PATH := "res://resources/mech/stock/weapon_heat_blade.tres"
const DEFAULT_CARRY_WEAPON_PATH := "res://resources/mech/stock/weapon_combat_shotgun.tres"

# -----------------------------------------------------------------------------
# WEAPON LOADOUT — central state for what the mech carries into battle.
# "left"/"right" are the hand weapons (resource path, "" = unarmed hand).
# "carry" is the array of weapon paths the mech carries on its back.
# "ammo" is how much ammo of each type the player allocates to bring into battle.
# Configured in the Hangar, read by WeaponManager at battle start.
# -----------------------------------------------------------------------------
var weapon_loadout: Dictionary = {
	"left": DEFAULT_LEFT_WEAPON_PATH,
	"right": DEFAULT_RIGHT_WEAPON_PATH,
	"carry": [DEFAULT_CARRY_WEAPON_PATH],
	"ammo": {
		"kinetic": 300,
		"energy": 150,
		"explosive": 30,
		"missile": 12
	}
}


# Returns the equipped WeaponPart for the given hand ("left"/"right").
# Reads the central weapon_loadout so the Hangar and battle share one source.
# An explicitly-unarmed hand ("") returns null; only a missing/blank slot falls
# back to the default stock weapon for that hand.
func get_equipped_weapon(side: String) -> WeaponPart:
	var path := str(weapon_loadout.get("left", "") if side == "left" else weapon_loadout.get("right", ""))
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		path = DEFAULT_LEFT_WEAPON_PATH if side == "left" else DEFAULT_RIGHT_WEAPON_PATH
	if ResourceLoader.exists(path):
		return load(path)
	return null


# Returns the WeaponParts the mech carries on its back into battle (from loadout).
func get_carry_weapons() -> Array[WeaponPart]:
	var result: Array[WeaponPart] = []
	var carry_paths = weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return result
	for path in carry_paths:
		if path is String and path != "" and ResourceLoader.exists(path):
			result.append(load(path))
	return result


# Total weight of all loadout weapons (both hands + back).
func get_loadout_weapon_weight() -> float:
	var total := 0.0
	var left = get_equipped_weapon("left")
	if left:
		total += float(left.weight)
	var right = get_equipped_weapon("right")
	if right:
		total += float(right.weight)
	for w in get_carry_weapons():
		total += float(w.weight)
	return total


# Assigns a weapon resource path to a hand. Empty path = unarmed hand.
func set_hand_weapon(side: String, path: String) -> void:
	if side == "left":
		weapon_loadout["left"] = path
	else:
		weapon_loadout["right"] = path


func is_weapon_in_carry(path: String) -> bool:
	var carry_paths = weapon_loadout.get("carry", [])
	return carry_paths is Array and path in carry_paths


func add_carry_weapon(path: String) -> void:
	var carry_paths = weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		carry_paths = []
	if path not in carry_paths:
		carry_paths.append(path)
	weapon_loadout["carry"] = carry_paths


func remove_carry_weapon(path: String) -> void:
	var carry_paths = weapon_loadout.get("carry", [])
	if carry_paths is Array:
		carry_paths.erase(path)
	weapon_loadout["carry"] = carry_paths


# Returns how much ammo of the given type the player carries into the next battle.
func get_loadout_ammo(ammo_type: String) -> int:
	var ammo = weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return 0
	return ammo.get(ammo_type.to_lower(), 0)


# Sets how much ammo of the given type the player carries into the next battle.
func set_loadout_ammo(ammo_type: String, amount: int) -> void:
	var ammo = weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		ammo = {}
	ammo[ammo_type.to_lower()] = max(0, amount)
	weapon_loadout["ammo"] = ammo


func get_loadout_ammo_dict() -> Dictionary:
	var ammo = weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return {}
	return ammo.duplicate()


func get_equipped_part_id(slot: String) -> String:
	var part = equipped_parts.get(slot)
	if part == null:
		return ""
	if part is Dictionary:
		var pid = part.get("id", "")
		if pid != "":
			return pid
		return part.get("name", part.get("path", ""))
	if part is Resource:
		if "id" in part and part.id != "":
			return part.id
		if "part_name" in part and part.part_name != "":
			return part.part_name
		return part.resource_path
	return ""


# Returns the chassis stats dict for the currently selected chassis_id.
# Used by mecha_controller at combat start so it doesn't rely on @export chassis resource.
# Keys: "speed" (float), "max_weight" (float), "color" (Color), "name" (String)
func get_chassis_stats() -> Dictionary:
	var result: Dictionary = chassis_catalog.get(chassis_id, chassis_catalog.get("standard", {
		"name": "Standard", "speed": 14.0, "max_weight": 75.0, "color": Color(0.6, 0.65, 0.7)
	})).duplicate(true)
	if not result.has("attachment_capacity"):
		var capacity := float(result.get("max_weight", 75.0))
		result["attachment_capacity"] = {"head": capacity * 0.10, "body": capacity * 0.35, "arm_left": capacity * 0.14, "arm_right": capacity * 0.14, "leg_left": capacity * 0.16, "leg_right": capacity * 0.16}
	result["movement_type"] = {"standard": "biped", "titan": "heavy", "vanguard": "light", "aegis": "hover", "brawler": "brawler"}.get(chassis_id, "biped")
	result["water_traversal"] = result["movement_type"] == "hover"
	return result


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
		"speed": 14.0,
		"max_weight": 75.0,
		"color": Color(0.6, 0.65, 0.7)
	},
	"titan": {
		"name": "TITAN OVERLORD-X (Heavy Siege)",
		"speed": 10.5,
		"max_weight": 110.0,
		"color": Color(0.3, 0.15, 0.35)
	},
	"vanguard": {
		"name": "VANGUARD STRIKER-09 (High-Mobility Recon)",
		"speed": 18.0,
		"max_weight": 55.0,
		"color": Color(0.85, 0.85, 0.9)
	},
	"aegis": {
		"name": "AEGIS FORTRESS-04 (Heavy Defense Barrier)",
		"speed": 11.5,
		"max_weight": 95.0,
		"color": Color(0.2, 0.4, 0.5)
	},
	"brawler": {
		"name": "BERSERKER BRAWLER-X (Close Combat Specialist)",
		"speed": 15.0,
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
	{"path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "count": 1},
	{"path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "count": 1},
	{"path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "count": 1}
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


func register_weapon(path: String, weapon_name: String) -> void:
	for entry in weapon_inventory:
		if entry.get("path", "") == path:
			entry["count"] = entry.get("count", 1) + 1
			return
	weapon_inventory.append({
		"path": path,
		"name": weapon_name,
		"count": 1
	})


func reset_run_data() -> void:
	equipped_parts.clear()
	part_damage.clear()
	attachments.clear()
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
		{"path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "count": 1},
		{"path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "count": 1},
		{"path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "count": 1}
	]
	weapon_loadout = {
		"left": DEFAULT_LEFT_WEAPON_PATH,
		"right": DEFAULT_RIGHT_WEAPON_PATH,
		"carry": [DEFAULT_CARRY_WEAPON_PATH],
		"ammo": {
			"kinetic": 300,
			"energy": 150,
			"explosive": 30,
			"missile": 12
		}
	}


func save_run() -> void:
	var data := {
		"chassis": chassis_id,
		"parts": _serialize_parts(),
		"frames": equipped_frames.duplicate(true),
		"damage": part_damage.duplicate(),
		"attachments": _serialize_attachments(),
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
		"weapon_inventory": weapon_inventory.duplicate(),
		"weapon_loadout": weapon_loadout.duplicate(true)
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
	var frames_data = data.get("frames", {})
	if frames_data is Dictionary and not frames_data.is_empty():
		for slot in frames_data:
			equipped_frames[slot] = frames_data[slot]
	part_damage = data.get("damage", {})
	attachments = data.get("attachments", []).duplicate(true)
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

	var loaded_loadout = data.get("weapon_loadout", null)
	if loaded_loadout is Dictionary and not loaded_loadout.is_empty():
		weapon_loadout = loaded_loadout.duplicate(true)
		# Older saves predate the "ammo" loadout key — default to the stash.
		if not weapon_loadout.has("ammo"):
			weapon_loadout["ammo"] = {
				"kinetic": get_reserve_ammo("kinetic"),
				"energy": get_reserve_ammo("energy"),
				"explosive": get_reserve_ammo("explosive"),
				"missile": get_reserve_ammo("missile")
			}


func _serialize_parts() -> Dictionary:
	var result := {}
	for slot in equipped_parts:
		var item = equipped_parts[slot]
		if item is Resource and "resource_path" in item and item.resource_path != "":
			# Resource file: save path string for reload
			result[slot] = item.resource_path
		elif item is Dictionary:
			# Dictionary (from armor_catalog or equip action): save full dict to
			# preserve all fields including the "equipped" flag
			result[slot] = item.duplicate()
		else:
			result[slot] = str(item)
	return result


func _serialize_attachments() -> Array:
	var result: Array = []
	for attachment in attachments:
		var copy: Dictionary = attachment.duplicate(true)
		for key in ["position", "rotation", "scale", "size"]:
			if copy.get(key) is Vector3:
				var value: Vector3 = copy[key]
				copy[key] = {"x": value.x, "y": value.y, "z": value.z}
		result.append(copy)
	return result
