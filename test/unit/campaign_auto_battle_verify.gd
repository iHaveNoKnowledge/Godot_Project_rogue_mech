extends Node
## ---------------------------------------------------------------------------
## AUTO-BATTLE FORMULA & TUNED BALANCE VERIFY — Phase C8-D.
##
## Covers:
##   - Pure resolver determinism and outcome classes (pure math, no RNG)
##   - Tuned production constants (ratio, rounds, garrison, raise strength)
##   - Proportional unit losses including wipe-outs
##   - Real playthrough: the seeded garrison is now bound to the player base,
##     so a hostile push is decided by the player force instead of falling
##     through to the attacker-by-default path
## ---------------------------------------------------------------------------

const SCENARIO_ID := "frontier_skirmish"

var _checks := 0
var _fails := 0
var _save_backup := ""
var _had_save := false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C8D_AUTO_BATTLE OK: %s" % message)
	else:
		_fails += 1
		printerr("C8D_AUTO_BATTLE FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN AUTO-BATTLE FORMULA & BALANCE VERIFY (Phase C8-D) ---")
	print("======================================================================")
	_had_save = FileAccess.file_exists(GlobalData.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	_test_formula()
	_test_unit_loss()
	_test_tuned_constants()
	_test_real_playthrough()

	if _had_save:
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()

	print("----------------------------------------------------------------------")
	print("PHASE C8-D SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")
	if _fails == 0:
		print("ALL AUTO-BATTLE BALANCE (C8-D) CHECKS PASSED!")
	else:
		printerr("C8-D AUTO-BATTLE VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _test_formula() -> void:
	var equal := CampaignAutoBattle.simulate(20, 20)
	_check(str(equal.get("winner", "")) == "stalemate",
		"equal forces deadlock after the round cap (defender keeps ground)")
	_check(int(equal.get("defender_remaining", -1)) == int(equal.get("attacker_remaining", -2)),
		"deadlock leaves equal strength")
	_check(int(equal.get("rounds", 0)) == CampaignAutoBattle.MAX_ROUNDS,
		"deadlock runs to the round cap")

	var stronger_defender := CampaignAutoBattle.simulate(32, 30)
	_check(str(stronger_defender.get("winner", "")) == "defender",
		"32 holds against a 30 push")
	_check(int(stronger_defender.get("defender_remaining", 0)) > 0,
		"holding defender keeps survivors")

	var overpowered := CampaignAutoBattle.simulate(20, 30)
	_check(str(overpowered.get("winner", "")) == "attacker",
		"20 loses to a 30 push")
	_check(int(overpowered.get("attacker_remaining", -1)) > 0,
		"winning attacker keeps strength")

	var wipe := CampaignAutoBattle.simulate(40, 15)
	_check(str(wipe.get("winner", "")) == "defender", "40 wipes a 15 force")
	_check(int(wipe.get("attacker_remaining", -1)) == 0, "wiped force reaches zero")
	_check(int(wipe.get("rounds", 0)) <= CampaignAutoBattle.MAX_ROUNDS,
		"wipe-out respects the round cap")

	var first := CampaignAutoBattle.simulate(27, 31)
	var second := CampaignAutoBattle.simulate(27, 31)
	_check(first == second, "identical inputs produce identical receipts (no RNG)")
	_check(int(CampaignAutoBattle.simulate(0, 10).get("attacker_remaining", -1)) == 10,
		"zero-strength defender loses nothing for the attacker")
	_check(CampaignAutoBattle.simulate(0, 0).get("rounds", -1) == 0,
		"no rounds run without combatants")


func _test_unit_loss() -> void:
	_check(CampaignAutoBattle.unit_loss(4, 40, 10) == 1, "10/40 of 4 units is 1 unit")
	_check(CampaignAutoBattle.unit_loss(4, 40, 40) == 4, "total loss removes every unit")
	_check(CampaignAutoBattle.unit_loss(4, 40, 0) == 0, "no loss removes no units")
	_check(CampaignAutoBattle.unit_loss(3, 30, 99) == 3, "over-loss cannot exceed the roster")
	_check(CampaignAutoBattle.unit_loss(0, 10, 5) == 0, "unitless force loses nothing")


func _test_tuned_constants() -> void:
	_check(is_equal_approx(CampaignAutoBattle.ATTRITION_RATIO, 0.2),
		"attrition ratio is tuned to 0.20 (measured in the playthrough sim)")
	_check(CampaignAutoBattle.MAX_ROUNDS == 5, "round cap is tuned to 5")
	_check(CampaignPlayerForce.START_GARRISON_STRENGTH == 20,
		"starting garrison is tuned to 20")
	_check(CampaignPlayerForce.START_GARRISON_UNITS == 2,
		"starting garrison carries 2 units")
	_check(CampaignPlayerForceAction.RAISE_STRENGTH == 12,
		"one raised detachment adds 12 strength")
	_check(CampaignPlayerForce.START_GARRISON_STRENGTH
		+ CampaignPlayerForceAction.RAISE_STRENGTH > 30,
		"garrison + one raise exceeds the scenario's 30-strength push")


func _test_real_playthrough() -> void:
	GlobalData.reset_run_data()
	var start := RunStartSystem.start_campaign_scenario(SCENARIO_ID)
	_check(bool(start.get("ok", false)), "canonical scenario starts for the balance check")
	var player_base := {}
	for base in CampaignBase.get_bases():
		if str(base.get("controller", "")) == FactionSystem.get_player_faction() \
				and int(base.get("state", -1)) != CampaignBase.BaseState.DESTROYED:
			player_base = base
			break
	_check(not player_base.is_empty(), "scenario placed a player-owned base")
	if player_base.is_empty():
		return
	var base_id := str(player_base.get("id", ""))
	var node_id := str(player_base.get("node_id", ""))
	var garrison := CampaignPlayerForce.get_detachment(CampaignPlayerForce.START_GARRISON_ID)
	_check(not garrison.is_empty(), "home garrison exists after start")
	_check(str(garrison.get("node_id", "")) == node_id,
		"garrison is seeded at the player base node (was the start node before C8-D)")
	_check(str(garrison.get("base_id", "")) == base_id, "garrison is bound to the player base")
	_check(int(garrison.get("strength", -1)) == CampaignPlayerForce.START_GARRISON_STRENGTH,
		"garrison uses the tuned starting strength")

	var attacker := CampaignForce.register_force(
		"force_c8d_push", "PATROL", "zeon", node_id, "", 3, 30)
	_check(attacker != "", "hostile push registers at the base node")

	var last_outcomes: Array = []
	for turn in range(1, 6):
		var receipt := CampaignTurnExecutive.advance_campaign_turn(
			"c8d_playthrough", {"spy_roll": false, "enemy_base_points": 0.0, "board_tiles": {}})
		var assault: Dictionary = receipt.get("strategic_assault", {})
		var resolved: Array = assault.get("auto_resolved", [])
		if not resolved.is_empty():
			last_outcomes = resolved

	_check(not last_outcomes.is_empty(), "the assault resolves inside the playthrough window")
	if not last_outcomes.is_empty():
		var outcome := str((last_outcomes[0] as Dictionary).get("outcome", ""))
		_check(outcome == "player_force_base_lost",
			"an unassisted 20 garrison loses to the 30 push through the player-force path")
		_check(outcome != "attacker_success",
			"the attacker-by-default path no longer decides the outcome")
	_check(int(CampaignForce.get_force(attacker).get("strength", -1)) < 30,
		"the attacker takes attrition from the garrison")
	_check(CampaignBase.get_state(base_id) == CampaignBase.BaseState.DISABLED,
		"the lost defence disables the base")
	_check(str(CampaignBase.get_base(base_id).get("controller", "")) == "federation",
		"controller is preserved on a lost defence")
