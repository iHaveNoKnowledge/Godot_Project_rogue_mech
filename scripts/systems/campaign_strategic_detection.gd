class_name CampaignStrategicDetection
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC DETECTION AUTHORITY — Phase C4-B2 (Campaign V2).
##
## Authoritative store for faction-specific strategic intelligence states.
##
## Architectural Contract:
##   - Faction-Specific Intelligence:
##     Tracks what each individual faction knows or suspects about the player's
##     location and activities. One faction's detection NEVER leaks to another.
##   - Anti-Omniscience Invariant:
##     Factions NEVER query or infer GlobalData.current_campaign_player_node_id
##     directly. Exact location is acquired ONLY via credible events (combat,
##     direct contact).
##   - Heat as Trace Evidence:
##     Node heat (CampaignStrategicHeat) is physical trace evidence. Heat
##     alone (>= 3) can elevate intelligence to SUSPECTED, but NEVER to LOCATED.
##   - Independent Freshness & Degradation:
##     Intelligence ages over campaign turns. LOCATED degrades to SUSPECTED
##     when unconfirmed, and SUSPECTED cools to UNKNOWN over time. Heat decay
##     does NOT instantly erase independent historical intelligence.
##   - Static Domain Authority:
##     Script-level static state matching CampaignStrategicHeat, CampaignBase,
##     CampaignTerritory, and CampaignForce.
## ---------------------------------------------------------------------------

enum DetectionState {
	UNKNOWN = 0,
	SUSPECTED = 1,
	LOCATED = 2,
}

const STATE_NAMES: Dictionary = {
	DetectionState.UNKNOWN: "unknown",
	DetectionState.SUSPECTED: "suspected",
	DetectionState.LOCATED: "located",
}

const SUSPICION_HEAT_THRESHOLD: int = 3
const LOCATED_MAX_AGE_TURNS: int = 1   # After 1 turn unconfirmed, LOCATED -> SUSPECTED
const SUSPECTED_MAX_AGE_TURNS: int = 3 # After 3 turns stale, SUSPECTED -> UNKNOWN

static var _faction_intelligence: Dictionary = {}


## Returns the human-readable string name for a DetectionState enum.
static func state_to_name(state: int) -> String:
	return str(STATE_NAMES.get(state, "unknown"))


## Converts a string name back into a DetectionState enum value (-1 if invalid).
static func state_from_name(raw_name: String) -> int:
	var lower := raw_name.strip_edges().to_lower()
	for key in STATE_NAMES:
		if str(STATE_NAMES[key]) == lower:
			return int(key)
	return -1


## Returns the current DetectionState int (0=UNKNOWN, 1=SUSPECTED, 2=LOCATED).
static func get_detection_state(faction_id: String) -> int:
	var fid := faction_id.strip_edges()
	if fid == "" or not _faction_intelligence.has(fid):
		return DetectionState.UNKNOWN
	var rec: Dictionary = _faction_intelligence[fid]
	return int(rec.get("state", DetectionState.UNKNOWN))


## Returns true if the faction has LOCATED detection state on the player.
static func is_located(faction_id: String) -> bool:
	return get_detection_state(faction_id) == DetectionState.LOCATED


## Returns true if the faction has at least SUSPECTED detection state (> UNKNOWN).
static func is_suspected(faction_id: String) -> bool:
	return get_detection_state(faction_id) >= DetectionState.SUSPECTED


## Returns the last known node ID for this faction ("" if unknown).
static func get_last_known_node_id(faction_id: String) -> String:
	var fid := faction_id.strip_edges()
	if fid == "" or not _faction_intelligence.has(fid):
		return ""
	var rec: Dictionary = _faction_intelligence[fid]
	return str(rec.get("last_known_node_id", ""))


## Returns the turn number when this faction last updated its intelligence (0 if none).
static func get_last_known_turn(faction_id: String) -> int:
	var fid := faction_id.strip_edges()
	if fid == "" or not _faction_intelligence.has(fid):
		return 0
	var rec: Dictionary = _faction_intelligence[fid]
	return int(rec.get("last_known_turn", 0))


## Returns the provenance source of the intelligence ("none", "combat", "trace", etc.).
static func get_intelligence_source(faction_id: String) -> String:
	var fid := faction_id.strip_edges()
	if fid == "" or not _faction_intelligence.has(fid):
		return "none"
	var rec: Dictionary = _faction_intelligence[fid]
	return str(rec.get("source", "none"))


