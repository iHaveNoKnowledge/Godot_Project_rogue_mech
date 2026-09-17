class_name TechnologySystem
extends RefCounted

## ---------------------------------------------------------------------------
## TECHNOLOGY SYSTEM — Authoritative Data-Driven Technology Architecture (Phase 2D)
##
## Defines technology lineage, architecture generation, families, compatibility,
## era plausibility, and discovery states.
##
## CORE PRINCIPLES:
## 1. Generation is NOT a power level. It represents technological lineage and architecture.
## 2. Platforms do not become obsolete at the same speed as technology.
## 3. Old Valkren frames can mount modern technologies via Technology Bridges.
## 4. Discovery is distinct from compatibility.
## 5. Technology definitions use neutral identifiers and avoid speculative unapproved lore.
## ---------------------------------------------------------------------------

# Discovery state progression
enum DiscoveryState {
	UNKNOWN = 0,
	ENCOUNTERED = 1,
	SALVAGED = 2,
	IDENTIFIED = 3,
	RESEARCHED = 4,
	USABLE = 5
}

# Compatibility evaluation status
enum CompatibilityStatus {
	INCOMPATIBLE = 0,
	DIRECT = 1,
	BRIDGED = 2
}

# Neutral Technology Family Identifiers
const FAMILY_BALLISTIC := "ballistic"
const FAMILY_ENERGY := "energy"
const FAMILY_POWER := "power"
const FAMILY_ACTUATION := "actuation"
const FAMILY_COOLING := "cooling"
const FAMILY_INTERFACE := "interface"
const FAMILY_ARMOR := "armor"
const FAMILY_MOBILITY := "mobility"

# Neutral Lineage Identifiers
const LINEAGE_VALKREN := "valkren"
const LINEAGE_VALKRYON := "valkryon"
const LINEAGE_COMMON := "common"
const LINEAGE_EXPERIMENTAL := "experimental"

# Neutral Technology Diffusion Categories (Phase 2E-1)
const CATEGORY_CONVENTIONAL := "conventional"
const CATEGORY_MIXED := "mixed"
const CATEGORY_EXPERIMENTAL := "experimental"

# Standard Faction Access Identifiers (Phase 2E-1)
const FACTION_ALL := "all"
const FACTION_RIVAL := "rival"
const FACTION_CONVOY := "convoy"

# In-memory technology catalog and discovery state
static var _catalog: Dictionary = {}
static var _player_discovery: Dictionary = {}
static var _world_diffusion_overrides: Dictionary = {}
static var _active_world_prototypes: Dictionary = {}
static var _faction_technologies: Dictionary = {}
static var _initialized: bool = false


# ===========================================================================
# CATALOG INITIALIZATION & REGISTRATION
# ===========================================================================

