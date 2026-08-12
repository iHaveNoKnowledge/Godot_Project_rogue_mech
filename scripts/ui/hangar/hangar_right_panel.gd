class_name HangarRightPanel
extends RefCounted
# Owns the hangar's right sidebar (stats & frame core power panel) build:
#   * the per-slot stats label + hover preview (catalog panel builds its label)
#   * the FRAME VS ARMOR weight bar + total stats label (HangarStatsPanel paints)
#   * the repair buttons (route to HangarRepairPanel)
#   * the roster page root build (HangarRosterPanel)
#   * the status message label + EXIT HANGAR button (routes to the controller)
#
# All node handles stay owned by the controller; this panel only builds them
# and wires the signals through `controller.`.

var controller  # hangar_controller.gd


# Build the right sidebar into `root` (the full-rect RootControl).
func build(root: Control) -> void:
	# Right Sidebar (Stats & Gundam Frame Core Power Panel)
	var right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.offset_top = 128
	right_panel.offset_bottom = -20
	right_panel.offset_right = -20
	right_panel.offset_left = -370
	right_panel.custom_minimum_size = Vector2(350, 0)
	controller.right_panel = right_panel
	root.add_child(right_panel)

	var style_right = StyleBoxFlat.new()
	style_right.bg_color = Color(0.08, 0.1, 0.15, 0.88)
	style_right.corner_radius_top_right = 8
	style_right.corner_radius_bottom_right = 8
	style_right.content_margin_left = 14
	style_right.content_margin_right = 14
	style_right.content_margin_top = 14
	style_right.content_margin_bottom = 14
	right_panel.add_theme_stylebox_override("panel", style_right)

	var right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

	var stats_title = Label.new()
	stats_title.text = "GUNDAM FRAME CORE SPECIFICATIONS"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	right_box.add_child(stats_title)

	controller.stats_label = Label.new()
	controller.stats_label.text = "Select a chassis, frame, or armor to view specifications"
	controller.stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(controller.stats_label)

	# Hover preview (title + stat card) lives in the catalog panel.
	controller.catalog_panel.build_hover_stats_label(right_box)

	var sep = HSeparator.new()
	right_box.add_child(sep)

	var total_title = Label.new()
	total_title.text = "FRAME VS. ARMOR DUAL CAPACITY"
	total_title.add_theme_font_size_override("font_size", 13)
	right_box.add_child(total_title)

	controller.weight_bar = ProgressBar.new()
	controller.weight_bar.custom_minimum_size = Vector2(0, 22)
	controller.weight_bar.max_value = 85.0
	right_box.add_child(controller.weight_bar)

	controller.total_stats_label = Label.new()
	controller.total_stats_label.text = "FRAME HP: 150 | ARMOR HP: 210\nTOTAL WEIGHT: 42.0 / 75.0 kg"
	right_box.add_child(controller.total_stats_label)

	var sep2 = HSeparator.new()
	right_box.add_child(sep2)

	controller.repair_part_button = Button.new()
	controller.repair_part_button.text = "Repair Selected Slot"
	controller.repair_part_button.pressed.connect(func(): if controller.repair_panel: controller.repair_panel.repair_part())
	right_box.add_child(controller.repair_part_button)

	controller.full_repair_button = Button.new()
	controller.full_repair_button.text = "Full Field Repair"
	controller.full_repair_button.pressed.connect(func(): if controller.repair_panel: controller.repair_panel.full_repair())
	right_box.add_child(controller.full_repair_button)

	# Mech roster page (parking grid) lives in the roster panel.
	controller.roster_panel_ui.build(root)

	controller.status_message_label = Label.new()
	controller.status_message_label.text = ""
	controller.status_message_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	right_box.add_child(controller.status_message_label)

	if controller.ammo_panel:
		controller.ammo_panel.status_label = controller.status_message_label

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(spacer)

	controller.close_button = Button.new()
	controller.close_button.text = "EXIT HANGAR"
	controller.close_button.custom_minimum_size = Vector2(0, 44)
	controller.close_button.pressed.connect(controller._on_close_pressed)
	right_box.add_child(controller.close_button)
