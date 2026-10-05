class_name CampaignForce
extends RefCounted

## ---------------------------------------------------------------------------
## FORCE ENTITY — Phase 5A (Campaign V2 foundation, NOT a battle system).
##
## Audit evidence (do not re-decide lightly):
##   - Patrols (BoardState.board_patrols, PatrolSystem) are the live enemy
##     presence: sector-local int ids, encounter-stance labels
##     (hostile/unknown/scavenger — NOT FactionSystem ids), RNG movement,
##     merge/split/QRF churn, combat removal. Mirroring them here with zero
##     consumers would create two diverging mutable truths. PATROL REMAINS
##     SEPARATE in 5A (force_type PATROL is reserved for the future bridge).
##   - Player presence (hangar roster + active mech + board token + traversal
##     modes, protected 2E/2F authority) is NOT modeled as a Force in 5A.
##     No player force is faked for symmetry.
##   - Fleet roster allies, spawn groups, and combat enemy lists are
##     combat/board-owned; never duplicated here.
##   - CombatSession stays the tactical execution context; forces never enter
##     combat code in 5A and combat never writes force state.
##
## Model: {id, force_type, state, faction, node_id, base_id, unit_count,
##   strength}. References only (node/base/faction by id); territory context
##   derives through existing topology, never stored.
## Types (minimal, audit-backed): PATROL, CONVOY, SCAVENGER, RIVAL.
##   (GARRISON/EXPEDITION have no existing data yet — deferred, documented.)
## States: ACTIVE / DISABLED / DESTROYED. Same triple as Base by deliberate
##   choice (operational -> impaired -> gone fits forces too), with its own
##   graph below — NOT shared code, NOT shared semantics.
## Composition: abstract unit_count + strength ints (authoritative-held;
##   nothing derives them yet — rosters stay board/combat-owned, combat
##   strength stays tactical). No logistics/morale/ranks (Phase 6+/future).
## ---------------------------------------------------------------------------

enum ForceState { ACTIVE = 0, DISABLED = 1, DESTROYED = 2 }

const STATE_NAMES := {
	ForceState.ACTIVE: "active",
	ForceState.DISABLED: "disabled",
	ForceState.DESTROYED: "destroyed",
}

const FORCE_TYPES := ["PATROL", "CONVOY", "SCAVENGER", "RIVAL"]

static var _forces: Dictionary = {}


static func state_to_name(state: int) -> String:
	return str(STATE_NAMES.get(state, "destroyed"))


static func state_from_name(raw_name: String) -> int:
	for key in STATE_NAMES:
		if str(STATE_NAMES[key]) == raw_name:
			return int(key)
	return -1


static func is_valid_type(force_type: String) -> bool:
	return FORCE_TYPES.has(force_type)


static func make_force_id(sector: int, slug: String) -> String:
	var clean := ""
	for ch in slug.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
		elif ch == "_" or ch == "-" or ch == " ":
			clean += "_"
	if clean == "":
		return ""
	return "force_s%d_%s" % [sector, clean]


static func has_force(force_id: String) -> bool:
	return _forces.has(force_id)


static func get_force(force_id: String) -> Dictionary:
	if not _forces.has(force_id):
		return {}
	return (_forces[force_id] as Dictionary).duplicate(true)


static func get_forces() -> Array:
	var ids := _forces.keys()
	ids.sort()
	var out: Array = []
	for fid in ids:
		out.append((_forces[fid] as Dictionary).duplicate(true))
	return out


static func get_forces_of_type(force_type: String) -> Array:
	var out: Array = []
	for f in get_forces():
		if str(f.get("force_type", "")) == force_type:
			out.append(f)
	return out


## Explicit registration. Returns id or "" when rejected: empty id, unknown
## type, unregistered faction ("" allowed = unattributed, same deferral as
## Base controller), unknown node/base refs, negative composition, or id
## collision with a different definition. Identical re-register idempotent.
static func register_force(force_id: String, force_type: String, faction_id: String = "",
		node_id: String = "", base_id: String = "", unit_count: int = 0,
		strength: int = 0) -> String:
	if force_id == "":
		return ""
	if not is_valid_type(force_type):
		return ""
	if faction_id != "" and not FactionSystem.has_faction(faction_id):
		return ""
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return ""
	if base_id != "" and not CampaignBase.has_base(base_id):
		return ""
	if unit_count < 0 or strength < 0:
		return ""
	if _forces.has(force_id):
		var e: Dictionary = _forces[force_id]
		if str(e.get("force_type", "")) == force_type \
				and str(e.get("faction", "")) == faction_id \
				and str(e.get("node_id", "")) == node_id \
				and str(e.get("base_id", "")) == base_id \
				and int(e.get("unit_count", -1)) == unit_count \
				and int(e.get("strength", -1)) == strength:
			return force_id
		return ""
	_forces[force_id] = {
		"id": force_id,
		"force_type": force_type,
		"state": ForceState.ACTIVE,
		"faction": faction_id,
		"node_id": node_id,
		"base_id": base_id,
		"unit_count": unit_count,
		"strength": strength,
	}
	return force_id


## Explicit state transition (graph-enforced). Legal: ACTIVE->{DISABLED,
## DESTROYED}, DISABLED->{ACTIVE,DESTROYED}. DESTROYED terminal. Same-state
## writes accepted. False on unknown id/state or illegal edge.
static func set_state(force_id: String, new_state: int) -> bool:
	if not _forces.has(force_id):
		return false
	if not STATE_NAMES.has(new_state):
		return false
	var cur := int((_forces[force_id] as Dictionary).get("state", ForceState.DESTROYED))
	if cur == new_state:
		return true
	if cur == ForceState.ACTIVE and (new_state == ForceState.DISABLED or new_state == ForceState.DESTROYED):
		(_forces[force_id] as Dictionary)["state"] = new_state
		return true
	if cur == ForceState.DISABLED and (new_state == ForceState.ACTIVE or new_state == ForceState.DESTROYED):
		(_forces[force_id] as Dictionary)["state"] = new_state
		return true
	return false


