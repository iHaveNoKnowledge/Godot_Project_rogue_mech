class_name CombatModifierResolver
extends RefCounted

## ---------------------------------------------------------------------------
## COMBAT MODIFIER RESOLVER (Phase 2E-16A Foundation)
##
## Centralized architectural authority for resolving pilot-derived combat modifiers
## and calculating aggregate multipliers for combat runtime systems.
##
## RESPONSIBILITY BOUNDARIES:
## 1. Reads pilot capabilities and progression from PilotSystem without leaking
##    into NarrativeState.
## 2. Provides stat-specific modifier resolution channels preserving existing
##    formula semantics (does NOT force arbitrary Base * Mod * Pilot * Penalty math).
## 3. Prevents duplicate modifier application across runtime systems.
## 4. Does NOT bypass TechnologySystem authorization or LoadoutSystem validation.
## ---------------------------------------------------------------------------

const PilotSys = preload("res://scripts/systems/pilot_system.gd")


## Checks whether an active pilot capability / perk is present for the player.
static func has_pilot_perk(perk_id: String, context: Dictionary = {}) -> bool:
	var hired: Array = Array(context.get("hired_pilots", []))
	var recruits: Array = Array(context.get("recruited_characters", []))
	return PilotSys.has_pilot_perk(perk_id, hired, recruits)


## Resolves pilot-derived dash energy cost multiplier.
## Legacy baseline: 'precognitive_flow' perk grants 0.5x cost (50% energy reduction).
static func resolve_dash_energy_multiplier(context: Dictionary = {}) -> float:
	if has_pilot_perk("precognitive_flow", context):
		return 0.5
	return 1.0


## Resolves pilot-derived dash precision dodge window multiplier.
## Legacy baseline: 'precognitive_flow' perk grants 1.5x precision dodge window.
static func resolve_dash_precision_window_multiplier(context: Dictionary = {}) -> float:
	if has_pilot_perk("precognitive_flow", context):
		return 1.5
	return 1.0


## Resolves pilot-derived weapon damage multiplier (default neutral 1.0).
static func resolve_pilot_damage_multiplier(_context: Dictionary = {}) -> float:
	return 1.0


## Resolves pilot-derived weapon aim spread multiplier (default neutral 1.0).
static func resolve_pilot_spread_multiplier(_context: Dictionary = {}) -> float:
	return 1.0


## Resolves pilot-derived weapon heat generation multiplier (default neutral 1.0).
static func resolve_pilot_heat_generation_multiplier(_context: Dictionary = {}) -> float:
	return 1.0


## Resolves pilot-derived movement speed multiplier (default neutral 1.0).
static func resolve_pilot_movement_speed_multiplier(_context: Dictionary = {}) -> float:
	return 1.0
