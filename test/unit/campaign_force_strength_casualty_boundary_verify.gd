extends Node
## PHASE 5P FORCE STRENGTH / CASUALTY / ATTRITION BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): unit_count/strength are CURRENT abstract
## composition values with NO gameplay producer. The only writers are the
## low-level primitives register_force()/set_composition() (zero production
## callers): no battle/turn/patrol/supply/movement/tactical/combat path
## writes them, and no casualty/attrition/reinforcement/recovery authority
## exists at campaign-force level. describe_composition() stays a pure
## read (5D). strength is NOT HP, NOT a roster count, NOT power formula
## output; DESTROYED retains composition verbatim (never 100%-casualty
## inference); zero values trigger NO state transition. Tactical, patrol,
## and campaign casualties are three unbridged domains.
## User save backed up/restored.

const CASUALTY_LIKE_KEYS := ["casualties", "casualty", "losses", "loss",
	"attrition", "damage", "survivors", "survivor", "destroyed_units",
	"remaining_units", "reinforcements", "reinforcement",
	"reinforcement_history", "recovery", "recovery_history", "repair_queue",
	"production_queue", "recruits", "wounded", "dead", "kills",
	"battle_result", "result", "winner", "casualty_history",
	"attrition_history", "depletion"]

const FORCE_KNOWN_KEYS := ["id", "force_type", "state", "faction",
	"node_id", "base_id", "unit_count", "strength"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CASUALTY OK: " + name)
	else:
		_fails += 1
		printerr("CASUALTY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_abstract_storage()
	_test_no_casualty_history_on_register()
	_test_location_base_faction_territory_keep_composition()
	_test_battle_lifecycle_keeps_composition()
	_test_turn_keeps_composition()
	_test_boundaries_disconnected()
	_test_patrol_tactical_disconnected()
	_test_destroyed_retains_composition()
	_test_zero_values_trigger_no_transition()
	_test_no_casualty_authority()
	_test_persistence_exact()
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
	print("CAMPAIGN_FORCE_STRENGTH_CASUALTY_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_STRENGTH_CASUALTY_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_STRENGTH_CASUALTY_TESTS_PASSED")
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


func _has_casualty_like_key(d: Dictionary) -> bool:
	for k in CASUALTY_LIKE_KEYS:
		if d.has(k):
			return true
	return false


func _composition_of(fid: String) -> Array:
	var f: Dictionary = CampaignForce.get_force(fid)
	return [int(f.get("unit_count", -999)), int(f.get("strength", -999))]


func _check_exact_schema(fid: String, label: String) -> void:
	var f: Dictionary = CampaignForce.get_force(fid)
	_check(not _has_casualty_like_key(f), "no casualty-like field on %s (%s)" % [fid, label])
	var keys: Array = (f as Dictionary).keys()
	keys.sort()
	var want: Array = FORCE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "record exactly the 8 locked keys (%s)" % label)


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# 1-2. Abstract storage: verbatim ints, paired writes, non-negative gate.
func _test_abstract_storage() -> void:
	_check(_composition_of("force_a") == [3, 10], "composition stored verbatim at registration")
	_check(CampaignForce.set_composition("force_a", 5, 20), "paired composition write accepted")
	_check(_composition_of("force_a") == [5, 20], "paired write lands together")
	_check(not CampaignForce.set_composition("force_a", -1, 20), "negative count rejected")
	_check(not CampaignForce.set_composition("force_a", 5, -1), "negative strength rejected")
	_check(_composition_of("force_a") == [5, 20], "rejected writes change nothing")
	_check(not CampaignForce.set_composition("force_nope", 1, 1), "write on unknown force rejected")
	var c: Dictionary = CampaignForce.describe_composition("force_a")
	_check(int(c.get("unit_count", -1)) == 5 and int(c.get("strength", -1)) == 20
		and str(c.get("force_id", "")) == "force_a",
		"describe_composition reads the same abstract values (pure read)")
	CampaignForce.set_composition("force_a", 3, 10)


# 3. Registration fabricates no casualty history.
func _test_no_casualty_history_on_register() -> void:
	_check_exact_schema("force_a", "seeded force")
	_check_exact_schema("force_b", "seeded force")
	_check(CampaignForce.register_force("force_z", "RIVAL", "federation",
		"node_s1_city_2_2", "", 0, 0) == "force_z", "zero-composition force registers")
	_check_exact_schema("force_z", "zero-composition registration")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 4-7. Location, base, faction, and territory contact keep composition.
func _test_location_base_faction_territory_keep_composition() -> void:
	var before: Array = _composition_of("force_a")
	CampaignForce.set_node("force_a", "node_s1_safehouse_2_3")
	CampaignForce.set_base("force_a", "base_alpha")
	CampaignForce.set_faction("force_a", "federation")
	_check(_composition_of("force_a") == before,
		"node + base + faction writes keep composition (no drain, no transfer cost)")
	_check(CampaignForce.get_territory_context("force_a") == "terr_downtown",
		"territory context derives")
	_check(_composition_of("force_a") == before, "territory contact keeps composition")
	_check_exact_schema("force_a", "after contact writes")
	CampaignForce.set_faction("force_a", "zeon")
	CampaignForce.set_base("force_a", "")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")


# 8-11. Full battle lifecycle keeps every composition byte.
func _test_battle_lifecycle_keeps_composition() -> void:
	CampaignBattle.clear()
	var before := JSON.stringify(CampaignForce.get_forces())
	_check(CampaignBattle.register_battle("battle_c", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_c", "forces seed a battle")
	_check(JSON.stringify(CampaignForce.get_forces()) == before, "registration keeps composition")
	_check(bool(CampaignBattle.prepare_launch("battle_c").get("ok", false)), "battle launches")
	_check(JSON.stringify(CampaignForce.get_forces()) == before, "launch keeps composition")
	_check(CampaignBattle.resolve_battle("battle_c"), "battle resolves")
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"resolve keeps composition (no casualty math)")
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.cancel_battle("battle_x")
	_check(JSON.stringify(CampaignForce.get_forces()) == before, "cancel keeps composition")
	_check_exact_schema("force_a", "after battle lifecycle")
	CampaignBattle.clear()


# 12. Turns keep composition byte-identical.
func _test_turn_keeps_composition() -> void:
	var before := JSON.stringify(CampaignForce.get_forces())
	CampaignTurnExecutive.advance_campaign_turn("casualty_probe", {"day_boundary": false})
	CampaignTurnExecutive.advance_campaign_turn("casualty_probe", {})
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"turns keep composition byte-identical (no attrition tick)")
	_check_exact_schema("force_b", "after turns")


# 13-15. Supply/detection/order boundaries stay disconnected.
func _test_boundaries_disconnected() -> void:
	for f in CampaignForce.get_forces():
		var d: Dictionary = f
		_check(not d.has("supply") and not d.has("supply_status")
			and not d.has("detected") and not d.has("intel")
			and not d.has("order") and not d.has("mission")
			and not _has_casualty_like_key(d),
			"force %s keeps 5L/5M/5N absence plus no casualty shadow" % str(d.get("id", "")))


# 16-17. Patrol and tactical domains never write force composition.
func _test_patrol_tactical_disconnected() -> void:
	var patrols_before: int = GlobalData.board.board_patrols.size()
	_check(CampaignForce.set_composition("force_a", 9, 99), "explicit composition write lands")
	_check(GlobalData.board.board_patrols.size() == patrols_before,
		"composition write churns no patrols (no roster bridge)")
	_check(CampaignForce.set_composition("force_a", 3, 10), "composition restored")
	_check(not _code_of("res://scripts/systems/patrol_system.gd").contains("CampaignForce"),
		"patrol code never references forces")
	for path in ["res://scripts/systems/spawn_manager.gd",
			"res://autoload/game_manager.gd"]:
		if FileAccess.file_exists(path):
			_check(not _code_of(path).contains("CampaignForce"),
				"no tactical bridge in %s" % path.get_file())
		else:
			_check(true, "tactical file absent (no bridge by construction): %s" % path.get_file())


# 18. DESTROYED retains composition verbatim — never casualty inference.
func _test_destroyed_retains_composition() -> void:
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"force destroyed")
	_check(_composition_of("force_a") == [3, 10],
		"DESTROYED retains composition verbatim (not zeroed, not history)")
	_check_exact_schema("force_a", "destroyed record")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 19. Zero values invent no transition in either direction.
