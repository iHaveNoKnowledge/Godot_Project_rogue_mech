class_name CampaignAttackBridge
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN ATTACK BRIDGE — Phase 2H-B Gate 2 routing + Gate 3A entry wiring.
##
## Correlates one player-driven attack engagement with its tactical result.
## Uses exactly one pending slot: battle_id -> {battle_id, node_id, session,
## targets}. There is deliberately NO reward payout and NO battle-record
## schema change.
##
## Production entry wiring (Gate 3A): CampaignAttackAction.handle_attack
## records the engagement, connects the result hook, and enters tactical
## combat as "grunt" — but only while no defense engagement is live (entry
## mutual exclusion; the defense mirror lives in CampaignBaseDefense).
## Observed result signals: EventBus.combat_ended(victory: bool) and
## EventBus.combat_escaped().
##
## Encounter-identity limitation (read this before trusting a result): the
## combat signals carry NO unique encounter id — a bare boolean cannot name
## its combat. This bridge therefore does NOT provide perfect encounter
## identity. Binding is closed operationally instead: at most one pending
## slot exists; every combat exit either consumes validated pending
## (combat_ended) or clears it (combat_escaped, plus the signal-less exit
## funnels in GameManager.return_to_board/game_over, which drop only this
## slot); entry always re-records; tactical scenes are exclusive; stale slots
## (battle missing or no longer ACTIVE) are evicted, never applied. A pending
## slot is therefore bound to the running combat by construction. This also
## fixes the cross-talk shape the older defense applier tolerates (kept
## pending across retreat): the attack bridge clears on escape so a later
## unrelated combat can never consume an old attack session. Malformed or
## stale results never consume a valid pending session: validation runs fully
## BEFORE any clearing. Residual risk: only a strand that bypasses every
## exit funnel could leave a live slot behind a new combat — abandon paths
## are covered at the funnels, so any remaining shape fails closed (entry
## blocked) rather than misattributed.
##
## Target rule (matches the attack handler predicate exactly): faction
## inequality vs the player faction at resolution time. Inequality is NOT a
## hostility claim. Each target is revalidated (exists, still non-player
## faction, not already DESTROYED) and invalid individuals are skipped.
## ---------------------------------------------------------------------------

## Prefix marking a battle record as carrying a player attack intervention.
const ATTACK_SESSION_PREFIX := "session_attack_"

## Pending engagement keyed by battle id (at most one entry is ever stored).
static var _pending_attack: Dictionary = {}
static var _attack_result_hook_connected: bool = false


## Clears the pending slot and hook flag. Battles, forces, and sessions in
## the registry are untouched. Used by tests; production recovery after
## save/load needs nothing (pending is memory-only by design: a reloaded run
## has no running tactical scene, so any combat_ended after load belongs to a
## combat entered post-load, which re-records first).
static func reset_attack_state() -> void:
	_pending_attack.clear()
	_attack_result_hook_connected = false


## Returns the pending attack battle id, or "" when nothing is tracked.
static func get_pending_attack_battle_id() -> String:
	for bid in _pending_attack:
		return str(bid)
	return ""


## Records one validated attack engagement. A conflicting pending session for
## a DIFFERENT battle is rejected (never silently overwritten); re-recording
## the same battle refreshes it. Stale slots (battle missing or no longer
## ACTIVE) are evicted first so dead state can never block a fresh entry.
## False otherwise, leaving any live pending session untouched.
static func record_attack_engagement(battle_id: String, targets: Array) -> bool:
	if battle_id == "" or not CampaignBattle.has_battle(battle_id):
		return false
	if not CampaignBattle.is_active(battle_id):
		return false
	for old_bid in _pending_attack.keys():
		if str(old_bid) == battle_id:
			continue
		if CampaignBattle.has_battle(str(old_bid)) \
				and CampaignBattle.is_active(str(old_bid)):
			return false
		_pending_attack.erase(old_bid)
	var clean: Array = []
	for f in targets:
		var fid := str(f)
		if fid == "" or not CampaignForce.has_force(fid):
			return false
		if clean.has(fid):
			return false
		clean.append(fid)
	if clean.is_empty():
		return false
	clean.sort()
	var battle := CampaignBattle.get_battle(battle_id)
	var session := ATTACK_SESSION_PREFIX + battle_id
	CampaignBattle.set_session_ref(battle_id, session)
	_pending_attack[battle_id] = {
		"battle_id": battle_id,
		"node_id": str(battle.get("node_id", "")),
		"session": session,
		"targets": clean,
	}
	return true


