extends Node
## PHASE 5N FORCE ORDERS / OPERATIONAL INTENT BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): campaign operational intent is NOT YET
## MODELED. No order/mission/directive authority exists: the only
## order-named class (ExtractionMissionSelect) is board extraction UI with
## zero CampaignForce contact; patrol "targets" are board tiles for
## merge/chase stepping; board "objectives/goals" are the PLAYER's sector
## goal tiles. CampaignForce carries no order-like field (record is exactly
## the 8 locked keys), and registration / relocation / base-link / battle
## participation / territory context / turn advancement / save / reset
## create none. force_type classifies the entity (never an order); node_id
## stays current presence (never destination intent); participants stay
## identity (never attack/defense intent); base links stay links (never
## garrison intent). 5K/5L/5M boundaries hold.
## User save backed up/restored.

const ORDER_LIKE_KEYS := ["order", "orders", "mission", "objective",
	"target_node", "destination", "destination_node", "goal", "command",
	"directive", "intent", "behavior", "stance", "task", "assignment",
	"operation", "operation_state", "role", "presence_role",
	"garrison", "occupation", "staging", "transit", "reserve",
	"attack", "defend", "defense", "retreat", "escort", "reinforce",
	"intercept", "capture", "occupy", "hold", "guard", "withdraw",
	"deploy", "resupply", "investigate", "recon", "waypoint", "route",
	"current_route", "path", "destination_queue"]

const FORCE_KNOWN_KEYS := ["id", "force_type", "state", "faction",
	"node_id", "base_id", "unit_count", "strength"]

const BATTLE_KNOWN_KEYS := ["id", "state", "node_id", "participants",
	"session_ref"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ORDER OK: " + name)
	else:
		_fails += 1
		printerr("ORDER FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_registration_creates_no_intent()
	_test_relocation_creates_no_destination()
	_test_base_link_creates_no_garrison()
	_test_battle_creates_no_attack_defend()
	_test_territory_creates_no_defense()
	_test_force_type_is_not_order()
	_test_turn_creates_no_orders()
	_test_patrol_encounter_outside_forces()
	_test_boundaries_hold()
	_test_no_order_authority()
	_test_persistence_has_no_orders()
	_test_reset()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_ORDER_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_ORDER_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_ORDER_BOUNDARY_TESTS_PASSED")
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
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


func _has_order_like_key(d: Dictionary) -> bool:
	for k in ORDER_LIKE_KEYS:
		if d.has(k):
			return true
	return false


func _check_exact_force_schema(fid: String, label: String) -> void:
	var f := CampaignForce.get_force(fid)
	_check(not _has_order_like_key(f), "no order-like field on %s (%s)" % [fid, label])
	var keys := (f as Dictionary).keys()
	keys.sort()
	var want := FORCE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "record schema exactly the 8 locked keys (%s)" % label)


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# 1-2. Registration classifies the entity; no operational intent is born.
func _test_registration_creates_no_intent() -> void:
	_check_exact_force_schema("force_a", "PATROL at city")
	_check_exact_force_schema("force_b", "SCAVENGER at safehouse")
	_check(CampaignForce.register_force("force_n", "CONVOY", "zeon",
		"node_s1_city_2_2", "", 1, 5) == "force_n", "new CONVOY registers")
	_check_exact_force_schema("force_n", "fresh registration")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 3. set_node() stays relocation (5K): no destination/target intent recorded.
func _test_relocation_creates_no_destination() -> void:
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"), "force relocates")
	_check_exact_force_schema("force_a", "after relocation")
	_check(CampaignForce.set_node("force_a", ""), "force clears to off-board")
	_check_exact_force_schema("force_a", "after off-board clear")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")


# 4. set_base() stays a link: no garrison/station/reserve intent recorded.
func _test_base_link_creates_no_garrison() -> void:
	_check(CampaignForce.set_base("force_a", "base_alpha"), "force attaches to base")
	_check_exact_force_schema("force_a", "while attached")
	_check(CampaignForce.set_base("force_a", ""), "force detaches")
	_check_exact_force_schema("force_a", "after detach")


# 5. Participation stays identity: no attack/defense/target intent, on
# forces or on the battle record, across the full lifecycle.
func _test_battle_creates_no_attack_defend() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_o", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_o", "forces seed a battle")
	_check_exact_force_schema("force_a", "as participant")
	var b := CampaignBattle.get_battle("battle_o")
	_check(not _has_order_like_key(b), "battle record carries no order field")
	var keys := b.keys()
	keys.sort()
	var want := BATTLE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "battle schema exactly the 5 locked keys")
	CampaignBattle.begin_battle("battle_o")
	CampaignBattle.resolve_battle("battle_o")
	_check_exact_force_schema("force_a", "after battle resolved")
	_check(not _has_order_like_key(CampaignBattle.get_battle("battle_o")),
		"resolved battle still carries no order field")
	CampaignBattle.clear()


