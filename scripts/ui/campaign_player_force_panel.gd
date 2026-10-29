class_name CampaignPlayerForcePanel
extends Control

## ---------------------------------------------------------------------------
## CAMPAIGN PLAYER FORCE PANEL — Phase C8-B (raise / move / station UI).
##
## Audit evidence (do not re-decide lightly):
##   - `campaign_node_map.gd` is the single campaign screen and builds its
##     sidebar inline; 5U/5V established the pattern of a dedicated panel
##     class for a distinct flow instead of growing the map script into a
##     god-object. This panel is that dedicated class for detachments.
##   - There was no player-facing entry point for CampaignPlayerForce (C8-A):
##     detachments could only be seeded by RunStartSystem.
##   - CampaignPlayerForceAction (C8-B) owns all validation/pricing; the panel
##     never calls CampaignPlayerForce mutators directly.
##
## Authority split: this panel owns TRANSIENT UI state only (selection, last
## receipt, widgets). It advances no turn, resolves no battle, mutates no base/
## territory/supply, and persists nothing. `refresh()` always re-reads
## canonical state.
## ---------------------------------------------------------------------------

var _selected_force_id := ""
var _selected_destination_node_id := ""
var _selected_attack_target_id := ""
var _last_result: Dictionary = {}
var _built := false

var _header_label: Label
var _detachment_option: OptionButton
var _info_label: Label
var _raise_button: Button
var _destination_option: OptionButton
var _move_button: Button
var _attack_target_option: OptionButton
var _attack_button: Button
var _station_button: Button
var _unstation_button: Button
var _result_label: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.name = "PlayerForceRoot"
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	root.add_child(_header_label)

	_detachment_option = OptionButton.new()
	_detachment_option.name = "DetachmentOption"
	root.add_child(_detachment_option)
	_detachment_option.item_selected.connect(_on_detachment_selected)

	_info_label = Label.new()
	_info_label.name = "DetachmentInfo"
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_info_label)

	_raise_button = Button.new()
	_raise_button.name = "RaiseButton"
	_raise_button.text = "RAISE DETACHMENT"
	root.add_child(_raise_button)
	_raise_button.pressed.connect(_on_raise_pressed)

	_destination_option = OptionButton.new()
	_destination_option.name = "DestinationOption"
	root.add_child(_destination_option)
	_destination_option.item_selected.connect(_on_destination_selected)

	_move_button = Button.new()
	_move_button.name = "MoveButton"
	_move_button.text = "MOVE DETACHMENT"
	root.add_child(_move_button)
	_move_button.pressed.connect(_on_move_pressed)

	_attack_target_option = OptionButton.new()
	_attack_target_option.name = "AttackTargetOption"
	root.add_child(_attack_target_option)
	_attack_target_option.item_selected.connect(_on_attack_target_selected)

	_attack_button = Button.new()
	_attack_button.name = "AttackButton"
	_attack_button.text = "ATTACK HOSTILE FORCE"
	root.add_child(_attack_button)
	_attack_button.pressed.connect(_on_attack_pressed)

	_station_button = Button.new()
	_station_button.name = "StationButton"
	_station_button.text = "STATION AT BASE"
	root.add_child(_station_button)
	_station_button.pressed.connect(_on_station_pressed)

	_unstation_button = Button.new()
	_unstation_button.name = "UnstationButton"
	_unstation_button.text = "UNSTATION"
	root.add_child(_unstation_button)
	_unstation_button.pressed.connect(_on_unstation_pressed)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_result_label)

	_built = true
	refresh()


## Sorted detachment ids from canonical state. Rebuilds the list widget.
func refresh_detachments() -> Array:
	var ids: Array = []
	for d in CampaignPlayerForce.get_detachments():
		ids.append(str(d.get("id", "")))
	ids.sort()
	if _built:
		_detachment_option.clear()
		for fid in ids:
			_detachment_option.add_item(str(fid))
		_sync_detachment_widget()
	return ids


func select_detachment(force_id: String) -> bool:
	if force_id == "" or not CampaignPlayerForce.has_detachment(force_id):
		return false
	_selected_force_id = force_id
	_selected_destination_node_id = ""
	_selected_attack_target_id = ""
	refresh()
	return true


func get_selected_detachment() -> String:
	return _selected_force_id


