class_name CampaignDefendAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN DEFEND ACTION DOMAIN CONTRACT — Phase S2-A
##
## Domain authority for executing the player 'defend' action: intervene in an
## ongoing assault against a player-controlled base and enter the existing
## playable tactical battle.
##
## Domain Responsibilities:
##   - Receives a validated action intent targeted at a strategic node.
##   - Enforces defend preconditions (known node, base present and intact,
##     player-controlled, ACTIVE assault, player physically present).
##   - Routes the intervention through CampaignBaseDefense (intervention
##     eligibility + session marker, never ownership mutation).
##   - Enters the existing playable battle via GameManager.enter_combat with
##     the established neutral combat type (same value the convoy defense
##     flow passes; spawn logic falls back to grunt waves and no raid,
##     duel, or patrol side effects apply).
##   - Produces a deterministic defense-initiation receipt.
##
## Architectural Contract:
##   - What it inspects: Target node from CampaignNodeRegistry, base record
##     from CampaignBase, assault/battle from CampaignBaseDefense/CampaignBattle.
##   - What it mutates: Battle session_ref (via intervene), the S2-A pending
##     engagement slot (via record), GameManager combat state (via the
##     existing enter_combat path). ZERO base/territory/force/currency/fuel
##     mutation, ZERO turn advancement.
##   - Failure: deterministic {ok:false} with ZERO side effects.
## ---------------------------------------------------------------------------

## Combat type passed to GameManager.enter_combat for a defense engagement.
## Proven existing value: convoy_escort.gd sets combat_node_type "defense"
## and enters with "grunt"; SpawnManager resolves waves to grunt, rewards
## treat it as neither duel nor raid, and GlobalData._on_combat_ended takes
## no patrol/duel/enemy_base/fuel_depot branch for it.
const DEFENSE_COMBAT_TYPE := "grunt"


## Executes the domain defend action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_defend(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()

	if action_id != "defend":
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

	var base := CampaignBase.get_base_at_node(node_id)
	if base.is_empty():
		return {
			"ok": false,
			"reason": "no_base_to_defend",
			"action_id": action_id,
			"node_id": node_id,
		}

	var base_id := str(base.get("id", ""))
	if int(base.get("state", -1)) == CampaignBase.BaseState.DESTROYED:
		return {
			"ok": false,
			"reason": "base_destroyed",
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

	if CampaignBaseDefense.get_defense_battle_for_base(base_id).is_empty():
		return {
			"ok": false,
			"reason": "base_not_under_attack",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
		}
	var battle_id := str(
		CampaignBaseDefense.get_defense_battle_for_base(base_id).get("id", ""))

	var check := CampaignBaseDefense.can_intervene(battle_id, player_faction)
	if not bool(check.get("ok", false)):
		var failed := (check as Dictionary).duplicate(true)
		failed["action_id"] = action_id
		failed["node_id"] = node_id
		failed["base_id"] = base_id
		return failed

	var started := CampaignBaseDefense.intervene(battle_id, player_faction)
	if not bool(started.get("ok", false)):
		var failed_start := (started as Dictionary).duplicate(true)
		failed_start["action_id"] = action_id
		failed_start["node_id"] = node_id
		failed_start["base_id"] = base_id
		return failed_start

	var session_ref := str(started.get("session_ref", ""))
	if not CampaignBaseDefense.record_defense_engagement(battle_id, base_id):
		return {
			"ok": false,
			"reason": "intervention_record_failed",
			"action_id": action_id,
			"node_id": node_id,
			"base_id": base_id,
			"battle_id": battle_id,
		}

	CampaignBaseDefense.ensure_defense_result_hook()
	GameManager.enter_combat(DEFENSE_COMBAT_TYPE)

	return {
		"ok": true,
		"reason": "defense_started",
		"action_id": "defend",
		"node_id": node_id,
		"base_id": base_id,
		"battle_id": battle_id,
		"session_ref": session_ref,
		"combat_type": DEFENSE_COMBAT_TYPE,
		"participants": started.get("participants", []),
	}
