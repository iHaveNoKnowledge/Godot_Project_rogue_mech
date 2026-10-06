extends Node
## PHASE 5T FORCE STRATEGIC MOVEMENT ACTION v1 VERIFY (first gameplay slice).
##
## Locks the movement contract: ACTIVE force at Node A + registered route
## A<->B => node_id = B, validated before mutation, receipt-shaped result.
## Every other case rejects with zero mutation (failure atomicity holds
## because the single-field write happens only after all gates pass).
## Movement never touches state/faction/base/composition, territory, base,
## battle, faction relations, turn counter, supply, detection, orders, or
## force-to-force relations; never creates battles; never advances turns;
## persists through node_id only; holds no runtime state of its own.
## User save backed up/restored.

const CITY := "node_s1_city_2_2"
const SAFE := "node_s1_safehouse_2_3"
const DEPOT := "node_s1_fuel_depot_5_5"

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MOVE-ACTION OK: " + name)
	else:
		_fails += 1
		printerr("MOVE-ACTION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_success_and_one_hop()
	_test_rejections()
	_test_colocation_and_hostile()
	_test_base_territory_battle_faction_turn_untouched()
	_test_atomicity_save_reset()
	_test_architecture_guards()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_MOVEMENT_ACTION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_MOVEMENT_ACTION_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_MOVEMENT_ACTION_TESTS_PASSED")
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


func _node_of(fid: String) -> String:
	return str(CampaignForce.get_force(fid).get("node_id", ""))


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# A — success receipt shape + mutation; one-hop limit (B); undirected routes.
func _test_success_and_one_hop() -> void:
	var r: Dictionary = CampaignForceMovement.move_force("force_a", SAFE)
	_check(bool(r.get("ok", false)) and str(r.get("reason", "")) == "moved",
		"A — adjacent move succeeds")
	var keys: Array = r.keys()
	keys.sort()
	_check(keys == ["force_id", "from_node_id", "ok", "reason", "to_node_id"],
		"A — receipt carries exactly the contract keys")
	_check(str(r.get("from_node_id", "")) == CITY and str(r.get("to_node_id", "")) == SAFE,
		"A — receipt names source and destination")
	_check(_node_of("force_a") == SAFE, "A — force.node_id is the destination")
	var r2: Dictionary = CampaignForceMovement.move_force("force_a", DEPOT)
	_check(not bool(r2.get("ok", true)) and str(r2.get("reason", "")) == "no_route",
		"B — two-hop destination without direct route rejects")
	_check(_node_of("force_a") == SAFE, "B — rejected move leaves force in place")
	var r3: Dictionary = CampaignForceMovement.move_force("force_a", CITY)
	_check(bool(r3.get("ok", false)), "routes are undirected (return hop succeeds)")
	_check(_node_of("force_a") == CITY, "return hop lands back at origin")


# C–I — every rejection gate, each with zero mutation.
func _test_rejections() -> void:
	var before := _snap_all()
	var rc: Dictionary = CampaignForceMovement.move_force("force_nope", SAFE)
	_check(not bool(rc.get("ok", true)) and str(rc.get("reason", "")) == "unknown_force",
		"C — unknown force rejects")
	var rd: Dictionary = CampaignForceMovement.move_force("force_d", SAFE)
	_check(not bool(rd.get("ok", true)) and str(rd.get("reason", "")) == "force_not_active",
		"D — DISABLED force rejects")
	_check(_node_of("force_d") == CITY, "D — disabled force node unchanged")
	var re: Dictionary = CampaignForceMovement.move_force("force_e", CITY)
	_check(not bool(re.get("ok", true)) and str(re.get("reason", "")) == "force_not_active",
		"E — DESTROYED force rejects")
	_check(_node_of("force_e") == SAFE, "E — destroyed force node unchanged")
	var rf: Dictionary = CampaignForceMovement.move_force("force_c", CITY)
	_check(not bool(rf.get("ok", true)) and str(rf.get("reason", "")) == "no_source_node",
		"F — off-board force rejects")
	var rg: Dictionary = CampaignForceMovement.move_force("force_a", "node_nope")
	_check(not bool(rg.get("ok", true)) and str(rg.get("reason", "")) == "unknown_destination",
		"G — unknown destination rejects")
	var rh: Dictionary = CampaignForceMovement.move_force("force_a", CITY)
	_check(not bool(rh.get("ok", true)) and str(rh.get("reason", "")) == "same_node",
		"H — same source/destination rejects (no fake success)")
	var ri: Dictionary = CampaignForceMovement.move_force("force_a", DEPOT)
	_check(not bool(ri.get("ok", true)) and str(ri.get("reason", "")) == "no_route",
		"I — non-adjacent destination rejects")
	var after := _snap_all()
	_check(after == before, "all rejections leave every authority untouched")


# J–L — co-location stays legal; hostile relations never gate.
func _test_colocation_and_hostile() -> void:
	var r: Dictionary = CampaignForceMovement.move_force("force_a", SAFE)
	_check(bool(r.get("ok", false)), "J — move onto an occupied node succeeds")
	_check(CampaignForce.get_forces_at_node(SAFE) == ["force_a", "force_b", "force_e"],
		"J — forces share the destination (no conflict)")
	_check(FactionSystem.set_relation("zeon", "outland", FactionSystem.Relation.HOSTILE),
		"HOSTILE override set")
	var back: Dictionary = CampaignForceMovement.move_force("force_a", CITY)
	_check(bool(back.get("ok", false)), "L — HOSTILE relation does not block movement")
	FactionSystem.reset_relations()
	_check(FactionSystem.get_relation("zeon", "outland") == FactionSystem.Relation.NEUTRAL,
		"matrix restored (K cross-faction co-location was valid throughout)")


# M–T — the full isolation battery around one real move.
func _test_base_territory_battle_faction_turn_untouched() -> void:
	CampaignForce.set_base("force_a", "base_alpha")
	CampaignBattle.register_battle("battle_iso", CITY, ["force_b"])
	var rel_before: int = FactionSystem.get_relation("zeon", "outland")
	var turn_before: int = CampaignTurnExecutive.get_turn()
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	var base_before := JSON.stringify(CampaignBase.get_base("base_alpha"))
	var battle_before := JSON.stringify(CampaignBattle.get_battles())
	var force_before: Dictionary = CampaignForce.get_force("force_a")
	var r: Dictionary = CampaignForceMovement.move_force("force_a", SAFE)
	_check(bool(r.get("ok", false)), "isolation move succeeds")
	var f: Dictionary = CampaignForce.get_force("force_a")
	_check(str(f.get("base_id", "")) == "base_alpha", "M — base attachment rides along")
	_check(int(f.get("state", -1)) == int(force_before.get("state", -1))
		and str(f.get("faction", "")) == str(force_before.get("faction", ""))
		and int(f.get("unit_count", -1)) == int(force_before.get("unit_count", -1))
		and int(f.get("strength", -1)) == int(force_before.get("strength", -1)),
		"state/faction/composition untouched (only node_id changes)")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before
		and CampaignTerritory.get_controller("terr_downtown") == "federation"
		and CampaignTerritory.get_contesting("terr_downtown").is_empty(),
		"N/T — territory control and contesting untouched")
	_check(JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"O — base record untouched (no attach/detach/capture)")
	_check(JSON.stringify(CampaignBattle.get_battles()) == battle_before,
		"P/S — battles untouched, none auto-created")
	_check(FactionSystem.get_relation("zeon", "outland") == rel_before,
		"Q — faction relations untouched (never even read as a gate)")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "R — turn counter untouched")
	CampaignBattle.clear()
	CampaignForceMovement.move_force("force_a", CITY)
	CampaignForce.set_base("force_a", "")


