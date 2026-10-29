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

## Phase C8-A auto-battle. The formula and its tuned constants live in
## `CampaignAutoBattle` (C8-D) so defence and assault can never drift; this
## file only applies the result to the authorities it owns.


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

	# Register and launch battle in CampaignBattle under a derived identity
	# (legacy def_<base> for the first assault, suffixed afterwards).
	var battle_id := next_defense_battle_id(sector, base_id)
	if not CampaignBattle.has_battle(battle_id):
		if CampaignBattle.register_battle(battle_id, node_id, participants) == "":
			return {
				"ok": false,
				"reason": "battle_registration_failed",
				"base_id": base_id,
				"node_id": node_id,
				"battle_id": battle_id,
				"attacker_force_id": attacker_force_id,
			}
		var launched := CampaignBattle.prepare_launch(battle_id)
		if not bool(launched.get("ok", false)):
			return {
				"ok": false,
				"reason": "battle_launch_failed",
				"base_id": base_id,
				"node_id": node_id,
				"battle_id": battle_id,
				"attacker_force_id": attacker_force_id,
			}
	elif CampaignBattle.is_active(battle_id):
		pass
	elif CampaignBattle.is_planned(battle_id):
		CampaignBattle.prepare_launch(battle_id)
	else:
		return {
			"ok": false,
			"reason": "battle_already_resolved",
			"base_id": base_id,
			"node_id": node_id,
			"battle_id": battle_id,
			"attacker_force_id": attacker_force_id,
		}

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


## Derives the battle identity for an assault on a base. The first assault
## keeps the legacy stable id (def_<base_id>, compatible with existing saves,
## tests, and session markers). Later assaults use deterministic suffixed ids
## (def_<base_id>_s2, _s3, ...) derived from authoritative battle records —
## no counter, no new state. An open (PLANNED or ACTIVE) battle is reused so
## a second assault never duplicates or bypasses it; terminal history only
## advances the suffix.
static func next_defense_battle_id(sector: int, base_id: String) -> String:
	var slug := "def_" + base_id
	var candidate := CampaignBattle.make_battle_id(sector, slug)
	if not CampaignBattle.has_battle(candidate):
		return candidate
	if CampaignBattle.is_active(candidate) or CampaignBattle.is_planned(candidate):
		return candidate
	var n := 2
	while true:
		candidate = CampaignBattle.make_battle_id(sector, slug + "_s" + str(n))
		if not CampaignBattle.has_battle(candidate):
			return candidate
		if CampaignBattle.is_active(candidate) or CampaignBattle.is_planned(candidate):
			return candidate
		n += 1
	return candidate


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
		if not CampaignBattle.is_active(bid):
			continue
		if _is_defense_battle_id(bid, expected_slug):
			return b

	return {}


## Defense-family identity check for a battle id against one base's slug.
## Matches exactly what next_defense_battle_id() generates and nothing else:
## a legacy id ending with the slug, or the slug followed by "_s<digits>".
## Attack ids (atk_...), other bases' slugs (def_base_ab vs def_base_a), and
## unknown hand-made ids never match — node co-location alone proves nothing.
static func _is_defense_battle_id(bid: String, expected_slug: String) -> bool:
	if bid == "" or expected_slug == "":
		return false
	if bid.ends_with(expected_slug):
		return true
	var marker := expected_slug + "_s"
	var idx := bid.find(marker)
	while idx != -1:
		if bid.substr(idx + marker.length()).is_valid_int():
			return true
		idx = bid.find(marker, idx + 1)
	return false


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
	# Entry mutual exclusion (Gate 3A mirror): never open a second
	# campaign-result pending session while an attack engagement is live.
	# Read-only check first, so rejection is side-effect free.
	if CampaignAttackBridge.get_pending_attack_battle_id() != "":
		return {
			"ok": false,
			"reason": "attack_engagement_active",
			"battle_id": battle_id,
		}
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


## Clears the pending slot, assault records, and hook flag. Battles, bases,
## and forces are untouched. Used by tests and run-state resets; production
## recovery after save/load goes through recover_pending_defense_from_records()
## and the assault deserializer instead.
static func reset_defense_state() -> void:
	_pending_defense.clear()
	_assaults.clear()
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
	clear_assault(battle_id)
	CampaignBattle.clear_session_ref(battle_id)