static func init_catalog_if_needed() -> void:
	if _initialized:
		return
	_initialized = true
	_catalog.clear()

	# --- Generation 1: Conventional Valkren Foundation ---
	register_technology({
		"tech_id": "tech_ballistic_conventional",
		"name": "Conventional Ballistics Architecture",
		"generation": 1,
		"technology_family": FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": LINEAGE_VALKREN,
		"tags": ["ballistic", "kinetic", "conventional", "low_heat"],
		"prerequisites": [],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_families": [FAMILY_BALLISTIC],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.USABLE,
		},
		"diffusion_metadata": {
			"category": CATEGORY_CONVENTIONAL,
			"min_era_phase": 1,
			"default_diffused": true,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL]
		},
		"description": "Standard heavy kinetic ordnance, rifling mechanisms, and chemical propellant feed systems."
	})

	register_technology({
		"tech_id": "tech_combustion_power",
		"name": "Direct Combustion Power Architecture",
		"generation": 1,
		"technology_family": FAMILY_POWER,
		"era_phase_req": 1,
		"origin_lineage": LINEAGE_VALKREN,
		"tags": ["power", "combustion", "rugged", "heavy_torque"],
		"prerequisites": [],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_families": [FAMILY_POWER],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.USABLE,
		},
		"diffusion_metadata": {
			"category": CATEGORY_CONVENTIONAL,
			"min_era_phase": 1,
			"default_diffused": true,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL]
		},
		"description": "High-displacement combustion powerplants providing immense torque at the cost of weight and thermal output."
	})

	register_technology({
		"tech_id": "tech_passive_cooling",
		"name": "Industrial Radiator Cooling",
		"generation": 1,
		"technology_family": FAMILY_COOLING,
		"era_phase_req": 1,
		"origin_lineage": LINEAGE_VALKREN,
		"tags": ["cooling", "radiator", "passive"],
		"prerequisites": [],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_families": [FAMILY_COOLING],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.USABLE,
		},
		"diffusion_metadata": {
			"category": CATEGORY_CONVENTIONAL,
			"min_era_phase": 1,
			"default_diffused": true,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL]
		},
		"description": "Standard passive heat sink fins and heat-pipe radiator assemblies."
	})

	register_technology({
		"tech_id": "tech_hydraulic_actuation",
		"name": "Hydraulic Servo Actuation",
		"generation": 1,
		"technology_family": FAMILY_ACTUATION,
		"era_phase_req": 1,
		"origin_lineage": LINEAGE_VALKREN,
		"tags": ["actuation", "hydraulic", "durability"],
		"prerequisites": [],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_families": [FAMILY_ACTUATION],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.USABLE,
		},
		"diffusion_metadata": {
			"category": CATEGORY_CONVENTIONAL,
			"min_era_phase": 1,
			"default_diffused": true,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL]
		},
		"description": "High-pressure hydraulic actuators suited for heavy armor bearing and stable firing postures."
	})

	register_technology({
		"tech_id": "tech_reinforced_plating",
		"name": "Reinforced Composite Armor Plating",
		"generation": 1,
		"technology_family": FAMILY_BALLISTIC,
		"era_phase_req": 1,
		"origin_lineage": LINEAGE_VALKREN,
		"tags": ["armor", "plating", "ballistic", "reinforced"],
		"prerequisites": ["tech_ballistic_conventional"],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_families": [FAMILY_BALLISTIC],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_CONVENTIONAL,
			"min_era_phase": 1,
			"default_diffused": false,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL],
			"lab_tier_req": 1
		},
		"description": "Heavy rolled homogeneous armor plating with ballistic deflective angling."
	})

	register_technology({
		"tech_id": "tech_relic_excavation_core",
		"name": "Excavated Pre-Calamity Relic Matrix",
		"generation": 1,
		"technology_family": FAMILY_POWER,
		"era_phase_req": 1,
		"origin_lineage": LINEAGE_COMMON,
		"tags": ["relic", "ancient", "excavation", "salvage", "energy"],
		"prerequisites": [],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_families": [FAMILY_POWER],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_EXPERIMENTAL,
			"min_era_phase": 1,
			"default_diffused": false,
			"prototype_only": true,
			"restricted": false,
			"factions": [FACTION_RIVAL],
			"excavation_tier_req": 1
		},
		"description": "Unearthed pre-calamity energy accumulator recovered from ruins excavation dig sites."
	})

	# --- Generation 2: Modernized & Energy Systems ---
	register_technology({
		"tech_id": "tech_modular_energy_interface",
		"name": "Modular Energy Interface Architecture",
		"generation": 2,
		"technology_family": FAMILY_INTERFACE,
		"era_phase_req": 2,
		"origin_lineage": LINEAGE_COMMON,
		"tags": ["interface", "bridge", "energy", "converter"],
		"prerequisites": ["tech_combustion_power"],
		"compatibility_requirements": {
			"min_generation": 1,
			"required_bridge_tags": ["energy_interface"],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_MIXED,
			"min_era_phase": 2,
			"default_diffused": true,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL]
		},
		"description": "Solid-state power converters and optical bus interfaces enabling high-draw beam hardware on older platforms."
	})

	register_technology({
		"tech_id": "tech_beam_weaponry",
		"name": "Focused Particle Beam Weaponry",
		"generation": 2,
		"technology_family": FAMILY_ENERGY,
		"era_phase_req": 2,
		"origin_lineage": LINEAGE_COMMON,
		"tags": ["energy", "beam", "high_heat"],
		"prerequisites": ["tech_modular_energy_interface"],
		"compatibility_requirements": {
			"min_generation": 2,
			"required_families": [FAMILY_ENERGY],
			"required_bridge_tags": ["energy_interface"],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_EXPERIMENTAL,
			"min_era_phase": 2,
			"default_diffused": false,
			"prototype_only": true,
			"restricted": false,
			"factions": [FACTION_RIVAL],
			"lab_tier_req": 2
		},
		"description": "Coherent particle focus emitters designed for piercing hardened composite armor plates."
	})

	register_technology({
		"tech_id": "tech_cryo_cooling",
		"name": "Closed-Loop Cryogenic Cooling",
		"generation": 2,
		"technology_family": FAMILY_COOLING,
		"era_phase_req": 2,
		"origin_lineage": LINEAGE_COMMON,
		"tags": ["cooling", "cryo", "thermal_management"],
		"prerequisites": ["tech_passive_cooling"],
		"compatibility_requirements": {
			"min_generation": 2,
			"required_families": [FAMILY_COOLING],
			"required_bridge_tags": ["cryo_coolant_interface"],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_MIXED,
			"min_era_phase": 2,
			"default_diffused": true,
			"prototype_only": false,
			"restricted": false,
			"factions": [FACTION_ALL]
		},
		"description": "Pressurized sub-zero coolant loops capable of rapidly dissipating weapon discharge spikes."
	})

	# --- Generation 3: Advanced Valkryon & Prototype Architecture ---
	register_technology({
		"tech_id": "tech_valkryon_actuator_chassis",
		"name": "Valkryon Integrated Actuator Lineage",
		"generation": 3,
		"technology_family": FAMILY_ACTUATION,
		"era_phase_req": 3,
		"origin_lineage": LINEAGE_VALKRYON,
		"tags": ["actuation", "valkryon", "advanced", "high_mobility"],
		"prerequisites": ["tech_hydraulic_actuation"],
		"compatibility_requirements": {
			"min_generation": 3,
			"required_lineage": LINEAGE_VALKRYON,
			"required_bridge_tags": ["neural_actuator_bridge"],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_EXPERIMENTAL,
			"min_era_phase": 3,
			"default_diffused": false,
			"prototype_only": true,
			"restricted": false,
			"factions": [FACTION_RIVAL],
			"lab_tier_req": 3
		},
		"description": "Direct synthetic muscle fiber bundles with rapid impulse response and zero fluid-seal fatigue."
	})

	register_technology({
		"tech_id": "tech_high_energy_barrier",
		"name": "Cohesive Deflection Field Architecture",
		"generation": 3,
		"technology_family": FAMILY_ENERGY,
		"era_phase_req": 3,
		"origin_lineage": LINEAGE_VALKRYON,
		"tags": ["energy", "barrier", "valkryon", "omni_shield"],
		"prerequisites": ["tech_beam_weaponry"],
		"compatibility_requirements": {
			"min_generation": 3,
			"required_families": [FAMILY_ENERGY],
			"required_bridge_tags": ["barrier_interface"],
		},
		"discovery_metadata": {
			"base_state": DiscoveryState.UNKNOWN,
		},
		"diffusion_metadata": {
			"category": CATEGORY_EXPERIMENTAL,
			"min_era_phase": 3,
			"default_diffused": false,
			"prototype_only": true,
			"restricted": false,
			"factions": [FACTION_RIVAL],
			"excavation_tier_req": 2
		},
		"description": "Full-envelope reactive plasma deflection matrix capable of absorbing high-velocity kinetic and thermal impacts."
	})


