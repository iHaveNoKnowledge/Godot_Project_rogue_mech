class_name CampaignCaptureAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN CAPTURE ACTION DOMAIN CONTRACT — Phase 5AT
##
## Domain authority for executing the player 'capture' action.
##
## Domain Responsibilities:
##   - Receives action intent targeted at a strategic capturable node.
##   - Enforces capture domain preconditions (capturable node/base, opposing controller).
##   - Atomically updates authoritative base controller and covering territory controller.
##   - Produces a deterministic capture completion receipt.
##   - Enforces zero unintended side-effects on turns, battles, currency, fuel, forces, or position.
##
## Architectural Contract:
##   - What it inspects: Target node type from CampaignNodeRegistry, base at node from CampaignBase,
##     and covering territories from CampaignTerritory.
##   - What it mutates: CampaignBase controller via CampaignBase.set_controller() and
##     CampaignTerritory controller via CampaignTerritory.set_controlled().
##   - What it preserves: Zero turn advancement (CampaignTurnExecutive untouched),
##     zero movement, zero currency/fuel/force mutations.
##   - Default claiming faction: "federation" (player faction) or payload["claim_faction"].
## ---------------------------------------------------------------------------

const DEFAULT_CLAIM_FACTION: String = "federation"

const CAPTURABLE_NODE_TYPES := [
	"ENEMY_BASE",
]


## Checks whether a node type or hosted installation supports capture operations.
static func is_capturable_node(node_id: String) -> bool:
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return false
	var node := CampaignNodeRegistry.get_node(node_id)
	var node_type := str(node.get("node_type", "")).to_upper()
	if CAPTURABLE_NODE_TYPES.has(node_type):
		return true
	var base := CampaignBase.get_base_at_node(node_id)
	return not base.is_empty() and int(base.get("state", -1)) != CampaignBase.BaseState.DESTROYED


## Executes the domain capture action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_capture(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()
	var payload: Dictionary = intent.get("payload", {})

	if action_id != "capture":
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

	var base := CampaignBase.get_base_at_node(node_id)
	var has_valid_base := not base.is_empty() and int(base.get("state", -1)) != CampaignBase.BaseState.DESTROYED

	if not CAPTURABLE_NODE_TYPES.has(node_type) and not has_valid_base:
		return {
			"ok": false,
			"reason": "node_cannot_capture",
			"action_id": action_id,
			"node_id": node_id,
			"node_type": node_type,
		}

	var claim_faction := str(payload.get("claim_faction", DEFAULT_CLAIM_FACTION)).strip_edges()
	if claim_faction == "" or not FactionSystem.has_faction(claim_faction):
		return {
			"ok": false,
			"reason": "invalid_claim_faction",
			"action_id": action_id,
			"node_id": node_id,
			"claim_faction": claim_faction,
		}

	var base_id := str(base.get("id", ""))
	var prev_controller := str(base.get("controller", ""))

	# If base exists and already owned by claim faction -> reject idempotent double-capture
	if has_valid_base and prev_controller == claim_faction:
		return {
			"ok": false,
			"reason": "already_player_owned",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
			"controller": prev_controller,
		}

	# Identify territory context
	var terr_id := str(base.get("territory_id", ""))
	if terr_id == "":
		var covering := CampaignTerritory.get_territories_for_node(node_id)
		if not covering.is_empty():
			terr_id = str(covering[0].get("id", ""))

	# Execute atomic ownership mutation
	if has_valid_base:
		var base_ok := CampaignBase.set_controller(base_id, claim_faction)
		if not base_ok:
			return {
				"ok": false,
				"reason": "base_ownership_mutation_failed",
				"action_id": action_id,
				"node_id": node_id,
				"base_id": base_id,
			}

	# Update covering territory if present
	if terr_id != "" and CampaignTerritory.has_territory(terr_id):
		CampaignTerritory.set_controlled(terr_id, claim_faction)

	return {
		"ok": true,
		"reason": "capture_completed",
		"action_id": "capture",
		"node_id": node_id,
		"node_type": node_type,
		"base_id": base_id,
		"previous_controller": prev_controller,
		"new_controller": claim_faction,
		"territory_id": terr_id,
	}
