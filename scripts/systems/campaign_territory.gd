class_name CampaignTerritory
extends RefCounted

## ---------------------------------------------------------------------------
## TERRITORY LAYER — Phase 3B (Campaign V2 foundation, NOT a gameplay system).
##
## Audit evidence (do not re-decide lightly):
##   - No existing Territory authority exists. "Territory" in the codebase is
##     only prose ("deep territory" distance band, "contested outpost" war
##     decor, "contested dead zones" pilot flavor). No ownership/control
##     fields exist anywhere.
##   - `sector` (1..3) is a linear run partition, not a spatial territory.
##   - Sub-zones are terrain micro-biomes (visuals + arena presets), not
##     control areas.
##   - Board cells must NOT become territories (35x35 physical substrate stays
##     with BoardManager/BoardState); routes are NOT boundaries.
##
## Model: Territory = strategic AREA (id + control state + optional node
## membership). Territory != Node (point), != BoardTile (cell), != Route.
## A territory may cover many nodes, one node, or zero nodes.
##
## Control semantics (explicit, minimal):
##   UNCONTROLLED: controller "", contesting [].
##   CONTROLLED:   controller = one registered faction, contesting [].
##   CONTESTED:    controller "" (never a single claimant), contesting =
##                 1+ registered factions, deduped + sorted.
## Faction identity always comes from FactionSystem (never duplicated here).
## Node membership references CampaignNodeRegistry IDs (never copied, never
## re-owned). Stale member IDs (consumed nodes) are KEPT and flagged by
## validate() — dynamic nodes (enemy_base) can return, so silent pruning
## would corrupt future state.
##
## Out of scope (later phases): capture logic, AI, supply, detection, UI,
## map visuals, war merge, combat migration, diplomacy.
## ---------------------------------------------------------------------------

enum ControlState { UNCONTROLLED = 0, CONTROLLED = 1, CONTESTED = 2 }

const CONTROL_NAMES := {
	ControlState.UNCONTROLLED: "uncontrolled",
	ControlState.CONTROLLED: "controlled",
	ControlState.CONTESTED: "contested",
}

static var _territories: Dictionary = {}


static func control_to_name(state: int) -> String:
	return str(CONTROL_NAMES.get(state, "uncontrolled"))


static func control_from_name(raw_name: String) -> int:
	for key in CONTROL_NAMES:
		if str(CONTROL_NAMES[key]) == raw_name:
			return int(key)
	return -1


## Deterministic helper for future derivation (sector + slug, sanitized).
static func make_territory_id(sector: int, slug: String) -> String:
	var clean := ""
	for ch in slug.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
		elif ch == "_" or ch == "-" or ch == " ":
			clean += "_"
	if clean == "":
		return ""
	return "terr_s%d_%s" % [sector, clean]


static func has_territory(territory_id: String) -> bool:
	return _territories.has(territory_id)


static func get_territory(territory_id: String) -> Dictionary:
	if not _territories.has(territory_id):
		return {}
	return (_territories[territory_id] as Dictionary).duplicate(true)


static func get_territories() -> Array:
	var ids := _territories.keys()
	ids.sort()
	var out: Array = []
	for tid in ids:
		out.append((_territories[tid] as Dictionary).duplicate(true))
	return out


## Registers one territory. members are CampaignNodeRegistry IDs (may be
## empty — a territory can cover zero nodes). Returns the id, or "" when
## rejected: empty id, unknown node member, or same id with a DIFFERENT
## member set. Re-registering the identical definition is idempotent.
static func register_territory(territory_id: String, members: Array = []) -> String:
	if territory_id == "":
		return ""
	var clean_members := _validate_members(members)
	if clean_members.is_empty() and not members.is_empty():
		return ""
	if _territories.has(territory_id):
		var existing: Dictionary = _territories[territory_id]
		if _same_id_set(existing.get("members", []), clean_members):
			return territory_id
		return ""
	_territories[territory_id] = {
		"id": territory_id,
		"control": ControlState.UNCONTROLLED,
		"controller": "",
		"contesting": [],
		"members": clean_members,
	}
	return territory_id


