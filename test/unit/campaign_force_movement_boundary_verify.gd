extends Node
## PHASE 5K FORCE STRATEGIC MOVEMENT BOUNDARY VERIFY (primitive only).
##
## Locks the audited architecture answer: NO campaign movement authority
## exists. CampaignForce.set_node() is a low-level validated relocation
## primitive (unknown node rejected, "" clears to off-board, known node sets
## the reference) with zero production callers; no pathfinding, no cost, no
## supply/fuel, no turn automation, no encounter or access-control rules.
## Relocation mutates ONLY the force's own node_id — never nodes, bases,
## territories, battles, faction relations, patrols, or player state — and
## applies identically in ACTIVE/DISABLED/DESTROYED (no state gate exists).
## Multiple forces may share one node (0..N). NodeRegistry owns topology.
## 5T amendment: the single sanctioned gameplay action
## (CampaignForceMovement.move_force, one validated route hop) now exists;
## everything this file locks about the set_node() primitive still holds,
## and no pathfinding/cost/queue authority may appear beside it.
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MOVEMENT OK: " + name)
	else:
		_fails += 1
		printerr("MOVEMENT FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_basic_relocation()
	_test_clear_presence()
	_test_unknown_node()
	_test_multiple_forces_per_node()
	_test_state_preservation()
	_test_base_isolation()
	_test_territory_isolation()
	_test_battle_isolation()
	_test_persistence()
	_test_reset()
	_test_no_movement_authority()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_MOVEMENT_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_MOVEMENT_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_MOVEMENT_BOUNDARY_TESTS_PASSED")
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
	CampaignTerritory.register_territory("terr_downtown",
		["node_s1_city_2_2", "node_s1_safehouse_2_3"])
	CampaignTerritory.register_territory("terr_outskirts", ["node_s1_fuel_depot_5_5"])
	CampaignBase.register_base("base_alpha", "node_s1_city_2_2", "OUTPOST",
		"federation", "terr_downtown")
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


func _reseed_forces() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


# A. Known node sets the reference; old/new node records untouched.
func _test_basic_relocation() -> void:
	_reseed_forces()
	var nodes_before := JSON.stringify(CampaignNodeRegistry.serialize())
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"),
		"relocation to a known node accepted")
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_safehouse_2_3",
		"force now references the new node")
	_check(not CampaignForce.get_forces_at_node("node_s1_city_2_2").has("force_a"),
		"force no longer listed at the old node")
	_check(CampaignForce.get_forces_at_node("node_s1_safehouse_2_3") == ["force_a", "force_b"],
		"force listed at the new node (sorted)")
	_check(JSON.stringify(CampaignNodeRegistry.serialize()) == nodes_before,
		"node records byte-identical across relocation (no topology mutation)")
	_reseed_forces()


# B. "" clears to off-board; the force record itself persists.
func _test_clear_presence() -> void:
	_reseed_forces()
	_check(CampaignForce.set_node("force_b", ""), "clearing to off-board accepted")
	_check(CampaignForce.get_force("force_b").get("node_id", "") == "",
		"force reference cleared")
	_check(not CampaignForce.get_forces_at_node("node_s1_safehouse_2_3").has("force_b"),
		"cleared force in no reference population")
	_check(not CampaignForce.get_active_forces_at_node("node_s1_safehouse_2_3").has("force_b"),
		"cleared force in no operational presence")
	_check(CampaignForce.has_force("force_b"), "cleared force record persists (no deletion)")
	_reseed_forces()


# C. Unknown node rejected; old reference kept. Unknown force rejected.
func _test_unknown_node() -> void:
	_reseed_forces()
	_check(not CampaignForce.set_node("force_a", "node_nope"),
		"move to unknown node rejected")
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_city_2_2",
		"rejected move changed nothing")
	_check(not CampaignForce.set_node("force_nope", "node_s1_city_2_2"),
		"move on unknown force rejected")
	_reseed_forces()