## ---------------------------------------------------------------------------
## S2-B PHASE 2A ASSAULT RECORDS, SCHEDULING & ABSOLUTE DEADLINE.
##
## Assault record: battle_id -> {base_id, controller, created_turn,
## deadline_turn, expired}. The pinned controller detects mid-assault
## ownership flips (capture): a live controller mismatch defers resolution.
## Created ONLY by process_assault_turn() after start_base_attack()
## yields an ACTIVE battle; deadline_turn = creation_turn + 2 (absolute
## campaign turn, the only turn authority in use).
##
## Intervention stays valid while get_turn() <= deadline_turn; expiration is
## eligible only when get_turn() > deadline_turn. Retreat and re-intervention
## never touch the record. Expired records are MARKED (expired=true,
## persisted) and preserved for the approved auto-resolve phase: this phase
## never destroys forces, disables bases, changes ownership, or resolves
## battles. Records whose battle is no longer ACTIVE are stale (assault over)
## and dropped by the scan. One assault per base per run follows from the
## stable battle ids (def_<base_id>) owned by CampaignBattle.
## ---------------------------------------------------------------------------

static var _assaults: Dictionary = {}


## Returns all assault records keyed by battle id (duplicated, read-only view).
static func get_assaults() -> Dictionary:
	var out := {}
	for bid in _assaults:
		out[str(bid)] = ((_assaults[bid] as Dictionary).duplicate(true))
	return out


## Returns one assault record, or {} when unknown.
static func get_assault(battle_id: String) -> Dictionary:
	if battle_id == "" or not _assaults.has(battle_id):
		return {}
	return ((_assaults[battle_id] as Dictionary).duplicate(true))


## True when the record exists and is marked expired.
static func is_assault_expired(battle_id: String) -> bool:
	return bool(get_assault(battle_id).get("expired", false))


## Drops one assault record. Battles, bases, and forces are untouched.
static func clear_assault(battle_id: String) -> void:
	_assaults.erase(battle_id)


## Day-boundary assault maintenance for one campaign turn. Never advances the
## turn. Returns {created, expired_marked, dropped_stale} battle-id lists:
##   1. drop records whose battle is missing or no longer ACTIVE;
##   2. mark records expired when turn > deadline_turn (ACTIVE battles only);
##   3. start assaults for eligible player bases with none in flight.
## Newly created records carry deadline_turn = turn + 2 and can never satisfy
## the expiration test in the same invocation. Repeating the same turn is a
## no-op by construction.
static func process_assault_turn(turn: int) -> Dictionary:
	var dropped: Array = []
	for bid in _assaults.keys():
		if not CampaignBattle.has_battle(str(bid)) \
				or not CampaignBattle.is_active(str(bid)):
			_assaults.erase(bid)
			dropped.append(str(bid))
	var expired_marked: Array = []
	for bid in _assaults:
		var rec: Dictionary = _assaults[bid]
		if not bool(rec.get("expired", false)) and turn > int(rec.get("deadline_turn", -1)):
			rec["expired"] = true
			expired_marked.append(str(bid))
	var created: Array = []
	for base in CampaignBase.get_bases():
		var base_id := str(base.get("id", ""))
		if base_id == "":
			continue
		if int(base.get("state", -1)) != CampaignBase.BaseState.ACTIVE:
			continue
		var controller := str(base.get("controller", "")).strip_edges()
		if controller == "" or controller != FactionSystem.get_player_faction():
			continue
		var node_id := str(base.get("node_id", "")).strip_edges()
		if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
			continue
		if not get_defense_battle_for_base(base_id).is_empty():
			continue
		var attacker_id := _find_hostile_attacker(node_id, controller)
		if attacker_id == "":
			continue
		var started := start_base_attack(base_id, attacker_id)
		var battle_id := str(started.get("battle_id", ""))
		if not bool(started.get("ok", false)) or not CampaignBattle.is_active(battle_id):
			continue
		_assaults[battle_id] = {
			"base_id": base_id,
			"controller": controller,
			"created_turn": turn,
			"deadline_turn": turn + 2,
			"expired": false,
		}
		created.append(battle_id)
	# Auto-resolve pass over expired records (approved outcomes only; see
	# try_auto_resolve_expired). Never touches records created above: they
	# carry expired=false and fail the expiry gate by construction.
	var auto_resolved: Array = []
	var deferred: Array = []
	for bid in _assaults.keys():
		var outcome := try_auto_resolve_expired(str(bid))
		if str(outcome.get("applied", "")) != "":
			auto_resolved.append({"battle_id": str(bid), "outcome": str(outcome.get("applied", ""))})
		elif str(outcome.get("reason", "")) != "not_expired":
			deferred.append({"battle_id": str(bid), "reason": str(outcome.get("reason", ""))})
	created.sort()
	expired_marked.sort()
	dropped.sort()
	return {"created": created, "expired_marked": expired_marked,
		"auto_resolved": auto_resolved, "deferred": deferred,
		"dropped_stale": dropped}


