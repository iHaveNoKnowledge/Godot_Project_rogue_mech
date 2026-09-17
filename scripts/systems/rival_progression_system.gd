class_name RivalProgressionSystem
extends RefCounted

## ---------------------------------------------------------------------------
## REAL-TURN RIVAL PROGRESSION & FOG-OF-WAR TECH TREE SIMULATION
##
## Every turn the player acts on the tabletop board, the rival faction executes
## behind-the-scenes turns:
##   - Scout & Logistics: Farms scrap and fuel, growing enemy reserve squads.
##   - Ruins Excavation: Secretly digs up ancient pre-calamity relics.
##   - Secret Laboratory: Researches experimental prototype frames and weapons.
##
## Fog of War Tech Tree hides the rival's progress until the player either scans
## them via intel or faces an unexpected Prototype Ace encounter!
## ---------------------------------------------------------------------------

const MAX_TECH_LEVEL: int = 5

# --- Behind-The-Scenes Simulation State ---
static var rival_scrap: int = 50
static var rival_energy: int = 30
static var scout_progress: float = 0.0
static var excavation_progress: float = 0.0
static var lab_progress: float = 0.0

# Tech Tree Levels
static var scout_tier: int = 1
static var excavation_tier: int = 1
static var lab_tier: int = 1

# Fog of War Visibility (player only sees what they uncover)
static var is_scout_intel_revealed: bool = false
static var is_excavation_intel_revealed: bool = false
static var is_lab_intel_revealed: bool = false

# Prototype weapon / unit pool generated behind the scenes
static var active_prototype: Dictionary = {}
static var pending_prototype_encounter: bool = false


static func reset() -> void:
	rival_scrap = 50
	rival_energy = 30
	scout_progress = 0.0
	excavation_progress = 0.0
	lab_progress = 0.0
	scout_tier = 1
	excavation_tier = 1
	lab_tier = 1
	is_scout_intel_revealed = false
	is_excavation_intel_revealed = false
	is_lab_intel_revealed = false
	active_prototype.clear()
	pending_prototype_encounter = false


## Advances rival turns behind the scenes whenever the player makes a board move / day passes.
static func advance_rival_turn(turns: int = 1) -> Dictionary:
	var results: Dictionary = {
		"scout_farmed": 0,
		"excavation_progress": 0.0,
		"lab_progress": 0.0,
		"prototype_spawned": false,
		"event_log": []
	}

	for i in range(turns):
		# 1. Scout & Logistics Farming
		var scrap_gain := 15 + scout_tier * 8 + int(randf() * 10)
		var energy_gain := 10 + scout_tier * 5 + int(randf() * 8)
		rival_scrap += scrap_gain
		rival_energy += energy_gain
		results["scout_farmed"] += scrap_gain
		scout_progress += 1.0

		if scout_progress >= 4.0 and scout_tier < MAX_TECH_LEVEL:
			scout_progress = 0.0
			scout_tier += 1
			if GlobalData.narrative:
				GlobalData.narrative.enemy_forces["grunt_max"] = mini(GlobalData.narrative.enemy_forces.get("grunt_max", 20) + 2, 40)
				GlobalData.narrative.enemy_forces["grunt_current"] = mini(GlobalData.narrative.enemy_forces.get("grunt_current", 10) + 2, GlobalData.narrative.enemy_forces["grunt_max"])

		# 2. Ruins Relic Excavation
		excavation_progress += 0.75 + float(excavation_tier) * 0.25
		if excavation_progress >= 6.0 and excavation_tier < MAX_TECH_LEVEL:
			excavation_progress = 0.0
			excavation_tier += 1
			results["event_log"].append("Rival unearthed an ancient relic core!")
			_trigger_branch_breakthrough("excavation", excavation_tier, results)

		# 3. Secret Laboratory Research
		lab_progress += 0.65 + float(lab_tier) * 0.35
		if lab_progress >= 7.0 and lab_tier < MAX_TECH_LEVEL:
			lab_progress = 0.0
			lab_tier += 1
			results["event_log"].append("Rival lab completed prototype development!")
			_trigger_branch_breakthrough("laboratory", lab_tier, results)
			results["prototype_spawned"] = not active_prototype.is_empty()

	EventBus.rival_progression_updated.emit(get_rival_status_summary())
	return results


