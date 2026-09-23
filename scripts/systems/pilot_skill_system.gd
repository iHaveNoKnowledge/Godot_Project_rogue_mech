class_name PilotSkillSystem
extends RefCounted

## ---------------------------------------------------------------------------
## PILOT SKILL SYSTEM (Phase 2E-18)
##
## Authoritative domain service for Pilot Progression, Skill Unlocks,
## XP Calculations, and Combat Specialization.
## Mutates and queries GlobalData.pilot.progression.
## ---------------------------------------------------------------------------

const PilotSkillCat = preload("res://scripts/systems/pilot_skill_catalog.gd")
const PilotSys = preload("res://scripts/systems/pilot_system.gd")

const MAX_PILOT_LEVEL: int = 10
const BASE_XP_THRESHOLD: int = 100
const XP_PER_LEVEL_INCREMENT: int = 50

const VALID_SPECIALIZATIONS: Array[String] = ["vanguard", "skirmisher", "artillery"]

const COMBAT_XP_TABLE: Dictionary = {
	"grunt": 50,
	"ace": 100,
	"boss": 250,
	"duel": 100,
	"enemy_base": 200
}


# --- Accessors ---------------------------------------------------------------

static func get_level() -> int:
	return PilotSys.get_pilot_level()


static func get_xp() -> int:
	return PilotSys.get_pilot_xp()


static func get_skill_points() -> int:
	return PilotSys.get_skill_points()


static func get_unlocked_skills() -> Array:
	return PilotSys.get_unlocked_skills()


static func get_specialization() -> String:
	return PilotSys.get_specialization()


static func is_skill_unlocked(skill_id: String) -> bool:
	return get_unlocked_skills().has(skill_id)


static func get_skill_definition(skill_id: String) -> Dictionary:
	return PilotSkillCat.get_skill(skill_id)


static func get_all_skill_definitions() -> Array:
	return PilotSkillCat.get_all_skills()


static func get_xp_required_for_next_level(lvl: int = -1) -> int:
	var target_lvl := get_level() if lvl <= 0 else lvl
	if target_lvl >= MAX_PILOT_LEVEL:
		return 0
	return BASE_XP_THRESHOLD + (maxi(target_lvl, 1) - 1) * XP_PER_LEVEL_INCREMENT


# --- XP & Level Progression -------------------------------------------------

## Awards combat/run XP, evaluates level thresholds, and awards skill points.
## Supports multi-level transitions from single grants and clamps at Level 10.
static func award_xp(amount: int, _context: Dictionary = {}) -> Dictionary:
	if amount <= 0:
		return {
			"awarded_xp": 0,
			"levels_gained": 0,
			"new_level": get_level(),
			"xp": get_xp(),
			"skill_points": get_skill_points()
		}

	if GlobalData == null or GlobalData.pilot == null:
		return {"awarded_xp": 0, "levels_gained": 0, "new_level": 1, "xp": 0, "skill_points": 0}

	var cur_level := int(GlobalData.pilot.progression.get("level", 1))
	var cur_xp := int(GlobalData.pilot.progression.get("xp", 0))
	var cur_points := int(GlobalData.pilot.progression.get("skill_points", 0))

	if cur_level >= MAX_PILOT_LEVEL:
		GlobalData.pilot.progression["xp"] = 0
		return {
			"awarded_xp": amount,
			"levels_gained": 0,
			"new_level": MAX_PILOT_LEVEL,
			"xp": 0,
			"skill_points": cur_points
		}

	cur_xp += amount
	var levels_gained := 0

	while cur_level < MAX_PILOT_LEVEL:
		var req := get_xp_required_for_next_level(cur_level)
		if cur_xp < req:
			break
		cur_xp -= req
		cur_level += 1
		cur_points += 1
		levels_gained += 1
		if EventBus and EventBus.has_signal("pilot_level_up"):
			EventBus.pilot_level_up.emit(cur_level, cur_points)

	if cur_level >= MAX_PILOT_LEVEL:
		cur_xp = 0

	GlobalData.pilot.progression["level"] = cur_level
	GlobalData.pilot.progression["xp"] = cur_xp
	GlobalData.pilot.progression["skill_points"] = cur_points

	return {
		"awarded_xp": amount,
		"levels_gained": levels_gained,
		"new_level": cur_level,
		"xp": cur_xp,
		"skill_points": cur_points
	}


