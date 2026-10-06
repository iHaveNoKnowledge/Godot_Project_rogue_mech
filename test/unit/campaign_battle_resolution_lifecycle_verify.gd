extends Node
## PHASE 5J BATTLE RESOLUTION LIFECYCLE VERIFY (boundary only, NO combat).
##
## Locks the complete CampaignBattle lifecycle from current architecture:
##   PLANNED -> ACTIVE -> RESOLVED, plus PLANNED/ACTIVE -> CANCELLED.
##   RESOLVED and CANCELLED are terminal (no reactivation, no second close).
## Ownership pinned: Battle owns lifecycle + participants[] + session_ref;
## Force owns state/node/base/faction/composition. resolve/cancel mutate
## ONLY the battle state — never participants, never forces, never combat.
## Participants are historical identity: DISABLED/DESTROYED transitions,
## node moves, and faction changes never rewrite a Battle, and resolution
## stays possible (resolution is a lifecycle close, not an eligibility gate
## like prepare_launch). No outcome/winner/casualty/reward fields exist and
## none are needed: RESOLVED/CANCELLED already carry the lifecycle.
## Combat isolation: no CombatSession, no GameManager/SpawnManager touch,
## no battle signals, session_ref opaque and lifecycle-independent.
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RESOLUTION OK: " + name)
	else:
		_fails += 1
		printerr("RESOLUTION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_planned()
	_test_active()
	_test_resolved_terminal()
	_test_cancelled_terminal()
	_test_force_mutation()
	_test_node_mutation()
	_test_faction_mutation()
	_test_session_isolation()
	_test_no_battle_signals()
	_test_source_isolation()
	_test_persistence()
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
	print("CAMPAIGN_BATTLE_RESOLUTION_LIFECYCLE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_BATTLE_RESOLUTION_LIFECYCLE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_BATTLE_RESOLUTION_LIFECYCLE_TESTS_PASSED")
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
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


func _reseed_forces() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)


# PLANNED: exists, can activate, can cancel, cannot resolve directly.
func _test_planned() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_p", "node_s1_city_2_2", ["force_a"])
	_check(CampaignBattle.is_planned("battle_p"), "PLANNED exists as initial state")
	_check(not CampaignBattle.resolve_battle("battle_p"),
		"PLANNED cannot resolve directly (must activate first)")
	_check(CampaignBattle.is_planned("battle_p"), "rejected resolve changed nothing")
	_check(CampaignBattle.begin_battle("battle_p"), "PLANNED -> ACTIVE")
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_c", "node_s1_city_2_2", ["force_a"])
	_check(CampaignBattle.cancel_battle("battle_c"), "PLANNED -> CANCELLED")
	_check(not CampaignBattle.begin_battle("battle_nope"), "begin on unknown rejected")
	_check(not CampaignBattle.resolve_battle("battle_nope"), "resolve on unknown rejected")
	_check(not CampaignBattle.cancel_battle("battle_nope"), "cancel on unknown rejected")
	CampaignBattle.clear()


