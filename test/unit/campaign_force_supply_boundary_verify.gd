extends Node
## PHASE 5L FORCE SUPPLY / SUSTAINMENT BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): CampaignForce owns NO supply/sustainment
## state. Existing supply-like states belong elsewhere and stay there:
##   faction-level supply_status -> FactionEconomySystem (consumed by patrol
##     spawning, never by forces);
##   player/board/convoy fuel     -> FuelManager (mech energy, convoy truck);
##   3D truck visuals             -> WarLogisticSystem (presentation only);
##   tactical ammo/HP/heat        -> combat authorities.
## Explicit code deferrals pin this: force has "No logistics/morale/ranks
## (Phase 6+/future)", nodes carry "no owner/supply/garrison", territory
## lists supply as out of scope. No turn/movement/battle/combat consumer
## needs force sustainment, so this phase adds NO field, NO manager, NO
## drain, NO penalty — only locks the absence and the ownership split.
## strength/unit_count keep their abstract-composition semantics (never
## supply, never HP). User save backed up/restored.

const SUPPLY_LIKE_KEYS := ["supply", "supply_status", "supply_level",
	"fuel", "ammo", "ammunition", "logistics", "ration", "rations",
	"sustainment", "stock", "stockpile", "resupply", "consumption",
	"attrition", "maintenance"]