## Evaluates combat node type & decisive victory bonus, then dispatches XP.
static func award_combat_xp(combat_node_type: String, is_decisive: bool = false) -> Dictionary:
	var base_xp := int(COMBAT_XP_TABLE.get(combat_node_type, 0))
	if base_xp <= 0:
		return {"awarded_xp": 0, "levels_gained": 0, "new_level": get_level(), "xp": get_xp(), "skill_points": get_skill_points()}

	var final_xp := int(roundf(float(base_xp) * 1.25)) if is_decisive else base_xp
	return award_xp(final_xp, {"combat_node_type": combat_node_type, "decisive": is_decisive})


# --- Skill Unlock & Validation ----------------------------------------------

static func validate_unlock(skill_id: String) -> Dictionary:
	var def := PilotSkillCat.get_skill(skill_id)
	if def.is_empty():
		return {"allowed": false, "reason": "invalid_skill"}

	if is_skill_unlocked(skill_id):
		return {"allowed": false, "reason": "already_unlocked"}

	var req_lvl := int(def.get("required_level", 1))
	if get_level() < req_lvl:
		return {"allowed": false, "reason": "insufficient_level"}

	var spec_req := str(def.get("specialization", "universal")).to_lower()
	if spec_req != "" and spec_req != "universal":
		var cur_spec := get_specialization().to_lower()
		if cur_spec != spec_req:
			return {"allowed": false, "reason": "specialization_locked"}

	var prereqs: Array = Array(def.get("prerequisites", []))
	for pid in prereqs:
		if not is_skill_unlocked(str(pid)):
			return {"allowed": false, "reason": "missing_prerequisite"}

	var cost := int(def.get("cost", 1))
	if get_skill_points() < cost:
		return {"allowed": false, "reason": "insufficient_skill_points"}

	return {"allowed": true, "reason": ""}


static func unlock_skill(skill_id: String) -> Dictionary:
	var val := validate_unlock(skill_id)
	if not bool(val.get("allowed", false)):
		return val

	var def := PilotSkillCat.get_skill(skill_id)
	var cost := int(def.get("cost", 1))

	if GlobalData and GlobalData.pilot:
		var cur_points := int(GlobalData.pilot.progression.get("skill_points", 0))
		GlobalData.pilot.progression["skill_points"] = maxi(cur_points - cost, 0)
		var skills: Array = Array(GlobalData.pilot.progression.get("unlocked_skills", []))
		if not skills.has(skill_id):
			skills.append(skill_id)
		GlobalData.pilot.progression["unlocked_skills"] = skills

	return {"allowed": true, "reason": "", "skill_id": skill_id}


# --- Specialization Selection & Validation ----------------------------------

static func validate_specialization(spec_id: String) -> Dictionary:
	var target_spec := spec_id.to_lower().strip_edges()
	if not VALID_SPECIALIZATIONS.has(target_spec):
		return {"allowed": false, "reason": "invalid_specialization"}

	if get_level() < 3:
		return {"allowed": false, "reason": "insufficient_level"}

	if get_specialization() != "":
		return {"allowed": false, "reason": "already_selected"}

	return {"allowed": true, "reason": ""}


static func select_specialization(spec_id: String) -> Dictionary:
	var val := validate_specialization(spec_id)
	if not bool(val.get("allowed", false)):
		return val

	var target_spec := spec_id.to_lower().strip_edges()
	if GlobalData and GlobalData.pilot:
		GlobalData.pilot.progression["specialization"] = target_spec

	return {"allowed": true, "reason": "", "specialization": target_spec}
