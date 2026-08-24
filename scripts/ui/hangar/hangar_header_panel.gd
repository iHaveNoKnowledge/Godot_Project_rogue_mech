class_name HangarHeaderPanel
extends RefCounted
# Owns the hangar's top header bar construction:
#   * title + selection label
#   * the mech-slot badge (delegates to the roster panel's build_badge_header)
#   * the slot tab buttons (HEAD/BODY/L.ARM/... / BACK CARRY) which drive
#     HangarSlotPanel.select() and are stored for the garage panel's blink
#   * the BACK TO MENU button (routes to HangarNavPanel)
#
# All node handles stay owned by the controller; this panel only builds them
# and wires the signals through `controller.`.

var controller  # hangar_controller.gd


# Build the header into `root` (the full-rect RootControl).
func build(root: Control) -> void:
	# Top Header Bar
	var header = PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, 80)
	root.add_child(header)
	header.mouse_filter = Control.MOUSE_FILTER_PASS

	var style_hdr = StyleBoxFlat.new()
	style_hdr.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	header.add_theme_stylebox_override("panel", style_hdr)

	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header.add_child(header_vbox)

	var hdr_box = HBoxContainer.new()
	hdr_box.add_theme_constant_override("separation", 15)
	header_vbox.add_child(hdr_box)

	var title_lbl = Label.new()
	title_lbl.text = " 🛠️ 3D MECHA GARAGE "
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	hdr_box.add_child(title_lbl)

	var selection_label = Label.new()
	selection_label.name = "SelectionLabel"
	selection_label.text = "EDITING: CHASSIS"
	selection_label.add_theme_font_size_override("font_size", 14)
	selection_label.add_theme_color_override("font_color", Color(0.25, 0.9, 1.0))
	hdr_box.add_child(selection_label)

	# Mech-slot switcher (badge + prev/next) lives in the roster panel.
	controller.roster_panel_ui.build_badge_header(hdr_box)

	controller.tab_container = HBoxContainer.new()
	controller.tab_container.add_theme_constant_override("separation", 4)
	hdr_box.add_child(controller.tab_container)

	var slots = [
		{"id": "head", "label": "HEAD"},
		{"id": "body", "label": "BODY"},
		{"id": "arm_left", "label": "L.ARM"},
		{"id": "arm_right", "label": "R.ARM"},
		{"id": "leg_left", "label": "L.LEGS"},
		{"id": "leg_right", "label": "R.LEGS"},
		{"id": "weapon_left", "label": "L.HAND"},
		{"id": "weapon_right", "label": "R.HAND"},
		{"id": "weapon_carry", "label": "BACK CARRY"}
	]

	for slot_info in slots:
		var btn = Button.new()
		btn.text = slot_info["label"]
		btn.custom_minimum_size = Vector2(72, 36)
		btn.pressed.connect(func(): if controller.slot_panel: controller.slot_panel.select(slot_info["id"]))
		controller.slot_tab_buttons[slot_info["id"]] = btn
		controller.tab_container.add_child(btn)

	# Spacer pushes the back-to-menu button to the far right of the header.
	var hdr_spacer = Control.new()
	hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_box.add_child(hdr_spacer)

	controller.back_to_menu_button = Button.new()
	controller.back_to_menu_button.text = "◀ BACK TO MENU"
	controller.back_to_menu_button.custom_minimum_size = Vector2(150, 32)
	controller.back_to_menu_button.focus_mode = Control.FOCUS_NONE
	controller.back_to_menu_button.pressed.connect(func(): if controller.nav_panel: controller.nav_panel.on_back_to_menu_pressed())
	controller.back_to_menu_button.visible = false
	hdr_box.add_child(controller.back_to_menu_button)

	# Row 2: Sub-Mode Toggle Bar directly beneath part selector
	controller.sub_toggle_container = HBoxContainer.new()
	controller.sub_toggle_container.add_theme_constant_override("separation", 8)
	header_vbox.add_child(controller.sub_toggle_container)

	_build_mode_buttons()


var mode_buttons: Dictionary = {}


func _build_mode_buttons() -> void:
	var mode_items = [
		{"id": "armor", "label": "🛡️ OUTER ARMOR", "color": Color(0.25, 0.90, 1.0), "bg": Color(0.12, 0.22, 0.35, 0.95)},
		{"id": "frame", "label": "⚙️ INNER FRAME", "color": Color(0.25, 0.95, 0.60), "bg": Color(0.10, 0.25, 0.18, 0.95)},
		{"id": "attachment", "label": "🔩 FRAME PROPERTIES & MODS", "color": Color(1.0, 0.85, 0.30), "bg": Color(0.28, 0.22, 0.08, 0.95)},
		{"id": "upgrade", "label": "⚡ REACTOR UPGRADE", "color": Color(0.85, 0.45, 1.0), "bg": Color(0.24, 0.10, 0.30, 0.95)}
	]

	mode_buttons = {}
	if controller:
		controller.mode_buttons = mode_buttons

	for item in mode_items:
		var btn := Button.new()
		btn.text = item["label"]
		btn.custom_minimum_size = Vector2(175, 30)
		btn.focus_mode = Control.FOCUS_NONE
		var m_id: String = item["id"]
		btn.pressed.connect(func(): if controller.nav_panel: controller.nav_panel.switch_custom_mode(m_id))
		mode_buttons[m_id] = btn
		controller.sub_toggle_container.add_child(btn)
		if m_id == "upgrade":
			controller.frame_upgrade_button = btn

	update_mode_highlights(controller.current_mode if "current_mode" in controller else "armor")


func update_mode_highlights(active_mode: String) -> void:
	var target_buttons: Dictionary = controller.mode_buttons if ("mode_buttons" in controller and controller.mode_buttons != null and not controller.mode_buttons.is_empty()) else mode_buttons
	if target_buttons.is_empty():
		return

	var mode_configs = {
		"armor": {"border": Color(0.25, 0.90, 1.0), "bg": Color(0.12, 0.22, 0.35, 0.95)},
		"frame": {"border": Color(0.25, 0.95, 0.60), "bg": Color(0.10, 0.25, 0.18, 0.95)},
		"attachment": {"border": Color(1.0, 0.85, 0.30), "bg": Color(0.28, 0.22, 0.08, 0.95)},
		"upgrade": {"border": Color(0.85, 0.45, 1.0), "bg": Color(0.24, 0.10, 0.30, 0.95)}
	}

	for m_id: String in target_buttons:
		var btn: Button = target_buttons[m_id]
		var is_active: bool = (m_id == active_mode)
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3

		if is_active:
			var cfg = mode_configs.get(m_id, {"border": Color(0.4, 0.8, 1.0), "bg": Color(0.15, 0.2, 0.3)})
			style.bg_color = cfg["bg"]
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = cfg["border"]
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			style.bg_color = Color(0.14, 0.15, 0.18, 0.9)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.3, 0.35, 0.42, 0.6)
			btn.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))

		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(st, style)


func update_header() -> void:
	if controller and controller.has_node("RootControl/PanelContainer/VBoxContainer/HBoxContainer/SelectionLabel"):
		var lbl = controller.get_node_or_null("RootControl/PanelContainer/VBoxContainer/HBoxContainer/SelectionLabel") as Label
		if lbl and "selected_slot" in controller:
			lbl.text = "EDITING: %s" % str(controller.selected_slot).to_upper()
	if controller and "roster_panel_ui" in controller and controller.roster_panel_ui and controller.roster_panel_ui.has_method("refresh_badge_header"):
		controller.roster_panel_ui.refresh_badge_header()
	update_mode_highlights(controller.current_mode if ("current_mode" in controller) else "armor")
