extends Node
## PHASE 3B TERRITORY LAYER VERIFY (Campaign V2 foundation).
##
## Proves: territory registry/identity, three control states with explicit
## controller semantics, faction validation via FactionSystem, invariants
## A–H, reset/new-run isolation, serialize round-trip + old-save safety,
## node-membership integration without duplicating node authority, and that
## no territory signal was added to EventBus. No gameplay consumers exist yet
## by design — nothing here moves the player or touches combat.
## Real-save safety: user save backed up on entry, restored at the end.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TERRITORY OK: " + name)
	else:
		_fails += 1
		printerr("TERRITORY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_nodes()
	_test_registry()
	_test_identity()
	_test_control()
	_test_faction_validation()
	_test_invariants()
	_test_reset_isolation()
	_test_serialize_round_trip()
	_test_old_save_compat()
	_test_node_integration()
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
	print("TERRITORY_LAYER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("TERRITORY_LAYER_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_TERRITORY_LAYER_TESTS_PASSED")
		get_tree().quit(0)


func _seed_nodes() -> void:
	CampaignNodeRegistry.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot")


func _nids() -> Array:
	return ["node_s1_city_2_2", "node_s1_safehouse_2_3", "node_s1_fuel_depot_5_5"]


# Registry: register / duplicate / lookup / unknown.
func _test_registry() -> void:
	CampaignTerritory.clear()
	var tids := _nids()
	_check(CampaignTerritory.register_territory("terr_a", [tids[0], tids[1]]) == "terr_a",
		"register territory with node members")
	_check(CampaignTerritory.has_territory("terr_a"), "has_territory true")
	_check(not CampaignTerritory.get_territory("terr_a").is_empty(), "get_territory returns data")
	_check(CampaignTerritory.get_territories().size() == 1, "list has one territory")
	_check(CampaignTerritory.register_territory("terr_a", [tids[0], tids[1]]) == "terr_a",
		"identical re-registration is idempotent (no duplicate authority)")
	_check(CampaignTerritory.register_territory("terr_a", [tids[2]]) == "",
		"same id with different members rejected")
	_check(CampaignTerritory.register_territory("", []) == "", "empty id rejected")
	_check(CampaignTerritory.register_territory("terr_zero") == "terr_zero",
		"zero-node territory allowed")
	_check(CampaignTerritory.get_territory("terr_nope").is_empty(), "unknown lookup empty")
	_check(CampaignTerritory.get_members("terr_nope").is_empty(), "unknown members empty")
	CampaignTerritory.clear()


# Identity: deterministic, unique, stable, sanitized helper.
func _test_identity() -> void:
	_check(CampaignTerritory.make_territory_id(1, "Downtown") == "terr_s1_downtown",
		"helper derives deterministic id")
	_check(CampaignTerritory.make_territory_id(1, "Downtown") == CampaignTerritory.make_territory_id(1, "Downtown"),
		"helper stable across calls")
	_check(CampaignTerritory.make_territory_id(1, "A B-C") == "terr_s1_a_b_c",
		"helper sanitizes slug")
	_check(CampaignTerritory.make_territory_id(1, "!!!") == "", "helper rejects empty slug")
	CampaignTerritory.clear()
	CampaignTerritory.register_territory("terr_a", [])
	CampaignTerritory.register_territory("terr_b", [])
	_check(CampaignTerritory.get_territories().size() == 2, "two ids coexist uniquely")
	CampaignTerritory.clear()


# Control: uncontrolled / controlled / contested + clearing.
func _test_control() -> void:
	CampaignTerritory.clear()
	CampaignTerritory.register_territory("terr_a", [])
	_check(CampaignTerritory.is_uncontrolled("terr_a"), "new territory uncontrolled")
	_check(CampaignTerritory.get_controller("terr_a") == "", "uncontrolled has no controller")
	_check(CampaignTerritory.get_contesting("terr_a").is_empty(), "uncontrolled has no contest list")
	_check(CampaignTerritory.set_controlled("terr_a", "federation"), "set controlled accepted")
	_check(CampaignTerritory.is_controlled("terr_a"), "is_controlled true")
	_check(CampaignTerritory.get_controller("terr_a") == "federation", "controller recorded")
	_check(CampaignTerritory.set_contested("terr_a", ["zeon", "federation", "zeon"]),
		"set contested accepted")
	_check(CampaignTerritory.is_contested("terr_a"), "is_contested true")
	_check(CampaignTerritory.get_controller("terr_a") == "", "contested claims no controller")
	_check(CampaignTerritory.get_contesting("terr_a") == ["federation", "zeon"],
		"contest list deduped + sorted")
	_check(CampaignTerritory.set_uncontrolled("terr_a"), "clear to uncontrolled")
	_check(CampaignTerritory.is_uncontrolled("terr_a")
		and CampaignTerritory.get_contesting("terr_a").is_empty(),
		"uncontrolled clears controller and contest list")
	_check(not CampaignTerritory.set_controlled("terr_nope", "federation"),
		"control write on unknown territory rejected")
	_check(not CampaignTerritory.set_contested("terr_nope", ["zeon"]),
		"contest write on unknown territory rejected")
	_check(not CampaignTerritory.set_uncontrolled("terr_nope"),
		"clear on unknown territory rejected")
	CampaignTerritory.clear()


# Faction validation via the canonical registry (never duplicated).
func _test_faction_validation() -> void:
	CampaignTerritory.clear()
	CampaignTerritory.register_territory("terr_a", [])
	_check(not CampaignTerritory.set_controlled("terr_a", "nope"),
		"unknown faction controller rejected")
	_check(CampaignTerritory.is_uncontrolled("terr_a"), "rejected write changed nothing")
	_check(not CampaignTerritory.set_contested("terr_a", []),
		"empty contest list rejected")
	_check(not CampaignTerritory.set_contested("terr_a", ["zeon", "nope"]),
		"contest with any unknown faction rejected all-or-nothing")
	_check(CampaignTerritory.is_uncontrolled("terr_a"), "rejected contest changed nothing")
	_check(not CampaignTerritory.set_controlled("terr_a", "hostile"),
		"encounter label is not a valid controller faction")
	CampaignTerritory.clear()


# Invariants A–G through the validate() audit.
func _test_invariants() -> void:
	CampaignTerritory.clear()
	CampaignTerritory.register_territory("terr_a", [_nids()[0]])
	CampaignTerritory.set_controlled("terr_a", "zeon")
	_check(CampaignTerritory.validate().is_empty(), "healthy controlled territory validates")
	CampaignTerritory.set_contested("terr_a", ["federation"])
	_check(CampaignTerritory.validate().is_empty(), "healthy contested territory validates")
	CampaignTerritory.set_uncontrolled("terr_a")
	_check(CampaignTerritory.validate().is_empty(), "healthy uncontrolled territory validates")
	CampaignTerritory.clear()


# Reset / new-run isolation (Invariant H).
func _test_reset_isolation() -> void:
	CampaignTerritory.register_territory("terr_a", [_nids()[0]])
	CampaignTerritory.set_controlled("terr_a", "federation")
	GlobalData.reset_run_data()
	_seed_nodes()
	_check(CampaignTerritory.get_territories().is_empty(),
		"reset_run_data clears territory state (no Run A leakage)")
	_check(CampaignTerritory.is_uncontrolled("terr_a"), "unknown id reads uncontrolled default")


# Serialize round trip: exact, ordered, deterministic.
func _test_serialize_round_trip() -> void:
	CampaignTerritory.clear()
	CampaignTerritory.register_territory("terr_b", [_nids()[2]])
	CampaignTerritory.register_territory("terr_a", [_nids()[0], _nids()[1]])
	CampaignTerritory.set_controlled("terr_a", "federation")
	CampaignTerritory.set_contested("terr_b", ["zeon", "outland"])
	var snap_a := JSON.stringify(CampaignTerritory.serialize())
	CampaignTerritory.clear()
	CampaignTerritory.deserialize(JSON.parse_string(snap_a))
	var snap_b := JSON.stringify(CampaignTerritory.serialize())
	_check(snap_a == snap_b, "round trip restores equivalent state")
	_check(CampaignTerritory.get_controller("terr_a") == "federation",
		"controller restored")
	_check(CampaignTerritory.get_contesting("terr_b") == ["outland", "zeon"],
		"contest list restored sorted")
	_check(CampaignTerritory.get_members("terr_a") == [_nids()[0], _nids()[1]],
		"members restored sorted")
	# Full SaveGameIO path.
	_check(SaveGameIO.save_run(), "save_run carries territory state")
	CampaignTerritory.clear()
	_check(SaveGameIO.load_run(), "load_run restores territory state")
	_check(CampaignTerritory.get_controller("terr_a") == "federation",
		"controller survives save/load")
	CampaignTerritory.clear()


# Old saves without territory data load safely.
func _test_old_save_compat() -> void:
	CampaignTerritory.register_territory("terr_a", [])
	CampaignTerritory.set_controlled("terr_a", "zeon")
	_check(SaveGameIO.save_run(), "save_run reports success")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(d is Dictionary and (d as Dictionary).has("territories"),
		"save file carries territories")
	(d as Dictionary).erase("territories")
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	CampaignTerritory.clear()
	_check(SaveGameIO.load_run(), "legacy payload without territories still loads")
	_check(CampaignTerritory.get_territories().is_empty(),
		"missing territory data reconstructs empty defaults")
	CampaignTerritory.deserialize({"territories": [
		{"id": "", "control": "controlled", "controller": "federation"},
		{"id": "terr_bad", "control": "bogus", "controller": "federation"},
		{"id": "terr_bad2", "control": "controlled", "controller": "nope"},
		"not-a-row",
	]})
	_check(CampaignTerritory.get_territories().is_empty(),
		"invalid rows skipped deterministically")
	CampaignTerritory.clear()


# Node integration: references, rejection, no duplicated authority, staleness.
func _test_node_integration() -> void:
	CampaignTerritory.clear()
	_check(CampaignTerritory.register_territory("terr_a", ["node_nope"]) == "",
		"unknown node member rejects the whole registration")
	_check(not CampaignTerritory.has_territory("terr_a"), "rejected registration created nothing")
	_check(CampaignTerritory.register_territory("terr_a", _nids()) == "terr_a",
		"valid node members accepted")
	_check(not CampaignTerritory.set_members("terr_a", [_nids()[0], "node_nope"]),
		"set_members with any unknown node rejected all-or-nothing")
	var kept := CampaignTerritory.get_members("terr_a")
	kept.sort()
	var want := _nids().duplicate()
	want.sort()
	_check(kept == want, "rejected member write changed nothing")
	_check(CampaignNodeRegistry.has_node(_nids()[0]),
		"nodes still owned by CampaignNodeRegistry (no duplication)")
	# Stale members are kept + flagged, never silently pruned.
	CampaignNodeRegistry.remove_node(_nids()[0])
	var problems := CampaignTerritory.validate()
	var flagged := false
	for p in problems:
		if str(p).contains("unknown node"):
			flagged = true
	_check(flagged, "stale member flagged by validate()")
	_check(CampaignTerritory.get_members("terr_a").has(_nids()[0]),
		"stale member preserved (dynamic nodes can return)")
	_seed_nodes()
	_check(CampaignTerritory.validate().is_empty(), "member valid again after node returns")
	CampaignTerritory.clear()


# No territory signal exists (no consumer requires one in 3B).
func _test_no_signal() -> void:
	_check(not EventBus.has_signal("territory_control_changed"),
		"no territory signal on EventBus (queries never emit)")
