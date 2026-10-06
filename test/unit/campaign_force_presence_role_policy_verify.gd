extends Node
## PHASE 5H CAMPAIGN FORCE PRESENCE ROLE POLICY VERIFY
##
## Proves Option A (No Presence Role Field Needed):
##   1. node_id = presence only (no ownership, control, or combat stance semantics)
##   2. base_id != garrison (base association does not create garrison role or mutate base)
##   3. territory != occupation (force presence does not alter territory control or occupy)
##   4. battle participant != attack/defense role (battle membership does not assign combat stance or mutate force)
##   5. patrol stance != force role (patrol aggro/stance remains board-level, separate from force)
##   6. force_type != presence_role (force classification is distinct from node presence)
##   7. save/load + reset preserve exact schema without speculative role fields.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ROLE_POLICY OK: " + name)
	else:
		_fails += 1
		printerr("ROLE_POLICY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_node_presence_only()
	_test_base_id_not_garrison()
	_test_territory_not_occupation()
	_test_battle_participant_not_attack_defense_role()
	_test_patrol_stance_not_force_role()
	_test_force_type_distinct_from_role()
	_test_save_load_reset_policy()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FORCE_PRESENCE_ROLE_POLICY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FORCE_PRESENCE_ROLE_POLICY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_PRESENCE_ROLE_POLICY_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignTerritory.register_territory("terr_alpha", ["node_s1_city_2_2", "node_s1_safehouse_2_3"])
	CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "OUTPOST", "federation", "terr_alpha")
	CampaignForce.register_force("force_1", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 15)


# 1. node_id = presence only
func _test_node_presence_only() -> void:
	var f := CampaignForce.get_force("force_1")
	_check(str(f.get("node_id", "")) == "node_s1_city_2_2", "force has node_id set as presence")
	_check(not f.has("presence_role") and not f.has("role"), "force holds no speculative presence_role field")
	var node := CampaignNodeRegistry.get_node("node_s1_city_2_2")
	_check(not node.has("forces") and not node.has("role") and not node.has("garrison"),
		"node registry holds topology only (no force lists or roles)")
	# Off-board force has node_id == "" without a hidden "RESERVE" role
	CampaignForce.register_force("force_offboard", "CONVOY", "federation", "", "", 2, 8)
	var f_off := CampaignForce.get_force("force_offboard")
	_check(str(f_off.get("node_id", "")) == "", "off-board force has empty node_id")
	_check(not f_off.has("presence_role"), "off-board force has no speculative RESERVE role")


# 2. base_id != garrison
func _test_base_id_not_garrison() -> void:
	CampaignForce.set_base("force_1", "base_alpha")
	var f := CampaignForce.get_force("force_1")
	_check(str(f.get("base_id", "")) == "base_alpha", "force references base_id")
	_check(not f.has("presence_role"), "base association does NOT create a GARRISON role")
	var base_before := CampaignBase.get_base("base_alpha")
	_check(not base_before.has("garrison") and not base_before.has("forces"),
		"CampaignBase does not track garrisons or forces")
	# Base state changes do not affect force role or presence
	CampaignBase.set_state("base_alpha", CampaignBase.BaseState.DISABLED)
	var f_after := CampaignForce.get_force("force_1")
	_check(int(f_after.get("state", -1)) == CampaignForce.ForceState.ACTIVE,
		"force state unaffected by base disable")
	_check(str(f_after.get("node_id", "")) == "node_s1_city_2_2",
		"force presence unaffected by base disable")
	CampaignBase.set_state("base_alpha", CampaignBase.BaseState.ACTIVE)


