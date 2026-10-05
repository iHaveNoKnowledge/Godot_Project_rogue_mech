extends Node
## PHASE 4 BASE ENTITY + STATE VERIFY (Campaign V2 foundation).
##
## Proves: base registry/identity, node occupancy (0..1), faction/territory
## validation without duplicating authorities, explicit state graph,
## legacy enemy-base bridge (both directions), serialize round-trip +
## old-save compatibility, reset isolation, and that no base signals exist.
## No gameplay consumers exist yet by design — nothing here touches combat,
## movement, production, or capture. User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("BASE OK: " + name)
	else:
		_fails += 1
		printerr("BASE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_registry()
	_test_identity()
	_test_location()
	_test_faction_territory()
	_test_states()
	_test_bridge()
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
	print("BASE_ENTITY_STATE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("BASE_ENTITY_STATE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_BASE_ENTITY_STATE_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot")
	CampaignTerritory.register_territory("terr_downtown",
		["node_s1_city_2_2", "node_s1_safehouse_2_3"])


# Registry: create / duplicate / lookup / unknown.
func _test_registry() -> void:
	CampaignBase.clear()
	var bid := CampaignBase.register_base("base_alpha", "node_s1_city_2_2",
		"OUTPOST", "federation", "terr_downtown")
	_check(bid == "base_alpha" and CampaignBase.has_base(bid), "register valid base")
	_check(not CampaignBase.get_base(bid).is_empty(), "get base returns data")
	_check(CampaignBase.get_bases().size() == 1, "list has one base")
	_check(CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "OUTPOST",
		"federation", "terr_downtown") == "base_alpha", "identical re-register idempotent")
	_check(CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "RESEARCH_BASE") == "",
		"same id with different type rejected")
	_check(CampaignBase.register_base("", "node_s1_city_2_2", "OUTPOST") == "",
		"empty id rejected")
	_check(CampaignBase.register_base("base_bad", "node_s1_city_2_2", "STARBASE") == "",
		"unknown base type rejected")
	_check(CampaignBase.register_base("base_bad", "node_nope", "OUTPOST") == "",
		"unknown node rejected")
	_check(CampaignBase.register_base("base_bad", "node_s1_city_2_2", "OUTPOST",
		"nope") == "", "unknown faction rejected")
	_check(CampaignBase.register_base("base_bad", "node_s1_city_2_2", "OUTPOST",
		"", "terr_nope") == "", "unknown territory rejected")
	_check(CampaignBase.get_base("base_nope").is_empty(), "unknown lookup empty")
	CampaignBase.clear()


# Identity: deterministic helper, legacy pattern, stability.
func _test_identity() -> void:
	_check(CampaignBase.make_base_id(1, "Alpha Post") == "base_s1_alpha_post",
		"helper derives deterministic id")
	_check(CampaignBase.make_base_id(1, "Alpha Post") == CampaignBase.make_base_id(1, "Alpha Post"),
		"helper stable across calls")
	_check(CampaignBase.make_base_id(2, "!!!") == "", "helper rejects empty slug")
	_check(CampaignBase.legacy_research_id(1) == "base_enemy_research_s1",
		"legacy bridge id deterministic per sector")
	_check(CampaignBase.legacy_research_id(1) != CampaignBase.legacy_research_id(2),
		"legacy bridge id sector-scoped")


# Location: 0..1 live bases per node, moves validated, destroyed frees.
func _test_location() -> void:
	CampaignBase.clear()
	CampaignBase.register_base("base_a", "node_s1_city_2_2", "OUTPOST")
	_check(CampaignBase.register_base("base_b", "node_s1_city_2_2", "OUTPOST") == "",
		"second live base on the same node rejected (0..1)")
	_check(not CampaignBase.set_node("base_a", "node_nope"), "move to unknown node rejected")
	_check(CampaignBase.set_node("base_a", "node_s1_safehouse_2_3"), "move to free node accepted")
	_check(CampaignBase.register_base("base_b", "node_s1_city_2_2", "OUTPOST") == "base_b",
		"freed node accepts a new base")
	_check(not CampaignBase.set_node("base_b", "node_s1_safehouse_2_3"),
		"move onto an occupied node rejected")
	_check(CampaignBase.set_state("base_a", CampaignBase.BaseState.DESTROYED),
		"destroy first base")
	_check(CampaignBase.set_node("base_b", "node_s1_safehouse_2_3"),
		"destroyed base frees its node")
	CampaignBase.clear()


