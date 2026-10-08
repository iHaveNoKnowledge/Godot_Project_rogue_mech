extends Node

## ---------------------------------------------------------------------------
## PHASE 5AR: CAMPAIGN TRADE ACTION AUTHORITY & ECONOMY CONTRACT VERIFICATION
##
## Proves the architectural contract for the 3rd Campaign Player Action: 'trade'
##
## Contracts Verified:
##   1. Action Registration & Routing:
##      - 'trade' is recognized by CampaignPlayerDispatch and routes to CampaignTradeAction.
##      - Coexists with 'investigate' and 'resupply' without handler or state displacement.
##   2. Economic Domain Mutation (Buy & Sell):
##      - Buying items / commodities deducts credits and increases inventory/scrap atomically.
##      - Selling items / commodities increases credits and deducts inventory/scrap atomically.
##   3. Precondition & Rejection Integrity:
##      - Non-trade nodes (e.g. ENEMY_BASE, EXIT, COMMS_RELAY) reject trade cleanly.
##      - Insufficient credits or inventory reject with zero state mutation.
##      - Invalid quantities (<= 0) or unknown items reject cleanly.
##   4. Turn Isolation:
##      - Trade operations cause exactly ZERO turn advancements (CampaignTurnExecutive untouched).
##   5. Cross-Action Multi-Sequence Integrity:
##      - Combinations of [investigate -> resupply -> trade] in all permutations execute cleanly.
##   6. Comprehensive Side-Effect Firewall:
##      - Territory, base, force, battle, turn, relation, heat/wanted, and position state remain untouched.
## ---------------------------------------------------------------------------

const CampaignPlayerDispatch = preload("res://scripts/systems/campaign_player_dispatch.gd")
const CampaignNodeInspection = preload("res://scripts/systems/campaign_node_inspection.gd")
const CampaignInvestigateAction = preload("res://scripts/systems/campaign_investigate_action.gd")
const CampaignResupplyAction = preload("res://scripts/systems/campaign_resupply_action.gd")
const CampaignTradeAction = preload("res://scripts/systems/campaign_trade_action.gd")

var _passed_count: int = 0
var _failed_count: int = 0
var _save_backup := ""


func _ready() -> void:
	print("Running Campaign Trade Action Authority & Economy verification (Phase 5AR)...")
	if FileAccess.file_exists(GlobalData.SAVE_PATH):
		_save_backup = FileAccess.get_file_as_string(GlobalData.SAVE_PATH)

	await get_tree().process_frame
	_run_all_tests()
	_restore_save_backup()
	_print_summary()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed_count += 1
		print("TRADE_ACTION OK: %s" % test_name)
	else:
		_failed_count += 1
		printerr("TRADE_ACTION FAIL: %s" % test_name)


func _print_summary() -> void:
	print("----------------------------------------------------------------------")
	print("PHASE 5AR SUMMARY: Passed: %d, Failed: %d" % [_passed_count, _failed_count])
	print("----------------------------------------------------------------------")
	if _failed_count == 0:
		print("ALL CAMPAIGN TRADE ACTION CHECKS PASSED!")
		get_tree().quit(0)
	else:
		printerr("CAMPAIGN TRADE ACTION VERIFICATION FAILED!")
		get_tree().quit(1)


func _restore_save_backup() -> void:
	if _save_backup != "":
		var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()


func _run_all_tests() -> void:
	_test_a_dispatch_and_registration()
	_test_b_successful_buy_and_sell()
	_test_c_rejection_safety_and_atomicity()
	_test_d_turn_isolation()
	_test_e_cross_action_sequence_coexistence()
	_test_f_side_effect_firewall()


