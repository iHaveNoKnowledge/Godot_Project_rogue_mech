class_name WeaponInventoryState
extends RefCounted

## ---------------------------------------------------------------------------
## WEAPON INVENTORY STATE — what the player owns and what the mech carries.
##
## Extracted from GlobalData.  Owns:
##   • Weapon loadout (left / right / carry / ammo allocation)
##   • Weapon inventory (owned stash)
##   • Ammo inventory (reserve)
##   • Battle loot (drops from THIS battle)
##   • Armor inventory
##   • Battle loot
## ---------------------------------------------------------------------------

# --- Weapon Loadout ---
# "left"/"right" = instance uid; "carry" = uids on back; "ammo" = allocation.
var weapon_loadout: Dictionary = {
	"left": "w_starter_left",
	"right": "w_starter_right",
	"carry": ["w_starter_carry"],
	"ammo": {
		"kinetic": 300,
		"energy": 150,
		"explosive": 30,
		"missile": 12,
	}
}

var equipped_weapon_instances: Dictionary:
	get: return weapon_loadout
	set(val): weapon_loadout = val

# --- Weapon Inventory (owned stash) ---
var weapon_inventory: Array = [
	{"uid": "w_starter_left", "path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "durability": 1.0, "upgrade_level": 1},
	{"uid": "w_starter_right", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "durability": 1.0, "upgrade_level": 1},
	{"uid": "w_starter_carry", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "durability": 1.0, "upgrade_level": 1},
]

var inventory: Array:
	get: return weapon_inventory
	set(val): weapon_inventory = val

# --- Ammo Inventory (reserve, replenished between battles) ---
var ammo_inventory: Dictionary = {
	"kinetic": 300,
	"energy": 150,
	"explosive": 30,
	"missile": 12,
}

# --- Battle Loot (drops from THIS battle) ---
var battle_loot: Array = []

# --- Armor Inventory ---
var armor_inventory: Array = []

# --- Loadout Accessories ---
var chassis_id: String = "standard"
var power_core_id: String = "combustion"  # GDD §4.3: combustion / hybrid / ancient
var equipped_parts: Dictionary = {}
var equipped_frames: Dictionary = {}
var attachments: Array = []
var part_damage: Dictionary = {}
var frame_upgrade_level: int = 1

const FRAME_UPGRADE_HP_BONUS: float = 25.0
const FRAME_UPGRADE_WEIGHT_BONUS: float = 15.0
const FRAME_UPGRADE_BASE_COST: int = 150

# --- Scrap Patches ---
var scrap_patches: Dictionary = {}

# --- Frame Bindings (GDD §6.2) ---
# Composite cloth wraps around exposed inner frame after repair.
var frame_bindings: Dictionary = {}

# --- Impact-localized damage (per-slot hit origin for crack shader) ---
# slot -> {"pos": Vector3, "radius": float}  radius 0 = no hit (uniform fallback)
var part_hit_meta: Dictionary = {}

const DEFAULT_LEFT_WEAPON_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const DEFAULT_RIGHT_WEAPON_PATH := "res://resources/mech/stock/weapon_heat_blade.tres"
const DEFAULT_CARRY_WEAPON_PATH := "res://resources/mech/stock/weapon_combat_shotgun.tres"


func reset() -> void:
	chassis_id = "standard"
	power_core_id = "combustion"
	equipped_parts.clear()
	equipped_frames.clear()
	attachments.clear()
	part_damage.clear()
	frame_upgrade_level = 1
	scrap_patches.clear()
	frame_bindings.clear()
	part_hit_meta.clear()
	weapon_loadout = {
		"left": "w_starter_left",
		"right": "w_starter_right",
		"carry": ["w_starter_carry"],
		"ammo": {
			"kinetic": 300,
			"energy": 150,
			"explosive": 30,
			"missile": 12,
		}
	}
	ammo_inventory = {
		"kinetic": 300,
		"energy": 150,
		"explosive": 30,
		"missile": 12,
	}
	weapon_inventory = [
		{"uid": "w_starter_left", "path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "durability": 1.0, "upgrade_level": 1},
		{"uid": "w_starter_right", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "durability": 1.0, "upgrade_level": 1},
		{"uid": "w_starter_carry", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "durability": 1.0, "upgrade_level": 1},
	]
	armor_inventory.clear()
	battle_loot.clear()
	ArmorSystem.ensure_default_equipped_parts()
	_ensure_default_frames()


func _ensure_default_frames() -> void:
	for slot in GlobalData.MECHA_SLOTS:
		var f = equipped_frames.get(slot)
		var is_valid := false
		if f is Dictionary and not f.is_empty() and f.has("name"):
			is_valid = true
		if not is_valid:
			if GlobalData.frame_catalog.has(slot) and GlobalData.frame_catalog[slot].size() > 0:
				equipped_frames[slot] = GlobalData.frame_catalog[slot][0].duplicate(true)


func clear_working_set() -> void:
	for slot in equipped_parts:
		var part = equipped_parts[slot]
		if part is Dictionary:
			part["equipped"] = false
	equipped_parts.clear()
	equipped_frames.clear()
	attachments.clear()
	part_damage.clear()
	part_hit_meta.clear()
	chassis_id = "standard"


func part_stat(part: Variant, key: String, default: float = 0.0) -> float:
	return GlobalData.part_stat(part, key, default)
