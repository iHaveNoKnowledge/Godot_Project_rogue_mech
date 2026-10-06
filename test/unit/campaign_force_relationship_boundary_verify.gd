extends Node
## PHASE 5Q FORCE-TO-FORCE RELATIONSHIP / HOSTILITY BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): Force-to-Force relationship is NOT YET
## MODELED. No relation/hostility/target field exists on CampaignForce
## (record is exactly the 8 locked keys); no relation manager, matrix, or
## targeting authority exists; the faction relation matrix stays
## FACTION-LEVEL ONLY (never consumed for force pairs — the only
## get_relation callers are tests). Same-node, same-faction, cross-faction,
## territory, and base contact create nothing; battles store participant
## IDs with no attacker/defender/ally/enemy sides (multi-force rosters are
## identity lists, not side counts); no automatic battle bridge exists.
## Patrol stance labels and tactical targeting stay in their own domains.
## User save backed up/restored.

const RELATION_LIKE_KEYS := ["relation", "relationship", "relations",
	"hostility", "hostile", "enemy", "ally", "allied", "friendly",
	"neutral", "opponent", "target", "target_force", "current_enemy",
	"preferred_target", "threat", "threat_level", "aggression",
	"side", "team", "support", "escort", "opposes"]

const FORCE_KNOWN_KEYS := ["id", "force_type", "state", "faction",
	"node_id", "base_id", "unit_count", "strength"]

const BATTLE_KNOWN_KEYS := ["id", "state", "node_id", "participants",
	"session_ref"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RELATION OK: " + name)
	else:
		_fails += 1
		printerr("RELATION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_no_relation_fields()
	_test_faction_relation_not_force_relation()
	_test_same_faction_no_implicit_relation()
	_test_cross_faction_no_implicit_relation()
	_test_same_node_no_hostility_no_battle()
	_test_territory_base_no_hostility()
	_test_battle_has_no_sides()
	_test_patrol_tactical_stay_separate()
	_test_boundaries_hold()
	_test_turn_save_reset_clean()
	_test_no_relation_authority()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_RELATIONSHIP_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_RELATIONSHIP_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_RELATIONSHIP_BOUNDARY_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignTerritory.register_territory("terr_downtown",
		["node_s1_city_2_2", "node_s1_safehouse_2_3"])
	CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "OUTPOST",
		"federation", "terr_downtown")
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


func _has_relation_like_key(d: Dictionary) -> bool:
	for k in RELATION_LIKE_KEYS:
		if d.has(k):
			return true
	return false


func _check_exact_force_schema(fid: String, label: String) -> void:
	var f: Dictionary = CampaignForce.get_force(fid)
	_check(not _has_relation_like_key(f), "no relation-like field on %s (%s)" % [fid, label])
	var keys: Array = (f as Dictionary).keys()
	keys.sort()
	var want: Array = FORCE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "record exactly the 8 locked keys (%s)" % label)


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# 1-4. No relation/target/hostility fields; faction stays current affiliation.
func _test_no_relation_fields() -> void:
	_check_exact_force_schema("force_a", "seeded zeon force")
	_check_exact_force_schema("force_b", "seeded outland force")
	_check_exact_force_schema("force_c", "seeded unattributed force")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"faction remains current affiliation only (no relation derived)")


# 5-6. Matrix is faction-level; even an explicit HOSTILE override stores
# nothing on either force.
func _test_faction_relation_not_force_relation() -> void:
	_check(FactionSystem.set_relation("zeon", "federation",
		FactionSystem.Relation.HOSTILE), "HOSTILE override set at faction level")
	_check(FactionSystem.get_relation("zeon", "federation")
		== FactionSystem.Relation.HOSTILE, "matrix reads HOSTILE (faction-level fact)")
	_check_exact_force_schema("force_a", "under HOSTILE matrix")
	_check_exact_force_schema("force_c", "under HOSTILE matrix")
	FactionSystem.reset_relations()


# 7. Same-faction forces gain no implicit relation state.
func _test_same_faction_no_implicit_relation() -> void:
	_check(CampaignForce.register_force("force_d", "CONVOY", "zeon",
		"node_s1_city_2_2", "", 1, 5) == "force_d", "second zeon force registers")
	_check(CampaignForce.set_node("force_d", "node_s1_city_2_2"), "same node as force_a")
	_check(CampaignBattle.register_battle("battle_same", "node_s1_city_2_2",
		["force_a", "force_d"]) == "battle_same", "same-faction pair battles together")
	_check_exact_force_schema("force_a", "same-faction contact")
	_check_exact_force_schema("force_d", "same-faction contact")
	CampaignBattle.clear()
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


# 8. Cross-faction forces gain no implicit relation state either.
func _test_cross_faction_no_implicit_relation() -> void:
	_check(CampaignBattle.register_battle("battle_cross", "node_s1_city_2_2",
		["force_a", "force_b", "force_c"]) == "battle_cross",
		"three-faction roster registers (identity list, not 3 teams)")
	_check(CampaignBattle.get_participants("battle_cross") == ["force_a", "force_b", "force_c"],
		"roster stored as sorted ids (no side inference)")
	_check_exact_force_schema("force_a", "cross-faction contact")
	_check_exact_force_schema("force_b", "cross-faction contact")
	_check_exact_force_schema("force_c", "cross-faction contact")
	CampaignBattle.clear()


