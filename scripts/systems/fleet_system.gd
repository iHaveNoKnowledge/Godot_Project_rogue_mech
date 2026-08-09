class_name FleetSystem
extends RefCounted

# -----------------------------------------------------------------------------
# FLEET — roster of allied mech units, fleet security vs enemy espionage,
# driver repair skill, and the research base. Extracted from GlobalData so the
# run-state autoload stays focused on state. Every function reads/writes state
# through the GlobalData singleton; GlobalData keeps thin facades for callers.
#
# Each fleet entry is a per-unit record: {"template_id", "name", "hp", "max_hp",
# "destroyed", "fielded"}. Units are researched from blueprints (data_cores) at
# the research base; fielded units tag along into combat as AI squadmates.
# -----------------------------------------------------------------------------


static func get_fleet_security() -> float:
	return clampf(GlobalData.fleet_security, GlobalData.FLEET_SECURITY_MIN, GlobalData.FLEET_SECURITY_MAX)


static func get_security_upgrade_cost() -> int:
	return GlobalData.SECURITY_UPGRADE_BASE_COST + (GlobalData.security_upgrade_level - 1) * 40


# Spend credits to raise fleet security. Returns false if unaffordable or maxed.
static func upgrade_fleet_security() -> bool:
	var cost := get_security_upgrade_cost()
	if GlobalData.credits < cost:
		return false
	if get_fleet_security() >= GlobalData.FLEET_SECURITY_MAX:
		return false
	GlobalData.credits -= cost
	GlobalData.security_upgrade_level += 1
	GlobalData.fleet_security = minf(get_fleet_security() + GlobalData.SECURITY_PER_UPGRADE, GlobalData.FLEET_SECURITY_MAX)
	return true


# Chance (0..1) that an enemy spy attempt on our mech data FAILS before stealing
# anything. 25 = starting security, 50 = one strong investment, 90+ = fortress.
static func get_spy_counter_chance() -> float:
	return clampf(0.10 + get_fleet_security() * 0.008, 0.10, 0.90)


# -----------------------------------------------------------------------------
# DRIVER REPAIR SKILL — how skilled the pilot is at field repairs.
# - driver_repair_skill: 1..5. Determines the tier of scrap armor a driver can
#   build from emergency patches. Higher skill = stronger (but never equal to
#   proper catalog armor) scrap armor.
# - driver_repair_xp:    earned by doing emergency scrap repairs (practice makes
#   perfect); leveling up raises the skill tier.
# -----------------------------------------------------------------------------


# XP required to advance from `level` to `level + 1`.
static func get_repair_skill_xp_for_next(level: int) -> int:
	return GlobalData.REPAIR_XP_BASE + maxi(level - 1, 0) * GlobalData.REPAIR_XP_PER_LEVEL


# Returns true when the XP gain pushed the skill to a new tier.
static func gain_repair_xp(amount: int) -> bool:
	if amount <= 0 or GlobalData.driver_repair_skill >= GlobalData.REPAIR_SKILL_MAX:
		return false
	GlobalData.driver_repair_xp += amount
	var leveled_up := false
	while GlobalData.driver_repair_skill < GlobalData.REPAIR_SKILL_MAX:
		var needed := get_repair_skill_xp_for_next(GlobalData.driver_repair_skill)
		if GlobalData.driver_repair_xp < needed:
			break
		GlobalData.driver_repair_xp -= needed
		GlobalData.driver_repair_skill += 1
		leveled_up = true
	return leveled_up


# The scrap armor tier the driver can build right now (1..5).
static func get_scrap_armor_tier() -> int:
	return clamp(GlobalData.driver_repair_skill, 1, GlobalData.REPAIR_SKILL_MAX)


# Stats multiplier for scrap-built armor vs the real catalog part. Tier 1 gives
# 40% of the real stats, each tier +10% up to 80% — scrap can never match a
# properly-crafted armor plate.
static func get_scrap_armor_stat_scale() -> float:
	return clampf(0.40 + 0.10 * (get_scrap_armor_tier() - 1), 0.40, 0.80)


