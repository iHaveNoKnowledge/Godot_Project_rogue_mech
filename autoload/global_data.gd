extends Node

var chassis_id: String = "standard"
var equipped_parts: Dictionary = {}
var attachments: Array = []

# Built mech roster. A hangar entry is a saved loadout, not a generated enemy
# capsule: it references the owned armor instances and frame catalog entries
# used to assemble that mech. The active entry mirrors the live loadout above.
# Each entry carries a stable `slot` (its parking berth in the truck convoy),
# a `pilot` (who drives it) and the loadout snapshot.
# The usable number of berths comes from HangarManager.get_capacity() (fleet
# size); HANGAR_HARD_MAX is only a physical safety cap for the stored array.
const HANGAR_HARD_MAX := 12
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
# each completed combat = 2 points. Wounded pilots also recover over board moves.
func _on_tile_entered(_tile_pos: Vector2i, _tile_data: Node) -> void:
	tick_research(1)
	RecruitSystem.tick_recovery()


func _on_combat_ended(victory: bool) -> void:
	# Finalize combat damage stats before any tech/reputation logic reads them.
	_compute_last_combat_damage_ratio()
	# A duel (recruitment fight) resolves here: win/lose decides whether the
	# rival joins, is salvaged, or simply beats the player. Duel combats never
	# touch enemy tech escalation / research tick.
	if RecruitSystem.has_pending_duel():
		RecruitSystem.resolve_duel(victory)
		return
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
	ArmorSystem.ensure_default_equipped_parts()


# -----------------------------------------------------------------------------
# ARMOR INSTANCE INVENTORY
# Each owned armor piece is a unique instance (uid) with its own durability and
# upgrade level. `part_damage[slot]` remains the live combat damage cache of the
# currently equipped instance; instance.durability is the persistent source for
# everything sitting in the inventory (equipped included, kept in sync).
# Logic lives in ArmorSystem; GlobalData keeps thin facades for its callers.
# -----------------------------------------------------------------------------

func _new_uid(prefix: String) -> String:
	return "%s_%d_%d" % [prefix, Time.get_ticks_usec(), randi() % 0xFFFFF]


func get_armor_catalog_slot(part_id: String) -> String:
	return ArmorSystem.get_armor_catalog_slot(part_id)


# Creates a fresh instance from a catalog template and adds it to armor_inventory.
func make_armor_instance_from_catalog(part_id: String) -> Dictionary:
	return ArmorSystem.make_armor_instance_from_catalog(part_id)


func get_armor_instance(uid: String) -> Dictionary:
	return ArmorSystem.get_armor_instance(uid)


# Extracts hp/armor/weight floats from a catalog entry (shared by cost formulas).
func _get_armor_cost_stats(entry: Dictionary) -> Dictionary:
	return ArmorSystem._get_armor_cost_stats(entry)


# Scrap material cost to craft a catalog armor entry (derived from its stats).
func get_armor_scrap_cost(entry: Dictionary) -> int:
	return ArmorSystem.get_armor_scrap_cost(entry)


# Credit cost to craft a catalog armor entry (derived from its stats).
func get_armor_credit_cost(entry: Dictionary) -> int:
	return ArmorSystem.get_armor_credit_cost(entry)


# True when a catalog armor entry is a gundam-tier part that must first be
# researched (its matching research project completed) before it can be crafted.
func entry_is_blueprint_locked(entry: Dictionary) -> bool:
	return ArmorSystem.entry_is_blueprint_locked(entry)


# Attempts to craft a fresh armor instance from the catalog, spending scrap + credits.
# Returns the new instance on success, or an empty Dictionary on any failure
# (unknown id / insufficient scrap / insufficient credits / blueprint not researched).
func try_craft_armor_from_catalog(part_id: String) -> Dictionary:
	return ArmorSystem.try_craft_armor_from_catalog(part_id)


# Equips an owned instance into a slot, carrying its wear into the combat cache.
func equip_armor_instance(uid: String, slot: String) -> bool:
	return ArmorSystem.equip_armor_instance(uid, slot)


func unequip_armor_instance(slot: String) -> void:
	ArmorSystem.unequip_armor_instance(slot)