# 6. Territory context grants no defend/occupy intent to the force.
func _test_territory_creates_no_defense() -> void:
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	_check(CampaignForce.get_territory_context("force_a") == "terr_downtown",
		"force derives territory context")
	_check_exact_force_schema("force_a", "inside controlled territory")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before,
		"presence writes no territory state (no occupation intent)")


# 7. force_type classifies; every type shares the identical intent-free schema.
func _test_force_type_is_not_order() -> void:
	for t in ["PATROL", "CONVOY", "SCAVENGER", "RIVAL"]:
		var fid: String = "force_t_" + str(t).to_lower()
		_check(CampaignForce.register_force(fid, t, "zeon",
			"node_s1_city_2_2", "", 1, 5) == fid, "type %s registers" % t)
		_check_exact_force_schema(fid, "type %s shares intent-free schema" % t)
		CampaignForce.clear()
		CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
		CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 8. Turn sequencing issues no commands: forces byte-identical, no intent.
func _test_turn_creates_no_orders() -> void:
	var before := JSON.stringify(CampaignForce.get_forces())
	CampaignTurnExecutive.advance_campaign_turn("order_probe", {"day_boundary": false})
	CampaignTurnExecutive.advance_campaign_turn("order_probe", {})
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"turns leave forces byte-identical (no command issuance)")
	_check_exact_force_schema("force_a", "after turns")
	_check_exact_force_schema("force_b", "after turns")


# 11-12. Patrol stance and board encounters stay outside CampaignForce.
func _test_patrol_encounter_outside_forces() -> void:
	var patrols_before: int = GlobalData.board.board_patrols.size()
	CampaignForce.set_node("force_a", "node_s1_safehouse_2_3")
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED)
	CampaignBattle.register_battle("battle_e", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.begin_battle("battle_e")
	_check(GlobalData.board.board_patrols.size() == patrols_before,
		"force ops churn no patrol behavior (stance stays board-owned)")
	CampaignBattle.clear()
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	_check(not _code_of("res://scripts/systems/patrol_system.gd").contains("CampaignForce"),
		"patrol code never references CampaignForce")
	_check(not _code_of("res://scripts/ui/extraction_mission_select.gd").contains("CampaignForce"),
		"mission-select UI never references CampaignForce (player-scope only)")


# 13-15. 5M/5L/5K boundaries hold: no detection, supply, or movement shadow.
func _test_boundaries_hold() -> void:
	for f in CampaignForce.get_forces():
		_check(not f.has("supply") and not f.has("supply_status")
			and not f.has("detected") and not f.has("visible")
			and not f.has("intel") and not f.has("last_known_node_id"),
			"force %s keeps 5L/5M absence" % str(f.get("id", "")))
	_check(CampaignForce.set_node("force_b", "node_s1_city_2_2")
		and not CampaignForce.set_node("force_b", "node_nope"),
		"5K relocation contract intact (known sets, unknown rejects)")


# Negative tests: no order authority exists; force source has no order concept.
func _test_no_order_authority() -> void:
	var force_code := _code_of("res://scripts/systems/campaign_force.gd").to_lower()
	var clean := true
	for token in ["order", "mission", "directive", "intent", "stance",
			"destination", "objective", "waypoint", "garrison", "occupation",
			"escort", "intercept", "reinforce", "staging", "transit"]:
		if force_code.contains(token):
			clean = false
	_check(clean, "force source has no order concept (code, not comments)")
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
				if n.contains("order_manager") or n.contains("mission_manager") \
						or n.contains("command_manager") or n.contains("strategic_ai") \
						or n.contains("operations_manager") or n.contains("force_order") \
						or n.contains("force_ai") or n.contains("campaign_ai"):
					found_manager = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_manager, "no order/mission/command/AI manager file exists")


# 9. Save rows and load results carry no order state; schema unchanged.
func _test_persistence_has_no_orders() -> void:
	CampaignBattle.register_battle("battle_sv", "node_s1_city_2_2", ["force_a"])
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	for row in ((d as Dictionary).get("forces", {}) as Dictionary).get("forces", []):
		if _has_order_like_key(row):
			clean = false
	_check(clean, "saved force rows carry no order field (schema unchanged)")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces")
	_check_exact_force_schema("force_a", "after load")
	CampaignBattle.clear()


# 10. Reset issues no intent and leaves no residue.
func _test_reset() -> void:
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 2, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	_check_exact_force_schema("force_a", "post-reset")
	CampaignBattle.clear()