# 3. territory != occupation
func _test_territory_not_occupation() -> void:
	# Territory starts uncontrolled
	_check(CampaignTerritory.get_control_state("terr_alpha") == CampaignTerritory.ControlState.UNCONTROLLED,
		"territory is initially UNCONTROLLED despite zeon force presence at member node")
	_check(CampaignTerritory.get_controller("terr_alpha") == "",
		"territory has no controller (zeon force presence is NOT occupation)")
	var terr := CampaignTerritory.get_territory("terr_alpha")
	_check(not terr.has("occupying_force") and not terr.has("forces"),
		"territory layer holds no force references")
	# Mutating territory control does not mutate force state or presence
	CampaignTerritory.set_controlled("terr_alpha", "federation")
	var f := CampaignForce.get_force("force_1")
	_check(int(f.get("state", -1)) == CampaignForce.ForceState.ACTIVE,
		"force state unaffected by territory control change")
	_check(str(f.get("faction", "")) == "zeon",
		"zeon force faction remains unaffected by federation territory control")
	CampaignTerritory.set_uncontrolled("terr_alpha")


# 4. battle participant != attack/defense role
func _test_battle_participant_not_attack_defense_role() -> void:
	CampaignForce.register_force("force_2", "RIVAL", "federation", "node_s1_city_2_2", "", 1, 20)
	var bid := CampaignBattle.register_battle("battle_alpha", "node_s1_city_2_2", ["force_1", "force_2"])
	_check(bid != "", "battle registered with two participant forces")
	var b := CampaignBattle.get_battle("battle_alpha")
	_check(not b.has("attackers") and not b.has("defenders"),
		"CampaignBattle lists participants symmetrically (no attacker/defender roles)")
	var prep := CampaignBattle.prepare_launch("battle_alpha")
	_check(bool(prep.get("ok", false)), "prepare_launch succeeds")
	var f1 := CampaignForce.get_force("force_1")
	var f2 := CampaignForce.get_force("force_2")
	_check(not f1.has("presence_role") and not f2.has("presence_role"),
		"battle launch assigns no ATTACKING or DEFENDING role to forces")
	_check(int(f1.get("unit_count", 0)) == 3 and int(f2.get("unit_count", 0)) == 1,
		"battle launch preserves force composition")
	CampaignBattle.resolve_battle("battle_alpha")


# 5. patrol stance != force role
func _test_patrol_stance_not_force_role() -> void:
	# Board patrol in PatrolSystem
	GlobalData.board.board_patrols.clear()
	GlobalData.board.board_patrols.append({
		"id": 101,
		"pos": Vector2i(2, 2),
		"home": Vector2i(2, 2),
		"faction": "hostile",
		"aggro": true,
	})
	var f := CampaignForce.get_force("force_1")
	_check(not f.has("aggro") and not f.has("hostile"),
		"force entity does not mirror patrol stance/aggro")
	_check(str(f.get("force_type", "")) == "PATROL",
		"force_type is PATROL (abstract category), distinct from board patrol entity")
	GlobalData.board.board_patrols.clear()


# 6. force_type distinct from presence role
func _test_force_type_distinct_from_role() -> void:
	CampaignForce.register_force("f_convoy", "CONVOY", "federation", "node_s1_city_2_2", "", 2, 5)
	CampaignForce.register_force("f_scav", "SCAVENGER", "scavenger", "node_s1_city_2_2", "", 1, 3)
	var active_forces := CampaignForce.get_active_forces_at_node("node_s1_city_2_2")
	_check(active_forces.has("force_1") and active_forces.has("f_convoy") and active_forces.has("f_scav"),
		"all force types share identical presence querying without role differentiation")


# 7. save/load + reset policy
func _test_save_load_reset_policy() -> void:
	var serialized := CampaignForce.serialize()
	_check(serialized.has("forces"), "serialize produces forces array")
	var rows: Array = serialized.get("forces", [])
	for row in rows:
		_check(not (row as Dictionary).has("presence_role") and not (row as Dictionary).has("role"),
			"serialized row contains no speculative role field")
	_check(SaveGameIO.save_run(), "save_run succeeds")
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "load_run succeeds")
	var loaded_f := CampaignForce.get_force("force_1")
	_check(str(loaded_f.get("node_id", "")) == "node_s1_city_2_2", "restored node_id presence")
	_check(not loaded_f.has("presence_role"), "restored record has no presence_role")
	GlobalData.reset_run_data()
	_check(CampaignForce.get_forces().is_empty(), "reset_run_data clears all forces cleanly")