## Neighbours of the selected detachment's node along registered routes.
func get_destinations() -> Array:
	if _selected_force_id == "" or not CampaignPlayerForce.has_detachment(_selected_force_id):
		return []
	var node_id := str(CampaignPlayerForce.get_detachment(_selected_force_id).get("node_id", ""))
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		return []
	var out: Array = []
	for nid in CampaignNodeRegistry.get_connected_node_ids(node_id):
		out.append(str(nid))
	out.sort()
	return out


func select_destination(node_id: String) -> bool:
	if not get_destinations().has(node_id):
		return false
	_selected_destination_node_id = node_id
	refresh()
	return true


func get_selected_destination() -> String:
	return _selected_destination_node_id


## Hostile forces the selected detachment may attack (same node, HOSTILE
## relation). Read-only authority query.
func get_attack_targets() -> Array:
	if _selected_force_id == "" or not CampaignPlayerForce.has_detachment(_selected_force_id):
		return []
	var node_id := str(CampaignPlayerForce.get_detachment(_selected_force_id).get("node_id", ""))
	return CampaignPlayerForceAssault.get_hostile_targets_at(node_id)


func select_attack_target(target_force_id: String) -> bool:
	if not get_attack_targets().has(target_force_id):
		return false
	_selected_attack_target_id = target_force_id
	refresh()
	return true


func get_selected_attack_target() -> String:
	return _selected_attack_target_id


## Runs the engagement through the assault domain and refreshes.
func attack_selected() -> Dictionary:
	if _selected_force_id == "" or _selected_attack_target_id == "":
		_last_result = {"ok": false, "reason": "no_selection"}
		refresh()
		return _last_result.duplicate(true)
	_last_result = CampaignPlayerForceAssault.attack(
		_selected_force_id, _selected_attack_target_id)
	if bool(_last_result.get("ok", false)):
		_selected_attack_target_id = ""
		GlobalData.save_run()
	refresh()
	return _last_result.duplicate(true)


## Raises a detachment at the player's current node using a deterministic slug.
func raise_at_current_node() -> Dictionary:
	var slug := "aux_%d" % (CampaignPlayerForce.get_detachments().size() + 1)
	_last_result = CampaignPlayerForceAction.raise_player_detachment(slug)
	if bool(_last_result.get("ok", false)):
		_selected_force_id = str(_last_result.get("force_id", ""))
		GlobalData.save_run()
	refresh()
	return _last_result.duplicate(true)


func execute_move() -> Dictionary:
	if _selected_force_id == "" or _selected_destination_node_id == "":
		_last_result = {"ok": false, "reason": "no_selection"}
		refresh()
		return _last_result.duplicate(true)
	_last_result = CampaignPlayerForceAction.move_player_detachment(
		_selected_force_id, _selected_destination_node_id)
	if bool(_last_result.get("ok", false)):
		_selected_destination_node_id = ""
		GlobalData.save_run()
	refresh()
	return _last_result.duplicate(true)


func station_at_base() -> Dictionary:
	if _selected_force_id == "":
		_last_result = {"ok": false, "reason": "no_selection"}
		refresh()
		return _last_result.duplicate(true)
	var base := _stationable_base(_selected_force_id)
	if base.is_empty():
		_last_result = {"ok": false, "reason": "no_player_base_at_node"}
		refresh()
		return _last_result.duplicate(true)
	_last_result = CampaignPlayerForceAction.station_player_detachment(
		_selected_force_id, str(base.get("id", "")))
	if bool(_last_result.get("ok", false)):
		GlobalData.save_run()
	refresh()
	return _last_result.duplicate(true)


func unstation() -> Dictionary:
	if _selected_force_id == "":
		_last_result = {"ok": false, "reason": "no_selection"}
		refresh()
		return _last_result.duplicate(true)
	_last_result = CampaignPlayerForceAction.unstation_player_detachment(_selected_force_id)
	if bool(_last_result.get("ok", false)):
		GlobalData.save_run()
	refresh()
	return _last_result.duplicate(true)


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


## Display lines for every detachment (UI list text).
func get_detachment_display_lines() -> Array:
	var lines: Array = []
	for fid in refresh_detachments():
		lines.append(CampaignPlayerForceAction.describe_detachment(str(fid)))
	return lines


