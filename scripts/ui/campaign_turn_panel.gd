class_name CampaignTurnPanel
extends Control

## ---------------------------------------------------------------------------
## CAMPAIGN TURN PANEL — Phase 5W (player-facing campaign turn entry point).
##
## Audit evidence (do not re-decide lightly):
##   - CampaignTurnExecutive (Phase 1) is the ONE AND ONLY authority for
##     advancing campaign turns. It runs the deterministic phase sequence:
##     economy -> spy -> base -> board_day_ended -> rival -> era -> scavenger.
##   - Previously, advance_campaign_turn was called only from board-scale
##     consequences (BoardManager calendar advance upon midnight cross or
##     intermission end day). No dedicated player-facing Campaign V2 turn
##     completion control existed.
##   - The 5U movement panel (CampaignForceMovementPanel) and 5V inspection panel
##     (CampaignNodeInspectionPanel) compose alongside this panel: players can
##     inspect, move forces across strategic routes, and complete their turn
##     without creating a giant monolithic manager or a secondary turn system.
##
## Authority split: this panel owns TRANSIENT UI state only
## (receipt display, confirmation state, status labels, widgets).
## All turn progression belongs strictly to CampaignTurnExecutive.
## This panel NEVER calls turn phases individually (FactionEconomySystem,
## EnemyFactionSystem, etc.), NEVER calls BoardManager calendar advance,
## NEVER mutates CampaignForce, CampaignTerritory, CampaignBase, or
## CampaignBattle, NEVER increments turn counters directly, and NEVER
## persists UI state.
## ---------------------------------------------------------------------------

const DEFAULT_REASON := "player_end_turn"

var _last_receipt: Dictionary = {}
var _confirming := false
var _requires_confirmation := false
var _built := false

var _turn_label: Label
var _end_turn_button: Button
var _status_label: Label
var _receipt_label: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.name = "TurnPanel"
	add_child(root)

	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	root.add_child(_turn_label)

	_end_turn_button = Button.new()
	_end_turn_button.name = "EndTurnButton"
	_end_turn_button.text = "End Campaign Turn"
	root.add_child(_end_turn_button)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	root.add_child(_status_label)

	_receipt_label = Label.new()
	_receipt_label.name = "ReceiptLabel"
	root.add_child(_receipt_label)

	_built = true
	refresh()


## Pure read of the current canonical turn from CampaignTurnExecutive.
func get_current_turn() -> int:
	return CampaignTurnExecutive.get_turn()


## Duplicate of the last receipt produced by advance_campaign_turn (or {}).
func get_last_receipt() -> Dictionary:
	return _last_receipt.duplicate(true)


func is_confirming() -> bool:
	return _confirming


func requires_confirmation() -> bool:
	return _requires_confirmation


func set_requires_confirmation(val: bool) -> void:
	_requires_confirmation = val
	_confirming = false
	refresh()


func cancel_confirmation() -> void:
	_confirming = false
	refresh()


## Requests ending the campaign turn. If confirmation is required and not yet
## active, transitions to confirmation state and returns a prompt receipt.
## Otherwise calls CampaignTurnExecutive.advance_campaign_turn directly.
func end_turn(reason: String = DEFAULT_REASON, opts: Dictionary = {}) -> Dictionary:
	if _requires_confirmation and not _confirming:
		_confirming = true
		if _built:
			_status_label.text = "Confirmation required. Press again to end turn."
			_end_turn_button.text = "Confirm End Turn"
		return {
			"ok": false,
			"reason": "confirmation_required",
			"turn": get_current_turn(),
			"phases": [],
		}

	_confirming = false
	var receipt := CampaignTurnExecutive.advance_campaign_turn(reason, opts)
	_last_receipt = receipt.duplicate(true)
	refresh()
	return receipt.duplicate(true)


## Helper that proceeds directly through confirmation if active.
func confirm_end_turn(reason: String = DEFAULT_REASON, opts: Dictionary = {}) -> Dictionary:
	_confirming = true
	return end_turn(reason, opts)


## Clears transient UI state (receipt and confirmation). Canonical turn untouched.
func clear() -> void:
	_last_receipt = {}
	_confirming = false
	refresh()


## Re-reads canonical state into widgets.
func refresh() -> void:
	if not _built:
		return
	var cur_turn := get_current_turn()
	_turn_label.text = "Campaign Turn: %d" % cur_turn
	_end_turn_button.disabled = CampaignTurnExecutive.is_executing()
	if _confirming:
		_end_turn_button.text = "Confirm End Turn"
		_status_label.text = "Confirm ending Campaign Turn %d?" % cur_turn
	else:
		_end_turn_button.text = "End Campaign Turn"
		if not _last_receipt.is_empty():
			if bool(_last_receipt.get("ok", false)):
				_status_label.text = "Turn %d completed (%s)" % [
					int(_last_receipt.get("turn", cur_turn)),
					str(_last_receipt.get("reason", ""))
				]
			else:
				_status_label.text = "Turn rejected: %s" % str(_last_receipt.get("error", "failed"))
		else:
			_status_label.text = "Ready"

	_receipt_label.text = "\n".join(get_summary_lines())


## Formats human-readable summary lines from current state and last receipt.
func get_summary_lines() -> Array:
	var lines: Array = []
	lines.append("Current Turn: %d" % get_current_turn())
	if not _last_receipt.is_empty():
		var r_turn := int(_last_receipt.get("turn", 0))
		var r_reason := str(_last_receipt.get("reason", ""))
		var r_ok := bool(_last_receipt.get("ok", false))
		lines.append("Last Action: %s (Turn %d)" % [r_reason, r_turn])
		lines.append("Status: %s" % ("Success" if r_ok else "Rejected (%s)" % str(_last_receipt.get("error", ""))))
		var phases: Array = _last_receipt.get("phases", [])
		if not phases.is_empty():
			lines.append("Phases: %s" % ", ".join(phases))
	return lines


func _on_end_turn_pressed() -> void:
	end_turn(DEFAULT_REASON, {})