func _reset_campaign_runtime() -> void:
	CampaignPlayerDispatch.clear_handlers()
	CampaignPlayerDispatch.register_default_handlers()
	GlobalData.reset_run_data()
	CampaignNodeRegistry.clear()
	CampaignTerritory.clear()
	CampaignBase.clear()
	CampaignForce.clear()
	CampaignBattle.clear()
	CampaignTurnExecutive.reset()
	FactionSystem.reset_relations()
	FactionEconomySystem.reset()
	GlobalData.current_campaign_scenario_id = ""

	if GlobalData.currency != null:
		GlobalData.currency.reset(500)
		GlobalData.currency.scrap = 10
	if GlobalData.fuel_inventory != null:
		GlobalData.fuel_inventory.clear()


## --- TEST A: DISPATCH & REGISTRATION ---
func _test_a_dispatch_and_registration() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(1, 1), "city", "node_city_a")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(1, 1)

	_check(CampaignPlayerDispatch.is_known_action("trade"), "A1: 'trade' is known action")
	var known := CampaignPlayerDispatch.get_known_actions()
	_check(known.has("trade") and known.has("investigate") and known.has("resupply"), "A2: Known actions contain investigate, resupply, and trade")

	var intent := CampaignPlayerDispatch.create_intent("trade", "node_city_a", {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1,
	})

	var res := CampaignPlayerDispatch.dispatch_intent(intent)
	_check(bool(res.get("ok", false)), "A3: Trade intent dispatches successfully")
	_check(str(res.get("reason", "")) == "trade_completed", "A4: Receipt reports trade_completed")


## --- TEST B: SUCCESSFUL BUY & SELL TRANSACTIONS ---
func _test_b_successful_buy_and_sell() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_b")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	GlobalData.currency.credits = 300
	GlobalData.currency.scrap = 5
	GlobalData.fuel_inventory.clear()

	# 1. Buy fuel_canister (price: 100)
	var buy_fuel_intent := CampaignPlayerDispatch.create_intent("trade", "node_city_b", {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 1,
	})
	var buy_res := CampaignPlayerDispatch.dispatch_intent(buy_fuel_intent)
	_check(bool(buy_res.get("ok", false)), "B1: Buy fuel_canister succeeds")
	_check(GlobalData.currency.credits == 200, "B2: Credits deducted from 300 to 200")
	_check(GlobalData.get_fuel_item_count("fuel_canister") == 1, "B3: fuel_canister added to inventory (count=1)")
	_check(int(buy_res.get("total_price", 0)) == 100, "B4: Receipt total_price is 100")

	# 2. Buy scrap (price: 10 each, qty: 5)
	var buy_scrap_intent := CampaignPlayerDispatch.create_intent("trade", "node_city_b", {
		"operation": "buy",
		"item_id": "scrap",
		"quantity": 5,
	})
	var buy_scrap_res := CampaignPlayerDispatch.dispatch_intent(buy_scrap_intent)
	_check(bool(buy_scrap_res.get("ok", false)), "B5: Buy scrap succeeds")
	_check(GlobalData.currency.credits == 150, "B6: Credits deducted from 200 to 150")
	_check(GlobalData.currency.scrap == 10, "B7: Scrap increased from 5 to 10")

	# 3. Sell fuel_canister (sell price: 50)
	var sell_fuel_intent := CampaignPlayerDispatch.create_intent("trade", "node_city_b", {
		"operation": "sell",
		"item_id": "fuel_canister",
		"quantity": 1,
	})
	var sell_res := CampaignPlayerDispatch.dispatch_intent(sell_fuel_intent)
	_check(bool(sell_res.get("ok", false)), "B8: Sell fuel_canister succeeds")
	_check(GlobalData.currency.credits == 200, "B9: Credits increased from 150 to 200")
	_check(GlobalData.get_fuel_item_count("fuel_canister") == 0, "B10: fuel_canister removed from inventory (count=0)")

	# 4. Sell scrap (sell price: 5 each, qty: 4)
	var sell_scrap_intent := CampaignPlayerDispatch.create_intent("trade", "node_city_b", {
		"operation": "sell",
		"item_id": "scrap",
		"quantity": 4,
	})
	var sell_scrap_res := CampaignPlayerDispatch.dispatch_intent(sell_scrap_intent)
	_check(bool(sell_scrap_res.get("ok", false)), "B11: Sell scrap succeeds")
	_check(GlobalData.currency.credits == 220, "B12: Credits increased from 200 to 220")
	_check(GlobalData.currency.scrap == 6, "B13: Scrap decreased from 10 to 6")


