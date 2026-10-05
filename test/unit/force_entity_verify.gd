extends Node
## PHASE 5A FORCE ENTITY VERIFY (Campaign V2 foundation).
##
## Proves: force registry/identity, faction/node/base validation without
## duplicating authorities, derived (never stored) territory context,
## explicit state graph, abstract composition, reset isolation, serialize
## round-trip + old-save safety, and that PatrolSystem stays separate
## (patrols are NOT auto-bridged in 5A). Nothing here touches combat,
## movement, or player handoff. User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FORCE OK: " + name)
	else:
		_fails += 1
		printerr("FORCE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_registry()
	_test_identity()
	_test_faction()
	_test_location()
	_test_base_link()
	_test_territory_derived()
	_test_states()
	_test_types()
	_test_composition()
	_test_reset_isolation()
	_test_serialize_round_trip()
	_test_old_save_compat()
	_test_patrol_separation()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FORCE_ENTITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FORCE_ENTITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_ENTITY_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot")
	CampaignTerritory.register_territory("terr_downtown",
		["node_s1_city_2_2", "node_s1_safehouse_2_3"])
	CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "OUTPOST",
		"federation", "terr_downtown")


# Registry: create / duplicate / lookup / unknown.
func _test_registry() -> void:
	CampaignForce.clear()
	var fid := CampaignForce.register_force("force recon", "PATROL", "zeon",
		"node_s1_safehouse_2_3", "", 3, 10)
	_check(fid == "force recon" and CampaignForce.has_force(fid), "register valid force")
	_check(not CampaignForce.get_force(fid).is_empty(), "get force returns data")
	_check(CampaignForce.get_forces().size() == 1, "list has one force")
	_check(CampaignForce.register_force("force recon", "PATROL", "zeon",
		"node_s1_safehouse_2_3", "", 3, 10) == "force recon",
		"identical re-registration idempotent")
	_check(CampaignForce.register_force("force recon", "PATROL", "zeon",
		"node_s1_safehouse_2_3", "", 4, 10) == "",
		"same id with different composition rejected")
	_check(CampaignForce.register_force("", "PATROL") == "", "empty id rejected")
	_check(CampaignForce.register_force("force_bad", "ARMY") == "", "unknown type rejected")
	_check(CampaignForce.register_force("force_bad", "PATROL", "nope") == "",
		"unknown faction rejected")
	_check(CampaignForce.register_force("force_bad", "PATROL", "",
		"node_nope") == "", "unknown node rejected")
	_check(CampaignForce.register_force("force_bad", "PATROL", "",
		"", "base_nope") == "", "unknown base rejected")
	_check(CampaignForce.register_force("force_bad", "PATROL", "",
		"", "", -1, 0) == "", "negative unit_count rejected")
	_check(CampaignForce.register_force("force_bad", "PATROL", "",
		"", "", 0, -5) == "", "negative strength rejected")
	_check(CampaignForce.get_force("force_nope").is_empty(), "unknown lookup empty")
	CampaignForce.clear()


# Identity: deterministic helper, stable, unique.
func _test_identity() -> void:
	_check(CampaignForce.make_force_id(1, "Raven Wing") == "force_s1_raven_wing",
		"helper derives deterministic id")
	_check(CampaignForce.make_force_id(1, "Raven Wing") == CampaignForce.make_force_id(1, "Raven Wing"),
		"helper stable across calls")
	_check(CampaignForce.make_force_id(1, "!!!") == "", "helper rejects empty slug")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL")
	CampaignForce.register_force("force_b", "CONVOY")
	_check(CampaignForce.get_forces().size() == 2, "two ids coexist uniquely")
	CampaignForce.clear()


# Faction: validated, clearable, encounter labels are not factions.
func _test_faction() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL")
	_check(not CampaignForce.set_faction("force_a", "nope"), "unknown faction rejected")
	_check(CampaignForce.set_faction("force_a", "federation"), "valid faction accepted")
	_check(CampaignForce.get_force("force_a").get("faction", "") == "federation",
		"faction stored as id string (no duplicated def)")
	_check(CampaignForce.set_faction("force_a", ""), "faction clearable (unattributed)")
	_check(not CampaignForce.set_faction("force_a", "hostile"),
		"encounter label is not a valid faction")
	CampaignForce.clear()