# 9-10. Co-location creates neither hostility nor battles, even under a
# HOSTILE matrix and across turns.
func _test_same_node_no_hostility_no_battle() -> void:
	FactionSystem.set_relation("zeon", "outland", FactionSystem.Relation.HOSTILE)
	_check(CampaignForce.set_node("force_b", "node_s1_city_2_2"), "outland force joins zeon node")
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2") == ["force_a", "force_b"],
		"hostile-matrix forces coexist (0..N holds)")
	_check_exact_force_schema("force_a", "hostile co-location")
	_check_exact_force_schema("force_b", "hostile co-location")
	CampaignTurnExecutive.advance_campaign_turn("relation_probe", {"day_boundary": true})
	_check(CampaignBattle.get_battles().is_empty(),
		"no automatic battle from hostile co-location (creation stays manual)")
	_check_exact_force_schema("force_a", "after hostile turn")
	FactionSystem.reset_relations()
	CampaignForce.set_node("force_b", "node_s1_safehouse_2_3")


# 11-12. Territory control and base attachment create no hostility/alliance.
func _test_territory_base_no_hostility() -> void:
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	_check(CampaignForce.get_territory_context("force_a") == "terr_downtown",
		"territory context derives")
	_check_exact_force_schema("force_a", "inside territory")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before,
		"presence writes no territory state (no attack/defense)")
	_check(CampaignForce.set_base("force_b", "base_alpha"), "outland force attaches to base")
	_check_exact_force_schema("force_b", "attached to foreign-controller base")
	_check(str(CampaignBase.get_base("base_alpha").get("controller", "")) == "federation",
		"attachment creates no alliance/takeover (controller intact)")
	CampaignForce.set_base("force_b", "")


# 13-14. Participants carry no side semantics through the full lifecycle.
func _test_battle_has_no_sides() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_ns", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_ns", "pair registers")
	var b: Dictionary = CampaignBattle.get_battle("battle_ns")
	_check(not _has_relation_like_key(b), "battle record carries no side field")
	var keys: Array = b.keys()
	keys.sort()
	var want: Array = BATTLE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "battle schema exactly the 5 locked keys (no attackers/defenders)")
	CampaignBattle.begin_battle("battle_ns")
	CampaignBattle.resolve_battle("battle_ns")
	_check_exact_force_schema("force_a", "after lifecycle (no side imprint)")
	_check_exact_force_schema("force_b", "after lifecycle (no side imprint)")
	_check(not _has_relation_like_key(CampaignBattle.get_battle("battle_ns")),
		"resolved battle still carries no side field")
	CampaignBattle.clear()


# 15. Patrol stance and tactical targeting stay in their own domains.
func _test_patrol_tactical_stay_separate() -> void:
	var patrols_before: int = GlobalData.board.board_patrols.size()
	CampaignForce.set_node("force_a", "node_s1_safehouse_2_3")
	CampaignBattle.register_battle("battle_pt", "node_s1_city_2_2", ["force_a", "force_b"])
	_check(GlobalData.board.board_patrols.size() == patrols_before,
		"force contact churns no patrol hostility")
	CampaignBattle.clear()
	CampaignForce.set_node("force_a", "node_s1_city_2_2")
	_check(not _code_of("res://scripts/systems/patrol_system.gd").contains("CampaignForce"),
		"patrol code never references forces (no stance bridge)")


# 16-19. 5M/5N/5O/5P boundaries hold on every record.
func _test_boundaries_hold() -> void:
	for f in CampaignForce.get_forces():
		var d: Dictionary = f
		_check(not d.has("detected") and not d.has("intel")
			and not d.has("order") and not d.has("mission")
			and not d.has("supply") and not d.has("supply_status")
			and not _has_relation_like_key(d)
			and int(d.get("unit_count", -1)) >= 0
			and int(d.get("strength", -1)) >= 0,
			"force %s keeps 5M/5N/5O/5P absence" % str(d.get("id", "")))


# 20-22. Turns, saves, and resets create/store/leave no relation state.
func _test_turn_save_reset_clean() -> void:
	var before := JSON.stringify(CampaignForce.get_forces())
	CampaignTurnExecutive.advance_campaign_turn("relation_probe2", {})
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"turns create no relationships")
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	for row in ((d as Dictionary).get("forces", {}) as Dictionary).get("forces", []):
		if _has_relation_like_key(row):
			clean = false
	_check(clean, "saved force rows carry no relation field (no relation persistence)")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces")
	_check_exact_force_schema("force_a", "after load")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 3, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	CampaignBattle.clear()


# 23-25. Negative tests: no relation authority in code or filenames.
func _test_no_relation_authority() -> void:
	var force_code := _code_of("res://scripts/systems/campaign_force.gd").to_lower()
	var clean := true
	for token in ["relation", "hostil", "target_force", "current_enemy",
			"preferred_target", "threat", "aggress", "escort", "oppos",
			"attacker", "defender"]:
		if force_code.contains(token):
			clean = false
	_check(clean, "force source has no relation concept (code, not comments)")
	var battle_code := _code_of("res://scripts/systems/campaign_battle.gd").to_lower()
	_check(not battle_code.contains("attacker") and not battle_code.contains("defender")
		and not battle_code.contains("target_force") and not battle_code.contains("hostil"),
		"battle source assumes no sides (code, not comments)")
	var found_manager := false
	for dir_path in ["res://scripts/systems", "res://scripts/board", "res://scripts/war"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				var n := entry.to_lower()
				if n.contains("force_relation") or n.contains("relation_manager") \
						or n.contains("diplomacy") or n.contains("hostility") \
						or n.contains("targeting_system") or n.contains("force_target"):
					found_manager = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_manager, "no relation/diplomacy/targeting manager file exists")