# D. 0..N forces per node: no occupancy, displacement, or exclusivity rule.
func _test_multiple_forces_per_node() -> void:
	_reseed_forces()
	_check(CampaignForce.set_node("force_b", "node_s1_city_2_2")
		and CampaignForce.set_node("force_c", "node_s1_city_2_2"),
		"three forces converge on one node")
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2") == ["force_a", "force_b", "force_c"],
		"all three listed (no collision, no faction exclusivity)")
	_check(CampaignForce.get_active_forces_at_node("node_s1_city_2_2") == ["force_a", "force_b", "force_c"],
		"all three operationally present")
	_reseed_forces()


# E. Relocation preserves every field but node_id, in every lifecycle state
# (no DISABLED/DESTROYED movement gate exists — primitive stays primitive).
func _test_state_preservation() -> void:
	_reseed_forces()
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DISABLED)
	CampaignForce.set_state("force_c", CampaignForce.ForceState.DESTROYED)
	for fid in ["force_a", "force_b", "force_c"]:
		var before: Dictionary = CampaignForce.get_force(fid)
		var moved: bool = CampaignForce.set_node(fid, "node_s1_fuel_depot_5_5")
		var after: Dictionary = CampaignForce.get_force(fid)
		_check(moved, "relocation accepted in state %s" % CampaignForce.state_to_name(int(before.get("state", -1))))
		var same := true
		for k in before:
			if k == "node_id":
				continue
			if str(after.get(k, "")) != str(before.get(k, "")) \
					and int(after.get(k, -999)) != int(before.get(k, -999)):
				same = false
		_check(same, "only node_id changed for %s (state/faction/base/composition kept)" % fid)
		_check(int(after.get("state", -1)) == int(before.get("state", -1)),
			"lifecycle state untouched by relocation for %s" % fid)
	_reseed_forces()


# F. Movement never mutates CampaignBase; base link rides along unchanged.
func _test_base_isolation() -> void:
	_reseed_forces()
	_check(CampaignForce.set_base("force_a", "base_alpha"), "force attaches to base")
	var base_before := JSON.stringify(CampaignBase.get_base("base_alpha"))
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"),
		"attached force relocates")
	_check(CampaignForce.get_force("force_a").get("base_id", "") == "base_alpha",
		"move neither detaches nor re-attaches the base link")
	_check(JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"base record byte-identical (no capture, no garrison write)")
	_check(CampaignForce.set_node("force_a", ""), "attached force moves off-board")
	_check(CampaignForce.get_force("force_a").get("base_id", "") == "base_alpha"
		and JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"off-board move still changes nothing about the base")
	_reseed_forces()


# G. Movement never mutates CampaignTerritory; context derives through nodes.
func _test_territory_isolation() -> void:
	_reseed_forces()
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	_check(CampaignForce.get_territory_context("force_a") == "terr_downtown",
		"derived context at the start node")
	_check(CampaignForce.set_node("force_a", "node_s1_fuel_depot_5_5"),
		"force relocates across the territory boundary")
	_check(CampaignForce.get_territory_context("force_a") == "terr_outskirts",
		"context re-derives through the new node (never stored)")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before,
		"territory control byte-identical (presence != control)")
	_reseed_forces()


# H. Participant relocation: no participant removal, no battle cancel/resolve,
# no battle node change — in PLANNED and ACTIVE alike.
func _test_battle_isolation() -> void:
	_reseed_forces()
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_m", "node_s1_city_2_2", ["force_a"])
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"),
		"participant relocates while battle PLANNED")
	_check(CampaignBattle.get_participants("battle_m") == ["force_a"],
		"participants unchanged by relocation")
	_check(str(CampaignBattle.get_battle("battle_m").get("node_id", "")) == "node_s1_city_2_2",
		"battle node unchanged by relocation")
	_check(CampaignBattle.is_planned("battle_m"), "battle lifecycle untouched")
	CampaignBattle.begin_battle("battle_m")
	_check(CampaignForce.set_node("force_a", "node_s1_fuel_depot_5_5"),
		"participant relocates while battle ACTIVE")
	_check(CampaignBattle.get_participants("battle_m") == ["force_a"]
		and CampaignBattle.is_active("battle_m")
		and str(CampaignBattle.get_battle("battle_m").get("node_id", "")) == "node_s1_city_2_2",
		"ACTIVE battle not auto-cancelled, roster and node intact")
	_check(CampaignBattle.resolve_battle("battle_m"), "relocated roster still resolves")
	CampaignBattle.clear()
	_reseed_forces()


