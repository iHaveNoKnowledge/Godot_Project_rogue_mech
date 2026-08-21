extends Node

## ---------------------------------------------------------------------------
## GLOBAL DATA — run-state singleton.
##
## Refactored: heavy state has been extracted into focused managers.  GlobalData
## now instantiates each manager as a child node and exposes backward-compatible
## proxy properties so the ~2200 existing `GlobalData.X` callers keep working
## without modification.  New code should reference the managers directly.
## ---------------------------------------------------------------------------

# --- Managers (created as children in _ready) ---
var currency: CurrencyManager
var fuel: FuelManager
var board: BoardState
var narrative: NarrativeState
var pilot: PilotState
var hangar: HangarState
var weapons: WeaponInventoryState

# --- Catalog databases (loaded once at startup) ---
var armor_catalog: Dictionary = {}
var chassis_catalog: Dictionary = {}
var frame_catalog: Dictionary = {}
var attachment_catalog: Array = []
var research_blueprints: Array = []
var ally_unit_templates: Dictionary = {}
var run_themes: Array = []
var run_events: Array = []

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
	],
	"leg_right": [
		{"name": "Thigh", "node": "LegRight"},
		{"name": "Shin", "node": "LegRight/ShinRight"},
	],
}

const FIELD_PACK_BASE_CAPACITY := 40.0
const AMMO_WEIGHT_PER_UNIT := {
	"kinetic": 0.01, "energy": 0.02, "explosive": 0.20, "missile": 0.50,
}
const PART_TIER_SUBSTEPS: int = 4
const REPAIR_COST_PER_HP := 0.5
const DECISIVE_VICTORY_RATIO := 0.5

# --- Last combat damage tracking (not delegated — tightly coupled to events) ---
var _combat_friendly_total_hp: float = 0.0
var _combat_friendly_damage: float = 0.0
var last_combat_damage_ratio: float = 0.0

# --- Combat damage snapshot helper ---
func snapshot_friendly_hp(hp: float) -> void:
	_combat_friendly_total_hp = hp
	_combat_friendly_damage = 0.0

func set_friendly_damage_ratio(ratio: float) -> void:
	last_combat_damage_ratio = ratio


# ===========================================================================
# BACKWARD-COMPATIBLE PROXY PROPERTIES
# ===========================================================================

# --- Currency proxies ---
var credits: int:
	get: return currency.credits
	set(v): currency.credits = v

var scrap: int:
	get: return currency.scrap
	set(v): currency.scrap = v

var data_cores: int:
	get: return currency.data_cores
	set(v): currency.data_cores = v

func try_spend_credits(amount: int) -> bool:
	return currency.try_spend_credits(amount)

func gain_credits(amount: int) -> void:
	currency.gain_credits(amount)

func try_spend_scrap(amount: int) -> bool:
	return currency.try_spend_scrap(amount)

func gain_scrap(amount: int) -> void:
	currency.gain_scrap(amount)

func try_spend_data_cores(amount: int) -> bool:
	return currency.try_spend_data_cores(amount)

func gain_data_cores(amount: int) -> void:
	currency.gain_data_cores(amount)

# --- Fuel proxies ---
var mech_energy: float:
	get: return fuel.mech_energy
	set(v): fuel.mech_energy = v

var mech_max_energy: float:
	get: return fuel.mech_max_energy
	set(v): fuel.mech_max_energy = v

var board_roller_mode: bool:
	get: return fuel.board_roller_mode
	set(v): fuel.board_roller_mode = v

var convoy_fuel_reserve: float:
	get: return fuel.convoy_fuel_reserve
	set(v): fuel.convoy_fuel_reserve = v

var convoy_fuel_max: float:
	get: return fuel.convoy_fuel_max
	set(v): fuel.convoy_fuel_max = v

var fuel_depot_seized_today: bool:
	get: return fuel.fuel_depot_seized_today
	set(v): fuel.fuel_depot_seized_today = v

var fuel_depot_bonus: float:
	get: return fuel.fuel_depot_bonus
	set(v): fuel.fuel_depot_bonus = v

var fuel_depot_approach: String:
	get: return fuel.fuel_depot_approach
	set(v): fuel.fuel_depot_approach = v

