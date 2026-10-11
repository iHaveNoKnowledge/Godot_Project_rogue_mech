extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN STRATEGIC THREAT QUERY VERIFICATION — Phase C4-B3.
##
## Tests the read-only CampaignStrategicThreat assessment layer:
##   - API shape, determinism, and safe failure policy
##   - Heat pressure policy (threshold-gated, never certainty alone)
##   - Detection freshness semantics (LOCATED/SUSPECTED/UNKNOWN effective
##     states, B2.1 suspicion-refresh pin, no promotion on timestamp alone)
##   - Anti-omniscience (no player-node reads, per-faction isolation)
##   - Strategic entities (forces/bases/territory/routes with verified
##     semantics: 1-hop reachability, destroyed-inert, unknown-neutral)
##   - Purity and isolation (snapshots, caller-mutation safety, no turn move)
##   - Boundary ladders (heat 2/3, intel ages 0/1/2/3, future-dated intel)
## ---------------------------------------------------------------------------

const CampaignStrategicThreat = preload("res://scripts/systems/campaign_strategic_threat.gd")
const CampaignStrategicHeat = preload("res://scripts/systems/campaign_strategic_heat.gd")
const CampaignStrategicDetection = preload("res://scripts/systems/campaign_strategic_detection.gd")
const CampaignNodeRegistry = preload("res://scripts/systems/campaign_node_registry.gd")
const CampaignForce = preload("res://scripts/systems/campaign_force.gd")
const CampaignBase = preload("res://scripts/systems/campaign_base.gd")
const CampaignTerritory = preload("res://scripts/systems/campaign_territory.gd")
const FactionSystem = preload("res://scripts/systems/faction_system.gd")
const CampaignTurnExecutive = preload("res://scripts/systems/campaign_turn_executive.gd")

var _checks := 0
var _fails := 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C4_B3_THREAT OK: %s" % message)
	else:
		_fails += 1
		printerr("C4_B3_THREAT FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN STRATEGIC THREAT VERIFY (Phase C4-B3) ---")
	print("======================================================================")

	_test_api_shape_and_determinism()
	_test_failure_policy()
	_test_heat_pressure_policy()
	_test_detection_freshness_ladder()
	_test_no_promotion_on_timestamp_alone()
	_test_anti_omniscience_and_isolation()
	_test_force_posture_semantics()
	_test_base_territory_route_semantics()
	_test_critical_conjunction()
	_test_observer_and_separation_semantics()
	_test_purity_and_isolation()
	_test_caller_mutation_safety()
	_test_boundary_conditions()

	print("----------------------------------------------------------------------")
	print("PHASE C4-B3 SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL STRATEGIC THREAT QUERY (C4-B3) CHECKS PASSED!")
	else:
		printerr("C4-B3 STRATEGIC THREAT VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _seed_empty_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignStrategicHeat.reset()
	CampaignStrategicDetection.reset()
	FactionSystem.reset_relations()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot")
	CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "city")
	CampaignNodeRegistry.register_route("node_s1_city_2_2", "node_s1_safehouse_2_3")
	CampaignNodeRegistry.register_route("node_s1_safehouse_2_3", "node_s1_fuel_depot_5_5")
	FactionSystem.set_relation("zeon", "federation", FactionSystem.Relation.HOSTILE)


func _codes(report: Dictionary) -> Array:
	var out: Array = []
	for c in report.get("contributors", []):
		out.append(str((c as Dictionary).get("code", "")))
	return out


func _test_api_shape_and_determinism() -> void:
	_seed_empty_world()
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(bool(r.get("ok", false)), "Valid assessment returns ok:true")
	_check(str(r.get("reason", "")) == "assessed", "Success reason is assessed")
	for key in ["node_id", "faction_id", "turn", "threat_level", "threat_name",
			"confidence", "contributors", "effective_intel"]:
		_check(r.has(key), "Report carries key: %s" % key)
	_check(str(r.get("node_id", "")) == "node_s1_city_2_2", "Report echoes node id")
	_check(str(r.get("faction_id", "")) == "federation", "Report echoes faction id")
	_check(int(r.get("turn", -1)) == 1, "Report echoes explicit turn")
	_check(str(r.get("threat_name", "")) == CampaignStrategicThreat.threat_name(int(r.get("threat_level", -1))), "threat_name matches threat_level")
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(JSON.stringify(r) == JSON.stringify(r2), "Repeated query is deterministic")
	_check(CampaignStrategicThreat.threat_name(0) == "secure", "Level 0 names secure")
	_check(CampaignStrategicThreat.threat_name(1) == "elevated", "Level 1 names elevated")
	_check(CampaignStrategicThreat.threat_name(2) == "interdicted", "Level 2 names interdicted")
	_check(CampaignStrategicThreat.threat_name(3) == "critical", "Level 3 names critical")
	_check(CampaignStrategicThreat.threat_name(99) == "unknown", "Invalid level names unknown")


