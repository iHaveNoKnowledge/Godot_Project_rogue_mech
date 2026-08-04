extends Node

var chassis_id: String = "standard"
var equipped_parts: Dictionary = {}
var attachments: Array = []

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

# Fleet / research catalog (blueprints for allied mechs and gundam-tier gear).
var gundam_research_projects: Array = []
var ally_unit_templates: Dictionary = {}


func _load_catalogs() -> void:
	var db = load("res://resources/data/mech_catalogs.tres") as CatalogData
	if db == null:
		push_error("Failed to load mech_catalogs.tres")
		return
	armor_catalog = db.armor_catalog
	chassis_catalog = db.chassis_catalog
	frame_catalog = db.frame_catalog
	attachment_catalog = db.attachment_catalog

	var gb = load("res://resources/data/gundam_catalogs.tres") as GundamCatalogData
	if gb == null:
		push_error("Failed to load gundam_catalogs.tres")
		return
	gundam_research_projects = gb.research_projects
	for template in gb.ally_unit_templates:
		ally_unit_templates[template.get("id", "")] = template


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


# Research timers advance with turn progress: each board move = 1 point,
# each completed combat = 2 points.
func _on_tile_entered(_tile_pos: Vector2i, _tile_data: Node) -> void:
	tick_research(1)


func _on_combat_ended(victory: bool) -> void:
	if victory:
		sync_equipped_armor_durability()
		tick_research(2)


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


# Scrap material cost to craft a catalog armor entry (derived from its stats).
func get_armor_scrap_cost(entry: Dictionary) -> int:
	var hp := float(entry.get("hp", entry.get("max_hp", 30.0)))
	var ac := float(entry.get("armor", entry.get("armor_class", 15.0)))
	var wt := float(entry.get("weight", 4.0))
	return maxi(1, int(ceil((hp + ac * 1.5 + wt * 2.0) / 20.0)))


# Credit cost to craft a catalog armor entry (derived from its stats).
func get_armor_credit_cost(entry: Dictionary) -> int:
	var hp := float(entry.get("hp", entry.get("max_hp", 30.0)))
	var ac := float(entry.get("armor", entry.get("armor_class", 15.0)))
	var wt := float(entry.get("weight", 4.0))
	return maxi(1, int(ceil((hp + ac + wt) / 15.0)))


# Attempts to craft a fresh armor instance from the catalog, spending scrap + credits.
# Returns the new instance on success, or an empty Dictionary on any failure
# (unknown id / insufficient scrap / insufficient credits).
func try_craft_armor_from_catalog(part_id: String) -> Dictionary:
	var entry := get_armor_catalog_entry(part_id)
	if entry.is_empty():
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
	var dmg := 1.0 - clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)
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
			inst["durability"] = 1.0 - clampf(float(part_damage.get(slot, 0.0)), 0.0, 1.0)
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
				inst["durability"] = 1.0 - clampf(float(part_damage.get(slot, 0.0)), 0.0, 1.0)


# Default stock weapons that the player starts with on each hand / on the back.
const DEFAULT_LEFT_WEAPON_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const DEFAULT_RIGHT_WEAPON_PATH := "res://resources/mech/stock/weapon_heat_blade.tres"
const DEFAULT_CARRY_WEAPON_PATH := "res://resources/mech/stock/weapon_combat_shotgun.tres"

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
	var total := 0.0
	var left = get_equipped_weapon("left")
	var right = get_equipped_weapon("right")
	if left:
		total += float(left.weight)
	if right:
		total += float(right.weight)
	for w in get_carry_weapons():
		total += float(w.weight)
	return total + get_field_pack_ammo_weight()


# Weight of the ammo the player chose to carry (the "ammo" loadout).
func get_field_pack_ammo_weight() -> float:
	var total := 0.0
	for ammo_type in weapon_loadout.get("ammo", {}):
		total += AMMO_WEIGHT_PER_UNIT.get(ammo_type, 0.01) * float(get_loadout_ammo(ammo_type))
	return total