var drop_tanks_attached: int:
	get: return fuel.drop_tanks_attached
	set(v): fuel.drop_tanks_attached = v

var drop_tank_fuel: float:
	get: return fuel.drop_tank_fuel
	set(v): fuel.drop_tank_fuel = v

var pilot_siphoning: bool:
	get: return fuel.pilot_siphoning
	set(v): fuel.pilot_siphoning = v

var pilot_siphoned_fuel: float:
	get: return fuel.pilot_siphoned_fuel
	set(v): fuel.pilot_siphoned_fuel = v

var engine_dirt: float:
	get: return fuel.engine_dirt
	set(v): fuel.engine_dirt = v

var wreckage_tile_pos: Vector2i:
	get: return fuel.wreckage_tile_pos
	set(v): fuel.wreckage_tile_pos = v

var wreckage_fuel_remaining: float:
	get: return fuel.wreckage_fuel_remaining
	set(v): fuel.wreckage_fuel_remaining = v

var siphoned_fuel: float:
	get: return fuel.siphoned_fuel
	set(v): fuel.siphoned_fuel = v

func get_tile_energy_cost(terrain: String) -> float:
	return fuel.get_tile_energy_cost(terrain)

# Fuel constants proxied to fuel manager
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

# --- Board proxies ---
var board_grid: Array:
	get: return board.board_grid
	set(v): board.board_grid = v

var current_tile: Vector2i:
	get: return board.current_tile
	set(v): board.current_tile = v

var board_seed: int:
	get: return board.board_seed
	set(v): board.board_seed = v

var player_last_dir: Vector2i:
	get: return board.player_last_dir
	set(v): board.player_last_dir = v

var board_mp_max: int:
	get: return board.board_mp_max
	set(v): board.board_mp_max = v

var board_mp: int:
	get: return board.board_mp
	set(v): board.board_mp = v

var board_day: int:
	get: return board.board_day
	set(v): board.board_day = v

var board_theme_id: String:
	get: return board.board_theme_id
	set(v): board.board_theme_id = v

var board_objective_id: String:
	get: return board.board_objective_id
	set(v): board.board_objective_id = v

var board_objective_progress: int:
	get: return board.board_objective_progress
	set(v): board.board_objective_progress = v

var board_objective_required: int:
	get: return board.board_objective_required
	set(v): board.board_objective_required = v

var board_objective_intro_consumed: bool:
	get: return board.board_objective_intro_consumed
	set(v): board.board_objective_intro_consumed = v

var board_patrols: Array:
	get: return board.board_patrols
	set(v): board.board_patrols = v

var board_patrol_engagement: int:
	get: return board.board_patrol_engagement
	set(v): board.board_patrol_engagement = v

var pending_tile_clear: Vector2i:
	get: return board.pending_tile_clear
	set(v): board.pending_tile_clear = v

var heat: int:
	get: return board.heat
	set(v): board.heat = v

var wanted_level: int:
	get: return board.wanted_level
	set(v): board.wanted_level = v

var wanted_escalation: int:
	get: return board.wanted_escalation
	set(v): board.wanted_escalation = v

var current_sector: int:
	get: return board.current_sector
	set(v): board.current_sector = v

var max_sectors: int:
	get: return board.max_sectors
	set(v): board.max_sectors = v

var current_hazard: String:
	get: return board.current_hazard
	set(v): board.current_hazard = v

var combat_tile_terrain: String:
	get: return board.combat_tile_terrain
	set(v): board.combat_tile_terrain = v

var current_arena_size: float:
	get: return board.current_arena_size
	set(v): board.current_arena_size = v

var patrol_last_seen: Vector2i:
	get: return board.patrol_last_seen
	set(v): board.patrol_last_seen = v

var patrol_alert: int:
	get: return board.patrol_alert
	set(v): board.patrol_alert = v

var ambush_pincer: bool:
	get: return board.ambush_pincer
	set(v): board.ambush_pincer = v

var consumed_bait: Array:
	get: return board.consumed_bait
	set(v): board.consumed_bait = v

var mid_battle_reinforcements_active: bool:
	get: return board.mid_battle_reinforcements_active
	set(v): board.mid_battle_reinforcements_active = v