## Replaces the member set (validated, all-or-nothing). False on unknown
## territory or any unknown node id — state left untouched.
static func set_members(territory_id: String, members: Array) -> bool:
	if not _territories.has(territory_id):
		return false
	var clean_members := _validate_members(members)
	if clean_members.is_empty() and not members.is_empty():
		return false
	(_territories[territory_id] as Dictionary)["members"] = clean_members
	return true


static func get_members(territory_id: String) -> Array:
	if not _territories.has(territory_id):
		return []
	return Array((_territories[territory_id] as Dictionary).get("members", [])).duplicate()


## CONTROLLED with a registered faction. Rejects unknown territories and
## unregistered factions without mutating. Clears any contest list.
static func set_controlled(territory_id: String, faction_id: String) -> bool:
	if not _territories.has(territory_id):
		return false
	if not FactionSystem.has_faction(faction_id):
		return false
	var t: Dictionary = _territories[territory_id]
	t["control"] = ControlState.CONTROLLED
	t["controller"] = faction_id
	t["contesting"] = []
	return true


## CONTESTED by 1+ registered factions. Controller is always cleared —
## a contested territory never claims a single controller. Rejects unknown
## territories, empty lists, and any unregistered faction, without mutating.
static func set_contested(territory_id: String, factions: Array) -> bool:
	if not _territories.has(territory_id):
		return false
	var clean: Array = []
	for f in factions:
		var fid := str(f)
		if not FactionSystem.has_faction(fid):
			return false
		if not clean.has(fid):
			clean.append(fid)
	if clean.is_empty():
		return false
	clean.sort()
	var t: Dictionary = _territories[territory_id]
	t["control"] = ControlState.CONTESTED
	t["controller"] = ""
	t["contesting"] = clean
	return true


## UNCONTROLLED: clears controller and contest list. False on unknown id.
static func set_uncontrolled(territory_id: String) -> bool:
	if not _territories.has(territory_id):
		return false
	var t: Dictionary = _territories[territory_id]
	t["control"] = ControlState.UNCONTROLLED
	t["controller"] = ""
	t["contesting"] = []
	return true


static func get_control_state(territory_id: String) -> int:
	if not _territories.has(territory_id):
		return ControlState.UNCONTROLLED
	return int((_territories[territory_id] as Dictionary).get("control", ControlState.UNCONTROLLED))


static func get_controller(territory_id: String) -> String:
	if not _territories.has(territory_id):
		return ""
	var t: Dictionary = _territories[territory_id]
	if int(t.get("control", ControlState.UNCONTROLLED)) != ControlState.CONTROLLED:
		return ""
	return str(t.get("controller", ""))


static func get_contesting(territory_id: String) -> Array:
	if not _territories.has(territory_id):
		return []
	return Array((_territories[territory_id] as Dictionary).get("contesting", [])).duplicate()


