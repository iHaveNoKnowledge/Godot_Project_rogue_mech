extends Node
## PHASE 5R FORCE STRATEGIC EFFECTS / TERRITORY & BASE CONTROL BOUNDARY VERIFY.
##
## Audited answer (Option D): CampaignForce has NO strategic effect on
## CampaignTerritory or CampaignBase. Presence is not control, faction is
## not controller, attachment is not garrison, battle victory is not
## capture, destruction is not loss. Territory control APIs
## (set_controlled/set_contested/set_uncontrolled) and base APIs
## (set_controller/set_state) exist but have ZERO production callers —
## they are authority-owned primitives for a future system, never driven
## by forces, battles, turns, patrols, or tactical combat. The sole
## production bridge (BoardManager -> sync_legacy_enemy_base) syncs a
## RESEARCH_BASE record from legacy narrative state with zero force
## contact and a permanently empty controller. Membership stays topology;
## control stays mutable territory-owned state.
## User save backed up/restored.

const FORCE_KNOWN_KEYS := ["id", "force_type", "state", "faction",
	"node_id", "base_id", "unit_count", "strength"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("STRATEGIC OK: " + name)
	else:
		_fails += 1
		printerr("STRATEGIC FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_same_faction_colocation()
	_test_cross_faction_colocation()
	_test_base_attachment_no_capture()
	_test_foreign_attachment_no_takeover()
	_test_presence_vs_controller()
	_test_destruction_no_loss()
	_test_battle_victory_no_capture()
	_test_turn_derives_no_control()
	_test_authorities_remain_usable()
	_test_no_control_authority()
	_test_persistence_reset()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_STRATEGIC_EFFECTS_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_STRATEGIC_EFFECTS_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_STRATEGIC_EFFECTS_TESTS_PASSED")
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
	CampaignTerritory.set_controlled("terr_downtown", "federation")
	CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "OUTPOST",
		"federation", "terr_downtown")
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


func _territory_snapshot() -> String:
	return JSON.stringify(CampaignTerritory.serialize())


func _base_snapshot() -> String:
	return JSON.stringify(CampaignBase.get_base("base_alpha"))


func _check_control_intact(terr_before: String, base_before: String, label: String) -> void:
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before,
		"territory control untouched (%s)" % label)
	_check(JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"base controller/state untouched (%s)" % label)
	_check(CampaignTerritory.get_controller("terr_downtown") == "federation",
		"controller still federation (%s)" % label)
	_check(CampaignTerritory.get_contesting("terr_downtown").is_empty(),
		"no auto-contest (%s)" % label)


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# Scenario A — same-faction co-location changes nothing.
func _test_same_faction_colocation() -> void:
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	_check(CampaignForce.register_force("force_d", "CONVOY", "zeon",
		"node_s1_city_2_2", "", 1, 5) == "force_d", "second zeon force co-locates")
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2") == ["force_a", "force_d"],
		"both present (presence only)")
	_check_control_intact(terr, base, "same-faction co-location")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# Scenario B — cross-faction co-location: no capture, no contest.
func _test_cross_faction_colocation() -> void:
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	_check(CampaignForce.set_node("force_b", "node_s1_city_2_2"), "outland force joins zeon node")
	_check_control_intact(terr, base, "cross-faction co-location")
	CampaignForce.set_node("force_b", "node_s1_safehouse_2_3")


# Scenario C — attachment is a link, not a capture.
func _test_base_attachment_no_capture() -> void:
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	_check(CampaignForce.set_base("force_a", "base_alpha"), "force attaches to base")
	_check_control_intact(terr, base, "base attachment")
	_check(str(CampaignForce.get_force("force_a").get("base_id", "")) == "base_alpha",
		"attachment link itself recorded (reference only)")
	CampaignForce.set_base("force_a", "")


# Scenario D — foreign-faction attachment is not a takeover.
func _test_foreign_attachment_no_takeover() -> void:
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	_check(CampaignForce.set_base("force_b", "base_alpha"), "outland force attaches")
	_check_control_intact(terr, base, "foreign attachment")
	CampaignForce.set_base("force_b", "")


# Scenario E — presence under a foreign controller changes nothing.
func _test_presence_vs_controller() -> void:
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	_check(CampaignForce.set_node("force_b", "node_s1_city_2_2"), "outland force enters node")
	_check(str(CampaignForce.get_force("force_b").get("faction", "")) == "outland",
		"force faction unchanged by foreign control")
	_check_control_intact(terr, base, "presence vs controller")
	var members: Array = CampaignTerritory.get_members("terr_downtown").duplicate()
	members.sort()
	_check(members == ["node_s1_city_2_2", "node_s1_safehouse_2_3"],
		"membership still pure topology (no force members)")
	CampaignForce.set_node("force_b", "node_s1_safehouse_2_3")


