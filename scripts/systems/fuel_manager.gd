class_name FuelManager
extends RefCounted

## ---------------------------------------------------------------------------
## FUEL MANAGER — global fuel pool + supply logistics (GDD §2.4, §4.1).
##
## Extracted from GlobalData.  Owns:
##   • Mech energy pool (combat + board movement)
##   • Convoy fuel reserve (supply truck)
##   • External drop tanks (bolt-on fuel canisters)
##   • Pilot siphon / wreckage protocol
##   • Engine dirt (impure fuel penalty)
##   • Board energy costs
##   • Fuel Container Inventory (GDD §4.1) — container-based fuel storage
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


# --- Multi-Tier Traversal Mode ---
var traversal_mode: String = "convoy" # "convoy", "mecha", "pilot"
var convoy_pos: Vector2i = Vector2i.ZERO
var convoy_is_deployed: bool = false

# --- Convoy Truck Primary Fuel Tank ---
var convoy_fuel: float = 350.0
var convoy_max_fuel: float = 500.0

# --- Pilot Stamina Pool ---
var pilot_stamina: float = 50.0
var pilot_max_stamina: float = 50.0

# --- Parked Asset 3-Stage Seizure State ---
var seizure_stage: int = 0 # 0: Safe/Hidden, 1: Investigation, 2: Breaching, 3: Extraction
var seizure_turns_left: int = 0

# --- Carried Fuel Canisters (when walking/scouting) ---
var carried_fuel: float = 0.0
var max_carried_fuel: float = 100.0

# --- Fuel Container Inventory (GDD §4.1) ---
var _fci_script: Script = preload("res://scripts/systems/fuel_container_inventory.gd")
var mech_fuel_inventory  # FuelContainerInventory instance
var convoy_fuel_inventory  # FuelContainerInventory instance

# --- Power Core System (GDD §4.3) ---
var _pcs_script: Script = preload("res://scripts/systems/power_core_system.gd")


func _init() -> void:
	mech_fuel_inventory = _fci_script.new()
	convoy_fuel_inventory = _fci_script.new()


# ==========================================================================
# FUEL CONTAINER INVENTORY FACADES (GDD §4.1)
# ==========================================================================

## Adds fuel to the mech's container inventory using auto-stacking.
## Returns the amount actually absorbed.
func add_mech_fuel(fuel_type: int, amount: float) -> float:
	var absorbed = mech_fuel_inventory.add_fuel(fuel_type, amount)
	if absorbed > 0.0:
		mech_energy = minf(mech_energy + absorbed, mech_max_energy)
	return absorbed


## Adds fuel to the convoy's container inventory using auto-stacking.
## Returns the amount actually absorbed.
func add_convoy_fuel(fuel_type: int, amount: float) -> float:
	var absorbed = convoy_fuel_inventory.add_fuel(fuel_type, amount)
	if absorbed > 0.0:
		convoy_fuel = minf(convoy_fuel + absorbed, convoy_max_fuel)
	return absorbed


## Consumes fuel from mech containers. Returns actual amount consumed.
func consume_mech_fuel(amount: float) -> float:
	var consumed = mech_fuel_inventory.consume_fuel(amount)
	if consumed > 0.0:
		mech_energy = maxf(mech_energy - consumed, 0.0)
	return consumed


## Consumes fuel from convoy containers. Returns actual amount consumed.
func consume_convoy_fuel(amount: float) -> float:
	var consumed = convoy_fuel_inventory.consume_fuel(amount)
	if consumed > 0.0:
		convoy_fuel = maxf(convoy_fuel - consumed, 0.0)
	return consumed


## Convenience: add a pre-filled container directly to mech inventory.
func add_mech_container(fuel_type: int, size_pct: float, fill_pct: float = -1.0) -> bool:
	var added = mech_fuel_inventory.add_container(fuel_type, size_pct, fill_pct)
	if added and fill_pct >= 0.0:
		mech_energy = minf(mech_energy + fill_pct, mech_max_energy)
	return added


## Convenience: add a pre-filled container directly to convoy inventory.
func add_convoy_container(fuel_type: int, size_pct: float, fill_pct: float = -1.0) -> bool:
	var added = convoy_fuel_inventory.add_container(fuel_type, size_pct, fill_pct)
	if added and fill_pct >= 0.0:
		convoy_fuel = minf(convoy_fuel + fill_pct, convoy_max_fuel)
	return added


## Display summary for HUD.
func mech_fuel_display() -> String:
	return mech_fuel_inventory.inventory_display()


