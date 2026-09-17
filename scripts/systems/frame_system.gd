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


## Preserves existing arm-frame heavy weapon power gating.
static func get_arm_power(side: String) -> float:
	return GlobalData.get_arm_power(side)
