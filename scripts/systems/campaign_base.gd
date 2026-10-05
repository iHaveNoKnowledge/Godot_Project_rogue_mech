class_name CampaignBase
extends RefCounted

## ---------------------------------------------------------------------------
## BASE ENTITY + STATE MACHINE — Phase 4 (Campaign V2 foundation).
##
## Audit evidence (do not re-decide lightly):
##   - Legacy "enemy_base" is THREE things at once, and stays that way:
##     (1) progression mechanics in EnemyFactionSystem + NarrativeState
##         (spy accumulation, progress/required, grunt/copy outcomes) — KEPT,
##         still owned there;
##     (2) a board tile (planted/restored/cleared by BoardManager,
##         combat entry, camp->fortified model) — KEPT, board-owned;
##     (3) a combat visual (ForwardBase destructible, also used for war
##         bases/camps) — VISUAL ONLY, untouched.
##   - What was MISSING is the canonical INSTALLATION record (identity +
##     lifecycle). That — and only that — lives here.
##   - Safehouse/city/depot/lab tiles are service points with no persistent
##     installation state; they are NOT base types in this phase.
##   - Scavenger camps (board-meta, unsaved) and war outposts/bases (isolated
##     war save) are separate systems; not migrated, not duplicated.
##
## Model: {id, node_id, base_type, state, controller, territory_id}.
##   Base != Node (installation occupies a location; node holds no base state).
##   Base != Territory (installation vs area; territory controller is never
##     duplicated here).
##   Base != Force (no rosters; Phase 5). Base != CombatSession (no battle
##     state; independent lifecycle).
## Types (minimal, audit-backed): RESEARCH_BASE (legacy spy-driven research
##   node), OUTPOST (generic forward installation).
## States: ACTIVE -> DISABLED -> DESTROYED, plus ACTIVE -> DESTROYED and
##   DISABLED -> ACTIVE (recovery). DESTROYED is terminal for explicit
##   writes; the legacy bridge alone may revive a record when legacy
##   re-activates (documented reconciliation, not a transition).
## Node occupancy: 0..1 non-destroyed bases per node on explicit writes;
##   the bridge bypasses occupancy (bridge wins) and validate() flags any
##   double-occupancy instead of silently corrupting records.
## Controller "": faction attribution for the legacy base is DEFERRED (the
##   federation/zeon-research vs singular-enemy-base duality is a known smell
##   for later unification — Phase 4 must not invent attribution).
## ---------------------------------------------------------------------------

enum BaseState { ACTIVE = 0, DISABLED = 1, DESTROYED = 2 }

const STATE_NAMES := {
	BaseState.ACTIVE: "active",
	BaseState.DISABLED: "disabled",
	BaseState.DESTROYED: "destroyed",
}

const BASE_TYPES := ["RESEARCH_BASE", "OUTPOST"]

## Well-known id prefix for the bridged legacy enemy research base.
const LEGACY_RESEARCH_PREFIX := "base_enemy_research_s"

static var _bases: Dictionary = {}


static func state_to_name(state: int) -> String:
	return str(STATE_NAMES.get(state, "destroyed"))


static func state_from_name(raw_name: String) -> int:
	for key in STATE_NAMES:
		if str(STATE_NAMES[key]) == raw_name:
			return int(key)
	return -1


static func is_valid_type(base_type: String) -> bool:
	return BASE_TYPES.has(base_type)


static func make_base_id(sector: int, slug: String) -> String:
	var clean := ""
	for ch in slug.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
		elif ch == "_" or ch == "-" or ch == " ":
			clean += "_"
	if clean == "":
		return ""
	return "base_s%d_%s" % [sector, clean]


static func legacy_research_id(sector: int) -> String:
	return "%s%d" % [LEGACY_RESEARCH_PREFIX, sector]


static func has_base(base_id: String) -> bool:
	return _bases.has(base_id)


static func get_base(base_id: String) -> Dictionary:
	if not _bases.has(base_id):
		return {}
	return (_bases[base_id] as Dictionary).duplicate(true)


static func get_bases() -> Array:
	var ids := _bases.keys()
	ids.sort()
	var out: Array = []
	for bid in ids:
		out.append((_bases[bid] as Dictionary).duplicate(true))
	return out


