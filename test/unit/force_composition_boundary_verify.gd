extends Node
## PHASE 5D FORCE COMPOSITION BOUNDARY VERIFY (Outcome B minimal contract).
##
## Proves the composition boundary is exactly a pure read of abstract
## campaign composition: stable identity, exact key set (no roster keys),
## no fabricated units, persistence through the existing force record, and
## zero mutation of patrols/hangar/combat/battles/forces. No rosters are
## resolved, no tactical units created. User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("COMPOSITION OK: " + name)
	else:
		_fails += 1
		printerr("COMPOSITION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_contract_shape()
	_test_no_duplication()
	_test_no_fabrication()
	_test_persistence()
	_test_isolation()
	_test_unknown()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("FORCE_COMPOSITION_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FORCE_COMPOSITION_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_COMPOSITION_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 5, 80)


# Identity: contract references the correct stable force.
func _test_contract_shape() -> void:
	var c := CampaignForce.describe_composition("force_a")
	_check(str(c.get("force_id", "")) == "force_a", "contract references correct force")
	_check(str(c.get("force_type", "")) == "PATROL", "contract carries force type")
	_check(int(c.get("unit_count", -1)) == 5, "contract carries unit_count")
	_check(int(c.get("strength", -1)) == 80, "contract carries strength")
	var keys := c.keys()
	keys.sort()
	_check(keys == ["force_id", "force_type", "strength", "unit_count"],
		"contract has exactly the four boundary keys")
	_check(CampaignForce.describe_composition("force_a") == c,
		"repeated reads identical (pure read)")


# No duplication: no roster/pilot/mecha/weapon keys from any owner.
func _test_no_duplication() -> void:
	var c := CampaignForce.describe_composition("force_a")
	for k in ["pilots", "pilot", "mecha", "mechas", "weapons", "roster",
			"fleet_roster", "loadout", "wave", "spawn", "units", "members"]:
		_check(not c.has(k), "no duplicated roster key: " + k)
	_check(JSON.stringify(c) != "", "contract is JSON-serializable (scalars only)")


# No fabrication: N units never become N pilot/mecha entries.
func _test_no_fabrication() -> void:
	var c := CampaignForce.describe_composition("force_a")
	var fabricated := false
	for k in c:
		var v = c[k]
		if v is Array and not (v as Array).is_empty():
			fabricated = true
		if v is Dictionary and not (v as Dictionary).is_empty():
			fabricated = true
	_check(not fabricated, "no fabricated unit entries (no arrays/dicts)")
	_check(int(c.get("unit_count", -1)) == 5, "count stays abstract (not expanded)")


# Persistence: contract follows the existing force record through save/load.
func _test_persistence() -> void:
	_check(SaveGameIO.save_run(), "save_run reports success")
	CampaignForce.clear()
	_check(SaveGameIO.load_run(), "load_run restores force record")
	var c := CampaignForce.describe_composition("force_a")
	_check(int(c.get("unit_count", -1)) == 5 and int(c.get("strength", -1)) == 80,
		"contract reflects restored force (no separate persistence needed)")
	CampaignForce.clear()


# Isolation: reading the boundary mutates nothing anywhere.
func _test_isolation() -> void:
	_seed_world()
	var patrols_before := JSON.stringify(GlobalData.board.board_patrols)
	var hangar_before := JSON.stringify(GlobalData.hangar.hangar_mechs)
	var battles_before := JSON.stringify(CampaignBattle.serialize())
	var force_before := JSON.stringify(CampaignForce.get_force("force_a"))
	for i in range(3):
		CampaignForce.describe_composition("force_a")
	_check(JSON.stringify(GlobalData.board.board_patrols) == patrols_before,
		"patrols untouched")
	_check(JSON.stringify(GlobalData.hangar.hangar_mechs) == hangar_before,
		"hangar untouched")
	_check(JSON.stringify(CampaignBattle.serialize()) == battles_before,
		"battles untouched")
	_check(JSON.stringify(CampaignForce.get_force("force_a")) == force_before,
		"force record untouched by its own boundary read")


# Unknown force reads empty (no invented composition).
func _test_unknown() -> void:
	_check(CampaignForce.describe_composition("force_nope").is_empty(),
		"unknown force reads empty")
