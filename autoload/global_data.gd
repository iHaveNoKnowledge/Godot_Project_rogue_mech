extends Node

var chassis_id: String = "standard"
var equipped_parts: Dictionary = {}
var attachments: Array = []

# Built mech roster. A hangar entry is a saved loadout, not a generated enemy
# capsule: it references the owned armor instances and frame catalog entries
# used to assemble that mech. The active entry mirrors the live loadout above.
const HANGAR_MAX_SLOTS := 6
var hangar_mechs: Array = []
var active_hangar_mech_id: String = ""

# ==============================================================================
# CATALOG DATABASE — static item definitions, loaded from resources/data/mech_catalogs.tres
# Single source of truth for all stock items (armor, chassis, frames, attachments).
# Inventory (equipped parts/frames) persists only id references + instance state
# and resolves the static stats back through these catalogs at load time.
# ==============================================================================
var armor_catalog: Dictionary = {}
var chassis_catalog: Dictionary = {}
var frame_catalog: Dictionary = {}
var attachment_catalog: Array = []

# Fleet / research catalog (blueprints for allied units and high-tier gear).
var research_blueprints: Array = []
var ally_unit_templates: Dictionary = {}

# Run theme / event catalogs (single source of truth for theme starts, event
# pools and per-theme endings). Loaded from run_theme_catalogs.tres and
# run_events.tres.
var run_themes: Array = []
var run_events: Array = []


func _load_catalogs() -> void:
	var db = load("res://resources/data/mech_catalogs.tres") as CatalogData
	if db == null:
		push_error("Failed to load mech_catalogs.tres")
		return
	armor_catalog = db.armor_catalog
	chassis_catalog = db.chassis_catalog
	frame_catalog = db.frame_catalog
	attachment_catalog = db.attachment_catalog

	var research_db = load("res://resources/data/research_catalogs.tres") as ResearchCatalogData
	if research_db == null:
		push_error("Failed to load research_catalogs.tres")
		return
	research_blueprints = research_db.research_projects
	for template in research_db.ally_unit_templates:
		ally_unit_templates[template.get("id", "")] = template

	var rt = load("res://resources/data/run_theme_catalogs.tres") as RunThemeCatalogData
	if rt == null:
		push_error("Failed to load run_theme_catalogs.tres")
	else:
		run_themes = rt.themes

	var re = load("res://resources/data/run_events.tres") as RunEventCatalogData
	if re == null:
		push_error("Failed to load run_events.tres")
	else:
		run_events = re.events


# --- Catalog lookups (by id) ---

func get_armor_catalog_entry(part_id: String) -> Dictionary:
	for slot in armor_catalog:
		for entry in armor_catalog[slot]:
			if entry.get("id", "") == part_id:
				return entry
	return {}


func get_frame_catalog_entry(frame_id: String) -> Dictionary:
	for slot in frame_catalog:
		for entry in frame_catalog[slot]:
			if entry.get("id", "") == frame_id:
				return entry
	return {}


func get_frame_catalog_entry_by_name(frame_name: String) -> Dictionary:
	for slot in frame_catalog:
		for entry in frame_catalog[slot]:
			if entry.get("name", "") == frame_name:
				return entry
	return {}


func is_catalog_armor_id(part_id: String) -> bool:
	return not get_armor_catalog_entry(part_id).is_empty()


func is_catalog_frame_id(frame_id: String) -> bool:
	return not get_frame_catalog_entry(frame_id).is_empty()


func _ready() -> void:
	_load_catalogs()
	_ensure_default_frames()
	ensure_default_equipped_parts()
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.friendly_damage_received.connect(_on_friendly_damage_received)


# Research timers advance with turn progress: each board move = 1 point,
# each completed combat = 2 points.
func _on_tile_entered(_tile_pos: Vector2i, _tile_data: Node) -> void:
	tick_research(1)


func _on_combat_ended(victory: bool) -> void:
	# Finalize combat damage stats before any tech/reputation logic reads them.
	_compute_last_combat_damage_ratio()
	# A raid on the enemy research node is not a normal battle: winning destroys
	# the node (only a partial grunt upgrade for them), and it never escalates
	# the enemy tech tier.
	if GameManager.combat_node_type == "enemy_base":
		if victory:
			destroy_enemy_base()
		return
	on_combat_ended_for_tech(victory)
	if victory:
		sync_equipped_armor_durability()
		tick_research(2)


func _on_friendly_damage_received(raw_damage: float) -> void:
	if raw_damage > 0.0:
		_combat_friendly_damage += raw_damage


# Initialise equipped_parts from armor_catalog[slot][0] (first/default entry per slot).
# Uses armor_catalog as single source of truth — no duplicated data.
func ensure_default_equipped_parts() -> void:
	if not equipped_parts.is_empty():
		return
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		if armor_catalog.has(slot) and armor_catalog[slot].size() > 0:
			var pid = armor_catalog[slot][0].get("id", "")
			if pid == "":
				continue
			var inst := make_armor_instance_from_catalog(pid)
			if not inst.is_empty():
				equip_armor_instance(inst["uid"], slot)


# -----------------------------------------------------------------------------
# ARMOR INSTANCE INVENTORY
# Each owned armor piece is a unique instance (uid) with its own durability and
# upgrade level. `part_damage[slot]` remains the live combat damage cache of the
# currently equipped instance; instance.durability is the persistent source for
# everything sitting in the inventory (equipped included, kept in sync).
# -----------------------------------------------------------------------------

func _new_uid(prefix: String) -> String:
	return "%s_%d_%d" % [prefix, Time.get_ticks_usec(), randi() % 0xFFFFF]


func get_armor_catalog_slot(part_id: String) -> String:
	for slot in armor_catalog:
		for entry in armor_catalog[slot]:
			if entry.get("id", "") == part_id:
				return slot
	return ""


# Creates a fresh instance from a catalog template and adds it to armor_inventory.
func make_armor_instance_from_catalog(part_id: String) -> Dictionary:
	var entry := get_armor_catalog_entry(part_id)
	if entry.is_empty():
		return {}
	var instance := entry.duplicate(true)
	instance["uid"] = _new_uid("a")
	instance["db_id"] = entry.get("id", "")
	instance["slot"] = get_armor_catalog_slot(part_id)
	instance["durability"] = 1.0
	instance["upgrade_level"] = 1
	instance["equipped"] = false
	armor_inventory.append(instance)
	return instance


func get_armor_instance(uid: String) -> Dictionary:
	for inst in armor_inventory:
		if inst.get("uid", "") == uid:
			return inst
	return {}


# Extracts hp/armor/weight floats from a catalog entry (shared by cost formulas).
func _get_armor_cost_stats(entry: Dictionary) -> Dictionary:
	return {
		"hp": part_stat(entry, "hp", 30.0),
		"armor": part_stat(entry, "armor", 15.0),
		"weight": part_stat(entry, "weight", 4.0)
	}


# Scrap material cost to craft a catalog armor entry (derived from its stats).
func get_armor_scrap_cost(entry: Dictionary) -> int:
	var s := _get_armor_cost_stats(entry)
	return maxi(1, int(ceil((s.hp + s.armor * 1.5 + s.weight * 2.0) / 20.0)))


# Credit cost to craft a catalog armor entry (derived from its stats).
func get_armor_credit_cost(entry: Dictionary) -> int:
	var s := _get_armor_cost_stats(entry)
	return maxi(1, int(ceil((s.hp + s.armor + s.weight) / 15.0)))


# True when a catalog armor entry is a gundam-tier part that must first be
# researched (its matching research project completed) before it can be crafted.
func entry_is_blueprint_locked(entry: Dictionary) -> bool:
	if not bool(entry.get("blueprint_only", false)):
		return false
	var blueprint_id := str(entry.get("blueprint_id", ""))
	return blueprint_id == "" or not is_research_completed(blueprint_id)


