class_name CampaignBaseDefense
extends RefCounted

## ---------------------------------------------------------------------------
## BASE DEFENSE / BASE ATTACK / INTERVENTION BOUNDARY — Phase 5AV
##
## Establishes the boundary contract between:
##   - Hostile Force attacking a Base (World Simulation)
##   - CampaignBattle representing the ongoing base assault (Combat Authority)
##   - Base Defense state & query inspection (Base State Authority)
##   - Player Intervention Eligibility (Physical Presence Gate)
##   - Zero Instant Capture & Zero Direct Ownership Mutation (5AT Firewalled)
##   - Zero Automatic Turn Advancement (5AQ Firewalled)
##   - Zero Automatic Battle Victory / Resolution (Tactical Session Firewalled)
##
## Architectural Invariants:
##   - BASE ATTACK != CAPTURE: Attacking a base creates an active CampaignBattle;
##     it never calls CampaignBase.set_controller() or CampaignTerritory.set_controlled().
##   - BASE ATTACK != PLAYER ATTACK: Base attack is world/faction-driven;
##     player attack is intent-driven via CampaignAttackAction.
##   - INTERVENTION != AUTOMATIC VICTORY: Player intervention prepares combat entry;
##     it never marks CampaignBattle as RESOLVED or destroys enemy forces.
##   - TURN DELTA = 0: All base attack and intervention operations have zero turn impact.
## ---------------------------------------------------------------------------

const DEFAULT_PLAYER_FACTION: String = "federation"


## Initiates a base attack by a hostile force, registering a defense battle in CampaignBattle.
## Returns a structured receipt.
static func start_base_attack(base_id: String, attacker_force_id: String) -> Dictionary:
	if base_id == "" or not CampaignBase.has_base(base_id):
		return {
			"ok": false,
			"reason": "unknown_base",
			"base_id": base_id,
			"attacker_force_id": attacker_force_id,
		}

	var base := CampaignBase.get_base(base_id)
	if int(base.get("state", -1)) == CampaignBase.BaseState.DESTROYED:
		return {
			"ok": false,
			"reason": "base_destroyed",
			"base_id": base_id,
			"attacker_force_id": attacker_force_id,
		}

	var node_id := str(base.get("node_id", "")).strip_edges()
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return {
			"ok": false,
			"reason": "invalid_base_node",
			"base_id": base_id,
			"node_id": node_id,
			"attacker_force_id": attacker_force_id,
		}

	if attacker_force_id == "" or not CampaignForce.has_force(attacker_force_id):
		return {
			"ok": false,
			"reason": "unknown_attacker_force",
			"base_id": base_id,
			"node_id": node_id,
			"attacker_force_id": attacker_force_id,
		}

	var attacker := CampaignForce.get_force(attacker_force_id)
	if int(attacker.get("state", -1)) == CampaignForce.ForceState.DESTROYED:
		return {
			"ok": false,
			"reason": "attacker_force_destroyed",
			"base_id": base_id,
			"node_id": node_id,
			"attacker_force_id": attacker_force_id,
		}

	var attacker_node := str(attacker.get("node_id", "")).strip_edges()
	if attacker_node != node_id:
		return {
			"ok": false,
			"reason": "attacker_not_at_base_node",
			"base_id": base_id,
			"node_id": node_id,
			"attacker_node": attacker_node,
			"attacker_force_id": attacker_force_id,
		}

	var attacker_faction := str(attacker.get("faction", "")).strip_edges()
	var base_controller := str(base.get("controller", "")).strip_edges()

	if base_controller != "" and attacker_faction == base_controller:
		return {
			"ok": false,
			"reason": "attacker_not_hostile",
			"base_id": base_id,
			"node_id": node_id,
			"attacker_faction": attacker_faction,
			"base_controller": base_controller,
		}

	# Identify or create defender force / garrison
	var node := CampaignNodeRegistry.get_node(node_id)
	var sector := int(node.get("sector", 1))

	var active_forces := CampaignForce.get_active_forces_at_node(node_id)
	var defender_force_id := ""
	for fid in active_forces:
		var fid_str := str(fid)
		if fid_str == attacker_force_id:
			continue
		var f := CampaignForce.get_force(fid_str)
		var f_fac := str(f.get("faction", "")).strip_edges()
		if base_controller != "" and f_fac == base_controller:
			defender_force_id = fid_str
			break
		elif base_controller == "" and f_fac != attacker_faction:
			defender_force_id = fid_str
			break

	if defender_force_id == "":
		defender_force_id = "force_garrison_" + node_id
		if not CampaignForce.has_force(defender_force_id):
			var def_fac := base_controller if base_controller != "" else FactionSystem.get_player_faction()
			CampaignForce.register_force(defender_force_id, "PATROL", def_fac, node_id, base_id, 1, 10)

	var participants: Array = [attacker_force_id, defender_force_id]
	participants.sort()

	# Register and launch battle in CampaignBattle
	var battle_id := CampaignBattle.make_battle_id(sector, "def_" + base_id)
	if not CampaignBattle.has_battle(battle_id):
		CampaignBattle.register_battle(battle_id, node_id, participants)
		CampaignBattle.prepare_launch(battle_id)
	elif not CampaignBattle.is_active(battle_id) and CampaignBattle.is_planned(battle_id):
		CampaignBattle.prepare_launch(battle_id)

	return {
		"ok": true,
		"reason": "base_attack_started",
		"base_id": base_id,
		"node_id": node_id,
		"battle_id": battle_id,
		"attacker_force_id": attacker_force_id,
		"defender_force_id": defender_force_id,
		"participants": participants,
		"base_controller": base_controller,
	}