# Scenario F — destruction causes no loss, no capture, no demolition.
func _test_destruction_no_loss() -> void:
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	CampaignForce.set_base("force_a", "base_alpha")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"attached force destroyed")
	_check_control_intact(terr, base, "force destruction")
	_check(CampaignForce.has_force("force_a")
		and str(CampaignForce.get_force("force_a").get("base_id", "")) == "base_alpha",
		"destroyed record + link retained (no cleanup inference)")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# Scenario G — cross-faction battle victory captures nothing.
func _test_battle_victory_no_capture() -> void:
	CampaignBattle.clear()
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	_check(CampaignBattle.register_battle("battle_g", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_g", "cross-faction battle registers")
	_check(bool(CampaignBattle.prepare_launch("battle_g").get("ok", false)), "battle launches")
	_check(CampaignBattle.resolve_battle("battle_g"), "battle resolves (victory abstract)")
	_check_control_intact(terr, base, "battle victory")
	CampaignBattle.clear()


# Scenario H — turns derive no control from presence/mismatch/co-location.
func _test_turn_derives_no_control() -> void:
	CampaignForce.set_node("force_b", "node_s1_city_2_2")
	var terr := _territory_snapshot()
	var base := _base_snapshot()
	CampaignTurnExecutive.advance_campaign_turn("strategic_probe", {"day_boundary": false})
	CampaignTurnExecutive.advance_campaign_turn("strategic_probe", {})
	_check_control_intact(terr, base, "turn advancement")
	CampaignForce.set_node("force_b", "node_s1_safehouse_2_3")


# Authority-owned writes still work (future systems keep usable primitives).
func _test_authorities_remain_usable() -> void:
	_check(CampaignTerritory.set_contested("terr_downtown", ["zeon", "outland"]),
		"territory authority can contest explicitly")
	_check(CampaignTerritory.is_contested("terr_downtown"), "contested state reads back")
	_check(CampaignTerritory.set_controlled("terr_downtown", "federation"),
		"territory authority can restore control explicitly")
	_check(CampaignBase.set_controller("base_alpha", "zeon"), "base authority can transfer control")
	_check(str(CampaignBase.get_base("base_alpha").get("controller", "")) == "zeon",
		"controller transfer lands (explicit write only)")
	_check(CampaignBase.set_controller("base_alpha", "federation"), "controller restored")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon"
		and str(CampaignForce.get_force("force_b").get("faction", "")) == "outland",
		"explicit control writes change no force faction (one-way separation)")


# Negative tests: no control concept in force code; no force bridge in
# territory/base/battle/turn code; no manager files.
func _test_no_control_authority() -> void:
	var force_code := _code_of("res://scripts/systems/campaign_force.gd").to_lower()
	var clean := true
	for token in ["control", "captur", "occup", "garrison", "influence",
			"siege", "takeover", "pressure"]:
		if force_code.contains(token):
			clean = false
	_check(clean, "force source has no control concept (code, not comments)")
	var separate := true
	for path in ["res://scripts/systems/campaign_territory.gd",
			"res://scripts/systems/campaign_base.gd",
			"res://scripts/systems/campaign_turn_executive.gd",
			"res://scripts/systems/patrol_system.gd"]:
		if _code_of(path).contains("CampaignForce"):
			separate = false
	_check(separate, "territory/base/turn/patrol code never touches forces")
	var battle_code := _code_of("res://scripts/systems/campaign_battle.gd")
	var battle_writes := false
	for token in ["set_controlled", "set_contested", "set_uncontrolled",
			"set_controller", "register_territory", "register_base",
			"set_territory", "set_members"]:
		if battle_code.contains(token):
			battle_writes = true
	_check(not battle_writes,
		"battle code never writes territory or base (read-only context derivation only)")
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
				if n.contains("occupation") or n.contains("garrison") \
						or n.contains("influence") or n.contains("control_manager") \
						or n.contains("strategic_control") or n.contains("siege"):
					found_manager = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_manager, "no occupation/garrison/control manager file exists")


# Persistence: control states round-trip; forces stay 8-key; reset clean.
func _test_persistence_reset() -> void:
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var saved_rows: Array = ((d as Dictionary).get("territories", {}) as Dictionary).get("territories", [])
	var saved_control := ""
	for row in saved_rows:
		if str((row as Dictionary).get("id", "")) == "terr_downtown":
			saved_control = str((row as Dictionary).get("controller", ""))
	_check(saved_control == "federation",
		"territory control persisted verbatim in save (authority persists)")
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores state")
	_check(CampaignTerritory.get_controller("terr_downtown") == "federation",
		"territory control survives save/load")
	_check(str(CampaignBase.get_base("base_alpha").get("controller", "")) == "federation",
		"base controller survives save/load")
	var f: Dictionary = CampaignForce.get_force("force_a")
	var keys: Array = f.keys()
	keys.sort()
	var want: Array = FORCE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "loaded force schema still exactly 8 keys")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignTerritory.get_controller("terr_downtown") == "federation",
		"seed control restored after reset")
	_check(CampaignForce.get_forces().size() == 2
		and CampaignBattle.get_battles().is_empty(),
		"reset clears forces/battles per existing contracts")
	CampaignBattle.clear()
