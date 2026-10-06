extends Node
## PHASE 5C BATTLE LAUNCH BOUNDARY VERIFY (contract only, NO tactical bridge).
##
## Proves: launch validation rules, PLANNED->ACTIVE on success (never
## RESOLVED), failed launches leave PLANNED, full force immutability,
## reference-only descriptor purity (JSON-serializable, no objects), and
## that launching never touches the tactical combat entry (GameManager
## state/type unchanged — TACTICAL BRIDGE NOT YET SAFE, no bridge faked).
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LAUNCH OK: " + name)
	else:
		_fails += 1
		printerr("LAUNCH FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_valid_launch()
	_test_state_gates()
	_test_node_gate()
	_test_participant_gates()
	_test_immutability()
	_test_descriptor_purity()
	_test_no_tactical_touch()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("BATTLE_LAUNCH_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("BATTLE_LAUNCH_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_BATTLE_LAUNCH_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# Registration: valid battle launches with an exact descriptor.
func _test_valid_launch() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_b", "force_a"])
	var d := CampaignBattle.prepare_launch("battle_x")
	_check(bool(d.get("ok", false)), "valid battle launches")
	_check(str(d.get("battle_id", "")) == "battle_x", "descriptor carries battle id")
	_check(str(d.get("node_id", "")) == "node_s1_city_2_2", "descriptor carries node id")
	_check(d.get("participant_force_ids", []) == ["force_a", "force_b"],
		"descriptor carries sorted force ids")
	_check(CampaignBattle.is_active("battle_x"), "successful launch: PLANNED -> ACTIVE")
	_check(not CampaignBattle.get_state("battle_x") == CampaignBattle.BattleState.RESOLVED,
		"launch never marks RESOLVED")
	var bad := CampaignBattle.prepare_launch("battle_nope")
	_check(not bool(bad.get("ok", true)) and str(bad.get("error", "")) == "unknown_battle",
		"unknown battle rejected")
	CampaignBattle.clear()


# State gates: only PLANNED launches; failures keep PLANNED.
func _test_state_gates() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.prepare_launch("battle_x")
	var again := CampaignBattle.prepare_launch("battle_x")
	_check(not bool(again.get("ok", true)) and str(again.get("error", "")) == "not_planned",
		"ACTIVE rejects duplicate launch")
	CampaignBattle.resolve_battle("battle_x")
	var resolved := CampaignBattle.prepare_launch("battle_x")
	_check(not bool(resolved.get("ok", true)), "RESOLVED rejects launch")
	CampaignBattle.register_battle("battle_y", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.cancel_battle("battle_y")
	var cancelled := CampaignBattle.prepare_launch("battle_y")
	_check(not bool(cancelled.get("ok", true)), "CANCELLED rejects launch")
	CampaignBattle.clear()


# Node gate: node removed after registration blocks launch, battle unharmed.
func _test_node_gate() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	CampaignNodeRegistry.remove_node("node_s1_city_2_2")
	var d := CampaignBattle.prepare_launch("battle_x")
	_check(not bool(d.get("ok", true)) and str(d.get("error", "")) == "invalid_node",
		"removed node blocks launch")
	_check(CampaignBattle.is_planned("battle_x"), "failed launch leaves PLANNED")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignBattle.clear()


# Participant gates: destroyed / unknown / emptied rosters block launch.
func _test_participant_gates() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED)
	var d := CampaignBattle.prepare_launch("battle_x")
	_check(not bool(d.get("ok", true)) and str(d.get("error", "")) == "force_destroyed",
		"destroyed force blocks launch")
	_check(CampaignBattle.is_planned("battle_x"), "failed launch leaves PLANNED")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignBattle.deserialize({"battles": [
		{"id": "battle_ghost", "state": "planned", "node_id": "node_s1_city_2_2",
			"participants": ["force_ghost"]},
	]})
	var g := CampaignBattle.prepare_launch("battle_ghost")
	_check(not bool(g.get("ok", true)) and str(g.get("error", "")) == "unknown_force",
		"unknown force blocks launch")
	CampaignBattle.register_battle("battle_y", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.remove_participant("battle_y", "force_b")
	var e := CampaignBattle.prepare_launch("battle_y")
	_check(not bool(e.get("ok", true)) and str(e.get("error", "")) == "no_participants",
		"emptied roster blocks launch")
	CampaignBattle.clear()


# Immutability: forces byte-identical across a successful launch.
func _test_immutability() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a", "force_b"])
	var before := JSON.stringify([CampaignForce.get_force("force_a"),
		CampaignForce.get_force("force_b")])
	CampaignBattle.prepare_launch("battle_x")
	_check(JSON.stringify([CampaignForce.get_force("force_a"),
		CampaignForce.get_force("force_b")]) == before,
		"unit_count/strength/state/node/base/faction all unchanged by launch")
	_check(CampaignBattle.resolve_battle("battle_x"),
		"launched battle still follows its lifecycle (ACTIVE -> RESOLVED)")
	CampaignBattle.clear()


# Descriptor purity: references/scalars only, JSON-safe, no objects.
func _test_descriptor_purity() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2",
		["force_a", "force_b"])
	var d := CampaignBattle.prepare_launch("battle_x")
	var keys := d.keys()
	keys.sort()
	_check(keys == ["battle_id", "node_id", "ok", "participant_force_ids"],
		"descriptor has exactly the contract keys")
	var clean := true
	for k in d:
		var v = d[k]
		if v is Object:
			clean = false
		if v is Array:
			for item in v:
				if not (item is String):
					clean = false
	_check(clean, "descriptor holds no objects (strings/arrays only)")
	_check(JSON.stringify(d) != "", "descriptor is JSON-serializable")
	CampaignBattle.clear()


# No tactical touch: GameManager combat entry completely unaffected.
func _test_no_tactical_touch() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_a"])
	var state_before: int = GameManager.current_state
	var type_before := str(GameManager.combat_node_type)
	CampaignBattle.prepare_launch("battle_x")
	_check(GameManager.current_state == state_before, "game state untouched by launch")
	_check(str(GameManager.combat_node_type) == type_before,
		"combat entry type untouched by launch (no bridge faked)")
	CampaignBattle.clear()