const FORCE_KNOWN_KEYS := ["id", "force_type", "state", "faction",
	"node_id", "base_id", "unit_count", "strength"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SUPPLY OK: " + name)
	else:
		_fails += 1
		printerr("SUPPLY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_no_supply_field()
	_test_lifecycle_creates_no_supply()
	_test_movement_creates_no_supply()
	_test_battle_creates_no_supply()
	_test_turn_creates_no_supply()
	_test_faction_economy_owns_supply_status()
	_test_fuel_is_player_convoy_scope()
	_test_no_supply_manager_or_drain()
	_test_save_has_no_supply()
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
	print("CAMPAIGN_FORCE_SUPPLY_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_SUPPLY_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_SUPPLY_BOUNDARY_TESTS_PASSED")
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


func _has_supply_like_key(f: Dictionary) -> bool:
	for k in SUPPLY_LIKE_KEYS:
		if f.has(k):
			return true
	return false


func _code_of(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		kept.append(line)
	return "\n".join(kept)


# The force record carries exactly the 8 known keys — no supply shadow field.
func _test_no_supply_field() -> void:
	for f in CampaignForce.get_forces():
		_check(not _has_supply_like_key(f),
			"force %s carries no supply-like field" % str(f.get("id", "")))
		var keys := (f as Dictionary).keys()
		keys.sort()
		var want := FORCE_KNOWN_KEYS.duplicate()
		want.sort()
		_check(keys == want, "force record schema is exactly the 8 known keys")
	_check(not _has_supply_like_key(CampaignForce.describe_composition("force_a")),
		"composition contract carries no supply semantics")


# Full lifecycle (disable/destroy) introduces no supply state and degrades
# nothing: strength/unit_count are composition, never sustainment meters.
func _test_lifecycle_creates_no_supply() -> void:
	var before_a := CampaignForce.get_force("force_a")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"ACTIVE -> DISABLED")
	var mid := CampaignForce.get_force("force_a")
	_check(not _has_supply_like_key(mid), "DISABLED transition creates no supply field")
	_check(int(mid.get("unit_count", -1)) == int(before_a.get("unit_count", -1))
		and int(mid.get("strength", -1)) == int(before_a.get("strength", -1)),
		"DISABLED degrades no composition (no attrition)")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"DISABLED -> DESTROYED")
	var gone := CampaignForce.get_force("force_a")
	_check(not _has_supply_like_key(gone), "DESTROYED transition creates no supply field")
	_check(int(gone.get("unit_count", -1)) == int(before_a.get("unit_count", -1))
		and int(gone.get("strength", -1)) == int(before_a.get("strength", -1)),
		"DESTROYED degrades no composition (no casualty math)")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# Relocation (5K primitive) consumes nothing and records nothing.
func _test_movement_creates_no_supply() -> void:
	var before: Dictionary = CampaignForce.get_force("force_a")
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"), "force relocates")
	var after: Dictionary = CampaignForce.get_force("force_a")
	_check(not _has_supply_like_key(after), "movement creates no supply field")
	_check(int(after.get("unit_count", -1)) == 3 and int(after.get("strength", -1)) == 10,
		"movement consumes no composition (no fuel/move drain)")
	var only_node := str(after.get("node_id", "")) == "node_s1_safehouse_2_3"
	for k in before:
		if str(k) == "node_id":
			continue
		if after.get(k) != before.get(k):
			only_node = false
	_check(only_node, "movement changes node_id only")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")


# Full battle lifecycle (incl. launch + resolve) neither needs nor writes
# supply; Phase 5I eligibility is untouched by sustainment.
func _test_battle_creates_no_supply() -> void:
	CampaignBattle.clear()
	var forces_before := JSON.stringify(CampaignForce.get_forces())
	_check(CampaignBattle.register_battle("battle_s", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_s", "ACTIVE forces seed a battle")
	_check(bool(CampaignBattle.prepare_launch("battle_s").get("ok", false)),
		"battle launches with no supply gate")
	_check(CampaignBattle.resolve_battle("battle_s"), "battle resolves")
	_check(JSON.stringify(CampaignForce.get_forces()) == forces_before,
		"register + launch + resolve change no force bytes (no battle drain)")
	for f in CampaignForce.get_forces():
		_check(not _has_supply_like_key(f), "battle lifecycle creates no supply field")
	CampaignBattle.clear()


# Turn progression never ticks force sustainment (no daily drain).
func _test_turn_creates_no_supply() -> void:
	var before := JSON.stringify(CampaignForce.get_forces())
	CampaignTurnExecutive.advance_campaign_turn("supply_probe", {"day_boundary": false})
	CampaignTurnExecutive.advance_campaign_turn("supply_probe", {})
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"campaign turns leave forces byte-identical (no supply tick)")
	for f in CampaignForce.get_forces():
		_check(not _has_supply_like_key(f), "turns create no supply field")


# supply_status lives at faction level and never leaks onto force records.
func _test_faction_economy_owns_supply_status() -> void:
	var eco := FactionEconomySystem.get_economy("zeon")
	_check(str(eco.get("supply_status", "")) != "",
		"faction economy carries supply_status (faction-level owner)")
	_check(not _has_supply_like_key(CampaignForce.get_force("force_a")),
		"zeon force record carries no supply_status copy (no duplication)")
	_check(not _code_of("res://scripts/systems/faction_economy_system.gd").contains("CampaignForce"),
		"faction economy code never references CampaignForce")


# Fuel is player/board/convoy scope: its code never touches CampaignForce.
func _test_fuel_is_player_convoy_scope() -> void:
	_check(not _code_of("res://scripts/systems/fuel_manager.gd").contains("CampaignForce"),
		"fuel manager code never references CampaignForce (no ownership move)")
	_check(not _has_supply_like_key(CampaignForce.get_force("force_a"))
		and not _has_supply_like_key(CampaignForce.get_force("force_b")),
		"no fuel shadow field on any force record")


# Negative tests: no supply field/manager/drain/penalty anywhere in 5L scope.
func _test_no_supply_manager_or_drain() -> void:
	_check(not _code_of("res://scripts/systems/campaign_force.gd").contains("supply")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("sustain")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("logistic"),
		"force source has no supply/sustain/logistics concept (code, not comments)")
	_check(not _code_of("res://scripts/systems/campaign_turn_executive.gd").contains("CampaignForce"),
		"turn executive code never touches forces (no drain hook)")
	_check(not _code_of("res://scripts/systems/campaign_battle.gd").contains("supply"),
		"battle code has no supply gate (5I eligibility preserved)")
	var found_supply_file := false
	for dir_path in ["res://scripts/systems", "res://scripts/board", "res://scripts/war"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.to_lower().contains("supply"):
				found_supply_file = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_supply_file, "no supply manager/depot file exists in campaign scope")


# Save payload carries no force supply shadow state.
func _test_save_has_no_supply() -> void:
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var forces = ((d as Dictionary).get("forces", {}) as Dictionary).get("forces", [])
	var clean := true
	for row in forces:
		for k in SUPPLY_LIKE_KEYS:
			if (row as Dictionary).has(k):
				clean = false
	_check(clean, "saved force rows carry no supply-like field (no schema change needed)")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces")
	for f in CampaignForce.get_forces():
		_check(not _has_supply_like_key(f), "loaded forces carry no supply field")


# Reset clears forces with no sustainment residue.
func _test_reset() -> void:
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 2, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	for f in CampaignForce.get_forces():
		_check(not _has_supply_like_key(f), "post-reset forces carry no supply field")
	CampaignBattle.clear()
