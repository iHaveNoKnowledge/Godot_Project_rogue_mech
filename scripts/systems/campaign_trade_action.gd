class_name CampaignTradeAction
extends RefCounted

## ---------------------------------------------------------------------------
## CAMPAIGN TRADE ACTION DOMAIN CONTRACT — Phase 5AR
##
## Domain authority for executing the player 'trade' action.
##
## Domain Responsibilities:
##   - Receives action intent targeted at a strategic node with trade payload.
##   - Enforces trade domain preconditions (trade-capable node, valid asset, positive quantity).
##   - Atomically mutates player currency and inventory via CurrencyManager & GlobalData.
##   - Produces a deterministic trade completion contract / receipt.
##   - Enforces zero unintended side-effects across territory, bases, forces, battles, turns, relations.
##
## Architectural Contract:
##   - What it inspects: Target node type from CampaignNodeRegistry, CurrencyManager balance, and inventory.
##   - What it mutates: GlobalData.currency (credits, scrap) and GlobalData.fuel_inventory.
##   - What it preserves: Zero mutation across territory, bases, forces, battles, turns, relations.
##   - Permitted nodes: START, SAFEHOUSE, CITY, SUPPLY_DEPOT.
##   - Turn semantics: ZERO turn advancement (CampaignTurnExecutive untouched).
## ---------------------------------------------------------------------------

const TRADE_NODE_TYPES := [
	"START",
	"SAFEHOUSE",
	"CITY",
	"SUPPLY_DEPOT",
]

const SCRAP_BUY_PRICE: int = 10
const SCRAP_SELL_PRICE: int = 5
const CONSUMABLE_SELL_RATIO: float = 0.5


## Checks whether a node type supports commercial trade operations.
static func is_trade_node_type(node_type: String) -> bool:
	return TRADE_NODE_TYPES.has(node_type.to_upper())


## Checks whether an item ID is a recognized tradable asset.
static func is_valid_tradable_item(item_id: String) -> bool:
	if item_id == "scrap":
		return true
	if GlobalData != null:
		var entry := GlobalData.get_fuel_item_entry(item_id)
		if not entry.is_empty():
			return true
	return false


## Returns the unit buy price in credits for an item. Returns 0 if invalid.
static func get_item_buy_price(item_id: String) -> int:
	if item_id == "scrap":
		return SCRAP_BUY_PRICE
	if GlobalData != null:
		var entry := GlobalData.get_fuel_item_entry(item_id)
		if not entry.is_empty():
			return int(entry.get("price", 100))
	return 0


## Returns the unit sell price in credits for an item. Returns 0 if invalid.
static func get_item_sell_price(item_id: String) -> int:
	if item_id == "scrap":
		return SCRAP_SELL_PRICE
	if GlobalData != null:
		var entry := GlobalData.get_fuel_item_entry(item_id)
		if not entry.is_empty():
			var buy_price := int(entry.get("price", 100))
			return maxi(int(floor(buy_price * CONSUMABLE_SELL_RATIO)), 1)
	return 0


## Returns current owned quantity of the given item.
static func get_item_inventory_count(item_id: String) -> int:
	if GlobalData == null:
		return 0
	if item_id == "scrap":
		return GlobalData.currency.scrap if GlobalData.currency != null else 0
	return GlobalData.get_fuel_item_count(item_id)


