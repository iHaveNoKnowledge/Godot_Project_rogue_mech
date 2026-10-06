class_name CampaignForceMovementPanel
extends Control

## ---------------------------------------------------------------------------
## CAMPAIGN FORCE MOVEMENT PANEL — Phase 5U (minimal player entry point).
##
## Audit evidence (do not re-decide lightly):
##   - No game-facing campaign screen/map/HUD exists: UI scripts are all
##     board/combat/hangar/shop/menu scoped, and zero UI files reference
##     CampaignForce or CampaignNodeRegistry. There was no existing
##     authority to extend, so this minimal dedicated entry point was
##     created instead of a parallel UI architecture.
##   - No PlayerForce exists (5F): hangar roster, active mech, board token,
##     convoy, and pilots are never fabricated into CampaignForces here.
##   - Destinations come only from CampaignNodeRegistry strategic routes
##     (one hop); BoardTile connections are never consulted.
##
## Authority split: this panel owns TRANSIENT UI state only
## (selected_force_id, selected_destination_node_id, last result, widgets).
## All validation and movement belong to CampaignForceMovement; all force
## state belongs to CampaignForce; all topology belongs to
## CampaignNodeRegistry. This panel never writes node_id directly, never
## persists selection, advances no turn, creates no battle, and emits no
## signals. Refresh always re-reads canonical state.
## ---------------------------------------------------------------------------

var _selected_force_id := ""
var _selected_destination_node_id := ""
var _last_result: Dictionary = {}
var _built := false

var _force_option: OptionButton
var _info_label: Label
var _destination_option: OptionButton
var _move_button: Button
var _result_label: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.name = "MovementPanel"
	add_child(root)
	_force_option = OptionButton.new()
	_force_option.name = "ForceOption"
	root.add_child(_force_option)
	_force_option.item_selected.connect(_on_force_item_selected)
	_info_label = Label.new()
	_info_label.name = "ForceInfo"
	root.add_child(_info_label)
	_destination_option = OptionButton.new()
	_destination_option.name = "DestinationOption"
	root.add_child(_destination_option)
	_destination_option.item_selected.connect(_on_destination_item_selected)
	_move_button = Button.new()
	_move_button.name = "MoveButton"
	_move_button.text = "Move"
	root.add_child(_move_button)
	_move_button.pressed.connect(_on_move_pressed)
	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	root.add_child(_result_label)
	_built = true
	refresh()


## Sorted force ids from canonical state. Rebuilds the force list widget.
func refresh_forces() -> Array:
	var ids: Array = []
	for f in CampaignForce.get_forces():
		ids.append(str(f.get("id", "")))
	ids.sort()
	if _built:
		_force_option.clear()
		for fid in ids:
			_force_option.add_item(str(fid))
		_sync_force_widget()
	return ids


## Selects a force. False on unknown id (selection unchanged).
func select_force(force_id: String) -> bool:
	if force_id == "" or not CampaignForce.has_force(force_id):
		return false
	_selected_force_id = force_id
	_selected_destination_node_id = ""
	refresh()
	return true


func get_selected_force_id() -> String:
	return _selected_force_id


## Canonical record of the selected force ({} when nothing selected).
func get_selected_force() -> Dictionary:
	if _selected_force_id == "":
		return {}
	return CampaignForce.get_force(_selected_force_id)


## Direct strategic neighbors of the selected force's current node,
## sorted. Empty when nothing selected, off-board, or isolated.
func get_destinations() -> Array:
	if _selected_force_id == "" or not CampaignForce.has_force(_selected_force_id):
		return []
	var node_id := str(CampaignForce.get_force(_selected_force_id).get("node_id", ""))
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return []
	var seen := {}
	for r in CampaignNodeRegistry.get_routes_for(node_id):
		for key in ["a", "b"]:
			var other := str((r as Dictionary).get(key, ""))
			if other != "" and other != node_id:
				seen[other] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## Selects a destination. False unless currently offered (selection unchanged).
func select_destination(node_id: String) -> bool:
	if not get_destinations().has(node_id):
		return false
	_selected_destination_node_id = node_id
	refresh()
	return true


func get_selected_destination() -> String:
	return _selected_destination_node_id


## Runs the selection through the movement authority and refreshes from
## canonical state. The authority is the final correctness gate.
func execute_move() -> Dictionary:
	if _selected_force_id == "" or not CampaignForce.has_force(_selected_force_id):
		_last_result = {
			"ok": false, "force_id": _selected_force_id,
			"from_node_id": "", "to_node_id": _selected_destination_node_id,
			"reason": "no_selection",
		}
		refresh()
		return _last_result.duplicate()
	if _selected_destination_node_id == "":
		_last_result = {
			"ok": false, "force_id": _selected_force_id,
			"from_node_id": _current_node(), "to_node_id": "",
			"reason": "no_destination",
		}
		refresh()
		return _last_result.duplicate()
	_last_result = CampaignForceMovement.move_force(
		_selected_force_id, _selected_destination_node_id)
	if bool(_last_result.get("ok", false)):
		_selected_destination_node_id = ""
	refresh()
	return _last_result.duplicate()


func get_last_result() -> Dictionary:
	return _last_result.duplicate()


## Display lines for the force list (id, type, faction, state, node).
func get_force_display_lines() -> Array:
	var lines: Array = []
	for fid in refresh_forces():
		var f := CampaignForce.get_force(str(fid))
		lines.append("%s [%s] faction=%s state=%s node=%s" % [
			str(fid), str(f.get("force_type", "")), str(f.get("faction", "")),
			CampaignForce.state_to_name(int(f.get("state", 0))),
			str(f.get("node_id", "")),
		])
	return lines


## Display lines for the current destination offer.
func get_destination_display_lines() -> Array:
	var lines: Array = []
	for nid in get_destinations():
		lines.append(str(nid))
	return lines


## One-line human summary of the last result ("" when no move attempted).
func get_result_line() -> String:
	if _last_result.is_empty():
		return ""
	if bool(_last_result.get("ok", false)):
		return "Moved: %s -> %s" % [
			str(_last_result.get("from_node_id", "")),
			str(_last_result.get("to_node_id", ""))]
	return "Move failed: %s" % str(_last_result.get("reason", ""))


## Re-reads canonical state into the widgets (never the reverse).
func refresh() -> void:
	refresh_forces()
	if _built:
		_sync_destination_widget()
		_info_label.text = _info_text()
		_result_label.text = get_result_line()


func _current_node() -> String:
	if _selected_force_id == "" or not CampaignForce.has_force(_selected_force_id):
		return ""
	return str(CampaignForce.get_force(_selected_force_id).get("node_id", ""))


func _info_text() -> String:
	var f := get_selected_force()
	if f.is_empty():
		return "No force selected"
	return "Force %s current node: %s" % [
		_selected_force_id, str(f.get("node_id", ""))]


func _sync_force_widget() -> void:
	for i in _force_option.item_count:
		if _force_option.get_item_text(i) == _selected_force_id:
			_force_option.select(i)
			return
	_force_option.select(-1)


func _sync_destination_widget() -> void:
	_destination_option.clear()
	for nid in get_destinations():
		_destination_option.add_item(str(nid))
	for i in _destination_option.item_count:
		if _destination_option.get_item_text(i) == _selected_destination_node_id:
			_destination_option.select(i)
			return
	_destination_option.select(-1)


func _on_force_item_selected(index: int) -> void:
	select_force(_force_option.get_item_text(index))


func _on_destination_item_selected(index: int) -> void:
	select_destination(_destination_option.get_item_text(index))


func _on_move_pressed() -> void:
	execute_move()