## Attempts the approved automatic outcome for one EXPIRED assault record.
## Returns {applied: outcome} on success, or {reason} when deferred/dropped:
##   not_expired        — deadline not passed (never an outcome).
##   stale              — battle missing or no longer ACTIVE (record dropped).
##   base_gone          — base record missing (record dropped).
##   base_destroyed     — base terminally destroyed (record dropped; the assault
##                        is moot, the battle record itself is kept as history).
##   ownership_changed  — live controller differs from the recorded one
##                        (capture/flip mid-assault makes roles ambiguous).
##   base_not_active    — base DISABLED (SKIP policy: record kept, assault
##                        preserved for tactical/manual handling).
##   multi_or_no_attacker — participants do not yield exactly one live-hostile
##                        attacker (aggregating factions is forbidden).
##   no_verified_defender — no single participant is verifiably the base's
##                        garrison (GARRISON_ONLY: never substitute friendlies,
##                        strongest, sums, or fabrications).
##   awaiting_policy    — expiry with a live but non-ACTIVE attacker (e.g.
##                        DISABLED): no approved outcome rule exists (AUDIT_ONLY),
##                        so the record stays expired and recoverable.
## Only the two approved outcomes mutate anything, and only on the matching
## battle: DEFENDER_SUCCESS (attacker already destroyed) and ATTACKER_SUCCESS
## (single verified ACTIVE attacker left unattended past the deadline, base
## DISABLED with controller preserved). Each applied outcome emits exactly one
## event_triggered notice naming the verified base and battle; deferred or
## skipped assaults emit nothing, so no notice can misreport a defeat.
static func try_auto_resolve_expired(battle_id: String) -> Dictionary:
	var rec := get_assault(battle_id)
	if rec.is_empty():
		return {"reason": "unknown_record"}
	if not bool(rec.get("expired", false)):
		return {"reason": "not_expired"}
	if not CampaignBattle.has_battle(battle_id) or not CampaignBattle.is_active(battle_id):
		_assaults.erase(battle_id)
		return {"reason": "stale"}
	var base_id := str(rec.get("base_id", ""))
	if not CampaignBase.has_base(base_id):
		_assaults.erase(battle_id)
		return {"reason": "base_gone"}
	var base := CampaignBase.get_base(base_id)
	if int(base.get("state", -1)) == CampaignBase.BaseState.DESTROYED:
		_assaults.erase(battle_id)
		return {"reason": "base_destroyed"}
	var live_controller := str(base.get("controller", "")).strip_edges()
	if live_controller == "" or live_controller != str(rec.get("controller", "")):
		return {"reason": "ownership_changed"}
	if int(base.get("state", -1)) != CampaignBase.BaseState.ACTIVE:
		return {"reason": "base_not_active"}
	var battle := CampaignBattle.get_battle(battle_id)
	var hostile: Array = []
	for f in Array(battle.get("participants", [])):
		var fid := str(f)
		if not CampaignForce.has_force(fid):
			continue
		var faction := str(CampaignForce.get_force(fid).get("faction", ""))
		if faction == "" or faction == live_controller:
			continue
		if FactionSystem.get_relation(faction, live_controller) != FactionSystem.Relation.HOSTILE:
			continue
		hostile.append(fid)
	hostile.sort()
	if hostile.size() != 1:
		return {"reason": "multi_or_no_attacker"}
	var attacker_id := str(hostile[0])
	if _find_verified_defender(battle, base_id, live_controller, attacker_id) == "":
		return {"reason": "no_verified_defender"}
	var attacker_state := CampaignForce.get_state(attacker_id)
	if attacker_state == CampaignForce.ForceState.DESTROYED:
		if not CampaignBattle.resolve_battle(battle_id):
			_assaults.erase(battle_id)
			return {"reason": "stale"}
		_assaults.erase(battle_id)
		CampaignBattle.clear_session_ref(battle_id)
		_emit_defense_outcome_notice(base_id, battle_id, true)
		return {"applied": "defender_success"}
	# Approved Option D (B1): one verified ACTIVE attacker left unattended past
	# the deadline wins by default — resolve the battle and DISABLE the base
	# (controller preserved), reusing the approved tactical-defeat semantics.
	# No strength comparison, no garrison-identity formula, no attacker
	# mutation beyond what the lifecycle already requires (none here).
	if attacker_state != CampaignForce.ForceState.ACTIVE:
		return {"reason": "awaiting_policy"}
	# Phase C8-A: when the player keeps a real strategic detachment at the base,
	# the expiry is decided by a strength auto-battle instead of the Option D
	# "attacker wins by default" fallback. No detachment = unchanged behaviour.
	var player_resolution := _try_player_force_resolution(
		battle_id, base_id, str(base.get("node_id", "")), attacker_id, live_controller)
	if not player_resolution.is_empty():
		return player_resolution
	if not CampaignBattle.resolve_battle(battle_id):
		_assaults.erase(battle_id)
		return {"reason": "stale"}
	CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED)
	_assaults.erase(battle_id)
	CampaignBattle.clear_session_ref(battle_id)
	_emit_defense_outcome_notice(base_id, battle_id, false)
	return {"applied": "attacker_success"}


