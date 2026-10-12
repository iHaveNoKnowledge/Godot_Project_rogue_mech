class_name CampaignRecoverAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN RECOVER ACTION DOMAIN CONTRACT — Phase 2D-1
##
## Domain authority for executing the player 'recover' action: reactivate a
## DISABLED player-controlled base back to ACTIVE for a flat credit fee.
##
## Domain Responsibilities:
##   - Receives a validated action intent targeted at a strategic node.
##   - Enforces recover preconditions (known node, base present, DISABLED,
##     player-controlled, no ACTIVE assault, player present, funded).
##   - Deducts exactly RECOVER_COST_CREDITS via CurrencyManager and applies
##     the authoritative DISABLED -> ACTIVE transition via CampaignBase.
##   - Produces a deterministic recovery receipt.
##
## Architectural Contract:
##   - What it inspects: Target node from CampaignNodeRegistry, base record
##     from CampaignBase, assault state from CampaignBaseDefense, funds from
##     CurrencyManager, presence from CampaignNodeInspection.
##   - What it mutates: GlobalData.currency.credits (-150) and the base state
##     (DISABLED -> ACTIVE). NOTHING else: no controller/ownership change, no
##     turn advancement, no assault/battle/force/fuel mutation.
##   - Atomicity: every eligibility check (including a funds read) runs before
##     any mutation; spending uses atomic try_spend_credits; the DISABLED ->
##     ACTIVE edge is graph-legal after validation, and a defensive refund via
##     the existing gain_credits() restores the fee if the transition ever
##     reports failure. No new transaction framework, no invented refund API.
##   - Failure: deterministic {ok:false} with ZERO net mutation.
## ---------------------------------------------------------------------------

## Flat reactivation fee in credits (approved Phase 2D-1 authorization).
const RECOVER_COST_CREDITS := 150


## Executes the domain recover action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_recover(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if action_id != "recover":
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

	# Authoritative lookup: DESTROYED bases are invisible here by contract,
	# so they (and missing bases) share one rejection.
	var base := CampaignBase.get_base_at_node(node_id)
	if base.is_empty():
		return {
			"ok": false,
			"reason": "no_base_to_recover",
			"action_id": action_id,
			"node_id": node_id,
		}

	var base_id := str(base.get("id", ""))
	if int(base.get("state", -1)) != CampaignBase.BaseState.DISABLED:
		return {
			"ok": false,
			"reason": "base_not_disabled",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
		}

	var player_faction := FactionSystem.get_player_faction()
	var controller := str(base.get("controller", "")).strip_edges()
	if controller != player_faction:
		return {
			"ok": false,
			"reason": "not_player_base",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
			"controller": controller,
		}

	if not CampaignBaseDefense.get_defense_battle_for_base(base_id).is_empty():
		return {
			"ok": false,
			"reason": "assault_in_progress",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
		}

	if GlobalData == null or GlobalData.currency == null:
		return {
			"ok": false,
			"reason": "economy_authority_unavailable",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
		}

	if int(GlobalData.currency.credits) < RECOVER_COST_CREDITS:
		return {
			"ok": false,
			"reason": "insufficient_credits",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
			"cost": RECOVER_COST_CREDITS,
			"credits": int(GlobalData.currency.credits),
		}

	if not GlobalData.currency.try_spend_credits(RECOVER_COST_CREDITS):
		return {
			"ok": false,
			"reason": "insufficient_credits",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
			"cost": RECOVER_COST_CREDITS,
			"credits": int(GlobalData.currency.credits),
		}

	if not CampaignBase.set_state(base_id, CampaignBase.BaseState.ACTIVE):
		GlobalData.currency.gain_credits(RECOVER_COST_CREDITS)
		return {
			"ok": false,
			"reason": "recovery_failed",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
		}

	return {
		"ok": true,
		"reason": "recovery_completed",
		"action_id": "recover",
		"node_id": node_id,
		"base_id": base_id,
		"controller": controller,
		"credits_spent": RECOVER_COST_CREDITS,
		"credits_remaining": int(GlobalData.currency.credits),
	}
