extends Node
## ---------------------------------------------------------------------------
## PLAYER STRATEGIC FORCE + AUTO-BATTLE DEFENCE VERIFY — Phase C8-A.
##
## Covers:
##   - CampaignPlayerForce authority (registration, validation, queries, state)
##   - Casualty application (strength + proportional units, wipe-out)
##   - Serialization round-trip, malformed rows, reset
##   - Base defence auto-battle decided by strength (held and lost paths)
##   - No player force = legacy Option D behaviour unchanged
##   - RunStartSystem garrison seeding (idempotent) + save schema declaration
##   - GlobalData.reset_run_data() lifecycle reset
## ---------------------------------------------------------------------------

const SaveGameIOScript = preload("res://scripts/systems/save_game_io.gd")

var _checks := 0
var _fails := 0
var _notices: Array = []


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C8A_PLAYER_FORCE OK: %s" % message)
	else:
		_fails += 1
		printerr("C8A_PLAYER_FORCE FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN PLAYER STRATEGIC FORCE VERIFY (Phase C8-A) ---")
	print("======================================================================")

	_test_authority_basics()
	_test_casualties()
	_test_serialization()
	_test_defence_held()
	_test_defence_lost()
	_test_no_player_force_legacy_path()
	_test_run_start_seed()
	_test_global_reset()

	print("----------------------------------------------------------------------")
	print("PHASE C8-A SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")
	if _fails == 0:
		print("ALL PLAYER STRATEGIC FORCE (C8-A) CHECKS PASSED!")
	else:
		printerr("C8-A PLAYER FORCE VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _reset_world() -> void:
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignPlayerForce.reset()
	CampaignBaseDefense.reset_defense_state()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionSystem.set_player_faction("federation")
	GlobalData.current_campaign_player_node_id = ""


func _setup_assault(tag: String, tile: Vector2i, attacker_strength: int,
		garrison_strength: int) -> Dictionary:
	_reset_world()
	var node_id := CampaignNodeRegistry.register_node(1, tile, "safehouse")
	CampaignTerritory.register_territory("terr_" + tag, [node_id])
	var base_id := CampaignBase.register_base("base_" + tag, node_id, "OUTPOST", "federation")
	var attacker_id := CampaignForce.register_force(
		"force_zeon_" + tag, "PATROL", "zeon", node_id, "", 3, attacker_strength)
	FactionSystem.set_relation("federation", "zeon", FactionSystem.Relation.HOSTILE)
	var garrison_id := ""
	if garrison_strength > 0:
		garrison_id = CampaignPlayerForce.register_detachment(
			"player_force_" + tag, node_id, base_id, 2, garrison_strength)
	var created: Array = CampaignBaseDefense.process_assault_turn(5).get("created", [])
	var battle_id := str(created[0]) if not created.is_empty() else ""
	_check(battle_id != "", "assault battle created for %s" % tag)
	return {
		"node_id": node_id, "base_id": base_id, "attacker_id": attacker_id,
		"garrison_id": garrison_id, "battle_id": battle_id,
	}


func _test_authority_basics() -> void:
	_reset_world()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city")
	var base_id := CampaignBase.register_base("base_auth", node_id, "OUTPOST", "federation")
	var fid := CampaignPlayerForce.register_detachment("player_force_auth", node_id, base_id, 2, 20)
	_check(fid != "", "detachment registers against a real node and base")
	_check(CampaignPlayerForce.has_detachment(fid), "registered detachment is queryable")
	_check(int(CampaignPlayerForce.get_detachment(fid).get("strength", -1)) == 20,
		"strength stored exactly")
	_check(int(CampaignPlayerForce.get_total_strength()) == 20, "total active strength rolls up")
	_check(CampaignPlayerForce.get_active_at_node(node_id) == [fid],
		"node query finds the detachment")
	_check(CampaignPlayerForce.get_active_at_base(base_id) == [fid],
		"base query finds the detachment")
	_check(CampaignPlayerForce.register_detachment("player_force_auth", node_id, base_id, 2, 20) == fid,
		"identical re-registration is idempotent")
	_check(CampaignPlayerForce.register_detachment("player_force_auth", node_id, base_id, 3, 20) == "",
		"conflicting re-registration is rejected")
	_check(CampaignPlayerForce.register_detachment("player_force_bad", "node_missing", "", 1, 5) == "",
		"unknown node is rejected")
	_check(CampaignPlayerForce.register_detachment("player_force_bad", node_id, "base_missing", 1, 5) == "",
		"unknown base is rejected")
	_check(CampaignPlayerForce.register_detachment("player_force_bad", node_id, "", -1, 5) == "",
		"negative composition is rejected")
	_check(CampaignPlayerForce.register_detachment("", node_id, "", 1, 5) == "",
		"empty id is rejected")
	_check(CampaignPlayerForce.make_detachment_id("Home Garrison") == "player_force_home_garrison",
		"id slug is stable and lowercased")
	_check(CampaignPlayerForce.set_strength(fid, 0), "strength can be zeroed")
	_check(CampaignPlayerForce.get_state(fid) == CampaignPlayerForce.ForceState.DISABLED,
		"zero strength disables the detachment")
	_check(int(CampaignPlayerForce.get_detachment(fid).get("unit_count", -1)) == 0,
		"zero strength zeroes units")
	_check(CampaignPlayerForce.set_strength(fid, 15), "strength can be restored")
	_check(CampaignPlayerForce.is_active(fid), "restored strength reactivates the detachment")
	_check(CampaignPlayerForce.validate().is_empty(), "healthy registry validates clean")


func _test_casualties() -> void:
	_reset_world()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city")
	var fid := CampaignPlayerForce.register_detachment("player_force_cas", node_id, "", 4, 40)
	var receipt := CampaignPlayerForce.apply_casualties(fid, 10)
	_check(bool(receipt.get("ok", false)), "casualties apply")
	_check(int(receipt.get("strength_after", -1)) == 30, "strength reduced by the loss")
	_check(int(receipt.get("units_lost", -1)) == 1, "units lost proportionally (10/40 of 4)")
	_check(int(CampaignPlayerForce.get_detachment(fid).get("unit_count", -1)) == 3,
		"unit count follows casualties")
	var wipe := CampaignPlayerForce.apply_casualties(fid, 999)
	_check(int(wipe.get("strength_after", -1)) == 0, "over-loss clamps to zero strength")
	_check(int(wipe.get("units_lost", -1)) == 3, "wipe-out loses every remaining unit")
	_check(CampaignPlayerForce.get_state(fid) == CampaignPlayerForce.ForceState.DISABLED,
		"wiped-out detachment is disabled, not deleted")
	var none := CampaignPlayerForce.apply_casualties(fid, 0)
	_check(int(none.get("units_lost", -1)) == 0, "zero loss changes nothing")
	_check(not bool(CampaignPlayerForce.apply_casualties("missing_force", 5).get("ok", true)),
		"unknown detachment is refused")


func _test_serialization() -> void:
	_reset_world()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "city")
	var fid := CampaignPlayerForce.register_detachment("player_force_ser", node_id, "", 2, 25)
	var payload := CampaignPlayerForce.serialize()
	_check(payload.has("detachments"), "serialize emits a detachments array")
	_check(SaveGameIOScript._DICT_FIELDS.has("campaign_player_forces"),
		"save schema declares campaign_player_forces")
	CampaignPlayerForce.reset()
	_check(not CampaignPlayerForce.has_detachment(fid), "reset clears the registry")
	CampaignPlayerForce.deserialize(payload)
	_check(int(CampaignPlayerForce.get_detachment(fid).get("strength", -1)) == 25,
		"deserialize restores strength")
	CampaignPlayerForce.deserialize({"detachments": [
		{"id": "bad_state", "state": "bogus"},
		{"id": "bad_negative", "state": "active", "strength": -5},
		{"id": "bad_node", "state": "active", "node_id": "node_missing", "strength": 5},
	]})
	_check(not CampaignPlayerForce.has_detachment("bad_state"), "unknown state row skipped")
	_check(not CampaignPlayerForce.has_detachment("bad_negative"), "negative row skipped")
	_check(not CampaignPlayerForce.has_detachment("bad_node"), "dangling node row skipped")
	_check(CampaignPlayerForce.validate().is_empty(), "deserialized registry validates clean")


