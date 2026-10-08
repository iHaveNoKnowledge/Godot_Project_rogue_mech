extends Node

## ---------------------------------------------------------------------------
## GLOBAL DATA — run-state singleton.
##
## Heavy state has been extracted into focused managers:
##   GlobalData.currency  (CurrencyManager)
##   GlobalData.fuel      (FuelManager)
##   GlobalData.board     (BoardState)
##   GlobalData.narrative (NarrativeState)
##   GlobalData.pilot     (PilotState)
##   GlobalData.hangar    (HangarState)
##   GlobalData.weapons   (WeaponInventoryState)
##
## All callers must access state through these managers directly.
## GlobalData retains: constants, catalog data, utility helpers, and
## combat-damage tracking that is tightly coupled to event handling.
## ---------------------------------------------------------------------------

# --- Signals ---
signal armor_destroyed_permanently(slot: String, armor_data: Dictionary)

const FrameModuleSys = preload("res://scripts/systems/frame_module_system.gd")
const ResProgSys = preload("res://scripts/systems/research_progression_system.gd")
const PilotSkillSys = preload("res://scripts/systems/pilot_skill_system.gd")

# --- Managers (created as children in _ready) ---
var currency: CurrencyManager
var fuel: FuelManager
var board: BoardState
var narrative: NarrativeState
var pilot: PilotState
var hangar: HangarState
var weapons: WeaponInventoryState
var thermal_cloak  # ThermalCloakSystem instance (GDD §6.2)
var ewar  # EWarSystem instance (GDD §7 electronic warfare)
var weather_transition  # WeatherTransitionSystem instance (dynamic weather)
var selected_stance_mode: String = "combat_crouch" # "combat_crouch", "upright_formal", "wide_squat"
# --- Campaign V2 Run Identity (Phase 5AE / C1) ---
var current_campaign_scenario_id: String = ""
var current_campaign_id: String = ""
# --- Catalog databases (loaded once at startup) ---
var armor_catalog: Dictionary = {}
var chassis_catalog: Dictionary = {}
var frame_catalog: Dictionary = {}
var attachment_catalog: Array = []
var research_blueprints: Array = []
var ally_unit_templates: Dictionary = {}
var run_themes: Array = []
var run_events: Array = []

# --- Consumables & Fuel Stash ---
var fuel_inventory: Dictionary = {
	"fuel_canister": 2,
	"energy_cell_pack": 2,
	"bio_fuel_cell": 1,
}

const FUEL_CONSUMABLES: Array = [
	{
		"id": "fuel_canister",
		"name": "Diesel Fuel Canister",
		"desc": "Pressurized military fuel canister. Refuels 150 Convoy Fuel or 300 Mech Energy.",
		"convoy_fuel": 150.0,
		"mech_energy": 300.0,
		"price": 100,
	},
	{
		"id": "energy_cell_pack",
		"name": "Energy Cell Battery",
		"desc": "High-density capacitor cell. Refuels 80 Convoy Fuel or 200 Mech Energy.",
		"convoy_fuel": 80.0,
		"mech_energy": 200.0,
		"price": 75,
	},
	{
		"id": "bio_fuel_cell",
		"name": "Bio-Ethanol Fuel Tank",
		"desc": "Refined bio-fuel tank. Refuels 120 Convoy Fuel or 250 Mech Energy.",
		"convoy_fuel": 120.0,
		"mech_energy": 250.0,
		"price": 90,
	},
	{
		"id": "crude_oil_drum",
		"name": "Crude Oil Drum",
		"desc": "Raw crude oil drum. Refuels 200 Convoy Fuel.",
		"convoy_fuel": 200.0,
		"mech_energy": 100.0,
		"price": 120,
	}
]

const EMERGENCY_REPAIR_BASE_SCRAP: int = 5
const EMERGENCY_REPAIR_SCRAP_PER_ARMOR_HP: float = 0.1
const EMERGENCY_REPAIR_SCRAP_PER_FRAME_HP: float = 0.15

const MECHA_SLOTS: Array[String] = [
	"head", "body", "arm_left", "arm_right", "leg_left", "leg_right"
]

## Maps slot name -> mecha-root-relative scene node name (Head, Body, etc.).
const SLOT_TO_NODE: Dictionary = {
	"head": "Head", "body": "Body",
	"arm_left": "ArmLeft", "arm_right": "ArmRight",
	"leg_left": "LegLeft", "leg_right": "LegRight",
}

## Maps slot name -> local-space offset used for hit detection on enemies.
const SLOT_OFFSETS: Dictionary = {
	"head": Vector3(0, 2.2, 0),
	"body": Vector3(0, 1.3, 0),
	"arm_left": Vector3(-0.9, 1.4, 0),
	"arm_right": Vector3(0.9, 1.4, 0),
	"leg_left": Vector3(-0.4, 0.5, 0),
	"leg_right": Vector3(0.4, 0.5, 0),
}

## Maps slot name -> scrap wreckage box size.
const SLOT_SCRAP_SIZE: Dictionary = {
	"head": Vector3(0.5, 0.45, 0.55),
	"body": Vector3(0.9, 1.1, 0.7),
	"arm_left": Vector3(0.4, 0.8, 0.4),
	"arm_right": Vector3(0.4, 0.8, 0.4),
	"leg_left": Vector3(0.5, 0.9, 0.5),
	"leg_right": Vector3(0.5, 0.9, 0.5),
}

const SAVE_PATH := "user://savegame.json"