static func _infer_diffusion_category(gen: int, tags: Array) -> String:
	if "prototype" in tags or "relic" in tags or "advanced" in tags or gen >= 3:
		return CATEGORY_EXPERIMENTAL
	if "bridge" in tags or "converter" in tags or "interface" in tags or gen == 2:
		return CATEGORY_MIXED
	return CATEGORY_CONVENTIONAL


static func register_technology(def: Dictionary) -> void:
	init_catalog_if_needed()
	var tid: String = str(def.get("tech_id", "")).strip_edges()
	if tid == "":
		return

	var raw_tags: Array = Array(def.get("tags", []))
	var t_gen: int = int(def.get("generation", 1))
	var era_req: int = int(def.get("era_phase_req", 1))
	var raw_diff: Dictionary = Dictionary(def.get("diffusion_metadata", {}))

	var schematized_diff: Dictionary = {
		"category": str(raw_diff.get("category", _infer_diffusion_category(t_gen, raw_tags))),
		"min_era_phase": int(raw_diff.get("min_era_phase", era_req)),
		"default_diffused": bool(raw_diff.get("default_diffused", era_req <= 1)),
		"prototype_only": bool(raw_diff.get("prototype_only", false)),
		"restricted": bool(raw_diff.get("restricted", false)),
		"factions": Array(raw_diff.get("factions", [FACTION_ALL])),
		"excavation_tier_req": int(raw_diff.get("excavation_tier_req", 0)),
		"lab_tier_req": int(raw_diff.get("lab_tier_req", 0))
	}

	var schematized: Dictionary = {
		"tech_id": tid,
		"name": str(def.get("name", tid)),
		"generation": t_gen,
		"technology_family": str(def.get("technology_family", FAMILY_BALLISTIC)),
		"era_phase_req": era_req,
		"origin_lineage": str(def.get("origin_lineage", LINEAGE_COMMON)),
		"tags": raw_tags,
		"prerequisites": Array(def.get("prerequisites", [])),
		"compatibility_requirements": Dictionary(def.get("compatibility_requirements", {})),
		"discovery_metadata": Dictionary(def.get("discovery_metadata", {})),
		"diffusion_metadata": schematized_diff,
		"description": str(def.get("description", ""))
	}
	_catalog[tid] = schematized


static func get_technology_definition(tech_id: String) -> Dictionary:
	init_catalog_if_needed()
	if _catalog.has(tech_id):
		return _catalog[tech_id].duplicate(true)
	return {}


static func has_technology(tech_id: String) -> bool:
	init_catalog_if_needed()
	return _catalog.has(tech_id)


static func get_all_technologies() -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		res.append(_catalog[k].duplicate(true))
	return res


static func get_technologies_by_family(family: String) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		if _catalog[k].get("technology_family", "") == family:
			res.append(_catalog[k].duplicate(true))
	return res


static func get_technologies_by_generation(generation: int) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		if int(_catalog[k].get("generation", 1)) == generation:
			res.append(_catalog[k].duplicate(true))
	return res


# ===========================================================================
# ERA & WORLD PROGRESSION INTERFACE (Phase 2E-1)
# ===========================================================================

static func _get_current_era_phase() -> int:
	var eps = load("res://scripts/systems/era_progression_system.gd")
	if eps and "current_phase" in eps:
		return int(eps.current_phase)
	return 1


static func _get_rival_system():
	return load("res://scripts/systems/rival_progression_system.gd")


## Queries whether a technology is plausible/available in the current world era phase.
static func is_technology_plausible_in_era(tech_id: String, era_phase: int) -> bool:
	var def := get_technology_definition(tech_id)
	if def.is_empty():
		return false
	var req_phase := int(def.get("era_phase_req", 1))
	return era_phase >= req_phase


## Returns all technologies plausible for a specific era phase.
static func get_plausible_technologies_for_era(era_phase: int) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		if is_technology_plausible_in_era(k, era_phase):
			res.append(_catalog[k].duplicate(true))
	return res


