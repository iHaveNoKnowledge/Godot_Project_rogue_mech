class_name FrameSystem
extends RefCounted

## ---------------------------------------------------------------------------
## FRAME SYSTEM — Authoritative Structural Architecture (Phase 2B-1)
##
## FRAME is the inner skeleton that physically supports:
## - ARMOR (mounted on frame)
## - MODULES (installed into frame sockets)
## - BACKPACK (mounted to frame core)
## - GENERATOR (housed within frame core)
## - WEAPONS (carried by frame limbs and hardpoints)
##
## This system acts as the single source of truth for querying and managing
## frame capabilities, compatibility, structural stats, and instances.
## ---------------------------------------------------------------------------

# Default module sockets per slot when not overridden by frame definition
const DEFAULT_SOCKET_COUNTS: Dictionary = {
	"head": 1,
	"body": 3,
	"torso": 3,
	"arm_left": 1,
	"arm_right": 1,
	"leg_left": 1,
	"leg_right": 1,
}

# Recognized Frame Tags (metadata for current and future mechanics)
const TAG_LIGHT := "light"
const TAG_MEDIUM := "medium"
const TAG_HEAVY := "heavy"
const TAG_ASSAULT := "assault"
const TAG_RECON := "recon"
const TAG_SUPPORT := "support"
const TAG_EXPERIMENTAL := "experimental"
const TAG_LEGACY := "legacy"


# ===========================================================================
# DEFINITION LOOKUP & RESOLUTION
# ===========================================================================

## Looks up an immutable frame definition from the catalog by ID.
static func get_frame_definition(frame_id: String) -> Dictionary:
	if frame_id == "":
		return {}
	return GlobalData.get_frame_catalog_entry(frame_id)


## Looks up an immutable frame definition by display name.
static func get_frame_definition_by_name(frame_name: String) -> Dictionary:
	if frame_name == "":
		return {}
	return GlobalData.get_frame_catalog_entry_by_name(frame_name)


## Internal helper to resolve any frame reference (ID, name, or Dictionary)
## into a fully schematized Dictionary.
static func _resolve_frame_dict(frame_data: Variant, slot_hint: String = "") -> Dictionary:
	if frame_data is Dictionary:
		return ensure_frame_instance_schema(frame_data, slot_hint)
	elif frame_data is String:
		var fid := str(frame_data)
		if fid == "":
			if slot_hint != "":
				return get_equipped_frame(slot_hint)
			return get_equipped_frame("body")
		var def := get_frame_definition(fid)
		if not def.is_empty():
			return def
		var def_name := get_frame_definition_by_name(fid)
		if not def_name.is_empty():
			return def_name
		return ensure_frame_instance_schema({"id": fid, "name": fid}, slot_hint)
	return {}


# ===========================================================================
# STAT GETTERS (Authoritative Frame Queries)
# ===========================================================================

## Returns structural Frame HP (internal skeleton health).
static func get_frame_hp(frame_data: Variant) -> float:
	var dict := _resolve_frame_dict(frame_data)
	return float(dict.get("hp", 40.0))


## Returns the physical weight of the frame in kg.
static func get_frame_weight(frame_data: Variant) -> float:
	var dict := _resolve_frame_dict(frame_data)
	return float(dict.get("weight", 4.0))


## Returns the frame's carry capacity contribution (maps to carry_bonus).
static func get_frame_carry_capacity(frame_data: Variant) -> float:
	var dict := _resolve_frame_dict(frame_data)
	return float(dict.get("carry_bonus", 0.0))


## Returns recoil resistance (dampens weapon recoil impulses).
static func get_frame_recoil_resistance(frame_data: Variant) -> float:
	var dict := _resolve_frame_dict(frame_data)
	return float(dict.get("recoil_resistance", 0.0))