## Validates the pending slot against live records WITHOUT clearing it.
## Returns the engagement context, or {} when invalid. A failed validation
## never destroys a valid pending session.
static func peek_validated_attack(battle_id: String) -> Dictionary:
	var ctx: Dictionary = (_pending_attack.get(battle_id, {}) as Dictionary).duplicate(true)
	if ctx.is_empty():
		return {}
	if not CampaignBattle.has_battle(battle_id) or not CampaignBattle.is_active(battle_id):
		return {}
	var battle := CampaignBattle.get_battle(battle_id)
	if str(battle.get("session_ref", "")) != str(ctx.get("session", "")):
		return {}
	if str(battle.get("node_id", "")) != str(ctx.get("node_id", "")):
		return {}
	ctx["battle_id"] = battle_id
	return ctx


## Consumes a validated pending engagement (clears the slot). Returns {} when
## invalid, leaving a valid pending session untouched.
static func consume_validated_attack(battle_id: String) -> Dictionary:
	var ctx := peek_validated_attack(battle_id)
	if ctx.is_empty():
		return {}
	_pending_attack.erase(battle_id)
	return ctx


## Clears one pending slot without validation. Used by the escape path only.
static func clear_attack_pending(battle_id: String) -> void:
	_pending_attack.erase(battle_id)


## Subscribes the result applier to the existing tactical result flow.
## Idempotent; safe to call on every attack entry.
static func ensure_attack_result_hook() -> void:
	if _attack_result_hook_connected:
		return
	var ended_hook := Callable(CampaignAttackBridge, "_on_attack_combat_ended")
	if not EventBus.combat_ended.is_connected(ended_hook):
		EventBus.combat_ended.connect(ended_hook)
	var escaped_hook := Callable(CampaignAttackBridge, "_on_attack_combat_escaped")
	if not EventBus.combat_escaped.is_connected(escaped_hook):
		EventBus.combat_escaped.connect(escaped_hook)
	_attack_result_hook_connected = true


## Revalidates one recorded target at resolution time against the
## authoritative force registry: must exist, still be non-player-faction
## (inequality predicate preserved, not hostility), and not already
## DESTROYED. Never fabricates.
static func _is_verified_target(fid: String, player_faction: String) -> bool:
	if fid == "" or not CampaignForce.has_force(fid):
		return false
	var faction := str(CampaignForce.get_force(fid).get("faction", ""))
	if faction == "" or faction == player_faction:
		return false
	if CampaignForce.get_state(fid) == CampaignForce.ForceState.DESTROYED:
		return false
	return true


## Applier for the existing tactical result flow. Victory destroys only
## revalidated targets and resolves the matching battle; defeat leaves the
## battle ACTIVE with no mutations; invalid, duplicate, or stale results are
## ignored without consuming a valid pending session.
static func _on_attack_combat_ended(victory: bool) -> void:
	var battle_id := get_pending_attack_battle_id()
	if battle_id == "":
		return
	var ctx := peek_validated_attack(battle_id)
	if ctx.is_empty():
		return
	if not victory:
		_pending_attack.erase(battle_id)
		return
	var player_faction := FactionSystem.get_player_faction()
	var destroyed_any := false
	for fid in Array(ctx.get("targets", [])):
		var target_id := str(fid)
		if not _is_verified_target(target_id, player_faction):
			continue
		if CampaignForce.get_state(target_id) != CampaignForce.ForceState.DESTROYED:
			CampaignForce.set_state(target_id, CampaignForce.ForceState.DESTROYED)
			destroyed_any = true
	if not destroyed_any:
		return
	if not CampaignBattle.resolve_battle(battle_id):
		_pending_attack.erase(battle_id)
		return
	_pending_attack.erase(battle_id)
	CampaignBattle.clear_session_ref(battle_id)


## Escape ends the engagement binding without any campaign mutation: the
## battle stays ACTIVE (retry allowed) and a later unrelated combat can never
## consume this session.
static func _on_attack_combat_escaped() -> void:
	var battle_id := get_pending_attack_battle_id()
	if battle_id == "":
		return
	_pending_attack.erase(battle_id)
