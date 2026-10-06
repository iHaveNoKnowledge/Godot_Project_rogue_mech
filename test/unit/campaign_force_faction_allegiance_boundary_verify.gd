extends Node
## PHASE 5O FORCE FACTION ALLEGIANCE / DEFECTION BOUNDARY VERIFY (audit-first).
##
## Audited answer (Option D): CampaignForce.faction is CURRENT affiliation
## only. No defection/betrayal/transfer/history concept exists anywhere in
## production (zero vocabulary hits; set_faction has zero production
## callers — tests only). The field stays exactly as-is; no allegiance
## manager, no history shadow, no side effects. Locked splits:
##   faction identity/registry/relations -> FactionSystem (HOSTILE/NEUTRAL/
##     COOPERATIVE/ALLIED matrix; unknown ids read NEUTRAL, never a force);
##   patrol stance labels (hostile/unknown/scavenger) -> board encounters,
##     never canonical faction ids ("unknown"/"hostile" rejected as factions);
##   territory controller / base controller -> their own authorities, never
##     derived from or written by force faction;
##   battle participants -> identity only, no faction-side grouping;
##   force_type -> classification only, fabricates no faction.
## set_faction() itself is an explicit low-level write (validated id or ""
## to clear); changing it mutates ONLY the faction key. 5K/5L/5M/5N
## boundaries hold. User save backed up/restored.

const HISTORY_LIKE_KEYS := ["previous_faction", "original_faction",
	"former_faction", "faction_history", "allegiance", "loyalty",
	"defected", "betrayed", "captured_by", "joined_turn", "defection_turn",
	"defection", "betrayal", "reputation"]

const FORCE_KNOWN_KEYS := ["id", "force_type", "state", "faction",
	"node_id", "base_id", "unit_count", "strength"]

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ALLEGIANCE OK: " + name)
	else:
		_fails += 1
		printerr("ALLEGIANCE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_explicit_identity()
	_test_type_fabricates_no_faction()
	_test_presence_base_territory_change_no_faction()
	_test_battle_changes_no_faction()
	_test_turn_creates_no_transfer()
	_test_patrol_stance_not_faction()
	_test_set_faction_contract()
	_test_boundaries_hold()
	_test_no_allegiance_authority()
	_test_persistence_current_only()
	_test_reset()
	_test_relation_semantics_unchanged()
	GlobalData.reset_run_data()
	if _backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.flush()
		f.close()
	else:
		if FileAccess.file_exists(GlobalData.SAVE_PATH):
			DirAccess.remove_absolute(GlobalData.SAVE_PATH)
	print("CAMPAIGN_FORCE_FACTION_ALLEGIANCE_BOUNDARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_FACTION_ALLEGIANCE_BOUNDARY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_FACTION_ALLEGIANCE_TESTS_PASSED")
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


func _has_history_like_key(d: Dictionary) -> bool:
	for k in HISTORY_LIKE_KEYS:
		if d.has(k):
			return true
	return false


func _check_exact_schema(fid: String, label: String) -> void:
	var f: Dictionary = CampaignForce.get_force(fid)
	_check(not _has_history_like_key(f), "no allegiance-history field on %s (%s)" % [fid, label])
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


# 1-2. Faction is explicit current identity; registration fabricates nothing.
func _test_explicit_identity() -> void:
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"registered faction stored verbatim (current identity)")
	_check(CampaignForce.register_force("force_u", "CONVOY", "",
		"node_s1_city_2_2", "", 1, 5) == "force_u",
		"unattributed (empty faction) registration accepted")
	_check(str(CampaignForce.get_force("force_u").get("faction", "X")) == "",
		"empty faction stays empty (no inference, no default)")
	_check(CampaignForce.register_force("force_bad", "PATROL", "nope") == "",
		"unregistered faction rejected at registration")
	_check_exact_schema("force_a", "explicit identity")
	_check_exact_schema("force_u", "unattributed")
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 3. Force type fabricates no faction (classification only).
func _test_type_fabricates_no_faction() -> void:
	var types: Array = ["PATROL", "CONVOY", "SCAVENGER", "RIVAL"]
	for t in types:
		var fid: String = "force_ft_" + str(t).to_lower()
		_check(CampaignForce.register_force(fid, str(t), "",
			"node_s1_city_2_2", "", 1, 5) == fid, "type %s registers unattributed" % str(t))
		_check(str(CampaignForce.get_force(fid).get("faction", "X")) == "",
			"type %s implies no faction" % str(t))
		CampaignForce.clear()
		CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
		CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# 4-6. Presence, base link, and territory context change no faction and write
