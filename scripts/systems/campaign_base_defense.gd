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

	var session_ref := INTERVENTION_SESSION_PREFIX + battle_id
	CampaignBattle.set_session_ref(battle_id, session_ref)

	return {
		"ok": true,
		"reason": "intervention_started",
		"battle_id": battle_id,
		"node_id": node_id,
		"participants": participants,
		"session_ref": session_ref,
	}


## ---------------------------------------------------------------------------
## S2-A DEFENSE ENGAGEMENT & RESULT APPLICATION (player-side base defense).
##
## The pending slot holds AT MOST ONE player-driven defense engagement. It is
## written only by record_defense_engagement() after full validation and
## cleared only when its result is consumed, so a stored battle id alone can
## never apply anything: every consume re-validates the live battle record
## (exists, ACTIVE, session_ref match, base/node coherence) and
## resolve_battle() itself accepts only ACTIVE battles (consume-once).
##
## session_ref is the persisted side of the mapping (CampaignBattle records
## survive SaveGameIO), so a save/load that wipes this static slot is
## recovered by recover_pending_defense_from_records(). Retreat
## (EventBus.combat_escaped) is deliberately NOT subscribed: an escaped
## engagement stays ACTIVE with its session intact, preserving the assault.
## ---------------------------------------------------------------------------

## Prefix marking a battle record as carrying a player defense intervention.
const INTERVENTION_SESSION_PREFIX := "session_intervention_"

## Pending engagement: battle_id -> {base_id, node_id, session_ref, attacker_force_id}.
static var _pending_defense: Dictionary = {}
static var _defense_result_hook_connected: bool = false


## Clears the pending slot and hook flag. Battles, bases, and forces are
## untouched. Used by tests and run-state resets; production recovery after
## save/load goes through recover_pending_defense_from_records() instead.
static func reset_defense_state() -> void:
	_pending_defense.clear()
	_defense_result_hook_connected = false


## Returns the pending defense battle id, or "" when no engagement is tracked.
static func get_pending_defense_battle_id() -> String:
	for bid in _pending_defense:
		return str(bid)
	return ""


## Records one validated defense engagement, replacing any previous slot.
## False (slot left empty) unless the battle is a live, coherent intervention:
## known + ACTIVE battle, session_ref exactly this engagement's marker, and
## the base still anchored at the battle node.
static func record_defense_engagement(battle_id: String, base_id: String) -> bool:
	_pending_defense.clear()
	if battle_id == "" or base_id == "":
		return false
	if not CampaignBattle.has_battle(battle_id) or not CampaignBattle.is_active(battle_id):
		return false
	if not CampaignBase.has_base(base_id):
		return false
	var battle := CampaignBattle.get_battle(battle_id)
	var node_id := str(battle.get("node_id", ""))
	if str(CampaignBase.get_base(base_id).get("node_id", "")) != node_id:
		return false
	var session_ref := str(battle.get("session_ref", ""))
	if session_ref != INTERVENTION_SESSION_PREFIX + battle_id:
		return false
	_pending_defense[battle_id] = {
		"base_id": base_id,
		"node_id": node_id,
		"session_ref": session_ref,
		"attacker_force_id": _find_lone_attacker(battle, base_id),
	}
	return true


## Returns the single hostile participant's force id when the battle holds
## exactly one force whose faction differs from the base controller, else "".
## Identity comes from live force records, never from id naming conventions.
static func _find_lone_attacker(battle: Dictionary, base_id: String) -> String:
	var controller := str(CampaignBase.get_base(base_id).get("controller", ""))
	var hostile := ""
	var hostile_count := 0
	for f in Array(battle.get("participants", [])):
		var fid := str(f)
		if not CampaignForce.has_force(fid):
			continue
		if str(CampaignForce.get_force(fid).get("faction", "")) != controller:
			hostile = fid
			hostile_count += 1
	if hostile_count == 1:
		return hostile
	return ""


