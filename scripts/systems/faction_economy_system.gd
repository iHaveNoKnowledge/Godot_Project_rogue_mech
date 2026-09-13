class_name FactionEconomySystem
extends RefCounted

## ---------------------------------------------------------------------------
## FACTION ECONOMY & LOGISTICS SYSTEM
##
## Manages living macro-economies for enemy factions:
## - Funds (Treasury) and Parts (Scrap/Components)
## - Barracks for Pilot Generation & Training
## - Hangar Mecha / Tank inventory
## - Checkpoint Outposts ("ตั้งด่าน") on roads/bridges
## - Supply States: "abundant", "normal", "starved", "depleted"
##   When starved, enemy waves become sparse ("ศัตรูน้อยผิดปกติ") and adopt
##   conservative stalling tactics ("สู้แบบกั๊กๆ").
## ---------------------------------------------------------------------------

const STATE_ABUNDANT := "abundant"
const STATE_NORMAL := "normal"
const STATE_STARVED := "starved"
const STATE_DEPLETED := "depleted"

# Default faction initial states
static var _faction_economies: Dictionary = {}

static func _ensure_initialized() -> void:
	if not _faction_economies.is_empty():
		return
	_faction_economies = {
		"federation": {
			"funds": 2500,
			"parts": 150,
			"barracks_capacity": 8,
			"active_pilots": [],
			"hangar_stock": 10,
			"supply_status": STATE_NORMAL,
			"checkpoints": [],
		},
		"zeon": {
			"funds": 2200,
			"parts": 180,
			"barracks_capacity": 6,
			"active_pilots": [],
			"hangar_stock": 8,
			"supply_status": STATE_NORMAL,
			"checkpoints": [],
		},
		"outland": {
			"funds": 1200,
			"parts": 90,
			"barracks_capacity": 4,
			"active_pilots": [],
			"hangar_stock": 5,
			"supply_status": STATE_STARVED,
			"checkpoints": [],
		},
		"scavenger": {
			"funds": 800,
			"parts": 200,
			"barracks_capacity": 5,
			"active_pilots": [],
			"hangar_stock": 6,
			"supply_status": STATE_NORMAL,
			"checkpoints": [],
		}
	}


static func get_economy(faction: String) -> Dictionary:
	_ensure_initialized()
	if not _faction_economies.has(faction):
		_faction_economies[faction] = {
			"funds": 1500,
			"parts": 100,
			"barracks_capacity": 5,
			"active_pilots": [],
			"hangar_stock": 6,
			"supply_status": STATE_NORMAL,
			"checkpoints": [],
		}
	return _faction_economies[faction]


## Generates a new pilot from the faction's barracks if funds & capacity allow.
static func pilot_generate(faction: String, difficulty: int = 1) -> Dictionary:
	_ensure_initialized()
	var eco := get_economy(faction)
	var pilot_cost := 120
	if int(eco.get("funds", 0)) < pilot_cost:
		eco["supply_status"] = STATE_STARVED
		return {}

	var pilots: Array = eco.get("active_pilots", [])
	if pilots.size() >= int(eco.get("barracks_capacity", 5)):
		return {}

	eco["funds"] = maxi(int(eco["funds"]) - pilot_cost, 0)
	var pilot := PilotGenerator.generate_pilot({"level": difficulty, "archetype": 0})
	pilot["faction"] = faction
	pilot["experience"] = randi_range(10, 50)
	pilots.append(pilot)
	eco["active_pilots"] = pilots

	_update_supply_status(faction)
	return pilot


