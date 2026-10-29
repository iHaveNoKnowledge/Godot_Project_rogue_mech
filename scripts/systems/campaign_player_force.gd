class_name CampaignPlayerForce
extends RefCounted

## ---------------------------------------------------------------------------
## PLAYER STRATEGIC FORCE — Phase C8-A (Campaign V2, "give the player an army").
##
## Authoritative store for the PLAYER's own strategic detachments (garrisons /
## expeditionary groups). Audit evidence (do not re-decide lightly):
##   - `CampaignForce` is an NPC operational entity; its header and the 5A/5L
##     boundary suites explicitly forbid repurposing it for player units
##     ("Player presence ... is NOT modeled as a Force in 5A. No player force is
##     faked for symmetry."). This is a SEPARATE authority, not a second copy.
##   - `CampaignBaseDefense.start_base_attack()` fabricates a placeholder
##     garrison force (`force_garrison_<node>`, strength 10) only so the battle
##     has a second participant. That placeholder is not the player's army.
##   - Consequence found in this phase: with no real player force, an expired
##     base assault falls through to Option D "attacker wins by default", so the
##     player could never win a strategic defence without tactical play. This
##     authority is the missing input to a real strength comparison.
##
## Model: {id, node_id, base_id, unit_count, strength, state}.
##   - Ownership is implicit: every record belongs to the player. No faction
##     field, because a faction field would duplicate `FactionSystem`.
##   - References only (node/base by id); nothing is copied from those owners.
##   - States: ACTIVE / DISABLED. There is no DESTROYED: once a detachment loses
##     all strength it becomes DISABLED and can be re-strengthened (spec §11:
##     losing assets is a setback, not run death — Pilot = Run).
##
## Boundaries:
##   - Never mutates CampaignForce, CampaignBase, CampaignBattle, territory,
##     supply, currency, or turn state. Defence resolution reads this store and
##     applies casualties through `apply_casualties()` only.
##   - No turn phase of its own. Nothing here advances time or heals for free.
##   - Static registry pattern (CampaignForce / CampaignBase / CampaignSupply):
##     reset() + serialize()/deserialize() are the only persistence surface.
## ---------------------------------------------------------------------------

enum ForceState { ACTIVE = 0, DISABLED = 1 }

const STATE_NAMES := {
	ForceState.ACTIVE: "active",
	ForceState.DISABLED: "disabled",
}

## Provisional starting garrison seeded by RunStartSystem (balance value, not a
## locked formula — spec §44 keeps exact force numbers PROPOSED).
const START_GARRISON_ID := "player_force_home_garrison"
const START_GARRISON_UNITS := 1
const START_GARRISON_STRENGTH := 10

static var _detachments: Dictionary = {}


static func state_to_name(state: int) -> String:
	return str(STATE_NAMES.get(state, "disabled"))


static func state_from_name(raw_name: String) -> int:
	for key in STATE_NAMES:
		if str(STATE_NAMES[key]) == raw_name:
			return int(key)
	return -1


static func make_detachment_id(slug: String) -> String:
	var clean := ""
	for ch in slug.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
		elif ch == "_" or ch == "-" or ch == " ":
			clean += "_"
	if clean == "":
		return ""
	return "player_force_" + clean


static func has_detachment(force_id: String) -> bool:
	return _detachments.has(force_id)


static func get_detachment(force_id: String) -> Dictionary:
	if not _detachments.has(force_id):
		return {}
	return (_detachments[force_id] as Dictionary).duplicate(true)


static func get_detachments() -> Array:
	var ids := _detachments.keys()
	ids.sort()
	var out: Array = []
	for fid in ids:
		out.append((_detachments[fid] as Dictionary).duplicate(true))
	return out


static func get_state(force_id: String) -> int:
	if not _detachments.has(force_id):
		return ForceState.DISABLED
	return int((_detachments[force_id] as Dictionary).get("state", ForceState.DISABLED))


static func is_active(force_id: String) -> bool:
	return get_state(force_id) == ForceState.ACTIVE


