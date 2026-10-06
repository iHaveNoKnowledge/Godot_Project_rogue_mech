extends Node
## PHASE 5I CAMPAIGN FORCE OPERATIONAL ELIGIBILITY BOUNDARY VERIFY.
##
## Answers one question from current architecture only:
##   Which CampaignForce states can join a CampaignBattle?
## Audited contract (Option A — current code already correct, locked here):
##   ACTIVE   -> eligible (register/add/launch accept)
##   DISABLED -> eligible (still a campaign entity; lifecycle != tactical
##               readiness; all three gates filter DESTROYED only)
##   DESTROYED -> rejected for NEW participation (register "", add false,
##               launch "force_destroyed"), but the record persists and
##               historical participant refs are never auto-deleted.
##   unknown  -> rejected (register "", add false, launch "unknown_force").
## Ownership pinned: Force owns state, Battle owns participants[].
## No back-reference (no battle_id on Force), no exclusivity rule, no
## node-match rule, no faction rule, no tactical semantics, no auto-recovery
## or auto-destruction. Production code untouched by 5I.
## User save backed up/restored.

var _fails := 0
var _checks := 0
var _backup := ""


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ELIGIBILITY OK: " + name)
	else:
		_fails += 1
		printerr("ELIGIBILITY FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)
	GlobalData.reset_run_data()
	_seed_world()
	_test_active_eligible()
	_test_disabled_eligible_documented()
	_test_destroyed_rejected()
	_test_unknown_rejected()
	_test_multiple_forces()
	_test_duplicate_contract()
	_test_state_mutation_no_rewrite()
	_test_destruction_no_autodelete()
	_test_node_mismatch_locked()
	_test_faction_mismatch_no_rejection()
	_test_no_back_reference()
	_test_no_exclusivity()
	_test_launch_gates()
	_test_save_load()
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
	print("CAMPAIGN_FORCE_BATTLE_ELIGIBILITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAMPAIGN_FORCE_BATTLE_ELIGIBILITY_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FORCE_BATTLE_ELIGIBILITY_TESTS_PASSED")
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
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


func _reseed_forces() -> void:
	CampaignForce.clear()
	CampaignForce.register_force("force_a", "PATROL", "zeon", "node_s1_city_2_2", "", 3, 10)
	CampaignForce.register_force("force_b", "SCAVENGER", "outland", "node_s1_safehouse_2_3", "", 2, 6)
	CampaignForce.register_force("force_c", "RIVAL", "federation", "", "", 1, 30)


# ACTIVE forces are operational campaign entities: fully eligible.
func _test_active_eligible() -> void:
	CampaignBattle.clear()
	_check(CampaignForce.is_active("force_a"), "ACTIVE is the operational campaign state")
	_check(CampaignBattle.register_battle("battle_active", "node_s1_city_2_2",
		["force_a"]) == "battle_active", "ACTIVE force seeds a battle")
	_check(CampaignBattle.add_participant("battle_active", "force_b"),
		"ACTIVE force joins an existing battle")
	_check(CampaignBattle.get_participants("battle_active") == ["force_a", "force_b"],
		"participants sorted deterministically")
	var d := CampaignBattle.prepare_launch("battle_active")
	_check(bool(d.get("ok", false)), "ACTIVE roster launches (PLANNED -> ACTIVE)")
	_check(CampaignBattle.is_active("battle_active"), "launch moved battle to ACTIVE")
	CampaignBattle.clear()


# DISABLED (Option A): still a campaign entity, still eligible. Lifecycle
# state is not tactical readiness; all gates filter DESTROYED only.
func _test_disabled_eligible_documented() -> void:
	CampaignBattle.clear()
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"ACTIVE -> DISABLED is a legal lifecycle edge")
	_check(not CampaignForce.is_active("force_a"), "DISABLED is not operational presence")
	_check(CampaignBattle.register_battle("battle_dis", "node_s1_city_2_2",
		["force_a"]) == "battle_dis", "DISABLED force seeds a battle (documented allow)")
	_check(CampaignBattle.add_participant("battle_dis", "force_b"),
		"ACTIVE force joins a DISABLED-seeded battle")
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_dis2", "node_s1_city_2_2", ["force_b"])
	_check(CampaignBattle.add_participant("battle_dis2", "force_a"),
		"DISABLED force joins an existing battle (documented allow)")
	var d := CampaignBattle.prepare_launch("battle_dis2")
	_check(bool(d.get("ok", false))
		and d.get("participant_force_ids", []) == ["force_a", "force_b"],
		"DISABLED participant launches (no tactical gate in campaign layer)")
	_check(CampaignBattle.is_active("battle_dis2"), "launch moved battle to ACTIVE")
	CampaignBattle.clear()
	_reseed_forces()