## Returns a defensive copy of a single faction's complete intelligence record.
static func get_faction_intelligence(faction_id: String) -> Dictionary:
	var fid := faction_id.strip_edges()
	if fid == "" or not _faction_intelligence.has(fid):
		return {
			"faction_id": fid,
			"state": DetectionState.UNKNOWN,
			"state_name": state_to_name(DetectionState.UNKNOWN),
			"last_known_node_id": "",
			"last_known_turn": 0,
			"source": "none",
			"evidence_heat": 0,
		}
	var rec: Dictionary = _faction_intelligence[fid].duplicate(true)
	rec["state_name"] = state_to_name(int(rec.get("state", DetectionState.UNKNOWN)))
	return rec


## Returns a deep copy of all currently tracked faction intelligence records.
static func get_all_intelligence() -> Dictionary:
	return _faction_intelligence.duplicate(true)


## Records a suspicion event for a faction at a node (e.g. from heat trace or recon).
## Transitions UNKNOWN -> SUSPECTED, or refreshes an existing SUSPECTED record.
## Does NOT downgrade an active LOCATED record.
static func report_suspicion(faction_id: String, node_id: String, turn: int, heat_evidence: int = 0, source: String = "trace") -> Dictionary:
	var fid := faction_id.strip_edges()
	var nid := node_id.strip_edges()
	if fid == "":
		return {"ok": false, "reason": "empty_faction_id", "faction_id": "", "node_id": nid}
	if nid == "":
		return {"ok": false, "reason": "empty_node_id", "faction_id": fid, "node_id": ""}
	if turn < 0:
		return {"ok": false, "reason": "negative_turn", "faction_id": fid, "node_id": nid}

	var current := get_faction_intelligence(fid)
	var cur_state: int = int(current.get("state", DetectionState.UNKNOWN))
	var cur_turn: int = int(current.get("last_known_turn", 0))

	# Reject stale events (turn is strictly older than current knowledge)
	if cur_turn > 0 and turn < cur_turn:
		return {
			"ok": false,
			"reason": "stale_event",
			"faction_id": fid,
			"node_id": nid,
			"current_turn": cur_turn,
			"event_turn": turn,
		}

	var new_state := cur_state
	var transition_reason := "suspicion_refreshed"

	if cur_state == DetectionState.UNKNOWN:
		new_state = DetectionState.SUSPECTED
		transition_reason = "elevated_to_suspected"
	elif cur_state == DetectionState.LOCATED:
		# If currently LOCATED, a suspicion event updates secondary trace evidence
		# but does not demote the authoritative LOCATED state until turn decay.
		transition_reason = "trace_noted_while_located"

	_faction_intelligence[fid] = {
		"faction_id": fid,
		"state": new_state,
		"last_known_node_id": nid if cur_state != DetectionState.LOCATED else str(current.get("last_known_node_id", nid)),
		"last_known_turn": maxi(turn, cur_turn),
		"source": source if cur_state != DetectionState.LOCATED else str(current.get("source", source)),
		"evidence_heat": clampi(heat_evidence, 0, 10),
	}

	return {
		"ok": true,
		"reason": transition_reason,
		"faction_id": fid,
		"node_id": nid,
		"old_state": cur_state,
		"new_state": new_state,
		"turn": turn,
		"source": source,
	}


## Records a credible location event for a faction at a node (e.g. from combat).
## Transitions UNKNOWN/SUSPECTED -> LOCATED, or updates an existing LOCATED record.
static func report_location(faction_id: String, node_id: String, turn: int, source: String = "combat") -> Dictionary:
	var fid := faction_id.strip_edges()
	var nid := node_id.strip_edges()
	if fid == "":
		return {"ok": false, "reason": "empty_faction_id", "faction_id": "", "node_id": nid}
	if nid == "":
		return {"ok": false, "reason": "empty_node_id", "faction_id": fid, "node_id": ""}
	if turn < 0:
		return {"ok": false, "reason": "negative_turn", "faction_id": fid, "node_id": nid}

	var current := get_faction_intelligence(fid)
	var cur_state: int = int(current.get("state", DetectionState.UNKNOWN))
	var cur_turn: int = int(current.get("last_known_turn", 0))

	# Reject stale events
	if cur_turn > 0 and turn < cur_turn:
		return {
			"ok": false,
			"reason": "stale_event",
			"faction_id": fid,
			"node_id": nid,
			"current_turn": cur_turn,
			"event_turn": turn,
		}

	var new_state := DetectionState.LOCATED
	var transition_reason := "elevated_to_located"
	if cur_state == DetectionState.LOCATED:
		transition_reason = "location_updated"

	_faction_intelligence[fid] = {
		"faction_id": fid,
		"state": new_state,
		"last_known_node_id": nid,
		"last_known_turn": turn,
		"source": source,
		"evidence_heat": int(current.get("evidence_heat", 0)),
	}

	return {
		"ok": true,
		"reason": transition_reason,
		"faction_id": fid,
		"node_id": nid,
		"old_state": cur_state,
		"new_state": new_state,
		"turn": turn,
		"source": source,
	}