func _test_failure_policy() -> void:
	_seed_empty_world()
	var e1 := CampaignStrategicThreat.get_node_threat("", "federation", 1)
	_check(not bool(e1.get("ok", true)) and str(e1.get("reason", "")) == "empty_node_id", "Empty node rejected")
	var e2 := CampaignStrategicThreat.get_node_threat("node_nope", "federation", 1)
	_check(not bool(e2.get("ok", true)) and str(e2.get("reason", "")) == "unknown_node", "Unknown node rejected")
	var e3 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "", 1)
	_check(not bool(e3.get("ok", true)) and str(e3.get("reason", "")) == "empty_faction_id", "Empty faction rejected")
	var e4 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", -5)
	_check(not bool(e4.get("ok", true)) and str(e4.get("reason", "")) == "negative_turn", "Negative turn rejected")
	var e5 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation")
	_check(bool(e5.get("ok", false)) and int(e5.get("turn", -1)) == CampaignTurnExecutive.get_turn(), "Default turn resolves to live campaign turn")
	for e in [e1, e2, e3, e4]:
		_check(int(e.get("threat_level", -1)) == 0 and (e.get("contributors", []) as Array).is_empty(), "Failures report secure level with no contributors")


func _test_heat_pressure_policy() -> void:
	_seed_empty_world()
	CampaignStrategicHeat.set_node_heat("node_s1_city_2_2", 2)
	var cold := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(not _codes(cold).has("residual_heat"), "Heat 2 contributes nothing")
	_check(int(cold.get("threat_level", -1)) == 0, "Heat 2 alone leaves SECURE")
	CampaignStrategicHeat.set_node_heat("node_s1_city_2_2", 3)
	var warm := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(_codes(warm).has("residual_heat"), "Heat 3 contributes residual_heat")
	_check(int(warm.get("threat_level", -1)) == 1, "Heat 3 raises ELEVATED")
	CampaignStrategicHeat.set_node_heat("node_s1_city_2_2", 10)
	var hot := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(int(hot.get("threat_level", -1)) == 1, "Heat 10 alone never exceeds ELEVATED (no certainty)")
	_check(str(hot.get("confidence", "")) == "unavailable", "Heat-only assessment has unavailable confidence")


func _test_detection_freshness_ladder() -> void:
	_seed_empty_world()
	# LOCATED@5, hostile force co-located: age 0 -> CRITICAL.
	CampaignForce.register_force("force_z1", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 5, "combat")
	var t5 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 5)
	_check(int(t5.get("threat_level", -1)) == 3, "Fresh LOCATED + hostile force is CRITICAL")
	_check(str(t5.get("confidence", "")) == "current", "Fresh LOCATED confidence is current")
	_check(_codes(t5).has("located_here"), "located_here contributor present")
	# Age 1 -> effective SUSPECTED: force still there -> INTERDICTED, not critical.
	var t6 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 6)
	_check(int(t6.get("threat_level", -1)) == 2, "Age-1 intel with hostile force is INTERDICTED, not critical")
	_check(str(t6.get("confidence", "")) == "uncertain", "Decayed intel confidence is uncertain")
	_check(not _codes(t6).has("located_here") and _codes(t6).has("suspected_here"), "Effective state demoted to suspected_here")
	# Age 3 -> UNKNOWN effective: force alone keeps INTERDICTED.
	var t8 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 8)
	_check(int(t8.get("threat_level", -1)) == 2, "Expired intel with hostile force stays INTERDICTED")
	_check(_codes(t8).has("intel_unknown"), "Expired intel reads intel_unknown")


func _test_no_promotion_on_timestamp_alone() -> void:
	_seed_empty_world()
	# LOCATED, recent timestamp, but NO hostile posture at the node.
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 5, "combat")
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 5)
	_check(int(r.get("threat_level", -1)) == 1, "Recent LOCATED without posture is ELEVATED, never CRITICAL")
	_check(_codes(r).has("located_no_hostile_posture"), "Contributor names the missing-posture case")
	# Suspicion-bumped clock (B2.1 pin): LOCATED@5 + suspicion@6 keeps node,
	# freshness now rides the bumped turn — still needs posture for CRITICAL.
	CampaignStrategicDetection.report_suspicion("federation", "node_s1_safehouse_2_3", 6, 5, "trace")
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 6)
	_check(int(r2.get("threat_level", -1)) == 1, "Bumped clock without posture is still ELEVATED")
	_check(str(CampaignStrategicDetection.get_last_known_node_id("federation")) == "node_s1_city_2_2", "Suspicion preserved the located node (B2.1 policy)")