# Where a scrap primitive may be attached on the mech.
const SCRAP_ATTACH_OPTIONS := {
	"head": [{"name": "Head", "node": "Head"}],
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
		{"name": "Foot", "node": "LegLeft/ShinLeft/FootLeft"},
	],
	"leg_right": [
		{"name": "Thigh", "node": "LegRight"},
		{"name": "Shin", "node": "LegRight/ShinRight"},
		{"name": "Foot", "node": "LegRight/ShinRight/FootRight"},
	],
}

const FIELD_PACK_BASE_CAPACITY := 40.0
const AMMO_WEIGHT_PER_UNIT := {
	"bullet": 0.01, "heavy_round": 0.03, "shell": 0.05, "spike": 0.04,
	"energy_cell": 0.02, "rocket": 0.25, "missile": 0.50, "explosive": 0.20,
} # Full catalog lives in AmmoSystem.WEIGHTS (kept in sync by test).
const PART_TIER_SUBSTEPS: int = 4
const REPAIR_COST_PER_HP := 0.5
const DECISIVE_VICTORY_RATIO := 0.5

# --- Fuel constants ---
const BOARD_ENERGY_ROAD: float = 10.0
const BOARD_ENERGY_OFFROAD: float = 25.0
const BOARD_ENERGY_ROLLER: float = 5.0
const REFUEL_ACTION_ENERGY: float = 500.0
const BOARD_ENERGY_REGEN_PER_DAY: float = 50.0
const SAFEHOUSE_ENERGY_REGEN: float = 150.0
const CONVOY_DAILY_FUEL_REGEN: float = 30.0
const CONVOY_TRANSFER_AMOUNT: float = 60.0
const CONVOY_TRANSFER_ALERT_GAIN: int = 2
const FUEL_DEPOT_PRECISE_BONUS: float = 80.0
const FUEL_DEPOT_HEAVY_BONUS: float = 40.0
const DROP_TANK_CAPACITY_PER: float = 40.0
const DROP_TANK_MAX_ATTACHED: int = 3
const DROP_TANK_PURGE_DAMAGE: float = 15.0
const DROP_TANK_COST_CREDITS: int = 80
const SIPHON_AMOUNT: float = 50.0
const SIPHON_WALK_TIME: float = 3.0
const ENGINE_DIRT_PER_SIPHON: float = 0.25
const ENGINE_DIRT_CLEANUP_PER_DAY: float = 0.1
const ENGINE_DIRT_HEAT_MULTIPLIER: float = 1.5
const WRECKAGE_SIPHON_AMOUNT: float = 30.0
const WRECKAGE_MAX_SIPHONS: int = 3
const REIGNITION_FUEL_COST: float = 60.0
const REIGNITION_ENGINE_DIRT_COST: float = 0.15

# --- Board / hazard constants ---
const HAZARD_DUST_STORM: String = "dust_storm"
const HAZARD_TACTICAL_SMOG: String = "tactical_smog"
const HAZARD_EMP_ZONE: String = "emp_zone"
const HAZARD_RAIN: String = "rain"
const HAZARD_SANDSTORM: String = "sandstorm"
const HAZARD_FOG: String = "fog"
const DUST_STORM_ROLLER_DRAIN_MULT: float = 1.5
const DUST_STORM_SPEED_MULT: float = 0.85
const SMOG_HEAT_COOL_PENALTY: float = 0.5
const EMP_LOCK_ON_DISABLED: bool = true
const EMP_BACKUP_BLOCKED: bool = true
const RAIN_SPEED_MULT: float = 0.80
const RAIN_FUEL_DRAIN_MULT: float = 1.3
const SANDSTORM_SPEED_MULT: float = 0.65
const SANDSTORM_FUEL_DRAIN_MULT: float = 1.6
const SANDSTORM_VISIBILITY_MULT: float = 0.5
const FOG_SPEED_MULT: float = 0.90
const FOG_VISIBILITY_MULT: float = 0.35

# --- Narrative constants ---
const FLEET_SECURITY_MIN := 0.0
const FLEET_SECURITY_MAX := 100.0
const SECURITY_PER_UPGRADE := 14.0
const SECURITY_UPGRADE_BASE_COST := 35
const REPAIR_SKILL_MAX := 5
const REPAIR_XP_BASE := 30
const REPAIR_XP_PER_LEVEL := 25
const HANGAR_HARD_MAX := HangarState.HANGAR_HARD_MAX

# --- Weapon constants ---
const FRAME_UPGRADE_HP_BONUS: float = 25.0
const FRAME_UPGRADE_WEIGHT_BONUS: float = 15.0
const FRAME_UPGRADE_BASE_COST: int = 150
const DEFAULT_LEFT_WEAPON_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const DEFAULT_RIGHT_WEAPON_PATH := "res://resources/mech/stock/weapon_heat_blade.tres"
const DEFAULT_CARRY_WEAPON_PATH := "res://resources/mech/stock/weapon_combat_shotgun.tres"

# --- Last combat damage tracking (not delegated — tightly coupled to events) ---
var _combat_friendly_total_hp: float = 0.0
var _combat_friendly_damage: float = 0.0
var last_combat_damage_ratio: float = 0.0
var pre_combat_weapon_loadout: Dictionary = {}
var _combat_xp_awarded: bool = false

# --- Combat damage snapshot helper ---
func snapshot_friendly_hp(hp: float) -> void:
	_combat_friendly_total_hp = hp
	_combat_friendly_damage = 0.0

func set_friendly_damage_ratio(ratio: float) -> void:
	last_combat_damage_ratio = ratio

# INIT
# ===========================================================================