## Subscribes the result applier to the existing tactical result flow.
## Idempotent; safe to call on every defense entry.
static func ensure_defense_result_hook() -> void:
	if _defense_result_hook_connected:
		return
	var hook := Callable(CampaignBaseDefense, "_on_defense_combat_ended")
	if not EventBus.combat_ended.is_connected(hook):
		EventBus.combat_ended.connect(hook)
	_defense_result_hook_connected = true


## Rebuilds the pending slot from persisted battle records after a save/load
## (which wipes static state but keeps session_ref inside battle records).
## Stale intervention markers on non-ACTIVE battles are cleared; at most one
## ACTIVE intervention is re-tracked.
static func recover_pending_defense_from_records() -> void:
	if not get_pending_defense_battle_id() == "":
		return
	for b in CampaignBattle.get_battles():
		var bid := str(b.get("id", ""))
		var sess := str(b.get("session_ref", ""))
		if not sess.begins_with(INTERVENTION_SESSION_PREFIX):
			continue
		if sess != INTERVENTION_SESSION_PREFIX + bid:
			continue
		if not CampaignBattle.is_active(bid):
			CampaignBattle.clear_session_ref(bid)
			continue
		var node_id := str(b.get("node_id", ""))
		var base := CampaignBase.get_base_at_node(node_id)
		if base.is_empty():
			continue
		var base_id := str(base.get("id", ""))
		if get_defense_battle_for_base(base_id).is_empty():
			continue
		if str(get_defense_battle_for_base(base_id).get("id", "")) != bid:
			continue
		record_defense_engagement(bid, base_id)
		return


## Validates the pending slot against live records and consumes it.
## Returns the engagement context, or {} when invalid (slot cleared either way,
## so an invalid entry can never apply later).
static func _consume_validated_pending(battle_id: String) -> Dictionary:
	var ctx: Dictionary = (_pending_defense.get(battle_id, {}) as Dictionary).duplicate(true)
	_pending_defense.clear()
	if ctx.is_empty():
		return {}
	if not CampaignBattle.has_battle(battle_id) or not CampaignBattle.is_active(battle_id):
		return {}
	var battle := CampaignBattle.get_battle(battle_id)
	if str(battle.get("session_ref", "")) != str(ctx.get("session_ref", "")):
		return {}
	var base_id := str(ctx.get("base_id", ""))
	if not CampaignBase.has_base(base_id):
		return {}
	if str(CampaignBase.get_base(base_id).get("node_id", "")) != str(battle.get("node_id", "")):
		return {}
	ctx["battle_id"] = battle_id
	return ctx


## Applier for the existing tactical result flow (see ensure_defense_result_hook).
## Ignores every battle that is not the validated pending defense engagement:
## unrelated victories/defeats and duplicate deliveries mutate nothing.
##   victory -> resolve battle, destroy the lone attacker (when unambiguous);
##              base ownership and condition untouched.
##   defeat  -> resolve battle, base ACTIVE->DISABLED via the state graph;
##              controller ownership NEVER changes; attacker untouched.
static func _on_defense_combat_ended(victory: bool) -> void:
	var battle_id := get_pending_defense_battle_id()
	if battle_id == "":
		recover_pending_defense_from_records()
		battle_id = get_pending_defense_battle_id()
		if battle_id == "":
			return
	var ctx := _consume_validated_pending(battle_id)
	if ctx.is_empty():
		return
	if not CampaignBattle.resolve_battle(battle_id):
		return
	var base_id := str(ctx.get("base_id", ""))
	if victory:
		var attacker_id := str(ctx.get("attacker_force_id", ""))
		if attacker_id != "" and CampaignForce.has_force(attacker_id):
			if CampaignForce.get_state(attacker_id) != CampaignForce.ForceState.DESTROYED:
				CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DESTROYED)
	else:
		if CampaignBase.has_base(base_id):
			CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED)
	CampaignBattle.clear_session_ref(battle_id)
