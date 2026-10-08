class_name CampaignInvestigateAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN INVESTIGATE ACTION DOMAIN CONTRACT — Phase 5AN
##
## Domain authority for executing the player 'investigate' action.
##
## Domain Responsibilities:
##   - Receives validated action intent targeted at a node.
##   - Performs domain-level precondition checks.
##   - Reads the strategic node situation via CampaignNodeInspection.
##   - Produces a deterministic investigation result contract.
##   - Enforces zero unintended side-effects on campaign authorities.
##
## Architectural Contract:
##   - What it inspects: Node situation projection (forces, bases, territory, routes, factions).
##   - What it mutates: ZERO state mutation (read-only tactical reconnaissance).
##   - What it consumes: Zero resources/supplies/turns.
##   - Success result: { "ok": true, "reason": "investigation_resolved", "action_id": "investigate", "node_id": node_id, "situation": Dictionary }
##   - Failure result: { "ok": false, "reason": String, "action_id": "investigate", "node_id": node_id }
## ---------------------------------------------------------------------------

const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")


## Executes the domain investigation action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_investigate(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if action_id != "investigate":
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

	var situation := CampaignNodeInspection.inspect_node(node_id)
	if not bool(situation.get("ok", false)):
		return {
			"ok": false,
			"reason": str(situation.get("reason", "inspection_failed")),
			"action_id": action_id,
			"node_id": node_id,
		}

	return {
		"ok": true,
		"reason": "investigation_resolved",
		"action_id": "investigate",
		"node_id": node_id,
		"situation": situation,
	}
