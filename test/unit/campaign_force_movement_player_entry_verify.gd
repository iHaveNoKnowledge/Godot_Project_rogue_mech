extends Node
## PHASE 5U MOVEMENT PLAYER ENTRY VERIFY (minimal game-facing entry point).
##
## Locks the 5U interaction loop: panel lists forces from canonical state,
## selection exposes the canonical node, destinations are exactly the
## one-hop strategic neighbors, Move goes ONLY through
## CampaignForceMovement.move_force(), and the panel refreshes from
## canonical state afterwards. Failures mutate nothing and surface the
## authority reason. The panel owns transient selection/display only: no
## PlayerForce fabrication, no direct set_node, no costs, no battles,
## no territory/base/faction/turn effects, no persisted orders.
## User save backed up/restored.

const CITY := "node_s1_city_2_2"
const SAFE := "node_s1_safehouse_2_3"
const DEPOT := "node_s1_fuel_depot_5_5"

var _fails := 0
var _checks := 0
var _backup := ""
var _panel: CampaignForceMovementPanel


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ENTRY OK: " + name)
	else:
		_fails += 1
		printerr("ENTRY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_panel = CampaignForceMovementPanel.new()
	add_child(_panel)
	await get_tree().process_frame
	_test_selection_and_display()
	_test_destinations()
	_test_move_through_authority()
	_test_failures()
	_test_inactive_forces()
	_test_colocation_and_hostile()
	_test_isolation()
	_test_transience_and_guards()
	_test_save_reset()
	_panel.queue_free()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_MOVEMENT_PLAYER_ENTRY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_MOVEMENT_PLAYER_ENTRY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_MOVEMENT_PLAYER_ENTRY_TESTS_PASSED")
		get_tree().quit(0)


func _seed_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	CampaignNodeRegistry.register_node(1, Vector2i(2, 3), "safehouse")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "fuel_depot")
	CampaignNodeRegistry.register_route(CITY, SAFE)
	CampaignTerritory.register_territory("terr_downtown", [CITY, SAFE])
	CampaignTerritory.set_controlled("terr_downtown", "federation")
	CampaignBase.register_base("base_alpha", CITY, "OUTPOST", "federation", "terr_downtown")
	CampaignForce.register_force("force_a", "PATROL", "zeon", CITY, "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", SAFE, "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)
	CampaignForce.register_force("force_d", "CONVOY", "zeon", CITY, "", 1, 5)
	CampaignForce.set_state("force_d", CampaignForce.ForceState.DISABLED)
	CampaignForce.register_force("force_e", "PATROL", "outland", SAFE, "", 2, 6)
	CampaignForce.set_state("force_e", CampaignForce.ForceState.DESTROYED)


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


# A–B. Selection lists canonical forces; display shows the canonical node.
func _test_selection_and_display() -> void:
	_check(_panel.refresh_forces() == ["force_a", "force_b", "force_c", "force_d", "force_e"],
		"A — panel lists every force from canonical state")
	_check(not _panel.select_force("force_nope"), "unknown force selection rejected")
	_check(_panel.get_selected_force_id() == "", "rejected selection keeps empty state")
	_check(_panel.select_force("force_a"), "A — valid force selects")
	_check(_panel.get_selected_force_id() == "force_a", "selection stored transiently")
	var f: Dictionary = _panel.get_selected_force()
	_check(str(f.get("node_id", "")) == CITY
		and str(f.get("node_id", "")) == str(CampaignForce.get_force("force_a").get("node_id", "")),
		"B — display reads the canonical node_id")
	var lines: Array = _panel.get_force_display_lines()
	_check(lines.size() == 5 and str(lines[0]).contains("force_a")
		and str(lines[0]).contains(CITY), "display lines carry id + current node")


# C–D. One-hop discovery only.
func _test_destinations() -> void:
	_panel.select_force("force_a")
	_check(_panel.get_destinations() == [SAFE], "C — direct neighbor offered")
	_check(not _panel.get_destinations().has(DEPOT), "D — two-hop node excluded")
	_check(not _panel.select_destination(DEPOT), "D — non-neighbor selection rejected")
	_check(_panel.get_selected_destination() == "", "rejected destination keeps empty state")
	_check(_panel.select_destination(SAFE), "destination selects when offered")
	_panel.select_force("force_c")
	_check(_panel.get_destinations().is_empty(), "off-board force offers nothing")


# E–G. The Move path goes through the authority and refreshes canonically.
func _test_move_through_authority() -> void:
	_panel.select_force("force_a")
	_panel.select_destination(SAFE)
	var r: Dictionary = _panel.execute_move()
	_check(bool(r.get("ok", false)) and str(r.get("reason", "")) == "moved",
		"F — panel move succeeds with authority receipt")
	_check(str(CampaignForce.get_force("force_a").get("node_id", "")) == SAFE,
		"F — canonical node changed")
	_check(_panel.get_selected_destination() == "",
		"consumed destination cleared (no persisted intent)")
	var f: Dictionary = _panel.get_selected_force()
	_check(str(f.get("node_id", "")) == SAFE, "G — post-move read reflects canonical state")
	_check(_panel.get_destinations() == [CITY], "G — offers re-derive from the new node")
	_check(_panel.get_result_line() == "Moved: %s -> %s" % [CITY, SAFE],
		"result line reports the move")
	_panel.execute_move()
	_check(_panel.get_selected_force_id() == "force_a", "selection survives moves")


# H. Failures mutate nothing and surface the reason.
func _test_failures() -> void:
	var before := _snap_all()
	_panel.select_force("force_a")
	var r: Dictionary = _panel.execute_move()
	_check(not bool(r.get("ok", true)) and str(r.get("reason", "")) == "no_destination",
		"H — move with no destination fails cleanly")
	_check(_snap_all() == before, "H — failed move mutates nothing")
	_check(_panel.get_result_line() == "Move failed: no_destination",
		"H — reason surfaces to the player")
	_panel.select_destination(CITY)
	var r2: Dictionary = CampaignForceMovement.move_force("force_a", "node_nope")
	_check(not bool(r2.get("ok", true)), "H — authority still gates unknown destinations")


# I–J. Inactive forces display but never move.
func _test_inactive_forces() -> void:
	_panel.select_force("force_d")
	_check(_panel.get_destinations() == [SAFE], "DISABLED force still displays neighbors")
	_panel.select_destination(SAFE)
	var rd: Dictionary = _panel.execute_move()
	_check(not bool(rd.get("ok", true)) and str(rd.get("reason", "")) == "force_not_active",
		"I — DISABLED cannot move")
	_check(str(CampaignForce.get_force("force_d").get("node_id", "")) == CITY,
		"I — disabled force node unchanged")
	_panel.select_force("force_e")
	_panel.select_destination(CITY)
	var re: Dictionary = _panel.execute_move()
	_check(not bool(re.get("ok", true)), "J — DESTROYED cannot move")
	_check(str(CampaignForce.get_force("force_e").get("node_id", "")) == SAFE,
		"J — destroyed force node unchanged")


# K–M. Co-location and hostile matrices never block the entry point.
func _test_colocation_and_hostile() -> void:
	_panel.select_force("force_b")
	_check(_panel.get_destinations() == [CITY], "forces at one node each see the other side")
	_check(_panel.select_destination(CITY), "neighbor with other forces stays selectable")
	_check(bool(_panel.execute_move().get("ok", false)), "K — move onto an occupied node succeeds")
	_check(CampaignForce.get_forces_at_node(CITY).has("force_b")
		and CampaignForce.get_forces_at_node(CITY).has("force_d"),
		"K/L — cross-faction co-location holds without conflict")
	_check(FactionSystem.set_relation("zeon", "outland", FactionSystem.Relation.HOSTILE),
		"HOSTILE override set")
	_panel.select_force("force_b")
	_panel.select_destination(SAFE)
	_check(bool(_panel.execute_move().get("ok", false)),
		"M — HOSTILE relation does not block the entry point")
	_check(CampaignForce.get_forces_at_node(SAFE).has("force_a")
		and CampaignForce.get_forces_at_node(SAFE).has("force_b"),
		"L — hostile-matrix co-location holds without conflict")
	FactionSystem.reset_relations()


# N–R. Isolation battery around a real panel move.
func _test_isolation() -> void:
	_check(bool(CampaignForceMovement.move_force("force_a", CITY).get("ok", false)),
		"force_a staged at CITY")
	CampaignForce.set_base("force_a", "base_alpha")
	CampaignBattle.register_battle("battle_entry", CITY, ["force_d"])
	var rel_before: int = FactionSystem.get_relation("zeon", "outland")
	var turn_before: int = CampaignTurnExecutive.get_turn()
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	var base_before := JSON.stringify(CampaignBase.get_base("base_alpha"))
	var battle_before := JSON.stringify(CampaignBattle.get_battles())
	_panel.select_force("force_a")
	_panel.select_destination(SAFE)
	_check(bool(_panel.execute_move().get("ok", false)), "isolation move succeeds")
	_check(str(CampaignForce.get_force("force_a").get("base_id", "")) == "base_alpha",
		"N — base attachment preserved")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before
		and CampaignTerritory.get_controller("terr_downtown") == "federation",
		"O — territory byte-identical")
	_check(JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"O — base byte-identical")
	_check(JSON.stringify(CampaignBattle.get_battles()) == battle_before,
		"P — battles untouched, none created")
	_check(FactionSystem.get_relation("zeon", "outland") == rel_before,
		"faction relations untouched")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "Q — turn untouched")
	var f: Dictionary = CampaignForce.get_force("force_a")
	_check(f.keys().size() == 8, "R — no cost/order/supply keys added to the record")
	CampaignBattle.clear()
	CampaignForceMovement.move_force("force_a", CITY)
	CampaignForce.set_base("force_a", "")