var mid_battle_reinforcements_timer: float:
	get: return board.mid_battle_reinforcements_timer
	set(v): board.mid_battle_reinforcements_timer = v

var mid_battle_reinforcements_delay: float:
	get: return board.mid_battle_reinforcements_delay
	set(v): board.mid_battle_reinforcements_delay = v

var mid_battle_countdown_active: bool:
	get: return board.mid_battle_countdown_active
	set(v): board.mid_battle_countdown_active = v

var mid_battle_countdown_timer: float:
	get: return board.mid_battle_countdown_timer
	set(v): board.mid_battle_countdown_timer = v

var mid_battle_countdown_max: float:
	get: return board.mid_battle_countdown_max
	set(v): board.mid_battle_countdown_max = v

var convoy_hp: float:
	get: return board.convoy_hp
	set(v): board.convoy_hp = v

var convoy_hp_max: float:
	get: return board.convoy_hp_max
	set(v): board.convoy_hp_max = v

var convoy_defense_waves: int:
	get: return board.convoy_defense_waves
	set(v): board.convoy_defense_waves = v

var convoy_defense_current_wave: int:
	get: return board.convoy_defense_current_wave
	set(v): board.convoy_defense_current_wave = v

var convoy_defense_active: bool:
	get: return board.convoy_defense_active
	set(v): board.convoy_defense_active = v

var convoy_destroyed: bool:
	get: return board.convoy_destroyed
	set(v): board.convoy_destroyed = v

var run_notice: String:
	get: return board.run_notice
	set(v): board.run_notice = v

var safehouse_upgrades: Array:
	get: return board.safehouse_upgrades
	set(v): board.safehouse_upgrades = v

# Board constants
const HAZARD_DUST_STORM: String = "dust_storm"
const HAZARD_TACTICAL_SMOG: String = "tactical_smog"
const HAZARD_EMP_ZONE: String = "emp_zone"
const DUST_STORM_ROLLER_DRAIN_MULT: float = 1.5
const DUST_STORM_SPEED_MULT: float = 0.85
const SMOG_HEAT_COOL_PENALTY: float = 0.5
const EMP_LOCK_ON_DISABLED: bool = true
const EMP_BACKUP_BLOCKED: bool = true

# --- Narrative proxies ---
var theme_id: String:
	get: return narrative.theme_id
	set(v): narrative.theme_id = v

var reputation: int:
	get: return narrative.reputation
	set(v): narrative.reputation = v

var theme_switched: bool:
	get: return narrative.theme_switched
	set(v): narrative.theme_switched = v

var ceasefire_turns: int:
	get: return narrative.ceasefire_turns
	set(v): narrative.ceasefire_turns = v

var blocked_intermission: bool:
	get: return narrative.blocked_intermission
	set(v): narrative.blocked_intermission = v

var mech_less: bool:
	get: return narrative.mech_less
	set(v): narrative.mech_less = v

var mech_bond: float:
	get: return narrative.mech_bond
	set(v): narrative.mech_bond = v

var mech_battles_survived: int:
	get: return narrative.mech_battles_survived
	set(v): narrative.mech_battles_survived = v

var mech_repairs_done: int:
	get: return narrative.mech_repairs_done
	set(v): narrative.mech_repairs_done = v

var mech_near_death_escapes: int:
	get: return narrative.mech_near_death_escapes
	set(v): narrative.mech_near_death_escapes = v

var sacrifice_event_available: bool:
	get: return narrative.sacrifice_event_available
	set(v): narrative.sacrifice_event_available = v

var sacrifice_event_triggered: bool:
	get: return narrative.sacrifice_event_triggered
	set(v): narrative.sacrifice_event_triggered = v

var grand_entry_mech_id: String:
	get: return narrative.grand_entry_mech_id
	set(v): narrative.grand_entry_mech_id = v

var grand_entry_pending: bool:
	get: return narrative.grand_entry_pending
	set(v): narrative.grand_entry_pending = v

var enemy_tech_tier: int:
	get: return narrative.enemy_tech_tier
	set(v): narrative.enemy_tech_tier = v

var pending_escalation_event: bool:
	get: return narrative.pending_escalation_event
	set(v): narrative.pending_escalation_event = v

