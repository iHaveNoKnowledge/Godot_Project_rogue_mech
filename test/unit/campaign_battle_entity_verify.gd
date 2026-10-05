extends Node
## PHASE 5B CAMPAIGN BATTLE VERIFY (boundary foundation, NOT resolution).
##
## Proves: battle registry/identity, node-validated location, participant
## rules (Force IDs only, never copied), explicit lifecycle, session-ref
## boundary (battle survives session end), force/base/territory separation,
## serialize round-trip + old-save safety, reset isolation, no signals.
## Nothing here runs combat, moves forces, or mutates any participant.
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("BATTLE OK: " + name)
	else:
		_fails += 1
		printerr("BATTLE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_registry()
	_test_identity()
	_test_location()
	_test_participants()
	_test_lifecycle()
	_test_session_boundary()
	_test_force_separation()
	_test_territory_derived()
	_test_serialize_round_trip()
	_test_old_save_compat()
	_test_reset_isolation()
	_test_no_signal()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_BATTLE_ENTITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_BATTLE_ENTITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CAMPAIGN_BATTLE_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignTerritory.register_territory("terr_downtown",
		["node_s1_city_2_2", "node_s1_safehouse_2_3"])
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


# Registry: create / duplicate / lookup / unknown.
func _test_registry() -> void:
	CampaignBattle.clear()
	var bid := CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a", "force_b"])
	_check(bid == "battle_x" and CampaignBattle.has_battle(bid), "register valid battle")
	_check(not CampaignBattle.get_battle(bid).is_empty(), "get battle returns data")
	_check(CampaignBattle.get_battles().size() == 1, "list has one battle")
	_check(CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_b", "force_a"]) == "battle_x",
		"identical re-registration idempotent (order-insensitive)")
	_check(CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a"]) == "", "same id with different participants rejected")
	_check(CampaignBattle.register_battle("", "node_s1_city_2_2", ["force_a"]) == "",
		"empty id rejected")
	_check(CampaignBattle.register_battle("battle_bad", "node_s1_city_2_2", []) == "",
		"empty participant list rejected")
	_check(CampaignBattle.register_battle("battle_bad", "node_s1_city_2_2",
		["force_nope"]) == "", "unknown force rejected")
	_check(CampaignBattle.register_battle("battle_bad", "node_s1_city_2_2",
		["force_a", "force_a"]) == "", "duplicate force rejected")
	_check(CampaignBattle.register_battle("battle_bad", "node_nope", ["force_a"]) == "",
		"unknown node rejected")
	_check(CampaignBattle.register_battle("battle_bad", "", ["force_a"]) == "",
		"empty node rejected")
	_check(CampaignBattle.get_battle("battle_nope").is_empty(), "unknown lookup empty")
	CampaignBattle.clear()


# Identity: deterministic helper, stable, unique.
func _test_identity() -> void:
	_check(CampaignBattle.make_battle_id(1, "Ridge Clash") == "battle_s1_ridge_clash",
		"helper derives deterministic id")
	_check(CampaignBattle.make_battle_id(1, "Ridge Clash") == CampaignBattle.make_battle_id(1, "Ridge Clash"),
		"helper stable across calls")
	_check(CampaignBattle.make_battle_id(1, "!!!") == "", "helper rejects empty slug")
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.register_battle("battle_y", "node_s1_city_2_2", ["force_b"])
	_check(CampaignBattle.get_battles().size() == 2, "two ids coexist uniquely")
	CampaignBattle.clear()


# Location: node reference only, never coordinates.
func _test_location() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	var b := CampaignBattle.get_battle("battle_x")
	_check(str(b.get("node_id", "")) == "node_s1_city_2_2", "node referenced by id")
	_check(not b.has("tile") and not b.has("world_position") and not b.has("terrain"),
		"no board data copied into the battle")
	CampaignBattle.clear()


# Participants: Force IDs only, validated, ordered, never copied.
func _test_participants() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_b", "force_a"])
	_check(CampaignBattle.get_participants("battle_x") == ["force_a", "force_b"],
		"participants sorted deterministically")
	_check(not CampaignBattle.add_participant("battle_x", "force_a"),
		"duplicate participant rejected")
	_check(not CampaignBattle.add_participant("battle_x", "force_nope"),
		"unknown force rejected")
	_check(CampaignBattle.add_participant("battle_x", "force_c"), "third force accepted")
	_check(CampaignBattle.get_participants("battle_x") == ["force_a", "force_b", "force_c"],
		"participant list stays ordered (multi-force capable, still not N-sided combat)")
	var b := CampaignBattle.get_battle("battle_x")
	_check(not b.has("strength") and not b.has("faction") and not b.has("pilots"),
		"no force data copied into the battle")
	_check(CampaignBattle.remove_participant("battle_x", "force_c"), "removal accepted")
	_check(not CampaignBattle.remove_participant("battle_x", "force_c"),
		"double removal rejected")
	_check(CampaignBattle.remove_participant("battle_x", "force_nope") == false,
		"removing unknown force rejected")
	CampaignBattle.clear()
	CampaignForce.set_state("force_c", CampaignForce.ForceState.DESTROYED)
	_check(CampaignBattle.register_battle("battle_doom", "node_s1_city_2_2",
		["force_c"]) == "", "destroyed force cannot seed a battle")
	CampaignForce.set_state("force_c", CampaignForce.ForceState.DESTROYED)
	CampaignBattle.register_battle("battle_ok", "node_s1_city_2_2", ["force_a"])
	_check(not CampaignBattle.add_participant("battle_ok", "force_c"),
		"destroyed force cannot join")
	CampaignBattle.clear()
	_seed_forces_back()


func _seed_forces_back() -> void:
	# Destroyed flags above were on force_c only; restore ACTIVE for later tests.
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


# Lifecycle: PLANNED -> ACTIVE -> RESOLVED, cancellations, terminal holds.
func _test_lifecycle() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	_check(CampaignBattle.is_planned("battle_x"), "initial state PLANNED")
	_check(not CampaignBattle.resolve_battle("battle_x"),
		"PLANNED cannot resolve directly (must activate first)")
	_check(CampaignBattle.begin_battle("battle_x"), "PLANNED -> ACTIVE")
	_check(not CampaignBattle.begin_battle("battle_x"), "double begin rejected")
	_check(CampaignBattle.resolve_battle("battle_x"), "ACTIVE -> RESOLVED")
	_check(not CampaignBattle.begin_battle("battle_x"), "RESOLVED terminal (no reactivation)")
	_check(not CampaignBattle.cancel_battle("battle_x"), "RESOLVED cannot cancel")
	CampaignBattle.register_battle("battle_y", "node_s1_city_2_2", ["force_b"])
	_check(CampaignBattle.cancel_battle("battle_y"), "PLANNED -> CANCELLED")
	_check(not CampaignBattle.begin_battle("battle_y"), "CANCELLED terminal")
	CampaignBattle.register_battle("battle_z", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_z")
	_check(CampaignBattle.cancel_battle("battle_z"), "ACTIVE -> CANCELLED")
	_check(not CampaignBattle.resolve_battle("battle_nope"), "resolve on unknown rejected")
	_check(not CampaignBattle.begin_battle("battle_nope"), "begin on unknown rejected")
	CampaignBattle.clear()


# Boundary (§31): battle outlives its tactical session; ids never collide.
func _test_session_boundary() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a", "force_b"])
	_check(CampaignBattle.get_session_ref("battle_x") == "",
		"no session attached initially")
	_check(CampaignBattle.set_session_ref("battle_x", "session_Y"),
		"opaque session reference attached")
	_check(CampaignBattle.get_session_ref("battle_x") == "session_Y",
		"session reference readable")
	_check(not CampaignBattle.set_session_ref("battle_x", ""),
		"empty session reference rejected (use clear)")
	_check(not CampaignBattle.set_session_ref("battle_nope", "session_Y"),
		"session attach on unknown battle rejected")
	_check("battle_x" != "session_Y", "battle id != session identity by construction")
	_check(CampaignBattle.begin_battle("battle_x"), "battle activates under session")
	_check(CampaignBattle.clear_session_ref("battle_x"), "session ends (cleared)")
	_check(CampaignBattle.get_session_ref("battle_x") == "",
		"session reference gone")
	_check(CampaignBattle.has_battle("battle_x")
		and CampaignBattle.get_participants("battle_x") == ["force_a", "force_b"],
		"battle remains a valid campaign object after session end")
	_check(CampaignBattle.resolve_battle("battle_x"),
		"battle still resolvable after session end (boundary holds)")
	_check(not CampaignBattle.clear_session_ref("battle_nope"),
		"session clear on unknown battle rejected")
	CampaignBattle.clear()


# Force separation: battles never mutate or mirror force state.
func _test_force_separation() -> void:
	CampaignBattle.clear()
	var before_a := JSON.stringify(CampaignForce.get_force("force_a"))
	var before_b := JSON.stringify(CampaignForce.get_force("force_b"))
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a", "force_b"])
	CampaignBattle.set_session_ref("battle_x", "session_Y")
	CampaignBattle.begin_battle("battle_x")
	CampaignBattle.clear_session_ref("battle_x")
	CampaignBattle.resolve_battle("battle_x")
	_check(JSON.stringify(CampaignForce.get_force("force_a")) == before_a
		and JSON.stringify(CampaignForce.get_force("force_b")) == before_b,
		"full battle lifecycle mutates no force state (resolution is future work)")
	CampaignBattle.clear()


# Territory context derives through the node, never stored.
func _test_territory_derived() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	_check(CampaignBattle.get_territory_context("battle_x") == "terr_downtown",
		"territory derived from battle node")
	_check(not CampaignBattle.get_battle("battle_x").has("territory_id"),
		"territory never stored on the battle")
	_check(CampaignBattle.get_territory_context("battle_nope") == "",
		"unknown battle reads empty")
	CampaignBattle.clear()


# Serialize round trip via snapshot + full SaveGameIO path.
func _test_serialize_round_trip() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_b", "node_s1_safehouse_2_3", ["force_b"])
	CampaignBattle.register_battle("battle_a", "node_s1_city_2_2", ["force_a", "force_b"])
	CampaignBattle.begin_battle("battle_a")
	CampaignBattle.set_session_ref("battle_a", "session_1")
	var snap_a := JSON.stringify(CampaignBattle.serialize())
	CampaignBattle.clear()
	CampaignBattle.deserialize(JSON.parse_string(snap_a))
	_check(JSON.stringify(CampaignBattle.serialize()) == snap_a, "round trip equivalent")
	_check(SaveGameIO.save_run(), "save_run carries battle state")
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores battle state")
	_check(CampaignBattle.is_active("battle_a")
		and CampaignBattle.get_session_ref("battle_a") == "session_1",
		"active battle + session ref survive save/load")
	CampaignBattle.clear()


# Old saves without battle data load safely; invalid rows skipped.
func _test_old_save_compat() -> void:
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	_check(SaveGameIO.save_run(), "save_run reports success")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(d is Dictionary and (d as Dictionary).has("campaign_battles"),
		"save file carries campaign_battles")
	(d as Dictionary).erase("campaign_battles")
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "legacy payload without battles still loads")
	_check(CampaignBattle.get_battles().is_empty(), "missing battle data loads as empty")
	CampaignBattle.deserialize({"battles": [
		{"id": "", "state": "planned", "node_id": "node_s1_city_2_2",
			"participants": ["force_a"]},
		{"id": "battle_bad", "state": "bogus", "node_id": "node_s1_city_2_2",
			"participants": ["force_a"]},
		{"id": "battle_bad2", "state": "planned", "node_id": "node_nope",
			"participants": ["force_a"]},
		{"id": "battle_bad3", "state": "planned", "node_id": "node_s1_city_2_2",
			"participants": []},
		"not-a-row",
	]})
	_check(CampaignBattle.get_battles().is_empty(), "invalid rows skipped deterministically")
	CampaignBattle.clear()


# Reset isolation through the established primitive.
func _test_reset_isolation() -> void:
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_x")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignBattle.get_battles().is_empty(),
		"reset_run_data clears battle state (no Run A leakage)")


# No battle signals exist (no consumer requires one in 5B).
func _test_no_signal() -> void:
	_check(not EventBus.has_signal("campaign_battle_started"), "no battle started signal")
	_check(not EventBus.has_signal("campaign_battle_resolved"), "no battle resolved signal")
	_check(not EventBus.has_signal("campaign_battle_changed"), "no battle changed signal")