## Authoritatively checks whether a technology has diffused into general world encounter/loot pools.
static func is_technology_diffused_in_world(tech_id: String) -> bool:
	init_catalog_if_needed()
	if not _catalog.has(tech_id):
		return false
	
	if _world_diffusion_overrides.has(tech_id):
		var override_data: Dictionary = _world_diffusion_overrides[tech_id]
		if override_data.has("diffused"):
			return bool(override_data["diffused"])

	var def: Dictionary = _catalog[tech_id]
	var diff_meta: Dictionary = def.get("diffusion_metadata", {})
	
	if bool(diff_meta.get("restricted", false)):
		return false
	
	if bool(diff_meta.get("prototype_only", false)):
		return false

	var min_phase: int = int(diff_meta.get("min_era_phase", def.get("era_phase_req", 1)))
	var cur_phase: int = _get_current_era_phase()
	if cur_phase < min_phase:
		return false

	var prereqs: Array = def.get("prerequisites", [])
	for p in prereqs:
		if not is_technology_diffused_in_world(str(p)):
			return false
			
	return true


## Authoritatively checks whether a technology exists/is active in the world in any form
## (diffused in general pools, active prototype testbed, or possessed by a faction).
static func is_technology_available_in_world(tech_id: String) -> bool:
	init_catalog_if_needed()
	if not _catalog.has(tech_id):
		return false

	if is_technology_diffused_in_world(tech_id):
		return true

	if is_technology_prototype_active(tech_id):
		return true

	if _world_diffusion_overrides.has(tech_id):
		var ov: Dictionary = _world_diffusion_overrides[tech_id]
		if ov.get("available", false):
			return true

	for f in [FACTION_RIVAL, FACTION_CONVOY]:
		if _can_faction_access_technology(f, tech_id):
			return true

	return false


## Checks whether a technology is currently deployed as an active prototype.
static func is_technology_prototype_active(tech_id: String) -> bool:
	if _active_world_prototypes.get(tech_id, false):
		return true
	
	var rps = _get_rival_system()
	if rps:
		if rps.has_method("get_active_prototype_tech_id") and rps.has_method("has_active_prototype"):
			if rps.has_active_prototype() and rps.get_active_prototype_tech_id() == tech_id:
				return true
	return false


## Returns all technologies currently diffused in the world.
static func get_diffused_technologies() -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		if is_technology_diffused_in_world(k):
			res.append(_catalog[k].duplicate(true))
	return res


## Returns all technologies that would be diffused at a given hypothetical/specific era phase.
static func get_diffused_technologies_for_phase(phase: int) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		var def: Dictionary = _catalog[k]
		var diff_meta: Dictionary = def.get("diffusion_metadata", {})
		if bool(diff_meta.get("restricted", false)) or bool(diff_meta.get("prototype_only", false)):
			continue
		var min_phase: int = int(diff_meta.get("min_era_phase", def.get("era_phase_req", 1)))
		if phase >= min_phase:
			var prereqs_ok := true
			for p in def.get("prerequisites", []):
				var p_def: Dictionary = get_technology_definition(str(p))
				var p_min: int = int(p_def.get("diffusion_metadata", {}).get("min_era_phase", p_def.get("era_phase_req", 1)))
				if phase < p_min:
					prereqs_ok = false
					break
			if prereqs_ok:
				res.append(_catalog[k].duplicate(true))
	return res


## Returns all technologies categorized under a specific diffusion category
## (e.g. CATEGORY_CONVENTIONAL, CATEGORY_MIXED, CATEGORY_EXPERIMENTAL).
static func get_technologies_by_diffusion_category(category: String) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		var def: Dictionary = _catalog[k]
		var cat: String = str(def.get("diffusion_metadata", {}).get("category", ""))
		if cat == category:
			res.append(_catalog[k].duplicate(true))
	return res


## Checks internal faction access rules.
static func _can_faction_access_technology(faction_id: String, tech_id: String) -> bool:
	if not _catalog.has(tech_id):
		return false
	
	var def: Dictionary = _catalog[tech_id]
	var diff_meta: Dictionary = def.get("diffusion_metadata", {})
	var allowed_factions: Array = diff_meta.get("factions", [FACTION_ALL])
	
	if is_technology_diffused_in_world(tech_id):
		if FACTION_ALL in allowed_factions or faction_id in allowed_factions:
			return true

	if _faction_technologies.has(faction_id) and tech_id in _faction_technologies[faction_id]:
		return true

	if faction_id == FACTION_RIVAL:
		var rps = _get_rival_system()
		if rps:
			var lab_req: int = int(diff_meta.get("lab_tier_req", 0))
			if lab_req > 0 and rps.has_method("get_lab_tier") and rps.get_lab_tier() >= lab_req:
				return true
			var exc_req: int = int(diff_meta.get("excavation_tier_req", 0))
			if exc_req > 0 and rps.has_method("get_excavation_tier") and rps.get_excavation_tier() >= exc_req:
				return true
			if rps.has_method("get_active_prototype_tech_id") and rps.get_active_prototype_tech_id() == tech_id:
				return true

	return false