## Returns maximum armor structural capacity (Phase 1 extensibility field).
static func get_frame_max_armor_capacity(frame_data: Variant) -> float:
	var dict := _resolve_frame_dict(frame_data)
	if dict.has("max_armor_capacity"):
		return float(dict["max_armor_capacity"])
	return get_frame_hp(frame_data) * 2.0


## Returns maximum armor weight supported by this frame segment.
static func get_frame_max_armor_weight(frame_data: Variant) -> float:
	var dict := _resolve_frame_dict(frame_data)
	if dict.has("max_armor_weight"):
		return float(dict["max_armor_weight"])
	return get_frame_weight(frame_data) * 2.5


## Returns the number of module sockets supported by this frame for a slot.
static func get_frame_module_slots(frame_data: Variant, slot: String = "") -> int:
	var dict := _resolve_frame_dict(frame_data, slot)
	var norm_slot := slot.to_lower().strip_edges()
	if norm_slot == "torso":
		norm_slot = "body"

	if dict.has("module_slots"):
		var ms = dict["module_slots"]
		if ms is int or ms is float:
			return int(ms)
		elif ms is Dictionary:
			if norm_slot != "" and ms.has(norm_slot):
				return int(ms[norm_slot])
			elif ms.has("body"):
				return int(ms["body"])
	if dict.has("sockets"):
		return int(dict["sockets"])

	return int(DEFAULT_SOCKET_COUNTS.get(norm_slot, 1))


## Returns generator compatibility list (IDs or ["all"]).
static func get_frame_generator_compatibility(frame_data: Variant) -> Array:
	var dict := _resolve_frame_dict(frame_data, "body")
	var compat = dict.get("generator_compatibility", ["all"])
	return Array(compat) if compat is Array else ["all"]


## Returns backpack compatibility list (IDs or ["all"]).
static func get_frame_backpack_compatibility(frame_data: Variant) -> Array:
	var dict := _resolve_frame_dict(frame_data, "body")
	var compat = dict.get("backpack_compatibility", ["all"])
	return Array(compat) if compat is Array else ["all"]


## Returns metadata tags associated with this frame.
static func get_frame_tags(frame_data: Variant) -> Array:
	var dict := _resolve_frame_dict(frame_data)
	var tags = dict.get("frame_tags", [])
	return Array(tags) if tags is Array else []


# ===========================================================================
# COMPATIBILITY CHECKS
# ===========================================================================

## Authoritatively checks whether a generator can be installed into this frame.
static func can_equip_generator(frame_data: Variant, generator_id: String) -> bool:
	var compat := get_frame_generator_compatibility(frame_data)
	if "all" in compat:
		return true
	var gid := generator_id.to_lower().strip_edges()
	for entry in compat:
		if str(entry).to_lower().strip_edges() == gid:
			return true
	return false


## Authoritatively checks whether a backpack can be mounted to this frame.
static func can_equip_backpack(frame_data: Variant, backpack_id: String) -> bool:
	var compat := get_frame_backpack_compatibility(frame_data)
	if "all" in compat:
		return true
	var bid := backpack_id.to_lower().strip_edges()
	for entry in compat:
		if str(entry).to_lower().strip_edges() == bid:
			return true
	return false


# ===========================================================================
# INSTANCE LIFECYCLE & MODIFICATION
# ===========================================================================

## Instantiates a frame instance with base definition, modifications, and unlocked capabilities.
static func make_frame_instance(frame_id: String, modifications: Array = [], unlocked_capabilities: Array = []) -> Dictionary:
	var def := get_frame_definition(frame_id)
	var inst := def.duplicate(true) if not def.is_empty() else {"id": frame_id, "name": frame_id}
	inst["base_frame_id"] = frame_id
	inst["modifications"] = modifications.duplicate(true)
	inst["unlocked_capabilities"] = unlocked_capabilities.duplicate(true)
	return ensure_frame_instance_schema(inst)


