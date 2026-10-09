class_name CampaignStrategicHeat
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC HEAT AUTHORITY — Phase C4-B1 (Campaign V2).
##
## Authoritative store for strategic node-local operational traces.
##
## Architectural Contract:
##   - Node-Local Trace Store:
##     Tracks physical/operational disturbance and signatures left at
##     strategic nodes (communication spikes, wreckage, supply movements).
##   - Scope & Boundary:
##     Pure strategic layer authority. Does NOT alias, mutate, or read
##     tactical HeatWantedSystem.heat or GlobalData.board.board_patrols.
##   - Value Bounds:
##     Heat level integer clamped in [MIN_HEAT, MAX_HEAT] (0..10).
##   - Decay Semantics:
##     Decays by positive amounts down to MIN_HEAT (0).
##   - Stateless Helpers / Static Storage:
##     Static registry pattern matching CampaignNodeRegistry, CampaignBase,
##     CampaignTerritory, and CampaignForce.
## ---------------------------------------------------------------------------

const MIN_HEAT: int = 0
const MAX_HEAT: int = 10
const DEFAULT_DECAY: int = 1

static var _node_heats: Dictionary = {}


## Returns the heat level of a strategic node (0 if untracked or unknown).
static func get_node_heat(node_id: String) -> int:
	var nid := node_id.strip_edges()
	if nid == "":
		return MIN_HEAT
	return int(_node_heats.get(nid, MIN_HEAT))


## Returns true if the node currently has positive strategic heat (> 0).
static func has_heat(node_id: String) -> bool:
	return get_node_heat(node_id) > MIN_HEAT


## Sets the heat level of a node directly, clamped to [MIN_HEAT, MAX_HEAT].
## Setting to 0 cleans up the tracking entry.
static func set_node_heat(node_id: String, heat: int) -> bool:
	var nid := node_id.strip_edges()
	if nid == "":
		return false
	var clamped_val := clampi(heat, MIN_HEAT, MAX_HEAT)
	if clamped_val == MIN_HEAT:
		_node_heats.erase(nid)
	else:
		_node_heats[nid] = clamped_val
	return true


## Adds a positive heat amount to a node, clamping at MAX_HEAT.
## Returns a detailed result receipt.
static func add_node_heat(node_id: String, amount: int) -> Dictionary:
	var nid := node_id.strip_edges()
	if nid == "":
		return {
			"ok": false,
			"reason": "empty_node_id",
			"node_id": "",
			"old_heat": MIN_HEAT,
			"new_heat": MIN_HEAT,
			"added": 0,
		}
	if amount <= 0:
		var current_heat := get_node_heat(nid)
		return {
			"ok": false,
			"reason": "non_positive_amount",
			"node_id": nid,
			"old_heat": current_heat,
			"new_heat": current_heat,
			"added": 0,
		}

	var old_heat := get_node_heat(nid)
	var new_heat := clampi(old_heat + amount, MIN_HEAT, MAX_HEAT)
	_node_heats[nid] = new_heat
	return {
		"ok": true,
		"reason": "heat_added",
		"node_id": nid,
		"old_heat": old_heat,
		"new_heat": new_heat,
		"added": new_heat - old_heat,
	}


## Decays the heat level of a single node by amount down to MIN_HEAT.
static func decay_node_heat(node_id: String, amount: int = DEFAULT_DECAY) -> Dictionary:
	var nid := node_id.strip_edges()
	if nid == "":
		return {
			"ok": false,
			"reason": "empty_node_id",
			"node_id": "",
			"old_heat": MIN_HEAT,
			"new_heat": MIN_HEAT,
			"decayed": 0,
		}
	if amount <= 0:
		var current_heat := get_node_heat(nid)
		return {
			"ok": false,
			"reason": "non_positive_amount",
			"node_id": nid,
			"old_heat": current_heat,
			"new_heat": current_heat,
			"decayed": 0,
		}

	var old_heat := get_node_heat(nid)
	var new_heat := clampi(old_heat - amount, MIN_HEAT, MAX_HEAT)
	if new_heat == MIN_HEAT:
		_node_heats.erase(nid)
	else:
		_node_heats[nid] = new_heat

	return {
		"ok": true,
		"reason": "heat_decayed",
		"node_id": nid,
		"old_heat": old_heat,
		"new_heat": new_heat,
		"decayed": old_heat - new_heat,
	}


## Decays all tracked nodes by amount down to MIN_HEAT.
static func decay_all_nodes(amount: int = DEFAULT_DECAY) -> Dictionary:
	if amount <= 0:
		return {
			"ok": false,
			"reason": "non_positive_amount",
			"decayed_nodes": 0,
			"details": {},
		}

	var details: Dictionary = {}
	var node_ids := _node_heats.keys()
	for nid in node_ids:
		var receipt := decay_node_heat(str(nid), amount)
		details[str(nid)] = receipt

	return {
		"ok": true,
		"reason": "all_decayed",
		"decayed_nodes": details.size(),
		"details": details,
	}


## Returns a duplicate of all currently tracked positive node heats.
static func get_all_heats() -> Dictionary:
	return _node_heats.duplicate(true)


## Clears all stored strategic heat states back to initial clean state.
static func reset() -> void:
	_node_heats.clear()


## Serializes active node heats to a clean dictionary format.
static func serialize() -> Dictionary:
	return {
		"node_heats": _node_heats.duplicate(true),
	}


## Deserializes node heats from dictionary with bounds validation.
static func deserialize(data: Variant) -> void:
	reset()
	if not (data is Dictionary):
		return
	var heats = data.get("node_heats", {})
	if not (heats is Dictionary):
		return
	for key in heats.keys():
		var nid := str(key).strip_edges()
		if nid == "":
			continue
		var raw_val = heats[key]
		if raw_val is int or raw_val is float:
			var val := clampi(int(raw_val), MIN_HEAT, MAX_HEAT)
			if val > MIN_HEAT:
				_node_heats[nid] = val