# DESTROYED: cannot seed/join new battles (existing "" / false convention),
# but the record persists and is never auto-deleted.
func _test_destroyed_rejected() -> void:
	CampaignBattle.clear()
	_check(CampaignForce.set_state("force_c", CampaignForce.ForceState.DESTROYED),
		"ACTIVE -> DESTROYED is a legal lifecycle edge")
	_check(CampaignBattle.register_battle("battle_doom", "node_s1_city_2_2",
		["force_c"]) == "", "DESTROYED force cannot seed a battle (empty-string convention)")
	CampaignBattle.register_battle("battle_ok", "node_s1_city_2_2", ["force_a"])
	_check(not CampaignBattle.add_participant("battle_ok", "force_c"),
		"DESTROYED force cannot join (false convention)")
	_check(not CampaignForce.has_force("force_nope")
		and CampaignForce.has_force("force_c"), "DESTROYED record persists (no auto-delete)")
	_check(not CampaignForce.get_force("force_c").is_empty(),
		"DESTROYED force data still readable")
	CampaignBattle.clear()
	_reseed_forces()


# Unknown force ids are never fabricated, held, or inferred.
func _test_unknown_rejected() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_ghost", "node_s1_city_2_2",
		["force_nope"]) == "", "unknown force cannot seed a battle")
	CampaignBattle.register_battle("battle_ok", "node_s1_city_2_2", ["force_a"])
	_check(not CampaignBattle.add_participant("battle_ok", "force_nope"),
		"unknown force cannot join")
	_check(not CampaignForce.has_force("force_nope"), "rejection created no force (no fabrication)")
	CampaignBattle.deserialize({"battles": [
		{"id": "battle_ghost2", "state": "planned", "node_id": "node_s1_city_2_2",
			"participants": ["force_ghost"]},
	]})
	var g := CampaignBattle.prepare_launch("battle_ghost2")
	_check(not bool(g.get("ok", true)) and str(g.get("error", "")) == "unknown_force",
		"unknown participant blocks launch (exact error convention)")
	CampaignBattle.clear()


# Two valid forces participate together; order-insensitive.
func _test_multiple_forces() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_multi", "node_s1_city_2_2",
		["force_b", "force_a"]) == "battle_multi", "A + B seed one battle")
	_check(CampaignBattle.get_participants("battle_multi") == ["force_a", "force_b"],
		"multi-force roster stored sorted")
	var d := CampaignBattle.prepare_launch("battle_multi")
	_check(bool(d.get("ok", false)), "multi-force roster launches")
	CampaignBattle.clear()


# Duplicate contract preserved: A,B,A collapses are rejected, never stored.
func _test_duplicate_contract() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_dup", "node_s1_city_2_2",
		["force_a", "force_a"]) == "", "A + A rejected at registration")
	CampaignBattle.register_battle("battle_dup2", "node_s1_city_2_2", ["force_a"])
	_check(not CampaignBattle.add_participant("battle_dup2", "force_a"),
		"duplicate add_participant rejected")
	_check(CampaignBattle.get_participants("battle_dup2") == ["force_a"],
		"participant list holds no duplicate")
	CampaignBattle.clear()


# Force state mutation never rewrites Battle participants (separate owners).
func _test_state_mutation_no_rewrite() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_mut", "node_s1_city_2_2", ["force_a"])
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED),
		"participant transitions ACTIVE -> DISABLED")
	_check(CampaignBattle.get_participants("battle_mut") == ["force_a"],
		"Battle participants unchanged by DISABLED transition")
	_check(CampaignBattle.is_planned("battle_mut"), "battle lifecycle untouched by force mutation")
	var d := CampaignBattle.prepare_launch("battle_mut")
	_check(bool(d.get("ok", false)), "DISABLED participant still launches (Option A holds)")
	CampaignBattle.clear()
	_reseed_forces()


# Destroying a registered participant keeps history; launch then blocks.
func _test_destruction_no_autodelete() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_hist", "node_s1_city_2_2", ["force_a"])
	_check(CampaignForce.set_state("force_a", CampaignForce.ForceState.DESTROYED),
		"participant transitions ACTIVE -> DESTROYED")
	_check(CampaignBattle.get_participants("battle_hist") == ["force_a"],
		"Battle participants unchanged by DESTROYED transition (historical data kept)")
	_check(CampaignForce.has_force("force_a"), "DESTROYED force record not auto-deleted")
	var d := CampaignBattle.prepare_launch("battle_hist")
	_check(not bool(d.get("ok", true)) and str(d.get("error", "")) == "force_destroyed",
		"destroyed participant blocks launch (exact error convention)")
	_check(CampaignBattle.is_planned("battle_hist"), "failed launch leaves battle PLANNED")
	CampaignBattle.clear()
	_reseed_forces()


# Node mismatch: no force.node_id == battle.node_id rule exists; Battle owns
# its node, Force node is an independent reference (reinforcement-compatible).
func _test_node_mismatch_locked() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_far", "node_s1_city_2_2",
		["force_b"]) == "battle_far",
		"force at safehouse joins battle at city (mismatch allowed)")
	_check(CampaignBattle.register_battle("battle_off", "node_s1_city_2_2",
		["force_c"]) == "battle_off",
		"off-board force (node_id '') joins a battle (no node requirement)")
	var d := CampaignBattle.prepare_launch("battle_far")
	_check(bool(d.get("ok", false)), "node-mismatched roster launches")
	CampaignBattle.clear()