func get_result_line() -> String:
	if _last_result.is_empty():
		return ""
	if bool(_last_result.get("ok", false)):
		return "OK: %s" % str(_last_result.get("reason", ""))
	return "Rejected: %s" % str(_last_result.get("reason", ""))


## Re-reads canonical state into the widgets (never the reverse).
func refresh() -> void:
	refresh_detachments()
	if not _built:
		return
	_sync_destination_widget()
	_sync_attack_widget()
	_header_label.text = "DETACHMENTS  |  Credits: %d  |  Raise cost: %d" % [
		int(GlobalData.currency.credits),
		CampaignPlayerForceAction.get_raise_cost(),
	]
	var selected := CampaignPlayerForce.get_detachment(_selected_force_id)
	if selected.is_empty():
		_info_label.text = "No detachment selected"
		_raise_button.disabled = true
		_move_button.disabled = true
		_attack_button.disabled = true
		_station_button.disabled = true
		_unstation_button.disabled = true
	else:
		_info_label.text = CampaignPlayerForceAction.describe_detachment(_selected_force_id)
		_move_button.disabled = _selected_destination_node_id == ""
		_attack_button.disabled = _selected_attack_target_id == "" \
			or not CampaignPlayerForce.is_active(_selected_force_id)
		_station_button.disabled = _stationable_base(_selected_force_id).is_empty()
		_unstation_button.disabled = str(selected.get("base_id", "")) == ""
		var current_node := CampaignPlayerMovement.get_current_node_id()
		var at_current := current_node != "" and current_node == str(selected.get("node_id", ""))
		_raise_button.disabled = not at_current \
			or int(GlobalData.currency.credits) < CampaignPlayerForceAction.get_raise_cost()
	_result_label.text = get_result_line()


## True when the panel can raise a detachment right now (used by tests/UI).
func can_raise_now() -> bool:
	var current_node := CampaignPlayerMovement.get_current_node_id()
	if current_node == "" or not CampaignNodeInspection.is_player_at_node(current_node):
		return false
	return int(GlobalData.currency.credits) >= CampaignPlayerForceAction.get_raise_cost()


func _stationable_base(force_id: String) -> Dictionary:
	if not CampaignPlayerForce.has_detachment(force_id):
		return {}
	var node_id := str(CampaignPlayerForce.get_detachment(force_id).get("node_id", ""))
	if node_id == "":
		return {}
	var base := CampaignBase.get_base_at_node(node_id)
	if base.is_empty():
		return {}
	if int(base.get("state", -1)) == CampaignBase.BaseState.DESTROYED:
		return {}
	if str(base.get("controller", "")) != FactionSystem.get_player_faction():
		return {}
	return base


func _sync_detachment_widget() -> void:
	for i in _detachment_option.item_count:
		if _detachment_option.get_item_text(i) == _selected_force_id:
			_detachment_option.select(i)
			return
	_detachment_option.select(-1)


func _sync_attack_widget() -> void:
	_attack_target_option.clear()
	for fid in get_attack_targets():
		_attack_target_option.add_item(str(fid))
	for i in _attack_target_option.item_count:
		if _attack_target_option.get_item_text(i) == _selected_attack_target_id:
			_attack_target_option.select(i)
			return
	_attack_target_option.select(-1)


func _sync_destination_widget() -> void:
	_destination_option.clear()
	for nid in get_destinations():
		_destination_option.add_item(str(nid))
	for i in _destination_option.item_count:
		if _destination_option.get_item_text(i) == _selected_destination_node_id:
			_destination_option.select(i)
			return
	_destination_option.select(-1)


func _on_detachment_selected(index: int) -> void:
	select_detachment(_detachment_option.get_item_text(index))


func _on_destination_selected(index: int) -> void:
	select_destination(_destination_option.get_item_text(index))


func _on_raise_pressed() -> void:
	raise_at_current_node()


func _on_move_pressed() -> void:
	execute_move()


func _on_attack_target_selected(index: int) -> void:
	select_attack_target(_attack_target_option.get_item_text(index))


func _on_attack_pressed() -> void:
	attack_selected()


func _on_station_pressed() -> void:
	station_at_base()


func _on_unstation_pressed() -> void:
	unstation()