static func get_base_at_node(node_id: String) -> Dictionary:
	for bid in _bases:
		var b: Dictionary = _bases[bid]
		if str(b.get("node_id", "")) == node_id \
				and int(b.get("state", BaseState.DESTROYED)) != BaseState.DESTROYED:
			return b.duplicate(true)
	return {}


## Explicit registration. Returns id or "" when rejected: empty id, unknown
## base type, unknown node ("" node allowed = unplaced record), unregistered
## controller/territory, or id collision with a different definition.
## Identical re-registration is idempotent. Node occupancy (0..1 live bases)
## is enforced here.
static func register_base(base_id: String, node_id: String, base_type: String,
		controller: String = "", territory_id: String = "") -> String:
	if base_id == "":
		return ""
	if not is_valid_type(base_type):
		return ""
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return ""
	if controller != "" and not FactionSystem.has_faction(controller):
		return ""
	if territory_id != "" and not CampaignTerritory.has_territory(territory_id):
		return ""
	if _bases.has(base_id):
		var e: Dictionary = _bases[base_id]
		if str(e.get("node_id", "")) == node_id \
				and str(e.get("base_type", "")) == base_type:
			return base_id
		return ""
	if node_id != "" and not get_base_at_node(node_id).is_empty():
		return ""
	_bases[base_id] = {
		"id": base_id,
		"node_id": node_id,
		"base_type": base_type,
		"state": BaseState.ACTIVE,
		"controller": controller,
		"territory_id": territory_id,
	}
	return base_id


## Explicit state transition (graph-enforced). False on unknown id, unknown
## state, or illegal edge. Legal: ACTIVE->{DISABLED,DESTROYED},
## DISABLED->{ACTIVE,DESTROYED}. DESTROYED is terminal here.
static func set_state(base_id: String, new_state: int) -> bool:
	if not _bases.has(base_id):
		return false
	if not STATE_NAMES.has(new_state):
		return false
	var cur := int((_bases[base_id] as Dictionary).get("state", BaseState.DESTROYED))
	if cur == new_state:
		return true
	if cur == BaseState.ACTIVE and (new_state == BaseState.DISABLED or new_state == BaseState.DESTROYED):
		(_bases[base_id] as Dictionary)["state"] = new_state
		return true
	if cur == BaseState.DISABLED and (new_state == BaseState.ACTIVE or new_state == BaseState.DESTROYED):
		(_bases[base_id] as Dictionary)["state"] = new_state
		return true
	return false


## Moves the base to another node (validated + occupancy-checked).
static func set_node(base_id: String, node_id: String) -> bool:
	if not _bases.has(base_id):
		return false
	if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
		return false
	if node_id != "":
		var occupant := get_base_at_node(node_id)
		if not occupant.is_empty() and str(occupant.get("id", "")) != base_id:
			return false
	(_bases[base_id] as Dictionary)["node_id"] = node_id
	return true


## Sets (or clears with "") the controller. Validated via FactionSystem.
static func set_controller(base_id: String, faction_id: String) -> bool:
	if not _bases.has(base_id):
		return false
	if faction_id != "" and not FactionSystem.has_faction(faction_id):
		return false
	(_bases[base_id] as Dictionary)["controller"] = faction_id
	return true


## Sets (or clears with "") the territory link. Validated via CampaignTerritory.
static func set_territory(base_id: String, territory_id: String) -> bool:
	if not _bases.has(base_id):
		return false
	if territory_id != "" and not CampaignTerritory.has_territory(territory_id):
		return false
	(_bases[base_id] as Dictionary)["territory_id"] = territory_id
	return true


static func get_state(base_id: String) -> int:
	if not _bases.has(base_id):
		return BaseState.DESTROYED
	return int((_bases[base_id] as Dictionary).get("state", BaseState.DESTROYED))


static func is_active(base_id: String) -> bool:
	return get_state(base_id) == BaseState.ACTIVE