# Can this weapon be added to the Field Pack without exceeding capacity?
func can_add_weapon_to_field_pack(weapon: WeaponPart) -> bool:
	if weapon == null:
		return false
	return get_field_pack_weight() + float(weapon.weight) <= get_field_pack_capacity()


# Older saves predate frame ids. Resolve a saved frame value into a full catalog
# entry so the Field Pack capacity and stats stay consistent across old save files.
func _resolve_frame_value(v: Variant) -> Variant:
	if v is Dictionary:
		var entry: Dictionary = {}
		var fid = v.get("id", "")
		if fid != "":
			entry = get_frame_catalog_entry(fid)
		if entry.is_empty():
			entry = get_frame_catalog_entry_by_name(v.get("name", ""))
		if not entry.is_empty():
			return entry.duplicate(true)
		return v.duplicate(true)
	return v


func _ensure_default_frames() -> void:
	if not equipped_frames.is_empty():
		return
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		if frame_catalog.has(slot) and frame_catalog[slot].size() > 0:
			equipped_frames[slot] = frame_catalog[slot][0].duplicate()

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
func get_loadout_weapon_weight() -> float:
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

var credits: int = 0
var data_cores: int = 0
var scrap: int = 0

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
	for project in gundam_research_projects:
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


func get_research_progress(project_id: String) -> Dictionary:
	if not research_projects.has(project_id):
		return {}
	return research_projects[project_id]


func _apply_research_reward(project_id: String) -> void:
	var project = get_research_project(project_id)
	if project.is_empty():
		return
	match project.get("reward_type", ""):
		"unit":
			add_ally_unit(str(project.get("reward_id", "")))
		"armor", "frame":
			# Unlocked gear becomes usable in the hangar. Gear entries are stored
			# by id; the hangar reads this list when building upgrade lists.
			pass

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


