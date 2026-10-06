extends Node
## PHASE 5G FORCE PRESENCE VERIFY (pure derived queries, no movement).
##
## Proves: empty/unknown node semantics, single + multi-force presence
## (0..N incl. cross-faction coexistence), deterministic ordering, node
## scoping, off-board exclusion, destroyed/disabled semantics across both
## queries, save/load + reset behavior, and isolation (patrol/hangar/battle/
## base/territory churn never affects presence). No movement, no cache, no
## second registry. User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PRESENCE OK: " + name)
	else:
		_fails += 1
		printerr("PRESENCE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_empty_unknown()
	_test_single_multiple()
	_test_determinism_scoping()
	_test_offboard()
	_test_destroyed_disabled()
	_test_save_reset()
	_test_isolation()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FORCE_PRESENCE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FORCE_PRESENCE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_PRESENCE_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)


# Empty valid node -> []; unknown node -> [] (documented, no fabrication).
func _test_empty_unknown() -> void:
	_check(CampaignForce.get_forces_at_node("node_s1_safehouse_2_3") == [],
		"valid node with zero forces reads []")
	_check(CampaignForce.get_active_forces_at_node("node_s1_safehouse_2_3") == [],
		"active query on empty node reads []")
	_check(CampaignForce.get_forces_at_node("node_nope") == [],
		"unknown node reads [] (no fabrication, no fallback)")
	_check(CampaignForce.get_active_forces_at_node("node_nope") == [],
		"active query on unknown node reads []")
	_check(CampaignForce.get_forces_at_node("") == []
		and CampaignForce.get_active_forces_at_node("") == [],
		"empty node id reads []")


# Single + multi-force presence incl. cross-faction coexistence (0..N).
func _test_single_multiple() -> void:
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2") == ["force_a"],
		"single force present")
	CampaignForce.register_force("force_b", "SCAVENGER", "outland",
		"node_s1_city_2_2", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation",
		"node_s1_city_2_2", "", 1, 30)
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2")
		== ["force_a", "force_b", "force_c"],
		"three forces (three factions) coexist on one node")
	_check(CampaignForce.get_active_forces_at_node("node_s1_city_2_2")
		== ["force_a", "force_b", "force_c"],
		"all active initially")


# Determinism across repeats; node scoping.
func _test_determinism_scoping() -> void:
	var first := JSON.stringify(CampaignForce.get_forces_at_node("node_s1_city_2_2"))
	_check(JSON.stringify(CampaignForce.get_forces_at_node("node_s1_city_2_2")) == first
		and JSON.stringify(CampaignForce.get_active_forces_at_node("node_s1_city_2_2")) == first,
		"repeated queries identical (sorted, no insertion-order dependence)")
	CampaignForce.set_node("force_c", "node_s1_safehouse_2_3")
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2") == ["force_a", "force_b"],
		"moved force leaves first node")
	_check(CampaignForce.get_forces_at_node("node_s1_safehouse_2_3") == ["force_c"],
		"moved force appears at second node")
	CampaignForce.set_node("force_c", "node_s1_city_2_2")


# Off-board forces appear in no query.
func _test_offboard() -> void:
	CampaignForce.set_node("force_c", "")
	_check(not CampaignForce.get_forces_at_node("node_s1_city_2_2").has("force_c"),
		"off-board force excluded from reference query")
	_check(not CampaignForce.get_active_forces_at_node("node_s1_city_2_2").has("force_c"),
		"off-board force excluded from active query")
	CampaignForce.set_node("force_c", "node_s1_city_2_2")


# Destroyed retained in reference query, absent from active; disabled in both.
func _test_destroyed_disabled() -> void:
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DISABLED)
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2")
		== ["force_a", "force_b", "force_c"],
		"disabled force stays in reference population")
	_check(CampaignForce.get_active_forces_at_node("node_s1_city_2_2")
		== ["force_a", "force_c"],
		"disabled force excluded from active presence")
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DESTROYED)
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2").has("force_b"),
		"destroyed force retained in reference query (fields kept per 5E)")
	_check(not CampaignForce.get_active_forces_at_node("node_s1_city_2_2").has("force_b"),
		"destroyed force never reads as active presence")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_city_2_2", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "node_s1_city_2_2", "", 1, 30)


# Save/load preserves references; reset empties every query (no stale cache).
func _test_save_reset() -> void:
	_check(SaveGameIO.save_run(), "save_run reports success")
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "load_run reports success")
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2")
		== ["force_a", "force_b", "force_c"],
		"presence identical after save/load (references persisted, query derived)")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2") == ["force_a"],
		"reset leaves only freshly seeded presence (no stale index)")


# Isolation: patrol/hangar/battle/base/territory churn never affects presence.
func _test_isolation() -> void:
	var before := JSON.stringify(
		CampaignForce.get_forces_at_node("node_s1_city_2_2"))
	GlobalData.board.board_patrols.append({"id": 7777, "faction": "hostile"})
	GlobalData.hangar.fleet_roster.append({"template_id": "probe"})
	CampaignBattle.register_battle("probe_battle", "node_s1_city_2_2", ["force_a"])
	CampaignBase.register_base("probe_base", "node_s1_city_2_2", "OUTPOST")
	CampaignTerritory.register_territory("probe_terr", ["node_s1_city_2_2"])
	_check(JSON.stringify(CampaignForce.get_forces_at_node("node_s1_city_2_2")) == before,
		"patrol/hangar/battle/base/territory churn never affects presence")
	_check(CampaignForce.get_active_forces_at_node("node_s1_city_2_2") == ["force_a"],
		"active query equally isolated")
	GlobalData.reset_run_data()
