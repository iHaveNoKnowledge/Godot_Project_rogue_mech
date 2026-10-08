class_name CampaignAttackAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN ATTACK ACTION DOMAIN CONTRACT — Phase 5AU
##
## Domain authority for executing the player 'attack' action.
##
## Domain Responsibilities:
##   - Receives action intent targeted at a strategic node with hostile presence.
##   - Enforces attack domain preconditions (valid node, player presence, active hostile target).
##   - Validates target hostile forces and/or hostile base installations at the node.
##   - Orchestrates campaign battle engagement entry via CampaignBattle.
##   - Produces a deterministic attack initiation receipt.
##   - Enforces strict firewalls: ZERO ownership mutation (Capture separation),
##     ZERO turn advancement (Turn separation), ZERO resource or position mutations.
##
## Architectural Invariants:
##   - ATTACK != CAPTURE: Attack never calls CampaignBase.set_controller() or
##     CampaignTerritory.set_controlled().
##   - ATTACK != TURN: Attack never calls CampaignTurnExecutive.advance_campaign_turn().
##   - ATTACK != COMBAT RESOLUTION: Tactical combat execution and resolution belong
##     to CampaignBattle / tactical systems.
## ---------------------------------------------------------------------------

const DEFAULT_PLAYER_FACTION: String = "federation"

const ATTACKABLE_NODE_TYPES := [
	"ENEMY_BASE",
]


## Checks whether a node currently hosts an attackable hostile target.
static func is_attackable_node(node_id: String, player_faction: String = "") -> bool:
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return false

	var cur_player_faction := player_faction if player_faction != "" else FactionSystem.get_player_faction()
	var node := CampaignNodeRegistry.get_node(node_id)
	var node_type := str(node.get("node_type", "")).to_upper()

	# 1. Check for active hostile forces at node
	var active_forces := CampaignForce.get_active_forces_at_node(node_id)
	for fid in active_forces:
		var f := CampaignForce.get_force(str(fid))
		var faction := str(f.get("faction", ""))
		if faction != "" and faction != cur_player_faction:
			return true

	# 2. Check for hostile base at node
	var base := CampaignBase.get_base_at_node(node_id)
	if not base.is_empty() and int(base.get("state", -1)) != CampaignBase.BaseState.DESTROYED:
		var base_ctrl := str(base.get("controller", ""))
		if base_ctrl != "" and base_ctrl != cur_player_faction:
			return true

	# 3. Dedicated ENEMY_BASE node type without player base
	if ATTACKABLE_NODE_TYPES.has(node_type):
		if base.is_empty() or str(base.get("controller", "")) != cur_player_faction:
			return true

	return false


## Executes the domain attack action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_attack(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()
	var payload: Dictionary = intent.get("payload", {})

	if action_id != "attack":
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

	var raw_faction: Variant = payload.get("player_faction", null)
	var player_faction: String = str(raw_faction).strip_edges() if raw_faction != null else FactionSystem.get_player_faction()
	if player_faction == "" or not FactionSystem.has_faction(player_faction):
		player_faction = FactionSystem.get_player_faction()

	var node := CampaignNodeRegistry.get_node(node_id)
	var node_type := str(node.get("node_type", "")).to_upper()
	var sector := int(node.get("sector", 1))

	# Inspect forces and base
	var active_force_ids := CampaignForce.get_active_forces_at_node(node_id)
	var hostile_force_ids: Array = []
	var primary_target_faction := ""

	for fid in active_force_ids:
		var f := CampaignForce.get_force(str(fid))
		var f_fac := str(f.get("faction", ""))
		if f_fac != player_faction:
			hostile_force_ids.append(str(fid))
			if primary_target_faction == "" and f_fac != "":
				primary_target_faction = f_fac

	var base := CampaignBase.get_base_at_node(node_id)
	var base_id := str(base.get("id", ""))
	var base_ctrl := str(base.get("controller", ""))
	var base_is_hostile := false

	if not base.is_empty() and int(base.get("state", -1)) != CampaignBase.BaseState.DESTROYED:
		if base_ctrl != "" and base_ctrl == player_faction:
			# Base is friendly to player
			if hostile_force_ids.is_empty():
				return {
					"ok": false,
					"reason": "target_not_hostile",
					"action_id": action_id,
					"node_id": node_id,
					"base_id": base_id,
					"controller": base_ctrl,
				}
		elif base_ctrl != "":
			base_is_hostile = true
			if primary_target_faction == "":
				primary_target_faction = base_ctrl
	elif ATTACKABLE_NODE_TYPES.has(node_type):
		base_is_hostile = true
		if primary_target_faction == "":
			primary_target_faction = "zeon"

	# If no hostile forces and no hostile base -> not attackable
	if hostile_force_ids.is_empty() and not base_is_hostile:
		return {
			"ok": false,
			"reason": "no_active_target",
			"action_id": action_id,
			"node_id": node_id,
			"node_type": node_type,
		}

	var primary_target_id := ""
	if not hostile_force_ids.is_empty():
		primary_target_id = hostile_force_ids[0]
	elif base_id != "":
		primary_target_id = base_id
	else:
		primary_target_id = node_id

	# Construct or engage battle in CampaignBattle
	var battle_id := str(payload.get("battle_id", ""))
	if battle_id == "":
		battle_id = CampaignBattle.make_battle_id(sector, "atk_" + node_id)

	if not CampaignBattle.has_battle(battle_id):
		if not hostile_force_ids.is_empty():
			CampaignBattle.register_battle(battle_id, node_id, hostile_force_ids)
			CampaignBattle.prepare_launch(battle_id)
		elif base_is_hostile:
			var garrison_fid := "force_garrison_" + node_id
			if not CampaignForce.has_force(garrison_fid):
				var fac := primary_target_faction if primary_target_faction != "" else "zeon"
				CampaignForce.register_force(garrison_fid, "PATROL", fac, node_id, base_id, 1, 10)
			hostile_force_ids.append(garrison_fid)
			CampaignBattle.register_battle(battle_id, node_id, [garrison_fid])
			CampaignBattle.prepare_launch(battle_id)

	return {
		"ok": true,
		"reason": "attack_started",
		"action_id": "attack",
		"node_id": node_id,
		"node_type": node_type,
		"target_id": primary_target_id,
		"battle_id": battle_id,
		"target_forces": hostile_force_ids,
		"target_base": base_id,
		"target_faction": primary_target_faction,
	}