# Writes the live combat damage cache back into the equipped instances' durability.
func sync_equipped_armor_durability() -> void:
	ArmorSystem.sync_equipped_armor_durability()

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
	return RepairSystem.get_repair_cost(slot)


# -----------------------------------------------------------------------------
# SCRAP PATCHES — emergency self-repair done in the intermission screen when the
# driver has no fleet mechanic available. Scrap is used to build crude armor out
# of basic primitives (boxes / spheres / wedges) placed on the mech like a Mass
# Builder frame editor. A patched slot uses WEAKER scrap stats derived from the
# driver's repair-skill tier and stays patched until a professional mechanic
# rebuilds the real armor. Repair/state logic lives in RepairSystem.
#   key: slot name
#   value: {
#     "tier": 1..5, "stat_scale": 0.40..0.80,
#     "scrap_armor_hp": float, "scrap_frame_hp": float,
#     "armor_class": float, "scrap_spent": int,
#     "primitives": [ {shape, pos, rot, scale, color, attach} ]
#   }
# -----------------------------------------------------------------------------
var scrap_patches: Dictionary = {}


# Where a scrap primitive may be attached on the mech. `node` is a
# mecha-root-relative path to the skeleton node the primitive should follow
# (so a patch on the arm can ride the upper arm, forearm, ...). The slot's
# first option is always its root skeleton node. Single source of truth shared
# by the repair editor and the combat/hangar scrap-patch renderer.
const SCRAP_ATTACH_OPTIONS := {
	"head": [
		{"name": "Head", "node": "Head"},
	],
	"body": [
		{"name": "Body", "node": "Body"},
		{"name": "Chest Plate", "node": "Body/ChestPlate"},
		{"name": "Backpack", "node": "Body/Backpack"},
	],
	"arm_left": [
		{"name": "Upper Arm", "node": "ArmLeft"},
		{"name": "Forearm", "node": "ArmLeft/ForearmLeft"},
	],
	"arm_right": [
		{"name": "Upper Arm", "node": "ArmRight"},
		{"name": "Forearm", "node": "ArmRight/ForearmRight"},
	],
	"leg_left": [
		{"name": "Thigh", "node": "LegLeft"},
		{"name": "Shin", "node": "LegLeft/ShinLeft"},
	],
	"leg_right": [
		{"name": "Thigh", "node": "LegRight"},
		{"name": "Shin", "node": "LegRight/ShinRight"},
	],
}


# Mecha-root-relative skeleton node paths a scrap patch on `slot` can attach to.
# Includes the slot's own root node as the first entry.
func scrap_attach_node_paths(slot: String) -> Array[String]:
	var paths: Array[String] = []
	for opt in SCRAP_ATTACH_OPTIONS.get(slot, []):
		if opt is Dictionary:
			var p := str(opt.get("node", ""))
			if p != "":
				paths.append(p)
	return paths


const EMERGENCY_REPAIR_BASE_SCRAP := 5
const EMERGENCY_REPAIR_SCRAP_PER_ARMOR_HP := 0.04
const EMERGENCY_REPAIR_SCRAP_PER_FRAME_HP := 0.03


# Scrap cost to emergency-patch a slot, based on how much of it is damaged.
func get_emergency_repair_scrap_cost(slot: String) -> int:
	return RepairSystem.get_emergency_repair_scrap_cost(slot)


# Builds and records a scrap patch on a slot: spends scrap, restores the slot to
# a partial weaker state (stats scaled by the driver's repair-skill tier) and
# clears its damage. Returns the patch, or {} when the slot is fine / unaffordable.
func apply_emergency_repair(slot: String, primitives: Array = []) -> Dictionary:
	return RepairSystem.apply_emergency_repair(slot, primitives)


# Converts a scrap primitive's Vector3/Color fields into JSON-safe arrays.
func _scrap_primitive_to_json_safe(primitive: Dictionary) -> Dictionary:
	return RepairSystem._scrap_primitive_to_json_safe(primitive)


func scrap_primitive_pos(primitive: Dictionary) -> Vector3:
	return RepairSystem.scrap_primitive_pos(primitive)


func scrap_primitive_rot(primitive: Dictionary) -> Vector3:
	return RepairSystem.scrap_primitive_rot(primitive)