## Triggers a data-driven breakthrough for a rival progression branch.
## Queries TechnologySystem for eligible faction technologies matching metadata,
## grants the candidate, activates prototype state if applicable, and emits EventBus signal.
static func trigger_breakthrough(branch: String = "laboratory") -> Dictionary:
	var tier: int = lab_tier if branch == "laboratory" else excavation_tier
	var dummy_results: Dictionary = {"event_log": []}
	_trigger_branch_breakthrough(branch, tier, dummy_results)
	return dummy_results.get("breakthrough", {})


static func _trigger_branch_breakthrough(branch: String, tier: int, results: Dictionary) -> void:
	var ts = load("res://scripts/systems/technology_system.gd")
	if not ts:
		return
	var context: Dictionary = {
		"branch": branch,
		"tier": tier
	}
	var tech_id: String = ts.select_breakthrough_technology("rival", context)
	if tech_id.is_empty():
		return
	
	ts.grant_faction_technology("rival", tech_id)
	var def: Dictionary = ts.get_technology_definition(tech_id)
	var diff_meta: Dictionary = def.get("diffusion_metadata", {})
	var is_proto: bool = diff_meta.get("prototype_only", false)
	
	if is_proto:
		ts.set_technology_prototype_active(tech_id, true)
		active_prototype = {
			"name": def.get("name", tech_id),
			"tier": tier,
			"tech_id": tech_id,
			"branch": branch,
			"damage_mult": 1.4 + float(tier) * 0.2,
			"speed_mult": 1.25 + float(tier) * 0.1,
			"special_sfx": "prototype_charge"
		}
		pending_prototype_encounter = true
	
	var breakthrough_data: Dictionary = {
		"faction_id": "rival",
		"tech_id": tech_id,
		"branch": branch,
		"tier": tier,
		"is_prototype": is_proto,
		"tech_name": def.get("name", tech_id)
	}
	
	if EventBus.has_signal("rival_technology_breakthrough"):
		EventBus.rival_technology_breakthrough.emit(breakthrough_data)
	
	results["event_log"].append("Rival breakthrough in %s: unlocked %s!" % [branch, def.get("name", tech_id)])
	results["breakthrough"] = breakthrough_data
	if results.has("breakthroughs") and results["breakthroughs"] is Array:
		results["breakthroughs"].append(breakthrough_data)


static func _develop_prototype() -> void:
	# Fallback prototype development using data-driven breakthrough if possible
	var res = trigger_breakthrough("laboratory")
	if active_prototype.is_empty():
		var prototype_names = [
			"Qibing-0 'Phantom Fang'",
			"Prototype X-8 'Singularity Dread'",
			"Oberon-Custom 'Vanguard Beam'",
			"Zephyr-Type-Null 'Blink Striker'"
		]
		var selected_name: String = prototype_names[randi() % prototype_names.size()]
		var wtype: String = "prototype_beam" if randf() > 0.5 else "relic_singularity_blade"
		var tid: String = "tech_beam_weaponry" if wtype == "prototype_beam" else "tech_high_energy_barrier"
		
		active_prototype = {
			"name": selected_name,
			"tier": lab_tier,
			"pilot_callsign": PilotGenerator.CALLSIGNS[randi() % PilotGenerator.CALLSIGNS.size()],
			"weapon_type": wtype,
			"tech_id": tid,
			"damage_mult": 1.4 + float(lab_tier) * 0.2,
			"speed_mult": 1.25 + float(lab_tier) * 0.1,
			"special_sfx": "prototype_charge"
		}
		pending_prototype_encounter = true
		EventBus.prototype_encounter_triggered.emit(active_prototype)