# no controller anywhere.
func _test_presence_base_territory_change_no_faction() -> void:
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"), "force relocates")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"relocation changes no faction")
	var base_before := JSON.stringify(CampaignBase.get_base("base_alpha"))
	_check(CampaignForce.set_base("force_a", "base_alpha"), "force attaches to base")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"base attachment changes no faction")
	_check(str(CampaignBase.get_base("base_alpha").get("controller", "")) == "federation"
		and JSON.stringify(CampaignBase.get_base("base_alpha")) == base_before,
		"zeon force attached, base controller still federation (no takeover)")
	var terr_before := JSON.stringify(CampaignTerritory.serialize())
	_check(CampaignForce.get_territory_context("force_a") == "terr_downtown",
		"territory context derives")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"territory context changes no faction")
	_check(JSON.stringify(CampaignTerritory.serialize()) == terr_before,
		"presence writes no territory control")
	_check_exact_schema("force_a", "after presence/base/territory contact")
	CampaignForce.set_base("force_a", "")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")


# 7-8. Battle lifecycle is faction-blind: no validation, no grouping, no write.
func _test_battle_changes_no_faction() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_f", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_f",
		"cross-faction roster registers (no side grouping)")
	_check(bool(CampaignBattle.prepare_launch("battle_f").get("ok", false)),
		"cross-faction roster launches (no relation gate)")
	_check(CampaignBattle.resolve_battle("battle_f"), "battle resolves")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon"
		and str(CampaignForce.get_force("force_b").get("faction", "")) == "outland",
		"register + launch + resolve change no faction")
	_check_exact_schema("force_a", "after battle lifecycle")
	_check_exact_schema("force_b", "after battle lifecycle")
	CampaignBattle.clear()


# 9. Turns never fabricate a transfer.
func _test_turn_creates_no_transfer() -> void:
	var before := JSON.stringify(CampaignForce.get_forces())
	CampaignTurnExecutive.advance_campaign_turn("allegiance_probe", {"day_boundary": false})
	CampaignTurnExecutive.advance_campaign_turn("allegiance_probe", {})
	_check(JSON.stringify(CampaignForce.get_forces()) == before,
		"turns leave forces byte-identical (no transfer tick)")
	_check_exact_schema("force_a", "after turns")


# 13-14. Patrol stance labels are not faction ids; force ops churn no patrols.
func _test_patrol_stance_not_faction() -> void:
	_check(not FactionSystem.has_faction("unknown"), "'unknown' is not a faction id")
	_check(not FactionSystem.has_faction("hostile"), "'hostile' is not a faction id")
	_check(CampaignForce.register_force("force_pu", "PATROL", "unknown") == "",
		"patrol 'unknown' label rejected as force faction")
	_check(CampaignForce.register_force("force_ph", "PATROL", "hostile") == "",
		"patrol 'hostile' label rejected as force faction")
	_check(not CampaignForce.set_faction("force_a", "scavenger favor"),
		"non-id faction string rejected")
	var patrols_before: int = GlobalData.board.board_patrols.size()
	CampaignForce.set_faction("force_a", "federation")
	CampaignForce.set_node("force_a", "node_s1_safehouse_2_3")
	_check(GlobalData.board.board_patrols.size() == patrols_before,
		"faction write + move churn no patrols (stances stay board-owned)")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "federation",
		"explicit set_faction write lands")
	CampaignForce.set_faction("force_a", "zeon")
	CampaignForce.set_node("force_a", "node_s1_city_2_2")