# Faction mismatch: participant validation is not a diplomacy engine.
func _test_faction_mismatch_no_rejection() -> void:
	CampaignBattle.clear()
	var fa := str(CampaignForce.get_force("force_a").get("faction", ""))
	var fb := str(CampaignForce.get_force("force_b").get("faction", ""))
	_check(fa != "" and fb != "" and fa != fb, "test forces hold different factions")
	_check(CampaignBattle.register_battle("battle_mix", "node_s1_city_2_2",
		["force_a", "force_b"]) == "battle_mix",
		"cross-faction roster accepted (no relation gate)")
	var d := CampaignBattle.prepare_launch("battle_mix")
	_check(bool(d.get("ok", false)), "cross-faction roster launches")
	CampaignBattle.clear()


# No battle back-reference lives on the Force (encounter lifecycle is
# Battle-owned; future reinforcement must not read it from here).
func _test_no_back_reference() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_ref", "node_s1_city_2_2", ["force_a"])
	var f := CampaignForce.get_force("force_a")
	_check(not f.has("battle_id") and not f.has("current_battle_id")
		and not f.has("active_battle_ids"),
		"force carries no battle back-reference")
	CampaignBattle.clear()


# No exclusivity: one force may appear in several battles (no combat lock).
func _test_no_exclusivity() -> void:
	CampaignBattle.clear()
	_check(CampaignBattle.register_battle("battle_one", "node_s1_city_2_2",
		["force_a"]) == "battle_one", "Force A in Battle 1")
	_check(CampaignBattle.register_battle("battle_two", "node_s1_safehouse_2_3",
		["force_a", "force_b"]) == "battle_two", "Force A also in Battle 2 (no exclusivity)")
	_check(CampaignBattle.get_participants("battle_one") == ["force_a"]
		and CampaignBattle.get_participants("battle_two") == ["force_a", "force_b"],
		"both rosters intact")
	CampaignBattle.clear()


# Launch gates: only PLANNED launches; destroyed-after-registration blocks
# with the existing error while the record survives.
func _test_launch_gates() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_gate", "node_s1_city_2_2", ["force_a"])
	var d := CampaignBattle.prepare_launch("battle_gate")
	_check(bool(d.get("ok", false)), "PLANNED launches")
	var again := CampaignBattle.prepare_launch("battle_gate")
	_check(not bool(again.get("ok", true)) and str(again.get("error", "")) == "not_planned",
		"ACTIVE rejects duplicate launch (exact error convention)")
	CampaignBattle.register_battle("battle_gate2", "node_s1_city_2_2", ["force_b"])
	CampaignForce.set_state("force_b", CampaignForce.ForceState.DESTROYED)
	var blocked := CampaignBattle.prepare_launch("battle_gate2")
	_check(not bool(blocked.get("ok", true))
		and str(blocked.get("error", "")) == "force_destroyed",
		"destroyed-after-registration blocks launch")
	CampaignBattle.clear()
	_reseed_forces()


# Eligibility semantics survive save/load with no hidden normalization.
func _test_save_load() -> void:
	CampaignBattle.clear()
	_reseed_forces()
	CampaignForce.set_state("force_a", CampaignForce.ForceState.DISABLED)
	CampaignBattle.register_battle("battle_save", "node_s1_city_2_2", ["force_a", "force_b"])
	_check(SaveGameIO.save_run(), "save_run carries forces + battles")
	CampaignForce.clear()
	CampaignBattle.clear()
	_check(SaveGameIO.load_run(), "load_run restores forces + battles")
	_check(CampaignForce.get_state("force_a") == CampaignForce.ForceState.DISABLED,
		"DISABLED state survives save/load (no silent revival)")
	_check(CampaignBattle.get_participants("battle_save") == ["force_a", "force_b"],
		"participants survive save/load (no normalization)")
	var d := CampaignBattle.prepare_launch("battle_save")
	_check(bool(d.get("ok", false)), "restored DISABLED roster still launches")
	CampaignBattle.clear()
	_reseed_forces()


# Reset clears both registries with no stale participant references.
func _test_reset() -> void:
	CampaignBattle.clear()
	CampaignBattle.register_battle("battle_reset", "node_s1_city_2_2", ["force_a"])
	CampaignBattle.prepare_launch("battle_reset")
	GlobalData.reset_run_data()
	_seed_world()
	_check(CampaignForce.get_forces().size() == 3, "seed restored after reset")
	_check(CampaignBattle.get_battles().is_empty(),
		"reset_run_data clears battles (no stale participant refs)")
	_check(CampaignBattle.validate().is_empty(), "no stale participant refs after reset")
	CampaignBattle.clear()