# ACTIVE: can resolve, can cancel (both close the lifecycle, never RESOLVED-by-cancel).
func _test_active() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_r", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_r")
	_check(CampaignBattle.resolve_battle("battle_r"), "ACTIVE -> RESOLVED")
	_check(CampaignBattle.get_state("battle_r") == CampaignBattle.BattleState.RESOLVED,
		"resolved battle reads RESOLVED")
	CampaignBattle.register_battle("battle_x", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.begin_battle("battle_x")
	_check(CampaignBattle.cancel_battle("battle_x"), "ACTIVE -> CANCELLED")
	_check(CampaignBattle.get_state("battle_x") == CampaignBattle.BattleState.CANCELLED,
		"cancelled battle reads CANCELLED (cancel never marks RESOLVED)")
	CampaignBattle.clear()


# RESOLVED is terminal: no cancel, no re-resolve, no reactivation.
# Participants preserved; forces byte-identical; record persists.
func _test_resolved_terminal() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_t", "node_s1_city_2_2", ["force_a", "force_b"])
	var forces_before := JSON.stringify(CampaignForce.get_forces())
	CampaignBattle.set_session_ref("battle_t", "session_1")
	CampaignBattle.begin_battle("battle_t")
	_check(CampaignBattle.resolve_battle("battle_t"), "ACTIVE resolves")
	_check(not CampaignBattle.cancel_battle("battle_t"), "RESOLVED cannot cancel")
	_check(not CampaignBattle.resolve_battle("battle_t"), "RESOLVED cannot resolve again")
	_check(not CampaignBattle.begin_battle("battle_t"), "RESOLVED terminal (no reactivation)")
	_check(CampaignBattle.get_participants("battle_t") == ["force_a", "force_b"],
		"resolve preserves participants (no roster mutation)")
	_check(JSON.stringify(CampaignForce.get_forces()) == forces_before,
		"resolve mutates no force (no casualties, no state change)")
	_check(CampaignBattle.get_session_ref("battle_t") == "session_1",
		"resolve preserves session_ref (lifecycle does not manage sessions)")
	_check(CampaignBattle.has_battle("battle_t"), "resolved battle record persists (historical)")
	CampaignBattle.clear()


# CANCELLED is terminal: no resolve, no second cancel, no reactivation.
func _test_cancelled_terminal() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_k", "node_s1_city_2_2", ["force_a"])
	var forces_before := JSON.stringify(CampaignForce.get_forces())
	CampaignBattle.begin_battle("battle_k")
	_check(CampaignBattle.cancel_battle("battle_k"), "ACTIVE cancels")
	_check(not CampaignBattle.resolve_battle("battle_k"), "CANCELLED cannot resolve")
	_check(not CampaignBattle.cancel_battle("battle_k"), "CANCELLED cannot cancel again")
	_check(not CampaignBattle.begin_battle("battle_k"), "CANCELLED terminal (no reactivation)")
	_check(CampaignBattle.get_participants("battle_k") == ["force_a"],
		"cancel preserves participants (no roster mutation)")
	_check(JSON.stringify(CampaignForce.get_forces()) == forces_before,
		"cancel mutates no force")
	_check(CampaignBattle.has_battle("battle_k"), "cancelled battle record persists (historical)")
	CampaignBattle.clear()


# Force state mutation never rewrites a Battle; resolution stays a pure
# lifecycle close (unlike prepare_launch, it is not an eligibility gate).
func _test_force_mutation() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_f", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_f")
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"participant transitions ACTIVE -> DISABLED")
	_check(CampaignBattle.get_participants("battle_f") == ["force_a"],
		"Battle participants unchanged by DISABLED transition")
	_check(CampaignBattle.is_active("battle_f"), "Battle not auto-cancelled by DISABLED")
	_check(CampaignBattle.resolve_battle("battle_f"), "DISABLED participant still resolves")
	_check(CampaignBattle.get_participants("battle_f") == ["force_a"],
		"resolved roster keeps DISABLED participant id")
	CampaignBattle.clear()
	_reseed_forces()
	CampaignBattle.register_battle("battle_g", "node_s1_city_2_2", ["force_a", "force_b"])
	CampaignBattle.begin_battle("battle_g")
	var b_before := JSON.stringify(CampaignForce.get_force("force_b"))
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"participant transitions ACTIVE -> DESTROYED")
	_check(CampaignBattle.get_participants("battle_g") == ["force_a", "force_b"],
		"Battle participants unchanged by DESTROYED transition (historical kept)")
	_check(CampaignBattle.is_active("battle_g"), "Battle not auto-cancelled by DESTROYED")
	_check(CampaignBattle.resolve_battle("battle_g"),
		"destroyed participant still resolves (close, not eligibility gate)")
	_check(CampaignBattle.get_participants("battle_g") == ["force_a", "force_b"],
		"destroyed participant id preserved after resolve")
	_check(JSON.stringify(CampaignForce.get_force("force_b")) == b_before,
		"uninvolved force byte-identical across destroy + resolve")
	_check(CampaignForce.has_force("force_a"), "DESTROYED force record not auto-deleted by resolve")
	CampaignBattle.clear()
	_reseed_forces()


# Force relocation never rewrites a Battle (no node-lock semantics).
func _test_node_mutation() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_n", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_n")
	_check(CampaignForce.set_node("force_a", "node_s1_safehouse_2_3"),
		"participant relocates to another node")
	_check(str(CampaignBattle.get_battle("battle_n").get("node_id", "")) == "node_s1_city_2_2",
		"Battle node unchanged by force relocation")
	_check(CampaignBattle.get_participants("battle_n") == ["force_a"],
		"Battle participants unchanged by force relocation")
	_check(CampaignBattle.is_active("battle_n"), "Battle not auto-cancelled by relocation")
	_check(CampaignForce.set_node("force_a", ""), "participant moves off-board")
	_check(CampaignBattle.get_participants("battle_n") == ["force_a"]
		and CampaignBattle.is_active("battle_n"),
		"off-board move changes nothing about the Battle")
	_check(CampaignBattle.resolve_battle("battle_n"), "relocated roster still resolves")
	CampaignBattle.clear()
	_reseed_forces()


# Faction change never rewrites a Battle (membership is not relation matrix).
func _test_faction_mutation() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_m", "node_s1_city_2_2", ["force_a", "force_b"])
	CampaignBattle.begin_battle("battle_m")
	_check(CampaignForce.set_faction("force_a", "federation"), "participant changes faction")
	_check(CampaignBattle.get_participants("battle_m") == ["force_a", "force_b"],
		"Battle participants unchanged by faction change")
	_check(CampaignBattle.is_active("battle_m"), "Battle not auto-cancelled by faction change")
	_check(CampaignBattle.resolve_battle("battle_m"), "faction-changed roster still resolves")
	CampaignBattle.clear()
	_reseed_forces()