func save_run() -> void:
	sync_equipped_armor_durability()
	var data := {
		"chassis": chassis_id,
		"parts": _serialize_parts(),
		"frames": _serialize_frames(),
		"damage": part_damage.duplicate(),
		"attachments": _serialize_attachments(),
		"armor_inventory": _serialize_armor_inventory(),
		"position": {"x": current_tile.x, "y": current_tile.y},
		"heat": heat,
		"wanted": wanted_level,
		"credits": credits,
		"data_cores": data_cores,
		"scrap": scrap,
		"fleet_roster": fleet_roster.duplicate(true),
		"research_projects": research_projects.duplicate(true),
		"research_unlocked": research_unlocked.duplicate(),
		"sector": current_sector,
		"board_seed": board_seed,
		"enemy_forces": enemy_forces.duplicate(),
		"last_combat_squad_size": last_combat_squad_size,
		"max_notoriety_multiplier": max_notoriety_multiplier,
		"stalking_aces": stalking_aces,
		"stalking_chance": stalking_chance,
		"ammo_inventory": ammo_inventory.duplicate(),
		"weapon_inventory": weapon_inventory.duplicate(),
		"weapon_loadout": weapon_loadout.duplicate(true)
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_run() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		return false
	_restore_from_dict(data)
	return true


func _restore_from_dict(data: Dictionary) -> void:
	chassis_id = data.get("chassis", "standard")
	var frames_data = data.get("frames", {})
	if frames_data is Dictionary and not frames_data.is_empty():
		for slot in frames_data:
			equipped_frames[slot] = _resolve_frame_value(frames_data[slot])
	_ensure_default_frames()
	part_damage = data.get("damage", {})
	attachments = data.get("attachments", []).duplicate(true)
	heat = data.get("heat", 0)
	wanted_level = data.get("wanted", 0)
	credits = data.get("credits", 0) + int(data.get("spare_parts", 0))
	data_cores = data.get("data_cores", 0)
	scrap = data.get("scrap", 0)
	current_sector = data.get("sector", 1)
	board_seed = data.get("board_seed", randi())

	var loaded_roster = data.get("fleet_roster", [])
	if loaded_roster is Array:
		fleet_roster = loaded_roster.duplicate(true)
	var loaded_research = data.get("research_projects", {})
	if loaded_research is Dictionary:
		research_projects = loaded_research.duplicate(true)
	var loaded_unlocked = data.get("research_unlocked", [])
	if loaded_unlocked is Array:
		research_unlocked = loaded_unlocked.duplicate()
	
	var pos = data.get("position", {"x": 0, "y": 0})
	current_tile = Vector2i(pos.x, pos.y)

	# --- Armor instance inventory (new schema) ---
	armor_inventory = []
	var loaded_armor = data.get("armor_inventory", [])
	if loaded_armor is Array:
		for raw in loaded_armor:
			if raw is Dictionary:
				armor_inventory.append(_restore_armor_instance(raw))
	# Legacy migration: old "salvaged armor" drops become regular instances.
	var legacy_salvage = data.get("salvaged_armor_inventory", [])
	if legacy_salvage is Array:
		for item in legacy_salvage:
			if item is Dictionary:
				var inst: Dictionary = item.duplicate(true)
				inst["uid"] = _new_uid("a")
				inst["db_id"] = ""
				inst["durability"] = clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)
				inst["upgrade_level"] = 1
				inst["equipped"] = false
				armor_inventory.append(inst)

	var parts_dict: Dictionary = data.get("parts", {})
	equipped_parts.clear()
	for slot in parts_dict:
		equipped_parts[slot] = _resolve_equipped_part(parts_dict[slot])
	_ensure_equipped_parts_are_instances()
	sync_equipped_armor_durability()
		
	enemy_forces = data.get("enemy_forces", {
		"boss_current": 1, "boss_max": 1,
		"ace_current": 1, "ace_max": 2,
		"grunt_current": 10, "grunt_max": 20
	}).duplicate()
	last_combat_squad_size = data.get("last_combat_squad_size", 1)
	max_notoriety_multiplier = data.get("max_notoriety_multiplier", 1.0)
	
	stalking_aces.clear()
	var loaded_aces = data.get("stalking_aces", [])
	if loaded_aces is Array:
		stalking_aces.assign(loaded_aces)
		
	stalking_chance = data.get("stalking_chance", 0.0)

	var loaded_ammo = data.get("ammo_inventory", {})
	if loaded_ammo is Dictionary and not loaded_ammo.is_empty():
		ammo_inventory = loaded_ammo.duplicate()

	var loaded_weapons = data.get("weapon_inventory", [])
	weapon_inventory = []
	if loaded_weapons is Array:
		for entry in loaded_weapons:
			if entry is Dictionary and entry.has("uid"):
				weapon_inventory.append(entry.duplicate())
			elif entry is Dictionary:
				# Legacy count-based stash: expand each copy into its own instance.
				var count = int(entry.get("count", 1))
				for i in range(maxi(count, 1)):
					var inst: Dictionary = entry.duplicate(true)
					inst.erase("count")
					inst["uid"] = _new_uid("w")
					inst["durability"] = 1.0
					inst["upgrade_level"] = 1
					weapon_inventory.append(inst)

	var loaded_loadout = data.get("weapon_loadout", null)
	if loaded_loadout is Dictionary and not loaded_loadout.is_empty():
		weapon_loadout = loaded_loadout.duplicate(true)
		# Older saves predate the "ammo" loadout key — default to the stash.
		if not weapon_loadout.has("ammo"):
			weapon_loadout["ammo"] = {
				"kinetic": get_reserve_ammo("kinetic"),
				"energy": get_reserve_ammo("energy"),
				"explosive": get_reserve_ammo("explosive"),
				"missile": get_reserve_ammo("missile")
			}


func _serialize_parts() -> Dictionary:
	var result := {}
	for slot in equipped_parts:
		var item = equipped_parts[slot]
		if item == null:
			result[slot] = null
		elif item is Dictionary and item.has("uid"):
			# Owned instance: persist the uid reference (armor_inventory has the rest).
			result[slot] = {"uid": item["uid"], "equipped": item.get("equipped", true)}
		elif item is Resource and "resource_path" in item and item.resource_path != "":
			# Resource file: save path string for reload
			result[slot] = item.resource_path
		elif item is Dictionary:
			var pid = item.get("id", "")
			if pid != "" and is_catalog_armor_id(pid):
				# Legacy catalog part: persist only the id reference + equipped state.
				# Static stats always come from the catalog (single source of truth).
				result[slot] = {"id": pid, "equipped": item.get("equipped", true)}
			else:
				# Legacy instance part (non-catalog): persist the full dict.
				result[slot] = item.duplicate(true)
		else:
			result[slot] = str(item)
	return result