## Assembles an operational combat unit by pairing an active pilot with hangar stock.
static func produce_unit(faction: String, archetype: String = "grunt") -> Dictionary:
	_ensure_initialized()
	var eco := get_economy(faction)
	var pilots: Array = eco.get("active_pilots", [])
	var stock: int = int(eco.get("hangar_stock", 0))

	# If out of pilots, attempt to recruit one
	if pilots.is_empty():
		var new_p := pilot_generate(faction)
		if new_p.is_empty():
			eco["supply_status"] = STATE_STARVED
			return {}

	if stock <= 0:
		# Need parts to construct new chassis
		var chassis_parts := 30
		if int(eco.get("parts", 0)) >= chassis_parts:
			eco["parts"] = int(eco["parts"]) - chassis_parts
			stock = 1
		else:
			eco["supply_status"] = STATE_STARVED
			return {}

	# Assign pilot and deduct chassis
	var pilot: Dictionary = pilots.pop_front()
	eco["active_pilots"] = pilots
	eco["hangar_stock"] = maxi(stock - 1, 0)

	_update_supply_status(faction)

	return {
		"pilot": pilot,
		"archetype": archetype,
		"faction": faction,
		"supply_status": eco["supply_status"],
	}


## Applies supply damage when player destroys convoys or captures fuel/ammo depots.
static func sever_supply_line(faction: String, fund_loss: int = 400, part_loss: int = 50) -> void:
	_ensure_initialized()
	var eco := get_economy(faction)
	eco["funds"] = maxi(int(eco.get("funds", 0)) - fund_loss, 0)
	eco["parts"] = maxi(int(eco.get("parts", 0)) - part_loss, 0)
	eco["supply_status"] = STATE_STARVED if int(eco["funds"]) > 0 else STATE_DEPLETED


## Daily economic replenishment & barracks graduation cycle.
static func advance_day_economy() -> void:
	_ensure_initialized()
	for fac in _faction_economies:
		var eco: Dictionary = _faction_economies[fac]
		# Daily production income
		var base_income := 250
		var base_parts := 25
		eco["funds"] = int(eco.get("funds", 0)) + base_income
		eco["parts"] = int(eco.get("parts", 0)) + base_parts
		eco["hangar_stock"] = clampi(int(eco.get("hangar_stock", 0)) + 1, 0, 15)

		# Train new recruits if under capacity
		var pilots: Array = eco.get("active_pilots", [])
		if pilots.size() < int(eco.get("barracks_capacity", 6)):
			pilot_generate(fac)

		_update_supply_status(fac)


static func _update_supply_status(faction: String) -> void:
	var eco := get_economy(faction)
	var funds: int = int(eco.get("funds", 0))
	var parts: int = int(eco.get("parts", 0))
	var stock: int = int(eco.get("hangar_stock", 0))

	if funds <= 50 or stock <= 0:
		eco["supply_status"] = STATE_DEPLETED
	elif funds < 500 or parts < 40 or stock <= 2:
		eco["supply_status"] = STATE_STARVED
	elif funds > 2000 and parts > 120 and stock >= 6:
		eco["supply_status"] = STATE_ABUNDANT
	else:
		eco["supply_status"] = STATE_NORMAL


## Checkpoint management ("ตั้งด่าน")
static func register_checkpoint(pos: Vector2i, faction: String, strength: int = 2) -> void:
	_ensure_initialized()
	var eco := get_economy(faction)
	var cps: Array = eco.get("checkpoints", [])
	for cp in cps:
		if cp.get("pos") == pos:
			return
	cps.append({
		"pos": pos,
		"faction": faction,
		"strength": strength,
		"toll_scrap": 15 * strength,
	})
	eco["checkpoints"] = cps


static func get_checkpoint_at(pos: Vector2i) -> Dictionary:
	_ensure_initialized()
	for fac in _faction_economies:
		var cps: Array = _faction_economies[fac].get("checkpoints", [])
		for cp in cps:
			if cp.get("pos") == pos:
				return cp
	return {}


static func remove_checkpoint_at(pos: Vector2i) -> void:
	_ensure_initialized()
	for fac in _faction_economies:
		var cps: Array = _faction_economies[fac].get("checkpoints", [])
		var filtered: Array = []
		for cp in cps:
			if cp.get("pos") != pos:
				filtered.append(cp)
		_faction_economies[fac]["checkpoints"] = filtered


## Returns whether a faction is currently in starved or depleted state.
static func is_faction_starved(faction: String) -> bool:
	_ensure_initialized()
	var st: String = str(get_economy(faction).get("supply_status", STATE_NORMAL))
	return st == STATE_STARVED or st == STATE_DEPLETED
