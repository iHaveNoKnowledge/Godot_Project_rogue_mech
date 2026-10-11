class_name CampaignStrategicThreat
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC THREAT QUERY — Phase C4-B3 (Campaign V2).
##
## Read-only derived assessment of strategic pressure at a node, evaluated
## from the perspective of one observing faction. Pure calculation: no
## static mutable state, no cache, no signals, no turn advancement, no
## persistence. Every call re-reads the owning authorities through their
## public query methods and returns freshly built containers.
##
## Architectural Contract:
##   - Authorities read (never written): CampaignNodeRegistry (topology),
##     CampaignForce (posture), CampaignBase (installations),
##     CampaignTerritory (control), FactionSystem (relation matrix),
##     CampaignStrategicHeat (traces), CampaignStrategicDetection
##     (faction intel), CampaignTurnExecutive (clock, read-only counter).
##   - Anti-omniscience invariant: GlobalData.current_campaign_player_node_id
##     is NEVER read. The player's true position cannot influence any result;
##     faction knowledge comes only from explicit detection records.
##   - Faction isolation: only the observing faction's own detection record
##     is consulted. One faction's intelligence never affects another's result.
##   - B2.1 freshness pin: effective intel mirrors process_turn_decay()
##     exactly (LOCATED iff age < 1, SUSPECTED iff 1 <= age < 3 on a located
##     trail or age < 3 suspected, else UNKNOWN; future-dated records read
##     as UNKNOWN). A recent last_known_turn may reflect a suspicion-trace
##     refresh rather than a new confirmation (report_suspicion() bumps the
##     clock while preserving node/source/state), so timestamp freshness
##     alone is never treated as proof of fresh confirmation: CRITICAL
##     additionally requires a co-located hostile force (objective fact).
##   - Reachability is exactly one route hop (no pathfinding). Destroyed
##     forces/bases exert no pressure (historical records only). Unknown or
##     unattributed affiliations never silently read as hostile.
##
## Provisional policy (documented, not balanced game design):
##   Levels: SECURE(0) / ELEVATED(1) / INTERDICTED(2) / CRITICAL(3).
##   - Hostile non-destroyed force co-located, or hostile non-destroyed base
##     at node                                        -> INTERDICTED.
##   - Effective LOCATED intel at node + co-located hostile force -> CRITICAL.
##   - Effective LOCATED intel at node without hostile posture,
##     same-node SUSPECTED intel, hostile force within 1 hop,
##     hostile-controlled covering territory (node or 1 hop),
##     or heat >= trace threshold                      -> ELEVATED.
##   Confidence tracks intel quality only: current (LOCATED) /
##   uncertain (SUSPECTED incl. decayed LOCATED) / unavailable (UNKNOWN).
## ---------------------------------------------------------------------------

const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const FactionSystem = preload("res://scripts/systems/faction_system.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")
const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")
const CampaignStrategicDetection = preload("res://scripts/systems/campaign_strategic_detection.gd")

enum ThreatLevel {
	SECURE = 0,
	ELEVATED = 1,
	INTERDICTED = 2,
	CRITICAL = 3,
}

const LEVEL_NAMES: Dictionary = {
	ThreatLevel.SECURE: "secure",
	ThreatLevel.ELEVATED: "elevated",
	ThreatLevel.INTERDICTED: "interdicted",
	ThreatLevel.CRITICAL: "critical",
}


## Returns the human-readable name for a ThreatLevel int ("unknown" if invalid).
static func threat_name(level: int) -> String:
	return str(LEVEL_NAMES.get(level, "unknown"))