## Moves the force to another node (validated; "" clears to off-board).
static func set_node(force_id: String, node_id: String) -> bool:
	if not _forces.has(force_id):
		return false
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return false
	(_forces[force_id] as Dictionary)["node_id"] = node_id
	return true


## Sets (or clears with "") the faction. Validated via FactionSystem.
static func set_faction(force_id: String, faction_id: String) -> bool:
	if not _forces.has(force_id):
		return false
	if faction_id != "" and not FactionSystem.has_faction(faction_id):
		return false
	(_forces[force_id] as Dictionary)["faction"] = faction_id
	return true


## Attaches to (or detaches from with "") a Base. Validated via CampaignBase.
## Never writes base state (no garrison semantics in 5A).
static func set_base(force_id: String, base_id: String) -> bool:
	if not _forces.has(force_id):
		return false
	if base_id != "" and not CampaignBase.has_base(base_id):
		return false
	(_forces[force_id] as Dictionary)["base_id"] = base_id
	return true


## Sets abstract composition (both >= 0, set together so count and strength
## can never drift apart through partial writes).
static func set_composition(force_id: String, unit_count: int, strength: int) -> bool:
	if not _forces.has(force_id):
		return false
	if unit_count < 0 or strength < 0:
		return false
	(_forces[force_id] as Dictionary)["unit_count"] = unit_count
	(_forces[force_id] as Dictionary)["strength"] = strength
	return true


static func get_state(force_id: String) -> int:
	if not _forces.has(force_id):
		return ForceState.DESTROYED
	return int((_forces[force_id] as Dictionary).get("state", ForceState.DESTROYED))


static func is_active(force_id: String) -> bool:
	return get_state(force_id) == ForceState.ACTIVE


## Derived territory context through existing topology (node -> territories).
## Never stored on the force; first sorted id or "" (no inference).
static func get_territory_context(force_id: String) -> String:
	if not _forces.has(force_id):
		return ""
	var node_id := str((_forces[force_id] as Dictionary).get("node_id", ""))
	if node_id == "":
		return ""
	var covering := CampaignTerritory.get_territories_for_node(node_id)
	if covering.is_empty():
		return ""
	return str(covering[0].get("id", ""))


## Structural health check. Returns violation strings (empty = healthy).
static func validate() -> Array:
	var problems: Array = []
	for fid in _forces:
		var f: Dictionary = _forces[fid]
		var state := int(f.get("state", -1))
		if not STATE_NAMES.has(state):
			problems.append("force %s has unknown state" % fid)
		if not is_valid_type(str(f.get("force_type", ""))):
			problems.append("force %s has unknown type %s" % [fid, str(f.get("force_type", ""))])
		var faction := str(f.get("faction", ""))
		if faction != "" and not FactionSystem.has_faction(faction):
			problems.append("force %s has unregistered faction %s" % [fid, faction])
		var node_id := str(f.get("node_id", ""))
		if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
			problems.append("force %s references unknown node %s" % [fid, node_id])
		var base_id := str(f.get("base_id", ""))
		if base_id != "" and not CampaignBase.has_base(base_id):
			problems.append("force %s references unknown base %s" % [fid, base_id])
		if int(f.get("unit_count", -1)) < 0:
			problems.append("force %s has negative unit_count" % fid)
		if int(f.get("strength", -1)) < 0:
			problems.append("force %s has negative strength" % fid)
	return problems


## Mutable state only: sorted force records with stable string values.
## Node/base/faction data referenced by id, never duplicated.
static func serialize() -> Dictionary:
	var out: Array = []
	for f in get_forces():
		out.append({
			"id": str(f.get("id", "")),
			"force_type": str(f.get("force_type", "")),
			"state": state_to_name(int(f.get("state", ForceState.DESTROYED))),
			"faction": str(f.get("faction", "")),
			"node_id": str(f.get("node_id", "")),
			"base_id": str(f.get("base_id", "")),
			"unit_count": int(f.get("unit_count", 0)),
			"strength": int(f.get("strength", 0)),
		})
	return {"forces": out}


## Restores records. Rows with empty/colliding ids, unknown types/states, or
## negative composition are skipped; dangling node/base refs and unregistered
## factions are KEPT and flagged by validate() (topology may load later).
static func deserialize(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var rows = data.get("forces", [])
	if not (rows is Array):
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var fid := str(row.get("id", ""))
		if fid == "" or _forces.has(fid):
			continue
		var force_type := str(row.get("force_type", ""))
		if not is_valid_type(force_type):
			continue
		var state := state_from_name(str(row.get("state", "destroyed")))
		if state == -1:
			continue
		if int(row.get("unit_count", 0)) < 0 or int(row.get("strength", 0)) < 0:
			continue
		_forces[fid] = {
			"id": fid,
			"force_type": force_type,
			"state": state,
			"faction": str(row.get("faction", "")),
			"node_id": str(row.get("node_id", "")),
			"base_id": str(row.get("base_id", "")),
			"unit_count": maxi(int(row.get("unit_count", 0)), 0),
			"strength": maxi(int(row.get("strength", 0)), 0),
		}


static func clear() -> void:
	_forces.clear()