func _ready() -> void:
	# Create manager instances.
	currency = CurrencyManager.new()
	fuel = FuelManager.new()
	board = BoardState.new()
	narrative = NarrativeState.new()
	pilot = PilotState.new()
	hangar = HangarState.new()
	weapons = WeaponInventoryState.new()
	thermal_cloak = preload("res://scripts/systems/thermal_cloak_system.gd").new()
	ewar = preload("res://scripts/systems/ewar_system.gd").new()
	weather_transition = preload("res://scripts/systems/weather_transition_system.gd").new()

	_load_catalogs()
	weapons._ensure_default_frames()
	ArmorSystem.ensure_default_equipped_parts()
	migrate_legacy_attachments()
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.board_day_ended.connect(_on_board_day_ended)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.friendly_damage_received.connect(_on_friendly_damage_received)


# ===========================================================================
# CATALOG LOADING
# ===========================================================================

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


static func ensure_armor_data_schema(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return entry
	var out := entry.duplicate(true)
	if not out.has("defense_type"):
		out["defense_type"] = str(out.get("type", "standard"))
	if not out.has("resistance") or not (out["resistance"] is Dictionary):
		var dtype: String = str(out.get("defense_type", "standard"))
		match dtype:
			"heavy", "reinforced":
				out["resistance"] = {"heat": 1.0, "pierce": 0.8, "impact": 0.7}
			"energy", "heat_resistant":
				out["resistance"] = {"heat": 0.6, "pierce": 1.0, "impact": 1.0}
			"reactive":
				out["resistance"] = {"heat": 1.1, "pierce": 0.6, "impact": 0.9}
			_:
				out["resistance"] = {"heat": 1.0, "pierce": 1.0, "impact": 1.0}
	return out


static func ensure_frame_data_schema(entry: Dictionary, slot_hint: String = "") -> Dictionary:
	if entry.is_empty():
		return entry
	var out := entry.duplicate(true)
	var fid: String = str(out.get("id", ""))
	if not out.has("frame_set_id") or str(out["frame_set_id"]).strip_edges() == "":
		var ftype := str(out.get("type", "")).to_lower()
		var fname := str(out.get("name", "")).to_lower()
		if fid.contains("valkyrion") or ftype.contains("valkyrion") or fname.contains("alaya"):
			out["frame_set_id"] = "valkyrion"
		elif fid.contains("vagrant") or ftype.contains("pre-cog") or fname.contains("scrap pilgrim"):
			out["frame_set_id"] = "vagrant"
		elif fid.contains("_04") or ftype.contains("heavy") or fname.contains("fortress") or fname.contains("siege"):
			out["frame_set_id"] = "heavy"
		else:
			out["frame_set_id"] = "standard"
	if not out.has("recoil_resistance"):
		out["recoil_resistance"] = 0.0
	if not out.has("max_armor_capacity"):
		out["max_armor_capacity"] = float(out.get("hp", 50.0)) * 2.0
	if not out.has("max_armor_weight"):
		out["max_armor_weight"] = float(out.get("weight", 4.0)) * 2.5
	if not out.has("module_slots"):
		var s: String = slot_hint if slot_hint != "" else str(out.get("slot", ""))
		out["module_slots"] = 3 if (s == "body" or s == "torso") else 1
	if not out.has("generator_compatibility"):
		out["generator_compatibility"] = ["all"]
	if not out.has("backpack_compatibility"):
		out["backpack_compatibility"] = ["all"]
	if not out.has("frame_tags") or (out["frame_tags"] is Array and (out["frame_tags"] as Array).is_empty()):
		var tags: Array = []
		var ftype := str(out.get("type", "")).to_lower()
		var fname := str(out.get("name", "")).to_lower()
		if ftype.contains("heavy") or fname.contains("heavy") or fname.contains("titan"):
			tags.append("heavy")
		elif ftype.contains("medium"):
			tags.append("medium")
		elif ftype.contains("light"):
			tags.append("light")
		elif ftype.contains("valkyrion") or ftype.contains("pre-cog") or fname.contains("alaya"):
			tags.append("experimental")
		else:
			tags.append("standard")
		out["frame_tags"] = tags
	if not out.has("base_frame_id"):
		out["base_frame_id"] = fid
	if not out.has("modifications"):
		out["modifications"] = []
	if not out.has("unlocked_capabilities"):
		out["unlocked_capabilities"] = []
	# Phase 2D: Technology Metadata
	if not out.has("technology_lineage"):
		var sid := str(out.get("frame_set_id", ""))
		out["technology_lineage"] = "valkryon" if sid == "valkyrion" else "valkren"
	if not out.has("native_generation"):
		var sid := str(out.get("frame_set_id", ""))
		out["native_generation"] = 3 if sid == "valkyrion" else 1
	if not out.has("supported_families"):
		out["supported_families"] = ["all"]
	return out


func get_armor_catalog_entry(part_id: String) -> Dictionary:
	for slot in armor_catalog:
		for entry in armor_catalog[slot]:
			if entry.get("id", "") == part_id:
				return ensure_armor_data_schema(entry)
	return {}


func get_frame_catalog_entry(frame_id: String) -> Dictionary:
	for slot in frame_catalog:
		for entry in frame_catalog[slot]:
			if entry.get("id", "") == frame_id:
				return ensure_frame_data_schema(entry, slot)
	return {}


func get_frame_catalog_entry_by_name(frame_name: String) -> Dictionary:
	for slot in frame_catalog:
		for entry in frame_catalog[slot]:
			if entry.get("name", "") == frame_name:
				return ensure_frame_data_schema(entry, slot)
	return {}


func is_catalog_armor_id(part_id: String) -> bool:
	return not get_armor_catalog_entry(part_id).is_empty()


func is_catalog_frame_id(frame_id: String) -> bool:
	return not get_frame_catalog_entry(frame_id).is_empty()


# --- FRAME PROPERTIES & RPG SOCKETED MODS CATALOG ---
var frame_property_catalog: Array = [
	# Body Core & Propulsion Modules
	{
		"id": "mod_reactor_fission",
		"name": "Fission Power Core",
		"slot": "body",
		"type": "reactor",
		"desc": "Primary power reactor. +1000 Energy, +80/s Recharge rate.",
		"energy_bonus": 1000.0,
		"recharge_bonus": 80.0,
		"weight": 18.0,
		"color": Color(0.2, 0.7, 1.0)
	},
	{
		"id": "mod_flight_booster",
		"name": "High-Output Vector Thruster",
		"slot": "body",
		"type": "propulsion",
		"desc": "Aerial thruster glide system. +25% Dash Speed.",
		"dash_speed_bonus": 0.25,
		"flight_glide": true,
		"weight": 14.0,
		"color": Color(1.0, 0.5, 0.1)
	},
	{
		"id": "mod_cryo_heatsink",
		"name": "Cryogenic Heat Dissipator",
		"slot": "body",
		"type": "thermal",
		"desc": "Liquid coolant circulation. -30% Heat accumulation.",
		"heat_reduction": 0.30,
		"weight": 8.0,
		"color": Color(0.3, 0.85, 1.0)
	},
	# Head Sensor & FCS Modules
	{
		"id": "mod_targeting_fcs",
		"name": "Tactical FCS Sensor",
		"slot": "head",
		"type": "sensor",
		"desc": "+40% Lock-On tracking speed, -15% weapon spread.",
		"lock_on_bonus": 0.40,
		"spread_reduction": 0.15,
		"weight": 4.0,
		"color": Color(0.2, 1.0, 0.4)
	},
	{
		"id": "mod_threat_analyzer",
		"name": "Weakpoint Scanner",
		"slot": "head",
		"type": "sensor",
		"desc": "Analyzes armor fault lines. +15% Critical hit chance.",
		"crit_bonus": 0.15,
		"weight": 5.0,
		"color": Color(1.0, 0.3, 0.3)
	},
	# Arm Weapon Stabilizers
	{
		"id": "mod_recoil_gyro_l",
		"name": "Gyro Recoil Compensator",
		"slot": "arm_left",
		"type": "actuator",
		"desc": "Torque dampeners. -35% weapon recoil kick.",
		"recoil_reduction": 0.35,
		"weight": 6.0,
		"color": Color(0.8, 0.8, 0.3)
	},
	{
		"id": "mod_recoil_gyro_r",
		"name": "Gyro Recoil Compensator",
		"slot": "arm_right",
		"type": "actuator",
		"desc": "Torque dampeners. -35% weapon recoil kick.",
		"recoil_reduction": 0.35,
		"weight": 6.0,
		"color": Color(0.8, 0.8, 0.3)
	},
	{
		"id": "mod_melee_hydraulic_l",
		"name": "High-Torque Melee Actuator",
		"slot": "arm_left",
		"type": "actuator",
		"desc": "Reinforced arm servos. +30% Melee attack speed & damage.",
		"melee_speed_bonus": 0.30,
		"weight": 10.0,
		"color": Color(1.0, 0.4, 0.1)
	},
	{
		"id": "mod_melee_hydraulic_r",
		"name": "High-Torque Melee Actuator",
		"slot": "arm_right",
		"type": "actuator",
		"desc": "Reinforced arm servos. +30% Melee attack speed & damage.",
		"melee_speed_bonus": 0.30,
		"weight": 10.0,
		"color": Color(1.0, 0.4, 0.1)
	},
	# Leg Mobility Mods
	{
		"id": "mod_roller_overdrive_l",
		"name": "Roller Overdrive Bearings",
		"slot": "leg_left",
		"type": "mobility",
		"desc": "+30% Roller Dash speed, -20% roller energy cost.",
		"roller_speed_bonus": 0.30,
		"weight": 8.0,
		"color": Color(0.4, 0.9, 1.0)
	},
	{
		"id": "mod_roller_overdrive_r",
		"name": "Roller Overdrive Bearings",
		"slot": "leg_right",
		"type": "mobility",
		"desc": "+30% Roller Dash speed, -20% roller energy cost.",
		"roller_speed_bonus": 0.30,
		"weight": 8.0,
		"color": Color(0.4, 0.9, 1.0)
	},
	{
		"id": "mod_shock_absorbers_l",
		"name": "Hydraulic Impact Dampeners",
		"slot": "leg_left",
		"type": "mobility",
		"desc": "Zero landing stun, +20% jump height.",
		"jump_bonus": 0.20,
		"weight": 7.0,
		"color": Color(0.9, 0.7, 0.2)
	},
	{
		"id": "mod_shock_absorbers_r",
		"name": "Hydraulic Impact Dampeners",
		"slot": "leg_right",
		"type": "mobility",
		"desc": "Zero landing stun, +20% jump height.",
		"jump_bonus": 0.20,
		"weight": 7.0,
		"color": Color(0.9, 0.7, 0.2)
	}
]


func get_slot_frame_sockets(slot: String) -> int:
	var fdict = weapons.equipped_frames.get(slot)
	if fdict is Dictionary and fdict.has("sockets"):
		return int(fdict.get("sockets", 2))
	return 2


func get_frame_property_entry(mod_id: String) -> Dictionary:
	for e in frame_property_catalog:
		if e.get("id", "") == mod_id:
			return e
	var entry := FrameModuleSys.get_module(mod_id)
	if not entry.is_empty():
		return entry
	return {}


func get_equipped_frame_mods_for_slot(slot: String) -> Array:
	var result: Array = []
	var norm := FrameModuleSys.normalize_slot_name(slot)
	var seen_ids: Dictionary = {}
	# 1. Check authoritative FrameModuleSystem installed modules
	if weapons and "frame_modules" in weapons and weapons.frame_modules.has(norm):
		for mod_id in weapons.frame_modules[norm]:
			if mod_id != "":
				var mod_data = FrameModuleSys.get_module(mod_id)
				if not mod_data.is_empty():
					result.append(mod_data)
					seen_ids[mod_id] = true
	# 2. Check legacy attachments for backward compatibility
	if weapons and "attachments" in weapons:
		for att in weapons.attachments:
			if att is Dictionary and att.get("slot", "") == slot:
				var aid: String = str(att.get("id", ""))
				if not seen_ids.has(aid):
					result.append(att)
	return result


## Migrates legacy backpacks and frame properties out of attachments into their dedicated fields
func migrate_legacy_attachments() -> void:
	if weapons == null or not ("attachments" in weapons) or not (weapons.attachments is Array):
		return
	var remaining_attachments: Array = []
	for att in weapons.attachments:
		if not (att is Dictionary):
			remaining_attachments.append(att)
			continue
		var aid := str(att.get("id", ""))
		var aslot := str(att.get("slot", ""))
		# Migrate backpack if equipped_backpack is currently empty
		if aid in BackpackSystem.BACKPACKS or aslot == "backpack":
			if "equipped_backpack" in weapons and weapons.equipped_backpack.is_empty():
				weapons.equipped_backpack = att.duplicate(true)
			# Do not keep backpack inside attachments
			continue
		# Migrate module into frame_modules if not already installed
		if FrameModuleSystem.MODULE_CATALOG.has(aid):
			var norm := FrameModuleSystem.normalize_slot_name(aslot)
			var installed := false
			if norm in weapons.frame_modules and weapons.frame_modules[norm] is Array:
				for installed_id in weapons.frame_modules[norm]:
					if installed_id == aid:
						installed = true
						break
			if not installed:
				var sc := FrameModuleSystem.get_socket_count(norm)
				for s_idx in range(sc):
					if FrameModuleSystem.get_installed_module_id(norm, s_idx) == "":
						FrameModuleSystem.install_module(norm, s_idx, aid)
						break
			# Kept in attachments only if cosmetic/positional test requires it, otherwise migrated
		remaining_attachments.append(att)
	weapons.attachments = remaining_attachments


# ===========================================================================
# EVENT HANDLERS
# ===========================================================================

func _on_tile_entered(_tile_pos: Vector2i, _tile_data: Node) -> void:
	pass


func _on_board_day_ended() -> void:
	# Delegate day-end ticks to subsystems.
	fuel.day_end_tick()
	var day_prog: Dictionary = ResProgSys.dispatch_progression("board_day", 1.0)
	_notify_research_completions(day_prog.get("blueprints_completed", []))
	RecruitSystem.tick_recovery()
	# Faction R&D ticks by real time (days)
	if ResourceLoader.exists("res://scripts/systems/faction_system.gd"):
		var FactionSystemScript = load("res://scripts/systems/faction_system.gd")
		FactionSystemScript.tick_research(1.0)
		FactionSystemScript.evaluate_triggers()


func _on_combat_ended(victory: bool) -> void:
	# Preserve loadout: after victory weapons must stay equipped, not thrown to inventory
	if victory and not pre_combat_weapon_loadout.is_empty():
		var cur = weapons.weapon_loadout
		var is_empty := str(cur.get("left", "")) == "" and str(cur.get("right", "")) == "" and (cur.get("carry", []) as Array).is_empty()
		if is_empty:
			weapons.weapon_loadout = pre_combat_weapon_loadout.duplicate(true)
		else:
			# Even if not fully empty, restore any hand that got cleared (e.g., arm destroyed should stay empty, but intact hands stay)
			for hand in ["left", "right"]:
				if str(cur.get(hand, "")) == "" and str(pre_combat_weapon_loadout.get(hand, "")) != "":
					# Only restore if that arm wasn't destroyed in this battle
					var frame_key: String = "arm_left_frame" if hand == "left" else "arm_right_frame"
					if float(weapons.part_damage.get(frame_key, 0.0)) < 1.0:
						cur[hand] = pre_combat_weapon_loadout[hand]
			var pre_carry = pre_combat_weapon_loadout.get("carry", [])
			var cur_carry = cur.get("carry", [])
			if (cur_carry is Array and pre_carry is Array and cur_carry.is_empty() and not pre_carry.is_empty()):
				cur["carry"] = pre_carry.duplicate()
	# NOTE: deliberately NOT cleared here. The victory screen needs the
	# pre-battle refs to tell the player's own dropped guns apart from enemy
	# drops (auto take-back). enter_combat() overwrites it every battle, and
	# the restore above only fills empty slots, so keeping it is safe.
	# Clear environmental hazard after combat (one-shot per encounter).
	board.current_hazard = ""
	# Faction: record battle for trigger and tick research by combat time (0.5 day per battle)
	if ResourceLoader.exists("res://scripts/systems/faction_system.gd"):
		var FactionSystemScript2 = load("res://scripts/systems/faction_system.gd")
		FactionSystemScript2.tick_research(0.5)
		FactionSystemScript2.evaluate_triggers()
	# Record bond.
	if victory:
		narrative.record_battle_survived(weapons.part_damage)
	# GDD §5 Sacrifice Event: re-evaluate after EVERY battle. When the
	# pilot-mech bond is at its peak AND the machine is wrecked, the mission
	# becomes accept-able from the Safehouse (announced exactly once).
	if narrative.check_sacrifice_availability(weapons.part_damage):
		board.run_notice = "Bond is at its peak and the old machine is wrecked. A SACRIFICE MISSION awaits at the Safehouse."
	# Finalize combat damage stats.
	CombatStatsSystem.compute_last_combat_damage_ratio()
	# Encounter-specific resolution (patrol, duel, enemy base, fuel depot)
	if board.board_patrol_engagement >= 0:
		PatrolSystem.resolve_patrol_combat(victory)
	elif RecruitSystem.has_pending_duel():
		RecruitSystem.resolve_duel(victory)
	elif GameManager.combat_node_type == "enemy_base":
		if victory:
			EnemyFactionSystem.destroy_enemy_base()
	elif GameManager.combat_node_type == "fuel_depot":
		if victory:
			var bonus: float = FuelManager.FUEL_DEPOT_PRECISE_BONUS if fuel.fuel_depot_approach == "precise" else FuelManager.FUEL_DEPOT_HEAVY_BONUS
			var gained := fuel.add_mech_fuel(0, bonus)  # FuelType.CRUDE_OIL = 0
			var approach_name := "Precise" if fuel.fuel_depot_approach == "precise" else "Heavy"
			board.run_notice = "Fuel depot seized (%s approach)! +%.0f energy." % [approach_name, gained]
		else:
			board.run_notice = "The fuel depot was lost in the fighting."
		fuel.fuel_depot_approach = ""

	# Common post-combat technology, armor durability, and research progression
	EnemyFactionSystem.on_combat_ended_for_tech(victory)
	if victory and not _combat_xp_awarded:
		_combat_xp_awarded = true
		var is_decisive := CombatStatsSystem.was_decisive_victory()
		PilotSkillSys.award_combat_xp(GameManager.combat_node_type, is_decisive)
		ArmorSystem.sync_equipped_armor_durability()
		var victory_prog: Dictionary = ResProgSys.dispatch_progression("combat_victory", 2.0)
		_notify_research_completions(victory_prog.get("blueprints_completed", []))


func _on_friendly_damage_received(raw_damage: float) -> void:
	if raw_damage > 0.0:
		_combat_friendly_damage += raw_damage


func _notify_research_completions(completed_ids: Array) -> void:
	for pid in completed_ids:
		var project: Dictionary = FleetSystem.get_research_project(pid)
		if project.is_empty():
			continue
		var pname: String = str(project.get("name", pid))
		var reward_name: String = str(project.get("reward_name", project.get("reward_id", "")))
		var reward_type: String = str(project.get("reward_type", ""))
		EventBus.event_triggered.emit({
			"name": "RESEARCH COMPLETE",
			"effect": "none",
			"amount": 0,
			"desc": "%s finished! Unlocked: %s (%s)." % [pname, reward_name, reward_type.capitalize()],
		})


# ===========================================================================
# UTILITY HELPERS
# ===========================================================================

func _new_uid(prefix: String) -> String:
	return "%s_%d_%d" % [prefix, Time.get_ticks_usec(), randi() % 0xFFFFF]


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


func get_durability_ratio(inst: Variant) -> float:
	if inst is Dictionary:
		return clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)
	elif inst is Resource and "durability" in inst and inst.durability != null:
		return clampf(float(inst.durability), 0.0, 1.0)
	return 1.0