## Pure membership query: every territory covering a node, sorted by id.
## Read-only derivation for consumers (e.g. the Base bridge); adds no state.
static func get_territories_for_node(node_id: String) -> Array:
	var out: Array = []
	for tid in _territories:
		if Array((_territories[tid] as Dictionary).get("members", [])).has(node_id):
			out.append((_territories[tid] as Dictionary).duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	return out


static func is_controlled(territory_id: String) -> bool:
	return get_control_state(territory_id) == ControlState.CONTROLLED


static func is_contested(territory_id: String) -> bool:
	return get_control_state(territory_id) == ControlState.CONTESTED


static func is_uncontrolled(territory_id: String) -> bool:
	return get_control_state(territory_id) == ControlState.UNCONTROLLED


## Structural health check. Returns violation strings (empty = healthy).
## Unknown member IDs are REPORTED, never silently pruned (dynamic nodes can
## return — e.g. a restored enemy_base — so pruning would corrupt the future).
static func validate() -> Array:
	var problems: Array = []
	var seen := {}
	for tid in _territories:
		if seen.has(tid):
			problems.append("duplicate territory id %s" % tid)
		seen[tid] = true
		var t: Dictionary = _territories[tid]
		var control := int(t.get("control", ControlState.UNCONTROLLED))
		var controller := str(t.get("controller", ""))
		var contesting: Array = t.get("contesting", [])
		if control == ControlState.UNCONTROLLED:
			if controller != "":
				problems.append("territory %s uncontrolled but keeps controller %s" % [tid, controller])
			if not contesting.is_empty():
				problems.append("territory %s uncontrolled but keeps contest list" % tid)
		elif control == ControlState.CONTROLLED:
			if not FactionSystem.has_faction(controller):
				problems.append("territory %s controlled by unregistered faction %s" % [tid, controller])
			if not contesting.is_empty():
				problems.append("territory %s controlled but keeps contest list" % tid)
		elif control == ControlState.CONTESTED:
			if controller != "":
				problems.append("territory %s contested but claims controller %s" % [tid, controller])
			if contesting.is_empty():
				problems.append("territory %s contested with empty contest list" % tid)
			for f in contesting:
				if not FactionSystem.has_faction(str(f)):
					problems.append("territory %s contested by unregistered faction %s" % [tid, str(f)])
		else:
			problems.append("territory %s has unknown control state %d" % [tid, control])
		for m in t.get("members", []):
			if not CampaignNodeRegistry.has_node(str(m)):
				problems.append("territory %s references unknown node %s" % [tid, str(m)])
	return problems


## Mutable state only: sorted territories with stable string values. Members
## are node-ID references (node data itself is never duplicated here).
static func serialize() -> Dictionary:
	var out: Array = []
	for t in get_territories():
		out.append({
			"id": str(t.get("id", "")),
			"control": control_to_name(int(t.get("control", ControlState.UNCONTROLLED))),
			"controller": str(t.get("controller", "")),
			"contesting": Array(t.get("contesting", [])).duplicate(),
			"members": Array(t.get("members", [])).duplicate(),
		})
	return {"territories": out}


## Restores registry + control. Rows with empty ids, unknown control names,
## unregistered controllers, or invalid contest lists are SKIPPED entirely
## (fail the row, keep nothing). Unknown node members are kept and flagged by
## validate() (never pruned — dynamic nodes can return). Missing/empty input
## resets to empty (old saves).
static func deserialize(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var rows = data.get("territories", [])
	if not (rows is Array):
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var tid := str(row.get("id", ""))
		if tid == "":
			continue
		var control := control_from_name(str(row.get("control", "uncontrolled")))
		if control == -1:
			continue
		var controller := str(row.get("controller", ""))
		var contest_raw = row.get("contesting", [])
		var contest_clean: Array = []
		if control == ControlState.CONTROLLED:
			if not FactionSystem.has_faction(controller):
				continue
		elif control == ControlState.CONTESTED:
			if not (contest_raw is Array):
				continue
			for f in contest_raw:
				var fid := str(f)
				if not FactionSystem.has_faction(fid):
					contest_clean = []
					break
				if not contest_clean.has(fid):
					contest_clean.append(fid)
			if contest_clean.is_empty():
				continue
			contest_clean.sort()
		var members: Array = []
		var mem_raw = row.get("members", [])
		if mem_raw is Array:
			for m in mem_raw:
				members.append(str(m))
		# Validate members WITHOUT pruning: keep known ids now, re-check
		# unknown ones through register + validate (dynamic nodes return).
		var known: Array = []
		var deferred: Array = []
		for m in members:
			if CampaignNodeRegistry.has_node(m):
				known.append(m)
			else:
				deferred.append(m)
		var rid := register_territory(tid, known)
		if rid == "":
			continue
		for m in deferred:
			(_territories[rid] as Dictionary)["members"].append(m)
		if control == ControlState.CONTROLLED:
			set_controlled(rid, controller)
		elif control == ControlState.CONTESTED:
			set_contested(rid, contest_clean)


static func clear() -> void:
	_territories.clear()


static func _validate_members(members: Array) -> Array:
	var clean: Array = []
	for m in members:
		var mid := str(m)
		if not CampaignNodeRegistry.has_node(mid):
			return []
		if not clean.has(mid):
			clean.append(mid)
	clean.sort()
	return clean


static func _same_id_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for item in a:
		if not b.has(item):
			return false
	return true
