extends Node
## PHASE 5M FORCE DETECTION / INTELLIGENCE BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): strategic detection / intelligence is NOT YET
## MODELED. CampaignForce carries no detected/visible/known/intel/last_seen
## state (record is exactly the 8 locked keys), and no detection authority
## exists anywhere. Related systems keep their own owners and never bridge
## to forces:
##   enemy spy events  -> EnemyFactionSystem (targets PLAYER mech data;
##                        output is a turn-receipt spy_event dict);
##   patrol "unknown"  -> encounter-stance label (mercenary convoy behavior),
##                        not a detection state, not a faction id;
##   board visibility  -> BoardState (fog mults, patrol_last_seen TILE);
##   tactical spotting -> radar/stealth/ZoC/AI chase distances (runtime);
##   tech discovery    -> TechnologySystem lineage (unrelated).
## Campaign deferrals pin this: nodes must not own detection, territory
## lists detection as out of scope. node_id stays CURRENT presence (never
## knowledge); Battle.participants[] stays identity (never intel); no
## last_known_node shadow field; no Detection/Intel/FogOfWar manager.
## User save backed up/restored.

const DETECTION_LIKE_KEYS := ["detected", "detection", "detection_level",
	"detectable", "visible", "vis", "visibility", "known", "hidden",
	"stealth", "intel", "intelligence", "last_seen", "last_known",
	"last_known_node", "last_known_node_id", "seen_by", "discovered",
	"revealed", "scouted", "contact", "tracked", "observable",
	"spotted", "awareness"]

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
		print("DETECTION OK: " + name)
	else:
		_fails += 1
		printerr("DETECTION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_force_model_has_no_detection()
	_test_presence_is_not_detection()
	_test_battle_creates_no_detection()
	_test_movement_creates_no_detection()
	_test_supply_boundary_holds()
	_test_patrol_remains_separate()
	_test_spy_remains_unchanged()
	_test_persistence_has_no_detection()
	_test_no_detection_authority()
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
	print("CAMPAIGN_FORCE_DETECTION_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_DETECTION_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_DETECTION_BOUNDARY_TESTS_PASSED")
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


func _has_detection_like_key(d: Dictionary) -> bool:
	for k in DETECTION_LIKE_KEYS:
		if d.has(k):
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


# A. Force model: exactly the 8 locked keys, in every lifecycle state.
func _test_force_model_has_no_detection() -> void:
	for f in CampaignForce.get_forces():
		_check(not _has_detection_like_key(f),
			"force %s carries no detection-like field" % str(f.get("id", "")))
		var keys := (f as Dictionary).keys()
		keys.sort()
		var want := FORCE_KNOWN_KEYS.duplicate()
		want.sort()
		_check(keys == want, "force record schema is exactly the 8 locked keys")
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED)
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DESTROYED)
	for f in CampaignForce.get_forces():
		_check(not _has_detection_like_key(f),
			"no detection field appears in state %s" % CampaignForce.state_to_name(int(f.get("state", -1))))
	_check(not _has_detection_like_key(CampaignForce.describe_composition("force_a")),
		"composition contract carries no detection semantics")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# B. node_id is CURRENT presence only: unfiltered listing in all states,
# and no observation layer between the force and its node.
func _test_presence_is_not_detection() -> void:
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DISABLED)
	_check(CampaignForce.get_forces_at_node("node_s1_safehouse_2_3") == ["force_b"],
		"DISABLED force listed without visibility filter")
	_check(CampaignForce.get_active_forces_at_node("node_s1_city_2_2") == ["force_a"],
		"operational query filters by STATE, never by detection")
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DESTROYED)
	_check(CampaignForce.get_forces_at_node("node_s1_safehouse_2_3") == ["force_b"],
		"DESTROYED force still listed (presence record, not sighting)")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# C. Battle lifecycle creates no detection state; battle record has no
# intel semantics (exact key set, participants are identity).
func _test_battle_creates_no_detection() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_d", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_d", "forces seed a battle")
	_check(bool(CampaignBattle.prepare_launch("battle_d").get("ok", false)),
		"launch needs no detection gate (5I eligibility intact)")
	_check(CampaignBattle.resolve_battle("battle_d"), "battle resolves")
	var b := CampaignBattle.get_battle("battle_d")
	_check(not _has_detection_like_key(b), "battle record carries no detection field")
	var keys := b.keys()
	keys.sort()
	var want := BATTLE_KNOWN_KEYS.duplicate()
	want.sort()
	_check(keys == want, "battle record schema is exactly the 5 locked keys")
	for f in CampaignForce.get_forces():
		_check(not _has_detection_like_key(f),
			"participation + resolution create no force detection field")
	CampaignBattle.clear()