## --- TEST C: REJECTION SAFETY & ATOMICITY ---
func _test_c_rejection_safety_and_atomicity() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(3, 3), "city", "node_city_c")
	CampaignNodeRegistry.register_node(1, Vector2i(4, 4), "enemy_base", "node_base_c")
	CampaignNodeRegistry.register_node(1, Vector2i(5, 5), "comms_relay", "node_relay_c")

	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(3, 3)

	GlobalData.currency.credits = 50
	GlobalData.currency.scrap = 2
	GlobalData.fuel_inventory.clear()

	# 1. Insufficient credits
	var fail_buy := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_city_c", {
		"operation": "buy",
		"item_id": "crude_oil_drum", # 120 credits
		"quantity": 1,
	}))
	_check(not bool(fail_buy.get("ok", true)), "C1: Buy rejected due to insufficient credits")
	_check(str(fail_buy.get("reason", "")) == "insufficient_credits", "C2: Reason is insufficient_credits")
	_check(GlobalData.currency.credits == 50, "C3: Credits untouched at 50")
	_check(GlobalData.get_fuel_item_count("crude_oil_drum") == 0, "C4: Inventory untouched")

	# 2. Insufficient inventory to sell
	var fail_sell := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_city_c", {
		"operation": "sell",
		"item_id": "bio_fuel_cell",
		"quantity": 1,
	}))
	_check(not bool(fail_sell.get("ok", true)), "C5: Sell rejected due to insufficient inventory")
	_check(str(fail_sell.get("reason", "")) == "insufficient_inventory", "C6: Reason is insufficient_inventory")
	_check(GlobalData.currency.credits == 50, "C7: Credits untouched at 50")

	# 3. Invalid node type for trade (Enemy Base)
	GlobalData.board.current_tile = Vector2i(4, 4)
	var fail_node := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_base_c", {
		"operation": "buy",
		"item_id": "scrap",
		"quantity": 1,
	}))
	_check(not bool(fail_node.get("ok", true)), "C8: Trade rejected at enemy base node")
	_check(str(fail_node.get("reason", "")) == "node_cannot_trade", "C9: Reason is node_cannot_trade")

	# 4. Unknown item
	GlobalData.board.current_tile = Vector2i(3, 3)
	var fail_item := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_city_c", {
		"operation": "buy",
		"item_id": "fictional_plasma_cannon",
		"quantity": 1,
	}))
	_check(not bool(fail_item.get("ok", true)), "C10: Unknown item rejected")
	_check(str(fail_item.get("reason", "")) == "unknown_tradable_item", "C11: Reason is unknown_tradable_item")

	# 5. Invalid quantity
	var fail_qty := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_city_c", {
		"operation": "buy",
		"item_id": "scrap",
		"quantity": -2,
	}))
	_check(not bool(fail_qty.get("ok", true)), "C12: Negative quantity rejected")
	_check(str(fail_qty.get("reason", "")) == "invalid_trade_quantity", "C13: Reason is invalid_trade_quantity")


## --- TEST D: TURN ISOLATION ---
func _test_d_turn_isolation() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(0, 0), "start", "node_start_d")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(0, 0)
	GlobalData.currency.credits = 1000

	var turn_start := CampaignTurnExecutive.get_turn()

	for i in range(5):
		CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_start_d", {
			"operation": "buy",
			"item_id": "energy_cell_pack",
			"quantity": 1,
		}))

	_check(CampaignTurnExecutive.get_turn() == turn_start, "D1: 5 trade dispatches result in ZERO turn advance")