# set_faction() contract: validated id or "" to clear; writes ONLY faction.
func _test_set_faction_contract() -> void:
	var before: Dictionary = CampaignForce.get_force("force_a")
	_check(CampaignForce.set_faction("force_a", "federation"), "valid faction accepted")
	var after: Dictionary = CampaignForce.get_force("force_a")
	var only_faction := str(after.get("faction", "")) == "federation"
	for k in before:
		if str(k) == "faction":
			continue
		if after.get(k) != before.get(k):
			only_faction = false
	_check(only_faction, "faction write mutates ONLY the faction key")
	_check(not CampaignForce.set_faction("force_a", "nope"), "unknown faction rejected")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "federation",
		"rejected write changed nothing")
	_check(CampaignForce.set_faction("force_a", ""), "clearing to unattributed accepted")
	_check(not CampaignForce.set_faction("force_nope", "zeon"), "write on unknown force rejected")
	_check(CampaignForce.set_faction("force_a", "zeon"), "faction restored")
	_check_exact_schema("force_a", "after faction writes")


# 10-12. 5M/5L/5N boundaries hold on every record.
func _test_boundaries_hold() -> void:
	for f in CampaignForce.get_forces():
		var d: Dictionary = f
		_check(not d.has("supply") and not d.has("supply_status")
			and not d.has("detected") and not d.has("visible")
			and not d.has("intel") and not d.has("last_known_node_id")
			and not _has_history_like_key(d)
			and not d.has("order") and not d.has("mission")
			and not d.has("objective") and not d.has("destination"),
			"force %s keeps 5L/5M/5N absence" % str(d.get("id", "")))


# 17-19. Negative tests: no history concept, no transfer authority.
func _test_no_allegiance_authority() -> void:
	var force_code := _code_of("res://scripts/systems/campaign_force.gd").to_lower()
	var clean := true
	for token in ["allegiance", "defect", "betray", "loyal", "transfer",
			"reputation", "history", "former_", "previous_faction",
			"original_faction", "turncoat", "desert"]:
		if force_code.contains(token):
			clean = false
	_check(clean, "force source has no allegiance concept (code, not comments)")
	_check(not _code_of("res://scripts/systems/faction_system.gd").contains("CampaignForce"),
		"faction registry never references forces (no membership authority)")
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
				if n.contains("defect") or n.contains("betray") \
						or n.contains("allegiance") or n.contains("loyalty") \
						or n.contains("faction_transfer") or n.contains("factiontransfer"):
					found_manager = true
			entry = dir.get_next()
		dir.list_dir_end()
	_check(not found_manager, "no defection/betrayal/allegiance manager file exists")


# 15. Save rows carry current faction only; load restores it with no history.
func _test_persistence_current_only() -> void:
	_check(SaveGameIO.save_run(), "save_run succeeds")
	var d = JSON.parse_string(FileAccess.get_file_as_string(GlobalData.SAVE_PATH))
	var clean := true
	var seen_zeon := false
	for row in ((d as Dictionary).get("forces", {}) as Dictionary).get("forces", []):
		if _has_history_like_key(row):
			clean = false
		if str((row as Dictionary).get("faction", "")) == "zeon":
			seen_zeon = true
	_check(clean, "saved rows carry no allegiance-history field (schema unchanged)")
	_check(seen_zeon, "saved rows carry current faction verbatim")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"current faction survives save/load with no history attached")
	_check_exact_schema("force_a", "after load")


# 16. Reset clears per existing contract; nothing resurrects allegiance.
func _test_reset() -> void:
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 2, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(), "reset clears battles (no stale refs)")
	_check(str(CampaignForce.get_force("force_a").get("faction", "")) == "zeon",
		"seed faction restored deterministically (no residue)")
	CampaignBattle.clear()


# 20. Relation matrix semantics untouched: unknown reads NEUTRAL, self ALLIED.
func _test_relation_semantics_unchanged() -> void:
	_check(FactionSystem.get_relation("zeon", "nope_faction")
		== FactionSystem.Relation.NEUTRAL, "unknown faction reads NEUTRAL")
	_check(FactionSystem.get_relation("zeon", "zeon")
		== FactionSystem.Relation.ALLIED, "self-relation reads ALLIED")
	_check(FactionSystem.get_relation_name("zeon", "zeon") == "allied",
		"relation name mapping intact")
	FactionSystem.reset_relations()
	_check(FactionSystem.get_relation("zeon", "federation")
		== FactionSystem.Relation.NEUTRAL, "reset restores default matrix")
