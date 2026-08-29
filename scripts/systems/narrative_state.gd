class_name NarrativeState
extends RefCounted

## ---------------------------------------------------------------------------
## NARRATIVE STATE — run identity, pilot-mech bond, and faction escalation.
##
## Extracted from GlobalData.  Owns:
##   • Run theme (soldier / gundam_merc / scavenger)
##   • Reputation
##   • Pilot-mech bond + sacrifice / grand entry events
##   • Enemy tech escalation
##   • Enemy research & base lifecycle
##   • Fleet security & driver repair skill
##   • Enemy forces pool
##   • Stalking aces
##   • Mechanic-less retreat flag
## ---------------------------------------------------------------------------

# --- Run Theme ---
var theme_id: String = "soldier"
var reputation: int = 0
var theme_switched: bool = false
var ceasefire_turns: int = 0
var blocked_intermission: bool = false

# --- Pilot-Only Mode ---
var mech_less: bool = false

# --- Narrative Bond (GDD §5) ---
var mech_bond: float = 0.0
var mech_battles_survived: int = 0
var mech_repairs_done: int = 0
var mech_near_death_escapes: int = 0
var sacrifice_event_available: bool = false
var sacrifice_event_triggered: bool = false
var grand_entry_mech_id: String = ""
var grand_entry_pending: bool = false

# --- Enemy Tech Escalation (legacy, kept for compat) ---
var enemy_tech_tier: int = 1
var pending_escalation_event: bool = false

# --- Faction Tech Tiers (Federation / Zeon / Outland) ---
var federation_tier: int = 1
var zeon_tier: int = 1
# Research per faction
var federation_research_active: bool = false
var federation_research_progress: float = 0.0
var federation_research_required: float = 2.5
var federation_research_start_day: float = 0.0
var federation_research_reason: String = ""
var zeon_research_active: bool = false
var zeon_research_progress: float = 0.0
var zeon_research_required: float = 2.5
var zeon_research_start_day: float = 0.0
var zeon_research_reason: String = ""
var enemy_losses: int = 0

# --- Enemy Research Node Lifecycle ---
var enemy_research_progress: float = 0.0
var enemy_base_active: bool = false
var enemy_base_progress: float = 0.0
var enemy_base_required: float = 6.0
var enemy_base_tile_pos: Vector2i = Vector2i(-1, -1)
var enemy_grunt_upgrade_level: int = 0
var enemy_copy_outcome: String = ""
var enemy_special_units: Array = []
var pending_enemy_base_spawn: bool = false
var pending_enemy_base_outcome: bool = false
var pending_enemy_base_destroyed: bool = false
var pending_enemy_base_tile_reset: Vector2i = Vector2i(-1, -1)

# --- Enemy Forces Pool ---
var enemy_forces: Dictionary = {
	"boss_current": 1, "boss_max": 1,
	"ace_current": 1, "ace_max": 2,
	"grunt_current": 10, "grunt_max": 20,
}
var last_combat_squad_size: int = 1
var max_notoriety_multiplier: float = 1.0

# --- Stalking Aces ---
var stalking_aces: Array[String] = []
var stalking_chance: float = 0.0

# --- Fleet Security ---
var fleet_security: float = 25.0
var security_upgrade_level: int = 1
const FLEET_SECURITY_MIN := 0.0
const FLEET_SECURITY_MAX := 100.0
const SECURITY_PER_UPGRADE := 14.0
const SECURITY_UPGRADE_BASE_COST := 35

# --- Driver Repair Skill ---
var driver_repair_skill: int = 1
var driver_repair_xp: int = 0
const REPAIR_SKILL_MAX := 5
const REPAIR_XP_BASE := 30
const REPAIR_XP_PER_LEVEL := 25


func increase_bond(amount: float) -> void:
	mech_bond = minf(mech_bond + amount, 100.0)