func scrap_primitive_scale(primitive: Dictionary) -> Vector3:
	return RepairSystem.scrap_primitive_scale(primitive)


func scrap_primitive_color(primitive: Dictionary) -> Color:
	return RepairSystem.scrap_primitive_color(primitive)


func has_scrap_patch(slot: String) -> bool:
	return RepairSystem.has_scrap_patch(slot)


func remove_scrap_patch(slot: String) -> void:
	RepairSystem.remove_scrap_patch(slot)


# -----------------------------------------------------------------------------
# PROFESSIONAL REPAIR — a fleet mechanic / village workshop rebuilds a scrap-
# patched (or damaged) slot into fresh catalog armor. Costs credits and consumes
# the node you're standing on. Returns the credit price for the slot.
# -----------------------------------------------------------------------------
const PROFESSIONAL_REPAIR_CREDITS_PER_ARMOR_HP := 1.0
const PROFESSIONAL_REPAIR_CREDITS_PER_FRAME_HP := 0.75


func get_professional_repair_cost(slot: String) -> int:
	return RepairSystem.get_professional_repair_cost(slot)


# The mechanic rebuilds the slot: removes any scrap patch, clears all damage and
# restores the real catalog armor at full HP. Returns false if unaffordable.
func apply_professional_repair(slot: String) -> bool:
	return RepairSystem.apply_professional_repair(slot)


# Maps a mech slot name to the mecha-root-relative node path holding that
# section's meshes. Single source of truth for all part visuals.
func get_slot_node_path(slot: String) -> String:
	return LoadoutSystem.get_slot_node_path(slot)


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
# Logic lives in LoadoutSystem; GlobalData keeps thin facades.
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
	return LoadoutSystem.get_field_pack_capacity()


# Current Field Pack load weight in kg (hand weapons + carry weapons + ammo).
func get_field_pack_weight() -> float:
	return LoadoutSystem.get_field_pack_weight()


# Weight of the ammo the player chose to carry (the "ammo" loadout).
func get_field_pack_ammo_weight() -> float:
	return LoadoutSystem.get_field_pack_ammo_weight()


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


func build_hangar_mech(mech_name: String = "", requested_slot: int = 0) -> Dictionary:
	return HangarManager.build(mech_name, requested_slot)


# Resource cost to assemble a new frame into an empty berth (roster REGISTER).
# Single source of truth so every UI shows the same price.
func get_frame_register_scrap_cost() -> int:
	return HangarManager.REGISTER_SCRAP_COST


func get_frame_register_credit_cost() -> int:
	return HangarManager.REGISTER_CREDIT_COST


func get_backup_hangar_mech_id() -> String:
	return HangarManager.get_backup_id()


func switch_hangar_mech(mech_id: String) -> bool:
	return HangarManager.switch_mech(mech_id)


# Loads a parked mech's parts into the working set for editing WITHOUT changing
# which mech the player actually pilots (active). Used by the customize page so
# you can tune any berth while keeping the combat mech as-is.
func load_hangar_mech_state(mech_id: String) -> bool:
	return HangarManager.load_mech_state(mech_id)


# Persists the current working set back onto a specific parked mech. Unlike
# save_active_hangar_mech(), this targets any berth, so edits to a non-active
# mech on the customize page are saved to the right entry.
func save_hangar_mech_state(mech_id: String) -> bool:
	return HangarManager.save_mech_state(mech_id)


# Replaces a parked mech's loadout with the given snapshot while preserving its
# identity (id/name/slot/pilot/archetype). Used to undo working-set edits that
# leaked onto a berth during the REGISTER assembly flow.
func restore_berth_loadout(mech_id: String, snapshot: Dictionary) -> bool:
	return HangarManager.restore_berth_loadout(mech_id, snapshot)


# Fleet-driven convoy capacity: number of parking berths the hangar has.
func get_hangar_capacity() -> int:
	return HangarManager.get_capacity()


# Number of pilots in the convoy (the player driver + every fleet unit).
func get_hangar_fleet_size() -> int:
	return HangarManager.get_fleet_size()


# Physical hard cap of the stored roster array.
func get_hangar_hard_max() -> int:
	return HangarManager.get_hard_max()