## Active detachments currently at a node (id-sorted, deterministic).
static func get_active_at_node(node_id: String) -> Array:
	var out: Array = []
	if node_id == "":
		return out
	for fid in _detachments:
		var d: Dictionary = _detachments[fid]
		if int(d.get("state", ForceState.DISABLED)) != ForceState.ACTIVE:
			continue
		if str(d.get("node_id", "")) != node_id:
			continue
		out.append(str(fid))
	out.sort()
	return out


## Active detachments assigned to a base (id-sorted, deterministic).
static func get_active_at_base(base_id: String) -> Array:
	var out: Array = []
	if base_id == "":
		return out
	for fid in _detachments:
		var d: Dictionary = _detachments[fid]
		if int(d.get("state", ForceState.DISABLED)) != ForceState.ACTIVE:
			continue
		if str(d.get("base_id", "")) != base_id:
			continue
		out.append(str(fid))
	out.sort()
	return out


## Total active strength across every detachment (read-only roll-up).
static func get_total_strength() -> int:
	var total := 0
	for fid in _detachments:
		var d: Dictionary = _detachments[fid]
		if int(d.get("state", ForceState.DISABLED)) != ForceState.ACTIVE:
			continue
		total += maxi(int(d.get("strength", 0)), 0)
	return total


## Explicit registration. Returns id or "" when rejected: empty/duplicate id,
## unknown node ("" allowed for an unplaced detachment), unknown base, or
## negative composition. Identical re-registration is idempotent.
static func register_detachment(force_id: String, node_id: String, base_id: String,
		unit_count: int, strength: int) -> String:
	if force_id == "":
		return ""
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return ""
	if base_id != "" and not CampaignBase.has_base(base_id):
		return ""
	if unit_count < 0 or strength < 0:
		return ""
	if _detachments.has(force_id):
		var e: Dictionary = _detachments[force_id]
		if str(e.get("node_id", "")) == node_id \
				and str(e.get("base_id", "")) == base_id \
				and int(e.get("unit_count", -1)) == unit_count \
				and int(e.get("strength", -1)) == strength:
			return force_id
		return ""
	_detachments[force_id] = {
		"id": force_id,
		"node_id": node_id,
		"base_id": base_id,
		"unit_count": unit_count,
		"strength": strength,
		"state": ForceState.ACTIVE if strength > 0 else ForceState.DISABLED,
	}
	return force_id


## Removes one record (disband/rollback). False on unknown id.
static func remove_detachment(force_id: String) -> bool:
	if not _detachments.has(force_id):
		return false
	_detachments.erase(force_id)
	return true


static func set_state(force_id: String, new_state: int) -> bool:
	if not _detachments.has(force_id):
		return false
	if not STATE_NAMES.has(new_state):
		return false
	(_detachments[force_id] as Dictionary)["state"] = new_state
	return true


static func set_node(force_id: String, node_id: String) -> bool:
	if not _detachments.has(force_id):
		return false
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return false
	(_detachments[force_id] as Dictionary)["node_id"] = node_id
	return true


static func set_base(force_id: String, base_id: String) -> bool:
	if not _detachments.has(force_id):
		return false
	if base_id != "" and not CampaignBase.has_base(base_id):
		return false
	(_detachments[force_id] as Dictionary)["base_id"] = base_id
	return true


## Sets strength directly (clamped at 0). Reaching 0 disables the detachment
## and zeroes its units; raising it above 0 reactivates it.
static func set_strength(force_id: String, strength: int) -> bool:
	if not _detachments.has(force_id):
		return false
	var d: Dictionary = _detachments[force_id]
	var clamped := maxi(strength, 0)
	d["strength"] = clamped
	if clamped == 0:
		d["unit_count"] = 0
		d["state"] = ForceState.DISABLED
	elif int(d.get("state", ForceState.DISABLED)) == ForceState.DISABLED:
		d["state"] = ForceState.ACTIVE
	return true


