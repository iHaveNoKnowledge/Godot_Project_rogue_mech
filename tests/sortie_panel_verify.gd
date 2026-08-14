extends Node

## Headless verification of the SORTIE page + the Feature 7 fielding rule:
##   - the hangar builds a SORTIE page listing every piloted berth with a
##     FIELDED / STANDING DOWN toggle that drives the pilot's fleet-unit flag
##   - the player's active mech shows as a read-only ★ PILOTED badge (they
##     pilot it directly, so it is never a tag-along ally)
##   - an unpiloted berth does not appear as a sortie row
##   - wounded/destroyed pilots get locked toggles; the healthy ones toggle
## Run: godot --headless --path . res://tests/sortie_panel_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_sortie_page()
	await _verify_fielding()
	print("SORTIE_PANEL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
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


func _find_button_by_text(host: Node, text: String) -> Button:
	for child in host.get_children():
		if child is Button and str(child.text) == text and is_instance_valid(child) and not child.is_queued_for_deletion():
			return child
		var found = _find_button_by_text(child, text)
		if found:
			return found
	return null


# Finds the first sortie row whose collected text mentions `needle`.
func _row_with_text(container: Node, needle: String) -> Node:
	for row in container.get_children():
		if row is HBoxContainer and _collect_text(row).contains(needle):
			return row
	return null


func _verify_sortie_page() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame

	var sp = ctrl.sortie_panel_ui
	_check(sp != null, "controller builds a HangarSortiePanel")
	_check(sp.sortie_panel != null, "sortie panel builds its root panel")
	_check(sp.sortie_list != null, "sortie panel builds the row list")
	_check(sp.sortie_panel.visible == false, "sortie page starts hidden")

	ctrl.nav_panel.select_submenu("sortie")
	await get_tree().process_frame
	_check(sp.sortie_panel.visible, "sortie page shows the panel")
	_check(not ctrl.roster_panel_ui.roster_panel.visible, "sortie page hides the roster page")
	_check(not ctrl.pilots_panel_ui.pilots_panel.visible, "sortie page hides the pilots page")

	var text := _collect_text(sp.sortie_panel)
	_check(text.contains("SORTIE"), "sortie page has its title")
	# The default hangar starts with the player's active mech -> read-only badge.
	_check(_find_button_by_text(sp.sortie_list, "★ PILOTED") != null, "active mech shows the read-only ★ PILOTED badge")
	_check(_row_with_text(sp.sortie_list, "YOU (driver)") != null, "sortie lists the active mech's driver")

	# An unpiloted spare berth does not appear as a sortie row.
	var berths_before: int = sp.sortie_list.get_child_count()
	var spare := GlobalData.build_hangar_mech("Spare 02", 2)
	_check(not spare.is_empty(), "a spare berth can be parked for the sortie test")
	if not spare.is_empty():
		spare["pilot"] = ""
		GlobalData.save_run()
	sp.refresh()
	await get_tree().process_frame
	_check(sp.sortie_list.get_child_count() == berths_before, "unpiloted berth is not a sortie row")

	# A fleet pilot seated in the spare berth -> a toggleable row appears.
	var spare_id := str(spare.get("id", ""))
	if spare_id != "":
		GlobalData.assign_hangar_pilot(spare_id, "fleet_t_sp")
		GlobalData.fleet_roster.append({"template_id": "t_sp", "name": "Sortie Sam", "hp": 60.0, "max_hp": 80.0, "destroyed": false, "fielded": true})
		GlobalData.save_run()
	sp.refresh()
	await get_tree().process_frame
	_check(sp.sortie_list.get_child_count() == berths_before + 1, "seated pilot becomes a sortie row")
	text = _collect_text(sp.sortie_panel)
	_check(text.contains("Sortie Sam"), "sortie row names the seated pilot")

	ctrl.queue_free()
	await get_tree().process_frame


func _verify_fielding() -> void:
	GlobalData.reset_run_data()
	var ctrl: Node = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(ctrl)
	await get_tree().process_frame
	await get_tree().process_frame
	var sp = ctrl.sortie_panel_ui
	ctrl.nav_panel.select_submenu("sortie")
	await get_tree().process_frame

	# Grow the convoy so there are berths for every test pilot (each added fleet
	# unit expands capacity: 3 pilots -> 2 trucks -> 8 berths).
	GlobalData.fleet_roster.append({"template_id": "t_fd", "name": "Fielded Fran", "hp": 50.0, "max_hp": 100.0, "destroyed": false, "fielded": true})
	GlobalData.fleet_roster.append({"template_id": "t_fw", "name": "Wanda Wound", "hp": 20.0, "max_hp": 80.0, "destroyed": false, "fielded": true, "wounded": true, "wound_turns": 2})
	GlobalData.fleet_roster.append({"template_id": "t_fx", "name": "Dan Dead", "hp": 0.0, "max_hp": 80.0, "destroyed": true, "fielded": true})
	# Park one spare berth per pilot and seat each fleet pilot.
	var seat_map := [
		{"template_id": "t_fd", "slot": 2},
		{"template_id": "t_fw", "slot": 3},
		{"template_id": "t_fx", "slot": 4},
	]
	for entry in seat_map:
		var m := GlobalData.build_hangar_mech("Spare %02d" % entry["slot"], entry["slot"])
		if not m.is_empty():
			GlobalData.assign_hangar_pilot(str(m.get("id", "")), "fleet_%s" % entry["template_id"])
	sp.refresh()
	await get_tree().process_frame

	# Healthy fielded pilot: enabled FIELDED toggle; pressing stands them down.
	var row := _row_with_text(sp.sortie_list, "Fielded Fran")
	_check(row != null, "fielded pilot appears as a sortie row")
	var field_btn: Button = _find_button_by_text(row, "FIELDED") if row else null
	_check(field_btn != null and not field_btn.disabled, "healthy pilot gets an enabled FIELDED toggle")
	if field_btn:
		field_btn.pressed.emit()
		await get_tree().process_frame
	var unit := GlobalData.get_fleet_unit("t_fd")
	_check(not bool(unit.get("fielded", true)), "pressing FIELDED stands the pilot down")
	row = _row_with_text(sp.sortie_list, "Fielded Fran")
	_check(_find_button_by_text(row, "STANDING DOWN") != null, "row shows STANDING DOWN after the toggle")

	# Standing down again -> fielded again.
	var stand_btn: Button = _find_button_by_text(row, "STANDING DOWN") if row else null
	if stand_btn:
		stand_btn.pressed.emit()
		await get_tree().process_frame
	unit = GlobalData.get_fleet_unit("t_fd")
	_check(bool(unit.get("fielded", true)), "pressing STANDING DOWN re-fields the pilot")

	# Wounded pilot: toggle is locked (still seated, recovering).
	row = _row_with_text(sp.sortie_list, "Wanda Wound")
	_check(row != null, "wounded pilot still appears as a sortie row")
	var w_btn: Button = _find_button_by_text(row, "FIELDED") if row else null
	if w_btn == null:
		w_btn = _find_button_by_text(row, "STANDING DOWN") if row else null
	_check(w_btn != null and w_btn.disabled, "wounded pilot's toggle is disabled")
	_check(bool(GlobalData.get_fleet_unit("t_fw").get("wounded", false)), "wounded pilot stays wounded")

	# Destroyed pilot: toggle is disabled.
	row = _row_with_text(sp.sortie_list, "Dan Dead")
	var d_btn: Button = _find_button_by_text(row, "FIELDED") if row else null
	if d_btn == null:
		d_btn = _find_button_by_text(row, "STANDING DOWN") if row else null
	_check(d_btn != null and d_btn.disabled, "destroyed pilot's toggle is disabled")

	# Feature 7: a template-only unit (no seated berth) is not offered at all.
	GlobalData.fleet_roster.append({"template_id": "t_lone", "name": "Lonely Lou", "hp": 50.0, "max_hp": 80.0, "destroyed": false, "fielded": true})
	sp.refresh()
	await get_tree().process_frame
	_check(_row_with_text(sp.sortie_list, "Lonely Lou") == null, "pilot-less template unit is not a sortie row")

	ctrl.queue_free()
	await get_tree().process_frame