# All assignable pilots: {"id": "...", "name": "..."}.
func get_hangar_pilots() -> Array:
	return HangarManager.get_pilots()


func get_hangar_pilot_name(pilot_id: String) -> String:
	return HangarManager.get_pilot_name(pilot_id)


# Reassigns the pilot driving a parked mech (swaps when the pilot already has a
# mech). Caller persists with save_run().
func assign_hangar_pilot(mech_id: String, pilot_id: String) -> bool:
	return HangarManager.assign_pilot(mech_id, pilot_id)


# Renames a parked mech (identity field only; blank name falls back to the
# slot-based name). Caller persists with save_run().
func rename_hangar_mech(mech_id: String, new_name: String) -> bool:
	return HangarManager.rename_mech(mech_id, new_name)


# Combat archetype a parked mech fights as when fielded as an ally (see
# HangarManager.ARCHETYPE_*). Caller persists with save_run().
func get_hangar_archetype(mech_id: String) -> int:
	return HangarManager.get_archetype(mech_id)


func set_hangar_archetype(mech_id: String, archetype: int) -> bool:
	return HangarManager.set_archetype(mech_id, archetype)


# Parking berth (slot number) of a stored mech, 0 when unknown.
func get_hangar_slot_of(mech_id: String) -> int:
	return HangarManager.get_slot_of(mech_id)


# Removes a destroyed mech from the roster (switches the active mech away first).
func remove_hangar_mech(mech_id: String) -> bool:
	return HangarManager.remove_mech(mech_id)


# True when the player is pilot-only but the convoy has squadmates left, so a
# defeat retreats instead of ending the run.
func can_mechless_retreat() -> bool:
	return HangarManager.can_mechless_retreat()


# Builds a fresh walking chassis from convoy spares and ends pilot-only mode.
func grant_recovery_hangar_mech() -> Dictionary:
	return HangarManager.grant_recovery_mech()

# -----------------------------------------------------------------------------
# WEAPON LOADOUT — central state for what the mech carries into battle.
# "left"/"right" are the hand weapons (resource path, "" = unarmed hand).
# "carry" is the array of weapon paths the mech carries on its back.
# "ammo" is how much ammo of each type the player allocates to bring into battle.
# Configured in the Hangar, read by WeaponManager at battle start.
# Logic lives in LoadoutSystem; GlobalData keeps thin facades for its callers.
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

# Owned reserve ammo (replenished between battles, spent by the hangar/board).
var ammo_inventory: Dictionary = {
	"kinetic": 300,
	"energy": 150,
	"explosive": 30,
	"missile": 12
}

# Owned weapon collection (each entry: uid/path/name/durability/upgrade_level).
var weapon_inventory: Array = [
	{"uid": "w_starter_left", "path": "res://resources/mech/stock/weapon_beam_rifle.tres", "name": "Beam Rifle", "durability": 1.0, "upgrade_level": 1},
	{"uid": "w_starter_right", "path": "res://resources/mech/stock/weapon_heat_blade.tres", "name": "Heat Blade", "durability": 1.0, "upgrade_level": 1},
	{"uid": "w_starter_carry", "path": "res://resources/mech/stock/weapon_combat_shotgun.tres", "name": "Combat Shotgun", "durability": 1.0, "upgrade_level": 1}
]


# Returns the equipped WeaponPart for the given hand ("left"/"right").
# Reads the central weapon_loadout so the Hangar and battle share one source.
# An explicitly-unarmed hand ("") returns null; only a missing/blank slot falls
# back to the default stock weapon for that hand.
func get_equipped_weapon(side: String) -> WeaponPart:
	return LoadoutSystem.get_equipped_weapon(side)


# Returns the WeaponParts the mech carries on its back into battle (from loadout).
func get_carry_weapons() -> Array[WeaponPart]:
	return LoadoutSystem.get_carry_weapons()


# Total weight of all loadout weapons (both hands + back).
func get_loadout_weapons_total() -> float:
	return LoadoutSystem.get_loadout_weapons_total()


# Total weight of all loadout weapons (both hands + back).
func get_loadout_weapon_weight() -> float:
	return LoadoutSystem.get_loadout_weapon_weight()


# Assigns a weapon resource path to a hand. Empty path = unarmed hand.
func set_hand_weapon(side: String, path: String) -> void:
	LoadoutSystem.set_hand_weapon(side, path)


