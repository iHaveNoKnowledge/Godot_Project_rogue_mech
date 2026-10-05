class_name CampaignBattle
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN BATTLE — Phase 5B (boundary foundation, NOT battle resolution).
##
## Audit evidence (do not re-decide lightly):
##   - There is NO CombatSession class. Tactical combat = game_world scene
##     lifetime + GameManager.combat_node_type + EventBus.combat_ended +
##     SpawnManager spawning + rewards UI. "CombatSession" here means that
##     tactical execution instance — and the battle NEVER depends on it.
##   - Board->combat flows through board_patrol_engagement + combat_node_type
##     (patrols have no Forces per 5A; player has no Force) — so 5B builds NO
##     board bridge and NO fake forces. Patrol engagements stay legacy combat.
##   - Combat targeting is binary (enemy/ally/friendly/player groups); the
##     battle participant LIST can still hold 2+ force ids (campaign layer is
##     future-multi-side-ready) without migrating tactical combat.
##
## Model: {id, state, node_id, participants: [force ids], session_ref}.
##   Battle != Force (encounter vs entity; force data never copied here).
##   Battle != CombatSession (campaign identity vs tactical execution).
##   session_ref is an OPAQUE string set by whoever runs tactics; it is never
##   the battle identity, never validated against combat, and the battle
##   survives it being cleared. Design test: replacing CombatSession tomorrow
##   changes nothing here — answer MUST stay YES.
## States: PLANNED -> ACTIVE -> RESOLVED, plus -> CANCELLED from PLANNED or
##   ACTIVE. Terminal states never reactivate. No result/outcome field (whose
##   victory presupposes roles the campaign flow does not have yet — outcome
##   attribution belongs to the future resolution phase, not 5B).
## No roles (no ATTACKER/DEFENDER — no 5B flow needs them), no casualty or
## strength mutation (firewalled to resolution), no signals (no consumer).
## ---------------------------------------------------------------------------

enum BattleState { PLANNED = 0, ACTIVE = 1, RESOLVED = 2, CANCELLED = 3 }

const STATE_NAMES := {
	BattleState.PLANNED: "planned",
	BattleState.ACTIVE: "active",
	BattleState.RESOLVED: "resolved",
	BattleState.CANCELLED: "cancelled",
}

static var _battles: Dictionary = {}


static func state_to_name(state: int) -> String:
	return str(STATE_NAMES.get(state, "cancelled"))


static func state_from_name(raw_name: String) -> int:
	for key in STATE_NAMES:
		if str(STATE_NAMES[key]) == raw_name:
			return int(key)
	return -1


static func make_battle_id(sector: int, slug: String) -> String:
	var clean := ""
	for ch in slug.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
		elif ch == "_" or ch == "-" or ch == " ":
			clean += "_"
	if clean == "":
		return ""
	return "battle_s%d_%s" % [sector, clean]


static func has_battle(battle_id: String) -> bool:
	return _battles.has(battle_id)


static func get_battle(battle_id: String) -> Dictionary:
	if not _battles.has(battle_id):
		return {}
	return (_battles[battle_id] as Dictionary).duplicate(true)


static func get_battles() -> Array:
	var ids := _battles.keys()
	ids.sort()
	var out: Array = []
	for bid in ids:
		out.append((_battles[bid] as Dictionary).duplicate(true))
	return out


static func get_participants(battle_id: String) -> Array:
	if not _battles.has(battle_id):
		return []
	return Array((_battles[battle_id] as Dictionary).get("participants", [])).duplicate()


## Explicit registration. Returns id or "" when rejected: empty id, unknown
## node, zero participants, unknown/destroyed/duplicate force, or id
## collision with a different definition. Identical re-register idempotent.
## Initial state is always PLANNED; session_ref "" initially.
static func register_battle(battle_id: String, node_id: String, participants: Array) -> String:
	if battle_id == "":
		return ""
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return ""
	if node_id == "":
		return ""
	var clean_parts := _validate_participants(participants)
	if clean_parts.is_empty():
		return ""
	if _battles.has(battle_id):
		var e: Dictionary = _battles[battle_id]
		if str(e.get("node_id", "")) == node_id and _same_id_set(e.get("participants", []), clean_parts):
			return battle_id
		return ""
	_battles[battle_id] = {
		"id": battle_id,
		"state": BattleState.PLANNED,
		"node_id": node_id,
		"participants": clean_parts,
		"session_ref": "",
	}
	return battle_id


## Adds one force (validated, deduped). False on unknown battle/force,
## destroyed force, or duplicate.
static func add_participant(battle_id: String, force_id: String) -> bool:
	if not _battles.has(battle_id):
		return false
	if force_id == "" or not CampaignForce.has_force(force_id):
		return false
	if CampaignForce.get_state(force_id) == CampaignForce.ForceState.DESTROYED:
		return false
	var parts: Array = (_battles[battle_id] as Dictionary)["participants"]
	if parts.has(force_id):
		return false
	parts.append(force_id)
	parts.sort()
	return true


## Removes one force. Allowed to reach zero (validate() flags an ACTIVE
## battle with no participants); resolution semantics belong to the future.
static func remove_participant(battle_id: String, force_id: String) -> bool:
	if not _battles.has(battle_id):
		return false
	var parts: Array = (_battles[battle_id] as Dictionary)["participants"]
	if not parts.has(force_id):
		return false
	parts.erase(force_id)
	return true


## PLANNED -> ACTIVE. False on unknown id or wrong state.
static func begin_battle(battle_id: String) -> bool:
	if not _battles.has(battle_id):
		return false
	if int((_battles[battle_id] as Dictionary).get("state", -1)) != BattleState.PLANNED:
		return false
	(_battles[battle_id] as Dictionary)["state"] = BattleState.ACTIVE
	return true


