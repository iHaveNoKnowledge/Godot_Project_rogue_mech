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
# --- Catalog databases (loaded once at startup) ---
var armor_catalog: Dictionary = {}
var chassis_catalog: Dictionary = {}
var frame_catalog: Dictionary = {}
var attachment_catalog: Array = []
var research_blueprints: Array = []
var ally_unit_templates: Dictionary = {}
var run_themes: Array = []
var run_events: Array = []

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
	board.current_hazard = ""
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
	# Patrol fleet engagement resolves first.
	if board.board_patrol_engagement >= 0:
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
			var bonus: float = FuelManager.FUEL_DEPOT_PRECISE_BONUS if fuel.fuel_depot_approach == "precise" else FuelManager.FUEL_DEPOT_HEAVY_BONUS
			var gained := fuel.add_mech_fuel(0, bonus)  # FuelType.CRUDE_OIL = 0
			var approach_name := "Precise" if fuel.fuel_depot_approach == "precise" else "Heavy"
			board.run_notice = "Fuel depot seized (%s approach)! +%.0f energy." % [approach_name, gained]
		else:
			board.run_notice = "The fuel depot was lost in the fighting."
		fuel.fuel_depot_approach = ""
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


## Returns the lifetime/health durability of an equipped armor part (0.0 to 1.0)
func get_part_durability(slot: String) -> float:
	var p = weapons.equipped_parts.get(slot)
	if p is Dictionary:
		return get_durability_ratio(p)
	return 1.0


## Returns the lifetime/health durability of an equipped frame (0.0 to 1.0)
func get_frame_durability(slot: String) -> float:
	var base_slot := str(slot).replace("_frame", "")
	var f = weapons.equipped_frames.get(base_slot)
	if f is Dictionary:
		return get_durability_ratio(f)
	return 1.0


## Degrades the lifetime durability of an equipped armor part (e.g. from repairs or armor shatter)
func degrade_part_durability(slot: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var p = weapons.equipped_parts.get(slot)
	if p is Dictionary:
		var cur := get_durability_ratio(p)
		p["durability"] = clampf(cur - amount, 0.10, 1.0)


## Degrades the lifetime durability of an equipped frame
func degrade_frame_durability(slot: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var base_slot := str(slot).replace("_frame", "")
	var f = weapons.equipped_frames.get(base_slot)
	if f is Dictionary:
		var cur := get_durability_ratio(f)
		f["durability"] = clampf(cur - amount, 0.10, 1.0)


## Degrades the lifetime durability of an equipped weapon
func degrade_weapon_durability(hand: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var uid := str(weapons.equipped_weapon_instances.get(hand, ""))
	if uid == "":
		return
	for w in weapons.inventory:
		if w is Dictionary and str(w.get("uid", "")) == uid:
			var cur := get_durability_ratio(w)
			w["durability"] = clampf(cur - amount, 0.05, 1.0)
			break


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
