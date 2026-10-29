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
	_test_repair_gate()
	_test_base_upkeep()
	_test_reinforcement_gate()
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
	CampaignBase.clear()
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


## C6-B: mecha recovery (professional rebuild) is a campaign-resource operation.
func _test_repair_gate() -> void:
	CampaignSupplyScript.reset()
	GlobalData.weapons.reset()
	GlobalData.currency.credits = 5000
	GlobalData.weapons.part_damage["leg_left"] = 0.5
	var credits_before: int = int(GlobalData.currency.credits)
	var supply_cost := RepairSystem.get_professional_repair_supply_cost("leg_left")
	_check(supply_cost >= 1, "professional repair quotes SUPPLY (%d)" % supply_cost)
	_check(RepairSystem.get_professional_repair_supply_cost("not_a_slot") == 0,
		"unknown slot quotes no SUPPLY")
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 0)
	_check(not RepairSystem.apply_professional_repair("leg_left"),
		"professional repair fails with no SUPPLY")
	_check(int(GlobalData.currency.credits) == credits_before,
		"failed repair spends no credits")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("leg_left", 0.0)), 0.5),
		"failed repair leaves damage untouched")
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, supply_cost)
	_check(RepairSystem.apply_professional_repair("leg_left"),
		"professional repair succeeds with SUPPLY")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 0,
		"professional repair consumes SUPPLY")
	_check(int(GlobalData.currency.credits) < credits_before,
		"successful repair still charges credits")
	GlobalData.weapons.reset()
	GlobalData.currency.credits = 110


## C6-B: base upkeep is charged per live player base on the turn boundary.
func _test_base_upkeep() -> void:
	CampaignSupplyScript.reset()
	CampaignBase.clear()
	CampaignTurnExecutiveScript.reset()
	var faction := FactionSystem.get_player_faction()
	var base_id := CampaignBase.register_base("base_c6b_upkeep_a", "", "OUTPOST", faction)
	_check(base_id != "", "player outpost registered for upkeep test")
	var upkeep := CampaignBase.get_player_upkeep()
	_check(int(upkeep.get("bases", -1)) == 1, "one live player base counted")
	_check(int(upkeep.get("cost", -1)) == CampaignBase.SUPPLY_UPKEEP_PER_BASE,
		"upkeep uses the per-base rate")
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 10)
	var receipt := CampaignTurnExecutiveScript.advance_campaign_turn(
		"c6b_upkeep",
		{"spy_roll": false, "enemy_base_points": 0.0, "board_tiles": {}}
	)
	var expected := 10 + CampaignSupplyScript.SUPPLY_INCOME_PER_TURN \
		- CampaignBase.SUPPLY_UPKEEP_PER_BASE
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == expected,
		"turn nets income minus base upkeep (%d)" % expected)
	var supply_receipt: Dictionary = receipt.get("campaign_supply", {})
	var upkeep_receipt: Dictionary = supply_receipt.get("upkeep", {})
	_check(bool(upkeep_receipt.get("ok", false)), "upkeep paid in full when affordable")
	_check(int(upkeep_receipt.get("paid", -1)) == CampaignBase.SUPPLY_UPKEEP_PER_BASE,
		"receipt records the paid upkeep")
	_check(int(supply_receipt.get("supply_after_upkeep", -1)) == expected,
		"receipt records the post-upkeep pool")
	# Destroyed bases stop costing upkeep.
	CampaignBase.set_state(base_id, CampaignBase.BaseState.DESTROYED)
	_check(int(CampaignBase.get_player_upkeep().get("cost", -1)) == 0,
		"destroyed base costs no upkeep")
	# Shortfall: three live bases (6 SUPPLY) against an empty pool + 4 income.
	CampaignBase.clear()
	for i in 3:
		CampaignBase.register_base("base_c6b_upkeep_%d" % i, "", "OUTPOST", faction)
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 0)
	var short_receipt := CampaignTurnExecutiveScript.advance_campaign_turn(
		"c6b_upkeep_shortfall",
		{"spy_roll": false, "enemy_base_points": 0.0, "board_tiles": {}}
	)
	var short_upkeep: Dictionary = (short_receipt.get("campaign_supply", {}) as Dictionary).get("upkeep", {})
	_check(not bool(short_upkeep.get("ok", true)), "unaffordable upkeep reports a shortfall")
	_check(int(short_upkeep.get("shortfall", 0)) == 2, "shortfall is reported exactly")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY)
		== CampaignSupplyScript.SUPPLY_INCOME_PER_TURN,
		"failed upkeep leaves the pool untouched (crisis, not game over)")
	CampaignBase.clear()
	CampaignTurnExecutiveScript.reset()
	CampaignSupplyScript.reset()


## C6-B: bringing an additional unit into the field costs campaign SUPPLY.
func _test_reinforcement_gate() -> void:
	CampaignSupplyScript.reset()
	GlobalData.hangar.fleet_roster.clear()
	GlobalData.hangar.fleet_roster.append({
		"template_id": "c6b_test_unit",
		"name": "C6B Test Unit",
		"hp": 50.0,
		"max_hp": 50.0,
		"destroyed": false,
		"fielded": false,
	})
	var cost := FleetSystem.get_reinforcement_supply_cost()
	_check(cost > 0, "reinforcement quotes SUPPLY (%d)" % cost)
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, 0)
	_check(not FleetSystem.set_unit_fielded("c6b_test_unit", true),
		"fielding fails without SUPPLY")
	_check(not bool(FleetSystem.get_fleet_unit("c6b_test_unit").get("fielded", false)),
		"refused unit stays standing down")
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SUPPLY, cost)
	_check(FleetSystem.set_unit_fielded("c6b_test_unit", true),
		"fielding succeeds with SUPPLY")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 0,
		"fielding consumes SUPPLY")
	_check(FleetSystem.set_unit_fielded("c6b_test_unit", true),
		"re-confirming an already fielded unit is free")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 0,
		"re-confirm charges nothing")
	_check(FleetSystem.set_unit_fielded("c6b_test_unit", false),
		"standing a unit down is always free")
	_check(not bool(FleetSystem.get_fleet_unit("c6b_test_unit").get("fielded", true)),
		"unit is standing down after the toggle")
	_check(not FleetSystem.set_unit_fielded("c6b_missing_unit", true),
		"unknown unit is refused")
	GlobalData.hangar.fleet_roster.clear()


func _test_global_data_reset_integration() -> void:
	CampaignSupplyScript.set_amount(CampaignSupplyScript.KEY_SALVAGE, 25)
	GlobalData.reset_run_data()
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SALVAGE) == 0,
		"reset_run_data clears SALVAGE")
	_check(CampaignSupplyScript.get_amount(CampaignSupplyScript.KEY_SUPPLY) == 42,
		"reset_run_data restores starting SUPPLY")
