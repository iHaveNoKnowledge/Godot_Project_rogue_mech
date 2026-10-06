extends Node
## PHASE 5S ACTION / CROSS-DOMAIN ORCHESTRATION BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): cross-domain campaign orchestration is NOT
## YET MODELED. No action/command/mission manager, bus, queue, or
## transaction system exists; every campaign authority mutates ONLY its
## own state through low-level validated primitives, and no production
## operation touches two authorities at once. CampaignTurnExecutive is a
## turn-only sequencer (economy -> spy/base -> day fan-out -> rival ->
## era -> scavenger) with zero references to Force/Territory/Base/Battle/
## Node — its receipt is a turn receipt (counter + phases + outputs), not
## a generic action receipt, with no rollback/atomicity concept. EventBus
## campaign signals (board_day_ended, campaign_turn_completed) are pure
## notifications whose handlers (fuel/research/recruit/heat) never write
## campaign authorities. Future Move/Capture-style actions stay unmodeled.
## User save backed up/restored.

const TURN_PHASES := ["begin_turn", "faction_economy", "spy", "enemy_base",
	"board_day_compatibility", "rival", "era", "scavenger", "end_turn"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ORCHESTRATION OK: " + name)
	else:
		_fails += 1
		printerr("ORCHESTRATION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_force_primitive_isolation()
	_test_territory_primitive_isolation()
	_test_base_primitive_isolation()
	_test_battle_primitive_isolation()
	_test_turn_scope()
	_test_event_isolation()
	_test_no_orchestration_authority()
	_test_save_reset_clean()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_ACTION_ORCHESTRATION_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_ACTION_ORCHESTRATION_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_ACTION_ORCHESTRATION_BOUNDARY_TESTS_PASSED")
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


func _snap_all() -> Dictionary:
	return {
		"forces": JSON.stringify(CampaignForce.get_forces()),
		"territories": JSON.stringify(CampaignTerritory.serialize()),
		"bases": JSON.stringify(CampaignBase.get_bases()),
		"battles": JSON.stringify(CampaignBattle.get_battles()),
		"turn": CampaignTurnExecutive.get_turn(),
	}


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# Scenario A — each Force primitive writes only its own key.
func _test_force_primitive_isolation() -> void:
	var b := _snap_all()
	CampaignForce.set_node("force_a", "node_s1_safehouse_2_3")
	var a := _snap_all()
	_check(a["forces"] != b["forces"], "set_node writes force state (sanity)")
	_check(a["territories"] == b["territories"] and a["bases"] == b["bases"]
		and a["battles"] == b["battles"] and a["turn"] == b["turn"],
		"set_node touches no other authority")
	var rel_before: int = FactionSystem.get_relation("zeon", "federation")
	CampaignForce.set_base("force_a", "base_alpha")
	CampaignForce.set_faction("force_a", "federation")
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED)
	CampaignForce.set_composition("force_a", 4, 12)
	var c := _snap_all()
	_check(c["territories"] == b["territories"] and c["bases"] == b["bases"]
		and c["battles"] == b["battles"] and c["turn"] == b["turn"],
		"base/faction/state/composition writes touch no other authority")
	_check(FactionSystem.get_relation("zeon", "federation") == rel_before,
		"force faction write touches no relation matrix")
	CampaignForce.set_composition("force_a", 3, 10)
	CampaignForce.set_state("force_a", CampaignForce.ForceState.ACTIVE)
	CampaignForce.set_faction("force_a", "zeon")
	CampaignForce.set_base("force_a", "")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")
	_check(JSON.stringify(CampaignForce.get_forces()) != "", "forces restored (sanity)")


# Scenario B — territory primitives write only territory state.
func _test_territory_primitive_isolation() -> void:
	var b := _snap_all()
	_check(CampaignTerritory.set_contested("terr_downtown", ["zeon", "outland"]),
		"territory contests explicitly")
	var a := _snap_all()
	_check(a["forces"] == b["forces"] and a["bases"] == b["bases"]
		and a["battles"] == b["battles"] and a["turn"] == b["turn"],
		"set_contested touches no other authority")
	_check(CampaignTerritory.set_controlled("terr_downtown", "federation"),
		"territory control restored explicitly")
	_check(CampaignTerritory.set_uncontrolled("terr_downtown"), "territory cleared explicitly")
	var c := _snap_all()
	_check(c["forces"] == b["forces"] and c["bases"] == b["bases"]
		and c["battles"] == b["battles"],
		"set_uncontrolled touches no other authority")
	_check(CampaignTerritory.set_controlled("terr_downtown", "federation"), "control restored")


# Scenario C — base primitives write only base state.
func _test_base_primitive_isolation() -> void:
	var b := _snap_all()
	_check(CampaignBase.set_controller("base_alpha", "zeon"), "base controller transfers")
	var a := _snap_all()
	_check(a["forces"] == b["forces"] and a["territories"] == b["territories"]
		and a["battles"] == b["battles"] and a["turn"] == b["turn"],
		"set_controller touches no other authority")
	_check(CampaignBase.set_state("base_alpha", CampaignBase.BaseState.DISABLED),
		"base disables explicitly")
	_check(CampaignBase.set_state("base_alpha", CampaignBase.BaseState.ACTIVE),
		"base reactivates explicitly")
	_check(CampaignBase.set_territory("base_alpha", "terr_downtown"),
		"base territory link rewrites explicitly")
	var c := _snap_all()
	_check(c["forces"] == b["forces"] and c["territories"] == b["territories"]
		and c["battles"] == b["battles"],
		"base lifecycle touches no other authority")
	_check(CampaignBase.set_controller("base_alpha", "federation"), "controller restored")


# Scenario D — battle primitives move only battle lifecycle state.
func _test_battle_primitive_isolation() -> void:
	CampaignBattle.clear()
	var b := _snap_all()
	_check(CampaignBattle.register_battle("battle_o", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_o", "battle registers")
	_check(bool(CampaignBattle.prepare_launch("battle_o").get("ok", false)), "battle launches")
	_check(CampaignBattle.resolve_battle("battle_o"), "battle resolves")
	var a := _snap_all()
	_check(a["forces"] == b["forces"] and a["territories"] == b["territories"]
		and a["bases"] == b["bases"] and a["turn"] == b["turn"],
		"register + launch + resolve touch no other authority")
	CampaignBattle.register_battle("battle_c", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.cancel_battle("battle_c")
	_check(JSON.stringify(CampaignForce.get_forces()) == b["forces"]
		and JSON.stringify(CampaignTerritory.serialize()) == b["territories"]
		and JSON.stringify(CampaignBase.get_bases()) == b["bases"],
		"cancel touches no other authority")
	CampaignBattle.clear()


# Scenario E — turn advances time only: counter +1, receipt is turn-shaped,
# campaign authorities byte-identical.
func _test_turn_scope() -> void:
	var b := _snap_all()
	var receipt: Dictionary = CampaignTurnExecutive.advance_campaign_turn("orchestration_probe", {})
	_check(bool(receipt.get("ok", false)), "turn executes")
	var a := _snap_all()
	_check(a["forces"] == b["forces"] and a["territories"] == b["territories"]
		and a["bases"] == b["bases"] and a["battles"] == b["battles"],
		"turn touches no campaign authority (not a generic executor)")
	_check(int(a["turn"]) == int(b["turn"]) + 1, "turn counter advances exactly once (time only)")
	_check(str(receipt.get("reason", "")) == "orchestration_probe"
		and receipt.has("phases") and receipt.has("turn"),
		"receipt is turn-shaped (counter + phases + outputs)")
	for phase in receipt.get("phases", []):
		_check(TURN_PHASES.has(str(phase)), "receipt phase is a known turn phase: %s" % str(phase))
	_check(not receipt.has("forces") and not receipt.has("territory")
		and not receipt.has("battle") and not receipt.has("action"),
		"receipt carries no authority payload (no generic action receipt)")


# Scenario G — notifications never become hidden mutation authorities.
func _test_event_isolation() -> void:
	_check(EventBus.has_signal("board_day_ended"), "day fan-out signal exists (notification)")
	_check(EventBus.has_signal("campaign_turn_completed"), "turn-complete signal exists (notification)")
	_check(not EventBus.has_signal("campaign_action")
		and not EventBus.has_signal("force_moved")
		and not EventBus.has_signal("territory_captured")
		and not EventBus.has_signal("base_captured"),
		"no action/outcome signals exist (nothing to hide behind)")
	var b := _snap_all()
	EventBus.board_day_ended.emit()
	var a := _snap_all()
	_check(a["forces"] == b["forces"] and a["territories"] == b["territories"]
		and a["bases"] == b["bases"] and a["battles"] == b["battles"],
		"day fan-out handlers write no campaign authority")


# Static guards: no orchestrator files; turn source is campaign-free.
func _test_no_orchestration_authority() -> void:
	_check(not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignForce")
		and not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignTerritory")
		and not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignBase")
		and not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignBattle")
		and not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignNodeRegistry"),
		"turn source references no campaign authority (code, not comments)")
	var found := false
	for dir_path in ["res://scripts/systems", "res://scripts/board", "res://scripts/war"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				var n := entry.to_lower()
				if n.contains("campaign_action") or n.contains("campaign_command") \
						or n.contains("campaign_operation") or n.contains("campaign_mission") \
						or n.contains("strategic_action") or n.contains("campaign_orchestrat") \
						or n.contains("campaign_transaction") or n.contains("action_manager") \
						or n.contains("command_bus") or n.contains("operations_manager"):
					found = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found, "no action/command/orchestrator manager file exists")


# Scenario H — no action persistence; reset leaves no action state.
func _test_save_reset_clean() -> void:
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	for k in (d as Dictionary).keys():
		var kl := str(k).to_lower()
		# Whole-token match only: "faction_relations" must NOT trip on "action".
		if (kl == "action" or kl.contains("_action_") or kl.begins_with("action_")
				or kl.ends_with("_action") or kl.contains("transaction")
				or kl.contains("rollback") or kl.contains("orchestrat")
				or kl.contains("command")):
			clean = false
	_check(clean, "save payload has no action/orchestration keys")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores state")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignTurnExecutive.get_turn() == 0, "reset clears turn counter")
	_check(CampaignTurnExecutive.get_last_receipt().is_empty(), "reset clears turn receipt")
	_check(CampaignForce.get_forces().size() == 2
		and CampaignBattle.get_battles().is_empty()
		and CampaignTerritory.get_controller("terr_downtown") == "federation",
		"reset restores seeds with no stale action state")
	CampaignBattle.clear()
