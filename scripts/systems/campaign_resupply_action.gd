class_name CampaignResupplyAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN RESUPPLY ACTION DOMAIN CONTRACT — Phase 5AO
##
## Domain authority for executing the player 'resupply' action.
##
## Domain Responsibilities:
##   - Receives action intent targeted at a strategic node.
##   - Enforces resupply domain preconditions (node capability, supply capacity).
##   - Mutates player energy and convoy fuel pools through authoritative FuelManager.
##   - Produces a deterministic resupply result contract.
##   - Enforces zero unintended side-effects on campaign authorities.
##
## Architectural Contract:
##   - What it inspects: Target node type from CampaignNodeRegistry and FuelManager levels.
##   - What it mutates: GlobalData.fuel.mech_energy and GlobalData.fuel.convoy_fuel.
##   - What it preserves: Zero mutation across territory, bases, forces, battles, turns, relations.
##   - Permitted nodes: START, SAFEHOUSE, CITY, FUEL_DEPOT, SUPPLY_DEPOT.
## ---------------------------------------------------------------------------

const RESUPPLY_NODE_TYPES := [
	"START",
	"SAFEHOUSE",
	"CITY",
	"FUEL_DEPOT",
	"SUPPLY_DEPOT",
]


## Checks whether a node type supports resupply operations.
static func is_resupply_node_type(node_type: String) -> bool:
	return RESUPPLY_NODE_TYPES.has(node_type.to_upper())


## Executes the domain resupply action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_resupply(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if action_id != "resupply":
		return {
			"ok": false,
			"reason": "invalid_action_for_handler",
			"action_id": action_id,
			"node_id": node_id,
		}

	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return {
			"ok": false,
			"reason": "unknown_node",
			"action_id": action_id,
			"node_id": node_id,
		}

	var node := CampaignNodeRegistry.get_node(node_id)
	var node_type := str(node.get("node_type", "")).to_upper()

	if not is_resupply_node_type(node_type):
		return {
			"ok": false,
			"reason": "node_cannot_resupply",
			"action_id": action_id,
			"node_id": node_id,
			"node_type": node_type,
		}

	if GlobalData == null or GlobalData.fuel == null:
		return {
			"ok": false,
			"reason": "fuel_authority_unavailable",
			"action_id": action_id,
			"node_id": node_id,
		}

	var fuel_mgr: FuelManager = GlobalData.fuel
	var mech_needed: float = maxf(fuel_mgr.mech_max_energy - fuel_mgr.mech_energy, 0.0)
	var convoy_needed: float = maxf(fuel_mgr.convoy_max_fuel - fuel_mgr.convoy_fuel, 0.0)

	if is_zero_approx(mech_needed) and is_zero_approx(convoy_needed):
		return {
			"ok": false,
			"reason": "already_fully_supplied",
			"action_id": action_id,
			"node_id": node_id,
			"mech_energy": fuel_mgr.mech_energy,
			"mech_max_energy": fuel_mgr.mech_max_energy,
			"convoy_fuel": fuel_mgr.convoy_fuel,
			"convoy_max_fuel": fuel_mgr.convoy_max_fuel,
		}

	var mech_energy_gained: float = fuel_mgr.refuel_mech_direct(fuel_mgr.mech_max_energy)
	var convoy_fuel_gained: float = fuel_mgr.refuel_convoy_direct(fuel_mgr.convoy_max_fuel)

	return {
		"ok": true,
		"reason": "resupply_completed",
		"action_id": "resupply",
		"node_id": node_id,
		"mech_energy_gained": mech_energy_gained,
		"convoy_fuel_gained": convoy_fuel_gained,
		"mech_energy": fuel_mgr.mech_energy,
		"mech_max_energy": fuel_mgr.mech_max_energy,
		"convoy_fuel": fuel_mgr.convoy_fuel,
		"convoy_max_fuel": fuel_mgr.convoy_max_fuel,
	}