## Returns the lifetime/health durability of an equipped armor part (0.0 to 1.0)
func get_part_durability(slot: String) -> float:
	var p = weapons.equipped_parts.get(slot)
	if p is Dictionary:
		return get_durability_ratio(p)
	return 1.0


## Returns the lifetime durability of an equipped weapon (0.0 to 1.0)
func get_weapon_durability(hand: String) -> float:
	if weapons == null:
		return 1.0
	var uid := str(weapons.weapon_loadout.get(hand, "")) if "weapon_loadout" in weapons else ""
	if uid == "":
		return 1.0
	var inv_list: Array = weapons.weapon_inventory if "weapon_inventory" in weapons else []
	for w in inv_list:
		if w is Dictionary and (str(w.get("uid", "")) == uid or str(w.get("path", "")) == uid):
			return get_durability_ratio(w)
	return 1.0


## Returns the lifetime/health durability of an equipped frame (0.0 to 1.0)
func get_frame_durability(slot: String) -> float:
	var base_slot := str(slot).replace("_frame", "")
	var f = weapons.equipped_frames.get(base_slot)
	if f is Dictionary:
		return get_durability_ratio(f)
	return 1.0


## Degrades the lifetime durability of an equipped armor part (from taking damage in combat)
func degrade_part_durability(slot: String, amount: float) -> void:
	if amount <= 0.0 or weapons == null:
		return
	var p = weapons.equipped_parts.get(slot)
	if p is Dictionary and not p.is_empty():
		var cur := get_durability_ratio(p)
		var new_dur := clampf(cur - amount, 0.0, 1.0)
		p["durability"] = new_dur
		if new_dur <= 0.0:
			shatter_and_destroy_armor(slot)