func _test_defence_held() -> void:
	var ctx := _setup_assault("held", Vector2i(6, 6), 30, 40)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	var garrison_id := str(ctx.get("garrison_id", ""))
	var result := CampaignBaseDefense.process_assault_turn(8)
	var outcomes: Array = result.get("auto_resolved", [])
	_check(outcomes.size() == 1, "one assault auto-resolved")
	if outcomes.size() == 1:
		_check(str((outcomes[0] as Dictionary).get("outcome", "")) == "player_force_defense_held",
			"player force decides the defence (held)")
	_check(CampaignBattle.get_state(battle_id) == CampaignBattle.BattleState.RESOLVED,
		"battle is RESOLVED without tactical play")
	_check(CampaignBaseDefense.get_assault(battle_id).is_empty(), "assault record cleared")
	_check(CampaignBattle.get_session_ref(battle_id) == "", "session reference cleared")
	_check(CampaignBase.get_state(base_id) == CampaignBase.BaseState.ACTIVE,
		"base survives a held defence")
	_check(str(CampaignBase.get_base(base_id).get("controller", "")) == "federation",
		"controller untouched")
	_check(CampaignForce.get_state(attacker_id) == CampaignForce.ForceState.DESTROYED,
		"attacker is destroyed when its strength reaches zero")
	var garrison := CampaignPlayerForce.get_detachment(garrison_id)
	_check(int(garrison.get("strength", -1)) > 0, "winning garrison keeps survivors")
	_check(int(garrison.get("strength", 999)) < 40, "winning garrison took casualties")
	var again := CampaignBaseDefense.process_assault_turn(9)
	_check((again.get("auto_resolved", []) as Array).is_empty(), "repeat turn changes nothing")