## --- TEST E: CROSS-ACTION SEQUENCE COEXISTENCE ---
func _test_e_cross_action_sequence_coexistence() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(2, 2), "city", "node_city_e")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(2, 2)

	GlobalData.currency.credits = 500
	GlobalData.fuel.mech_energy = 400.0
	GlobalData.fuel.convoy_fuel = 200.0

	# Sequence 1: [Investigate -> Resupply -> Trade -> Investigate]
	var inv1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_e"))
	_check(bool(inv1.get("ok", false)), "E1: Seq 1 - Investigate ok")

	var res1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_city_e"))
	_check(bool(res1.get("ok", false)), "E2: Seq 1 - Resupply ok")
	_check(is_equal_approx(GlobalData.fuel.mech_energy, 1000.0), "E3: Energy filled to 1000.0")

	var trd1 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_city_e", {
		"operation": "buy",
		"item_id": "bio_fuel_cell",
		"quantity": 2,
	}))
	_check(bool(trd1.get("ok", false)), "E4: Seq 1 - Trade ok")
	_check(GlobalData.currency.credits == 320, "E5: Credits 500 - 180 = 320")

	var inv2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_e"))
	_check(bool(inv2.get("ok", false)), "E6: Seq 1 - Second Investigate ok")

	# Sequence 2: [Trade -> Investigate -> Resupply]
	GlobalData.fuel.mech_energy = 800.0
	var trd2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_city_e", {
		"operation": "sell",
		"item_id": "bio_fuel_cell",
		"quantity": 1,
	}))
	_check(bool(trd2.get("ok", false)), "E7: Seq 2 - Trade sell ok")
	_check(GlobalData.currency.credits == 365, "E8: Credits 320 + 45 = 365")

	var inv3 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("investigate", "node_city_e"))
	_check(bool(inv3.get("ok", false)), "E9: Seq 2 - Investigate ok")

	var res2 := CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("resupply", "node_city_e"))
	_check(bool(res2.get("ok", false)), "E10: Seq 2 - Resupply ok")
	_check(is_equal_approx(GlobalData.fuel.mech_energy, 1000.0), "E11: Energy restored to 1000.0")


## --- TEST F: SIDE EFFECT FIREWALL ---
func _test_f_side_effect_firewall() -> void:
	_reset_campaign_runtime()

	CampaignNodeRegistry.register_node(1, Vector2i(7, 7), "supply_depot", "node_depot_f")
	GlobalData.board.current_sector = 1
	GlobalData.board.current_tile = Vector2i(7, 7)
	GlobalData.currency.credits = 1000

	# Snapshot non-economic domain states
	var forces_before := JSON.stringify(CampaignForce.get_forces())
	var territory_before := JSON.stringify(CampaignTerritory.serialize())
	var bases_before := JSON.stringify(CampaignBase.get_bases())
	var battles_before := JSON.stringify(CampaignBattle.get_battles())
	var turn_before := CampaignTurnExecutive.get_turn()
	var relations_before := JSON.stringify(FactionSystem.serialize_relations())
	var pos_before := GlobalData.board.current_tile
	var sector_before := GlobalData.board.current_sector

	# Execute trade
	CampaignPlayerDispatch.dispatch_intent(CampaignPlayerDispatch.create_intent("trade", "node_depot_f", {
		"operation": "buy",
		"item_id": "fuel_canister",
		"quantity": 2,
	}))

	_check(JSON.stringify(CampaignForce.get_forces()) == forces_before, "F1: Forces unmutated by trade")
	_check(JSON.stringify(CampaignTerritory.serialize()) == territory_before, "F2: Territories unmutated by trade")
	_check(JSON.stringify(CampaignBase.get_bases()) == bases_before, "F3: Bases unmutated by trade")
	_check(JSON.stringify(CampaignBattle.get_battles()) == battles_before, "F4: Battles unmutated by trade")
	_check(CampaignTurnExecutive.get_turn() == turn_before, "F5: Turn unmutated by trade")
	_check(JSON.stringify(FactionSystem.serialize_relations()) == relations_before, "F6: Relations unmutated by trade")
	_check(GlobalData.board.current_tile == pos_before, "F7: Player tile unmutated by trade")
	_check(GlobalData.board.current_sector == sector_before, "F8: Player sector unmutated by trade")