# Location: node-validated moves, off-board clearing.
func _test_location() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "", "node_s1_city_2_2")
	_check(not CampaignForce.set_node("force_a", "node_nope"), "move to unknown node rejected")
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"), "move accepted")
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_safehouse_2_3",
		"location updated")
	_check(CampaignForce.set_node("force_a", ""), "clearing to off-board accepted")
	_check(not CampaignForce.set_node("force_nope", "node_s1_city_2_2"),
		"move on unknown force rejected")
	CampaignForce.clear()


# Base link: validated attach/detach, never writes base state.
func _test_base_link() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "", "node_s1_city_2_2")
	_check(not CampaignForce.set_base("force_a", "base_nope"), "unknown base rejected")
	_check(CampaignForce.set_base("force_a", "base_alpha"), "valid base attached")
	_check(CampaignBase.is_active("base_alpha"), "attaching never mutates base state")
	_check(CampaignForce.set_base("force_a", ""), "detach accepted")
	_check(not CampaignForce.set_base("force_nope", "base_alpha"),
		"attach on unknown force rejected")
	CampaignForce.clear()


# Territory context derives through topology, never stored.
func _test_territory_derived() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "", "node_s1_city_2_2")
	_check(CampaignForce.get_territory_context("force_a") == "terr_downtown",
		"territory derived from covering territory")
	CampaignForce.register_force("force_b", "SCAVENGER", "", "node_s1_fuel_depot_5_5")
	_check(CampaignForce.get_territory_context("force_b") == "",
		"no covering territory reads empty (no inference)")
	CampaignForce.register_force("force_c", "RIVAL")
	_check(CampaignForce.get_territory_context("force_c") == "",
		"unlocated force has no territory context")
	_check(CampaignForce.get_territory_context("force_nope") == "",
		"unknown force reads empty")
	_check(not CampaignForce.get_force("force_a").has("territory_id"),
		"territory never stored on the force (no duplication)")
	CampaignForce.clear()


# State graph: legal edges pass, illegal edges fail, terminal holds.
func _test_states() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL")
	_check(CampaignForce.is_active("force_a"), "initial state ACTIVE")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"ACTIVE -> DISABLED")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.ACTIVE),
		"DISABLED -> ACTIVE (recovery)")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"ACTIVE -> DESTROYED direct")
	_check(not CampaignForce.set_state("force_a", CampaignForce.ForceState.ACTIVE),
		"DESTROYED terminal for explicit writes")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"same-state write accepted")
	_check(not CampaignForce.set_state("force_a", 99), "unknown state rejected")
	_check(not CampaignForce.set_state("force_nope", CampaignForce.ForceState.ACTIVE),
		"state write on unknown force rejected")
	CampaignForce.clear()
	CampaignForce.register_force("force_b", "CONVOY")
	_check(CampaignForce.set_state("force_b", CampaignForce.ForceState.DISABLED)
		and CampaignForce.set_state("force_b", CampaignForce.ForceState.DESTROYED),
		"DISABLED -> DESTROYED")
	CampaignForce.clear()


# Types: audit-backed vocabulary only; type is not faction.
func _test_types() -> void:
	CampaignForce.clear()
	for t in ["PATROL", "CONVOY", "SCAVENGER", "RIVAL"]:
		_check(CampaignForce.register_force("force_" + t.to_lower(), t) != "",
			"valid force type accepted: " + t)
	_check(CampaignForce.register_force("force_g", "GARRISON") == "",
		"GARRISON deferred (no existing data)")
	_check(CampaignForce.register_force("force_e", "EXPEDITION") == "",
		"EXPEDITION deferred (no existing data)")
	_check(CampaignForce.get_forces_of_type("PATROL").size() == 1, "type query works")
	var f := CampaignForce.register_force("force_mix", "PATROL", "zeon")
	_check(f != "" and CampaignForce.get_force(f).get("force_type", "") == "PATROL"
		and CampaignForce.get_force(f).get("faction", "") == "zeon",
		"type and faction are independent dimensions")
	CampaignForce.clear()