# resolve/cancel never invoke tactical combat; session_ref stays independent.
func _test_session_isolation() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_s", "node_s1_city_2_2", ["force_a"])
	var state_before: int = GameManager.current_state
	var type_before := str(GameManager.combat_node_type)
	CampaignBattle.set_session_ref("battle_s", "session_9")
	CampaignBattle.begin_battle("battle_s")
	CampaignBattle.resolve_battle("battle_s")
	_check(GameManager.current_state == state_before, "resolve touches no game state")
	_check(str(GameManager.combat_node_type) == type_before,
		"resolve touches no combat entry type (no tactical bridge)")
	_check(CampaignBattle.get_session_ref("battle_s") == "session_9",
		"session_ref survives resolve (cleared only by explicit clear)")
	_check(CampaignBattle.clear_session_ref("battle_s"), "explicit session clear accepted")
	_check(CampaignBattle.get_session_ref("battle_s") == "",
		"session reference cleared explicitly, battle record untouched")
	CampaignBattle.register_battle("battle_s2", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.begin_battle("battle_s2")
	CampaignBattle.cancel_battle("battle_s2")
	_check(GameManager.current_state == state_before, "cancel touches no game state")
	_check(str(GameManager.combat_node_type) == type_before,
		"cancel touches no combat entry type")
	CampaignBattle.clear()


# No battle lifecycle signals exist (no consumer requires one in 5J).
func _test_no_battle_signals() -> void:
	_check(not EventBus.has_signal("campaign_battle_started"), "no battle started signal")
	_check(not EventBus.has_signal("campaign_battle_resolved"), "no battle resolved signal")
	_check(not EventBus.has_signal("campaign_battle_cancelled"), "no battle cancelled signal")
	_check(not EventBus.has_signal("campaign_battle_changed"), "no battle changed signal")


# Static guard: battle source (code, not comments) never references tactical
# authorities, and no parallel battle/combat manager file exists.
func _test_source_isolation() -> void:
	var path := "res://scripts/systems/campaign_battle.gd"
	_check(FileAccess.file_exists(path), "battle source readable for static audit")
	var raw := FileAccess.get_file_as_string(path)
	var code_lines: PackedStringArray = []
	for line in raw.split("\n"):
		var cut := line.find("#")
		if cut != -1:
			line = line.substr(0, cut)
		code_lines.append(line)
	var code := "\n".join(code_lines)
	var clean := true
	for token in ["CombatSession", "GameManager", "SpawnManager", "combat_ended",
			"enter_combat", "EventBus", "set_state", "set_node", "unit_count", "strength"]:
		if token == "set_state" or token == "set_node":
			if code.contains("CampaignForce." + token):
				clean = false
		elif code.contains(token):
			clean = false
	_check(clean, "battle code references no tactical/force-mutating authority")
	var dir := DirAccess.open("res://scripts/systems")
	var names: PackedStringArray = []
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				names.append(entry.to_lower())
			entry = dir.get_next()
		dir.list_dir_end()
	var parallel := false
	for n in names:
		if n.contains("combat_session") or n.contains("battle_manager") \
				or n.contains("battle_resolver") or n.contains("battle_outcome") \
				or n.contains("battle_system"):
			parallel = true
	_check(not parallel, "no parallel battle manager/resolver/outcome authority exists")


# Lifecycle state + historical participants round-trip through save/load.
func _test_persistence() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_pr", "node_s1_city_2_2", ["force_a", "force_b"])
	CampaignBattle.set_session_ref("battle_pr", "session_p")
	CampaignBattle.begin_battle("battle_pr")
	CampaignBattle.resolve_battle("battle_pr")
	CampaignBattle.register_battle("battle_pc", "node_s1_safehouse_2_3", ["force_b"])
	CampaignBattle.cancel_battle("battle_pc")
	_check(SaveGameIO.save_run(), "save_run carries resolved + cancelled battles")
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores battles")
	_check(CampaignBattle.get_state("battle_pr") == CampaignBattle.BattleState.RESOLVED,
		"RESOLVED survives save/load")
	_check(CampaignBattle.get_participants("battle_pr") == ["force_a", "force_b"],
		"resolved participants survive save/load (no normalization)")
	_check(CampaignBattle.get_session_ref("battle_pr") == "session_p",
		"session_ref survives save/load")
	_check(CampaignBattle.get_state("battle_pc") == CampaignBattle.BattleState.CANCELLED,
		"CANCELLED survives save/load")
	_check(CampaignBattle.get_participants("battle_pc") == ["force_b"],
		"cancelled participants survive save/load")
	CampaignBattle.clear()


# Reset clears the registry; nothing resurrects a closed battle.
func _test_reset() -> void:
	CampaignBattle.register_battle("battle_q", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.begin_battle("battle_q")
	CampaignBattle.resolve_battle("battle_q")
	CampaignBattle.register_battle("battle_w", "node_s1_city_2_2", ["force_b"])
	CampaignBattle.cancel_battle("battle_w")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignBattle.get_battles().is_empty(),
		"reset_run_data clears battles (no Run A leakage)")
	_check(CampaignBattle.validate().is_empty(), "no stale participant refs after reset")
	_check(CampaignForce.get_forces().size() == 2, "seed restored after reset")
	CampaignBattle.clear()