## Evaluates a node's operational heat trace against the suspicion threshold.
## If heat >= 3, records suspicion. Otherwise reports below_threshold with zero mutation.
static func evaluate_node_trace(faction_id: String, node_id: String, heat_level: int, turn: int) -> Dictionary:
	var fid := faction_id.strip_edges()
	var nid := node_id.strip_edges()
	if fid == "" or nid == "":
		return {"ok": false, "reason": "invalid_parameters"}

	if heat_level >= SUSPICION_HEAT_THRESHOLD:
		return report_suspicion(fid, nid, turn, heat_level, "trace_threshold")

	return {
		"ok": false,
		"reason": "below_threshold",
		"faction_id": fid,
		"node_id": nid,
		"heat": heat_level,
		"threshold": SUSPICION_HEAT_THRESHOLD,
	}


## Processes turn-based intelligence aging and degradation.
##   - LOCATED (> LOCATED_MAX_AGE_TURNS old) -> degrades to SUSPECTED.
##   - SUSPECTED (> SUSPECTED_MAX_AGE_TURNS old) -> degrades to UNKNOWN.
## Called during PHASE_STRATEGIC_DETECTION of CampaignTurnExecutive.
static func process_turn_decay(current_turn: int) -> Dictionary:
	if current_turn < 0:
		return {"ok": false, "reason": "negative_turn", "degraded_count": 0, "details": {}}

	var degraded_count := 0
	var details: Dictionary = {}

	for fid in _faction_intelligence.keys():
		var rec: Dictionary = _faction_intelligence[fid]
		var state: int = int(rec.get("state", DetectionState.UNKNOWN))
		var last_turn: int = int(rec.get("last_known_turn", 0))
		var age: int = current_turn - last_turn

		if state == DetectionState.LOCATED and age >= LOCATED_MAX_AGE_TURNS:
			rec["state"] = DetectionState.SUSPECTED
			rec["source"] = "stale_location"
			degraded_count += 1
			details[fid] = {
				"from": DetectionState.LOCATED,
				"to": DetectionState.SUSPECTED,
				"reason": "located_expired_to_suspected",
				"age": age,
			}
		elif state == DetectionState.SUSPECTED and age >= SUSPECTED_MAX_AGE_TURNS:
			rec["state"] = DetectionState.UNKNOWN
			rec["last_known_node_id"] = ""
			rec["source"] = "expired"
			rec["evidence_heat"] = 0
			degraded_count += 1
			details[fid] = {
				"from": DetectionState.SUSPECTED,
				"to": DetectionState.UNKNOWN,
				"reason": "suspected_expired_to_unknown",
				"age": age,
			}

	return {
		"ok": true,
		"reason": "decay_processed",
		"degraded_count": degraded_count,
		"current_turn": current_turn,
		"details": details,
	}


## Clears all faction intelligence records back to initial clean state.
static func reset() -> void:
	_faction_intelligence.clear()


## Serializes all faction intelligence to a clean dictionary format.
static func serialize() -> Dictionary:
	return {
		"faction_intelligence": _faction_intelligence.duplicate(true),
	}


## Deserializes faction intelligence from dictionary with validation.
static func deserialize(data: Variant) -> void:
	reset()
	if not (data is Dictionary):
		return
	var intel = data.get("faction_intelligence", {})
	if not (intel is Dictionary):
		return
	for key in intel.keys():
		var fid := str(key).strip_edges()
		if fid == "":
			continue
		var raw_rec = intel[key]
		if not (raw_rec is Dictionary):
			continue
		var raw_state = raw_rec.get("state", DetectionState.UNKNOWN)
		var state_val := DetectionState.UNKNOWN
		if raw_state is int or raw_state is float:
			var int_st := int(raw_state)
			if int_st in [DetectionState.UNKNOWN, DetectionState.SUSPECTED, DetectionState.LOCATED]:
				state_val = int_st
		var node_id := str(raw_rec.get("last_known_node_id", "")).strip_edges()
		var turn := maxi(0, int(raw_rec.get("last_known_turn", 0)))
		var source := str(raw_rec.get("source", "none")).strip_edges()
		var heat_val := clampi(int(raw_rec.get("evidence_heat", 0)), 0, 10)

		if state_val != DetectionState.UNKNOWN:
			_faction_intelligence[fid] = {
				"faction_id": fid,
				"state": state_val,
				"last_known_node_id": node_id,
				"last_known_turn": turn,
				"source": source,
				"evidence_heat": heat_val,
			}
