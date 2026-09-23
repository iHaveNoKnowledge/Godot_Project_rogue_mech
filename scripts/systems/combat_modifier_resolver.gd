class_name CombatModifierResolver
extends RefCounted

## ---------------------------------------------------------------------------
## COMBAT MODIFIER RESOLVER (Phase 2E-18)
##
## Centralized architectural authority for resolving pilot-derived combat modifiers
## and calculating aggregate multipliers for combat runtime systems.
##
## RESPONSIBILITY BOUNDARIES:
## 1. Reads pilot capabilities, perks, and unlocked skills from PilotSystem / PilotSkillSystem.
## 2. Provides stat-specific modifier resolution channels preserving existing
##    formula semantics:
##    - Multiplicative for reduction channels (dash energy, spread, heat)
##    - Additive for positive damage bonuses (1.0 + bonus1 + bonus2)
## 3. Prevents duplicate modifier application across runtime systems.
## 4. Does NOT bypass TechnologySystem authorization or LoadoutSystem validation.
## ---------------------------------------------------------------------------

const PilotSys = preload("res://scripts/systems/pilot_system.gd")


## Checks whether an active pilot capability / perk is present for the player.
static func has_pilot_perk(perk_id: String, context: Dictionary = {}) -> bool:
	var hired: Array = Array(context.get("hired_pilots", []))
	var recruits: Array = Array(context.get("recruited_characters", []))
	return PilotSys.has_pilot_perk(perk_id, hired, recruits)


## Checks whether a pilot skill is unlocked (checking explicit context or GlobalData.pilot).
static func is_skill_unlocked(skill_id: String, context: Dictionary = {}) -> bool:
	if context.has("unlocked_skills") and context["unlocked_skills"] is Array:
		return (context["unlocked_skills"] as Array).has(skill_id)
	return PilotSys.get_unlocked_skills().has(skill_id)


## Resolves pilot-derived dash energy cost multiplier.
## Legacy baseline: 'precognitive_flow' perk grants 0.5x cost.
## Skills: 'tactical_dash' (0.85x), 'slipstream_dash' (0.70x).
static func resolve_dash_energy_multiplier(context: Dictionary = {}) -> float:
	var mult := 0.5 if has_pilot_perk("precognitive_flow", context) else 1.0
	if is_skill_unlocked("tactical_dash", context):
		mult *= 0.85
	if is_skill_unlocked("slipstream_dash", context):
		mult *= 0.70
	return mult


## Resolves pilot-derived dash precision dodge window multiplier.
## Legacy baseline: 'precognitive_flow' perk grants 1.5x precision dodge window.
## Skills: 'evasive_reflexes' (1.25x).
static func resolve_dash_precision_window_multiplier(context: Dictionary = {}) -> float:
	var mult := 1.5 if has_pilot_perk("precognitive_flow", context) else 1.0
	if is_skill_unlocked("evasive_reflexes", context):
		mult *= 1.25
	return mult


## Resolves pilot-derived weapon damage multiplier.
## Additive bonuses: 'kinetic_tuning' (+10%), 'point_blank_mastery' (+20%).
static func resolve_pilot_damage_multiplier(context: Dictionary = {}) -> float:
	var bonus := 0.0
	if is_skill_unlocked("kinetic_tuning", context):
		bonus += 0.10
	if is_skill_unlocked("point_blank_mastery", context):
		bonus += 0.20
	return 1.0 + bonus


## Resolves pilot-derived weapon aim spread multiplier.
## Skills: 'ballistic_calibration' (0.75x).
static func resolve_pilot_spread_multiplier(context: Dictionary = {}) -> float:
	var mult := 1.0
	if is_skill_unlocked("ballistic_calibration", context):
		mult *= 0.75
	return mult


## Resolves pilot-derived weapon heat generation multiplier.
## Skills: 'heat_venting_drills' (0.85x).
static func resolve_pilot_heat_generation_multiplier(context: Dictionary = {}) -> float:
	var mult := 1.0
	if is_skill_unlocked("heat_venting_drills", context):
		mult *= 0.85
	return mult


## Resolves pilot-derived movement speed multiplier.
## Skills: 'combat_strides' (1.10x).
static func resolve_pilot_movement_speed_multiplier(context: Dictionary = {}) -> float:
	var mult := 1.0
	if is_skill_unlocked("combat_strides", context):
		mult *= 1.10
	return mult