## Returns the id of the player detachment that will fight the auto-battle for
## this base: detachments anchored to the base win over detachments merely
## standing at the same node, and the id-sorted first of the winning class is
## used so resolution is deterministic. "" when the player has no force there.
static func _find_player_garrison(base_id: String, base_node_id: String) -> String:
	if base_node_id == "":
		return ""
	var bound := CampaignPlayerForce.get_active_at_base(base_id)
	for fid in bound:
		if str(CampaignPlayerForce.get_detachment(str(fid)).get("node_id", "")) == base_node_id:
			return str(fid)
	for fid in CampaignPlayerForce.get_active_at_node(base_node_id):
		return str(fid)
	return ""


## Resolves an expired assault by strength comparison between the player's
## detachment and the single verified ACTIVE attacker. Returns {} when the
## player has no force at the base (caller keeps the legacy Option D path),
## otherwise an {applied} receipt. Mutates exactly: player detachment
## casualties, attacker composition/state, battle lifecycle, base state on a
## loss, and the assault record. Never invents a garrison, a role, or a
## second defender.
static func _try_player_force_resolution(battle_id: String, base_id: String,
		base_node_id: String, attacker_id: String, live_controller: String) -> Dictionary:
	var garrison_id := _find_player_garrison(base_id, base_node_id)
	if garrison_id == "":
		return {}
	var garrison := CampaignPlayerForce.get_detachment(garrison_id)
	var defender_strength := maxi(int(garrison.get("strength", 0)), 0)
	if defender_strength <= 0:
		return {}
	var attacker := CampaignForce.get_force(attacker_id)
	var attacker_strength := maxi(int(attacker.get("strength", 0)), 0)
	var attacker_units := maxi(int(attacker.get("unit_count", 0)), 0)

	var start_attacker_strength := maxi(attacker_strength, 1)
	var battle := CampaignAutoBattle.simulate(defender_strength, attacker_strength)
	var rounds := int(battle.get("rounds", 0))
	attacker_strength = int(battle.get("attacker_remaining", 0))
	defender_strength = int(battle.get("defender_remaining", 0))
	var battle_winner := str(battle.get("winner", "stalemate"))
	# A tie after the round cap is a held defence (defender keeps the ground).
	var held := battle_winner == "defender" or battle_winner == "stalemate"
	var attacker_units_lost := CampaignAutoBattle.unit_loss(
		attacker_units, start_attacker_strength, start_attacker_strength - attacker_strength)
	CampaignForce.set_composition(attacker_id, attacker_units - attacker_units_lost, attacker_strength)
	if attacker_strength == 0:
		CampaignForce.set_state(attacker_id, CampaignForce.ForceState.DESTROYED)

	var defender_casualties := CampaignPlayerForce.apply_casualties(
		garrison_id, maxi(int(garrison.get("strength", 0)) - defender_strength, 0))

	if not CampaignBattle.resolve_battle(battle_id):
		return {"reason": "stale"}
	_assaults.erase(battle_id)
	CampaignBattle.clear_session_ref(battle_id)
	if not held:
		CampaignBase.set_state(base_id, CampaignBase.BaseState.DISABLED)
	_emit_defense_outcome_notice(base_id, battle_id, held)
	return {
		"applied": "player_force_defense_held" if held else "player_force_base_lost",
		"battle_id": battle_id,
		"base_id": base_id,
		"garrison_id": garrison_id,
		"attacker_id": attacker_id,
		"attacker_faction": str(attacker.get("faction", "")),
		"controller": live_controller,
		"rounds": rounds,
		"defender_remaining": defender_strength,
		"attacker_remaining": attacker_strength,
		"defender_casualties": defender_casualties,
	}