func is_weapon_in_carry(path: String) -> bool:
	return LoadoutSystem.is_weapon_in_carry(path)


func add_carry_weapon(path: String) -> void:
	LoadoutSystem.add_carry_weapon(path)


func remove_carry_weapon(path: String) -> void:
	LoadoutSystem.remove_carry_weapon(path)


# How many physical copies of a weapon model are currently on the back pack.
func count_carry_weapon(path: String) -> int:
	return LoadoutSystem.count_carry_weapon(path)


# Returns how much ammo of the given type the player carries into the next battle.
func get_loadout_ammo(ammo_type: String) -> int:
	return LoadoutSystem.get_loadout_ammo(ammo_type)


# Sets how much ammo of the given type the player carries into the next battle.
func set_loadout_ammo(ammo_type: String, amount: int) -> void:
	LoadoutSystem.set_loadout_ammo(ammo_type, amount)


func get_loadout_ammo_dict() -> Dictionary:
	return LoadoutSystem.get_loadout_ammo_dict()


func get_equipped_part_id(slot: String) -> String:
	return LoadoutSystem.get_equipped_part_id(slot)


# Returns the chassis stats dict for the currently selected chassis_id.
# Used by mecha_controller at combat start so it doesn't rely on @export chassis resource.
# Keys: "speed" (float), "max_weight" (float), "color" (Color), "name" (String)
func get_chassis_stats() -> Dictionary:
	return LoadoutSystem.get_chassis_stats()


# Total mech Power: chassis base + arm-frame strength that contributes to
# supporting heavy weapons in a single hand.
func get_mech_power() -> float:
	var power := float(get_chassis_stats().get("power", 12.0))
	for arm in ["arm_left", "arm_right"]:
		var f = equipped_frames.get(arm, {})
		if f is Dictionary:
			power += float(f.get("carry_bonus", 0.0)) * 0.5
	return power


# Equipped inner frames. Values are full catalog-entry dicts at runtime; the
# save file persists only {"id": ...} references (see _serialize_frames).
var equipped_frames: Dictionary = {}
var frame_upgrade_level: int = 1


const FRAME_UPGRADE_HP_BONUS: float = 25.0
const FRAME_UPGRADE_WEIGHT_BONUS: float = 15.0
const FRAME_UPGRADE_BASE_COST: int = 150


func get_frame_upgrade_hp_bonus() -> float:
	return LoadoutSystem.get_frame_upgrade_hp_bonus()


func get_frame_upgrade_weight_bonus() -> float:
	return LoadoutSystem.get_frame_upgrade_weight_bonus()


func get_frame_upgrade_cost() -> int:
	return LoadoutSystem.get_frame_upgrade_cost()

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
# Sector-progression floor for wanted_level, raised by HeatWantedSystem.escalate_wanted().
var wanted_escalation: int = 0
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

# PILOT-ONLY MODE — true while the convoy owns no mech (the player fights on
# foot). Set when the last parked mech is destroyed in battle; cleared when a
# recovery event or reward grants a fresh chassis. While true the hangar roster
# stays empty and board "combat" tiles become recovery events.
var mech_less: bool = false

# Text shown to the player on the next screen after an event's effect lands
# (e.g. "Scrap truck driver joins your convoy"). Cleared on read.
var run_notice: String = ""

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
# Logic lives in FleetSystem; GlobalData keeps thin facades for its callers.
# -----------------------------------------------------------------------------
var fleet_roster: Array = []

# -----------------------------------------------------------------------------
# RECRUITABLE CHARACTERS — named pilots met on the board (see RecruitSystem).
# - recruited_characters: character ids already met/resolved this run, so the
#   same pilot can't be recruited or duelled twice.
# - pending_duel: {"character_id", "intent"} while a duel battle is live;
#   consumed by RecruitSystem when that combat ends.
# - duel_result_text: outcome text for the combat rewards screen after a duel.
# -----------------------------------------------------------------------------
var recruited_characters: Array = []
var pending_duel: Dictionary = {}
var duel_result_text: String = ""

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
	return FleetSystem.get_fleet_security()