# U–W — atomicity, persistence, statelessness.
func _test_atomicity_save_reset() -> void:
	var before := _snap_all()
	var r: Dictionary = CampaignForceMovement.move_force("force_a", "node_nope")
	_check(not bool(r.get("ok", true)), "U — invalid move rejects")
	_check(_snap_all() == before, "U — all five authorities unchanged")
	_check(bool(CampaignForceMovement.move_force("force_a", SAFE).get("ok", false)),
		"V — move succeeds before save")
	_check(SaveGameIO.save_run(), "V — save_run succeeds")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "V — load_run restores")
	_check(_node_of("force_a") == SAFE, "V — destination preserved through save/load")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForceMovement.move_force("force_a", SAFE).get("ok", false),
		"W — movement works after reset with no reset call of its own (stateless)")
	_check(CampaignTurnExecutive.get_turn() == 0, "W — turn counter clean after reset")
	_seed_world()


# Architecture guards: the authority touches only what v1 allows.
func _test_architecture_guards() -> void:
	var code := _code_of("res://scripts/systems/campaign_force_movement.gd")
	var forbidden := true
	for token in ["advance_campaign_turn", "register_battle", "begin_battle",
			"prepare_launch", "resolve_battle", "set_controlled", "set_contested",
			"set_controller", "set_territory", "FactionSystem", "CombatSession",
			"SpawnManager", "GameManager", "EventBus", "supply", "detect",
			"order", "mission", "signal", "static var", "set_state",
			"set_composition", "set_faction", "set_base"]:
		if code.contains(token):
			forbidden = false
	_check(forbidden, "movement source touches no forbidden authority or concept")
	_check(code.contains("set_node("), "final mutation goes through set_node() only")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_action_system.gd")
		and not FileAccess.file_exists("res://scripts/systems/campaign_orchestrator.gd"),
		"no generic action/orchestrator file was created")
