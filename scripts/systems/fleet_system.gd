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
	return clampf(GlobalData.narrative.fleet_security, GlobalData.FLEET_SECURITY_MIN, GlobalData.FLEET_SECURITY_MAX)


static func get_security_upgrade_cost() -> int:
	return GlobalData.SECURITY_UPGRADE_BASE_COST + (GlobalData.hangar.security_upgrade_level - 1) * 40


# Spend credits to raise fleet security. Returns false if unaffordable or maxed.
static func upgrade_fleet_security() -> bool:
	var cost := get_security_upgrade_cost()
	if GlobalData.currency.credits < cost:
		return false
	if get_fleet_security() >= GlobalData.FLEET_SECURITY_MAX:
		return false
	GlobalData.currency.credits -= cost
	GlobalData.hangar.security_upgrade_level += 1
	GlobalData.narrative.fleet_security = minf(get_fleet_security() + GlobalData.SECURITY_PER_UPGRADE, GlobalData.FLEET_SECURITY_MAX)
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
	if amount <= 0 or GlobalData.narrative.driver_repair_skill >= GlobalData.REPAIR_SKILL_MAX:
		return false
	GlobalData.narrative.driver_repair_xp += amount
	var leveled_up := false
	while GlobalData.narrative.driver_repair_skill < GlobalData.REPAIR_SKILL_MAX:
		var needed := get_repair_skill_xp_for_next(GlobalData.narrative.driver_repair_skill)
		if GlobalData.narrative.driver_repair_xp < needed:
			break
		GlobalData.narrative.driver_repair_xp -= needed
		GlobalData.narrative.driver_repair_skill += 1
		leveled_up = true
	return leveled_up


# The scrap armor tier the driver can build right now (1..5).
static func get_scrap_armor_tier() -> int:
	return clamp(GlobalData.narrative.driver_repair_skill, 1, GlobalData.REPAIR_SKILL_MAX)


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
	for unit in GlobalData.hangar.fleet_roster:
		if unit is Dictionary and unit.get("fielded", true) and not unit.get("destroyed", false):
			# A wounded pilot can still be ASSIGNED to a berth (so a mech waits for
			# them), but they never tag into combat until the recovery countdown
			# ends (or the roster's HEAL clears it). This gate is the source of
			# truth even if some UI toggles `fielded` back on early.
			if bool(unit.get("wounded", false)):
				continue
			result.append(unit)
	return result


# Feature 7 rule: combat allies come ONLY from piloted hangar mechs. A fleet
# unit can field only when a pilot is seated in a hangar berth AND the unit's
# fielded flag is on (healthy — not wounded/destroyed). Returns the hangar
# mechs that tag along, paired with their pilot's fleet unit:
#   [{mech, unit}] sorted by berth slot. Template-only units (researched
# blueprints with no seated driver) are dropped from the field.
static func get_sortie_units() -> Array:
	var active_id := str(HangarManager.get_active_mech().get("id", ""))
	var result: Array = []
	for mech in HangarManager.get_mechs():
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		# The active mech is the one the player pilots — never an AI ally.
		if mech_id == active_id:
			continue
		var pilot_id := str(mech.get("pilot", ""))
		if pilot_id == "" or pilot_id == HangarManager.PLAYER_PILOT_ID:
			continue
		if not pilot_id.begins_with("fleet_"):
			continue
		var template_id := pilot_id.trim_prefix("fleet_")
		var unit := get_fleet_unit(template_id)
		if unit.is_empty():
			continue
		if bool(unit.get("destroyed", false)):
			continue
		if bool(unit.get("wounded", false)):
			continue
		if not bool(unit.get("fielded", true)):
			continue
		result.append({"mech": mech, "unit": unit})
	return result


# Template ids of every fleet pilot currently seated in a hangar mech — the
# only units that can field under the Feature 7 rule. Shared by the intermission
# fleet panel so it never offers a toggle for a pilot-less template unit.
static func get_seated_template_ids() -> Dictionary:
	var seated: Dictionary = {}
	for mech in HangarManager.get_mechs():
		var pilot := str(mech.get("pilot", ""))
		if pilot.begins_with("fleet_"):
			seated[pilot.trim_prefix("fleet_")] = true
	return seated


static func get_fleet_unit(template_id: String) -> Dictionary:
	for unit in GlobalData.hangar.fleet_roster:
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
	GlobalData.hangar.fleet_roster.append({
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
	# A wounded pilot is recovering and cannot be sent into the field — the
	# get_fielded_units() gate would skip them anyway, so refusing to even flag
	# them fielded keeps the roster state honest (the intermission toggle and
	# any other caller share this single source of truth).
	if fielded and bool(unit.get("wounded", false)):
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
	return GlobalData.hangar.research_projects.has(project_id)


static func is_research_completed(project_id: String) -> bool:
	return project_id in GlobalData.hangar.research_unlocked


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
	if GlobalData.currency.data_cores < cost:
		return false
	GlobalData.currency.data_cores -= cost
	GlobalData.hangar.research_projects[project_id] = {
		"progress": 0,
		"required": int(project.get("research_time", 6)),
		"started": true,
	}
	return true


# Advance all active research by `points`. Returns project ids completed now.
static func tick_research(points: int) -> Array:
	var completed: Array = []
	for project_id in GlobalData.hangar.research_projects.keys():
		var state = GlobalData.hangar.research_projects[project_id]
		if state is Dictionary:
			state["progress"] = int(state.get("progress", 0)) + points
			if int(state.get("progress", 0)) >= int(state.get("required", 1)) and not (project_id in completed):
				GlobalData.hangar.research_unlocked.append(project_id)
				GlobalData.hangar.research_projects.erase(project_id)
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
			# matching valkyrion-tier catalog parts (flagged blueprint_only). The
			# unlocking is recorded in research_unlocked; the hangar/craft gates
			# read entry_is_blueprint_locked() against that list. The blueprint_id
			# on each guarded catalog entry must equal this project_id.
			pass