func _test_anti_omniscience_and_isolation() -> void:
	_seed_empty_world()
	GlobalData.current_campaign_player_node_id = "node_s1_city_2_2"
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(int(r.get("threat_level", -1)) == 0, "True player position alone creates zero threat")
	_check(_codes(r) == ["intel_unknown"], "Only contributor is intel_unknown")
	GlobalData.current_campaign_player_node_id = "node_s1_fuel_depot_5_5"
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 1, "combat")
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(int(r2.get("threat_level", -1)) == 1, "Intel-driven result unaffected by true position elsewhere")
	# Federation intel must not leak into zeon's assessment.
	var rz := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "zeon", 1)
	_check(int(rz.get("threat_level", -1)) == 0, "Zeon result unaffected by federation intel")
	_check(str(rz.get("confidence", "")) == "unavailable", "Zeon confidence unavailable without own intel")
	GlobalData.current_campaign_player_node_id = ""


func _test_force_posture_semantics() -> void:
	_seed_empty_world()
	# Distant force (2 hops: city -> safehouse -> depot) contributes nothing.
	CampaignForce.register_force("force_far", "PATROL", "zeon", "node_s1_fuel_depot_5_5", "", 3, 10)
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(not _codes(r).has("hostile_force_present") and not _codes(r).has("hostile_force_adjacent"), "Two-hop force contributes nothing")
	_check(int(r.get("threat_level", -1)) == 0, "Distant force leaves SECURE")
	# Adjacent hostile force (1 hop) contributes at severity 1.
	CampaignForce.register_force("force_near", "PATROL", "zeon", "node_s1_safehouse_2_3", "", 3, 10)
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(_codes(r2).has("hostile_force_adjacent"), "One-hop hostile force contributes")
	_check(int(r2.get("threat_level", -1)) == 1, "Adjacent hostile force raises ELEVATED")
	# Reverse direction: the same edge is read from the far side (undirected routes).
	var r2b := CampaignStrategicThreat.get_node_threat("node_s1_fuel_depot_5_5", "federation", 1)
	var reverse_hit := false
	for c in r2b.get("contributors", []):
		if str((c as Dictionary).get("code", "")) == "hostile_force_adjacent":
			for f in (c as Dictionary).get("detail", {}).get("forces", []):
				if str((f as Dictionary).get("force_id", "")) == "force_near" \
						and str((f as Dictionary).get("node_id", "")) == "node_s1_safehouse_2_3":
					reverse_hit = true
	_check(_codes(r2b).has("hostile_force_adjacent"), "Edge readable from the far side")
	_check(reverse_hit, "Reverse adjacency names force_near at safehouse")
	# Co-located hostile force contributes at severity 2.
	CampaignForce.register_force("force_here", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	var r3 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(_codes(r3).has("hostile_force_present"), "Co-located hostile force contributes")
	_check(int(r3.get("threat_level", -1)) == 2, "Co-located hostile force raises INTERDICTED")
	# Destroyed hostile force is inert.
	CampaignForce.set_state("force_here", CampaignForce.ForceState.DESTROYED)
	var r4 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(not _codes(r4).has("hostile_force_present"), "Destroyed hostile force contributes nothing")
	# Unattributed force never reads as hostile.
	CampaignForce.register_force("force_myst", "SCAVENGER", "", "node_s1_city_2_2", "", 1, 5)
	CampaignForce.set_state("force_near", CampaignForce.ForceState.DESTROYED)
	var r5 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(int(r5.get("threat_level", -1)) == 0, "Unattributed force never silently hostile")
	# DISABLED hostile force still present (provisional: impaired but extant).
	CampaignForce.register_force("force_deg", "PATROL", "zeon", "node_s1_city_9_9", "", 3, 10)
	CampaignForce.set_state("force_deg", CampaignForce.ForceState.DISABLED)
	var r6 := CampaignStrategicThreat.get_node_threat("node_s1_city_9_9", "federation", 1)
	_check(int(r6.get("threat_level", -1)) == 2, "DISABLED hostile force still counts as present (provisional)")


func _test_base_territory_route_semantics() -> void:
	_seed_empty_world()
	# Hostile-controlled base at the node.
	CampaignBase.register_base("base_z", "node_s1_city_2_2", "OUTPOST", "zeon", "")
	CampaignBase.register_base("base_f", "node_s1_safehouse_2_3", "OUTPOST", "federation", "")
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(_codes(r).has("hostile_base_present"), "Hostile base contributes")
	_check(int(r.get("threat_level", -1)) == 2, "Hostile base raises INTERDICTED")
	var rs := CampaignStrategicThreat.get_node_threat("node_s1_safehouse_2_3", "federation", 1)
	_check(not _codes(rs).has("hostile_base_present") and int(rs.get("threat_level", -1)) == 0, "Own-faction base contributes nothing")
	# Destroyed hostile base is inert (also filtered by get_base_at_node itself).
	CampaignBase.set_state("base_z", CampaignBase.BaseState.DESTROYED)
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(not _codes(r2).has("hostile_base_present"), "Destroyed hostile base contributes nothing")
	# Hostile-controlled covering territory (node's own, then neighbor-only).
	CampaignTerritory.register_territory("terr_home", ["node_s1_city_2_2"])
	CampaignTerritory.set_controlled("terr_home", "zeon")
	var r3 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(_codes(r3).has("adjacent_hostile_territory"), "Hostile covering territory contributes")
	_check(int(r3.get("threat_level", -1)) == 1, "Hostile territory caps at ELEVATED")
	CampaignTerritory.register_territory("terr_near", ["node_s1_safehouse_2_3"])
	CampaignTerritory.set_controlled("terr_near", "zeon")
	var r4 := CampaignStrategicThreat.get_node_threat("node_s1_fuel_depot_5_5", "federation", 1)
	_check(_codes(r4).has("adjacent_hostile_territory"), "Neighbor-only hostile territory contributes")
	# Territory covering only a 2-hop node is out of scope.
	CampaignTerritory.register_territory("terr_far", ["node_s1_city_9_9"])
	CampaignTerritory.set_controlled("terr_far", "zeon")
	var r5 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	var far_leak := false
	for c in r5.get("contributors", []):
		var d: Dictionary = (c as Dictionary).get("detail", {})
		if str(d.get("territory_ids", "")).contains("terr_far") or str(d).contains("terr_far"):
			far_leak = true
	_check(not far_leak, "Two-hop territory never contributes")
	# Own-controlled covering territory contributes nothing.
	CampaignTerritory.register_territory("terr_own", ["node_s1_city_2_2"])
	CampaignTerritory.set_controlled("terr_own", "federation")
	var r6 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	var tids: Array = []
	for c in r6.get("contributors", []):
		if str((c as Dictionary).get("code", "")) == "adjacent_hostile_territory":
			tids = (c as Dictionary).get("detail", {}).get("territory_ids", [])
	tids.sort()
	_check(tids == ["terr_home", "terr_near"], "Only hostile-controlled territories listed (own excluded)")


func _test_critical_conjunction() -> void:
	_seed_empty_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 4, "combat")
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 4)
	_check(int(r.get("threat_level", -1)) == 3, "Co-located hostile force + fresh LOCATED is CRITICAL")
	_check(str(r.get("confidence", "")) == "current", "CRITICAL confidence is current")
	var sev := -1
	for c in r.get("contributors", []):
		if str((c as Dictionary).get("code", "")) == "located_here":
			sev = int((c as Dictionary).get("severity", -1))
	_check(sev == 3, "located_here carries severity 3 inside the conjunction")
	# SUSPECTED (not LOCATED) with a co-located hostile force caps at INTERDICTED.
	CampaignStrategicDetection.reset()
	CampaignStrategicDetection.report_suspicion("federation", "node_s1_city_2_2", 4, 5, "trace")
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 4)
	_check(int(r2.get("threat_level", -1)) == 2, "SUSPECTED + hostile force caps at INTERDICTED")
	_check(_codes(r2).has("suspected_here"), "suspected_here contributor present, never certainty")