## Ensures all standard frame instance fields are present with safe defaults.
static func ensure_frame_instance_schema(data: Dictionary, slot_hint: String = "") -> Dictionary:
	return GlobalData.ensure_frame_data_schema(data, slot_hint)


## Returns the currently equipped frame instance for a specific slot.
static func get_equipped_frame(slot: String) -> Dictionary:
	if GlobalData and GlobalData.weapons and ("equipped_frames" in GlobalData.weapons):
		var f = GlobalData.weapons.equipped_frames.get(slot, {})
		if f is Dictionary and not f.is_empty():
			return ensure_frame_instance_schema(f, slot)
	return {}


## Equips a frame instance into the specified slot.
static func equip_frame(slot: String, frame_instance: Dictionary) -> void:
	if GlobalData and GlobalData.weapons:
		var schematized := ensure_frame_instance_schema(frame_instance, slot)
		GlobalData.weapons.equipped_frames[slot] = schematized


# ===========================================================================
# AGGREGATE SYSTEM QUERIES
# ===========================================================================

## Total base Frame HP across all 6 equipped frame slots.
static func get_total_frame_hp() -> float:
	var total := 0.0
	for slot in GlobalData.MECHA_SLOTS:
		var f := get_equipped_frame(slot)
		if not f.is_empty():
			total += get_frame_hp(f)
	return total


## Total Frame weight across all 6 equipped frame slots.
static func get_total_frame_weight() -> float:
	var total := 0.0
	for slot in GlobalData.MECHA_SLOTS:
		var f := get_equipped_frame(slot)
		if not f.is_empty():
			total += get_frame_weight(f)
	return total


## Total carry capacity bonus provided by all equipped frames.
static func get_total_frame_carry_bonus() -> float:
	var total := 0.0
	for slot in GlobalData.MECHA_SLOTS:
		var f := get_equipped_frame(slot)
		if not f.is_empty():
			total += get_frame_carry_capacity(f)
	return total


## Average recoil resistance across equipped arm frames (or 0.0 if neutral).
static func get_total_recoil_resistance() -> float:
	var total := 0.0
	var count := 0
	for arm in ["arm_left", "arm_right"]:
		var f := get_equipped_frame(arm)
		if not f.is_empty():
			total += get_frame_recoil_resistance(f)
			count += 1
	return total / maxf(float(count), 1.0)


## Preserves existing arm-power heavy weapon gating.
static func get_arm_power(side: String) -> float:
	return GlobalData.get_arm_power(side)


# Compatibility evaluation status
enum CompatibilityStatus {
	INCOMPATIBLE = 0,
	DIRECT = 1,
	BRIDGED = 2
}

# ===========================================================================
# PHYSICAL HARDWARE COMPATIBILITY EVALUATION (FrameSystem Authority)
# ===========================================================================

## Returns the architectural technology lineage of this frame (e.g. "valkren", "valkryon").
static func get_frame_technology_lineage(frame_data: Variant) -> String:
	var dict := _resolve_frame_dict(frame_data)
	return str(dict.get("technology_lineage", "valkren"))


## Returns the native architecture generation of this frame (e.g. 1, 2, 3).
static func get_frame_native_generation(frame_data: Variant) -> int:
	var dict := _resolve_frame_dict(frame_data)
	return int(dict.get("native_generation", 1))


## Returns the supported technology families array for this frame.
static func get_frame_supported_families(frame_data: Variant) -> Array:
	var dict := _resolve_frame_dict(frame_data)
	var fams = dict.get("supported_families", ["all"])
	return Array(fams) if fams is Array else ["all"]