## Returns all technologies available to a specific faction.
static func get_faction_available_technologies(faction_id: String) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	for k in _catalog:
		if _can_faction_access_technology(faction_id, k):
			res.append(_catalog[k].duplicate(true))
	return res


## Queries technologies currently eligible for a faction to unlock via research/breakthrough.
## Evaluates:
## 1. Faction eligibility (def.diffusion_metadata.factions contains faction_id or FACTION_ALL)
## 2. Era phase requirement (def.diffusion_metadata.min_era_phase <= EraProgressionSystem.current_phase)
## 3. Prerequisites: Faction must already possess all required prerequisites
## 4. Exclusion: Faction must not already possess the technology
## 5. Optional context filters (branch == "laboratory" or "excavation", category, family)
static func get_eligible_faction_technologies(faction_id: String, context: Dictionary = {}) -> Array:
	init_catalog_if_needed()
	var res: Array = []
	var cur_phase := _get_current_era_phase()
	var branch: String = str(context.get("branch", "")).to_lower()
	var desired_category: String = str(context.get("category", ""))
	var desired_family: String = str(context.get("family", ""))

	for tid in _catalog:
		var def: Dictionary = _catalog[tid]
		var diff_meta: Dictionary = def.get("diffusion_metadata", {})
		
		# 1. Faction eligibility
		var allowed_factions: Array = diff_meta.get("factions", [FACTION_ALL])
		if not (FACTION_ALL in allowed_factions or faction_id in allowed_factions):
			continue
			
		# 2. Era phase requirement
		var min_phase: int = int(diff_meta.get("min_era_phase", def.get("era_phase_req", 1)))
		if cur_phase < min_phase:
			continue
			
		# 3. Must NOT already be possessed by the faction or generally diffused in world
		if has_faction_technology(faction_id, tid) or is_technology_diffused_in_world(tid):
			continue
			
		# 4. Prerequisites: All prerequisites must already be accessible to this faction
		var prereqs_ok := true
		for p in def.get("prerequisites", []):
			if not _can_faction_access_technology(faction_id, str(p)):
				prereqs_ok = false
				break
		if not prereqs_ok:
			continue
			
		# 5. Optional context filters
		if desired_category != "" and str(diff_meta.get("category", "")) != desired_category:
			continue
			
		if desired_family != "" and str(def.get("technology_family", "")) != desired_family:
			continue

		if branch == "laboratory":
			var lab_req: int = int(diff_meta.get("lab_tier_req", 0))
			var fam: String = str(def.get("technology_family", ""))
			var is_lab_family: bool = fam in [FAMILY_ENERGY, FAMILY_INTERFACE, FAMILY_ACTUATION, FAMILY_COOLING, FAMILY_BALLISTIC]
			var is_lab_meta: bool = lab_req > 0 or bool(diff_meta.get("prototype_only", false)) or is_lab_family
			if not is_lab_meta:
				continue
		elif branch == "excavation":
			var exc_req: int = int(diff_meta.get("excavation_tier_req", 0))
			var tags: Array = def.get("tags", [])
			var is_exc_meta: bool = exc_req > 0 or "relic" in tags or "ancient" in tags or "barrier" in tags or "salvage" in tags
			if not is_exc_meta:
				continue

		res.append(def.duplicate(true))

	return res


## Selects a single breakthrough technology for a faction from eligible candidates.
## Uses data-driven metadata rather than a rigid hardcoded ladder.
static func select_breakthrough_technology(faction_id: String, context: Dictionary = {}) -> String:
	var eligible := get_eligible_faction_technologies(faction_id, context)
	if eligible.is_empty():
		return ""
	
	# Prefer technology that directly targets the current branch tier if specified
	var target_tier: int = int(context.get("tier", 0))
	var branch: String = str(context.get("branch", "")).to_lower()
	if target_tier > 0:
		for candidate in eligible:
			var diff_meta: Dictionary = candidate.get("diffusion_metadata", {})
			if branch == "laboratory" and int(diff_meta.get("lab_tier_req", 0)) == target_tier:
				return str(candidate.get("tech_id", ""))
			elif branch == "excavation" and int(diff_meta.get("excavation_tier_req", 0)) == target_tier:
				return str(candidate.get("tech_id", ""))

	# Otherwise return the first valid eligible candidate
	return str(eligible[0].get("tech_id", ""))


## Returns detailed world status dictionary for a technology.
static func get_technology_world_state(tech_id: String) -> Dictionary:
	init_catalog_if_needed()
	if not _catalog.has(tech_id):
		return {
			"tech_id": tech_id,
			"is_registered": false,
			"is_diffused": false,
			"is_available_in_world": false,
			"is_prototype_active": false,
			"diffusion_category": "unknown",
			"factions_with_access": [],
			"era_phase_req": 1,
			"missing_requirements": ["technology_not_found"]
		}

	var def: Dictionary = _catalog[tech_id]
	var diff_meta: Dictionary = def.get("diffusion_metadata", {})
	var factions_access: Array = []
	for f in [FACTION_RIVAL, FACTION_CONVOY]:
		if _can_faction_access_technology(f, tech_id):
			factions_access.append(f)

	return {
		"tech_id": tech_id,
		"is_registered": true,
		"is_diffused": is_technology_diffused_in_world(tech_id),
		"is_available_in_world": is_technology_available_in_world(tech_id),
		"is_prototype_active": is_technology_prototype_active(tech_id),
		"diffusion_category": str(diff_meta.get("category", CATEGORY_CONVENTIONAL)),
		"factions_with_access": factions_access,
		"era_phase_req": int(def.get("era_phase_req", 1)),
		"missing_requirements": get_missing_diffusion_requirements(tech_id)
	}