## Read-only threat assessment for one node from one faction's perspective.
## current_turn < 0 resolves to the live campaign turn (read-only clock).
## Returns {ok, reason, node_id, faction_id, turn, threat_level, threat_name,
## confidence, contributors[], effective_intel{}} on success.
static func get_node_threat(node_id: String, faction_id: String, current_turn: int = -1) -> Dictionary:
	var nid := node_id.strip_edges()
	var fid := faction_id.strip_edges()
	if nid == "":
		return _fail("", fid, -1, "empty_node_id")
	if not CampaignNodeRegistry.has_node(nid):
		return _fail(nid, fid, -1, "unknown_node")
	if fid == "":
		return _fail(nid, "", -1, "empty_faction_id")
	var turn := current_turn
	if turn < -1:
		return _fail(nid, fid, current_turn, "negative_turn")
	if turn == -1:
		turn = CampaignTurnExecutive.get_turn()

	var contributors: Array = []

	# Objective posture: co-located non-destroyed forces, split by hostility.
	var present_hostile: Array = []
	var adjacent_hostile: Array = []
	for force_fid in CampaignForce.get_forces_at_node(nid):
		var force := CampaignForce.get_force(str(force_fid))
		if force.is_empty():
			continue
		if int(force.get("state", CampaignForce.ForceState.DESTROYED)) == CampaignForce.ForceState.DESTROYED:
			continue
		if _is_hostile_to(str(force.get("faction", "")), fid):
			present_hostile.append(str(force.get("id", str(force_fid))))

	# One-hop reachability only: hostile non-destroyed forces on direct neighbors.
	var neighbors := _neighbor_nodes(nid)
	for neighbor in neighbors:
		for force_fid in CampaignForce.get_forces_at_node(str(neighbor)):
			var force := CampaignForce.get_force(str(force_fid))
			if force.is_empty():
				continue
			if int(force.get("state", CampaignForce.ForceState.DESTROYED)) == CampaignForce.ForceState.DESTROYED:
				continue
			if _is_hostile_to(str(force.get("faction", "")), fid):
				adjacent_hostile.append({
					"force_id": str(force.get("id", str(force_fid))),
					"node_id": str(neighbor),
				})
	present_hostile.sort()
	adjacent_hostile.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("force_id", "")) < str(b.get("force_id", "")))

	# Hostile installation at the node (destroyed bases are already filtered
	# out by get_base_at_node itself).
	var hostile_base_id := ""
	var base := CampaignBase.get_base_at_node(nid)
	if not base.is_empty():
		var controller := str(base.get("controller", ""))
		if controller != "" and _is_hostile_to(controller, fid):
			hostile_base_id = str(base.get("id", ""))

	# Hostile-controlled covering territory at the node or one hop out.
	var hostile_territories: Array = []
	var checked_nodes: Array = [nid] + neighbors
	for scope_node in checked_nodes:
		for territory in CampaignTerritory.get_territories_for_node(str(scope_node)):
			var tid := str(territory.get("id", ""))
			var controller := str(territory.get("controller", ""))
			if tid != "" and controller != "" and _is_hostile_to(controller, fid) \
					and not hostile_territories.has(tid):
				hostile_territories.append(tid)
	hostile_territories.sort()

	# Residual operational trace (pressure only, never certainty).
	var heat_level := CampaignStrategicHeat.get_node_heat(nid)
	var heat_sig := heat_level >= CampaignStrategicDetection.SUSPICION_HEAT_THRESHOLD

	# Effective intelligence for the observing faction ONLY (no mutation,
	# mirrors process_turn_decay boundaries; future-dated records are UNKNOWN).
	var intel := _effective_intel(fid, nid, turn)

	# Contributors + level ladder (CRITICAL is conjunctive by construction).
	if not present_hostile.is_empty():
		contributors.append({"code": "hostile_force_present", "severity": 2,
			"detail": {"force_ids": present_hostile.duplicate()}})
	if hostile_base_id != "":
		contributors.append({"code": "hostile_base_present", "severity": 2,
			"detail": {"base_id": hostile_base_id}})
	var intel_state := str(intel.get("state", "unknown"))
	if intel_state == "located":
		if not present_hostile.is_empty():
			contributors.append({"code": "located_here", "severity": 3,
				"detail": {"node_id": nid, "age": int(intel.get("age", 0)),
					"source": str(intel.get("source", "none"))}})
		else:
			contributors.append({"code": "located_no_hostile_posture", "severity": 1,
				"detail": {"node_id": nid, "age": int(intel.get("age", 0)),
					"source": str(intel.get("source", "none"))}})
	elif intel_state == "suspected":
		contributors.append({"code": "suspected_here", "severity": 1,
			"detail": {"node_id": nid, "age": int(intel.get("age", 0)),
				"source": str(intel.get("source", "none"))}})
	else:
		contributors.append({"code": "intel_unknown", "severity": 0, "detail": {}})
	if not adjacent_hostile.is_empty():
		contributors.append({"code": "hostile_force_adjacent", "severity": 1,
			"detail": {"forces": adjacent_hostile.duplicate(true)}})
	if not hostile_territories.is_empty():
		contributors.append({"code": "adjacent_hostile_territory", "severity": 1,
			"detail": {"territory_ids": hostile_territories.duplicate()}})
	if heat_sig:
		contributors.append({"code": "residual_heat", "severity": 1,
			"detail": {"heat": heat_level,
				"threshold": CampaignStrategicDetection.SUSPICION_HEAT_THRESHOLD}})

	var level := ThreatLevel.SECURE
	if not present_hostile.is_empty() or hostile_base_id != "":
		level = ThreatLevel.INTERDICTED
	if intel_state == "located" and not present_hostile.is_empty():
		level = ThreatLevel.CRITICAL
	elif intel_state == "located" or intel_state == "suspected" \
			or not adjacent_hostile.is_empty() or not hostile_territories.is_empty() or heat_sig:
		level = maxi(level, ThreatLevel.ELEVATED)

	var confidence := "unavailable"
	if intel_state == "located":
		confidence = "current"
	elif intel_state == "suspected":
		confidence = "uncertain"

	return {
		"ok": true,
		"reason": "assessed",
		"node_id": nid,
		"faction_id": fid,
		"turn": turn,
		"threat_level": level,
		"threat_name": threat_name(level),
		"confidence": confidence,
		"contributors": contributors,
		"effective_intel": intel,
	}