# Attempts to craft a fresh armor instance from the catalog, spending scrap + credits.
# Returns the new instance on success, or an empty Dictionary on any failure
# (unknown id / insufficient scrap / insufficient credits / blueprint not researched).
func try_craft_armor_from_catalog(part_id: String) -> Dictionary:
	var entry := get_armor_catalog_entry(part_id)
	if entry.is_empty():
		return {}
	if entry_is_blueprint_locked(entry):
		return {}
	if scrap < get_armor_scrap_cost(entry) or credits < get_armor_credit_cost(entry):
		return {}
	scrap -= get_armor_scrap_cost(entry)
	credits -= get_armor_credit_cost(entry)
	return make_armor_instance_from_catalog(part_id)


# Equips an owned instance into a slot, carrying its wear into the combat cache.
func equip_armor_instance(uid: String, slot: String) -> bool:
	var inst := get_armor_instance(uid)
	if inst.is_empty():
		return false
	unequip_armor_instance(slot)
	inst["equipped"] = true
	inst["slot"] = slot
	equipped_parts[slot] = inst
	var dmg := 1.0 - get_durability_ratio(inst)
	if dmg <= 0.0:
		part_damage.erase(slot)
	else:
		part_damage[slot] = dmg
	return true


func unequip_armor_instance(slot: String) -> void:
	var current = equipped_parts.get(slot)
	if current is Dictionary and current.has("uid"):
		var inst := get_armor_instance(str(current["uid"]))
		if not inst.is_empty():
			inst["durability"] = get_part_durability(slot)
			inst["equipped"] = false
	equipped_parts[slot] = null
	part_damage.erase(slot)
	part_damage.erase(slot + "_frame")


# Writes the live combat damage cache back into the equipped instances' durability.
func sync_equipped_armor_durability() -> void:
	for slot in equipped_parts:
		var part = equipped_parts[slot]
		if part is Dictionary and part.has("uid"):
			var inst := get_armor_instance(str(part["uid"]))
			if not inst.is_empty():
				inst["durability"] = get_part_durability(slot)


# -----------------------------------------------------------------------------
# SHARED PART HELPERS — single source for stat/durability/cost reads so the
# hangar, safehouse, intermission and mecha UIs can never disagree.
# -----------------------------------------------------------------------------

# Reads a numeric stat from either an ArmorPart resource or a Dictionary
# instance, normalizing key aliases (max_hp/hp, armor_class/armor).
func part_stat(part: Variant, key: String, default: float = 0.0) -> float:
	var v: Variant = default
	if part is ArmorPart:
		if key == "hp" or key == "max_hp":
			v = part.max_hp
		elif key == "armor" or key == "armor_class":
			v = part.armor_class
		elif key == "weight":
			v = part.weight
	else:
		var d: Dictionary = part if part is Dictionary else {}
		if key == "hp" or key == "max_hp":
			v = d.get("hp", d.get("max_hp", default))
		elif key == "armor" or key == "armor_class":
			v = d.get("armor", d.get("armor_class", default))
		elif key == "weight":
			v = d.get("weight", default)
	return float(v)


# Normalizes an armor instance's stored durability to a 0..1 fraction.
func get_durability_ratio(inst: Dictionary) -> float:
	return clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)


# Live durability fraction (0..1) of the currently equipped part in a slot,
# derived from the combat damage cache.
func get_part_durability(slot: String) -> float:
	return 1.0 - clampf(float(part_damage.get(slot, 0.0)), 0.0, 1.0)


