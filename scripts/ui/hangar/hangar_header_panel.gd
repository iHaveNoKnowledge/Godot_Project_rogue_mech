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