## Permanently shatters and destroys an armor plate when durability hits 0.0
func shatter_and_destroy_armor(slot: String) -> void:
	if weapons == null:
		return
	var p = weapons.equipped_parts.get(slot)
	if p is Dictionary and not p.is_empty():
		var destroyed_part: Dictionary = p.duplicate(true)
		weapons.equipped_parts[slot] = {}
		# Remove from inventory if present
		if "armor_inventory" in weapons and weapons.armor_inventory is Array:
			var idx := -1
			for i in range(weapons.armor_inventory.size()):
				var item = weapons.armor_inventory[i]
				if item is Dictionary and (item == p or (item.has("uid") and item["uid"] == destroyed_part.get("uid", ""))):
					idx = i
					break
			if idx != -1:
				weapons.armor_inventory.remove_at(idx)
		armor_destroyed_permanently.emit(slot, destroyed_part)
		EventBus.armor_broken.emit(slot)


## Degrades the lifetime durability of an equipped frame
func degrade_frame_durability(slot: String, amount: float) -> void:
	if amount <= 0.0 or weapons == null:
		return
	var base_slot := str(slot).replace("_frame", "")
	var f = weapons.equipped_frames.get(base_slot)
	if f is Dictionary:
		var cur := get_durability_ratio(f)
		f["durability"] = clampf(cur - amount, 0.0, 1.0)