## Returns array of missing requirement identifiers preventing diffusion in the world.
static func get_missing_diffusion_requirements(tech_id: String, _context: Dictionary = {}) -> Array:
	init_catalog_if_needed()
	if not _catalog.has(tech_id):
		return ["technology_not_found"]

	var def: Dictionary = _catalog[tech_id]
	var diff_meta: Dictionary = def.get("diffusion_metadata", {})
	var missing: Array = []

	var min_phase: int = int(diff_meta.get("min_era_phase", def.get("era_phase_req", 1)))
	var cur_phase: int = _get_current_era_phase()
	if cur_phase < min_phase:
		missing.append("insufficient_era_phase")

	if bool(diff_meta.get("restricted", false)):
		if not _world_diffusion_overrides.get(tech_id, {}).get("diffused", false):
			missing.append("restricted_requires_activation")

	if bool(diff_meta.get("prototype_only", false)):
		if not _world_diffusion_overrides.get(tech_id, {}).get("diffused", false):
			missing.append("prototype_only_not_diffused")

	var prereqs: Array = def.get("prerequisites", [])
	for p in prereqs:
		if not is_technology_diffused_in_world(str(p)):
			missing.append("missing_prerequisite:" + str(p))

	var lab_req: int = int(diff_meta.get("lab_tier_req", 0))
	if lab_req > 0:
		var rps = _get_rival_system()
		if rps and rps.has_method("get_lab_tier") and rps.get_lab_tier() < lab_req:
			missing.append("insufficient_lab_tier")

	var exc_req: int = int(diff_meta.get("excavation_tier_req", 0))
	if exc_req > 0:
		var rps = _get_rival_system()
		if rps and rps.has_method("get_excavation_tier") and rps.get_excavation_tier() < exc_req:
			missing.append("insufficient_excavation_tier")

	return missing


# --- World Diffusion Mutations & Overrides (ZERO impact on Player Discovery) ---

static func activate_technology_diffusion(tech_id: String) -> bool:
	if not has_technology(tech_id):
		return false
	_world_diffusion_overrides[tech_id] = {"diffused": true, "available": true}
	return true


static func deactivate_technology_diffusion(tech_id: String) -> bool:
	if not has_technology(tech_id):
		return false
	_world_diffusion_overrides[tech_id] = {"diffused": false, "available": false}
	return true


static func set_technology_prototype_active(tech_id: String, active: bool) -> void:
	if active:
		_active_world_prototypes[tech_id] = true
	else:
		_active_world_prototypes.erase(tech_id)


static func grant_faction_technology(faction_id: String, tech_id: String) -> void:
	if not _faction_technologies.has(faction_id):
		_faction_technologies[faction_id] = []
	if not _faction_technologies[faction_id].has(tech_id):
		_faction_technologies[faction_id].append(tech_id)


static func has_faction_technology(faction_id: String, tech_id: String) -> bool:
	if not _faction_technologies.has(faction_id):
		return false
	return tech_id in _faction_technologies[faction_id]


static func get_technologies_for_faction(faction_id: String) -> Array:
	if not _faction_technologies.has(faction_id):
		return []
	return _faction_technologies[faction_id].duplicate()


static func reset_world_diffusion_state() -> void:
	_world_diffusion_overrides.clear()
	_active_world_prototypes.clear()
	_faction_technologies.clear()


static func serialize_world_diffusion_state() -> Dictionary:
	return {
		"overrides": _world_diffusion_overrides.duplicate(true),
		"prototypes": _active_world_prototypes.duplicate(true),
		"faction_technologies": _faction_technologies.duplicate(true)
	}


static func deserialize_world_diffusion_state(data: Variant) -> void:
	reset_world_diffusion_state()
	if data is Dictionary:
		var ov = data.get("overrides", {})
		if ov is Dictionary:
			_world_diffusion_overrides = ov.duplicate(true)
		var proto = data.get("prototypes", {})
		if proto is Dictionary:
			_active_world_prototypes = proto.duplicate(true)
		var ftech = data.get("faction_technologies", {})
		if ftech is Dictionary:
			_faction_technologies = ftech.duplicate(true)


# ===========================================================================
# DISCOVERY STATE SYSTEM
# ===========================================================================

static func get_discovery_state(tech_id: String) -> int:
	if _player_discovery.has(tech_id):
		return int(_player_discovery[tech_id])
	var def := get_technology_definition(tech_id)
	if not def.is_empty():
		var meta: Dictionary = def.get("discovery_metadata", {})
		return int(meta.get("base_state", DiscoveryState.UNKNOWN))
	return DiscoveryState.UNKNOWN


