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

# In-memory technology catalog and discovery state
static var _catalog: Dictionary = {}
static var _player_discovery: Dictionary = {}
static var _initialized: bool = false


# ===========================================================================
# CATALOG INITIALIZATION & REGISTRATION
# ===========================================================================

static func init_catalog_if_needed() -> void:
	if _initialized and not _catalog.is_empty():
		return
	_catalog.clear()
	_initialized = true

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
		"description": "High-pressure hydraulic actuators suited for heavy armor bearing and stable firing postures."
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
		"description": "Full-envelope reactive plasma deflection matrix capable of absorbing high-velocity kinetic and thermal impacts."
	})


static func register_technology(def: Dictionary) -> void:
	init_catalog_if_needed()
	var tid: String = str(def.get("tech_id", "")).strip_edges()
	if tid == "":
		return

	var schematized: Dictionary = {
		"tech_id": tid,
		"name": str(def.get("name", tid)),
		"generation": int(def.get("generation", 1)),
		"technology_family": str(def.get("technology_family", FAMILY_BALLISTIC)),
		"era_phase_req": int(def.get("era_phase_req", 1)),
		"origin_lineage": str(def.get("origin_lineage", LINEAGE_COMMON)),
		"tags": Array(def.get("tags", [])),
		"prerequisites": Array(def.get("prerequisites", [])),
		"compatibility_requirements": Dictionary(def.get("compatibility_requirements", {})),
		"discovery_metadata": Dictionary(def.get("discovery_metadata", {})),
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
# ERA & WORLD PROGRESSION INTERFACE
# ===========================================================================

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