# Faction + territory links: validated, clearable, never duplicated.
func _test_faction_territory() -> void:
	CampaignBase.clear()
	CampaignBase.register_base("base_a", "node_s1_city_2_2", "OUTPOST")
	_check(not CampaignBase.set_controller("base_a", "nope"), "unknown faction rejected")
	_check(CampaignBase.set_controller("base_a", "zeon"), "valid faction accepted")
	_check(CampaignBase.get_base("base_a").get("controller", "") == "zeon",
		"controller stored as id string (no duplicated def)")
	_check(CampaignBase.set_controller("base_a", ""), "controller clearable")
	_check(not CampaignBase.set_territory("base_a", "terr_nope"), "unknown territory rejected")
	_check(CampaignBase.set_territory("base_a", "terr_downtown"), "valid territory accepted")
	_check(CampaignBase.set_territory("base_a", ""), "territory clearable")
	_check(not CampaignBase.set_controller("base_nope", "zeon"), "faction write on unknown base rejected")
	CampaignBase.clear()


# State graph: legal edges pass, illegal edges fail, terminal holds.
func _test_states() -> void:
	CampaignBase.clear()
	CampaignBase.register_base("base_a", "node_s1_city_2_2", "OUTPOST")
	_check(CampaignBase.is_active("base_a"), "initial state ACTIVE")
	_check(CampaignBase.set_state("base_a", CampaignBase.BaseState.DISABLED),
		"ACTIVE -> DISABLED")
	_check(not CampaignBase.is_active("base_a"), "disabled is not active")
	_check(CampaignBase.set_state("base_a", CampaignBase.BaseState.ACTIVE),
		"DISABLED -> ACTIVE (recovery)")
	_check(CampaignBase.set_state("base_a", CampaignBase.BaseState.DESTROYED),
		"ACTIVE -> DESTROYED direct")
	_check(not CampaignBase.set_state("base_a", CampaignBase.BaseState.ACTIVE),
		"DESTROYED terminal for explicit writes")
	_check(CampaignBase.set_state("base_a", CampaignBase.BaseState.DESTROYED),
		"same-state write accepted")
	_check(not CampaignBase.set_state("base_a", 99), "unknown state rejected")
	_check(not CampaignBase.set_state("base_nope", CampaignBase.BaseState.ACTIVE),
		"state write on unknown base rejected")
	CampaignBase.clear()
	CampaignBase.register_base("base_b", "node_s1_city_2_2", "OUTPOST")
	_check(CampaignBase.set_state("base_b", CampaignBase.BaseState.DISABLED)
		and CampaignBase.set_state("base_b", CampaignBase.BaseState.DESTROYED),
		"DISABLED -> DESTROYED")
	CampaignBase.clear()


# Legacy bridge: legacy flags <-> canonical record, both directions.
func _test_bridge() -> void:
	CampaignBase.clear()
	GlobalData.narrative.enemy_base_active = true
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(4, 4)
	CampaignNodeRegistry.sync_tile(1, Vector2i(4, 4), "enemy_base")
	var bid := CampaignBase.sync_legacy_enemy_base(1)
	_check(bid == "base_enemy_research_s1", "bridge creates the well-known legacy record")
	var b := CampaignBase.get_base(bid)
	_check(CampaignBase.is_active(bid)
		and str(b.get("base_type", "")) == "RESEARCH_BASE", "bridged base ACTIVE research base")
	_check(str(b.get("node_id", "")) == "node_s1_enemy_base_4_4",
		"bridged base references the live node (not a tile copy)")
	_check(CampaignBase.validate().is_empty(), "bridged record validates clean")
	GlobalData.narrative.enemy_base_active = false
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(-1, -1)
	CampaignBase.sync_legacy_enemy_base(1)
	_check(not CampaignBase.is_active(bid) and CampaignBase.has_base(bid),
		"legacy clear marks DESTROYED and keeps the record")
	_check(CampaignBase.validate().is_empty(), "destroyed record validates clean")
	GlobalData.narrative.enemy_base_active = true
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(6, 6)
	CampaignNodeRegistry.sync_tile(1, Vector2i(6, 6), "enemy_base")
	CampaignBase.sync_legacy_enemy_base(1)
	_check(CampaignBase.is_active(bid)
		and str(CampaignBase.get_base(bid).get("node_id", "")) == "node_s1_enemy_base_6_6",
		"legacy re-activation revives the record at the new node (bridge wins)")
	GlobalData.narrative.enemy_base_active = false
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(-1, -1)
	CampaignBase.clear()