## Degrades the lifetime durability of an equipped weapon
func degrade_weapon_durability(slot_or_hand: String, amount: float) -> void:
	if amount <= 0.0 or weapons == null:
		return
	var uid := ""
	var slot_key := slot_or_hand
	if slot_or_hand == "shoulder_left" or slot_or_hand == "shoulder_right":
		slot_key = slot_or_hand
	elif slot_or_hand != "left" and slot_or_hand != "right":
		slot_key = "shoulder_" + slot_or_hand if (slot_or_hand == "shldr_left" or slot_or_hand == "shldr_right") else slot_or_hand
	if "weapon_loadout" in weapons:
		uid = str(weapons.weapon_loadout.get(slot_key, ""))
	elif "equipped_weapon_instances" in weapons:
		uid = str(weapons.equipped_weapon_instances.get(slot_key, ""))
	if uid == "":
		return
	var inv_list: Array = weapons.weapon_inventory if "weapon_inventory" in weapons else (weapons.inventory if "inventory" in weapons else [])
	for w in inv_list:
		if w is Dictionary and str(w.get("uid", "")) == uid:
			var cur := get_durability_ratio(w)
			w["durability"] = clampf(cur - amount, 0.0, 1.0)
			break


## Restores the lifetime durability of an equipped armor part (e.g. from Hangar Overhaul)
func restore_part_durability(slot: String, amount: float = 1.0) -> void:
	var p = weapons.equipped_parts.get(slot)
	if p is Dictionary:
		var cur := get_durability_ratio(p)
		p["durability"] = clampf(cur + amount, 0.0, 1.0)