var enemy_research_progress: float:
	get: return narrative.enemy_research_progress
	set(v): narrative.enemy_research_progress = v

var enemy_base_active: bool:
	get: return narrative.enemy_base_active
	set(v): narrative.enemy_base_active = v

var enemy_base_progress: float:
	get: return narrative.enemy_base_progress
	set(v): narrative.enemy_base_progress = v

var enemy_base_required: float:
	get: return narrative.enemy_base_required
	set(v): narrative.enemy_base_required = v

var enemy_base_tile_pos: Vector2i:
	get: return narrative.enemy_base_tile_pos
	set(v): narrative.enemy_base_tile_pos = v

var enemy_grunt_upgrade_level: int:
	get: return narrative.enemy_grunt_upgrade_level
	set(v): narrative.enemy_grunt_upgrade_level = v

var enemy_copy_outcome: String:
	get: return narrative.enemy_copy_outcome
	set(v): narrative.enemy_copy_outcome = v

var enemy_special_units: Array:
	get: return narrative.enemy_special_units
	set(v): narrative.enemy_special_units = v

var pending_enemy_base_spawn: bool:
	get: return narrative.pending_enemy_base_spawn
	set(v): narrative.pending_enemy_base_spawn = v

var pending_enemy_base_outcome: bool:
	get: return narrative.pending_enemy_base_outcome
	set(v): narrative.pending_enemy_base_outcome = v

var pending_enemy_base_destroyed: bool:
	get: return narrative.pending_enemy_base_destroyed
	set(v): narrative.pending_enemy_base_destroyed = v

var pending_enemy_base_tile_reset: Vector2i:
	get: return narrative.pending_enemy_base_tile_reset
	set(v): narrative.pending_enemy_base_tile_reset = v

var enemy_forces: Dictionary:
	get: return narrative.enemy_forces
	set(v): narrative.enemy_forces = v

var last_combat_squad_size: int:
	get: return narrative.last_combat_squad_size
	set(v): narrative.last_combat_squad_size = v

var max_notoriety_multiplier: float:
	get: return narrative.max_notoriety_multiplier
	set(v): narrative.max_notoriety_multiplier = v

var stalking_aces: Array[String]:
	get: return narrative.stalking_aces
	set(v): narrative.stalking_aces = v

var stalking_chance: float:
	get: return narrative.stalking_chance
	set(v): narrative.stalking_chance = v

var fleet_security: float:
	get: return narrative.fleet_security
	set(v): narrative.fleet_security = v

var security_upgrade_level: int:
	get: return narrative.security_upgrade_level
	set(v): narrative.security_upgrade_level = v

var driver_repair_skill: int:
	get: return narrative.driver_repair_skill
	set(v): narrative.driver_repair_skill = v

var driver_repair_xp: int:
	get: return narrative.driver_repair_xp
	set(v): narrative.driver_repair_xp = v

# Narrative constants
const FLEET_SECURITY_MIN := 0.0
const FLEET_SECURITY_MAX := 100.0
const SECURITY_PER_UPGRADE := 14.0
const SECURITY_UPGRADE_BASE_COST := 35
const REPAIR_SKILL_MAX := 5
const REPAIR_XP_BASE := 30
const REPAIR_XP_PER_LEVEL := 25

func increase_bond(amount: float) -> void:
	narrative.increase_bond(amount)

func record_battle_survived() -> void:
	narrative.record_battle_survived(part_damage)

func record_repair() -> void:
	narrative.record_repair()

func record_near_death_escape() -> void:
	narrative.record_near_death_escape()

func _check_sacrifice_availability() -> void:
	narrative.check_sacrifice_availability(part_damage)

func trigger_sacrifice_event(new_mech_id: String) -> void:
	narrative.trigger_sacrifice_event(new_mech_id)

func has_pilot_perk(perk_id: String) -> bool:
	return narrative.has_pilot_perk(perk_id, pilot.hired_pilots, hangar.recruited_characters)

# --- Pilot proxies ---
var pilot_hp: float:
	get: return pilot.pilot_hp
	set(v): pilot.pilot_hp = v