# D. Relocation records CURRENT presence only: no last_known shadow, no
# trace at the old node, no reveal of the new one.
func _test_movement_creates_no_detection() -> void:
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"), "force relocates")
	var after: Dictionary = CampaignForce.get_force("force_a")
	_check(not _has_detection_like_key(after), "movement creates no detection field")
	_check(not after.has("last_known_node") and not after.has("last_known_node_id")
		and not after.has("last_seen"), "no last-known shadow field after move")
	_check(CampaignForce.get_forces_at_node("node_s1_city_2_2").is_empty(),
		"old node keeps no trace (no observation history)")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")


# E. 5L boundary holds: still no supply shadow and no detection piggyback.
func _test_supply_boundary_holds() -> void:
	for f in CampaignForce.get_forces():
		_check(not f.has("supply") and not f.has("supply_status")
			and not _has_detection_like_key(f),
			"force %s has neither supply nor detection shadow" % str(f.get("id", "")))


# F. Patrols stay separate: force ops never churn board patrols, and patrol
# code never references CampaignForce (stance labels are not intel).
func _test_patrol_remains_separate() -> void:
	var patrols_before: int = GlobalData.board.board_patrols.size()
	CampaignForce.register_force("force_x", "CONVOY", "zeon", "node_s1_city_2_2", "", 1, 5)
	CampaignForce.set_node("force_x", "node_s1_safehouse_2_3")
	CampaignForce.set_state("force_x", CampaignForce.ForceState.DISABLED)
	CampaignBattle.register_battle("battle_px", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_px")
	_check(GlobalData.board.board_patrols.size() == patrols_before,
		"force register/move/state/battle churn leaves board patrols untouched")
	CampaignBattle.clear()
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	_check(not _code_of("res://scripts/systems/patrol_system.gd").contains("CampaignForce"),
		"patrol code never references CampaignForce (no intel bridge)")


# G. Spy pipeline intact and force-free: receipt still carries spy_event,
# forces byte-identical, spy code never references CampaignForce.
func _test_spy_remains_unchanged() -> void:
	var before := JSON.stringify(CampaignForce.get_forces())
	var receipt := CampaignTurnExecutive.advance_campaign_turn("detection_probe",
		{"day_boundary": true})
	_check((receipt as Dictionary).has("spy_event"),
		"turn receipt still carries the spy pipeline output (unchanged)")
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"spy turn leaves forces byte-identical (spy knowledge != force state)")
	_check(not _code_of("res://scripts/systems/enemy_faction_system.gd").contains("CampaignForce"),
		"spy code never references CampaignForce (no detection bridge)")
	for f in CampaignForce.get_forces():
		_check(not _has_detection_like_key(f), "spy turn creates no detection field")


# H. Save payload carries no detection shadow state for forces or battles.
func _test_persistence_has_no_detection() -> void:
	CampaignBattle.register_battle("battle_sv", "node_s1_city_2_2", ["force_a"])
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	for row in ((d as Dictionary).get("forces", {}) as Dictionary).get("forces", []):
		if _has_detection_like_key(row):
			clean = false
	for row in ((d as Dictionary).get("campaign_battles", {}) as Dictionary).get("battles", []):
		if _has_detection_like_key(row):
			clean = false
	_check(clean, "saved force + battle rows carry no detection field (schema unchanged)")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores state")
	for f in CampaignForce.get_forces():
		_check(not _has_detection_like_key(f), "loaded forces carry no detection field")
	CampaignBattle.clear()


# Negative tests: no detection authority was created for this phase, and no
# campaign file bridges intelligence onto forces.
func _test_no_detection_authority() -> void:
	_check(not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("detect")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("intel")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("visible")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("hidden")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("stealth")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("last_seen")
		and not _code_of("res://scripts/systems/campaign_force.gd").to_lower().contains("last_known"),
		"force source has no detection concept (code, not comments)")
	for path in ["res://scripts/systems/campaign_turn_executive.gd",
			"res://scripts/systems/campaign_node_registry.gd",
			"res://scripts/systems/campaign_territory.gd",
			"res://scripts/systems/campaign_base.gd",
			"res://scripts/systems/faction_system.gd"]:
		_check(not _code_of(path).contains("CampaignForce"),
			"no force-detection bridge in %s" % path.get_file())
	var battle_code := _code_of("res://scripts/systems/campaign_battle.gd").to_lower()
	_check(not battle_code.contains("detect") and not battle_code.contains("intel")
		and not battle_code.contains("visible") and not battle_code.contains("hidden")
		and not battle_code.contains("last_seen") and not battle_code.contains("last_known"),
		"battle code has no detection concept (eligibility reads are identity, not intel)")
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
				if n.contains("detection") or n.contains("intelligence") \
						or n.contains("fog_of_war") or n.contains("fogofwar") \
						or n.contains("recon_manager") or n.contains("spy_manager"):
					found_manager = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_manager, "no Detection/Intel/FogOfWar/Recon manager file exists")


# Reset leaves no intelligence residue (nothing to leak by construction).
func _test_reset() -> void:
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 2, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	for f in CampaignForce.get_forces():
		_check(not _has_detection_like_key(f), "post-reset forces carry no detection field")
	CampaignBattle.clear()