## Restores the lifetime durability of an equipped frame
func restore_frame_durability(slot: String, amount: float = 1.0) -> void:
	var base_slot := str(slot).replace("_frame", "")
	var f = weapons.equipped_frames.get(base_slot)
	if f is Dictionary:
		var cur := get_durability_ratio(f)
		f["durability"] = clampf(cur + amount, 0.0, 1.0)


## Restores the lifetime durability of an equipped weapon
func restore_weapon_durability(hand: String, amount: float = 1.0) -> void:
	if weapons == null:
		return
	var uid := str(weapons.weapon_loadout.get(hand, "")) if "weapon_loadout" in weapons else ""
	if uid == "":
		return
	var inv_list: Array = weapons.weapon_inventory if "weapon_inventory" in weapons else []
	for w in inv_list:
		if w is Dictionary and (str(w.get("uid", "")) == uid or str(w.get("path", "")) == uid):
			var cur := get_durability_ratio(w)
			w["durability"] = clampf(cur + amount, 0.0, 1.0)
			break


## Restores the lifetime durability of any inventory item dictionary directly
func restore_item_instance_durability(item: Dictionary, amount: float = 1.0) -> void:
	if item.is_empty():
		return
	var cur := get_durability_ratio(item)
	item["durability"] = clampf(cur + amount, 0.0, 1.0)


## Finds a fuel consumable definition by its ID
func get_fuel_item_entry(item_id: String) -> Dictionary:
	for entry in FUEL_CONSUMABLES:
		if entry.get("id", "") == item_id:
			return entry.duplicate(true)
	return {}


## Returns the quantity of a fuel item currently in stock
func get_fuel_item_count(item_id: String) -> int:
	return int(fuel_inventory.get(item_id, 0))