var pilot_max_hp: float:
	get: return pilot.pilot_max_hp
	set(v): pilot.pilot_max_hp = v

var pilot_weapons: Array:
	get: return pilot.pilot_weapons
	set(v): pilot.pilot_weapons = v

var pilot_ammo: Dictionary:
	get: return pilot.pilot_ammo
	set(v): pilot.pilot_ammo = v

var pilot_items: Dictionary:
	get: return pilot.pilot_items
	set(v): pilot.pilot_items = v

var hired_pilots: Array:
	get: return pilot.hired_pilots
	set(v): pilot.hired_pilots = v

var fallen_pilots: Array:
	get: return pilot.fallen_pilots
	set(v): pilot.fallen_pilots = v

var rival_pilots: Array:
	get: return pilot.rival_pilots
	set(v): pilot.rival_pilots = v

var defeated_rivals: Array:
	get: return pilot.defeated_rivals
	set(v): pilot.defeated_rivals = v

var active_combat_commander: Dictionary:
	get: return pilot.active_combat_commander
	set(v): pilot.active_combat_commander = v

# --- Hangar proxies ---
var hangar_mechs: Array:
	get: return hangar.hangar_mechs
	set(v): hangar.hangar_mechs = v

var active_hangar_mech_id: String:
	get: return hangar.active_hangar_mech_id
	set(v): hangar.active_hangar_mech_id = v

var fleet_roster: Array:
	get: return hangar.fleet_roster
	set(v): hangar.fleet_roster = v

var recruited_characters: Array:
	get: return hangar.recruited_characters
	set(v): hangar.recruited_characters = v

var pending_duel: Dictionary:
	get: return hangar.pending_duel
	set(v): hangar.pending_duel = v

var duel_result_text: String:
	get: return hangar.duel_result_text
	set(v): hangar.duel_result_text = v

var research_projects: Dictionary:
	get: return hangar.research_projects
	set(v): hangar.research_projects = v

var research_unlocked: Array:
	get: return hangar.research_unlocked
	set(v): hangar.research_unlocked = v

# --- Weapon inventory proxies ---
var weapon_loadout: Dictionary:
	get: return weapons.weapon_loadout
	set(v): weapons.weapon_loadout = v

var weapon_inventory: Array:
	get: return weapons.weapon_inventory
	set(v): weapons.weapon_inventory = v

var ammo_inventory: Dictionary:
	get: return weapons.ammo_inventory
	set(v): weapons.ammo_inventory = v

var battle_loot: Array:
	get: return weapons.battle_loot
	set(v): weapons.battle_loot = v

var armor_inventory: Array:
	get: return weapons.armor_inventory
	set(v): weapons.armor_inventory = v

var chassis_id: String:
	get: return weapons.chassis_id
	set(v): weapons.chassis_id = v

var equipped_parts: Dictionary:
	get: return weapons.equipped_parts
	set(v): weapons.equipped_parts = v

var equipped_frames: Dictionary:
	get: return weapons.equipped_frames
	set(v): weapons.equipped_frames = v

var attachments: Array:
	get: return weapons.attachments
	set(v): weapons.attachments = v

var part_damage: Dictionary:
	get: return weapons.part_damage
	set(v): weapons.part_damage = v

var frame_upgrade_level: int:
	get: return weapons.frame_upgrade_level
	set(v): weapons.frame_upgrade_level = v

var scrap_patches: Dictionary:
	get: return weapons.scrap_patches
	set(v): weapons.scrap_patches = v

const FRAME_UPGRADE_HP_BONUS: float = 25.0
const FRAME_UPGRADE_WEIGHT_BONUS: float = 15.0
const FRAME_UPGRADE_BASE_COST: int = 150
const DEFAULT_LEFT_WEAPON_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const DEFAULT_RIGHT_WEAPON_PATH := "res://resources/mech/stock/weapon_heat_blade.tres"
const DEFAULT_CARRY_WEAPON_PATH := "res://resources/mech/stock/weapon_combat_shotgun.tres"


# ===========================================================================
# INIT
# ===========================================================================