func _test_defence_lost() -> void:
	var ctx := _setup_assault("lost", Vector2i(7, 7), 60, 10)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var attacker_id := str(ctx.get("attacker_id", ""))
	var garrison_id := str(ctx.get("garrison_id", ""))
	var result := CampaignBaseDefense.process_assault_turn(8)
	var outcomes: Array = result.get("auto_resolved", [])
	_check(outcomes.size() == 1, "one assault auto-resolved (lost case)")
	if outcomes.size() == 1:
		_check(str((outcomes[0] as Dictionary).get("outcome", "")) == "player_force_base_lost",
			"player force loses the strength comparison")
	_check(CampaignBattle.get_state(battle_id) == CampaignBattle.BattleState.RESOLVED,
		"lost defence still resolves the battle")
	_check(CampaignBase.get_state(base_id) == CampaignBase.BaseState.DISABLED,
		"losing the auto-battle disables the base")
	_check(str(CampaignBase.get_base(base_id).get("controller", "")) == "federation",
		"base controller is preserved on a loss")
	_check(CampaignPlayerForce.get_state(garrison_id) == CampaignPlayerForce.ForceState.DISABLED,
		"wiped garrison is disabled, not deleted")
	_check(int(CampaignForce.get_force(attacker_id).get("strength", -1)) < 60,
		"attacker took casualties in the auto-battle")


func _test_no_player_force_legacy_path() -> void:
	var ctx := _setup_assault("legacy", Vector2i(8, 8), 30, 0)
	var battle_id := str(ctx.get("battle_id", ""))
	var base_id := str(ctx.get("base_id", ""))
	var result := CampaignBaseDefense.process_assault_turn(8)
	var outcomes: Array = result.get("auto_resolved", [])
	_check(outcomes.size() == 1, "legacy path still auto-resolves")
	if outcomes.size() == 1:
		_check(str((outcomes[0] as Dictionary).get("outcome", "")) == "attacker_success",
			"no player force keeps the existing Option D outcome")
	_check(CampaignBase.get_state(base_id) == CampaignBase.BaseState.DISABLED,
		"legacy path disables the base as before")
	_check(CampaignBattle.get_state(battle_id) == CampaignBattle.BattleState.RESOLVED,
		"legacy path resolves the battle")


func _test_run_start_seed() -> void:
	_reset_world()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(9, 9), "start")
	var seeded := RunStartSystem.seed_player_garrison(node_id)
	_check(seeded == CampaignPlayerForce.START_GARRISON_ID, "run start seeds the home garrison")
	_check(CampaignPlayerForce.get_active_at_node(node_id) == [CampaignPlayerForce.START_GARRISON_ID],
		"seeded garrison sits on the start node")
	_check(int(CampaignPlayerForce.get_detachment(seeded).get("strength", -1))
		== CampaignPlayerForce.START_GARRISON_STRENGTH, "seeded garrison uses the provisional strength")
	_check(RunStartSystem.seed_player_garrison(node_id) == CampaignPlayerForce.START_GARRISON_ID,
		"seeding twice is idempotent")
	_check(CampaignPlayerForce.get_detachments().size() == 1, "seeding never duplicates")
	_check(RunStartSystem.seed_player_garrison("node_missing") == "",
		"seeding an unknown node is refused")


func _test_global_reset() -> void:
	_reset_world()
	var node_id := CampaignNodeRegistry.register_node(1, Vector2i(10, 10), "city")
	CampaignPlayerForce.register_detachment("player_force_reset", node_id, "", 1, 12)
	GlobalData.reset_run_data()
	_check(CampaignPlayerForce.get_detachments().is_empty(),
		"reset_run_data clears player detachments")