## ACTIVE -> RESOLVED. A planned battle must pass through ACTIVE first.
## False on unknown id or wrong state. No outcome recorded (deferred).
static func resolve_battle(battle_id: String) -> bool:
	if not _battles.has(battle_id):
		return false
	if int((_battles[battle_id] as Dictionary).get("state", -1)) != BattleState.ACTIVE:
		return false
	(_battles[battle_id] as Dictionary)["state"] = BattleState.RESOLVED
	return true


## PLANNED/ACTIVE -> CANCELLED. Terminal. False on unknown id or wrong state.
static func cancel_battle(battle_id: String) -> bool:
	if not _battles.has(battle_id):
		return false
	var cur := int((_battles[battle_id] as Dictionary).get("state", -1))
	if cur != BattleState.PLANNED and cur != BattleState.ACTIVE:
		return false
	(_battles[battle_id] as Dictionary)["state"] = BattleState.CANCELLED
	return true


## Attaches an opaque tactical session reference (any non-empty string).
## Never validated against combat — there is no session authority to check.
static func set_session_ref(battle_id: String, session_ref: String) -> bool:
	if not _battles.has(battle_id):
		return false
	if session_ref == "":
		return false
	(_battles[battle_id] as Dictionary)["session_ref"] = session_ref
	return true


## Clears the session reference (tactical session ended). The battle record
## is untouched and stays resolvable — this is the boundary guarantee.
static func clear_session_ref(battle_id: String) -> bool:
	if not _battles.has(battle_id):
		return false
	(_battles[battle_id] as Dictionary)["session_ref"] = ""
	return true


static func get_session_ref(battle_id: String) -> String:
	if not _battles.has(battle_id):
		return ""
	return str((_battles[battle_id] as Dictionary).get("session_ref", ""))


static func get_state(battle_id: String) -> int:
	if not _battles.has(battle_id):
		return BattleState.CANCELLED
	return int((_battles[battle_id] as Dictionary).get("state", BattleState.CANCELLED))


static func is_planned(battle_id: String) -> bool:
	return get_state(battle_id) == BattleState.PLANNED


static func is_active(battle_id: String) -> bool:
	return get_state(battle_id) == BattleState.ACTIVE


## Derived territory context through the battle node (never stored).
static func get_territory_context(battle_id: String) -> String:
	if not _battles.has(battle_id):
		return ""
	var node_id := str((_battles[battle_id] as Dictionary).get("node_id", ""))
	if node_id == "":
		return ""
	var covering := CampaignTerritory.get_territories_for_node(node_id)
	if covering.is_empty():
		return ""
	return str(covering[0].get("id", ""))


## Structural health check. Returns violation strings (empty = healthy).
static func validate() -> Array:
	var problems: Array = []
	for bid in _battles:
		var b: Dictionary = _battles[bid]
		var state := int(b.get("state", -1))
		if not STATE_NAMES.has(state):
			problems.append("battle %s has unknown state" % bid)
		var node_id := str(b.get("node_id", ""))
		if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
			problems.append("battle %s references unknown node %s" % [bid, node_id])
		var parts: Array = b.get("participants", [])
		var seen := {}
		for f in parts:
			var fid := str(f)
			if seen.has(fid):
				problems.append("battle %s lists duplicate force %s" % [bid, fid])
			seen[fid] = true
			if not CampaignForce.has_force(fid):
				problems.append("battle %s references unknown force %s" % [bid, fid])
		if (state == BattleState.PLANNED or state == BattleState.ACTIVE) and parts.is_empty():
			problems.append("battle %s is live with no participants" % bid)
	return problems


## Mutable state only: sorted battle records with stable string values.
## Force/node data referenced by id, never duplicated. session_ref is an
## opaque string, never a runtime object.
static func serialize() -> Dictionary:
	var out: Array = []
	for b in get_battles():
		out.append({
			"id": str(b.get("id", "")),
			"state": state_to_name(int(b.get("state", BattleState.CANCELLED))),
			"node_id": str(b.get("node_id", "")),
			"participants": Array(b.get("participants", [])).duplicate(),
			"session_ref": str(b.get("session_ref", "")),
		})
	return {"battles": out}


## Restores records. Rows with empty/colliding ids, unknown states/nodes, or
## empty/invalid participant sets are skipped; dangling force refs are KEPT
## and flagged by validate() (forces may legitimately load later).
static func deserialize(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var rows = data.get("battles", [])
	if not (rows is Array):
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var bid := str(row.get("id", ""))
		if bid == "" or _battles.has(bid):
			continue
		var state := state_from_name(str(row.get("state", "")))
		if state == -1:
			continue
		var node_id := str(row.get("node_id", ""))
		if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
			continue
		var parts: Array = []
		var raw_parts = row.get("participants", [])
		if raw_parts is Array:
			for f in raw_parts:
				var fid := str(f)
				if fid != "" and not parts.has(fid):
					parts.append(fid)
		if parts.is_empty():
			continue
		parts.sort()
		_battles[bid] = {
			"id": bid,
			"state": state,
			"node_id": node_id,
			"participants": parts,
			"session_ref": str(row.get("session_ref", "")),
		}


static func clear() -> void:
	_battles.clear()


static func _validate_participants(participants: Array) -> Array:
	var clean: Array = []
	for f in participants:
		var fid := str(f)
		if fid == "" or not CampaignForce.has_force(fid):
			return []
		if CampaignForce.get_state(fid) == CampaignForce.ForceState.DESTROYED:
			return []
		if clean.has(fid):
			return []
		clean.append(fid)
	if clean.is_empty():
		return []
	clean.sort()
	return clean


static func _same_id_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for item in a:
		if not b.has(item):
			return false
	return true