## Returns masked / Fog-of-War view of rival tech tree for player UI inspection.
static func get_fog_of_war_tech_tree() -> Dictionary:
	return {
		"scout": {
			"tier": scout_tier if is_scout_intel_revealed else -1,
			"status": "Logistics & Fleet Reserve" if is_scout_intel_revealed else "UNKNOWN (Fog of War)",
			"revealed": is_scout_intel_revealed
		},
		"excavation": {
			"tier": excavation_tier if is_excavation_intel_revealed else -1,
			"status": "Ancient Ruins Dig Sites" if is_excavation_intel_revealed else "UNKNOWN (Fog of War)",
			"revealed": is_excavation_intel_revealed
		},
		"laboratory": {
			"tier": lab_tier if is_lab_intel_revealed else -1,
			"status": "Prototype Research Labs" if is_lab_intel_revealed else "CLASSIFIED (Fog of War)",
			"revealed": is_lab_intel_revealed,
			"prototype": active_prototype.get("name", "NONE") if is_lab_intel_revealed else "???"
		}
	}


static func reveal_intel(branch: String) -> void:
	match branch:
		"scout": is_scout_intel_revealed = true
		"excavation": is_excavation_intel_revealed = true
		"laboratory": is_lab_intel_revealed = true
		"all":
			is_scout_intel_revealed = true
			is_excavation_intel_revealed = true
			is_lab_intel_revealed = true


static func get_rival_status_summary() -> Dictionary:
	return {
		"scout_tier": scout_tier,
		"excavation_tier": excavation_tier,
		"lab_tier": lab_tier,
		"has_prototype": not active_prototype.is_empty(),
		"pending_encounter": pending_prototype_encounter
	}


static func get_scout_tier() -> int:
	return scout_tier


static func get_excavation_tier() -> int:
	return excavation_tier


static func get_lab_tier() -> int:
	return lab_tier


static func get_active_prototype() -> Dictionary:
	return active_prototype.duplicate(true)


static func get_active_prototype_tech_id() -> String:
	return str(active_prototype.get("tech_id", ""))


static func has_active_prototype() -> bool:
	return not active_prototype.is_empty()


## Serializes authoritative rival progression state.
static func serialize_rival_state() -> Dictionary:
	return {
		"rival_scrap": rival_scrap,
		"rival_energy": rival_energy,
		"scout_progress": scout_progress,
		"excavation_progress": excavation_progress,
		"lab_progress": lab_progress,
		"scout_tier": scout_tier,
		"excavation_tier": excavation_tier,
		"lab_tier": lab_tier,
		"is_scout_intel_revealed": is_scout_intel_revealed,
		"is_excavation_intel_revealed": is_excavation_intel_revealed,
		"is_lab_intel_revealed": is_lab_intel_revealed,
		"active_prototype": active_prototype.duplicate(true),
		"pending_prototype_encounter": pending_prototype_encounter
	}


## Deserializes authoritative rival progression state with safe defaults for missing fields.
static func deserialize_rival_state(data: Variant) -> void:
	reset()
	if not (data is Dictionary):
		return
	var dict: Dictionary = data
	rival_scrap = int(dict.get("rival_scrap", 50))
	rival_energy = int(dict.get("rival_energy", 30))
	scout_progress = float(dict.get("scout_progress", 0.0))
	excavation_progress = float(dict.get("excavation_progress", 0.0))
	lab_progress = float(dict.get("lab_progress", 0.0))
	scout_tier = int(dict.get("scout_tier", 1))
	excavation_tier = int(dict.get("excavation_tier", 1))
	lab_tier = int(dict.get("lab_tier", 1))
	is_scout_intel_revealed = bool(dict.get("is_scout_intel_revealed", false))
	is_excavation_intel_revealed = bool(dict.get("is_excavation_intel_revealed", false))
	is_lab_intel_revealed = bool(dict.get("is_lab_intel_revealed", false))
	var proto = dict.get("active_prototype", {})
	if proto is Dictionary:
		active_prototype = proto.duplicate(true)
	pending_prototype_encounter = bool(dict.get("pending_prototype_encounter", false))