func get_security_upgrade_cost() -> int:
	return FleetSystem.get_security_upgrade_cost()


# Spend credits to raise fleet security. Returns false if unaffordable or maxed.
func upgrade_fleet_security() -> bool:
	return FleetSystem.upgrade_fleet_security()


# Chance (0..1) that an enemy spy attempt on our mech data FAILS before stealing
# anything. 25 = starting security, 50 = one strong investment, 90+ = fortress.
func get_spy_counter_chance() -> float:
	return FleetSystem.get_spy_counter_chance()


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
	return FleetSystem.get_repair_skill_xp_for_next(level)


# Returns true when the XP gain pushed the skill to a new tier.
func gain_repair_xp(amount: int) -> bool:
	return FleetSystem.gain_repair_xp(amount)


# The scrap armor tier the driver can build right now (1..5).
func get_scrap_armor_tier() -> int:
	return FleetSystem.get_scrap_armor_tier()


# Stats multiplier for scrap-built armor vs the real catalog part. Tier 1 gives
# 40% of the real stats, each tier +10% up to 80% — scrap can never match a
# properly-crafted armor plate.
func get_scrap_armor_stat_scale() -> float:
	return FleetSystem.get_scrap_armor_stat_scale()


func get_ally_template(template_id: String) -> Dictionary:
	return FleetSystem.get_ally_template(template_id)


func get_fielded_units() -> Array:
	return FleetSystem.get_fielded_units()


func get_fleet_unit(template_id: String) -> Dictionary:
	return FleetSystem.get_fleet_unit(template_id)


func has_ally_unit(template_id: String) -> bool:
	return FleetSystem.has_ally_unit(template_id)


func add_ally_unit(template_id: String) -> bool:
	return FleetSystem.add_ally_unit(template_id)


func set_unit_fielded(template_id: String, fielded: bool) -> void:
	FleetSystem.set_unit_fielded(template_id, fielded)


# --- Recruitable characters (see RecruitSystem) -----------------------------

func get_recruit_character(character_id: String) -> Dictionary:
	return RecruitSystem.get_character(character_id)


func is_character_recruited(character_id: String) -> bool:
	return RecruitSystem.is_character_recruited(character_id)


func is_recruit_event_available(event: Dictionary) -> bool:
	return RecruitSystem.is_event_available(event)


# --- Research base ----------------------------------------------------------

func get_research_project(project_id: String) -> Dictionary:
	return FleetSystem.get_research_project(project_id)


func is_research_active(project_id: String) -> bool:
	return FleetSystem.is_research_active(project_id)


func is_research_completed(project_id: String) -> bool:
	return FleetSystem.is_research_completed(project_id)


# Start a research project: consumes data_cores (the blueprint) and begins the
# clock. Research time progresses via board moves (tick_research(1)) and
# completed combats (tick_research(2)).
func start_research(project_id: String) -> bool:
	return FleetSystem.start_research(project_id)


# Advance all active research by `points`. Returns project ids completed now.
func tick_research(points: int) -> Array:
	return FleetSystem.tick_research(points)


func _apply_research_reward(project_id: String) -> void:
	FleetSystem._apply_research_reward(project_id)

# -----------------------------------------------------------------------------
# RUN THEME HELPERS — logic lives in ThemeSystem; GlobalData keeps thin facades.
# -----------------------------------------------------------------------------

func get_run_theme() -> Dictionary:
	return ThemeSystem.get_run_theme()


func get_theme_event_pool() -> Array:
	return ThemeSystem.get_theme_event_pool()


func get_weighted_recovery_event() -> Dictionary:
	return ThemeSystem.get_weighted_recovery_event()


func get_run_affiliation() -> Dictionary:
	return ThemeSystem.get_affiliation()


func get_run_event(event_id: String) -> Dictionary:
	return ThemeSystem.get_run_event(event_id)


func get_theme_ending() -> Dictionary:
	return ThemeSystem.get_theme_ending()


# -----------------------------------------------------------------------------
# ENEMY TECH ESCALATION — see state block near the theme fields. Logic lives in
# EnemyFactionSystem; GlobalData keeps thin facades.
# -----------------------------------------------------------------------------

# Per-theme escalation tuning; falls back to sensible defaults.
func get_escalation_config() -> Dictionary:
	return EnemyFactionSystem.get_escalation_config()


