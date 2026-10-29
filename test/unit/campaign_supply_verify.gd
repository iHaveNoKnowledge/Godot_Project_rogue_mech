extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN SUPPLY LEDGER VERIFICATION — Phase C6-A.
##
## Tests the new campaign resource authority:
##   - Starting pool and SUPPLY cap / ratio
##   - DATA stays with CurrencyManager.data_cores (no duplicate pool)
##   - Add clamping, unknown-key and non-positive rejection
##   - Atomic spend (insufficient leaves the pool untouched)
##   - Supply crisis flag at 0 (explicitly not a game-over state)
##   - Day-boundary income tick
##   - Isolation from CurrencyManager and CampaignForce
##   - Serialization round-trip, malformed payload fallback, reset
##   - CampaignTurnExecutive phase wiring (PHASE_CAMPAIGN_SUPPLY)
##   - GlobalData.reset_run_data() lifecycle reset
## ---------------------------------------------------------------------------

const CampaignSupplyScript = preload("res://scripts/systems/campaign_supply.gd")
const CampaignTurnExecutiveScript = preload("res://scripts/systems/campaign_turn_executive.gd")
const SaveGameIOScript = preload("res://scripts/systems/save_game_io.gd")

var _checks := 0
var _fails := 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("C6A_SUPPLY OK: %s" % message)
	else:
		_fails += 1
		printerr("C6A_SUPPLY FAIL: %s" % message)


func _ready() -> void:
	print("======================================================================")
	print("--- BEGIN CAMPAIGN SUPPLY LEDGER VERIFY (Phase C6-A) ---")
	print("======================================================================")

	_test_starting_pool()
	_test_add_and_cap()
	_test_rejections()
	_test_atomic_spend()
	_test_supply_crisis()
	_test_turn_income()
	_test_isolation()
	_test_serialization()
	_test_reset()
	_test_turn_executive_phase()
	_test_global_data_reset_integration()

	print("----------------------------------------------------------------------")
	print("PHASE C6-A SUMMARY: Passed: %d, Failed: %d" % [_checks - _fails, _fails])
	print("----------------------------------------------------------------------")

	if _fails == 0:
		print("ALL CAMPAIGN SUPPLY LEDGER (C6-A) CHECKS PASSED!")
	else:
		printerr("C6-A CAMPAIGN SUPPLY VERIFICATION FAILED WITH %d ERRORS" % _fails)

	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _test_starting_pool() -> void:
	CampaignSupplyScript.reset()
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"starting SUPPLY is 42")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_MATERIALS) == 0,
		"starting MATERIALS is 0")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SALVAGE) == 0,
		"starting SALVAGE is 0")
	_check(CampaignSupplyScript.SUPPLY_CAP == 100, "SUPPLY cap is 100")
	_check(is_equal_approx(CampaignSupplyScript.get_supply_ratio(), 0.42),
		"supply ratio is 0.42")
	_check(not CampaignSupplyScript.is_supply_crisis(), "no crisis at starting pool")
	_check(CampaignSupplyScript.RESOURCE_KEYS.size() == 3,
		"exactly three owned resources (DATA stays with CurrencyManager)")
	_check(not CampaignSupplyScript.is_valid_key("DATA"),
		"DATA is not duplicated in the campaign ledger")


func _test_add_and_cap() -> void:
	CampaignSupplyScript.reset()
	var receipt := CampaignSupplyScript.add(CampaignSupplyScript.KEY_SUPPLY, 10)
	_check(bool(receipt.get("ok", false)), "add SUPPLY succeeds")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 52,
		"SUPPLY is 52 after +10")
	CampaignSupplyScript.add(CampaignSupplyScript.KEY_SUPPLY, 500)
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 100,
		"SUPPLY clamps at cap 100")
	var mat_receipt := CampaignSupplyScript.add(CampaignSupplyScript.KEY_MATERIALS, 30)
	_check(bool(mat_receipt.get("ok", false)), "MATERIALS add accepted")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_MATERIALS) == 30,
		"MATERIALS accumulates without a cap")
	_check(CampaignSupplyScript.get_cap(CampaignSupplyScript.KEY_MATERIALS) == 0,
		"MATERIALS reports uncapped (0)")