func _test_observer_and_separation_semantics() -> void:
	_seed_empty_world()
	# Hostile posture with UNKNOWN intel: physical pressure WITHOUT knowledge.
	CampaignForce.register_force("force_z1", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(int(r.get("threat_level", -1)) == 2, "Hostile force + UNKNOWN intel is INTERDICTED (pressure, not knowledge)")
	_check(str(r.get("confidence", "")) == "unavailable", "Confidence honestly reports unavailable intel")
	_check(_codes(r) == ["hostile_force_present", "intel_unknown"], "Physical and intel facts sit side by side, unmixed")
	# Unregistered observer faction: relations default NEUTRAL, never hostile.
	var rn := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "nomads", 1)
	_check(int(rn.get("threat_level", -1)) == 0, "Unregistered observer reads zero threat (no silent hostility)")
	_check(str(rn.get("confidence", "")) == "unavailable", "Unregistered observer confidence unavailable")
	# Explicit ALLIED override: allied co-located force contributes nothing.
	FactionSystem.set_relation("outland", "federation", FactionSystem.Relation.ALLIED)
	CampaignForce.register_force("force_o1", "SCAVENGER", "outland", "node_s1_city_2_2", "", 2, 6)
	var ra := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check(int(ra.get("threat_level", -1)) == 2, "Level stays INTERDICTED from the zeon force only (allied force adds nothing)")
	var allied_leak := false
	for c in ra.get("contributors", []):
		if str((c as Dictionary).get("detail", {})).contains("force_o1"):
			allied_leak = true
	_check(not allied_leak, "Allied force id appears in no contributor detail")
	FactionSystem.reset_relations()