# Composition: paired writes, non-negative, round trip.
func _test_composition() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "", "", "", 3, 10)
	_check(CampaignForce.set_composition("force_a", 5, 20), "composition update accepted")
	var f := CampaignForce.get_force("force_a")
	_check(int(f.get("unit_count", -1)) == 5 and int(f.get("strength", -1)) == 20,
		"composition stored")
	_check(not CampaignForce.set_composition("force_a", -1, 20),
		"negative count rejected")
	_check(not CampaignForce.set_composition("force_a", 5, -1),
		"negative strength rejected")
	f = CampaignForce.get_force("force_a")
	_check(int(f.get("unit_count", -1)) == 5 and int(f.get("strength", -1)) == 20,
		"rejected writes changed nothing (paired)")
	CampaignForce.clear()


# Reset isolation through the established primitive.
func _test_reset_isolation() -> void:
	CampaignForce.register_force("force_a", "PATROL", "zeon", "", "", 3, 10)
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED)
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().is_empty(),
		"reset_run_data clears force state (no Run A leakage)")


# Serialize round trip via snapshot + full SaveGameIO path.
func _test_serialize_round_trip() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_b", "CONVOY", "outland", "node_s1_safehouse_2_3",
		"", 2, 8)
	CampaignForce.register_force("force_a", "RIVAL", "zeon", "node_s1_city_2_2",
		"base_alpha", 1, 30)
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED)
	var snap_a := JSON.stringify(CampaignForce.serialize())
	CampaignForce.clear()
	CampaignForce.deserialize(JSON.parse_string(snap_a))
	_check(JSON.stringify(CampaignForce.serialize()) == snap_a, "round trip equivalent")
	_check(SaveGameIO.save_run(), "save_run carries force state")
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "load_run restores force state")
	_check(CampaignForce.get_state("force_a") == CampaignForce.ForceState.DISABLED,
		"disabled state survives save/load")
	_check(CampaignForce.get_force("force_a").get("base_id", "") == "base_alpha",
		"base link survives save/load")
	CampaignForce.clear()


# Old saves without force data load safely.
func _test_old_save_compat() -> void:
	CampaignForce.register_force("force_a", "PATROL")
	_check(SaveGameIO.save_run(), "save_run reports success")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(d is Dictionary and (d as Dictionary).has("forces"), "save file carries forces")
	(d as Dictionary).erase("forces")
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "legacy payload without forces still loads")
	_check(CampaignForce.get_forces().is_empty(), "missing force data loads as empty")
	CampaignForce.deserialize({"forces": [
		{"id": "", "force_type": "PATROL", "state": "active"},
		{"id": "force_bad", "force_type": "ARMY", "state": "active"},
		{"id": "force_bad2", "force_type": "PATROL", "state": "bogus"},
		{"id": "force_bad3", "force_type": "PATROL", "state": "active",
			"unit_count": -2, "strength": 0},
		"not-a-row",
	]})
	_check(CampaignForce.get_forces().is_empty(), "invalid rows skipped deterministically")
	CampaignForce.clear()


# Patrol separation: patrol churn never touches forces and vice versa.
func _test_patrol_separation() -> void:
	CampaignForce.clear()
	var patrols_before: int = GlobalData.board.board_patrols.size()
	CampaignForce.register_force("force_a", "PATROL", "zeon")
	_check(GlobalData.board.board_patrols.size() == patrols_before,
		"registering a force leaves board patrols untouched")
	GlobalData.board.board_patrols.append({"id": 9999, "faction": "hostile"})
	_check(CampaignForce.get_forces().size() == 1
		and CampaignForce.validate().is_empty(),
		"patrol churn never touches force state")
	GlobalData.board.board_patrols = GlobalData.board.board_patrols.filter(
		func(p) -> bool: return int((p as Dictionary).get("id", -1)) != 9999)
	CampaignForce.clear()
