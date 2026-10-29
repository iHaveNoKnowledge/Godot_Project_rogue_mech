class_name CampaignSupply
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN SUPPLY / RESOURCE LEDGER — Phase C6-A (Campaign V2).
##
## Authoritative store for the campaign-level resource pool defined by the
## master spec §10/§11/§41: SUPPLY, MATERIALS, SALVAGE.
##
## DATA is NOT duplicated here: `GlobalData.currency.data_cores`
## (CurrencyManager) is the existing authoritative research currency and is
## already consumed by FleetSystem blueprint research (fleet_system.gd:218+).
## Spec §41's DATA role is therefore satisfied by the existing purse; this
## ledger adds only the resources that had NO owner.
##
## Audit evidence (do not re-decide lightly):
##   - No campaign resource pool existed. `GlobalData.currency`
##     (CurrencyManager = credits/scrap) is a tactical/hangar purse, and
##     `FactionEconomySystem.supply_status` is FACTION-only state consumed by
##     patrol spawning. `CampaignForce` explicitly owns NO supply
##     (test/unit/campaign_force_supply_boundary_verify.gd locks that absence).
##     This author is therefore a NEW responsibility, not a duplicate.
##   - One pool, three keys — spec §41 forbids extra resource types for a
##     single system, and DATA already has an owner (see above). No
##     per-faction, per-node, or per-base sub-ledger here.
##   - SUPPLY is the only capped resource (§11 "42 / 100"): it is the war
##     effort budget. MATERIALS/DATA/SALVAGE are uncapped accumulators.
##     Values are PROVISIONAL balance numbers, not a locked formula.
##   - Supply 0 is NOT game over (§11): it reports a crisis flag only. No
##     authority is disabled here; consumers decide what the crisis blocks.
##
## Boundaries:
##   - Never reads/writes CurrencyManager (including data_cores),
##     FuelManager, FactionEconomySystem, CampaignForce, CampaignBase, or
##     research state.
##   - Never advances turns. Income is applied by CampaignTurnExecutive's
##     day-boundary phase (PHASE_CAMPAIGN_SUPPLY) through this API.
##   - Static registry pattern matching CampaignStrategicHeat / CampaignBase /
##     CampaignForce, including reset() and serialize()/deserialize().
## ---------------------------------------------------------------------------

const KEY_SUPPLY := "SUPPLY"
const KEY_MATERIALS := "MATERIALS"
const KEY_SALVAGE := "SALVAGE"

const RESOURCE_KEYS: Array[String] = [KEY_SUPPLY, KEY_MATERIALS, KEY_SALVAGE]

## Provisional starting values (§11 example: 42 / 100, +4 per turn).
const START_SUPPLY: int = 42
const SUPPLY_CAP: int = 100
const SUPPLY_INCOME_PER_TURN: int = 4
const START_MATERIALS: int = 0
const START_SALVAGE: int = 0

static var _amounts: Dictionary = {}


static func _default_amounts() -> Dictionary:
	return {
		KEY_SUPPLY: START_SUPPLY,
		KEY_MATERIALS: START_MATERIALS,
		KEY_SALVAGE: START_SALVAGE,
	}


static func is_valid_key(key: String) -> bool:
	return RESOURCE_KEYS.has(key)


## Capacity of a resource: SUPPLY is capped, the others are uncapped (0).
static func get_cap(key: String) -> int:
	return SUPPLY_CAP if key == KEY_SUPPLY else 0


## Current amount of one resource (0 for unknown keys).
static func get_amount(key: String) -> int:
	var k := key.strip_edges().to_upper()
	if not is_valid_key(k):
		return 0
	if _amounts.is_empty():
		_amounts = _default_amounts()
	return int(_amounts.get(k, 0))


## Snapshot of every resource amount.
static func get_amounts() -> Dictionary:
	if _amounts.is_empty():
		_amounts = _default_amounts()
	var out: Dictionary = {}
	for key in RESOURCE_KEYS:
		out[key] = int(_amounts.get(key, 0))
	return out