## Adds a quantity of fuel items to the inventory stash
func add_fuel_item(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	fuel_inventory[item_id] = get_fuel_item_count(item_id) + count


## Uses a fuel consumable item to refuel the Convoy truck or recharge the Mecha
## Returns the actual fuel/energy gained (> 0 on success, 0.0 on failure/full)
func use_fuel_item(item_id: String, target: String = "convoy") -> float:
	var entry := get_fuel_item_entry(item_id)
	if entry.is_empty():
		return 0.0
	if get_fuel_item_count(item_id) <= 0:
		return 0.0

	var gained: float = 0.0
	if target == "convoy":
		var amount: float = float(entry.get("convoy_fuel", 100.0))
		gained = fuel.refuel_convoy_direct(amount)
	else:
		var amount: float = float(entry.get("mech_energy", 200.0))
		gained = fuel.refuel_mech_direct(amount)

	if gained > 0.0:
		fuel_inventory[item_id] = get_fuel_item_count(item_id) - 1
		if fuel_inventory[item_id] <= 0:
			fuel_inventory.erase(item_id)
	return gained


func scrap_attach_node_paths(slot: String) -> Array[String]:
	var paths: Array[String] = []
	for opt in SCRAP_ATTACH_OPTIONS.get(slot, []):
		if opt is Dictionary:
			var p := str(opt.get("node", ""))
			if p != "":
				paths.append(p)
	return paths


func part_tier_major(upgrade_level: int) -> int:
	return 1 + maxi(upgrade_level - 1, 0) / (PART_TIER_SUBSTEPS + 1)


func part_tier_substep(upgrade_level: int) -> int:
	return maxi(upgrade_level - 1, 0) % (PART_TIER_SUBSTEPS + 1)


func part_tier_text(upgrade_level: int) -> String:
	var major := part_tier_major(upgrade_level)
	var sub := part_tier_substep(upgrade_level)
	if sub == 0:
		return str(major)
	return "%d.%d" % [major, sub]


func part_tier_pips_filled(upgrade_level: int) -> int:
	return part_tier_substep(upgrade_level)


func part_tier_pips_text(upgrade_level: int) -> String:
	var filled := part_tier_pips_filled(upgrade_level)
	var s := ""
	for i in range(PART_TIER_SUBSTEPS):
		s += "●" if i < filled else "○"
	return s


func get_part_upgrade_cost(upgrade_level: int) -> int:
	return 50 + (maxi(upgrade_level, 1) - 1) * 25


func get_mech_power() -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	for arm in ["arm_left", "arm_right"]:
		var f = weapons.equipped_frames.get(arm, {})
		if f is Dictionary:
			power += float(f.get("carry_bonus", 0.0)) * 0.5
	return power


func get_arm_power(side: String) -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	if side != "left" and side != "right":
		return power
	var f = weapons.equipped_frames.get("arm_%s" % side, {})
	if f is Dictionary:
		power += float(f.get("carry_bonus", 0.0))
	return power


func get_leg_power() -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	for leg in ["leg_left", "leg_right"]:
		var f = weapons.equipped_frames.get(leg, {})
		if f is Dictionary:
			power += float(f.get("carry_bonus", 0.0))
	return power


# ===========================================================================
# REPAIR FACADES (delegate to RepairSystem)
# ===========================================================================

func get_repair_cost(slot: String) -> int:
	return RepairSystem.get_repair_cost(slot)

func get_emergency_repair_scrap_cost(slot: String) -> int:
	return RepairSystem.get_emergency_repair_scrap_cost(slot)

func apply_emergency_repair(slot: String, primitives: Array = []) -> Dictionary:
	return RepairSystem.apply_emergency_repair(slot, primitives)

func has_scrap_patch(slot: String) -> bool:
	return RepairSystem.has_scrap_patch(slot)

func remove_scrap_patch(slot: String) -> void:
	RepairSystem.remove_scrap_patch(slot)

func get_professional_repair_cost(slot: String) -> int:
	return RepairSystem.get_professional_repair_cost(slot)

func apply_professional_repair(slot: String) -> bool:
	return RepairSystem.apply_professional_repair(slot)

func scrap_primitive_pos(primitive: Dictionary) -> Vector3:
	return RepairSystem.scrap_primitive_pos(primitive)

func scrap_primitive_rot(primitive: Dictionary) -> Vector3:
	return RepairSystem.scrap_primitive_rot(primitive)

func scrap_primitive_scale(primitive: Dictionary) -> Vector3:
	return RepairSystem.scrap_primitive_scale(primitive)

func scrap_primitive_color(primitive: Dictionary) -> Color:
	return RepairSystem.scrap_primitive_color(primitive)

func serialize_scrap_primitive(primitive: Dictionary) -> Dictionary:
	return RepairSystem._scrap_primitive_to_json_safe(primitive)


# ===========================================================================
# SAVE / LOAD
# ===========================================================================

func save_run() -> bool:
	return SaveGameIO.save_run()

func load_run() -> bool:
	return SaveGameIO.load_run()


# ===========================================================================
# RESET
# ===========================================================================

func reset_run_data() -> void:
	currency.reset(110)
	fuel.reset()
	board.reset()
	narrative.reset()
	pilot.reset()
	hangar.reset()
	weapons.reset()
	# Phase 1 (Campaign V2): the campaign-turn counter is run state and must
	# reset with everything else so consecutive runs/tests never leak turns.
	CampaignTurnExecutive.reset()
	# Phase 2 (Campaign V2): relation overrides are run state; defs are static.
	FactionSystem.reset_relations()
	# Phase 3A (Campaign V2): strategic topology is derived per board; clear
	# any registry state so runs/tests never leak nodes or routes.
	CampaignNodeRegistry.clear()
	# Phase 3B (Campaign V2): territory control state is run state.
	CampaignTerritory.clear()
	# Phase 4 (Campaign V2): base installation records are run state.
	CampaignBase.clear()
	# Phase 5A (Campaign V2): force records are run state.
	CampaignForce.clear()
	# Phase 5B (Campaign V2): battle records are run state.
	CampaignBattle.clear()
	# Phase 5AF (Campaign V2): faction economies are run state.
	FactionEconomySystem.reset()
	# Phase 5AE (Campaign V2): active scenario identity.
	current_campaign_scenario_id = ""

	# Non-delegated state.
	_combat_friendly_total_hp = 0.0
	_combat_friendly_damage = 0.0
	last_combat_damage_ratio = 0.0
	_combat_xp_awarded = false

	# Restore defaults after weapons.reset() (it calls ensure_default_equipped_parts).
	ArmorSystem.ensure_default_equipped_parts()
	weapons._ensure_default_frames()
	HangarManager.ensure_roster()


func clear_working_set() -> void:
	weapons.clear_working_set()


func get_current_campaign_scenario_id() -> String:
	return current_campaign_scenario_id
