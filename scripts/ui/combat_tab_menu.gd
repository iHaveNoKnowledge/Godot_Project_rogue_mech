extends CanvasLayer

## COMBAT TAB MENU — opens with TAB during battle (mech or eject/pilot mode).
## Lists battlefield actions; "Call Reserve Mech" shows the free hangar mechs
## that are not currently in this battle, and picking one starts the 30s
## edge-delivery via BackupMechSpawner. Future actions land in the same list.

const RESERVE_DELIVERY_TIME := 30.0

var _root: Control = null
var _menu_list: VBoxContainer = null
var _spawner: Node = null
var _open: bool = false

# Free mechs shown in the reserve sub-view: [{mech_id, name, pilot_name}].
var _free_mechs: Array = []


func _ready() -> void:
	layer = 30
	visible = false
	_build_ui()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("combat_menu"):
		return
	if GameManager.current_state != GameManager.State.COMBAT \
			and GameManager.current_state != GameManager.State.EJECT:
		return
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main_menu()


func close() -> void:
	_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -260
	panel.offset_bottom = 260
	_root.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.97)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.35, 0.65, 1.0, 0.55)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "FIELD COMMAND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "TAB to close — battlefield actions"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	vbox.add_child(hint)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_menu_list)

	# Fixed footer note shown on the main menu.
	var footer := Label.new()
	footer.name = "FooterNote"
	footer.text = ""
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))
	vbox.add_child(footer)


func _clear_menu() -> void:
	for child in _menu_list.get_children():
		child.queue_free()


func _make_button(text: String, accent: Color, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 40)
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not enabled
	if enabled:
		btn.add_theme_color_override("font_color", accent)
	return btn


# Main list: Call Reserve Mech + placeholders for future actions.
func _show_main_menu() -> void:
	_clear_menu()

	var reserve_btn := _make_button("CALL RESERVE MECH", Color(0.5, 0.9, 1.0), true)
	reserve_btn.tooltip_text = "Drop a spare hangar mech at the arena edge (%ds delivery)." % RESERVE_DELIVERY_TIME
	reserve_btn.pressed.connect(_show_reserve_list)
	_menu_list.add_child(reserve_btn)

	# Future battlefield actions — kept as disabled placeholders so the menu
	# already reads as a command list.
	var placeholders := [
		"SUPPLY DROP — COMING SOON",
		"ARTILLERY SUPPORT — COMING SOON",
		"SQUAD ORDERS — COMING SOON",
	]
	for text in placeholders:
		var btn := _make_button(text, Color(0.45, 0.5, 0.6), false)
		_menu_list.add_child(btn)

	var footer := _menu_list.get_parent().get_node_or_null("FooterNote")
	if footer:
		footer.text = ""


# Reserve sub-view: the free hangar mechs (not active, not already fielded in
# this battle). Empty roster -> empty window message.
func _show_reserve_list() -> void:
	_clear_menu()
	_free_mechs = _collect_free_mechs()

	var back := _make_button("< BACK", Color(0.75, 0.8, 0.9), true)
	back.pressed.connect(_show_main_menu)
	_menu_list.add_child(back)

	var title := Label.new()
	title.text = "FREE MECHS — pick one to drop in"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	_menu_list.add_child(title)

	if _free_mechs.is_empty():
		var empty := Label.new()
		empty.text = "No free mechs in the hangar.\nEvery parked machine is already on this battlefield."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		_menu_list.add_child(empty)
		return

	for entry in _free_mechs:
		var name := str(entry.get("name", "Mech"))
		var pilot := str(entry.get("pilot_name", ""))
		var label := name if pilot == "" else "%s — %s" % [name, pilot]
		var btn := _make_button("DROP ▸ %s" % label, Color(0.6, 0.95, 0.7), true)
		btn.pressed.connect(_call_reserve.bind(str(entry.get("mech_id", ""))))
		_menu_list.add_child(btn)

	var footer := _menu_list.get_parent().get_node_or_null("FooterNote")
	if footer:
		footer.text = "Delivery: ~%ds to the arena edge. The mech arrives empty (no pilot)." % RESERVE_DELIVERY_TIME


# Free = a hangar mech that is NOT the active mech and NOT one of the allies
# already fighting in this battle (sortie units). Driverless or piloted — any
# parked machine not on the field can be called in.
func _collect_free_mechs() -> Array:
	var active_id := str(GlobalData.get_active_hangar_mech().get("id", ""))
	var fielded_ids: Dictionary = {}
	for entry in FleetSystem.get_sortie_units():
		var mech: Dictionary = entry.get("mech", {})
		fielded_ids[str(mech.get("id", ""))] = true

	var result: Array = []
	for mech in GlobalData.get_hangar_mechs():
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		if mech_id == "" or mech_id == active_id:
			continue
		if fielded_ids.has(mech_id):
			continue
		var pilot_id := str(mech.get("pilot", ""))
		result.append({
			"mech_id": mech_id,
			"name": str(mech.get("name", "Mech")),
			"pilot_name": GlobalData.get_hangar_mech_pilot_name(mech_id),
		})
	return result


func _call_reserve(mech_id: String) -> void:
	if _spawner == null:
		_spawner = get_tree().current_scene.get_node_or_null("BackupMechSpawner")
	if _spawner == null or not _spawner.has_method("call_reserve_mech"):
		return
	_spawner.call_reserve_mech(mech_id)
	close()