## Resolves hardware/technology requirement specifications.
## Can accept a tech_id (String) and query TechnologySystem, or a Dictionary directly.
static func _resolve_hardware_requirements(req_data: Variant) -> Dictionary:
	if req_data is Dictionary:
		return req_data
	elif req_data is String:
		var tid := str(req_data)
		var ts = load("res://scripts/systems/technology_system.gd")
		if ts:
			var def: Dictionary = ts.get_technology_definition(tid)
			if not def.is_empty():
				var compat_reqs: Dictionary = def.get("compatibility_requirements", {})
				var t_gen: int = int(def.get("generation", 1))
				return {
					"tech_id": tid,
					"generation": t_gen,
					"min_generation": int(compat_reqs.get("min_generation", t_gen)),
					"technology_family": str(def.get("technology_family", "ballistic")),
					"origin_lineage": str(def.get("origin_lineage", "common")).to_lower(),
					"required_lineage": str(compat_reqs.get("required_lineage", "")).to_lower(),
					"required_bridge_tags": Array(compat_reqs.get("required_bridge_tags", []))
				}
	return {}


## Authoritatively evaluates physical hardware compatibility between a frame platform and hardware requirements.
## FrameSystem is the sole authority for physical compatibility.
static func evaluate_hardware_compatibility(frame_data: Variant, hardware_requirements_or_tech_id: Variant, installed_bridges: Array = []) -> Dictionary:
	var reqs := _resolve_hardware_requirements(hardware_requirements_or_tech_id)
	if reqs.is_empty():
		return {
			"status": CompatibilityStatus.INCOMPATIBLE,
			"is_supported": false,
			"active_bridges": [],
			"missing_requirements": ["hardware_requirements_not_found"],
			"reasons": ["Hardware specification or technology definition not found."]
		}

	var frame_dict := _resolve_frame_dict(frame_data)
	var f_lineage := str(frame_dict.get("technology_lineage", "valkren")).to_lower()
	var f_gen := int(frame_dict.get("native_generation", 1))
	var f_supported_fams: Array = frame_dict.get("supported_families", ["all"])

	var req_gen: int = int(reqs.get("min_generation", reqs.get("generation", 1)))
	var t_family: String = str(reqs.get("technology_family", "ballistic"))
	var req_lineage: String = str(reqs.get("required_lineage", "")).to_lower()
	var req_bridge_tags: Array = reqs.get("required_bridge_tags", [])

	# 1. Test Direct Native Compatibility:
	var direct_gen_ok := (f_gen >= req_gen)
	var direct_fam_ok := ("all" in f_supported_fams or t_family in f_supported_fams)
	var direct_lineage_ok := (req_lineage == "" or req_lineage == "common" or f_lineage == req_lineage)

	if direct_gen_ok and direct_fam_ok and direct_lineage_ok:
		return {
			"status": CompatibilityStatus.DIRECT,
			"is_supported": true,
			"active_bridges": [],
			"missing_requirements": [],
			"reasons": ["Native frame architecture directly supports hardware generation and family."]
		}

	# 2. Test Bridged Compatibility via Installed Technology Bridges:
	var active_bridges: Array = []
	var remaining_missing: Array = []
	var reasons: Array = []

	var bridge_max_gen := f_gen
	var bridged_families: Array = []
	var provided_bridge_tags: Array = []

	var mod_sys = load("res://scripts/systems/frame_module_system.gd")

	for b in installed_bridges:
		var b_dict: Dictionary = b if b is Dictionary else {}
		if b_dict.is_empty() and b is String and mod_sys:
			var mod_def: Dictionary = mod_sys.get_module(str(b))
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

	var gen_bridged := (f_gen >= req_gen) or (bridge_max_gen >= req_gen)
	if not gen_bridged:
		remaining_missing.append("insufficient_generation")
		reasons.append("Frame generation (%d) and bridge limit (%d) below required (%d)." % [f_gen, bridge_max_gen, req_gen])

	var fam_bridged := direct_fam_ok or ("all" in bridged_families) or (t_family in bridged_families)
	if not fam_bridged:
		remaining_missing.append("unsupported_family")
		reasons.append("Hardware family '%s' is not supported by frame or active bridge modules." % t_family)

	for req_tag in req_bridge_tags:
		var tag_str := str(req_tag)
		if not provided_bridge_tags.has(tag_str):
			if not (direct_gen_ok and direct_lineage_ok):
				remaining_missing.append("missing_bridge_tag:" + tag_str)
				reasons.append("Requires bridge module providing tag '%s'." % tag_str)

	if req_lineage != "" and req_lineage != "common" and f_lineage != req_lineage:
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
			"reasons": ["Hardware successfully bridged to frame via installed module interfaces."],
			"required_bridge_summary": ""
		}

	var bridge_summary: String = resolve_bridge_requirement_summary(remaining_missing, reqs)

	return {
		"status": CompatibilityStatus.INCOMPATIBLE,
		"is_supported": false,
		"active_bridges": [],
		"missing_requirements": remaining_missing,
		"reasons": reasons,
		"required_bridge_summary": bridge_summary
	}


