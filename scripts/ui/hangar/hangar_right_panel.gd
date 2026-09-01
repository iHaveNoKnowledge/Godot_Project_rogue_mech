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
	# Right Sidebar (Stats & Valkyrion Frame Core Power Panel)
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
	style_right.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style_right.corner_radius_top_right = 0
	style_right.corner_radius_bottom_right = 0
	style_right.content_margin_left = 14
	style_right.content_margin_right = 14
	style_right.content_margin_top = 14
	style_right.content_margin_bottom = 14
	right_panel.add_theme_stylebox_override("panel", style_right)

	var right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

	var stats_title = Label.new()
	stats_title.text = "PART SPECIFICATIONS & INTEGRITY"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	right_box.add_child(stats_title)

	var rtl_stats := RichTextLabel.new()
	rtl_stats.bbcode_enabled = true
	rtl_stats.fit_content = true
	rtl_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl_stats.text = "Select a chassis, frame, or armor to view specifications"
	controller.stats_label = rtl_stats
	right_box.add_child(rtl_stats)

	var hp_bar_box = VBoxContainer.new()
	hp_bar_box.add_theme_constant_override("separation", 5)
	controller.stats_hp_bar_box = hp_bar_box
	right_box.add_child(hp_bar_box)

	# TIER box — the selected part's upgrade tier on the 1 -> 1.1 -> ... -> 2
	# ladder with four progress pips (filled toward the next whole tier).
	var tier_panel = PanelContainer.new()
	var tier_style = StyleBoxFlat.new()
	tier_style.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	tier_style.border_width_left = 1
	tier_style.border_width_top = 1
	tier_style.border_width_right = 1
	tier_style.border_width_bottom = 1
	tier_style.border_color = Color(0.4, 0.55, 0.75, 0.8)
	tier_style.corner_radius_top_left = 0
	tier_style.corner_radius_top_right = 0
	tier_style.corner_radius_bottom_left = 0
	tier_style.corner_radius_bottom_right = 0
	tier_style.content_margin_left = 10
	tier_style.content_margin_right = 10
	tier_style.content_margin_top = 8
	tier_style.content_margin_bottom = 8
	tier_panel.add_theme_stylebox_override("panel", tier_style)
	right_box.add_child(tier_panel)

	var tier_row = HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 14)
	tier_panel.add_child(tier_row)

	var tier_left = VBoxContainer.new()
	tier_row.add_child(tier_left)

	var tier_caption = Label.new()
	tier_caption.text = "TIER"
	tier_caption.add_theme_font_size_override("font_size", 10)
	tier_caption.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	tier_left.add_child(tier_caption)

	controller.tier_label = Label.new()
	controller.tier_label.text = "—"
	controller.tier_label.add_theme_font_size_override("font_size", 24)
	controller.tier_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	tier_left.add_child(controller.tier_label)

	controller.tier_pips_label = Label.new()
	controller.tier_pips_label.text = "○○○○"
	controller.tier_pips_label.add_theme_font_size_override("font_size", 15)
	controller.tier_pips_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	tier_left.add_child(controller.tier_pips_label)

	controller.tier_effect_label = Label.new()
	controller.tier_effect_label.text = ""
	controller.tier_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controller.tier_effect_label.custom_minimum_size = Vector2(90, 0)
	controller.tier_effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controller.tier_effect_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	controller.tier_effect_label.add_theme_font_size_override("font_size", 11)
	tier_row.add_child(controller.tier_effect_label)

	# Hover preview (title + stat card) lives in the catalog panel.
	controller.catalog_panel.build_hover_stats_label(right_box)

	var sep = HSeparator.new()
	right_box.add_child(sep)

	# Slot Actions Box (Repair Slot, Overhaul Slot, Full Repair)
	var actions_title = Label.new()
	actions_title.text = "SLOT MAINTENANCE & ACTIONS"
	actions_title.add_theme_font_size_override("font_size", 12)
	actions_title.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	right_box.add_child(actions_title)

	var actions_grid = GridContainer.new()
	actions_grid.columns = 2
	actions_grid.add_theme_constant_override("h_separation", 8)
	actions_grid.add_theme_constant_override("v_separation", 6)
	right_box.add_child(actions_grid)

	controller.repair_part_button = Button.new()
	controller.repair_part_button.text = "🔧 Repair Slot"
	controller.repair_part_button.custom_minimum_size = Vector2(150, 32)
	controller.repair_part_button.pressed.connect(func(): if controller.repair_panel: controller.repair_panel.repair_part())
	actions_grid.add_child(controller.repair_part_button)

	controller.overhaul_part_button = Button.new()
	controller.overhaul_part_button.text = "⚡ Overhaul Slot"
	controller.overhaul_part_button.custom_minimum_size = Vector2(150, 32)
	controller.overhaul_part_button.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	controller.overhaul_part_button.pressed.connect(func():
		var slot: String = controller.selected_slot
		if slot != "":
			var item_dur: float = 1.0
			if slot.begins_with("weapon"):
				var hand := "left" if slot == "weapon_left" else "right"
				item_dur = GlobalData.get_durability_ratio(LoadoutSystem.get_equipped_weapon(hand)) if LoadoutSystem.get_equipped_weapon(hand) else 1.0
			elif controller.current_mode == "frame":
				item_dur = GlobalData.get_frame_durability(slot)
			else:
				item_dur = GlobalData.get_part_durability(slot)

			if item_dur >= 0.999:
				controller.show_toast("%s is already at 100%% Durability!" % slot.to_upper(), false)
				return

			var lost_pct := 1.0 - item_dur
			var oh_cr: int = int(lost_pct * 80.0) + 20
			var oh_scrap: int = int(lost_pct * 15.0) + 5
			if GlobalData.currency.credits < oh_cr:
				controller.show_toast("Need %d credits for overhaul!" % oh_cr, true)
				return
			if GlobalData.currency.scrap < oh_scrap:
				controller.show_toast("Need %d scrap for overhaul!" % oh_scrap, true)
				return

			GlobalData.currency.try_spend_credits(oh_cr)
			GlobalData.currency.try_spend_scrap(oh_scrap)
			if slot.begins_with("weapon"):
				var hand := "left" if slot == "weapon_left" else "right"
				GlobalData.restore_weapon_durability(hand, 1.0)
			elif controller.current_mode == "frame":
				GlobalData.restore_frame_durability(slot, 1.0)
			else:
				GlobalData.restore_part_durability(slot, 1.0)

			GlobalData.weapons.part_damage.erase(slot)
			GlobalData.weapons.part_damage.erase(slot + "_frame")
			GlobalData.weapons.part_hit_meta.erase(slot)
			controller.show_toast("%s Overhauled to 100%% Durability!" % slot.to_upper(), false)
			GlobalData.save_run()
			controller.refresh_after_part_mutation(slot)
	)
	actions_grid.add_child(controller.overhaul_part_button)

	controller.full_repair_button = Button.new()
	controller.full_repair_button.text = "🛠️ Full Fleet Repair"
	controller.full_repair_button.custom_minimum_size = Vector2(0, 32)
	controller.full_repair_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controller.full_repair_button.pressed.connect(func(): if controller.repair_panel: controller.repair_panel.full_repair())
	right_box.add_child(controller.full_repair_button)

	# Mech roster page (parking grid) lives in the roster panel.
	controller.roster_panel_ui.build(root)

	controller.status_message_label = Label.new()
	controller.status_message_label.text = ""
	controller.status_message_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	right_box.add_child(controller.status_message_label)

	if "ammo_panel" in controller and controller.ammo_panel:
		controller.ammo_panel.status_label = controller.status_message_label

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(spacer)

	controller.close_button = Button.new()
	controller.close_button.text = "EXIT HANGAR"
	controller.close_button.custom_minimum_size = Vector2(0, 44)
	controller.close_button.pressed.connect(func(): if "exit_panel" in controller and controller.exit_panel: controller.exit_panel.close())
	right_box.add_child(controller.close_button)
