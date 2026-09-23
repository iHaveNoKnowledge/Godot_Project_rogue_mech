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
var pilot_ammo: Dictionary = AmmoSystem.STARTER_PILOT_AMMO.duplicate()

# --- Items (item_id: count) ---
var pilot_items: Dictionary = {}

# --- Hired Pilots & Permadeath ---
var hired_pilots: Array = []
var fallen_pilots: Array = []

# --- Rival / Nemesis ---
var rival_pilots: Array = []
var defeated_rivals: Array = []
var active_combat_commander: Dictionary = {}

# --- Combat Pilot Progression (Phase 2E-16A) ---
var progression: Dictionary = {
	"level": 1,
	"xp": 0,
	"skill_points": 0,
	"unlocked_skills": [],
	"specialization": ""
}


func reset() -> void:
	pilot_hp = PilotSystem.PILOT_MAX_HP_DEFAULT
	pilot_max_hp = PilotSystem.PILOT_MAX_HP_DEFAULT
	pilot_weapons = ["res://resources/mech/stock/weapon_pilot_pistol.tres"]
	pilot_ammo = AmmoSystem.STARTER_PILOT_AMMO.duplicate()
	pilot_items = {}
	hired_pilots.clear()
	fallen_pilots.clear()
	rival_pilots.clear()
	defeated_rivals.clear()
	active_combat_commander.clear()
	progression = {
		"level": 1,
		"xp": 0,
		"skill_points": 0,
		"unlocked_skills": [],
		"specialization": ""
	}
