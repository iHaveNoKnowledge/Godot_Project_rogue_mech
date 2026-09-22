class_name DynamicEncounterDirector
extends RefCounted

## =============================================================================
## DYNAMIC ENCOUNTER DIRECTOR — Tactical Rival Adaptation & Encounter Injection
## =============================================================================
## Evaluates player combat profile and macro rival progress, dynamically injecting
## custom Counter-Build Rival Ace mechas into battlefield encounters.
##
## Adaptation Rules:
##   • Player Melee Rush -> Rival Ranged Kiter (high mobility, beam/EMP)
##   • Player Long-Range / Missiles -> Rival High-Speed CQB Shield Rusher
##   • Player Heavy / High Armor -> Rival Armor-Piercing / Thermal Heavy
##   • Player Balanced / Defensive -> Rival Tactical Flanker
## =============================================================================

const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")

## Evaluates whether a dynamic rival encounter should be injected.
static func should_trigger_encounter() -> bool:
	if RivalProgSys.pending_prototype_encounter:
		return true
	if not RivalProgSys.active_prototype.is_empty():
		return true
	if GlobalData and GlobalData.board and int(GlobalData.board.get("wanted_level")) >= 3:
		return true
	return false


## Analyzes the player's current weapon loadout and style
static func analyze_player_loadout() -> Dictionary:
	var analysis: Dictionary = {
		"melee_count": 0,
		"ranged_count": 0,
		"missile_count": 0,
		"shield_count": 0,
		"primary_style": "balanced"
	}

	var loadout: Dictionary = GlobalData.weapons.weapon_loadout
	var slots: Array[String] = ["left", "right", "shoulder_left", "shoulder_right"]

	for slot in slots:
		var ref: String = str(loadout.get(slot, ""))
		if ref == "":
			continue
		var path: String = ref.to_lower()
		var resolved: String = LoadoutSystem.ref_to_path(ref).to_lower()
		if resolved != "":
			path = resolved

		if "blade" in path or "bunker" in path or "fist" in path or "melee" in path:
			analysis["melee_count"] += 1
		elif "shield" in path or "barrier" in path:
			analysis["shield_count"] += 1
		elif "missile" in path or "rocket" in path or "launcher" in path:
			analysis["missile_count"] += 1
		elif "rifle" in path or "carbine" in path or "cannon" in path or "sniper" in path or "gun" in path:
			analysis["ranged_count"] += 1

	if analysis["melee_count"] >= 2:
		analysis["primary_style"] = "melee"
	elif analysis["missile_count"] >= 1 or analysis["ranged_count"] >= 2:
		analysis["primary_style"] = "long_range"
	elif analysis["shield_count"] >= 1:
		analysis["primary_style"] = "defense"
	else:
		analysis["primary_style"] = "balanced"

	return analysis


## Generates a tailor-made counter prototype configuration based on player's build
static func generate_counter_prototype(forced_style: String = "") -> Dictionary:
	var style: String = forced_style
	if style == "":
		style = analyze_player_loadout()["primary_style"]

	var base_proto: Dictionary = RivalProgSys.active_prototype.duplicate(true)
	var tier: int = int(base_proto.get("tier", RivalProgSys.lab_tier))

	var counter_data: Dictionary = {
		"name": base_proto.get("name", "Prototype X-0 'Nemesis'"),
		"pilot_callsign": base_proto.get("pilot_callsign", "Ghost"),
		"tier": tier,
		"hp_scale": 1.5 + float(tier) * 0.15,
		"damage_mult": 1.3 + float(tier) * 0.1,
		"speed_mult": 1.2 + float(tier) * 0.08,
		"paint": {
			"primary": Color(0.12, 0.12, 0.14),
			"secondary": Color(0.88, 0.15, 0.15),
			"accent": Color(1.0, 0.45, 0.1)
		}
	}

	match style:
		"melee":
			# Player rushes melee -> Counter with High-Mobility Kiter with Shield & Beam
			counter_data["archetype"] = 5 # SHIELD_RANGED
			counter_data["tactical_stance"] = "Kite_And_Disrupt"
			counter_data["ai_posture"] = "aggressive"
			counter_data["tech_id"] = "tech_beam_weaponry"
			counter_data["preferred_range"] = 24.0
			counter_data["counter_rationale"] = "Anti-Melee: Maintains kiting range and deploys beam suppression"
		"long_range":
			# Player snipes / fires missiles -> Counter with High-Speed Melee Rusher with Shield
			counter_data["archetype"] = 4 # SHIELD_MELEE
			counter_data["tactical_stance"] = "Frontal_Breaker"
			counter_data["ai_posture"] = "aggressive"
			counter_data["tech_id"] = "tech_high_energy_barrier"
			counter_data["speed_mult"] += 0.15
			counter_data["preferred_range"] = 5.0
			counter_data["counter_rationale"] = "Anti-Ranged: Deflects incoming volleys and closes gap rapidly"
		"defense":
			# Player plays heavy shield/armor -> Counter with Heavy Armor-Piercing Cannon
			counter_data["archetype"] = 2 # HEAVY
			counter_data["tactical_stance"] = "Armor_Crusher"
			counter_data["ai_posture"] = "aggressive"
			counter_data["tech_id"] = "tech_assault_cannon"
			counter_data["damage_mult"] += 0.25
			counter_data["counter_rationale"] = "Anti-Armor: Heavy blunt/piercing bombardment to smash defenses"
		_: # balanced
			counter_data["archetype"] = 0 # RUSHER
			counter_data["tactical_stance"] = "Flank_Hunter"
			counter_data["ai_posture"] = "aggressive"
			counter_data["tech_id"] = "tech_prototype_chassis"
			counter_data["counter_rationale"] = "Balanced Stance: High speed flank maneuvers"

	return counter_data


## Injects the rival prototype into the battle scene via SpawnManager
static func inject_rival_encounter(spawn_manager: Node, spawn_pos: Vector3 = Vector3.ZERO) -> Node3D:
	if spawn_manager == null:
		return null

	var proto: Dictionary = generate_counter_prototype()
	if spawn_manager.has_method("spawn_rival_prototype"):
		return await spawn_manager.spawn_rival_prototype(proto, spawn_pos)
	return null