func _serialize_armor_inventory() -> Array:
	var result: Array = []
	for inst in armor_inventory:
		var copy: Dictionary = inst.duplicate(true)
		if copy.get("color") is Color:
			var c: Color = copy["color"]
			copy["color"] = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
		result.append(copy)
	return result


func _restore_armor_instance(raw: Dictionary) -> Dictionary:
	var inst := raw.duplicate(true)
	if inst.get("color") is Dictionary:
		var cd: Dictionary = inst["color"]
		inst["color"] = Color(
			float(cd.get("r", 0.5)), float(cd.get("g", 0.5)),
			float(cd.get("b", 0.5)), float(cd.get("a", 1.0))
		)
	inst["durability"] = clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)
	inst["upgrade_level"] = int(inst.get("upgrade_level", 1))
	return inst


func _serialize_frames() -> Dictionary:
	var result := {}
	for slot in equipped_frames:
		var f = equipped_frames[slot]
		if f is Dictionary and f.get("id", "") != "" and is_catalog_frame_id(f["id"]):
			# Catalog frame: persist only the id reference.
			result[slot] = {"id": f["id"]}
		else:
			result[slot] = f.duplicate(true)
	return result


# Resolves a saved equipped-part value into a usable runtime part.
#   - Resource path string -> loads the Resource
#   - Catalog id reference -> resolved fresh from armor_catalog (with instance flags)
#   - Full legacy/salvaged dict -> returned as-is (instance data, not in catalog)
func _resolve_armor_value(v: Variant) -> Variant:
	if v is String and ResourceLoader.exists(v):
		return load(v)
	if v is Dictionary:
		var pid = v.get("id", "")
		var entry: Dictionary = {}
		if pid != "":
			entry = get_armor_catalog_entry(pid)
		if not entry.is_empty():
			var resolved = entry.duplicate()
			resolved["equipped"] = v.get("equipped", true)
			return resolved
		return v.duplicate(true)
	return v


# Resolves a saved equipped-part value. Owned instances resolve to the instance
# stored in armor_inventory (shared reference); everything else falls back to the
# legacy resolver.
func _resolve_equipped_part(v: Variant) -> Variant:
	if v is Dictionary and v.has("uid"):
		var inst := get_armor_instance(str(v["uid"]))
		if not inst.is_empty():
			inst["equipped"] = v.get("equipped", true)
			return inst
	return _resolve_armor_value(v)


# Migrates any legacy equipped part (catalog id / full dict without a uid) into a
# proper instance so the whole loadout is instance-based after loading old saves.
func _ensure_equipped_parts_are_instances() -> void:
	for slot in equipped_parts.keys():
		var part = equipped_parts[slot]
		if part == null or part is Resource:
			continue
		if part is Dictionary and part.has("uid"):
			continue
		var inst: Dictionary = {}
		var pid = part.get("id", "") if part is Dictionary else ""
		if pid != "" and is_catalog_armor_id(pid):
			var created := make_armor_instance_from_catalog(pid)
			if not created.is_empty():
				inst = created
		else:
			inst = (part.duplicate(true) if part is Dictionary else {})
			inst["uid"] = _new_uid("a")
			inst["db_id"] = ""
			inst["slot"] = str(part.get("slot", slot)) if part is Dictionary else slot
			inst["durability"] = 1.0
			inst["upgrade_level"] = 1
		if not inst.is_empty():
			equip_armor_instance(inst["uid"], slot)


func _serialize_attachments() -> Array:
	var result: Array = []
	for attachment in attachments:
		var copy: Dictionary = attachment.duplicate(true)
		for key in ["position", "rotation", "scale", "size"]:
			if copy.get(key) is Vector3:
				var value: Vector3 = copy[key]
				copy[key] = {"x": value.x, "y": value.y, "z": value.z}
		result.append(copy)
	return result
