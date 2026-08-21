class_name FuelManager
extends RefCounted

## ---------------------------------------------------------------------------
## FUEL MANAGER — global fuel pool + supply logistics (GDD §2.4).
##
## Extracted from GlobalData.  Owns:
##   • Mech energy pool (combat + board movement)
##   • Convoy fuel reserve (supply truck)
##   • External drop tanks (bolt-on fuel canisters)
##   • Pilot siphon / wreckage protocol
##   • Engine dirt (impure fuel penalty)
##   • Board energy costs
## ---------------------------------------------------------------------------

# --- Mech Energy Pool ---
var mech_energy: float = 1000.0
var mech_max_energy: float = 1000.0

# Board movement mode: true when the mech deploys roller-dash wheels on the map.
var board_roller_mode: bool = false

# Energy costs per terrain cell (GDD §3.1).
const BOARD_ENERGY_ROAD: float = 10.0
const BOARD_ENERGY_OFFROAD: float = 25.0
const BOARD_ENERGY_ROLLER: float = 5.0
const REFUEL_ACTION_ENERGY: float = 500.0

# Energy regen per day on the board (passive recharge while resting).
const BOARD_ENERGY_REGEN_PER_DAY: float = 50.0
# Bonus regen at safehouses.
const SAFEHOUSE_ENERGY_REGEN: float = 150.0

# --- Convoy Fuel Reserve ---
var convoy_fuel_reserve: float = 100.0
var convoy_fuel_max: float = 200.0
const CONVOY_DAILY_FUEL_REGEN: float = 30.0
const CONVOY_TRANSFER_AMOUNT: float = 60.0
const CONVOY_TRANSFER_ALERT_GAIN: int = 2

# --- Fuel Depot Seizure ---
var fuel_depot_seized_today: bool = false
var fuel_depot_bonus: float = 80.0
var fuel_depot_approach: String = ""
const FUEL_DEPOT_PRECISE_BONUS: float = 80.0
const FUEL_DEPOT_HEAVY_BONUS: float = 40.0

# --- External Drop Tanks ---
# 0 = no tanks, 1 = one side, 2 = both sides, 3 = dorsal + both sides.
var drop_tanks_attached: int = 0
var drop_tank_fuel: float = 0.0
const DROP_TANK_CAPACITY_PER: float = 40.0
const DROP_TANK_MAX_ATTACHED: int = 3
const DROP_TANK_PURGE_DAMAGE: float = 15.0
const DROP_TANK_COST_CREDITS: int = 80

# --- Pilot Siphon Protocol ---
var pilot_siphoning: bool = false
var pilot_siphoned_fuel: float = 0.0
const SIPHON_AMOUNT: float = 50.0
const SIPHON_WALK_TIME: float = 3.0

# --- Engine Dirt (impure fuel penalty) ---
var engine_dirt: float = 0.0
const ENGINE_DIRT_PER_SIPHON: float = 0.25
const ENGINE_DIRT_CLEANUP_PER_DAY: float = 0.1
const ENGINE_DIRT_HEAT_MULTIPLIER: float = 1.5

# --- Wreckage Siphon ---
var wreckage_tile_pos: Vector2i = Vector2i(-1, -1)
var wreckage_fuel_remaining: float = 80.0
var siphoned_fuel: float = 0.0
const WRECKAGE_SIPHON_AMOUNT: float = 30.0
const WRECKAGE_MAX_SIPHONS: int = 3
const REIGNITION_FUEL_COST: float = 60.0
const REIGNITION_ENGINE_DIRT_COST: float = 0.15


func get_tile_energy_cost(terrain: String) -> float:
	return preload("res://scripts/board/board_config.gd").energy_cost(terrain, board_roller_mode)


func reset() -> void:
	mech_energy = 1000.0
	mech_max_energy = 1000.0
	board_roller_mode = false
	convoy_fuel_reserve = 100.0
	convoy_fuel_max = 200.0
	fuel_depot_seized_today = false
	fuel_depot_approach = ""
	drop_tanks_attached = 0
	drop_tank_fuel = 0.0
	pilot_siphoning = false
	pilot_siphoned_fuel = 0.0
	engine_dirt = 0.0
	wreckage_tile_pos = Vector2i(-1, -1)
	wreckage_fuel_remaining = 80.0
	siphoned_fuel = 0.0


func day_end_tick() -> void:
	# Passive energy regen per day.
	mech_energy = minf(mech_energy + BOARD_ENERGY_REGEN_PER_DAY, mech_max_energy)
	# Convoy fuel reserve regen.
	convoy_fuel_reserve = minf(convoy_fuel_reserve + CONVOY_DAILY_FUEL_REGEN, convoy_fuel_max)
	# Natural engine dirt cleanup.
	engine_dirt = maxf(engine_dirt - ENGINE_DIRT_CLEANUP_PER_DAY, 0.0)
	# Reset one-shot seizure flag.
	fuel_depot_seized_today = false