# Called when a battle ends. The enemy tiers up one step when we win a battle
# DECISIVELY — i.e. we took at most 50% of our combined fielded HP in damage.
# Decisive wins prove our gear works, so the enemy copies it. Non-decisive
# wins or losses don't escalate (our build barely worked / we failed).
func on_combat_ended_for_tech(victory: bool) -> void:
	EnemyFactionSystem.on_combat_ended_for_tech(victory)


func _try_escalate(cfg: Dictionary) -> void:
	EnemyFactionSystem._try_escalate(cfg)


# Returns true once so the board can surface the "enemy upgraded" popup when
# the player returns from combat.
func consume_pending_escalation_event() -> bool:
	return EnemyFactionSystem.consume_pending_escalation_event()


# Multiplier applied to freshly spawned enemy HP/damage based on tech tier.
func get_enemy_tech_multiplier() -> float:
	return EnemyFactionSystem.get_enemy_tech_multiplier()


# Combined spawn scaling including the partial grunt upgrades salvaged from
# destroyed research nodes. Grunts get tougher even without a full tier-up.
func get_enemy_grunt_multiplier() -> float:
	return EnemyFactionSystem.get_enemy_grunt_multiplier()


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

# -----------------------------------------------------------------------------
# RUN PROGRESSION + ENEMY STALKING
# - current_sector / max_sectors: board sector the run is on.
# - enemy_forces: pool of enemy unit budgets used by spawn logic.
# - stalking_aces: counter-units from completed research nodes that hunt the
#   player across the board (see EnemyFactionSystem._add_stalking_ace).
# -----------------------------------------------------------------------------
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

# Probability that the enemy attempts a spy this move (0..1).
func get_spy_attempt_chance() -> float:
	return EnemyFactionSystem.get_spy_attempt_chance()


# Rolls a full spy event for the current board move. Returns a Dictionary the
# board can surface. On success, enemy_research_progress is bumped.
func roll_spy_event() -> Dictionary:
	return EnemyFactionSystem.roll_spy_event()


func _get_enemy_research_cap() -> float:
	return EnemyFactionSystem._get_enemy_research_cap()


# -----------------------------------------------------------------------------
# ENEMY RESEARCH NODE LIFECYCLE — the spawned board node and its outcome.
# Logic lives in EnemyFactionSystem; GlobalData keeps thin facades.
# -----------------------------------------------------------------------------

# Called by the board once it has physically placed the enemy_base tile.
func consume_enemy_base_spawn_request() -> bool:
	return EnemyFactionSystem.consume_enemy_base_spawn_request()


# Advance the research node's counter-unit progress (1 per board move).
# Returns true when the enemy completes their counter-unit.
func tick_enemy_base_progress(points: float) -> bool:
	return EnemyFactionSystem.tick_enemy_base_progress(points)


func _enemy_base_completed() -> void:
	EnemyFactionSystem._enemy_base_completed()


# The player reached and destroyed the node. The enemy only salvages a partial
# grunt upgrade instead of a full counter-unit.
func destroy_enemy_base() -> void:
	EnemyFactionSystem.destroy_enemy_base()


# Returns the board tile position that must be reset (consumed once), or
# Vector2i(-1, -1) when there is nothing to reset.
func consume_enemy_base_tile_reset() -> Vector2i:
	return EnemyFactionSystem.consume_enemy_base_tile_reset()


func consume_pending_enemy_base_outcome() -> bool:
	return EnemyFactionSystem.consume_pending_enemy_base_outcome()


func consume_pending_enemy_base_destroyed() -> bool:
	return EnemyFactionSystem.consume_pending_enemy_base_destroyed()


# Outcome probabilities shift toward stronger copies as the enemy tier rises.
func _roll_enemy_base_outcome() -> String:
	return EnemyFactionSystem._roll_enemy_base_outcome()


func _apply_enemy_base_outcome(outcome: String) -> void:
	EnemyFactionSystem._apply_enemy_base_outcome(outcome)


# A completed research node deploys its counter-unit as a stalking ace that
# hunts the player across the board. Once deployed it starts accumulating
# ambush chance with every move and will force a fight.
func _add_stalking_ace(ace_kind: String) -> void:
	EnemyFactionSystem._add_stalking_ace(ace_kind)


