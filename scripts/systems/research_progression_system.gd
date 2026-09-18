class_name ResearchProgressionSystem
extends RefCounted

## ---------------------------------------------------------------------------
## RESEARCH PROGRESSION SYSTEM (Phase 2E-4B)
##
## Authoritative router for gameplay research progression events across
## independent research domains:
## 1. TechnologySystem (Macro scientific lineage & architecture research)
## 2. FleetSystem (Micro blueprint manufacturing & equipment unlocks)
##
## Keeps TechnologySystem decoupled from GlobalData, BoardManager, and CombatManager.
## ---------------------------------------------------------------------------

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FleetSys = preload("res://scripts/systems/fleet_system.gd")


## Dispatches approved progression points to all active research domains.
## points: progression units (e.g. 1.0 for a board day, 2.0 for combat victory)
## source: identifier for event origin ("board_day", "combat_victory", "lab_action", etc.)
static func dispatch_progression(source: String, points: float = 1.0, context: Dictionary = {}) -> Dictionary:
	var ctx := context.duplicate(true)
	ctx["source"] = source
	ctx["progression_points"] = points

	# 1. Advance TechnologySystem active scientific research (Macro)
	var tech_result: Dictionary = {}
	if TechSys:
		tech_result = TechSys.advance_active_research(points, ctx)

	# 2. Advance FleetSystem blueprint manufacturing research (Micro)
	# FleetSystem operates on discrete integer points
	var bp_points := int(roundf(points))
	var completed_blueprints: Array = []
	if FleetSys and bp_points > 0:
		completed_blueprints = FleetSys.tick_research(bp_points)

	return {
		"source": source,
		"points": points,
		"technology": tech_result,
		"blueprints_completed": completed_blueprints
	}


## Convenience helper for board day progression events.
static func advance_board_day(points: float = 1.0, context: Dictionary = {}) -> Dictionary:
	return dispatch_progression("board_day", points, context)


## Convenience helper for combat victory progression events.
static func advance_combat_victory(points: float = 2.0, context: Dictionary = {}) -> Dictionary:
	return dispatch_progression("combat_victory", points, context)