# -----------------------------------------------------------------------------
# ALLY UNITS
# -----------------------------------------------------------------------------


static func get_ally_template(template_id: String) -> Dictionary:
	return GlobalData.ally_unit_templates.get(template_id, {})


static func get_fielded_units() -> Array:
	var result: Array = []
	for unit in GlobalData.fleet_roster:
		if unit is Dictionary and unit.get("fielded", true) and not unit.get("destroyed", false):
			result.append(unit)
	return result


static func get_fleet_unit(template_id: String) -> Dictionary:
	for unit in GlobalData.fleet_roster:
		if unit.get("template_id", "") == template_id:
			return unit
	return {}


static func has_ally_unit(template_id: String) -> bool:
	return not get_fleet_unit(template_id).is_empty()


static func add_ally_unit(template_id: String) -> bool:
	var template = get_ally_template(template_id)
	if template.is_empty():
		push_warning("add_ally_unit: unknown template '%s'" % template_id)
		return false
	if has_ally_unit(template_id):
		return false
	GlobalData.fleet_roster.append({
		"template_id": template_id,
		"name": template.get("name", template_id),
		"hp": float(template.get("frame_hp", 50.0)),
		"max_hp": float(template.get("frame_hp", 50.0)),
		"destroyed": false,
		"fielded": template.get("fielded", true),
	})
	return true


static func set_unit_fielded(template_id: String, fielded: bool) -> void:
	var unit = get_fleet_unit(template_id)
	if unit.is_empty():
		return
	unit["fielded"] = fielded


# -----------------------------------------------------------------------------
# RESEARCH BASE
# -----------------------------------------------------------------------------


static func get_research_project(project_id: String) -> Dictionary:
	for project in GlobalData.research_blueprints:
		if project.get("id", "") == project_id:
			return project
	return {}


static func is_research_active(project_id: String) -> bool:
	return GlobalData.research_projects.has(project_id)


static func is_research_completed(project_id: String) -> bool:
	return project_id in GlobalData.research_unlocked


# Start a research project: consumes data_cores (the blueprint) and begins the
# clock. Research time progresses via board moves (tick_research(1)) and
# completed combats (tick_research(2)).
static func start_research(project_id: String) -> bool:
	if is_research_active(project_id) or is_research_completed(project_id):
		return false
	var project = get_research_project(project_id)
	if project.is_empty():
		return false
	var cost = int(project.get("data_cores", 1))
	if GlobalData.data_cores < cost:
		return false
	GlobalData.data_cores -= cost
	GlobalData.research_projects[project_id] = {
		"progress": 0,
		"required": int(project.get("research_time", 6)),
		"started": true,
	}
	return true


# Advance all active research by `points`. Returns project ids completed now.
static func tick_research(points: int) -> Array:
	var completed: Array = []
	for project_id in GlobalData.research_projects.keys():
		var state = GlobalData.research_projects[project_id]
		if state is Dictionary:
			state["progress"] = int(state.get("progress", 0)) + points
			if int(state.get("progress", 0)) >= int(state.get("required", 1)) and not (project_id in completed):
				GlobalData.research_unlocked.append(project_id)
				GlobalData.research_projects.erase(project_id)
				_apply_research_reward(project_id)
				completed.append(project_id)
	return completed


static func _apply_research_reward(project_id: String) -> void:
	var project = get_research_project(project_id)
	if project.is_empty():
		return
	match project.get("reward_type", ""):
		"unit":
			add_ally_unit(str(project.get("reward_id", "")))
		"armor", "frame":
			# Completing an armor/frame blueprint unlocks crafting access to the
			# matching gundam-tier catalog parts (flagged blueprint_only). The
			# unlocking is recorded in research_unlocked; the hangar/craft gates
			# read entry_is_blueprint_locked() against that list. The blueprint_id
			# on each guarded catalog entry must equal this project_id.
			pass
