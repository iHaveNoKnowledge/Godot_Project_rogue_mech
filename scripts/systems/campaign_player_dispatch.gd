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
##   5. Post-Success Exposure (C4-B6):
##      - After a domain handler reports success, exactly one exposure hook
##        records the committed action in the strategic Heat / Detection
##        authorities (values per the C4 design exposure matrix; heat is
##        node-local and unattributed, detection names only the faction
##        legitimately informed). Failed, rejected, and unimplemented
##        actions record nothing. The handler receipt itself is returned
##        unmodified.
## ---------------------------------------------------------------------------

const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")
const CampaignCaptureAction = preload("res://scripts/systems/campaign_capture_action.gd")
const CampaignAttackAction = preload("res://scripts/systems/campaign_attack_action.gd")
const CampaignDefendAction = preload("res://scripts/systems/campaign_defend_action.gd")
const CampaignRecoverAction = preload("res://scripts/systems/campaign_recover_action.gd")

const CORE_KNOWN_ACTIONS := [
	"investigate",
	"attack",
	"resupply",
	"trade",
	"defend",
	"capture",
]

static var _handlers: Dictionary = {}


static func _static_init() -> void:
	register_default_handlers()


## Registers standard domain handlers for all fully implemented actions.
static func register_default_handlers() -> void:
	register_handler("investigate", Callable(CampaignInvestigateAction, "handle_investigate"))
	register_handler("resupply", Callable(CampaignResupplyAction, "handle_resupply"))
	register_handler("trade", Callable(CampaignTradeAction, "handle_trade"))
	register_handler("capture", Callable(CampaignCaptureAction, "handle_capture"))
	register_handler("attack", Callable(CampaignAttackAction, "handle_attack"))
	register_handler("defend", Callable(CampaignDefendAction, "handle_defend"))
	register_handler("recover", Callable(CampaignRecoverAction, "handle_recover"))




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
## On domain success, records exactly one strategic exposure hook (C4-B6)
## and returns the handler receipt unmodified.
static func dispatch_intent(intent: Dictionary) -> Dictionary:
	var validation := validate_intent(intent)
	if not bool(validation.get("ok", false)):
		return validation

	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if _handlers.has(action_id):
		var handler: Callable = _handlers[action_id]
		if handler.is_valid():
			var result: Dictionary = handler.call(intent)
			if bool(result.get("ok", false)):
				_apply_action_exposure(result)
			return result

	return {
		"ok": false,
		"reason": "action_not_implemented",
		"action_id": action_id,
		"node_id": node_id,
	}


## Records the strategic exposure of one successfully committed action
## (C4-B6). Values follow the C4 design exposure matrix (provisional
## balance values, documented here — not balanced game design):
##   attack    -> heat +3 at node; defending faction LOCATED ("direct_attack").
##   capture   -> heat +2 at node; dislodged controller SUSPECTED ("capture_takeover").
##   resupply  -> heat +1 unless covering territory allied to the player;
##                covering controller evaluated for trace suspicion.
##   trade     -> same as resupply.
##   investigate / unlisted -> nothing (covert recon has no exposure).
## Heat is node-local and faction-free; detection names only the faction
## legitimately informed (never every faction, never from heat alone).
## Timestamps use the live campaign turn (read-only clock, never advanced).
static func _apply_action_exposure(result: Dictionary) -> void:
	var action_id := str(result.get("action_id", "")).strip_edges()
	var node_id := str(result.get("node_id", "")).strip_edges()
	if action_id == "" or node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return
	var turn := CampaignTurnExecutive.get_turn()
	match action_id:
		"attack":
			CampaignStrategicHeat.add_node_heat(node_id, 3)
			var target_faction := str(result.get("target_faction", "")).strip_edges()
			if target_faction != "":
				CampaignStrategicDetection.report_location(
					target_faction, node_id, turn, "direct_attack")
		"capture":
			var heat_receipt := CampaignStrategicHeat.add_node_heat(node_id, 2)
			var previous := str(result.get("previous_controller", "")).strip_edges()
			var claim := str(result.get("new_controller", "")).strip_edges()
			if previous != "" and previous != claim:
				CampaignStrategicDetection.report_suspicion(
					previous, node_id, turn,
					int(heat_receipt.get("new_heat", 0)), "capture_takeover")
		"resupply", "trade":
			_apply_territorial_trace(node_id, turn)
		_:
			pass


## Shared resupply/trade exposure: +1 heat unless the node sits in
## territory allied to the player faction; a covering controller (if any)
## is then evaluated for trace suspicion (threshold-gated inside
## evaluate_node_trace, which can only yield SUSPECTED, never LOCATED).
## Allied/Hostile tests scan every covering territory so overlapping zones
## cannot hide a trace (same ANY rule as the movement hook).
static func _apply_territorial_trace(node_id: String, turn: int) -> void:
	var player_faction := FactionSystem.get_player_faction()
	var controller := ""
	var allied_cover := false
	for territory in CampaignTerritory.get_territories_for_node(node_id):
		var candidate := str(territory.get("controller", ""))
		if candidate == "":
			continue
		if controller == "":
			controller = candidate
		if FactionSystem.get_relation(player_faction, candidate) == FactionSystem.Relation.ALLIED:
			allied_cover = true
	if not allied_cover:
		var heat_receipt := CampaignStrategicHeat.add_node_heat(node_id, 1)
		if controller != "":
			CampaignStrategicDetection.evaluate_node_trace(
				controller, node_id, int(heat_receipt.get("new_heat", 0)), turn)


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