# Snapshot the combined max HP of every friendly unit in the current scene:
# the player mech + all fielded allies. Also resets the damage accumulator.
func begin_combat_stats() -> void:
	CombatStatsSystem.begin_combat_stats()


# Allow tests / callers to supply the snapshot directly without a live scene.
func set_combat_hp_snapshot(total_hp: float) -> void:
	CombatStatsSystem.set_combat_hp_snapshot(total_hp)


func get_combat_friendly_total_hp() -> float:
	return CombatStatsSystem.get_combat_friendly_total_hp()


func get_combat_friendly_damage() -> float:
	return CombatStatsSystem.get_combat_friendly_damage()


# ratio = friendly damage taken / combined friendly HP. 0 if nothing fielded.
func _compute_last_combat_damage_ratio() -> void:
	CombatStatsSystem.compute_last_combat_damage_ratio()


# A victory is "decisive" when we took at most 50% of our combined HP in damage.
func was_decisive_victory() -> bool:
	return CombatStatsSystem.was_decisive_victory()


# Picks a weighted-random chassis key from a theme's chassis_weights.
func _roll_weighted_chassis(theme: Dictionary) -> String:
	return RunStartSystem.roll_weighted_chassis(theme)


# Picks a random catalog part id for an armor slot (lowest tier always exists).
func _roll_armor_part(slot: String) -> String:
	return RunStartSystem.roll_armor_part(slot)


# Picks a frame id for a slot weighted by part_tier_weights.
# frame_catalog[slot] is ordered: [standard, gundam, medium, heavy] per slot.
func _roll_frame(slot: String, tier_weights: Dictionary) -> String:
	return RunStartSystem.roll_frame(slot, tier_weights)


# Rolls and installs a random starting loadout for the current theme.
func roll_random_start() -> void:
	RunStartSystem.roll_random_start()


# Adds a run theme to the current run (used by theme_switch events).
func switch_theme(new_theme_id: String) -> bool:
	return ThemeSystem.switch_theme(new_theme_id)


# Adjusts run reputation and clamps it to a sane range.
func add_reputation(amount: int) -> void:
	ThemeSystem.add_reputation(amount)


# Applies a board event's effect immediately. Returns true when the event forced
# a scene transition (e.g. force_combat) — the caller should stop afterwards.
func apply_event_effect(event: Dictionary) -> bool:
	return ThemeSystem.apply_event_effect(event)


# Called when a battle ends: applies reputation from the outcome.
func on_combat_ended_for_reputation(victory: bool) -> void:
	ThemeSystem.on_combat_ended_for_reputation(victory)


# -----------------------------------------------------------------------------
# RESERVE AMMO / WEAPON INVENTORY — logic lives in LoadoutSystem; GlobalData
# keeps thin facades for its callers.
# -----------------------------------------------------------------------------

func get_reserve_ammo(ammo_type: String) -> int:
	return LoadoutSystem.get_reserve_ammo(ammo_type)


func add_reserve_ammo(ammo_type: String, amount: int) -> void:
	LoadoutSystem.add_reserve_ammo(ammo_type, amount)


func consume_reserve_ammo(ammo_type: String, amount: int) -> int:
	return LoadoutSystem.consume_reserve_ammo(ammo_type, amount)


func register_weapon(path: String, weapon_name: String) -> void:
	LoadoutSystem.register_weapon(path, weapon_name)


func reset_run_data() -> void:
	equipped_parts.clear()
	part_damage.clear()
	attachments.clear()
	board_grid.clear()
	current_tile = Vector2i.ZERO
	board_seed = randi()
	heat = 0
	wanted_level = 0
	wanted_escalation = 0
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
	mech_less = false
	run_notice = ""
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
	recruited_characters.clear()
	pending_duel.clear()
	duel_result_text = ""
	research_projects.clear()
	research_unlocked.clear()
	chassis_id = "standard"
	equipped_frames.clear()
	frame_upgrade_level = 1

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


const SAVE_PATH := "user://savegame.json"


func save_run() -> void:
	SaveGameIO.save_run()


func load_run() -> bool:
	return SaveGameIO.load_run()