func convoy_fuel_display() -> String:
	return convoy_fuel_inventory.inventory_display()


func deploy_mecha() -> void:
	if traversal_mode == "convoy":
		convoy_pos = GlobalData.board.current_tile
		convoy_is_deployed = true
	traversal_mode = "mecha"


func deploy_pilot() -> void:
	if traversal_mode == "convoy":
		convoy_pos = GlobalData.board.current_tile
		convoy_is_deployed = true
	traversal_mode = "pilot"


func reembark_convoy() -> void:
	traversal_mode = "convoy"
	convoy_is_deployed = false
	if carried_fuel > 0.0:
		refuel_convoy_from_carried(carried_fuel)
	# Re-embarking clears active seizure if we returned and resolved it
	seizure_stage = 0
	seizure_turns_left = 0


func refuel_convoy_from_carried(amount: float) -> float:
	var needed := convoy_max_fuel - convoy_fuel
	var transfer := minf(amount, needed)
	convoy_fuel += transfer
	carried_fuel = maxf(carried_fuel - transfer, 0.0)
	return transfer


func get_camouflage_rate(terrain: String) -> float:
	match terrain:
		"forest":
			return 0.75
		"urban", "city":
			return 0.65
		"sand", "plain":
			return 0.40
		"road", "bridge":
			return 0.15
		_:
			return 0.35


func get_mode_step_cost(terrain: String) -> Dictionary:
	match traversal_mode:
		"mecha":
			var e_cost: float = 10.0 if (terrain == "road" or terrain == "bridge") else 20.0
			# GDD §4.3: Power Core class modifies board energy cost
			var core_mult = _pcs_script.board_cost_multiplier()
			e_cost *= core_mult
			var mp_cost: int = 1
			return {"mp": mp_cost, "fuel": 0.0, "energy": e_cost, "stamina": 0.0}
		"pilot":
			var s_cost: float = 10.0 if (terrain == "road" or terrain == "bridge" or terrain == "plain") else 15.0
			var mp_cost: int = 1 if (terrain == "road" or terrain == "plain") else 2
			return {"mp": mp_cost, "fuel": 0.0, "energy": 0.0, "stamina": s_cost}
		_: # "convoy"
			var f_cost: float = 5.0 if (terrain == "road" or terrain == "bridge") else (15.0 if terrain == "plain" else 30.0)
			var mp_cost: int = 1 if (terrain == "road" or terrain == "bridge" or terrain == "plain") else 2
			return {"mp": mp_cost, "fuel": f_cost, "energy": 0.0, "stamina": 0.0}


func get_tile_energy_cost(terrain: String) -> float:
	var costs := get_mode_step_cost(terrain)
	match traversal_mode:
		"mecha":
			return float(costs["energy"])
		"pilot":
			return float(costs["stamina"])
		_:
			return float(costs["fuel"])


func reset() -> void:
	traversal_mode = "convoy"
	convoy_pos = Vector2i.ZERO
	convoy_is_deployed = false
	convoy_fuel = 350.0
	convoy_max_fuel = 500.0
	mech_energy = 1000.0
	mech_max_energy = 1000.0
	pilot_stamina = 50.0
	pilot_max_stamina = 50.0
	carried_fuel = 0.0
	seizure_stage = 0
	seizure_turns_left = 0
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
	# Reset container inventories with starting loadout (GDD §4.1)
	mech_fuel_inventory.reset([
		_fci_script.create_filled_container(0, 20.0),  # FuelType.CRUDE_OIL
		_fci_script.create_filled_container(0, 10.0),  # FuelType.CRUDE_OIL
	])
	convoy_fuel_inventory.reset([
		_fci_script.create_filled_container(0, 100.0),  # FuelType.CRUDE_OIL
		_fci_script.create_filled_container(0, 20.0),   # FuelType.CRUDE_OIL
	])


func day_end_tick() -> void:
	# Passive energy and stamina regen per day.
	mech_energy = minf(mech_energy + BOARD_ENERGY_REGEN_PER_DAY, mech_max_energy)
	pilot_stamina = minf(pilot_stamina + 25.0, pilot_max_stamina)
	convoy_fuel_reserve = minf(convoy_fuel_reserve + CONVOY_DAILY_FUEL_REGEN, convoy_fuel_max)
	engine_dirt = maxf(engine_dirt - ENGINE_DIRT_CLEANUP_PER_DAY, 0.0)
	fuel_depot_seized_today = false
