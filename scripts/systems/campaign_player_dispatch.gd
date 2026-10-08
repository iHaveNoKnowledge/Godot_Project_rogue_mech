class_name CampaignPlayerDispatch
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN PLAYER ACTION INTENT & DISPATCH BOUNDARY — Phase 5AM
##
## Thin routing layer that validates and dispatches strategic player action
## intents from the UI / decision layer to future domain executors.
##
## Architectural Contract:
##   1. Pure Routing Boundary:
##      - The dispatcher is NOT a domain owner.
##      - Does not execute combat, capture territory, advance turns,
##        transfer supply, or mutate forces/bases.
##   2. Strict Intent Validation:
##      - Validates action recognition, node validity, and player presence.
##      - Reject unknown actions ("unknown_action").
##      - Reject unknown nodes ("unknown_node").
##      - Reject actions targeting nodes where the player is not physically
##        present ("player_not_at_node").
##   3. Unimplemented Safety:
##      - Recognized actions without domain executors return a deterministic
##        rejection ("action_not_implemented") with ZERO state side effects.
##   4. Pure Separation:
##      - CampaignNodeInspection observes.
##      - CampaignPlayerMovement moves.
##      - CampaignPlayerDispatch routes intents.
##      - Domain systems execute.
## ---------------------------------------------------------------------------

const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")

const CORE_KNOWN_ACTIONS := [
	"investigate",
	"attack",
	"resupply",
	"trade",
	"defend",
	"capture",
]

static var _handlers: Dictionary = {}


## Constructs a canonical action intent dictionary.
static func create_intent(action_id: String, node_id: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"action_id": action_id.strip_edges(),
		"node_id": node_id.strip_edges(),
		"payload": payload.duplicate(true),
	}


## Validates an action intent without dispatching it to an executor.
## Returns { "ok": true, "reason": "valid" } or failure dictionary.
static func validate_intent(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if action_id == "" or not is_known_action(action_id):
		return {
			"ok": false,
			"reason": "unknown_action",
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

	if not CampaignNodeInspection.is_player_at_node(node_id):
		return {
			"ok": false,
			"reason": "player_not_at_node",
			"action_id": action_id,
			"node_id": node_id,
		}

	return {
		"ok": true,
		"reason": "valid",
		"action_id": action_id,
		"node_id": node_id,
	}


## Dispatches a player action intent. Validates intent first, then routes to
## registered domain handler or returns "action_not_implemented".
static func dispatch_intent(intent: Dictionary) -> Dictionary:
	var validation := validate_intent(intent)
	if not bool(validation.get("ok", false)):
		return validation

	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if _handlers.has(action_id):
		var handler: Callable = _handlers[action_id]
		if handler.is_valid():
			return handler.call(intent)

	return {
		"ok": false,
		"reason": "action_not_implemented",
		"action_id": action_id,
		"node_id": node_id,
	}


## Returns whether an action ID is recognized (either core known or registered).
static func is_known_action(action_id: String) -> bool:
	if action_id == "":
		return false
	if CORE_KNOWN_ACTIONS.has(action_id):
		return true
	return _handlers.has(action_id)


## Returns a sorted list of all currently known action IDs.
static func get_known_actions() -> Array:
	var actions_set: Dictionary = {}
	for a in CORE_KNOWN_ACTIONS:
		actions_set[a] = true
	for a in _handlers.keys():
		actions_set[str(a)] = true
	var list := actions_set.keys()
	list.sort()
	return list


## Registers a domain executor callable for an action ID.
static func register_handler(action_id: String, handler: Callable) -> void:
	if action_id != "" and handler.is_valid():
		_handlers[action_id.strip_edges()] = handler


## Unregisters a domain executor callable.
static func unregister_handler(action_id: String) -> void:
	_handlers.erase(action_id.strip_edges())


## Clears all dynamically registered handlers.
static func clear_handlers() -> void:
	_handlers.clear()