static func get_discovery_state_name(tech_id: String) -> String:
	var state := get_discovery_state(tech_id)
	match state:
		DiscoveryState.UNKNOWN:
			return "UNKNOWN"
		DiscoveryState.ENCOUNTERED:
			return "ENCOUNTERED"
		DiscoveryState.SALVAGED:
			return "SALVAGED"
		DiscoveryState.IDENTIFIED:
			return "IDENTIFIED"
		DiscoveryState.RESEARCHED:
			return "RESEARCHED"
		DiscoveryState.USABLE:
			return "USABLE"
	return "UNKNOWN"


static func set_discovery_state(tech_id: String, state: int) -> void:
	_player_discovery[tech_id] = clampi(state, DiscoveryState.UNKNOWN, DiscoveryState.USABLE)


## Monotonically advances discovery state (cannot regress unless force-set).
static func advance_discovery_state(tech_id: String, target_state: int) -> bool:
	var cur := get_discovery_state(tech_id)
	var desired := clampi(target_state, DiscoveryState.UNKNOWN, DiscoveryState.USABLE)
	if desired > cur:
		_player_discovery[tech_id] = desired
		return true
	return false


static func is_technology_usable(tech_id: String) -> bool:
	return get_discovery_state(tech_id) >= DiscoveryState.USABLE


static func serialize_discovery_states() -> Dictionary:
	return _player_discovery.duplicate(true)


static func deserialize_discovery_states(data: Variant) -> void:
	_player_discovery.clear()
	if data is Dictionary:
		for k in data:
			_player_discovery[str(k)] = int(data[k])


static func reset_discovery_states() -> void:
	_player_discovery.clear()


# ===========================================================================
# AUTHORITATIVE COMPATIBILITY EVALUATION
# ===========================================================================

## Resolves raw frame data (Dict, String ID, or Variant) into a normalized frame dictionary.
static func _resolve_frame(frame_data: Variant) -> Dictionary:
	if frame_data is Dictionary:
		return frame_data
	elif frame_data is String:
		var fid: String = str(frame_data)
		if fid != "" and GlobalData:
			var entry: Dictionary = GlobalData.get_frame_catalog_entry(fid)
			if not entry.is_empty():
				return entry
			var entry_name: Dictionary = GlobalData.get_frame_catalog_entry_by_name(fid)
			if not entry_name.is_empty():
				return entry_name
		return {"id": fid, "name": fid}
	return {}


## Authoritatively checks whether a given frame platform can support a technology,
## returning a detailed report with DIRECT, BRIDGED, or INCOMPATIBLE status.
static func evaluate_frame_technology_compatibility(frame_data: Variant, tech_id: String, installed_bridges: Array = []) -> Dictionary:
	var def := get_technology_definition(tech_id)
	if def.is_empty():
		return {
			"status": CompatibilityStatus.INCOMPATIBLE,
			"is_supported": false,
			"active_bridges": [],
			"missing_requirements": ["technology_not_found"],
			"reasons": ["Technology ID '%s' is not registered." % tech_id]
		}

	var frame_dict := _resolve_frame(frame_data)
	var f_lineage := str(frame_dict.get("technology_lineage", LINEAGE_VALKREN)).to_lower()
	var f_gen := int(frame_dict.get("native_generation", 1))
	var f_supported_fams: Array = frame_dict.get("supported_families", ["all"])

	var t_gen := int(def.get("generation", 1))
	var t_family := str(def.get("technology_family", FAMILY_BALLISTIC))
	var t_lineage := str(def.get("origin_lineage", LINEAGE_COMMON)).to_lower()
	var compat_reqs: Dictionary = def.get("compatibility_requirements", {})

	var req_lineage: String = str(compat_reqs.get("required_lineage", "")).to_lower()
	var req_gen: int = int(compat_reqs.get("min_generation", t_gen))
	var req_bridge_tags: Array = compat_reqs.get("required_bridge_tags", [])

	# 1. Test Direct Native Compatibility:
	var direct_gen_ok := (f_gen >= req_gen)
	var direct_fam_ok := ("all" in f_supported_fams or t_family in f_supported_fams)
	var direct_lineage_ok := (req_lineage == "" or req_lineage == LINEAGE_COMMON or f_lineage == req_lineage)

	if direct_gen_ok and direct_fam_ok and direct_lineage_ok:
		return {
			"status": CompatibilityStatus.DIRECT,
			"is_supported": true,
			"active_bridges": [],
			"missing_requirements": [],
			"reasons": ["Native frame architecture directly supports technology generation and family."]
		}

	# 2. Test Bridged Compatibility via Installed Technology Bridges:
	var active_bridges: Array = []
	var remaining_missing: Array = []
	var reasons: Array = []

	# Gather bridge capabilities
	var bridge_max_gen := f_gen
	var bridged_families: Array = []
	var provided_bridge_tags: Array = []

	for b in installed_bridges:
		var b_dict: Dictionary = b if b is Dictionary else {}
		if b_dict.is_empty() and b is String:
			# If a string module_id is passed, query FrameModuleSystem if available
			var mod_def := FrameModuleSystem.get_module(str(b))
			if not mod_def.is_empty():
				b_dict = mod_def.get("bridge_capabilities", {})
		else:
			b_dict = b_dict.get("bridge_capabilities", b_dict)

		var up_to := int(b_dict.get("bridges_generation_up_to", 0))
		if up_to > bridge_max_gen:
			bridge_max_gen = up_to

		var b_fams = b_dict.get("bridges_families", [])
		if b_fams is Array:
			for bf in b_fams:
				if not bridged_families.has(bf):
					bridged_families.append(bf)

		var b_tags = b_dict.get("bridge_tags", [])
		if b_tags is Array:
			for bt in b_tags:
				if not provided_bridge_tags.has(bt):
					provided_bridge_tags.append(bt)

	# Check Generation requirement
	var gen_bridged := (f_gen >= req_gen) or (bridge_max_gen >= req_gen)
	if not gen_bridged:
		remaining_missing.append("insufficient_generation")
		reasons.append("Frame generation (%d) and bridge limit (%d) below required (%d)." % [f_gen, bridge_max_gen, req_gen])

	# Check Family requirement
	var fam_bridged := direct_fam_ok or ("all" in bridged_families) or (t_family in bridged_families)
	if not fam_bridged:
		remaining_missing.append("unsupported_family")
		reasons.append("Technology family '%s' is not supported by frame or active bridge modules." % t_family)

	# Check Specific Bridge Tags
	for req_tag in req_bridge_tags:
		var tag_str := str(req_tag)
		if not provided_bridge_tags.has(tag_str):
			# If frame natively supports the lineage and generation, specific bridge tag may not be required
			if not (direct_gen_ok and direct_lineage_ok):
				remaining_missing.append("missing_bridge_tag:" + tag_str)
				reasons.append("Requires bridge module providing tag '%s'." % tag_str)

	# Check Lineage constraint
	if req_lineage != "" and req_lineage != LINEAGE_COMMON and f_lineage != req_lineage:
		# Can only bridge lineage if a bridge explicitly provides lineage adapter tag
		var lineage_bridge_tag := req_lineage + "_interface"
		if not provided_bridge_tags.has(lineage_bridge_tag) and not provided_bridge_tags.has("universal_interface"):
			remaining_missing.append("incompatible_lineage:" + req_lineage)
			reasons.append("Frame lineage '%s' does not match required '%s', no compatible adapter installed." % [f_lineage, req_lineage])

	if remaining_missing.is_empty():
		return {
			"status": CompatibilityStatus.BRIDGED,
			"is_supported": true,
			"active_bridges": installed_bridges,
			"missing_requirements": [],
			"reasons": ["Technology successfully bridged to frame via installed module interfaces."]
		}

	return {
		"status": CompatibilityStatus.INCOMPATIBLE,
		"is_supported": false,
		"active_bridges": [],
		"missing_requirements": remaining_missing,
		"reasons": reasons
	}