## Queries whether a base is currently involved in an active defense battle.
static func is_base_under_attack(base_id: String) -> bool:
	return not get_defense_battle_for_base(base_id).is_empty()


## Returns the active defense battle for the base, or empty dictionary if none.
static func get_defense_battle_for_base(base_id: String) -> Dictionary:
	if base_id == "" or not CampaignBase.has_base(base_id):
		return {}

	var base := CampaignBase.get_base(base_id)
	var node_id := str(base.get("node_id", ""))
	if node_id == "":
		return {}

	var expected_slug := "def_" + base_id
	for b in CampaignBattle.get_battles():
		var bid := str(b.get("id", ""))
		if bid.find(expected_slug) != -1 and CampaignBattle.is_active(bid):
			return b
		if str(b.get("node_id", "")) == node_id and CampaignBattle.is_active(bid):
			return b

	return {}


## Checks whether the player can physically intervene in the ongoing defense battle.
static func can_intervene(battle_id: String, player_faction: String = "") -> Dictionary:
	var cur_player_faction := player_faction if player_faction != "" else FactionSystem.get_player_faction()
	if battle_id == "" or not CampaignBattle.has_battle(battle_id):
		return {
			"ok": false,
			"reason": "unknown_battle",
			"battle_id": battle_id,
		}

	if not CampaignBattle.is_active(battle_id):
		return {
			"ok": false,
			"reason": "battle_not_active",
			"battle_id": battle_id,
			"state": CampaignBattle.state_to_name(CampaignBattle.get_state(battle_id)),
		}

	var battle := CampaignBattle.get_battle(battle_id)
	var node_id := str(battle.get("node_id", ""))

	if not CampaignNodeInspection.is_player_at_node(node_id):
		return {
			"ok": false,
			"reason": "player_not_at_node",
			"battle_id": battle_id,
			"node_id": node_id,
		}

	return {
		"ok": true,
		"reason": "intervention_eligible",
		"battle_id": battle_id,
		"node_id": node_id,
		"player_faction": cur_player_faction,
		"participants": battle.get("participants", []),
	}


## Executes player tactical intervention into an active defense battle.
## Prepares playable combat descriptor without mutating ownership or resolving battle prematurely.
static func intervene(battle_id: String, player_faction: String = "") -> Dictionary:
	var cur_player_faction := player_faction if player_faction != "" else FactionSystem.get_player_faction()
	var check := can_intervene(battle_id, cur_player_faction)
	if not bool(check.get("ok", false)):
		return check

	var battle := CampaignBattle.get_battle(battle_id)
	var node_id := str(battle.get("node_id", ""))
	var participants: Array = battle.get("participants", [])

	var session_ref := "session_intervention_" + battle_id
	CampaignBattle.set_session_ref(battle_id, session_ref)

	return {
		"ok": true,
		"reason": "intervention_started",
		"battle_id": battle_id,
		"node_id": node_id,
		"participants": participants,
		"session_ref": session_ref,
	}
