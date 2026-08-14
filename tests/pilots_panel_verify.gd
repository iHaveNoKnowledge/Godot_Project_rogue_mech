extends Node

## Headless verification of the pilot roster system:
##   - the hangar builds a PILOTS page listing every pilot in the convoy (the
##     driver plus each researched fleet unit) with live status and the mech
##     they drive; wounded pilots get a HEAL shortcut
##   - the REGISTER name dialog offers the same pilot list, defaults to the
##     driver, and assigning a fleet pilot parks the new frame under them
##     instead of taking over the driver's mech
## Run: godot --headless --path . res://tests/pilots_panel_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_pilots_page()
	await _verify_register_pilot()
	print("PILOTS_PANEL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _collect_text(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += child.text + "\n"
		out += _collect_text(child)
	return out


func _find_heal_button(container: Node) -> Button:
	for row in container.get_children():
		if not is_instance_valid(row) or row.is_queued_for_deletion():
			continue
		for child in row.get_children():
			if child is Button and str(child.text).begins_with("HEAL") and is_instance_valid(child) and not child.is_queued_for_deletion():
				return child
	return null


func _find_button_by_text(host: Node, text: String) -> Button:
	for child in host.get_children():
		if child is Button and str(child.text) == text and is_instance_valid(child) and not child.is_queued_for_deletion():
			return child
		var found = _find_button_by_text(child, text)
		if found:
			return found
	return null


func _verify_pilots_page() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var pp = ctrl.pilots_panel_ui
	_check(pp != null, "controller builds a HangarPilotsPanel")
	_check(pp.pilots_panel != null, "pilots panel builds its root panel")
	_check(pp.pilot_list != null, "pilots panel builds the pilot list")
	_check(pp.pilots_panel.visible == false, "pilots page starts hidden")

	ctrl.nav_panel.select_submenu("pilots")
	await get_tree().process_frame
	_check(pp.pilots_panel.visible, "pilots page shows the panel")
	_check(not ctrl.roster_panel_ui.roster_panel.visible, "pilots page hides the roster page")

	var text := _collect_text(pp.pilots_panel)
	_check(text.contains("PILOT ROSTER"), "pilots page has its title")
	_check(text.contains("YOU (driver)"), "pilots page lists the player driver")

	# A healthy fleet unit shows with its live HP and no mech when unseated.
	GlobalData.fleet_roster.append({"template_id": "t_pp", "name": "Pilot Patty", "hp": 40.0, "max_hp": 80.0, "destroyed": false, "fielded": true})
	pp.refresh()
	await get_tree().process_frame
	text = _collect_text(pp.pilots_panel)
	_check(text.contains("Pilot Patty · 40/80 HP"), "pilots page shows the fleet pilot's live HP")
	_check(text.contains("· (no mech)"), "unseated pilot shows no mech")

	# Seating her in the active berth -> the row names the mech she drives.
	var slot1_id := ""
	for m in GlobalData.get_hangar_mechs():
		if int(m.get("slot", 0)) == 1:
			slot1_id = str(m.get("id", ""))
			break
	if slot1_id != "":
		GlobalData.assign_hangar_pilot(slot1_id, "fleet_t_pp")
	pp.refresh()
	await get_tree().process_frame
	text = _collect_text(pp.pilots_panel)
	_check(text.contains("Pilot Patty · 40/80 HP · Mech 01"), "seated fleet pilot shows the mech they drive")

	# Wounded -> countdown marker + HEAL button; healing clears both.
	for u in GlobalData.fleet_roster:
		if u.get("template_id", "") == "t_pp":
			u["wounded"] = true
			u["wound_turns"] = 2
	pp.refresh()
	await get_tree().process_frame
	text = _collect_text(pp.pilots_panel)
	_check(text.contains("Pilot Patty · WOUNDED (2T)"), "wounded pilot shows the recovery countdown")
	var heal_btn := _find_heal_button(pp.pilot_list)
	_check(heal_btn != null, "wounded pilot row offers a HEAL button")
	GlobalData.credits = 1000
	if heal_btn:
		heal_btn.pressed.emit()
		await get_tree().process_frame
	var healed := false
	for u in GlobalData.fleet_roster:
		if u.get("template_id", "") == "t_pp":
			healed = not bool(u.get("wounded", false))
	_check(healed, "HEAL clears the wound")
	_check(_find_heal_button(pp.pilot_list) == null, "HEAL button disappears once the pilot is healthy")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_register_pilot() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame
	var rp = ctrl.roster_panel_ui

	# Give the convoy a fleet pilot to pick in the REGISTER dialog.
	GlobalData.fleet_roster.append({"template_id": "t_reg", "name": "Regina", "hp": 60.0, "max_hp": 60.0, "destroyed": false, "fielded": true})

	# Start the REGISTER assembly for the empty berth and equip a walking chassis.
	rp.register_mech(2)
	await get_tree().process_frame
	GlobalData.equipped_frames["body"] = (GlobalData.frame_catalog["body"][0] as Dictionary).duplicate()
	GlobalData.equipped_frames["leg_left"] = (GlobalData.frame_catalog["leg_left"][0] as Dictionary).duplicate()
	GlobalData.equipped_frames["leg_right"] = (GlobalData.frame_catalog["leg_right"][0] as Dictionary).duplicate()
	rp.refresh_pending_register()
	GlobalData.gain_scrap(200)
	GlobalData.gain_credits(200)
	if rp.pending_register_button:
		rp.pending_register_button.pressed.emit()
		await get_tree().process_frame
	_check(rp.register_dialog != null, "REGISTER opens the name dialog")
	_check(rp.register_dialog_pilot != null, "name dialog offers a pilot picker")
	if rp.register_dialog_pilot:
		_check(rp.register_dialog_pilot.item_count == GlobalData.get_hangar_pilots().size(), "pilot picker lists every convoy pilot")
		_check(rp.register_dialog_pilot.selected == 0, "pilot picker defaults to the driver")

	var mechs_before := GlobalData.get_hangar_mechs().size()
	if rp.register_dialog_edit:
		rp.register_dialog_edit.text = "Reggie"
	if rp.register_dialog_pilot:
		var fleet_idx := -1
		for i in range(rp.register_dialog_pilot.item_count):
			if rp.register_dialog_pilot.get_item_text(i).contains("Regina"):
				fleet_idx = i
				break
		_check(fleet_idx >= 0, "fleet pilot is selectable in the picker")
		if fleet_idx >= 0:
			rp.register_dialog_pilot.select(fleet_idx)
	if rp.register_dialog:
		var ok := _find_button_by_text(rp.register_dialog, "REGISTER FRAME")
		if ok:
			ok.pressed.emit()
			await get_tree().process_frame
	_check(GlobalData.get_hangar_mechs().size() == mechs_before + 1, "confirmed REGISTER parks the frame")
	var new_id := ""
	for m in GlobalData.get_hangar_mechs():
		if str(m.get("name", "")) == "Reggie":
			new_id = str(m.get("id", ""))
	_check(new_id != "", "registered frame carries the custom name")
	if new_id != "":
		var pilot_of := ""
		for m in GlobalData.get_hangar_mechs():
			if str(m.get("id", "")) == new_id:
				pilot_of = str(m.get("pilot", ""))
		_check(pilot_of == "fleet_t_reg", "fleet-pilot REGISTER parks the frame under the chosen pilot")
		_check(GlobalData.active_hangar_mech_id != new_id, "fleet-pilot REGISTER does not take over the driver's mech")
	_check(GlobalData.get_hangar_pilot_name("fleet_t_reg") != "", "registered pilot resolves through the shared pilot list")

	ctrl.queue_free()
	await get_tree().process_frame