func _test_rejections() -> void:
	CampaignSupplyScript.reset()
	var unknown := CampaignSupplyScript.add("CREDITS", 5)
	_check(not bool(unknown.get("ok", true)), "unknown resource key rejected")
	_check(str(unknown.get("reason", "")) == "unknown_resource",
		"unknown key reason is unknown_resource")
	var zero := CampaignSupplyScript.add(CampaignSupplyScript.KEY_SUPPLY, 0)
	_check(not bool(zero.get("ok", true)), "zero amount rejected")
	var negative := CampaignSupplyScript.add(CampaignSupplyScript.KEY_SUPPLY, -5)
	_check(not bool(negative.get("ok", true)), "negative amount rejected")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"rejections mutate nothing")
	_check(not CampaignSupplyScript.is_valid_key("CREDITS"),
		"CREDITS is not a campaign resource")
	_check(not CampaignSupplyScript.set_amount("NOPE", 1), "set_amount rejects unknown key")


func _test_atomic_spend() -> void:
	CampaignSupplyScript.reset()
	var ok_spend := CampaignSupplyScript.try_spend(CampaignSupplyScript.KEY_SUPPLY, 12)
	_check(bool(ok_spend.get("ok", false)), "affordable spend succeeds")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 30,
		"SUPPLY reduced to 30")
	var poor := CampaignSupplyScript.try_spend(CampaignSupplyScript.KEY_SUPPLY, 999)
	_check(not bool(poor.get("ok", true)), "unaffordable spend rejected")
	_check(str(poor.get("reason", "")) == "insufficient_supply",
		"insufficient reason is insufficient_supply")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 30,
		"rejected spend leaves the pool untouched")
	_check(CampaignSupplyScript.can_afford(CampaignSupplyScript.KEY_SUPPLY, 30),
		"can_afford true at exact balance")
	_check(not CampaignSupplyScript.can_afford(CampaignSupplyScript.KEY_SUPPLY, 31),
		"can_afford false above balance")
	var zero := CampaignSupplyScript.try_spend(CampaignSupplyScript.KEY_SUPPLY, 0)
	_check(not bool(zero.get("ok", true)), "zero spend rejected")


func _test_supply_crisis() -> void:
	CampaignSupplyScript.reset()
	CampaignSupplyScript.try_spend(CampaignSupplyScript.KEY_SUPPLY, 42)
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 0,
		"SUPPLY can reach 0")
	_check(CampaignSupplyScript.is_supply_crisis(), "0 SUPPLY reports a crisis")
	_check(is_equal_approx(CampaignSupplyScript.get_supply_ratio(), 0.0),
		"ratio is 0.0 during crisis")


func _test_turn_income() -> void:
	CampaignSupplyScript.reset()
	var receipt := CampaignSupplyScript.process_turn_income()
	_check(bool(receipt.get("ok", false)), "turn income succeeds")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 46,
		"SUPPLY is 46 after one income tick")
	_check(int(receipt.get("supply_before", -1)) == 42, "receipt records supply_before")
	_check(int(receipt.get("supply_after", -1)) == 46, "receipt records supply_after")
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 99)
	CampaignSupplyScript.process_turn_income()
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 100,
		"income clamps at cap")
	var bad := CampaignSupplyScript.process_turn_income(0)
	_check(not bool(bad.get("ok", true)), "zero income rejected")


func _test_isolation() -> void:
	CampaignSupplyScript.reset()
	var credits_before: int = int(GlobalData.currency.credits)
	var scrap_before: int = int(GlobalData.currency.scrap)
	var data_before: int = int(GlobalData.currency.data_cores)
	CampaignSupplyScript.add(CampaignSupplyScript.KEY_SUPPLY, 5)
	CampaignSupplyScript.try_spend(CampaignSupplyScript.KEY_SUPPLY, 3)
	_check(int(GlobalData.currency.credits) == credits_before,
		"CurrencyManager credits untouched by campaign supply")
	_check(int(GlobalData.currency.scrap) == scrap_before,
		"CurrencyManager scrap untouched by campaign supply")
	_check(int(GlobalData.currency.data_cores) == data_before,
		"CurrencyManager data_cores untouched (DATA authority unchanged)")
	_check(not CampaignSupplyScript.get_amounts().has("credits"),
		"ledger exposes no currency keys")
	CampaignForce.clear()
	var force_id := CampaignForce.make_force_id(1, "supply_test")
	CampaignForce.register_force(force_id, "PATROL", "zeon", "", "", 3, 10)
	var force := CampaignForce.get_force(force_id)
	_check(not force.has("supply"), "CampaignForce still owns no supply field")
	_check(not force.has("supply_status"), "CampaignForce still owns no supply_status")
	CampaignForce.clear()


