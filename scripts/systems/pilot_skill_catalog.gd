class_name PilotSkillCatalog
extends RefCounted

## ---------------------------------------------------------------------------
## PILOT SKILL CATALOG (Phase 2E-18)
##
## Authoritative, immutable static definitions for V1 Pilot Skills.
## All skills are single-rank binary unlocks costing 1 skill point.
## ---------------------------------------------------------------------------

const SKILLS: Array[Dictionary] = [
	{
		"id": "tactical_dash",
		"name": "Tactical Dash",
		"desc": "Optimizes thruster bursts. Reduces dash energy cost by 15%.",
		"category": "mobility",
		"specialization": "universal",
		"required_level": 1,
		"prerequisites": [],
		"cost": 1,
		"modifier_channel": "dash_energy",
		"modifier_value": 0.85
	},
	{
		"id": "evasive_reflexes",
		"name": "Evasive Reflexes",
		"desc": "Expands precision dodge window by 25%.",
		"category": "defense",
		"specialization": "universal",
		"required_level": 2,
		"prerequisites": ["tactical_dash"],
		"cost": 1,
		"modifier_channel": "dash_precision",
		"modifier_value": 1.25
	},
	{
		"id": "kinetic_tuning",
		"name": "Kinetic Tuning",
		"desc": "Enhances weapon output. +10% projectile damage.",
		"category": "offense",
		"specialization": "universal",
		"required_level": 1,
		"prerequisites": [],
		"cost": 1,
		"modifier_channel": "pilot_damage",
		"modifier_value": 1.10
	},
	{
		"id": "heat_venting_drills",
		"name": "Heat Venting Drills",
		"desc": "Optimizes thermal dispersal. -15% weapon heat accumulation.",
		"category": "tactics",
		"specialization": "universal",
		"required_level": 2,
		"prerequisites": [],
		"cost": 1,
		"modifier_channel": "pilot_heat_generation",
		"modifier_value": 0.85
	},
	{
		"id": "point_blank_mastery",
		"name": "Point-Blank Mastery",
		"desc": "Vanguard close-range doctrine. +20% weapon damage.",
		"category": "offense",
		"specialization": "vanguard",
		"required_level": 3,
		"prerequisites": [],
		"cost": 1,
		"modifier_channel": "pilot_damage",
		"modifier_value": 1.20
	},
	{
		"id": "slipstream_dash",
		"name": "Slipstream Dash",
		"desc": "Skirmisher inertia regulation. Reduces dash energy cost by 30%.",
		"category": "mobility",
		"specialization": "skirmisher",
		"required_level": 3,
		"prerequisites": ["tactical_dash"],
		"cost": 1,
		"modifier_channel": "dash_energy",
		"modifier_value": 0.70
	},
	{
		"id": "ballistic_calibration",
		"name": "Ballistic Calibration",
		"desc": "Artillery marksmanship protocols. -25% weapon aim spread.",
		"category": "offense",
		"specialization": "artillery",
		"required_level": 3,
		"prerequisites": [],
		"cost": 1,
		"modifier_channel": "pilot_spread",
		"modifier_value": 0.75
	},
	{
		"id": "combat_strides",
		"name": "Combat Strides",
		"desc": "Synchronized chassis gait. +10% mecha movement speed.",
		"category": "mobility",
		"specialization": "universal",
		"required_level": 2,
		"prerequisites": [],
		"cost": 1,
		"modifier_channel": "pilot_movement_speed",
		"modifier_value": 1.10
	}
]


static func get_all_skills() -> Array[Dictionary]:
	return SKILLS.duplicate(true)


static func get_skill(skill_id: String) -> Dictionary:
	for skill in SKILLS:
		if str(skill.get("id", "")) == skill_id:
			return skill.duplicate(true)
	return {}


static func has_skill_definition(skill_id: String) -> bool:
	return not get_skill(skill_id).is_empty()


static func get_skills_for_specialization(spec: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill in SKILLS:
		var s_spec := str(skill.get("specialization", "universal")).to_lower()
		if s_spec == "universal" or s_spec == spec.to_lower():
			result.append(skill.duplicate(true))
	return result