## Direct-neighbor node ids via registered strategic routes (sorted, unique).
static func _neighbor_nodes(node_id: String) -> Array:
	var out: Array = []
	for r in CampaignNodeRegistry.get_routes_for(node_id):
		for key in ["a", "b"]:
			var other := str((r as Dictionary).get(key, ""))
			if other != "" and other != node_id and CampaignNodeRegistry.has_node(other) \
					and not out.has(other):
				out.append(other)
	out.sort()
	return out


## True only for an explicit HOSTILE matrix relation. Unknown, empty, or
## unattributed affiliations read as non-hostile (never silent-hostile).
static func _is_hostile_to(other_faction: String, observer_faction: String) -> bool:
	return FactionSystem.get_relation(other_faction.strip_edges(), observer_faction) \
		== FactionSystem.Relation.HOSTILE


## Effective intel state without mutating the stored record. Mirrors
## process_turn_decay() boundaries exactly; records dated after the query
## turn read as UNKNOWN (the intel does not exist yet at that turn).
static func _effective_intel(faction_id: String, node_id: String, turn: int) -> Dictionary:
	var rec := CampaignStrategicDetection.get_faction_intelligence(faction_id)
	var stored := int(rec.get("state", CampaignStrategicDetection.DetectionState.UNKNOWN))
	var record_node := str(rec.get("last_known_node_id", ""))
	var record_turn := int(rec.get("last_known_turn", 0))
	var source := str(rec.get("source", "none"))
	if stored == CampaignStrategicDetection.DetectionState.UNKNOWN:
		return {"state": "unknown", "node": "", "age": -1, "source": source}
	var age := turn - record_turn
	if age < 0:
		return {"state": "unknown", "node": "", "age": age, "source": source}
	if stored == CampaignStrategicDetection.DetectionState.LOCATED:
		if age < CampaignStrategicDetection.LOCATED_MAX_AGE_TURNS:
			if record_node == node_id:
				return {"state": "located", "node": record_node, "age": age, "source": source}
			return {"state": "unknown", "node": "", "age": age, "source": source}
		if age < CampaignStrategicDetection.SUSPECTED_MAX_AGE_TURNS:
			if record_node == node_id:
				return {"state": "suspected", "node": record_node, "age": age, "source": source}
			return {"state": "unknown", "node": "", "age": age, "source": source}
		return {"state": "unknown", "node": "", "age": age, "source": source}
	if age < CampaignStrategicDetection.SUSPECTED_MAX_AGE_TURNS:
		if record_node == node_id:
			return {"state": "suspected", "node": record_node, "age": age, "source": source}
		return {"state": "unknown", "node": "", "age": age, "source": source}
	return {"state": "unknown", "node": "", "age": age, "source": source}


static func _fail(node_id: String, faction_id: String, turn: int, reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"node_id": node_id,
		"faction_id": faction_id,
		"turn": turn,
		"threat_level": ThreatLevel.SECURE,
		"threat_name": threat_name(ThreatLevel.SECURE),
		"confidence": "unavailable",
		"contributors": [],
		"effective_intel": {},
	}