## Quick boolean query for frame technology support.
static func can_frame_support_technology(frame_data: Variant, tech_id: String, installed_bridges: Array = []) -> bool:
	var report := evaluate_frame_technology_compatibility(frame_data, tech_id, installed_bridges)
	return bool(report.get("is_supported", false))


## Returns requirements dictionary for a given technology.
static func get_technology_requirements(tech_id: String) -> Dictionary:
	var def := get_technology_definition(tech_id)
	if def.is_empty():
		return {}
	return def.get("compatibility_requirements", {}).duplicate(true)


## Returns array of missing requirement identifiers.
static func get_missing_requirements(frame_data: Variant, tech_id: String, installed_bridges: Array = []) -> Array:
	var report := evaluate_frame_technology_compatibility(frame_data, tech_id, installed_bridges)
	return report.get("missing_requirements", [])


## Checks if a module can act as a bridge for a specific technology.
static func can_module_bridge_technology(module_data: Variant, tech_id: String) -> bool:
	var b_dict: Dictionary = {}
	if module_data is Dictionary:
		b_dict = module_data.get("bridge_capabilities", module_data)
	elif module_data is String:
		var mod_def := FrameModuleSystem.get_module(str(module_data))
		b_dict = mod_def.get("bridge_capabilities", {})
	if b_dict.is_empty():
		return false

	var def := get_technology_definition(tech_id)
	if def.is_empty():
		return false

	var t_gen := int(def.get("generation", 1))
	var t_family := str(def.get("technology_family", ""))
	var compat_reqs: Dictionary = def.get("compatibility_requirements", {})
	var req_tags: Array = compat_reqs.get("required_bridge_tags", [])

	var bridges_gen := int(b_dict.get("bridges_generation_up_to", 0)) >= t_gen
	var bridges_fam := false
	var fams = b_dict.get("bridges_families", [])
	if fams is Array:
		bridges_fam = ("all" in fams) or (t_family in fams)

	var has_tag := false
	var b_tags = b_dict.get("bridge_tags", [])
	if b_tags is Array:
		for rt in req_tags:
			if b_tags.has(rt):
				has_tag = true
				break

	return (bridges_gen and bridges_fam) or has_tag


## Evaluates equipment item (e.g. weapon) technology compatibility.
static func can_equipment_use_technology(equipment_data: Variant, tech_id: String) -> bool:
	if not has_technology(tech_id):
		return false
	if equipment_data is Dictionary:
		var eq_tech := str(equipment_data.get("tech_id", ""))
		if eq_tech != "" and eq_tech == tech_id:
			return true
	return true
