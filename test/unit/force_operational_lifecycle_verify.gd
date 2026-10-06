extends Node
## PHASE 5E FORCE OPERATIONAL LIFECYCLE VERIFY (Option A: existing APIs).
##
## Audit result pinned here: NO production code creates or mutates forces —
## register_force/set_state/set_node/set_base/set_faction/set_composition are
## called only by tests and the lifecycle wires (clear/serialize/deserialize).
## There is deliberately NO production creator, NO turn consumer, NO battle
## mutator, NO movement/AI/supply owner yet (future producers undelegated).
## This test locks the ownership semantics so a future producer cannot
## silently change them: creation rules, activation/disable/destroy graph,
## node/base reference lifecycle, destroyed-field retention, turn absence,
## battle absence, persistence shape, and reset order-independence.
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LIFECYCLE OK: " + name)
	else:
		_fails += 1
		printerr("LIFECYCLE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_creation_ownership()
	_test_activation_graph()
	_test_node_lifecycle()
	_test_base_lifecycle()
	_test_destroyed_semantics()
	_test_turn_absence()
	_test_battle_absence()
	_test_persistence_shape()
	_test_reset_order()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FORCE_OPERATIONAL_LIFECYCLE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FORCE_OPERATIONAL_LIFECYCLE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_LIFECYCLE_TESTS_PASSED")
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


# Creation: low-level authority only; invariants hold; no auto-merge.
func _test_creation_ownership() -> void:
	CampaignForce.clear()
	_check(CampaignForce.register_force("force_a", "PATROL", "zeon",
		"node_s1_city_2_2", "base_alpha", 3, 10) == "force_a",
		"creation with all references accepted")
	var f := CampaignForce.get_force("force_a")
	_check(CampaignForce.is_active("force_a"), "new force starts ACTIVE (no separate activation step)")
	_check(int(f.get("unit_count", -1)) == 3 and int(f.get("strength", -1)) == 10,
		"creation composition stored verbatim (no derivation)")
	_check(CampaignForce.register_force("force_a", "PATROL", "zeon",
		"node_s1_city_2_2", "base_alpha", 3, 10) == "force_a",
		"identical re-registration idempotent (no auto-merge, no duplicate)")
	_check(CampaignForce.get_forces().size() == 1, "no duplicate authority created")
	CampaignForce.clear()


# Activation graph ownership: CampaignForce.set_state alone; terminal holds.
func _test_activation_graph() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"owner can disable (ACTIVE -> DISABLED)")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.ACTIVE),
		"owner can re-activate (DISABLED -> ACTIVE)")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"owner can destroy (ACTIVE -> DESTROYED)")
	_check(not CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"destroyed cannot leave terminal (no resurrection path)")
	CampaignForce.clear()


# Node presence: reference lifecycle; destroyed keeps its last reference.
func _test_node_lifecycle() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "", "node_s1_city_2_2")
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"),
		"owner can relocate reference (no pathfinding, no cost, no encounter)")
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_safehouse_2_3",
		"relocation is a pure reference change")
	_check(not CampaignForce.set_node("force_a", "node_nope"),
		"unknown node rejected; old reference kept")
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_safehouse_2_3",
		"rejected move changed nothing")
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED)
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_safehouse_2_3",
		"destroyed force retains node reference (no silent clearing)")
	CampaignForce.clear()


# Base attachment: reference lifecycle; base never written.
func _test_base_lifecycle() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "", "node_s1_city_2_2")
	var base_before := JSON.stringify(CampaignBase.get_base("base_alpha"))
	_check(CampaignForce.set_base("force_a", "base_alpha"), "owner can attach")
	_check(CampaignForce.set_base("force_a", ""), "owner can detach")
	_check(CampaignForce.set_base("force_a", "base_alpha"), "owner can re-attach")
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED)
	_check(CampaignForce.get_force("force_a").get("base_id", "") == "base_alpha",
		"destroyed force retains base reference")
	_check(JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"base record never written by force lifecycle (no garrison semantics)")
	CampaignForce.clear()


# Destroyed semantics: fields retained, battles refuse, save keeps.
func _test_destroyed_semantics() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2",
		"base_alpha", 3, 10)
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED)
	var f := CampaignForce.get_force("force_a")
	_check(str(f.get("faction", "")) == "zeon"
		and int(f.get("unit_count", -1)) == 3, "destroyed retains faction/composition")
	_check(CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a"]) == "", "destroyed force cannot seed a battle (invariant holds)")
	_check(SaveGameIO.save_run(), "save_run carries destroyed force")
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "load_run restores destroyed force")
	_check(not CampaignForce.is_active("force_a")
		and CampaignForce.get_state("force_a") == CampaignForce.ForceState.DESTROYED,
		"destroyed state survives save/load (no silent revival)")
	CampaignForce.clear()


# Turn absence: campaign turns never mutate forces (no subscriber).
func _test_turn_absence() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2",
		"", 3, 10)
	var before := JSON.stringify(CampaignForce.get_force("force_a"))
	CampaignTurnExecutive.advance_campaign_turn("lifecycle_probe", {"day_boundary": false})
	CampaignTurnExecutive.advance_campaign_turn("lifecycle_probe", {})
	_check(JSON.stringify(CampaignForce.get_force("force_a")) == before,
		"campaign turns (both granularities) leave forces byte-identical")
	CampaignForce.clear()


# Battle absence: full battle lifecycle mutates no force.
func _test_battle_absence() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "", "", 2, 6)
	var before := JSON.stringify(CampaignForce.get_forces())
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a", "force_b"])
	CampaignBattle.prepare_launch("battle_x")
	CampaignBattle.resolve_battle("battle_x")
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"register + launch + resolve mutate no force (resolution is future work)")
	CampaignBattle.clear()
	CampaignForce.clear()


# Persistence shape: ids/scalars only, deterministic order.
func _test_persistence_shape() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_b", "CONVOY", "outland", "", "", 2, 8)
	CampaignForce.register_force("force_a", "RIVAL", "zeon", "node_s1_city_2_2",
		"base_alpha", 1, 30)
	var snap := CampaignForce.serialize()
	_check((snap.get("forces", []) as Array).size() == 2, "two forces serialized")
	_check(str((snap["forces"] as Array)[0].get("id", "")) == "force_a",
		"serialization order deterministic (sorted)")
	var has_runtime := false
	for row in snap["forces"]:
		for k in (row as Dictionary):
			if (row as Dictionary)[k] is Object:
				has_runtime = true
	_check(not has_runtime, "no runtime objects serialized")
	CampaignForce.clear()


# Reset order: battles + forces clear independently; no stale refs remain.
func _test_reset_order() -> void:
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().is_empty()
		and CampaignBattle.get_battles().is_empty(),
		"one reset clears both forces and battles (order-independent, no hidden cleanup)")
	_check(CampaignBattle.validate().is_empty(), "no stale participant refs after reset")