## Applies auto-battle casualties to one detachment: strength first, then a
## proportional unit loss (floor, never fabricating survivors). Returns a
## receipt; a wiped-out detachment ends DISABLED with 0 units.
static func apply_casualties(force_id: String, strength_loss: int) -> Dictionary:
	if not _detachments.has(force_id):
		return {"ok": false, "reason": "unknown_detachment", "force_id": force_id}
	var d: Dictionary = _detachments[force_id]
	var before_strength := int(d.get("strength", 0))
	var before_units := int(d.get("unit_count", 0))
	var loss := clampi(strength_loss, 0, before_strength)
	if loss <= 0:
		return {
			"ok": true,
			"reason": "no_casualties",
			"force_id": force_id,
			"strength_before": before_strength,
			"strength_after": before_strength,
			"units_lost": 0,
			"state": state_to_name(int(d.get("state", ForceState.DISABLED))),
		}
	var after_strength := before_strength - loss
	var units_lost := 0
	if after_strength == 0:
		units_lost = before_units
	else:
		units_lost = int(floor(float(before_units) * float(loss) / float(before_strength)))
		units_lost = clampi(units_lost, 0, before_units)
	d["strength"] = after_strength
	d["unit_count"] = before_units - units_lost
	if after_strength == 0:
		d["state"] = ForceState.DISABLED
	return {
		"ok": true,
		"reason": "casualties_applied",
		"force_id": force_id,
		"strength_before": before_strength,
		"strength_after": after_strength,
		"units_lost": units_lost,
		"units_after": int(d.get("unit_count", 0)),
		"state": state_to_name(int(d.get("state", ForceState.DISABLED))),
	}


## Structural health check. Empty array = healthy.
static func validate() -> Array:
	var problems: Array = []
	for fid in _detachments:
		var d: Dictionary = _detachments[fid]
		var node_id := str(d.get("node_id", ""))
		var base_id := str(d.get("base_id", ""))
		if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
			problems.append("detachment %s references unknown node %s" % [fid, node_id])
		if base_id != "" and not CampaignBase.has_base(base_id):
			problems.append("detachment %s references unknown base %s" % [fid, base_id])
		if int(d.get("strength", -1)) < 0 or int(d.get("unit_count", -1)) < 0:
			problems.append("detachment %s has negative composition" % fid)
		if not STATE_NAMES.has(int(d.get("state", -1))):
			problems.append("detachment %s has unknown state" % fid)
	return problems


static func serialize() -> Dictionary:
	var rows: Array = []
	for d in get_detachments():
		rows.append({
			"id": str(d.get("id", "")),
			"node_id": str(d.get("node_id", "")),
			"base_id": str(d.get("base_id", "")),
			"unit_count": int(d.get("unit_count", 0)),
			"strength": int(d.get("strength", 0)),
			"state": state_to_name(int(d.get("state", ForceState.DISABLED))),
		})
	return {"detachments": rows}


## Restores records. Rows with empty/colliding ids, unknown states, negative
## composition, or dangling node/base refs are skipped (never partially loaded).
static func deserialize(data: Variant) -> void:
	reset()
	if not (data is Dictionary):
		return
	var rows = (data as Dictionary).get("detachments", [])
	if not (rows is Array):
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var fid := str((row as Dictionary).get("id", "")).strip_edges()
		if fid == "" or _detachments.has(fid):
			continue
		var state := state_from_name(str((row as Dictionary).get("state", "")))
		if state == -1:
			continue
		var node_id := str((row as Dictionary).get("node_id", ""))
		var base_id := str((row as Dictionary).get("base_id", ""))
		if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
			continue
		if base_id != "" and not CampaignBase.has_base(base_id):
			continue
		var units := int((row as Dictionary).get("unit_count", 0))
		var strength := int((row as Dictionary).get("strength", 0))
		if units < 0 or strength < 0:
			continue
		_detachments[fid] = {
			"id": fid,
			"node_id": node_id,
			"base_id": base_id,
			"unit_count": units,
			"strength": strength,
			"state": state,
		}


static func reset() -> void:
	_detachments.clear()