## True when the supply pool is exhausted (§11 Supply Crisis, not game over).
static func is_supply_crisis() -> bool:
	return get_amount(KEY_SUPPLY) <= 0


## SUPPLY fill ratio in [0.0, 1.0] for HUD gauges.
static func get_supply_ratio() -> float:
	return clampf(float(get_amount(KEY_SUPPLY)) / float(SUPPLY_CAP), 0.0, 1.0)


## Sets one resource directly, clamped to [0, cap] (cap 0 = uncapped).
static func set_amount(key: String, value: int) -> bool:
	var k := key.strip_edges().to_upper()
	if not is_valid_key(k):
		return false
	if _amounts.is_empty():
		_amounts = _default_amounts()
	var cap := get_cap(k)
	var clamped := maxi(value, 0)
	if cap > 0:
		clamped = mini(clamped, cap)
	_amounts[k] = clamped
	return true


## Adds a positive amount to one resource, clamped at its cap.
static func add(key: String, amount: int) -> Dictionary:
	var k := key.strip_edges().to_upper()
	if not is_valid_key(k):
		return {"ok": false, "reason": "unknown_resource", "key": k, "added": 0}
	if amount <= 0:
		return {"ok": false, "reason": "non_positive_amount", "key": k, "added": 0}
	var old_amount := get_amount(k)
	set_amount(k, old_amount + amount)
	var new_amount := get_amount(k)
	return {
		"ok": true,
		"reason": "resource_added",
		"key": k,
		"old_amount": old_amount,
		"new_amount": new_amount,
		"added": new_amount - old_amount,
	}


## True when the pool can pay the amount in one resource.
static func can_afford(key: String, amount: int) -> bool:
	if amount <= 0:
		return false
	return get_amount(key) >= amount


## Atomic spend: validates first, mutates only on success.
static func try_spend(key: String, amount: int) -> Dictionary:
	var k := key.strip_edges().to_upper()
	if not is_valid_key(k):
		return {"ok": false, "reason": "unknown_resource", "key": k}
	if amount <= 0:
		return {"ok": false, "reason": "non_positive_amount", "key": k}
	if not can_afford(k, amount):
		return {
			"ok": false,
			"reason": "insufficient_" + k.to_lower(),
			"key": k,
			"amount": amount,
			"available": get_amount(k),
		}
	var old_amount := get_amount(k)
	set_amount(k, old_amount - amount)
	return {
		"ok": true,
		"reason": "resource_spent",
		"key": k,
		"amount": amount,
		"old_amount": old_amount,
		"new_amount": get_amount(k),
	}


## Day-boundary income tick. Called by CampaignTurnExecutive only.
static func process_turn_income(income: int = SUPPLY_INCOME_PER_TURN) -> Dictionary:
	if income <= 0:
		return {"ok": false, "reason": "non_positive_income", "income": income}
	var before := get_amount(KEY_SUPPLY)
	var receipt := add(KEY_SUPPLY, income)
	receipt["supply_before"] = before
	receipt["supply_after"] = get_amount(KEY_SUPPLY)
	receipt["crisis"] = is_supply_crisis()
	return receipt


## Clears the ledger back to starting values (new runs, test isolation).
static func reset() -> void:
	_amounts = _default_amounts()


## Serializes every resource amount (schema stays version 1).
static func serialize() -> Dictionary:
	return {"amounts": get_amounts()}


## Deserializes with per-resource sanitization. Legacy/malformed payloads fall
## back to starting values rather than failing the load.
static func deserialize(data: Variant) -> void:
	reset()
	if not (data is Dictionary):
		return
	var raw = (data as Dictionary).get("amounts", {})
	if not (raw is Dictionary):
		return
	for key in RESOURCE_KEYS:
		var value = (raw as Dictionary).get(key)
		if value is int or value is float:
			set_amount(key, int(value))
