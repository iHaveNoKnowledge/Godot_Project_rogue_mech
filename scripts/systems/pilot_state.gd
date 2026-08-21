class_name PilotState
extends RefCounted

## ---------------------------------------------------------------------------
## PILOT STATE — the player pilot's own condition, kept separate from the mech.
##
## Extracted from GlobalData.  Owns:
##   • Pilot HP
##   • Personal weapons / ammo / items
##   • Hired pilots & permadeath history
##   • Rival / nemesis enemy pilot system
## ---------------------------------------------------------------------------

# --- Pilot HP ---
var pilot_hp: float = 100.0
var pilot_max_hp: float = 100.0

# --- Personal Weapons (WeaponPart resource paths) ---
var pilot_weapons: Array = ["res://resources/mech/stock/weapon_pilot_pistol.tres"]

# --- Personal Ammo (type -> count) ---
var pilot_ammo: Dictionary = {
	"kinetic": 120,
	"energy": 40,
	"explosive": 8,
	"missile": 3,
}

# --- Items (item_id: count) ---
var pilot_items: Dictionary = {}

# --- Hired Pilots & Permadeath ---
var hired_pilots: Array = []
var fallen_pilots: Array = []

# --- Rival / Nemesis ---
var rival_pilots: Array = []
var defeated_rivals: Array = []
var active_combat_commander: Dictionary = {}


func reset() -> void:
	pilot_hp = PilotSystem.PILOT_MAX_HP_DEFAULT
	pilot_max_hp = PilotSystem.PILOT_MAX_HP_DEFAULT
	pilot_weapons = ["res://resources/mech/stock/weapon_pilot_pistol.tres"]
	pilot_ammo = {
		"kinetic": 120,
		"energy": 40,
		"explosive": 8,
		"missile": 3,
	}
	pilot_items = {}
	hired_pilots.clear()
	fallen_pilots.clear()
	rival_pilots.clear()
	defeated_rivals.clear()
	active_combat_commander.clear()