## Emits one outcome notice for an applied defense resolution, naming the
## verified base and battle (existing event_triggered convention: convoy
## escort announcements, research completions). Emitted only on the tick the
## outcome is applied — the record is cleared in the same block, so repeats
## and save/load cycles cannot re-emit. Never called for deferred/skipped
## assaults, so no notice can misreport an unapplied defeat.
static func _emit_defense_outcome_notice(base_id: String, battle_id: String, defender_held: bool) -> void:
	if defender_held:
		EventBus.event_triggered.emit({
			"name": "BASE DEFENSE HELD",
			"effect": "none",
			"amount": 0,
			"desc": "The assault on %s was broken. Defending forces hold the base." % base_id,
		})
	else:
		EventBus.event_triggered.emit({
			"name": "BASE DEFENSE LOST",
			"effect": "none",
			"amount": 0,
			"desc": "No relief reached %s in time. The base has been disabled, but remains under our control." % base_id,
		})


## Returns the verified garrison for an assault: the single battle participant
## (other than the attacker) that serves the base controller or is attached
## to the base. Identity always comes from the battle record itself — never
## all friendlies at the node, never the strongest, never sums, never
## fabrications. Anything else (none, or ambiguous multiples) yields ""
## (GARRISON_ONLY).
static func _find_verified_defender(battle: Dictionary, base_id: String, controller: String, attacker_id: String) -> String:
	var matches: Array = []
	for f in Array(battle.get("participants", [])):
		var fid := str(f)
		if fid == "" or fid == attacker_id or not CampaignForce.has_force(fid):
			continue
		var force := CampaignForce.get_force(fid)
		if str(force.get("faction", "")) != controller \
				and str(force.get("base_id", "")) != base_id:
			continue
		matches.append(fid)
	matches.sort()
	if matches.size() == 1:
		return str(matches[0])
	return ""


## Returns the first (id-sorted, deterministic) ACTIVE force at the node whose
## faction is HOSTILE to the given controller, or "". Friendly, neutral,
## inactive, and destroyed forces never trigger. Hostility follows the
## existing FactionSystem relation API, not faction inequality.
static func _find_hostile_attacker(node_id: String, controller: String) -> String:
	var candidates: Array = []
	for fid in CampaignForce.get_active_forces_at_node(node_id):
		var fid_str := str(fid)
		var faction := str(CampaignForce.get_force(fid_str).get("faction", ""))
		if faction == "" or faction == controller:
			continue
		if FactionSystem.get_relation(controller, faction) != FactionSystem.Relation.HOSTILE:
			continue
		candidates.append(fid_str)
	candidates.sort()
	if candidates.is_empty():
		return ""
	return str(candidates[0])


## Serializes assault records only (battles/bases/forces persist via their own
## authorities; correlation is battle_id + base_id). SaveGameIO owns the key.
static func serialize_assaults() -> Dictionary:
	var rows := {}
	for bid in _assaults:
		rows[str(bid)] = ((_assaults[bid] as Dictionary).duplicate(true))
	return {"assaults": rows}


## Restores assault records. Malformed rows (non-dict, empty ids, unknown
## base/battle, negative or inverted turns) are skipped without touching any
## other campaign state. Never resolves battles or mutates bases/forces.
static func deserialize_assaults(data: Variant) -> void:
	_assaults.clear()
	if not (data is Dictionary):
		return
	var rows = (data as Dictionary).get("assaults", {})
	if not (rows is Dictionary):
		return
	for bid in (rows as Dictionary):
		var row = (rows as Dictionary)[bid]
		if not (row is Dictionary):
			continue
		var base_id := str((row as Dictionary).get("base_id", ""))
		if str(bid) == "" or base_id == "" or not CampaignBase.has_base(base_id):
			continue
		if not CampaignBattle.has_battle(str(bid)):
			continue
		var created := int((row as Dictionary).get("created_turn", -1))
		var deadline := int((row as Dictionary).get("deadline_turn", -1))
		if created < 0 or deadline < 0 or deadline < created:
			continue
		# Pre-controller rows (Phase 2A saves) migrate to the live base
		# controller; an explicitly stored empty controller is malformed.
		var controller := str((row as Dictionary).get("controller", ""))
		if controller == "":
			if (row as Dictionary).has("controller"):
				continue
			controller = str(CampaignBase.get_base(base_id).get("controller", ""))
			if controller == "":
				continue
		_assaults[str(bid)] = {
			"base_id": base_id,
			"controller": controller,
			"created_turn": created,
			"deadline_turn": deadline,
			"expired": bool((row as Dictionary).get("expired", false)),
		}