# Credit cost to fully repair a slot (armor + inner frame). One formula, used by
# every repair UI so the same damage always costs the same credits.
func get_repair_cost(slot: String) -> int:
	var dmg := clampf(float(part_damage.get(slot, 0.0)), 0.0, 1.0)
	var frame_dmg := clampf(float(part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
	if dmg <= 0.0 and frame_dmg <= 0.0:
		return 0
	var armor_max_hp := part_stat(equipped_parts.get(slot), "max_hp", 50.0)
	var frame_max_hp := part_stat(equipped_frames.get(slot), "max_hp", 50.0)
	var cost := dmg * armor_max_hp * REPAIR_COST_PER_HP
	cost += frame_dmg * frame_max_hp * REPAIR_COST_PER_HP
	return maxi(1, int(ceil(cost)))


# -----------------------------------------------------------------------------
# SCRAP PATCHES — emergency self-repair done in the intermission screen when the
# driver has no fleet mechanic available. Scrap is used to build crude armor out
# of basic primitives (boxes / spheres / wedges) placed on the mech like a Mass
# Builder frame editor. A patched slot uses WEAKER scrap stats derived from the
# driver's repair-skill tier and stays patched until a professional mechanic
# rebuilds the real armor.
#   key: slot name
#   value: {
#     "tier": 1..5, "stat_scale": 0.40..0.80,
#     "scrap_armor_hp": float, "scrap_frame_hp": float,
#     "armor_class": float, "scrap_spent": int,
#     "primitives": [ {shape, pos, rot, scale, color} ]
#   }
# -----------------------------------------------------------------------------
var scrap_patches: Dictionary = {}

const EMERGENCY_REPAIR_BASE_SCRAP := 5
const EMERGENCY_REPAIR_SCRAP_PER_ARMOR_HP := 0.04
const EMERGENCY_REPAIR_SCRAP_PER_FRAME_HP := 0.03


# Scrap cost to emergency-patch a slot, based on how much of it is damaged.
func get_emergency_repair_scrap_cost(slot: String) -> int:
	var dmg := clampf(float(part_damage.get(slot, 0.0)), 0.0, 1.0)
	var frame_dmg := clampf(float(part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
	if dmg <= 0.0 and frame_dmg <= 0.0:
		return 0
	var armor_max_hp := part_stat(equipped_parts.get(slot), "max_hp", 50.0)
	var frame_max_hp := part_stat(equipped_frames.get(slot), "max_hp", 50.0)
	var cost := EMERGENCY_REPAIR_BASE_SCRAP
	cost += int(ceil(dmg * armor_max_hp * EMERGENCY_REPAIR_SCRAP_PER_ARMOR_HP))
	cost += int(ceil(frame_dmg * frame_max_hp * EMERGENCY_REPAIR_SCRAP_PER_FRAME_HP))
	return maxi(1, cost)


# Builds and records a scrap patch on a slot: spends scrap, restores the slot to
# a partial weaker state (stats scaled by the driver's repair-skill tier) and
# clears its damage. Returns the patch, or {} when the slot is fine / unaffordable.
func apply_emergency_repair(slot: String, primitives: Array = []) -> Dictionary:
	if slot not in MECHA_SLOTS:
		return {}
	var cost := get_emergency_repair_scrap_cost(slot)
	if cost <= 0 or scrap < cost:
		return {}
	scrap -= cost

	var tier := get_scrap_armor_tier()
	var scale := get_scrap_armor_stat_scale()
	var armor_max_hp := part_stat(equipped_parts.get(slot), "max_hp", 50.0)
	var frame_max_hp := part_stat(equipped_frames.get(slot), "max_hp", 50.0)

	var armor_class := 1.0
	var p = equipped_parts.get(slot)
	if p:
		if p.get("armor_class") != null:
			armor_class = float(p.armor_class)
		elif p.get("armor") != null:
			armor_class = maxf(float(p.get("armor", 10.0)) / 10.0, 0.1)

	# Primitives are stored JSON-safe (arrays for vec3/color) so the patch
	# survives save_run()/load_run() round-trips.
	var safe_primitives: Array = []
	for primitive in primitives:
		if primitive is Dictionary:
			safe_primitives.append(_scrap_primitive_to_json_safe(primitive))

	var patch := {
		"tier": tier,
		"stat_scale": scale,
		"scrap_armor_hp": maxf(armor_max_hp * scale, 1.0),
		"scrap_frame_hp": maxf(frame_max_hp * scale, 1.0),
		"armor_class": maxf(armor_class * scale, 0.1),
		"scrap_spent": cost,
		"primitives": safe_primitives,
	}
	scrap_patches[slot] = patch
	part_damage.erase(slot)
	part_damage.erase(slot + "_frame")

	# Practice makes perfect — patching is how the driver's repair skill grows.
	gain_repair_xp(10 + cost)
	return patch


# Converts a scrap primitive's Vector3/Color fields into JSON-safe arrays.
func _scrap_primitive_to_json_safe(primitive: Dictionary) -> Dictionary:
	var out := primitive.duplicate(true)
	var pos = primitive.get("pos")
	if pos is Vector3:
		out["pos"] = [pos.x, pos.y, pos.z]
	var rot = primitive.get("rot")
	if rot is Vector3:
		out["rot"] = [rot.x, rot.y, rot.z]
	var scale = primitive.get("scale")
	if scale is Vector3:
		out["scale"] = [scale.x, scale.y, scale.z]
	elif scale is float or scale is int:
		var f := float(scale)
		out["scale"] = [f, f, f]
	var color = primitive.get("color")
	if color is Color:
		out["color"] = [color.r, color.g, color.b, color.a]
	return out


func scrap_primitive_pos(primitive: Dictionary) -> Vector3:
	var raw = primitive.get("pos")
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


func scrap_primitive_rot(primitive: Dictionary) -> Vector3:
	var raw = primitive.get("rot")
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


func scrap_primitive_scale(primitive: Dictionary) -> Vector3:
	var raw = primitive.get("scale")
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var flat = primitive.get("scale")
	if flat is float or flat is int:
		var f := float(flat)
		return Vector3(f, f, f)
	return Vector3.ONE


func scrap_primitive_color(primitive: Dictionary) -> Color:
	var raw = primitive.get("color")
	if raw is Color:
		return raw
	if raw is Array and raw.size() >= 4:
		return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return Color(0.55, 0.55, 0.6, 1.0)


func has_scrap_patch(slot: String) -> bool:
	return scrap_patches.has(slot)


func remove_scrap_patch(slot: String) -> void:
	scrap_patches.erase(slot)


# -----------------------------------------------------------------------------
# PROFESSIONAL REPAIR — a fleet mechanic / village workshop rebuilds a scrap-
# patched (or damaged) slot into fresh catalog armor. Costs credits and consumes
# the node you're standing on. Returns the credit price for the slot.
# -----------------------------------------------------------------------------
const PROFESSIONAL_REPAIR_CREDITS_PER_ARMOR_HP := 1.0
const PROFESSIONAL_REPAIR_CREDITS_PER_FRAME_HP := 0.75


func get_professional_repair_cost(slot: String) -> int:
	if slot not in MECHA_SLOTS:
		return 0
	var armor_max_hp := part_stat(equipped_parts.get(slot), "max_hp", 50.0)
	var frame_max_hp := part_stat(equipped_frames.get(slot), "max_hp", 50.0)
	var cost := armor_max_hp * PROFESSIONAL_REPAIR_CREDITS_PER_ARMOR_HP
	cost += frame_max_hp * PROFESSIONAL_REPAIR_CREDITS_PER_FRAME_HP
	return maxi(1, int(ceil(cost)))


# The mechanic rebuilds the slot: removes any scrap patch, clears all damage and
# restores the real catalog armor at full HP. Returns false if unaffordable.
func apply_professional_repair(slot: String) -> bool:
	if slot not in MECHA_SLOTS:
		return false
	var cost := get_professional_repair_cost(slot)
	if credits < cost:
		return false
	credits -= cost
	scrap_patches.erase(slot)
	part_damage.erase(slot)
	part_damage.erase(slot + "_frame")
	return true


# Maps a mech slot name to the mecha-root-relative node path holding that
# section's meshes. Single source of truth for all part visuals.
func get_slot_node_path(slot: String) -> String:
	match slot:
		"head": return "Head"
		"body": return "Body"
		"arm_left": return "ArmLeft"
		"arm_right": return "ArmRight"
		"leg_left": return "LegLeft"
		"leg_right": return "LegRight"
	return ""


# Default stock weapons that the player starts with on each hand / on the back.
const DEFAULT_LEFT_WEAPON_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const DEFAULT_RIGHT_WEAPON_PATH := "res://resources/mech/stock/weapon_heat_blade.tres"
const DEFAULT_CARRY_WEAPON_PATH := "res://resources/mech/stock/weapon_combat_shotgun.tres"

# The six armor/frame slots of the mech, in a stable order.
const MECHA_SLOTS: Array[String] = [
	"head", "body", "arm_left", "arm_right", "leg_left", "leg_right"
]

# Credits charged per point of HP repaired.
const REPAIR_COST_PER_HP := 0.5

# -----------------------------------------------------------------------------
# FIELD PACK vs DEPOT
# - DEPOT: permanent storage (weapon_inventory, ammo_inventory, salvaged armor).
# - FIELD PACK: what the mech physically carries into battle (hand weapons,
#   back-carry weapons, and the ammo loadout). Weight capacity comes from the
#   equipped Inner Frames (each frame adds a "carry_bonus").
# -----------------------------------------------------------------------------
const FIELD_PACK_BASE_CAPACITY := 40.0
# Weight of one round of ammo (kg), used to weigh the ammo loadout.
const AMMO_WEIGHT_PER_UNIT := {
	"kinetic": 0.01,
	"energy": 0.02,
	"explosive": 0.20,
	"missile": 0.50,
}

# Total Field Pack weight capacity in kg = base + sum of equipped frames.
func get_field_pack_capacity() -> float:
	var capacity := FIELD_PACK_BASE_CAPACITY
	for slot in equipped_frames:
		var f = equipped_frames[slot]
		if f is Dictionary:
			capacity += float(f.get("carry_bonus", 0.0))
	return capacity


# Current Field Pack load weight in kg (hand weapons + carry weapons + ammo).
func get_field_pack_weight() -> float:
	return get_loadout_weapons_total() + get_field_pack_ammo_weight()


# Weight of the ammo the player chose to carry (the "ammo" loadout).
func get_field_pack_ammo_weight() -> float:
	var total := 0.0
	for ammo_type in weapon_loadout.get("ammo", {}):
		total += AMMO_WEIGHT_PER_UNIT.get(ammo_type, 0.01) * float(get_loadout_ammo(ammo_type))
	return total


# Older saves predate frame ids. Resolve a saved frame value into a full catalog
# entry so the Field Pack capacity and stats stay consistent across old save files.


func _ensure_default_frames() -> void:
	if not equipped_frames.is_empty():
		return
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		if frame_catalog.has(slot) and frame_catalog[slot].size() > 0:
			equipped_frames[slot] = frame_catalog[slot][0].duplicate()


# -----------------------------------------------------------------------------
# HANGAR MECH ROSTER
# A roster entry is a built machine that can be selected in the hangar. It is
# deliberately a loadout snapshot, so entering a different mech never mutates
# the catalog or invents a placeholder backup body. Logic lives in HangarManager;
# GlobalData keeps these thin facades so all existing callers stay untouched.
# -----------------------------------------------------------------------------
func ensure_hangar_roster() -> void:
	HangarManager.ensure_roster()


func get_hangar_mechs() -> Array:
	return HangarManager.get_mechs()


func get_active_hangar_mech() -> Dictionary:
	return HangarManager.get_active_mech()


func save_active_hangar_mech() -> bool:
	return HangarManager.save_active()


func build_hangar_mech(mech_name: String = "") -> Dictionary:
	return HangarManager.build(mech_name)


func get_backup_hangar_mech_id() -> String:
	return HangarManager.get_backup_id()


func switch_hangar_mech(mech_id: String) -> bool:
	return HangarManager.switch_mech(mech_id)

# -----------------------------------------------------------------------------
# WEAPON LOADOUT — central state for what the mech carries into battle.
# "left"/"right" are the hand weapons (resource path, "" = unarmed hand).
# "carry" is the array of weapon paths the mech carries on its back.
# "ammo" is how much ammo of each type the player allocates to bring into battle.
# Configured in the Hangar, read by WeaponManager at battle start.
# -----------------------------------------------------------------------------
var weapon_loadout: Dictionary = {
	"left": DEFAULT_LEFT_WEAPON_PATH,
	"right": DEFAULT_RIGHT_WEAPON_PATH,
	"carry": [DEFAULT_CARRY_WEAPON_PATH],
	"ammo": {
		"kinetic": 300,
		"energy": 150,
		"explosive": 30,
		"missile": 12
	}
}


# Returns the equipped WeaponPart for the given hand ("left"/"right").
# Reads the central weapon_loadout so the Hangar and battle share one source.
# An explicitly-unarmed hand ("") returns null; only a missing/blank slot falls
# back to the default stock weapon for that hand.
func get_equipped_weapon(side: String) -> WeaponPart:
	var path := str(weapon_loadout.get("left", "") if side == "left" else weapon_loadout.get("right", ""))
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		path = DEFAULT_LEFT_WEAPON_PATH if side == "left" else DEFAULT_RIGHT_WEAPON_PATH
	if ResourceLoader.exists(path):
		return load(path)
	return null


# Returns the WeaponParts the mech carries on its back into battle (from loadout).
func get_carry_weapons() -> Array[WeaponPart]:
	var result: Array[WeaponPart] = []
	var carry_paths = weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		return result
	for path in carry_paths:
		if path is String and path != "" and ResourceLoader.exists(path):
			result.append(load(path))
	return result


# Total weight of all loadout weapons (both hands + back).
func get_loadout_weapons_total() -> float:
	var total := 0.0
	var left = get_equipped_weapon("left")
	if left:
		total += float(left.weight)
	var right = get_equipped_weapon("right")
	if right:
		total += float(right.weight)
	for w in get_carry_weapons():
		total += float(w.weight)
	return total


# Total weight of all loadout weapons (both hands + back).
func get_loadout_weapon_weight() -> float:
	return get_loadout_weapons_total()


# Assigns a weapon resource path to a hand. Empty path = unarmed hand.
func set_hand_weapon(side: String, path: String) -> void:
	if side == "left":
		weapon_loadout["left"] = path
	else:
		weapon_loadout["right"] = path


func is_weapon_in_carry(path: String) -> bool:
	var carry_paths = weapon_loadout.get("carry", [])
	return carry_paths is Array and path in carry_paths


func add_carry_weapon(path: String) -> void:
	var carry_paths = weapon_loadout.get("carry", [])
	if not (carry_paths is Array):
		carry_paths = []
	if path not in carry_paths:
		carry_paths.append(path)
	weapon_loadout["carry"] = carry_paths


func remove_carry_weapon(path: String) -> void:
	var carry_paths = weapon_loadout.get("carry", [])
	if carry_paths is Array:
		carry_paths.erase(path)
	weapon_loadout["carry"] = carry_paths


# Returns how much ammo of the given type the player carries into the next battle.
func get_loadout_ammo(ammo_type: String) -> int:
	var ammo = weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return 0
	return ammo.get(ammo_type.to_lower(), 0)


# Sets how much ammo of the given type the player carries into the next battle.
func set_loadout_ammo(ammo_type: String, amount: int) -> void:
	var ammo = weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		ammo = {}
	ammo[ammo_type.to_lower()] = max(0, amount)
	weapon_loadout["ammo"] = ammo


func get_loadout_ammo_dict() -> Dictionary:
	var ammo = weapon_loadout.get("ammo", {})
	if not (ammo is Dictionary):
		return {}
	return ammo.duplicate()


func get_equipped_part_id(slot: String) -> String:
	var part = equipped_parts.get(slot)
	if part == null:
		return ""
	if part is Dictionary:
		var pid = part.get("id", "")
		if pid != "":
			return pid
		return part.get("name", part.get("path", ""))
	if part is Resource:
		if "id" in part and part.id != "":
			return part.id
		if "part_name" in part and part.part_name != "":
			return part.part_name
		return part.resource_path
	return ""


# Returns the chassis stats dict for the currently selected chassis_id.
# Used by mecha_controller at combat start so it doesn't rely on @export chassis resource.
# Keys: "speed" (float), "max_weight" (float), "color" (Color), "name" (String)
func get_chassis_stats() -> Dictionary:
	var result: Dictionary = chassis_catalog.get(chassis_id, chassis_catalog.get("standard", {
		"name": "Standard", "speed": 14.0, "max_weight": 75.0, "color": Color(0.6, 0.65, 0.7)
	})).duplicate(true)
	if not result.has("attachment_capacity"):
		var capacity := float(result.get("max_weight", 75.0))
		result["attachment_capacity"] = {"head": capacity * 0.10, "body": capacity * 0.35, "arm_left": capacity * 0.14, "arm_right": capacity * 0.14, "leg_left": capacity * 0.16, "leg_right": capacity * 0.16}
	result["movement_type"] = {"standard": "biped", "titan": "heavy", "vanguard": "light", "aegis": "hover", "brawler": "brawler"}.get(chassis_id, "biped")
	result["water_traversal"] = result["movement_type"] == "hover"
	return result


# Equipped inner frames. Values are full catalog-entry dicts at runtime; the
# save file persists only {"id": ...} references (see _serialize_frames).
var equipped_frames: Dictionary = {}
var frame_upgrade_level: int = 1


const FRAME_UPGRADE_HP_BONUS: float = 25.0
const FRAME_UPGRADE_WEIGHT_BONUS: float = 15.0
const FRAME_UPGRADE_BASE_COST: int = 150


func get_frame_upgrade_hp_bonus() -> float:
	return float(maxi(frame_upgrade_level - 1, 0)) * FRAME_UPGRADE_HP_BONUS


func get_frame_upgrade_weight_bonus() -> float:
	return float(maxi(frame_upgrade_level - 1, 0)) * FRAME_UPGRADE_WEIGHT_BONUS


func get_frame_upgrade_cost() -> int:
	return frame_upgrade_level * FRAME_UPGRADE_BASE_COST

# Owned armor instances. Every acquired part is a distinct instance with its own
# durability (0..1) and upgrade_level. Catalog entries are templates only; the
# stats are duplicated into the instance at creation and never mutate the catalog.
# Entry: {"uid", "db_id", "name", "slot", "type", "hp", "armor", "weight", "color",
#         "durability", "upgrade_level", "equipped"}
var armor_inventory: Array = []
var part_damage: Dictionary = {}

var board_grid: Array = []
var current_tile: Vector2i = Vector2i.ZERO
var board_seed: int = 0
var heat: int = 0
var wanted_level: int = 0
var safehouse_upgrades: Array = []

# -----------------------------------------------------------------------------
# RUN THEME — the identity of the current run (see run_theme_catalogs.tres).
# - theme_id:       which story this run is (soldier / gundam_merc / scavenger).
# - reputation:     accrued deeds that gate high-tier choice events.
# - theme_switched: allows a theme_switch event to fire at most once per run.
# - ceasefire_turns: board moves left with no combat (political ceasefire).
# - blocked_intermission: set when a force_combat event denies the intermission
#   between battles.
# -----------------------------------------------------------------------------
var theme_id: String = "soldier"
var reputation: int = 0
var theme_switched: bool = false
var ceasefire_turns: int = 0
var blocked_intermission: bool = false

# -----------------------------------------------------------------------------
# ENEMY TECH ESCALATION — enemies reverse-engineer our mech over time.
# - enemy_tech_tier:     the enemy's current standard (new unit tier).
#   It rises one step at a time whenever we win a battle DECISIVELY (we took
#   at most 50% of our combined fielded HP in damage). Decisive wins prove
#   our gear works; the enemy copies it for the next deployment.
# -----------------------------------------------------------------------------
var enemy_tech_tier: int = 1
var pending_escalation_event: bool = false

# -----------------------------------------------------------------------------
# COMBAT DAMAGE TRACKING — measures how "decisive" our victory was.
# - _combat_friendly_total_hp: snapshot of combined max HP of every friendly
#   unit fielded (player mech + allies) taken at combat start.
# - _combat_friendly_damage:   accumulated raw HP lost by friendly units.
# - last_combat_damage_ratio:  damage / total_hp, finalized at combat end.
#   A decisive victory keeps this <= 0.5 (we took <= 50% combined damage).
# -----------------------------------------------------------------------------
var _combat_friendly_total_hp: float = 0.0
var _combat_friendly_damage: float = 0.0
var last_combat_damage_ratio: float = 0.0

const DECISIVE_VICTORY_RATIO := 0.5

var credits: int = 0
var data_cores: int = 0
var scrap: int = 0


# --- Currency API ---
# All external code should mutate currency through these helpers so spending
# rules stay in one place (single source of truth for the economy).
func try_spend_credits(amount: int) -> bool:
	if amount <= 0 or credits < amount:
		return false
	credits -= amount
	return true


func gain_credits(amount: int) -> void:
	if amount > 0:
		credits += amount


func try_spend_scrap(amount: int) -> bool:
	if amount <= 0 or scrap < amount:
		return false
	scrap -= amount
	return true


func gain_scrap(amount: int) -> void:
	if amount > 0:
		scrap += amount


func try_spend_data_cores(amount: int) -> bool:
	if amount <= 0 or data_cores < amount:
		return false
	data_cores -= amount
	return true


func gain_data_cores(amount: int) -> void:
	if amount > 0:
		data_cores += amount

# -----------------------------------------------------------------------------
# FLEET (กองยาน) — roster of allied mech units the player owns.
# Each entry is a per-unit record: {"template_id", "name", "hp", "max_hp",
# "destroyed", "fielded"}. Units are researched from blueprints (data_cores)
# at the research base; fielded units tag along into combat as AI squadmates.
# -----------------------------------------------------------------------------
var fleet_roster: Array = []

# Active research: {project_id: {"progress": int, "required": int, "started": bool}}
var research_projects: Dictionary = {}

# Blueprint projects fully researched and unlocked (ids), e.g. units/gear.
var research_unlocked: Array = []

# -----------------------------------------------------------------------------
# FLEET SECURITY — how well our ships/facility fend off enemy espionage.
# - fleet_security:      0-100. Higher value = enemy spies more likely to be
#   caught before stealing mech data.
# - security_upgrade_level: the fleet's defensive-hardening branch level. Each
#   upgrade costs credits and raises fleet_security (separate from research).
# -----------------------------------------------------------------------------
var fleet_security: float = 25.0
var security_upgrade_level: int = 1

const FLEET_SECURITY_MIN := 0.0
const FLEET_SECURITY_MAX := 100.0
const SECURITY_PER_UPGRADE := 14.0
const SECURITY_UPGRADE_BASE_COST := 35


func get_fleet_security() -> float:
	return clampf(fleet_security, FLEET_SECURITY_MIN, FLEET_SECURITY_MAX)


func get_security_upgrade_cost() -> int:
	return SECURITY_UPGRADE_BASE_COST + (security_upgrade_level - 1) * 40


# Spend credits to raise fleet security. Returns false if unaffordable or maxed.
func upgrade_fleet_security() -> bool:
	var cost := get_security_upgrade_cost()
	if credits < cost:
		return false
	if get_fleet_security() >= FLEET_SECURITY_MAX:
		return false
	credits -= cost
	security_upgrade_level += 1
	fleet_security = minf(get_fleet_security() + SECURITY_PER_UPGRADE, FLEET_SECURITY_MAX)
	return true


# Chance (0..1) that an enemy spy attempt on our mech data FAILS before stealing
# anything. 25 = starting security, 50 = one strong investment, 90+ = fortress.
func get_spy_counter_chance() -> float:
	return clampf(0.10 + get_fleet_security() * 0.008, 0.10, 0.90)


# -----------------------------------------------------------------------------
# DRIVER REPAIR SKILL — how skilled the pilot is at field repairs.
# - driver_repair_skill: 1..5. Determines the tier of scrap armor a driver can
#   build from emergency patches. Higher skill = stronger (but never equal to
#   proper catalog armor) scrap armor.
# - driver_repair_xp:    earned by doing emergency scrap repairs (practice makes
#   perfect); leveling up raises the skill tier.
# -----------------------------------------------------------------------------
var driver_repair_skill: int = 1
var driver_repair_xp: int = 0

const REPAIR_SKILL_MAX := 5
const REPAIR_XP_BASE := 30
const REPAIR_XP_PER_LEVEL := 25


# XP required to advance from `level` to `level + 1`.
func get_repair_skill_xp_for_next(level: int) -> int:
	return REPAIR_XP_BASE + maxi(level - 1, 0) * REPAIR_XP_PER_LEVEL


# Returns true when the XP gain pushed the skill to a new tier.
func gain_repair_xp(amount: int) -> bool:
	if amount <= 0 or driver_repair_skill >= REPAIR_SKILL_MAX:
		return false
	driver_repair_xp += amount
	var leveled_up := false
	while driver_repair_skill < REPAIR_SKILL_MAX:
		var needed := get_repair_skill_xp_for_next(driver_repair_skill)
		if driver_repair_xp < needed:
			break
		driver_repair_xp -= needed
		driver_repair_skill += 1
		leveled_up = true
	return leveled_up


# The scrap armor tier the driver can build right now (1..5).
func get_scrap_armor_tier() -> int:
	return clamp(driver_repair_skill, 1, REPAIR_SKILL_MAX)


# Stats multiplier for scrap-built armor vs the real catalog part. Tier 1 gives
# 40% of the real stats, each tier +10% up to 80% — scrap can never match a
# properly-crafted armor plate.
func get_scrap_armor_stat_scale() -> float:
	return clampf(0.40 + 0.10 * (get_scrap_armor_tier() - 1), 0.40, 0.80)


func get_ally_template(template_id: String) -> Dictionary:
	return ally_unit_templates.get(template_id, {})


func get_fielded_units() -> Array:
	var result: Array = []
	for unit in fleet_roster:
		if unit is Dictionary and unit.get("fielded", true) and not unit.get("destroyed", false):
			result.append(unit)
	return result


func get_fleet_unit(template_id: String) -> Dictionary:
	for unit in fleet_roster:
		if unit.get("template_id", "") == template_id:
			return unit
	return {}


func has_ally_unit(template_id: String) -> bool:
	return not get_fleet_unit(template_id).is_empty()


func add_ally_unit(template_id: String) -> bool:
	var template = get_ally_template(template_id)
	if template.is_empty():
		push_warning("add_ally_unit: unknown template '%s'" % template_id)
		return false
	if has_ally_unit(template_id):
		return false
	fleet_roster.append({
		"template_id": template_id,
		"name": template.get("name", template_id),
		"hp": float(template.get("frame_hp", 50.0)),
		"max_hp": float(template.get("frame_hp", 50.0)),
		"destroyed": false,
		"fielded": template.get("fielded", true),
	})
	return true


func set_unit_fielded(template_id: String, fielded: bool) -> void:
	var unit = get_fleet_unit(template_id)
	if unit.is_empty():
		return
	unit["fielded"] = fielded


# --- Research base ----------------------------------------------------------

func get_research_project(project_id: String) -> Dictionary:
	for project in research_blueprints:
		if project.get("id", "") == project_id:
			return project
	return {}


func is_research_active(project_id: String) -> bool:
	return research_projects.has(project_id)


func is_research_completed(project_id: String) -> bool:
	return project_id in research_unlocked


# Start a research project: consumes data_cores (the blueprint) and begins the
# clock. Research time progresses via board moves (tick_research(1)) and
# completed combats (tick_research(2)).
func start_research(project_id: String) -> bool:
	if is_research_active(project_id) or is_research_completed(project_id):
		return false
	var project = get_research_project(project_id)
	if project.is_empty():
		return false
	var cost = int(project.get("data_cores", 1))
	if data_cores < cost:
		return false
	data_cores -= cost
	research_projects[project_id] = {
		"progress": 0,
		"required": int(project.get("research_time", 6)),
		"started": true,
	}
	return true


# Advance all active research by `points`. Returns project ids completed now.
func tick_research(points: int) -> Array:
	var completed: Array = []
	for project_id in research_projects.keys():
		var state = research_projects[project_id]
		if state is Dictionary:
			state["progress"] = int(state.get("progress", 0)) + points
			if int(state.get("progress", 0)) >= int(state.get("required", 1)) and not (project_id in completed):
				research_unlocked.append(project_id)
				research_projects.erase(project_id)
				_apply_research_reward(project_id)
				completed.append(project_id)
	return completed


func _apply_research_reward(project_id: String) -> void:
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

# -----------------------------------------------------------------------------
# RUN THEME HELPERS
# -----------------------------------------------------------------------------

func get_run_theme() -> Dictionary:
	for theme in run_themes:
		if theme.get("id", "") == theme_id:
			return theme
	return {}


func get_theme_event_pool() -> Array:
	var theme = get_run_theme()
	var forced: Array = theme.get("events", [])
	var result: Array = []
	for event in run_events:
		if not (event is Dictionary):
			continue
		var themes = event.get("themes", [])
		if themes is Array and not themes.is_empty() and not (theme_id in themes):
			continue
		if int(event.get("min_reputation", 0)) > reputation:
			continue
		if str(event.get("id", "")) in forced:
			continue
		result.append(event)
	for event_id in forced:
		var event = get_run_event(event_id)
		if event.is_empty():
			continue
		# Theme-forced events still respect the reputation gate.
		if int(event.get("min_reputation", 0)) > reputation:
			continue
		result.append(event)
	return result


func get_run_event(event_id: String) -> Dictionary:
	for event in run_events:
		if event.get("id", "") == event_id:
			return event
	return {}


func get_theme_ending() -> Dictionary:
	var theme = get_run_theme()
	return theme.get("ending", {})


# -----------------------------------------------------------------------------
# ENEMY TECH ESCALATION — see state block near the theme fields.
# -----------------------------------------------------------------------------

# Per-theme escalation tuning; falls back to sensible defaults.
func get_escalation_config() -> Dictionary:
	var theme = get_run_theme()
	var flow: Dictionary = theme.get("flow", {})
	return {
		"max_tier": int(flow.get("escalation_max_tier", 4)),
		"hp_per_tier": float(flow.get("escalation_hp_per_tier", 0.35)),
		"spy_base_chance": float(flow.get("escalation_spy_base_chance", 0.05)),
		"spy_chance_per_tier": float(flow.get("escalation_spy_chance_per_tier", 0.06)),
	}


# Called when a battle ends. The enemy tiers up one step when we win a battle
# DECISIVELY — i.e. we took at most 50% of our combined fielded HP in damage.
# Decisive wins prove our gear works, so the enemy copies it. Non-decisive
# wins or losses don't escalate (our build barely worked / we failed).
func on_combat_ended_for_tech(victory: bool) -> void:
	if not victory:
		return
	var cfg := get_escalation_config()
	if last_combat_damage_ratio <= DECISIVE_VICTORY_RATIO:
		_try_escalate(cfg)


func _try_escalate(cfg: Dictionary) -> void:
	var max_tier := int(cfg.get("max_tier", 4))
	if enemy_tech_tier >= max_tier:
		return
	enemy_tech_tier = mini(enemy_tech_tier + 1, max_tier)
	pending_escalation_event = true
	EventBus.enemy_tech_escalated.emit(enemy_tech_tier)


# Returns true once so the board can surface the "enemy upgraded" popup when
# the player returns from combat.
func consume_pending_escalation_event() -> bool:
	var had_pending := pending_escalation_event
	pending_escalation_event = false
	return had_pending


# Multiplier applied to freshly spawned enemy HP/damage based on tech tier.
func get_enemy_tech_multiplier() -> float:
	var cfg := get_escalation_config()
	return 1.0 + float(enemy_tech_tier - 1) * float(cfg.get("hp_per_tier", 0.35))


# Combined spawn scaling including the partial grunt upgrades salvaged from
# destroyed research nodes. Grunts get tougher even without a full tier-up.
func get_enemy_grunt_multiplier() -> float:
	return get_enemy_tech_multiplier() + float(enemy_grunt_upgrade_level) * 0.10


# -----------------------------------------------------------------------------
# ENEMY SPY / DATA THEFT — the enemy tries to steal our mech data out of combat.
# - Rolled on board moves. Attempt chance rises with the enemy tier (the higher
#   their tech interest, the more they probe us).
# - If a spy attempts, our fleet security decides whether it gets caught. A
#   successful theft starts the enemy's mech-copy research, which later spawns
#   a research node the player must destroy (see Phase 5).
# -----------------------------------------------------------------------------
var enemy_research_progress: float = 0.0

# --- Enemy research node (Phase 5) ---
# When enough mech data is stolen, the enemy spins up a research base node on
# the board. The player must reach it and destroy it before the enemy's
# counter-unit research completes. If it completes, the enemy fields one of
# three upgraded unit types (grunt MKII / special ace / gundam copy).
var enemy_base_active: bool = false
var enemy_base_progress: float = 0.0
var enemy_base_required: float = 6.0
var enemy_base_tile_pos: Vector2i = Vector2i(-1, -1)

# Partial upgrade granted when the player destroys the base before completion.
var enemy_grunt_upgrade_level: int = 0

# The outcome of a completed (NOT destroyed) research node.
var enemy_copy_outcome: String = ""  # "", "grunt_mk2", "special_ace", "gundam_copy"

# Units the enemy fields as a result of completed research (real mechs later).
var enemy_special_units: Array = []

var pending_enemy_base_spawn: bool = false
var pending_enemy_base_outcome: bool = false
var pending_enemy_base_destroyed: bool = false

# Position of the node tile that must be reverted back to a normal combat tile
# once the node is destroyed or finishes its counter-unit. Set before
# enemy_base_tile_pos is cleared so the board can reset the stale tile's meta.
var pending_enemy_base_tile_reset: Vector2i = Vector2i(-1, -1)

# Probability that the enemy attempts a spy this move (0..1).
func get_spy_attempt_chance() -> float:
	var cfg := get_escalation_config()
	return clampf(
		float(cfg.get("spy_base_chance", 0.05))
		+ float(enemy_tech_tier - 1) * float(cfg.get("spy_chance_per_tier", 0.06)),
		0.0,
		1.0
	)


# Rolls a full spy event for the current board move. Returns a Dictionary the
# board can surface. On success, enemy_research_progress is bumped.
func roll_spy_event() -> Dictionary:
	var chance := get_spy_attempt_chance()
	if randf() > chance:
		return {}
	var counter := get_spy_counter_chance()
	var caught := randf() < counter
	if caught:
		var bounty := 20 + int(randf() * 30)
		credits += bounty
		return {
			"name": "SPY CAUGHT",
			"effect": "none",
			"amount": 0,
			"desc": "Your fleet security intercepted an enemy spy and captured its gear! +%d credits." % bounty,
		}
	enemy_research_progress = minf(enemy_research_progress + 1.0, _get_enemy_research_cap())
	var stolen = {
		"name": "DATA STOLEN",
		"effect": "none",
		"amount": 0,
		"desc": "An enemy spy slipped past your security and stole mech data! The enemy has started researching a counter-unit.",
	}
	if enemy_research_progress >= _get_enemy_research_cap():
		enemy_research_progress = 0.0
		enemy_base_active = true
		enemy_base_progress = 0.0
		pending_enemy_base_spawn = true
		stolen["desc"] = "The enemy's stolen data has coalesced into a research base on the sector map! Destroy it before they finish a counter-unit."
	return stolen


func _get_enemy_research_cap() -> float:
	return 2.0


# -----------------------------------------------------------------------------
# ENEMY RESEARCH NODE LIFECYCLE — the spawned board node and its outcome.
# -----------------------------------------------------------------------------

# Called by the board once it has physically placed the enemy_base tile.
func consume_enemy_base_spawn_request() -> bool:
	var was_pending := pending_enemy_base_spawn
	pending_enemy_base_spawn = false
	return was_pending


# Advance the research node's counter-unit progress (1 per board move).
# Returns true when the enemy completes their counter-unit.
func tick_enemy_base_progress(points: float) -> bool:
	if not enemy_base_active:
		return false
	enemy_base_progress = minf(enemy_base_progress + points, enemy_base_required)
	if enemy_base_progress >= enemy_base_required:
		_enemy_base_completed()
		return true
	return false


func _enemy_base_completed() -> void:
	enemy_base_active = false
	pending_enemy_base_tile_reset = enemy_base_tile_pos
	enemy_base_tile_pos = Vector2i(-1, -1)
	enemy_copy_outcome = _roll_enemy_base_outcome()
	_apply_enemy_base_outcome(enemy_copy_outcome)
	pending_enemy_base_outcome = true


# The player reached and destroyed the node. The enemy only salvages a partial
# grunt upgrade instead of a full counter-unit.
func destroy_enemy_base() -> void:
	enemy_base_active = false
	enemy_base_progress = 0.0
	pending_enemy_base_tile_reset = enemy_base_tile_pos
	enemy_base_tile_pos = Vector2i(-1, -1)
	enemy_grunt_upgrade_level += 1
	pending_enemy_base_destroyed = true


# Returns the board tile position that must be reset (consumed once), or
# Vector2i(-1, -1) when there is nothing to reset.
func consume_enemy_base_tile_reset() -> Vector2i:
	var pos := pending_enemy_base_tile_reset
	pending_enemy_base_tile_reset = Vector2i(-1, -1)
	return pos


func consume_pending_enemy_base_outcome() -> bool:
	var was_pending := pending_enemy_base_outcome
	pending_enemy_base_outcome = false
	return was_pending


func consume_pending_enemy_base_destroyed() -> bool:
	var was_pending := pending_enemy_base_destroyed
	pending_enemy_base_destroyed = false
	return was_pending


# Outcome probabilities shift toward stronger copies as the enemy tier rises.
func _roll_enemy_base_outcome() -> String:
	var cfg := get_escalation_config()
	var max_tier := int(cfg.get("max_tier", 4))
	var tier_factor := clampf(float(enemy_tech_tier) / float(maxf(max_tier, 1)), 0.0, 1.0)
	var mk2_weight := int(lerpf(50.0, 25.0, tier_factor))
	var special_weight := int(lerpf(35.0, 35.0, tier_factor))
	var copy_weight := int(lerpf(15.0, 40.0, tier_factor))
	var total := mk2_weight + special_weight + copy_weight
	var roll := randi() % maxi(total, 1)
	if roll < mk2_weight:
		return "grunt_mk2"
	if roll < mk2_weight + special_weight:
		return "special_ace"
	return "gundam_copy"


func _apply_enemy_base_outcome(outcome: String) -> void:
	match outcome:
		"grunt_mk2":
			enemy_grunt_upgrade_level += 2
		"special_ace":
			enemy_special_units.append({"kind": "special_ace", "source": "research_node"})
			_add_stalking_ace("special_ace")
		"gundam_copy":
			enemy_special_units.append({"kind": "gundam_copy", "source": "research_node"})
			_add_stalking_ace("gundam_copy")


# A completed research node deploys its counter-unit as a stalking ace that
# hunts the player across the board. Once deployed it starts accumulating
# ambush chance with every move and will force a fight.
func _add_stalking_ace(ace_kind: String) -> void:
	if not stalking_aces.has(ace_kind):
		stalking_aces.append(ace_kind)


# Snapshot the combined max HP of every friendly unit in the current scene:
# the player mech + all fielded allies. Also resets the damage accumulator.
func begin_combat_stats() -> void:
	_combat_friendly_damage = 0.0
	_combat_friendly_total_hp = 0.0
	var scene = get_tree().current_scene
	if scene == null:
		return
	var mecha = scene.get_node_or_null("Mecha")
	if mecha:
		var hs = mecha.get_node_or_null("HealthSystem")
		if hs and hs.has_method("get_health_percent"):
			_combat_friendly_total_hp += float(hs.max_total_armor + hs.max_total_frame)
	for ally in get_tree().get_nodes_in_group("ally"):
		if not is_instance_valid(ally):
			continue
		var hs = ally.get_node_or_null("HealthSystem")
		if hs and hs.has_method("get_health_percent"):
			_combat_friendly_total_hp += float(hs.max_total_armor + hs.max_total_frame)


# Allow tests / callers to supply the snapshot directly without a live scene.
func set_combat_hp_snapshot(total_hp: float) -> void:
	_combat_friendly_total_hp = maxf(total_hp, 0.0)
	_combat_friendly_damage = 0.0


func get_combat_friendly_total_hp() -> float:
	return _combat_friendly_total_hp


func get_combat_friendly_damage() -> float:
	return _combat_friendly_damage


# ratio = friendly damage taken / combined friendly HP. 0 if nothing fielded.
func _compute_last_combat_damage_ratio() -> void:
	if _combat_friendly_total_hp <= 0.0:
		last_combat_damage_ratio = 0.0
		return
	last_combat_damage_ratio = clampf(_combat_friendly_damage / _combat_friendly_total_hp, 0.0, 1.0)


# A victory is "decisive" when we took at most 50% of our combined HP in damage.
func was_decisive_victory() -> bool:
	return last_combat_damage_ratio <= DECISIVE_VICTORY_RATIO


# Picks a weighted-random chassis key from a theme's chassis_weights.
func _roll_weighted_chassis(theme: Dictionary) -> String:
	var weights: Dictionary = theme.get("start", {}).get("chassis_weights", {})
	var total := 0
	for key in weights:
		total += int(weights[key])
	if total <= 0:
		return "standard"
	var roll := randi() % total
	for key in weights:
		roll -= int(weights[key])
		if roll < 0:
			return key
	return "standard"


# Picks a random catalog part id for an armor slot (lowest tier always exists).
func _roll_armor_part(slot: String) -> String:
	if armor_catalog.has(slot) and armor_catalog[slot].size() > 0:
		return str(armor_catalog[slot][0].get("id", ""))
	return ""


# Picks a frame id for a slot weighted by part_tier_weights.
# frame_catalog[slot] is ordered: [standard, gundam, medium, heavy] per slot.
func _roll_frame(slot: String, tier_weights: Dictionary) -> String:
	var entries: Array = frame_catalog.get(slot, [])
	if entries.is_empty():
		return ""
	var tier_order := ["standard", "gundam", "medium", "heavy"]
	var total := 0
	for tier in tier_order:
		total += int(tier_weights.get(tier, 0))
	if total <= 0:
		return str(entries[0].get("id", ""))
	var roll := randi() % total
	var index := 0
	for tier in tier_order:
		var w := int(tier_weights.get(tier, 0))
		if roll < w:
			index = tier_order.find(tier)
			break
		roll -= w
	index = clampi(index, 0, entries.size() - 1)
	return str(entries[index].get("id", ""))


# Rolls and installs a random starting loadout for the current theme.
func roll_random_start() -> void:
	var theme = get_run_theme()
	if theme.is_empty():
		return
	var start: Dictionary = theme.get("start", {})

	# Chassis.
	chassis_id = _roll_weighted_chassis(theme)

	# Armor + frames per slot.
	equipped_parts.clear()
	part_damage.clear()
	armor_inventory.clear()
	equipped_frames.clear()
	var tier_weights: Dictionary = start.get("part_tier_weights", {})
	for slot in MECHA_SLOTS:
		var armor_id := _roll_armor_part(slot)
		if armor_id != "":
			var inst := make_armor_instance_from_catalog(armor_id)
			if not inst.is_empty():
				equip_armor_instance(inst["uid"], slot)
		var frame_id := _roll_frame(slot, tier_weights)
		if frame_id != "":
			equipped_frames[slot] = get_frame_catalog_entry(frame_id)
	_ensure_default_frames()

	# Weapons.
	var pool: Array = start.get("weapon_pool", [])
	if pool.is_empty():
		pool = [DEFAULT_LEFT_WEAPON_PATH, DEFAULT_RIGHT_WEAPON_PATH, DEFAULT_CARRY_WEAPON_PATH]
	var valid: Array = []
	for p in pool:
		if p is String and ResourceLoader.exists(p):
			valid.append(p)
	weapon_loadout["left"] = valid[randi() % valid.size()] if not valid.is_empty() else DEFAULT_LEFT_WEAPON_PATH
	weapon_loadout["right"] = DEFAULT_RIGHT_WEAPON_PATH
	weapon_loadout["carry"] = [DEFAULT_CARRY_WEAPON_PATH]
	weapon_inventory.clear()
	for path in [weapon_loadout["left"], weapon_loadout["right"], weapon_loadout["carry"][0]]:
		if path is String and path != "":
			register_weapon(path, "Starter")

	# Allies.
	fleet_roster.clear()
	var allies: Dictionary = start.get("allies", {})
	var templates: Array = allies.get("templates", [])
	var min_a := int(allies.get("min", 0))
	var max_a := int(allies.get("max", min_a))
	if not templates.is_empty():
		var count := randi_range(min_a, max_a)
		var shuffled := templates.duplicate()
		shuffled.shuffle()
		for tpl in shuffled.slice(0, count):
			add_ally_unit(str(tpl))

	# Resources.
	var credits_range: Array = start.get("credits", [100, 150])
	var scrap_range: Array = start.get("scrap", [0, 10])
	var cores_range: Array = start.get("data_cores", [0, 0])
	credits = randi_range(int(credits_range[0]), int(credits_range[1]))
	scrap = randi_range(int(scrap_range[0]), int(scrap_range[1]))
	data_cores = randi_range(int(cores_range[0]), int(cores_range[1]))
	ensure_hangar_roster()
	save_active_hangar_mech()


# Adds a run theme to the current run (used by theme_switch events).
func switch_theme(new_theme_id: String) -> bool:
	if not theme_switched:
		theme_id = new_theme_id
		theme_switched = true
		return true
	return false


# Adjusts run reputation and clamps it to a sane range.
func add_reputation(amount: int) -> void:
	reputation = clampi(reputation + amount, -20, 100)


# Applies a board event's effect immediately. Returns true when the event forced
# a scene transition (e.g. force_combat) — the caller should stop afterwards.
func apply_event_effect(event: Dictionary) -> bool:
	var effect := str(event.get("effect", ""))
	var amount := int(event.get("amount", 0))
	var params: Dictionary = event.get("params", {})

	match effect:
		"credits":
			credits += amount
		"scrap":
			scrap += amount
		"data_cores":
			data_cores += amount
		"damage":
			if not equipped_parts.is_empty():
				var keys = equipped_parts.keys()
				var rand_part = keys[randi() % keys.size()]
				var cur_dmg = part_damage.get(rand_part, 0.0)
				part_damage[rand_part] = minf(cur_dmg + float(amount) / 100.0, 1.0)
		"reputation":
			add_reputation(amount)
		"supply_drop":
			credits += amount
			scrap += int(params.get("scrap", 0))
		"ceasefire":
			ceasefire_turns = maxi(ceasefire_turns, int(params.get("turns", amount)))
		"add_ally":
			add_ally_unit(str(params.get("unit_id", "")))
		"heat_bonus":
			heat = maxi(0, heat + int(params.get("heat", amount)))
		"theme_switch":
			return switch_theme(str(params.get("theme_id", "")))
		"force_combat":
			blocked_intermission = true
			return true
		"choice":
			# Choices are resolved by the event UI; nothing to apply here.
			pass
		_:
			push_warning("apply_event_effect: unknown effect '%s'" % effect)
	return false


# Called when a battle ends: applies reputation from the outcome.
func on_combat_ended_for_reputation(victory: bool) -> void:
	if victory:
		add_reputation(1)
		if GameManager.is_boss_combat:
			add_reputation(2)

var current_sector: int = 1
var max_sectors: int = 3

var enemy_forces: Dictionary = {
	"boss_current": 1, "boss_max": 1,
	"ace_current": 1, "ace_max": 2,
	"grunt_current": 10, "grunt_max": 20
}

var last_combat_squad_size: int = 1
var max_notoriety_multiplier: float = 1.0
var stalking_aces: Array[String] = []
var stalking_chance: float = 0.0

var ammo_inventory: Dictionary = {
	"kinetic": 300,
	"energy": 150,
	"explosive": 30,
	"missile": 12
}

var weapon_inventory: Array = [
	{"uid": "w_starter_left", "path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "durability": 1.0, "upgrade_level": 1},
	{"uid": "w_starter_right", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "durability": 1.0, "upgrade_level": 1},
	{"uid": "w_starter_carry", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "durability": 1.0, "upgrade_level": 1}
]

const SAVE_PATH := "user://savegame.json"


func get_reserve_ammo(ammo_type: String) -> int:
	return ammo_inventory.get(ammo_type.to_lower(), 0)


func add_reserve_ammo(ammo_type: String, amount: int) -> void:
	var type = ammo_type.to_lower()
	ammo_inventory[type] = ammo_inventory.get(type, 0) + amount


func consume_reserve_ammo(ammo_type: String, amount: int) -> int:
	var type = ammo_type.to_lower()
	var current = get_reserve_ammo(type)
	var taken = mini(current, amount)
	ammo_inventory[type] = current - taken
	return taken


func register_weapon(path: String, weapon_name: String) -> void:
	weapon_inventory.append({
		"uid": _new_uid("w"),
		"path": path,
		"name": weapon_name,
		"durability": 1.0,
		"upgrade_level": 1
	})


func reset_run_data() -> void:
	equipped_parts.clear()
	part_damage.clear()
	attachments.clear()
	board_grid.clear()
	current_tile = Vector2i.ZERO
	board_seed = randi()
	heat = 0
	wanted_level = 0
	safehouse_upgrades.clear()
	credits = 110
	data_cores = 0
	scrap = 0
	current_sector = 1
	enemy_forces = {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}
	last_combat_squad_size = 1
	max_notoriety_multiplier = 1.0
	stalking_aces.clear()
	stalking_chance = 0.0

	# Run identity — a new run is a brand-new story: nothing carries over.
	theme_id = "soldier"
	reputation = 0
	theme_switched = false
	ceasefire_turns = 0
	blocked_intermission = false
	enemy_tech_tier = 1
	pending_escalation_event = false
	enemy_research_progress = 0.0
	enemy_base_active = false
	enemy_base_progress = 0.0
	enemy_base_required = 8.0
	enemy_base_tile_pos = Vector2i(-1, -1)
	enemy_grunt_upgrade_level = 0
	enemy_copy_outcome = ""
	enemy_special_units.clear()
	pending_enemy_base_spawn = false
	pending_enemy_base_outcome = false
	pending_enemy_base_destroyed = false
	pending_enemy_base_tile_reset = Vector2i(-1, -1)
	fleet_security = 25.0
	security_upgrade_level = 1
	driver_repair_skill = 1
	driver_repair_xp = 0
	scrap_patches.clear()
	_combat_friendly_total_hp = 0.0
	_combat_friendly_damage = 0.0
	last_combat_damage_ratio = 0.0
	fleet_roster.clear()
	research_projects.clear()
	research_unlocked.clear()
	chassis_id = "standard"
	equipped_frames.clear()

	ammo_inventory = {
		"kinetic": 300,
		"energy": 150,
		"explosive": 30,
		"missile": 12
	}
	weapon_inventory = [
		{"uid": "w_starter_left", "path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "durability": 1.0, "upgrade_level": 1},
		{"uid": "w_starter_right", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "durability": 1.0, "upgrade_level": 1},
		{"uid": "w_starter_carry", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "durability": 1.0, "upgrade_level": 1}
	]
	weapon_loadout = {
		"left": DEFAULT_LEFT_WEAPON_PATH,
		"right": DEFAULT_RIGHT_WEAPON_PATH,
		"carry": [DEFAULT_CARRY_WEAPON_PATH],
		"ammo": {
			"kinetic": 300,
			"energy": 150,
			"explosive": 30,
			"missile": 12
		}
	}
	armor_inventory.clear()
	ensure_default_equipped_parts()
	_ensure_default_frames()
	hangar_mechs.clear()
	active_hangar_mech_id = ""
	ensure_hangar_roster()


func save_run() -> void:
	SaveGameIO.save_run()


func load_run() -> bool:
	return SaveGameIO.load_run()