## Authoritatively resolves human-readable requirement descriptions for missing hardware/bridge capabilities.
static func resolve_bridge_requirement_summary(missing_requirements: Array, hardware_reqs: Dictionary) -> String:
	var req_parts: Array[String] = []
	var req_gen: int = int(hardware_reqs.get("min_generation", hardware_reqs.get("generation", 1)))
	var t_family: String = str(hardware_reqs.get("technology_family", ""))
	var req_lineage: String = str(hardware_reqs.get("required_lineage", "")).to_lower()

	for missing in missing_requirements:
		var m_str := str(missing)
		if m_str == "unsupported_family":
			if t_family == "energy":
				req_parts.append("Energy Weapon Bridge (e.g. Modular Energy Bridge Interface)")
			elif t_family == "cooling":
				req_parts.append("Cryo Coolant Bridge (e.g. Cryo Heatsink Loop)")
			elif t_family != "":
				req_parts.append("%s Architecture Bridge Module" % t_family.capitalize())
		elif m_str == "insufficient_generation":
			req_parts.append("Gen %d+ Bridge Module or Gen %d+ Frame" % [req_gen, req_gen])
		elif m_str.begins_with("missing_bridge_tag:"):
			var tag := m_str.trim_prefix("missing_bridge_tag:")
			if tag == "energy_interface":
				if not req_parts.has("Energy Weapon Bridge (e.g. Modular Energy Bridge Interface)"):
					req_parts.append("Energy Interface Bridge (Modular Energy Bridge Interface)")
			elif tag == "cryo_coolant_interface":
				if not req_parts.has("Cryo Coolant Bridge (e.g. Cryo Heatsink Loop)"):
					req_parts.append("Cryo Coolant Interface Bridge (Cryo Heatsink Loop)")
			else:
				req_parts.append("%s Interface Module" % tag.replace("_", " ").capitalize())
		elif m_str.begins_with("incompatible_lineage:"):
			var lin := m_str.trim_prefix("incompatible_lineage:")
			req_parts.append("%s Lineage Adapter Module" % lin.capitalize())

	if req_parts.is_empty():
		return "Compatible Frame Bridge Module or Upgraded Frame"
	return " | ".join(req_parts)


## Evaluates whether this frame can physically support given hardware or technology requirements.
static func can_support_hardware(frame_data: Variant, hardware_requirements_or_tech_id: Variant, installed_bridges: Array = []) -> bool:
	var report := evaluate_hardware_compatibility(frame_data, hardware_requirements_or_tech_id, installed_bridges)
	return bool(report.get("is_supported", false))


## Convenience alias for technology compatibility queries.
static func can_support_technology(frame_data: Variant, tech_id: String, installed_bridges: Array = []) -> bool:
	return can_support_hardware(frame_data, tech_id, installed_bridges)


## Convenience alias returning full report.
static func evaluate_technology_compatibility(frame_data: Variant, tech_id: String, installed_bridges: Array = []) -> Dictionary:
	return evaluate_hardware_compatibility(frame_data, tech_id, installed_bridges)