func _ready() -> void:
	# Create manager instances as child nodes.
	currency = CurrencyManager.new()
	currency.name = "CurrencyManager"
	add_child(currency)

	fuel = FuelManager.new()
	fuel.name = "FuelManager"
	add_child(fuel)

	board = BoardState.new()
	board.name = "BoardState"
	add_child(board)

	narrative = NarrativeState.new()
	narrative.name = "NarrativeState"
	add_child(narrative)

	pilot = PilotState.new()
	pilot.name = "PilotState"
	add_child(pilot)

	hangar = HangarState.new()
	hangar.name = "HangarState"
	add_child(hangar)

	weapons = WeaponInventoryState.new()
	weapons.name = "WeaponInventoryState"
	add_child(weapons)

	_load_catalogs()
	weapons._ensure_default_frames()
	ArmorSystem.ensure_default_equipped_parts()
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


# ===========================================================================
# EVENT HANDLERS
# ===========================================================================

func _on_tile_entered(_tile_pos: Vector2i, _tile_data: Node) -> void:
	pass


func _on_board_day_ended() -> void:
	# Delegate day-end ticks to subsystems.
	fuel.day_end_tick()
	_notify_research_completions(FleetSystem.tick_research(1))
	RecruitSystem.tick_recovery()


func _on_combat_ended(victory: bool) -> void:
	# Clear environmental hazard after combat (one-shot per encounter).
	current_hazard = ""
	# Record bond.
	if victory:
		record_battle_survived()
	# Finalize combat damage stats.
	CombatStatsSystem.compute_last_combat_damage_ratio()
	# Patrol fleet engagement resolves first.
	if board_patrol_engagement >= 0:
		PatrolSystem.resolve_patrol_combat(victory)
		return
	# Duel resolves.
	if RecruitSystem.has_pending_duel():
		RecruitSystem.resolve_duel(victory)
		return
	# Enemy base raid.
	if GameManager.combat_node_type == "enemy_base":
		if victory:
			EnemyFactionSystem.destroy_enemy_base()
		return
	# Fuel depot seizure.
	if GameManager.combat_node_type == "fuel_depot":
		if victory:
			var bonus: float = FuelManager.FUEL_DEPOT_PRECISE_BONUS if fuel_depot_approach == "precise" else FuelManager.FUEL_DEPOT_HEAVY_BONUS
			var gained := minf(bonus, mech_max_energy - mech_energy)
			mech_energy = minf(mech_energy + gained, mech_max_energy)
			var approach_name := "Precise" if fuel_depot_approach == "precise" else "Heavy"
			run_notice = "Fuel depot seized (%s approach)! +%.0f energy." % [approach_name, gained]
		else:
			run_notice = "The fuel depot was lost in the fighting."
		fuel_depot_approach = ""
		return
	EnemyFactionSystem.on_combat_ended_for_tech(victory)
	if victory:
		ArmorSystem.sync_equipped_armor_durability()
		_notify_research_completions(FleetSystem.tick_research(2))


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


func get_durability_ratio(inst: Dictionary) -> float:
	return clampf(float(inst.get("durability", 1.0)), 0.0, 1.0)


func get_part_durability(slot: String) -> float:
	return 1.0 - clampf(float(part_damage.get(slot, 0.0)), 0.0, 1.0)


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
		var f = equipped_frames.get(arm, {})
		if f is Dictionary:
			power += float(f.get("carry_bonus", 0.0)) * 0.5
	return power


func get_arm_power(side: String) -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	if side != "left" and side != "right":
		return power
	var f = equipped_frames.get("arm_%s" % side, {})
	if f is Dictionary:
		power += float(f.get("carry_bonus", 0.0))
	return power


func get_leg_power() -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	for leg in ["leg_left", "leg_right"]:
		var f = equipped_frames.get(leg, {})
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

func save_run() -> void:
	SaveGameIO.save_run()

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

	# Non-delegated state.
	_combat_friendly_total_hp = 0.0
	_combat_friendly_damage = 0.0
	last_combat_damage_ratio = 0.0

	# Restore defaults after weapons.reset() (it calls ensure_default_equipped_parts).
	ArmorSystem.ensure_default_equipped_parts()
	weapons._ensure_default_frames()
	HangarManager.ensure_roster()


func clear_working_set() -> void:
	weapons.clear_working_set()