# S–T + guards. No orders, no player force, no direct writes, no new systems.
func _test_transience_and_guards() -> void:
	var code := _code_of("res://scripts/ui/campaign_force_movement_panel.gd")
	_check(code.contains("move_force("), "E — panel calls the movement authority")
	_check(not code.contains("set_node("), "panel never writes node_id directly")
	var clean := true
	for token in ["PlayerForce", "CampaignPlayerForce", "HangarManager", "active_mech",
			"advance_campaign_turn", "register_battle", "set_controlled",
			"set_controller", "FactionSystem", "CombatSession", "signal "]:
		if code.contains(token):
			clean = false
	_check(clean, "panel creates no player force and touches no foreign authority")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_action_system.gd")
		and not FileAccess.file_exists("res://scripts/systems/campaign_command_system.gd")
		and not FileAccess.file_exists("res://scripts/systems/campaign_orchestrator.gd"),
		"T — no generic action/command/orchestrator file exists")
	var found_player_force := false
	for dir_path in ["res://scripts/systems", "res://scripts/board", "res://scripts/ui"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				var n := entry.to_lower()
				if n.get_extension() != "uid" and (n.contains("player_force")
						or n.contains("playerforce") or n.contains("campaign_player_force")):
					found_player_force = true

			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_player_force, "T — no PlayerForce file exists anywhere near the entry point")


# Save keeps destination via node_id; selection stays transient; reset clean.
func _test_save_reset() -> void:
	_panel.select_force("force_a")
	_panel.select_destination(SAFE)
	_check(bool(_panel.execute_move().get("ok", false)), "pre-save move succeeds")
	_check(SaveGameIO.save_run(), "save_run succeeds")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores")
	_check(str(CampaignForce.get_force("force_a").get("node_id", "")) == SAFE,
		"destination preserved through save/load (node_id persistence)")
	var fresh: CampaignForceMovementPanel = CampaignForceMovementPanel.new()
	add_child(fresh)
	await get_tree().process_frame
	_check(fresh.get_selected_force_id() == "" and fresh.get_last_result().is_empty(),
		"fresh panel holds no carried-over selection (transience)")
	fresh.queue_free()
	GlobalData.reset_run_data()
	_seed_world()
	_panel.refresh()
	_check(_panel.refresh_forces().size() == 5, "panel re-reads reseeded forces after reset")
	_check(not _panel.select_force("force_gone"), "selection of vanished force rejected")