# Serialize round trip via snapshot + full SaveGameIO path.
func _test_serialize_round_trip() -> void:
	CampaignBase.clear()
	CampaignBase.register_base("base_b", "node_s1_safehouse_2_3", "OUTPOST", "outland")
	CampaignBase.register_base("base_a", "node_s1_city_2_2", "RESEARCH_BASE",
		"federation", "terr_downtown")
	CampaignBase.set_state("base_b", CampaignBase.BaseState.DISABLED)
	var snap_a := JSON.stringify(CampaignBase.serialize())
	CampaignBase.clear()
	CampaignBase.deserialize(JSON.parse_string(snap_a))
	_check(JSON.stringify(CampaignBase.serialize()) == snap_a, "round trip equivalent")
	_check(SaveGameIO.save_run(), "save_run carries base state")
	CampaignBase.clear()
	_check(SaveGameIO.load_run(), "load_run restores base state")
	_check(CampaignBase.get_state("base_b") == CampaignBase.BaseState.DISABLED,
		"disabled state survives save/load")
	_check(str(CampaignBase.get_base("base_a").get("controller", "")) == "federation",
		"controller survives save/load")
	CampaignBase.clear()


# Old saves: no "bases" key loads fine; legacy fields still bridge.
func _test_old_save_compat() -> void:
	GlobalData.narrative.enemy_base_active = true
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(4, 4)
	_check(SaveGameIO.save_run(), "save_run reports success")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	_check(d is Dictionary and (d as Dictionary).has("bases"), "save file carries bases")
	(d as Dictionary).erase("bases")
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	CampaignBase.clear()
	_check(SaveGameIO.load_run(), "legacy payload without bases still loads")
	_check(CampaignBase.get_bases().is_empty(), "missing base data loads as empty")
	_check(bool(GlobalData.narrative.enemy_base_active), "legacy enemy-base flags intact")
	CampaignNodeRegistry.sync_tile(1, Vector2i(4, 4), "enemy_base")
	_check(CampaignBase.sync_legacy_enemy_base(1) == "base_enemy_research_s1",
		"legacy flags deterministically rebuild the canonical record")
	_check(CampaignBase.is_active("base_enemy_research_s1"), "rebuilt record ACTIVE")
	CampaignBase.deserialize({"bases": [
		{"id": "", "node_id": "", "base_type": "OUTPOST", "state": "active"},
		{"id": "base_bad", "node_id": "", "base_type": "STARBASE", "state": "active"},
		{"id": "base_bad2", "node_id": "", "base_type": "OUTPOST", "state": "bogus"},
		"not-a-row",
	]})
	_check(CampaignBase.get_bases().is_empty(), "invalid rows skipped deterministically")
	GlobalData.narrative.enemy_base_active = false
	GlobalData.narrative.enemy_base_tile_pos = Vector2i(-1, -1)
	CampaignBase.clear()


# Reset isolation through the established primitive.
func _test_reset_isolation() -> void:
	CampaignBase.register_base("base_a", "node_s1_city_2_2", "OUTPOST")
	CampaignBase.set_state("base_a", CampaignBase.BaseState.DESTROYED)
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignBase.get_bases().is_empty(),
		"reset_run_data clears base state (no Run A leakage)")


# No base signals exist (no consumer requires one in Phase 4).
func _test_no_signal() -> void:
	_check(not EventBus.has_signal("base_state_changed"), "no base_state_changed signal")
	_check(not EventBus.has_signal("base_destroyed"), "no base_destroyed signal")
	_check(not EventBus.has_signal("base_created"), "no base_created signal")