## Legacy bridge (one direction: legacy progression state -> Base record).
## Call after board rebuild/sync points, when the ENEMY_BASE node (if any)
## already exists. Never touches legacy fields, tiles, or combat.
##   legacy active   -> record present, state ACTIVE, node/type refreshed.
##   legacy inactive -> existing non-destroyed record goes DESTROYED (kept).
## Explicit API writes can be reconciled by later bridge runs (bridge wins);
## set_state() graph still governs every non-bridge write.
static func sync_legacy_enemy_base(sector: int) -> String:
	var bid := legacy_research_id(sector)
	var active := false
	var tile := Vector2i(-1, -1)
	if GlobalData != null and GlobalData.narrative != null:
		active = bool(GlobalData.narrative.enemy_base_active)
		tile = GlobalData.narrative.enemy_base_tile_pos
	if active:
		var node_id := ""
		if tile != Vector2i(-1, -1):
			var n := CampaignNodeRegistry.get_node_at(sector, tile)
			node_id = str(n.get("id", ""))
		var territory_id := ""
		if node_id != "":
			var covering := CampaignTerritory.get_territories_for_node(node_id)
			if not covering.is_empty():
				territory_id = str(covering[0].get("id", ""))
		if not _bases.has(bid):
			# Bypass occupancy: the legacy installation wins its tile; any
			# conflict is reported by validate(), never silently resolved.
			_bases[bid] = {
				"id": bid,
				"node_id": node_id,
				"base_type": "RESEARCH_BASE",
				"state": BaseState.ACTIVE,
				"controller": "",
				"territory_id": territory_id,
			}
		else:
			var b: Dictionary = _bases[bid]
			b["node_id"] = node_id
			b["base_type"] = "RESEARCH_BASE"
			b["state"] = BaseState.ACTIVE
			b["territory_id"] = territory_id
		return bid
	if _bases.has(bid):
		var b: Dictionary = _bases[bid]
		if int(b.get("state", BaseState.DESTROYED)) != BaseState.DESTROYED:
			b["state"] = BaseState.DESTROYED
		return bid
	return ""


## Structural health check. Returns violation strings (empty = healthy).
static func validate() -> Array:
	var problems: Array = []
	var occupied := {}
	for bid in _bases:
		var b: Dictionary = _bases[bid]
		var state := int(b.get("state", -1))
		if not STATE_NAMES.has(state):
			problems.append("base %s has unknown state" % bid)
		if not is_valid_type(str(b.get("base_type", ""))):
			problems.append("base %s has unknown type %s" % [bid, str(b.get("base_type", ""))])
		var node_id := str(b.get("node_id", ""))
		if node_id != "" and not CampaignNodeRegistry.has_node(node_id):
			problems.append("base %s references unknown node %s" % [bid, node_id])
		var controller := str(b.get("controller", ""))
		if controller != "" and not FactionSystem.has_faction(controller):
			problems.append("base %s controlled by unregistered faction %s" % [bid, controller])
		var terr := str(b.get("territory_id", ""))
		if terr != "" and not CampaignTerritory.has_territory(terr):
			problems.append("base %s references unknown territory %s" % [bid, terr])
		if node_id != "" and state != BaseState.DESTROYED:
			if occupied.has(node_id):
				problems.append("node %s hosts multiple live bases (%s, %s)" % [node_id, str(occupied[node_id]), bid])
			else:
				occupied[node_id] = bid
	return problems


## Mutable state only: sorted base records with stable string values.
## Node/territory/faction data is referenced by id, never duplicated.
static func serialize() -> Dictionary:
	var out: Array = []
	for b in get_bases():
		out.append({
			"id": str(b.get("id", "")),
			"node_id": str(b.get("node_id", "")),
			"base_type": str(b.get("base_type", "")),
			"state": state_to_name(int(b.get("state", BaseState.DESTROYED))),
			"controller": str(b.get("controller", "")),
			"territory_id": str(b.get("territory_id", "")),
		})
	return {"bases": out}


## Restores records. Rows with empty ids, unknown types/states, or colliding
## ids are skipped; dangling node/territory/controller refs are KEPT and
## flagged by validate() (board/nodes may legitimately load later).
static func deserialize(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var rows = data.get("bases", [])
	if not (rows is Array):
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var bid := str(row.get("id", ""))
		if bid == "" or _bases.has(bid):
			continue
		var base_type := str(row.get("base_type", ""))
		if not is_valid_type(base_type):
			continue
		var state := state_from_name(str(row.get("state", "destroyed")))
		if state == -1:
			continue
		_bases[bid] = {
			"id": bid,
			"node_id": str(row.get("node_id", "")),
			"base_type": base_type,
			"state": state,
			"controller": str(row.get("controller", "")),
			"territory_id": str(row.get("territory_id", "")),
		}


static func clear() -> void:
	_bases.clear()