## Executes the domain trade action for a given intent.
## Callable signature: (intent: Dictionary) -> Dictionary
static func handle_trade(intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", "")).strip_edges()
	var node_id := str(intent.get("node_id", "")).strip_edges()
	var payload: Dictionary = intent.get("payload", {})

	if action_id != "trade":
		return {
			"ok": false,
			"reason": "invalid_action_for_handler",
			"action_id": action_id,
			"node_id": node_id,
		}

	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return {
			"ok": false,
			"reason": "unknown_node",
			"action_id": action_id,
			"node_id": node_id,
		}

	var node := CampaignNodeRegistry.get_node(node_id)
	var node_type := str(node.get("node_type", "")).to_upper()

	if not is_trade_node_type(node_type):
		return {
			"ok": false,
			"reason": "node_cannot_trade",
			"action_id": action_id,
			"node_id": node_id,
			"node_type": node_type,
		}

	if GlobalData == null or GlobalData.currency == null:
		return {
			"ok": false,
			"reason": "economy_authority_unavailable",
			"action_id": action_id,
			"node_id": node_id,
		}

	var operation := str(payload.get("operation", "buy")).to_lower().strip_edges()
	if operation != "buy" and operation != "sell":
		return {
			"ok": false,
			"reason": "invalid_trade_operation",
			"action_id": action_id,
			"node_id": node_id,
			"operation": operation,
		}

	var item_id := str(payload.get("item_id", "")).strip_edges()
	if not is_valid_tradable_item(item_id):
		return {
			"ok": false,
			"reason": "unknown_tradable_item",
			"action_id": action_id,
			"node_id": node_id,
			"item_id": item_id,
		}

	var quantity := int(payload.get("quantity", 1))
	if quantity <= 0:
		return {
			"ok": false,
			"reason": "invalid_trade_quantity",
			"action_id": action_id,
			"node_id": node_id,
			"quantity": quantity,
		}

	if operation == "buy":
		var unit_price := get_item_buy_price(item_id)
		var total_cost := unit_price * quantity
		if GlobalData.currency.credits < total_cost:
			return {
				"ok": false,
				"reason": "insufficient_credits",
				"action_id": action_id,
				"node_id": node_id,
				"operation": "buy",
				"item_id": item_id,
				"quantity": quantity,
				"total_cost": total_cost,
				"credits": GlobalData.currency.credits,
			}

		if not GlobalData.currency.try_spend_credits(total_cost):
			return {
				"ok": false,
				"reason": "currency_deduction_failed",
				"action_id": action_id,
				"node_id": node_id,
			}

		if item_id == "scrap":
			GlobalData.currency.gain_scrap(quantity)
		else:
			GlobalData.add_fuel_item(item_id, quantity)

		return {
			"ok": true,
			"reason": "trade_completed",
			"action_id": "trade",
			"node_id": node_id,
			"operation": "buy",
			"item_id": item_id,
			"quantity": quantity,
			"total_price": total_cost,
			"credits_remaining": GlobalData.currency.credits,
			"scrap_remaining": GlobalData.currency.scrap,
			"inventory_count": get_item_inventory_count(item_id),
		}

	else: # operation == "sell"
		var owned := get_item_inventory_count(item_id)
		if owned < quantity:
			return {
				"ok": false,
				"reason": "insufficient_inventory",
				"action_id": action_id,
				"node_id": node_id,
				"operation": "sell",
				"item_id": item_id,
				"quantity": quantity,
				"owned": owned,
			}

		var unit_price := get_item_sell_price(item_id)
		var total_gain := unit_price * quantity

		if item_id == "scrap":
			if not GlobalData.currency.try_spend_scrap(quantity):
				return {
					"ok": false,
					"reason": "scrap_deduction_failed",
					"action_id": action_id,
					"node_id": node_id,
				}
		else:
			var cur_count := GlobalData.get_fuel_item_count(item_id)
			var new_count := cur_count - quantity
			if new_count <= 0:
				GlobalData.fuel_inventory.erase(item_id)
			else:
				GlobalData.fuel_inventory[item_id] = new_count

		GlobalData.currency.gain_credits(total_gain)

		return {
			"ok": true,
			"reason": "trade_completed",
			"action_id": "trade",
			"node_id": node_id,
			"operation": "sell",
			"item_id": item_id,
			"quantity": quantity,
			"total_price": total_gain,
			"credits_remaining": GlobalData.currency.credits,
			"scrap_remaining": GlobalData.currency.scrap,
			"inventory_count": get_item_inventory_count(item_id),
		}