# I. Relocated (and cleared) node_id round-trips through save/load.
func _test_persistence() -> void:
	_reseed_forces()
	CampaignBattle.clear()
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3")
		and CampaignForce.set_node("force_b", ""), "relocate + clear before save")
	_check(SaveGameIO.save_run(), "save_run carries relocated node refs")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces")
	_check(CampaignForce.get_force("force_a").get("node_id", "") == "node_s1_safehouse_2_3",
		"relocated node_id survives save/load")
	_check(CampaignForce.get_force("force_b").get("node_id", "") == "",
		"cleared node_id survives save/load (no silent re-place)")
	_reseed_forces()


# J. Reset clears the force registry under the existing contract.
func _test_reset() -> void:
	CampaignBattle.register_battle("battle_q", "node_s1_city_2_2", ["force_a"])
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 3, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	_check(CampaignBattle.validate().is_empty() and CampaignForce.validate().is_empty(),
		"no stale cross-references after reset")
	CampaignBattle.clear()


# K. Static ownership guard: no production system mutates CampaignForce, and
# no campaign movement/pathfinding/cost authority file exists beyond the
# single sanctioned 5T action (campaign_force_movement.gd).
func _test_no_movement_authority() -> void:
	var readers := {
		"res://scripts/systems/campaign_node_registry.gd": false,
		"res://scripts/systems/campaign_base.gd": false,
		"res://scripts/systems/campaign_territory.gd": false,
		"res://scripts/systems/campaign_turn_executive.gd": false,
		"res://scripts/systems/patrol_system.gd": false,
		"res://scripts/board/board_manager.gd": false,
	}
	var clean := true
	for path in readers:
		_check(FileAccess.file_exists(path), "audited source readable: %s" % path.get_file())
		var raw := FileAccess.get_file_as_string(path)
		var kept: PackedStringArray = []
		for line in raw.split("\n"):
			var cut := line.find("#")
			if cut != -1:
				line = line.substr(0, cut)
			kept.append(line)
		if ("\n".join(kept)).contains("CampaignForce"):
			clean = false
	_check(clean, "no topology/base/territory/turn/patrol/board code touches CampaignForce")
	var battle_raw := FileAccess.get_file_as_string("res://scripts/systems/campaign_battle.gd")
	var bkept: PackedStringArray = []
	for line in battle_raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		bkept.append(line)
	var bcode := "\n".join(bkept)
	var bclean := true
	for token in ["CampaignForce.set_node", "CampaignForce.set_base",
			"CampaignForce.set_faction", "CampaignForce.set_composition",
			"CampaignForce.set_state", "CampaignForce.register_force"]:
		if bcode.contains(token):
			bclean = false
	_check(bclean, "battle code never writes force state (reads only)")
	var parallel := false
	for dir_path in ["res://scripts/systems", "res://scripts/board"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				var n := entry.to_lower()
				# 5T/5AK amendment: campaign_force_movement.gd and
				# campaign_player_movement.gd are the sanctioned one-hop actions;
				# everything else stays forbidden.
				# (.uid sidecars are engine metadata, never authorities.)
				if n.get_extension() != "uid" and n != "campaign_force_movement.gd" and n != "campaign_player_movement.gd" and (n.contains("movement") or n.contains("pathfind") \
						or n.contains("force_orders") or n.contains("force_command") \
						or n.contains("travel_cost") or n.contains("waypoint")):
					parallel = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not parallel, "no unsanctioned movement/pathfinding/order authority file exists")
