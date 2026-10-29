class_name CampaignPlayerForceAssault
extends RefCounted

## ---------------------------------------------------------------------------
## PLAYER DETACHMENT STRATEGIC ASSAULT — Phase C8-C.
##
## Lets a player detachment initiate (not only defend) a strategic engagement:
## it attacks one hostile `CampaignForce` at the same node and the fight is
## resolved by the same deterministic strength auto-battle used for base
## defence (C8-A), with no tactical scene.
##
## Audit evidence (do not re-decide lightly):
##   - `CampaignAttackAction` is the PLAYER-MECHA attack path: it validates a
##     node, records a `CampaignAttackBridge` engagement and enters tactical
##     combat as a grunt. It must not be reused for a detachment, because the
##     mecha bridge owns exactly one pending tactical session.
##   - `CampaignBattle` participants are `CampaignForce` ids by contract; a
##     `CampaignPlayerForce` detachment is a different authority (5A invariant),
##     so no battle record is fabricated here. A field engagement is resolved
##     immediately and reported in the receipt.
##   - Attrition constants are READ from `CampaignBaseDefense`
##     (`AUTO_BATTLE_ATTRITION_RATIO` / `AUTO_BATTLE_MAX_ROUNDS`) so the two
##     resolution paths can never drift apart.
##   - Hostility uses `FactionSystem.get_relation(...) == HOSTILE` — never
##     mere faction inequality (NEUTRAL/COOPERATIVE/ALLIED factions are not
##     legal targets).
##
## Firewalls: no base or territory ownership mutation, no capture, no turn
## advancement, no tactical combat entry, no supply/currency spend, no
## detection/heat writes beyond nothing at all. Deterministic: no RNG.
## ---------------------------------------------------------------------------


## Hostile, active enemy forces standing at a node (id-sorted, deterministic).
static func get_hostile_targets_at(node_id: String) -> Array:
	var out: Array = []
	if node_id == "":
		return out
	var player_faction := FactionSystem.get_player_faction()
	for fid in CampaignForce.get_active_forces_at_node(node_id):
		var target_id := str(fid)
		var force := CampaignForce.get_force(target_id)
		var faction := str(force.get("faction", ""))
		if faction == "" or faction == player_faction:
			continue
		if FactionSystem.get_relation(player_faction, faction) != FactionSystem.Relation.HOSTILE:
			continue
		out.append(target_id)
	out.sort()
	return out


## Validates one detachment-vs-force engagement without mutating anything.
static func can_attack(force_id: String, target_force_id: String) -> Dictionary:
	if force_id == "" or not CampaignPlayerForce.has_detachment(force_id):
		return {"ok": false, "reason": "unknown_detachment", "force_id": force_id}
	if not CampaignPlayerForce.is_active(force_id):
		return {"ok": false, "reason": "detachment_not_active", "force_id": force_id}
	var detachment := CampaignPlayerForce.get_detachment(force_id)
	if int(detachment.get("strength", 0)) <= 0:
		return {"ok": false, "reason": "detachment_no_strength", "force_id": force_id}
	var node_id := str(detachment.get("node_id", ""))
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return {"ok": false, "reason": "no_source_node", "force_id": force_id}
	if target_force_id == "" or not CampaignForce.has_force(target_force_id):
		return {"ok": false, "reason": "unknown_target", "force_id": force_id,
			"target_force_id": target_force_id}
	if CampaignForce.get_state(target_force_id) != CampaignForce.ForceState.ACTIVE:
		return {"ok": false, "reason": "target_not_active", "force_id": force_id,
			"target_force_id": target_force_id}
	var target := CampaignForce.get_force(target_force_id)
	if str(target.get("node_id", "")) != node_id:
		return {"ok": false, "reason": "target_not_at_node", "force_id": force_id,
			"target_force_id": target_force_id}
	var player_faction := FactionSystem.get_player_faction()
	var target_faction := str(target.get("faction", ""))
	if target_faction == "" or target_faction == player_faction:
		return {"ok": false, "reason": "target_not_hostile", "force_id": force_id,
			"target_force_id": target_force_id}
	if FactionSystem.get_relation(player_faction, target_faction) != FactionSystem.Relation.HOSTILE:
		return {"ok": false, "reason": "target_not_hostile", "force_id": force_id,
			"target_force_id": target_force_id, "relation": FactionSystem.get_relation_name(
				player_faction, target_faction)}
	return {
		"ok": true,
		"reason": "engagement_ready",
		"force_id": force_id,
		"target_force_id": target_force_id,
		"node_id": node_id,
	}


## Resolves one detachment-vs-force engagement immediately. Returns a receipt;
## {ok:false} rejects leave every authority untouched.
static func attack(force_id: String, target_force_id: String) -> Dictionary:
	var check := can_attack(force_id, target_force_id)
	if not bool(check.get("ok", false)):
		return check
	var node_id := str(check.get("node_id", ""))
	var detachment := CampaignPlayerForce.get_detachment(force_id)
	var enemy := CampaignForce.get_force(target_force_id)
	var player_strength := maxi(int(detachment.get("strength", 0)), 0)
	var enemy_strength := maxi(int(enemy.get("strength", 0)), 0)
	var enemy_units := maxi(int(enemy.get("unit_count", 0)), 0)
	var enemy_start_strength := maxi(int(enemy.get("strength", 0)), 1)
	var battle := CampaignAutoBattle.simulate(player_strength, enemy_strength)
	var rounds := int(battle.get("rounds", 0))
	player_strength = int(battle.get("defender_remaining", 0))
	enemy_strength = int(battle.get("attacker_remaining", 0))
	var raw_winner := str(battle.get("winner", "stalemate"))
	var enemy_units_lost := CampaignAutoBattle.unit_loss(
		enemy_units, enemy_start_strength, enemy_start_strength - enemy_strength)
	CampaignForce.set_composition(target_force_id, enemy_units - enemy_units_lost, enemy_strength)
	if enemy_strength == 0:
		CampaignForce.set_state(target_force_id, CampaignForce.ForceState.DESTROYED)

	var player_casualties := CampaignPlayerForce.apply_casualties(
		force_id, maxi(int(detachment.get("strength", 0)) - player_strength, 0))

	var winner := "stalemate"
	if raw_winner == "defender":
		winner = "player"
	elif raw_winner == "attacker":
		winner = "enemy"
	elif raw_winner == "mutual_destruction":
		winner = "mutual_destruction"

	return {
		"ok": true,
		"reason": "engagement_resolved",
		"winner": winner,
		"force_id": force_id,
		"target_force_id": target_force_id,
		"node_id": node_id,
		"rounds": rounds,
		"player_remaining": player_strength,
		"enemy_remaining": enemy_strength,
		"enemy_units_lost": enemy_units_lost,
		"player_casualties": player_casualties,
		"enemy_destroyed": enemy_strength == 0,
		"detachment_state": CampaignPlayerForce.state_to_name(
			CampaignPlayerForce.get_state(force_id)),
	}