func _test_purity_and_isolation() -> void:
	_seed_empty_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignBase.register_base("base_z", "node_s1_city_2_2", "OUTPOST", "zeon", "")
	CampaignStrategicHeat.set_node_heat("node_s1_city_2_2", 6)
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 2, "combat")
	GlobalData.current_campaign_player_node_id = "node_s1_city_2_2"
	var turn_before := CampaignTurnExecutive.get_turn()
	var snap := {
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"heat": JSON.stringify(CampaignStrategicHeat.serialize()),
		"detection": JSON.stringify(CampaignStrategicDetection.serialize()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
	}
	var r := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 2)
	_check(bool(r.get("ok", false)), "Assessment runs on a loaded world")
	_check(JSON.stringify(CampaignForce.get_forces()) == snap["forces"], "Forces untouched by query")
	_check(JSON.stringify(CampaignStrategicHeat.serialize()) == snap["heat"], "Heat untouched by query")
	_check(JSON.stringify(CampaignStrategicDetection.serialize()) == snap["detection"], "Detection untouched by query")
	_check(JSON.stringify(CampaignBase.get_bases()) == snap["bases"], "Bases untouched by query")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "Campaign turn untouched by query")
	_check(GlobalData.current_campaign_player_node_id == "node_s1_city_2_2", "Player node untouched by query")
	GlobalData.current_campaign_player_node_id = ""


func _test_caller_mutation_safety() -> void:
	_seed_empty_world()
	CampaignForce.register_force("force_z1", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 1, "combat")
	var r1 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	(r1.get("contributors", []) as Array).clear()
	(r1.get("effective_intel", {}) as Dictionary)["state"] = "tampered"
	(r1 as Dictionary)["threat_level"] = 99
	var r2 := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 1)
	_check((r2.get("contributors", []) as Array).size() == 2, "Caller-cleared contributors do not persist")
	_check(str((r2.get("effective_intel", {}) as Dictionary).get("state", "")) == "located", "Caller-tampered intel does not persist")
	_check(int(r2.get("threat_level", -1)) == 3, "Caller-tampered level does not persist")


func _test_boundary_conditions() -> void:
	_seed_empty_world()
	# SUSPECTED ladder across ages 0..3 with no posture: 1/1/1/0.
	CampaignStrategicDetection.report_suspicion("federation", "node_s1_city_2_2", 5, 4, "trace")
	_check(int(CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 5).get("threat_level", -1)) == 1, "SUSPECTED age 0 is ELEVATED")
	_check(int(CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 7).get("threat_level", -1)) == 1, "SUSPECTED age 2 is ELEVATED")
	_check(int(CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 8).get("threat_level", -1)) == 0, "SUSPECTED age 3 expires to SECURE")
	# Future-dated intel reads as UNKNOWN at the earlier query turn.
	CampaignStrategicDetection.reset()
	CampaignStrategicDetection.report_location("federation", "node_s1_city_2_2", 10, "combat")
	var rf := CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "federation", 5)
	_check(str((rf.get("effective_intel", {}) as Dictionary).get("state", "")) == "unknown", "Future-dated intel reads UNKNOWN")
	_check(int(rf.get("threat_level", -1)) == 0, "Future-dated intel creates no pressure")
	# Missing intel is explicit.
	_check(_codes(CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "outland", 5)).has("intel_unknown"), "No record reads intel_unknown")
	_check(str(CampaignStrategicThreat.get_node_threat("node_s1_city_2_2", "outland", 5).get("confidence", "")) == "unavailable", "No record confidence is unavailable")
	CampaignStrategicDetection.reset()
	CampaignStrategicHeat.reset()
	FactionSystem.reset_relations()
	GlobalData.reset_run_data()