func _test_serialization() -> void:
	CampaignSupplyScript.reset()
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 77)
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_MATERIALS, 12)
	var payload := CampaignSupplyScript.serialize()
	_check(payload.has("amounts"), "serialize produces an amounts dictionary")
	_check(SaveGameIOScript._DICT_FIELDS.has("campaign_supply"),
		"save schema declares campaign_supply as a dict field")
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 0)
	CampaignSupplyScript.deserialize(payload)
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 77,
		"deserialize restores SUPPLY")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_MATERIALS) == 12,
		"deserialize restores MATERIALS")
	CampaignSupplyScript.deserialize({})
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"missing payload restores the starting pool")
	CampaignSupplyScript.deserialize({"amounts": "corrupt"})
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"malformed payload restores the starting pool")
	CampaignSupplyScript.deserialize({"amounts": {"SUPPLY": 99999, "MATERIALS": -4}})
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 100,
		"deserialize clamps over-cap values")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_MATERIALS) == 0,
		"deserialize floors negative values at 0")


func _test_reset() -> void:
	CampaignSupplyScript.reset()
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_MATERIALS, 40)
	CampaignSupplyScript.reset()
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_MATERIALS) == 0,
		"reset clears MATERIALS")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"reset restores starting SUPPLY")


func _test_turn_executive_phase() -> void:
	CampaignSupplyScript.reset()
	CampaignTurnExecutiveScript.reset()
	var receipt := CampaignTurnExecutiveScript.advance_campaign_turn(
		"c6a_supply_test",
		{"spy_roll": false, "enemy_base_points": 0.0, "board_tiles": {}}
	)
	_check(bool(receipt.get("ok", false)), "campaign turn advances")
	var phases: Array = receipt.get("phases", [])
	_check(phases.has(CampaignTurnExecutiveScript.PHASE_CAMPAIGN_SUPPLY),
		"PHASE_CAMPAIGN_SUPPLY executes on a day boundary")
	var index_economy := phases.find(CampaignTurnExecutiveScript.PHASE_FACTION_ECONOMY)
	var index_supply := phases.find(CampaignTurnExecutiveScript.PHASE_CAMPAIGN_SUPPLY)
	_check(index_economy >= 0 and index_supply == index_economy + 1,
		"supply phase follows the faction economy phase")
	var supply_receipt = receipt.get("campaign_supply", {})
	_check(supply_receipt is Dictionary and bool((supply_receipt as Dictionary).get("ok", false)),
		"receipt carries the supply income result")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 46,
		"turn income applied exactly once (+4)")
	_check(CampaignTurnExecutiveScript.get_phase_call_count(
		CampaignTurnExecutiveScript.PHASE_CAMPAIGN_SUPPLY) == 1,
		"supply phase ran exactly once")
	var counter_only := CampaignTurnExecutiveScript.advance_campaign_turn(
		"c6a_counter_only", {"day_boundary": false})
	_check(not (counter_only.get("phases", []) as Array).has(
		CampaignTurnExecutiveScript.PHASE_CAMPAIGN_SUPPLY),
		"counter-only turn skips supply income")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 46,
		"counter-only turn changes no supply")
	CampaignTurnExecutiveScript.reset()


func _test_global_data_reset_integration() -> void:
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SALVAGE, 25)
	GlobalData.reset_run_data()
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SALVAGE) == 0,
		"reset_run_data clears SALVAGE")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"reset_run_data restores starting SUPPLY")