func record_battle_survived(part_damage: Dictionary) -> void:
	mech_battles_survived += 1
	var damage_taken := 0.0
	for slot in part_damage:
		damage_taken += float(part_damage[slot])
	var damage_bonus := clampf(damage_taken * 20.0, 0.0, 15.0)
	increase_bond(5.0 + damage_bonus)


func record_repair() -> void:
	mech_repairs_done += 1
	increase_bond(3.0)


func record_near_death_escape() -> void:
	mech_near_death_escapes += 1
	increase_bond(10.0)


## Re-evaluates whether the Sacrifice Event can be offered: requires a strong
## pilot-mech bond (>= 80) AND a heavily damaged machine (total damage >= 200%).
## Returns true only when availability JUST flipped on this call, so callers
## can announce the unlock exactly once.
func check_sacrifice_availability(part_damage: Dictionary) -> bool:
	if sacrifice_event_triggered:
		return false
	var total_damage := 0.0
	for slot in part_damage:
		total_damage += float(part_damage[slot])
	var now_available := (mech_bond >= 80.0 and total_damage >= 2.0)
	var newly_available := now_available and not sacrifice_event_available
	sacrifice_event_available = now_available
	return newly_available


func trigger_sacrifice_event(new_mech_id: String) -> void:
	sacrifice_event_triggered = true
	sacrifice_event_available = false
	# NOTE: grand_entry_pending is deliberately NOT armed here. It is set only
	# when the mech actually falls during the sacrifice mission — otherwise a
	# VICTORY would also complete the Grand Entry and hand over the reward mech.
	if str(new_mech_id) != "":
		grand_entry_mech_id = new_mech_id


func has_pilot_perk(perk_id: String, hired_pilots: Array = [], recruited_characters: Array = []) -> bool:
	var pilots: Array = hired_pilots if not hired_pilots.is_empty() else (GlobalData.pilot.hired_pilots if (GlobalData != null and GlobalData.pilot != null) else [])
	var recruits: Array = recruited_characters if not recruited_characters.is_empty() else (GlobalData.hangar.recruited_characters if (GlobalData != null and GlobalData.hangar != null) else [])
	for pilot in pilots:
		if pilot is Dictionary and str(pilot.get("perk_id", "")) == perk_id:
			return true
	for cid in recruits:
		if cid == "vagrant_ace" and perk_id == "precognitive_flow":
			return true
	return false


func reset() -> void:
	theme_id = "soldier"
	reputation = 0
	theme_switched = false
	ceasefire_turns = 0
	blocked_intermission = false
	mech_less = false
	mech_bond = 0.0
	mech_battles_survived = 0
	mech_repairs_done = 0
	mech_near_death_escapes = 0
	sacrifice_event_available = false
	sacrifice_event_triggered = false
	grand_entry_mech_id = ""
	grand_entry_pending = false
	enemy_tech_tier = 1
	pending_escalation_event = false
	federation_tier = 1
	zeon_tier = 1
	federation_research_active = false
	federation_research_progress = 0.0
	federation_research_required = 2.5
	federation_research_start_day = 0.0
	federation_research_reason = ""
	zeon_research_active = false
	zeon_research_progress = 0.0
	zeon_research_required = 2.5
	zeon_research_start_day = 0.0
	zeon_research_reason = ""
	enemy_losses = 0
	enemy_research_progress = 0.0
	enemy_base_active = false
	enemy_base_progress = 0.0
	enemy_base_required = 8.0
	enemy_base_tile_pos = Vector2i(-1, -1)
	enemy_grunt_upgrade_level = 0
	enemy_copy_outcome = ""
	enemy_special_units.clear()
	pending_enemy_base_spawn = false
	pending_enemy_base_outcome = false
	pending_enemy_base_destroyed = false
	pending_enemy_base_tile_reset = Vector2i(-1, -1)
	enemy_forces = {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20,
	}
	last_combat_squad_size = 1
	max_notoriety_multiplier = 1.0
	stalking_aces.clear()
	stalking_chance = 0.0
	fleet_security = 25.0
	security_upgrade_level = 1
	driver_repair_skill = 1
	driver_repair_xp = 0