func _test_zero_values_trigger_no_transition() -> void:
	_check(CampaignForce.register_force("force_zero", "CONVOY", "zeon",
		"node_s1_city_2_2", "", 0, 0) == "force_zero", "zero-composition force registers")
	_check(CampaignForce.is_active("force_zero"), "zero values do not prevent ACTIVE state")
	_check(CampaignBattle.register_battle("battle_z", "node_s1_city_2_2",
		["force_zero"]) == "battle_z",
		"zero-composition force still seeds a battle (no strength gate)")
	CampaignBattle.clear()
	_check(CampaignForce.set_composition("force_a", 0, 0), "composition set to zero")
	_check(CampaignForce.is_active("force_a"), "zeroing composition triggers no DISABLED")
	_check(CampaignForce.get_state("force_a") == CampaignForce.ForceState.ACTIVE,
		"zeroing composition triggers no DESTROYED")
	_check_exact_schema("force_a", "zeroed record keeps schema")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 22-27. Negative tests: no casualty authority in code or filenames.
func _test_no_casualty_authority() -> void:
	var force_code := _code_of("res://scripts/systems/campaign_force.gd").to_lower()
	var clean := true
	for token in ["casualt", "attrition", "pilots", "board_patrols",
			"patrolsystem", "tactical", "reinforce", "recover", "recruit",
			"survivor", "wound", " Winner", "loser"]:
		if force_code.contains(token):
			clean = false
	_check(clean, "force source has no casualty concept (code, not comments)")
	_check(not _code_of("res://scripts/systems/campaign_battle.gd").to_lower().contains("casualt")
		and not _code_of("res://scripts/systems/campaign_battle.gd").to_lower().contains("attrition")
		and not _code_of("res://scripts/systems/campaign_battle.gd").to_lower().contains("survivor"),
		"battle source has no casualty concept")
	_check(not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignForce"),
		"turn executive never touches forces (no attrition hook)")
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
				if n.contains("casualt") or n.contains("attrition") \
						or n.contains("reinforcement") or n.contains("recovery"):
					found_manager = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_manager, "no casualty/attrition/reinforcement manager file exists")


# 20. Save/load round-trips composition exactly; no shadow fields.
func _test_persistence_exact() -> void:
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	var exact := false
	for row in ((d as Dictionary).get("forces", {}) as Dictionary).get("forces", []):
		if _has_casualty_like_key(row):
			clean = false
		if str((row as Dictionary).get("id", "")) == "force_a" \
				and int((row as Dictionary).get("unit_count", -1)) == 3 \
				and int((row as Dictionary).get("strength", -1)) == 10:
			exact = true
	_check(clean, "saved rows carry no casualty shadow (schema unchanged)")
	_check(exact, "saved composition values exact")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces")
	_check(_composition_of("force_a") == [3, 10], "loaded composition exact")
	_check_exact_schema("force_a", "after load")
	CampaignBattle.clear()


# 21. Reset clears per existing lifecycle; reseed restores composition.
func _test_reset() -> void:
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 2, "seed restored after reset")
	_check(_composition_of("force_a") == [3, 10], "reseeded composition exact (no leakage)")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	CampaignBattle.clear()
