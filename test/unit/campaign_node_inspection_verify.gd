extends Node
## PHASE 5V NODE INSPECTION / INSPECTION v1 VERIFY (read-only interaction).
##
## Locks the inspection contract: any registered node inspects from
## canonical authorities (identity + routes from NodeRegistry, forces
## verbatim from CampaignForce, first covering territory verbatim,
## base-at-node verbatim); unknown nodes fail safely without placeholders;
## empty nodes show zero forces; 0..N forces show all with canonical state
## and verbatim composition (never rosters/HP/power); no battle section
## exists (no canonical read API); every inspection leaves Force,
## Territory, Base, Battle, Faction, and Turn byte-identical; the
## select→inspect→move→re-inspect flow composes with the 5U panel and the
## 5T authority; no PlayerForce, no orchestration, no persistence.
## User save backed up/restored.

const CITY := "node_s1_city_2_2"
const SAFE := "node_s1_safehouse_2_3"
const DEPOT := "node_s1_fuel_depot_5_5"

var _fails := 0
var _checks := 0
var _backup := ""
var _panel: CampaignNodeInspectionPanel
var _mover: CampaignForceMovementPanel


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("INSPECT OK: " + name)
	else:
		_fails += 1
		printerr("INSPECT FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_panel = CampaignNodeInspectionPanel.new()
	add_child(_panel)
	_mover = CampaignForceMovementPanel.new()
	add_child(_mover)
	await get_tree().process_frame
	_test_valid_and_unknown()
	_test_identity_routes_board_separation()
	_test_forces_display()
	_test_territory_base_display()
	_test_read_only()
	_test_flow_with_movement()
	await _test_transience_save_reset()
	_test_guards()
	_panel.queue_free()
	_mover.queue_free()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_NODE_INSPECTION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_NODE_INSPECTION_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_NODE_INSPECTION_TESTS_PASSED")
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


# A–B. Valid node inspects; unknown node fails safely with state kept.
func _test_valid_and_unknown() -> void:
	var r: Dictionary = _panel.inspect_node(CITY)
	_check(bool(r.get("ok", false)), "A — existing node inspects")
	_check(_panel.get_selected_node_id() == CITY, "selection tracks inspection")
	var bad: Dictionary = _panel.inspect_node("node_nope")
	_check(not bool(bad.get("ok", true)) and str(bad.get("reason", "")) == "unknown_node",
		"B — unknown node fails safely")
	_check(_panel.get_selected_node_id() == CITY, "B — failed inspection keeps selection")
	_check(not CampaignNodeRegistry.has_node("node_nope"), "B — no placeholder created")


# C–F. Identity and routes come from the registry, never board tiles.
func _test_identity_routes_board_separation() -> void:
	var r: Dictionary = _panel.inspect_node(CITY)
	var node: Dictionary = r.get("node", {})
	var canon := CampaignNodeRegistry.get_node(CITY)
	_check(str(node.get("id", "")) == CITY and str(node.get("id", "")) == str(canon.get("id", "")),
		"C — displayed id matches canonical node")
	_check(str(node.get("node_type", "")) == "CITY"
		and str(node.get("node_type", "")) == str(canon.get("node_type", ""))
		and int(node.get("sector", -1)) == 1,
		"D — displayed type/sector match canonical node")
	var expected: Array = []
	for route in CampaignNodeRegistry.get_routes_for(CITY):
		for key in ["a", "b"]:
			var other := str((route as Dictionary).get(key, ""))
			if other != "" and other != CITY and not expected.has(other):
				expected.append(other)
	expected.sort()
	var got: Array = r.get("routes", [])
	got.sort()
	_check(got == expected and got == [SAFE], "E — routes equal registry neighbors (one hop)")
	var code := _code_of("res://scripts/ui/campaign_node_inspection_panel.gd")
	_check(not code.contains("BoardTile") and not code.contains("connections")
		and not code.contains("get_meta") and not code.contains("nodes_dict"),
		"F — inspection never consults board tiles")


# G–N. Forces display verbatim: empty, present, multi, cross-faction, states.
func _test_forces_display() -> void:
	var g: Dictionary = _panel.inspect_node(DEPOT)
	_check(bool(g.get("ok", false)) and (g.get("forces", []) as Array).is_empty(),
		"G — empty node inspects with zero forces")
	var h: Dictionary = _panel.inspect_node(SAFE)
	var hforces: Array = h.get("forces", [])
	_check(hforces.size() == 2, "H — both forces shown (incl. DESTROYED)")
	var hid: Array = []
	for f in hforces:
		hid.append(str(f.get("id", "")))
	hid.sort()
	_check(hid == CampaignForce.get_forces_at_node(SAFE),
		"AA — shown forces equal registry listing (no fabrication, no PlayerForce)")
	_check(CampaignForceMovement.move_force("force_b", CITY).get("ok", false),
		"stage cross-faction co-location")
	var i: Dictionary = _panel.inspect_node(CITY)
	var ids: Array = []
	for f in i.get("forces", []):
		ids.append(str(f.get("id", "")))
	ids.sort()
	_check(ids == ["force_a", "force_b", "force_d"], "I — every force shown, none assumed")
	var factions := {}
	for f in i.get("forces", []):
		factions[str(f.get("faction", ""))] = true
	_check(factions.has("zeon") and factions.has("outland"), "J — cross-faction shown verbatim")
	_check(FactionSystem.set_relation("zeon", "outland", FactionSystem.Relation.HOSTILE),
		"HOSTILE override set")
	_check(bool(_panel.inspect_node(CITY).get("ok", false)), "K — HOSTILE never blocks inspection")
	FactionSystem.reset_relations()
	var states := {}
	var comp_ok := false
	for f in i.get("forces", []):
		states[str(f.get("id", ""))] = CampaignForce.state_to_name(int(f.get("state", -1)))
		if str(f.get("id", "")) == "force_a" and int(f.get("unit_count", -1)) == 3 \
				and int(f.get("strength", -1)) == 10:
			comp_ok = true
	_check(states.get("force_d", "") == "disabled", "L — DISABLED shown canonically")
	_check(comp_ok, "M — composition shown verbatim (3 / 10)")
	_check(not _code_of("res://scripts/ui/campaign_node_inspection_panel.gd").contains("pilot")
		and not _code_of("res://scripts/ui/campaign_node_inspection_panel.gd").contains("mech")
		and not _code_of("res://scripts/ui/campaign_node_inspection_panel.gd").contains("roster"),
		"N — no roster/HP reinterpretation in code")
	CampaignForceMovement.move_force("force_b", SAFE)


# O–R. Territory and base contexts display verbatim.
func _test_territory_base_display() -> void:
	var r: Dictionary = _panel.inspect_node(CITY)
	var t: Dictionary = r.get("territory", {})
	_check(str(t.get("id", "")) == "terr_downtown"
		and str(t.get("controller", "")) == "federation",
		"O — territory context shown verbatim")
	var b: Dictionary = r.get("base", {})
	_check(str(b.get("id", "")) == "base_alpha"
		and str(b.get("base_type", "")) == "OUTPOST"
		and str(b.get("controller", "")) == "federation",
		"Q — base context shown verbatim")
	var d: Dictionary = _panel.inspect_node(DEPOT)
	_check((d.get("territory", {}) as Dictionary).is_empty()
		and (d.get("base", {}) as Dictionary).is_empty(),
		"uncovered node shows empty territory and base (no fabrication)")
	_check(str(b.get("controller", "")) != "zeon", "no controller derived from force faction")


# S–V. Read-only proof across every authority.
func _test_read_only() -> void:
	var before := _snap_all()
	_panel.inspect_node(CITY)
	_panel.inspect_node(SAFE)
	_panel.inspect_node(DEPOT)
	_panel.inspect_node("node_nope")
	_panel.refresh()
	_check(_snap_all() == before, "S/V — inspections leave all authorities byte-identical")
	_check(CampaignBattle.get_battles().is_empty(), "T — no battle created or mutated")
	_check(FactionSystem.get_relation("zeon", "outland") == FactionSystem.Relation.NEUTRAL,
		"U — faction matrix untouched")


# Z + definition-of-done flow: select → inspect → move → re-inspect.
func _test_flow_with_movement() -> void:
	_check(_mover.select_force("force_a"), "flow — force selects in movement panel")
	var current := str(_mover.get_selected_force().get("node_id", ""))
	_check(current == CITY, "flow — current node reads CITY")
	var before: Dictionary = _panel.inspect_node(current)
	_check((before.get("forces", []) as Array).size() == 2, "flow — CITY shows its forces")
	_mover.select_destination(SAFE)
	_check(bool(_mover.execute_move().get("ok", false)), "flow — move executes")
	var after_here: Dictionary = _panel.inspect_node(CITY)
	var after_there: Dictionary = _panel.inspect_node(SAFE)
	var here_ids: Array = []
	for f in after_here.get("forces", []):
		here_ids.append(str(f.get("id", "")))
	var there_ids: Array = []
	for f in after_there.get("forces", []):
		there_ids.append(str(f.get("id", "")))
	_check(not here_ids.has("force_a") and there_ids.has("force_a"),
		"Z — post-move inspection reads new canonical state on both nodes")
	CampaignForceMovement.move_force("force_a", CITY)


# W–Y + AA–AB. Transience, persistence, guards.
func _test_transience_save_reset() -> void:
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	for k in (d as Dictionary).keys():
		var kl := str(k).to_lower()
		if kl == "inspection" or kl.contains("_inspection") or kl.contains("inspected_node"):
			clean = false
	_check(clean, "W — save payload gains no inspection keys")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores")
	var fresh := CampaignNodeInspectionPanel.new()
	add_child(fresh)
	await get_tree().process_frame
	_check(fresh.get_selected_node_id() == "" and fresh.get_last_inspection().is_empty(),
		"Y — fresh instance holds no stale selection")
	_check(not fresh.inspect_node("node_nope").get("ok", true), "X — removed node fails safely")
	fresh.queue_free()
	GlobalData.reset_run_data()
	_seed_world()
	_panel.refresh()
	_check(_panel.refresh_nodes().size() == 3, "X — panel re-reads reseeded nodes after reset")


func _test_guards() -> void:
	var code := _code_of("res://scripts/ui/campaign_node_inspection_panel.gd")
	_check(code.contains("get_node(") and code.contains("get_routes_for(")
		and code.contains("get_forces_at_node(")
		and code.contains("get_territories_for_node(")
		and code.contains("get_base_at_node("),
		"reads flow through canonical read APIs only")
	var write_free := true
	for token in ["set_node(", "move_force(", "register_", "set_controlled",
			"set_contested", "set_controller", "set_state", "set_faction",
			"set_composition", "set_base", "set_territory", "begin_battle",
			"resolve_battle", "CampaignForceMovement", "PlayerForce",
			"CampaignPlayerForce", "HangarManager", "active_mech",
			"advance_campaign_turn", "CombatSession", "signal "]:
		if code.contains(token):
			write_free = false
	_check(write_free, "inspection path calls no mutating authority (read-only)")
	_check(not FileAccess.file_exists("res://scripts/systems/campaign_action_system.gd")
		and not FileAccess.file_exists("res://scripts/systems/campaign_orchestrator.gd")
		and not FileAccess.file_exists("res://scripts/systems/campaign_node_controller.gd")
		and not FileAccess.file_exists("res://scripts/systems/campaign_interaction_manager.gd"),
		"AB — no generic orchestration/interaction architecture created")
