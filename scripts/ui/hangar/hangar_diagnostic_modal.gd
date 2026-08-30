class_name HangarDiagnosticModal
extends RefCounted

## Interactive Telemetry & Diagnostic Report for Hangar.
## Pinpoints exact root-causes for penalties (speed reduction, dash stutter, recoil kick, etc.),
## displays 6-part Armor & Frame integrity meters, and provides one-click
## [ JUMP TO PART ], [ REPAIR ], and [ OVERHAUL ] navigation.

var controller: Node # hangar_controller.gd
var modal_panel: Control = null
var is_open: bool = false


func close() -> void:
	is_open = false
	if modal_panel != null and is_instance_valid(modal_panel):
		modal_panel.queue_free()
		modal_panel = null
	if controller and controller.root_control:
		for child in controller.root_control.get_children():
			if child.name == "DiagnosticModal" or child.name.begins_with("DiagnosticModal") or child.name.begins_with("@DiagnosticModal"):
				child.queue_free()
	if controller:
		var local_old = controller.get_node_or_null("DiagnosticModal")
		if local_old:
			local_old.queue_free()
	modal_panel = null


func open() -> void:
	close()
	is_open = true

	modal_panel = PanelContainer.new()
	modal_panel.name = "DiagnosticModal"
	modal_panel.anchor_left = 0.5
	modal_panel.anchor_right = 0.5
	modal_panel.anchor_top = 0.5
	modal_panel.anchor_bottom = 0.5
	modal_panel.offset_left = -460
	modal_panel.offset_right = 460
	modal_panel.offset_top = -320
	modal_panel.offset_bottom = 320
	modal_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.08, 0.12, 0.97)
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.3, 0.65, 0.95, 0.85)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	bg_style.content_margin_left = 16
	bg_style.content_margin_right = 16
	bg_style.content_margin_top = 12
	bg_style.content_margin_bottom = 12
	modal_panel.add_theme_stylebox_override("panel", bg_style)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	modal_panel.add_child(main_vbox)

	# 1. Header Bar
	var hdr_box := HBoxContainer.new()
	main_vbox.add_child(hdr_box)

	var title_lbl := Label.new()
	title_lbl.text = "🛰️ MECHA TELEMETRY & DIAGNOSTIC REPORT"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	hdr_box.add_child(title_lbl)

	var hdr_spacer := Control.new()
	hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_box.add_child(hdr_spacer)

	var close_hdr_btn := Button.new()
	close_hdr_btn.text = "✕ CLOSE"
	close_hdr_btn.custom_minimum_size = Vector2(80, 26)
	close_hdr_btn.pressed.connect(close)
	hdr_box.add_child(close_hdr_btn)

	var sub_lbl := Label.new()
	var pilot_name = controller.stats_panel._editing_pilot_name() if controller.stats_panel else "Pilot"
	var active_penalties = PartPenaltySystem.active_penalties()
	var pen_summary = "[color=#44ff77]✓ ALL SYSTEMS OPTIMAL (0 Malfunctions)[/color]" if active_penalties.is_empty() else "[color=#ff5555]⚠ %d ACTIVE MALFUNCTIONS DETECTED[/color]" % active_penalties.size()
	sub_lbl.text = "Diagnostic Scan for Pilot: %s  |  Status: %s" % [pilot_name, "OPTIMAL" if active_penalties.is_empty() else "%d DEBUFFS DETECTED" % active_penalties.size()]
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	main_vbox.add_child(sub_lbl)

	var sep1 := HSeparator.new()
	main_vbox.add_child(sep1)

	# 2. Scrollable 6-Slot Diagnosis List
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var slots_vbox := VBoxContainer.new()
	slots_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(slots_vbox)

	var slot_meta = [
		{"id": "head", "name": "HEAD", "desc": "Optics, Targeting Sensors & HUD Core"},
		{"id": "body", "name": "BODY / TORSO", "desc": "Power Core Reactor, Heat Sinks & Cockpit"},
		{"id": "arm_left", "name": "LEFT ARM", "desc": "Primary Weapon Gimbal & Melee Servos"},
		{"id": "arm_right", "name": "RIGHT ARM", "desc": "Secondary Weapon Gimbal & Heavy Mount"},
		{"id": "leg_left", "name": "LEFT LEG", "desc": "Suspension, Roller Dash & Walk Actuators"},
		{"id": "leg_right", "name": "RIGHT LEG", "desc": "Suspension, Roller Dash & Walk Actuators"}
	]

	var total_repair_cost: int = 0

	for sm in slot_meta:
		var s_id: String = sm["id"]
		var row_card := _build_slot_diagnostic_card(s_id, sm["name"], sm["desc"])
		slots_vbox.add_child(row_card)
		total_repair_cost += RepairSystem.get_repair_cost(s_id)

	var sep2 := HSeparator.new()
	main_vbox.add_child(sep2)

	# 3. Bottom Action Footer
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(footer_hbox)

	var full_repair_btn := Button.new()
	full_repair_btn.text = "🛠️ REPAIR ENTIRE MECH (%d cr)" % total_repair_cost if total_repair_cost > 0 else "✓ ENTIRE MECH FULLY REPAIRED (0 cr)"
	full_repair_btn.disabled = total_repair_cost <= 0
	full_repair_btn.custom_minimum_size = Vector2(250, 36)
	full_repair_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if total_repair_cost > 0 else Color(0.6, 0.6, 0.6))
	full_repair_btn.pressed.connect(func():
		if GlobalData.currency.try_spend_credits(total_repair_cost):
			for sm in slot_meta:
				var s: String = sm["id"]
				GlobalData.weapons.part_damage.erase(s)
				GlobalData.weapons.part_damage.erase(s + "_frame")
				GlobalData.weapons.part_hit_meta.erase(s)
			GlobalData.save_run()
			var msg := "Entire Mech Repaired to Full Combat HP!"
			controller.status_message_label.text = msg
			if controller.has_method("show_toast"):
				controller.show_toast(msg, false)
			controller.refresh_after_part_mutation(controller.selected_slot)
			open() # Refresh modal
		else:
			var err := "Insufficient credits for full repair (%d cr needed)!" % total_repair_cost
			controller.status_message_label.text = err
			if controller.has_method("show_toast"):
				controller.show_toast(err, true)
	)
	footer_hbox.add_child(full_repair_btn)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

	var close_bottom_btn := Button.new()
	close_bottom_btn.text = "CLOSE"
	close_bottom_btn.custom_minimum_size = Vector2(120, 36)
	close_bottom_btn.pressed.connect(close)
	footer_hbox.add_child(close_bottom_btn)

	controller.root_control.add_child(modal_panel)


func _build_slot_diagnostic_card(slot: String, slot_title: String, slot_sub: String) -> PanelContainer:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.09, 0.11, 0.15, 0.9)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_left = 3
	card_style.corner_radius_top_right = 3
	card_style.corner_radius_bottom_left = 3
	card_style.corner_radius_bottom_right = 3
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8

	var armor_dmg := clampf(float(GlobalData.weapons.part_damage.get(slot, 0.0)), 0.0, 1.0)
	var frame_dmg := clampf(float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
	var combined_dmg := maxf(armor_dmg, frame_dmg)

	var equipped_armor = GlobalData.weapons.equipped_parts.get(slot)
	var armor_name = equipped_armor.get("name", equipped_armor.get("part_name", "Outer Armor")) if equipped_armor is Dictionary else "(No Armor)"
	var armor_max_hp: float = float(GlobalData.weapons.part_stat(equipped_armor, "max_hp", 30.0))
	var armor_cur_hp: float = armor_max_hp * (1.0 - armor_dmg)

	var equipped_frame = GlobalData.weapons.equipped_frames.get(slot)
	var frame_name = equipped_frame.get("name", equipped_frame.get("part_name", "Inner Frame")) if equipped_frame is Dictionary else "Standard Frame"
	var frame_max_hp: float = float(GlobalData.weapons.part_stat(equipped_frame, "max_hp", 40.0))
	var frame_cur_hp: float = frame_max_hp * (1.0 - frame_dmg)

	var penalties_for_slot := _get_penalties_for_slot(slot, combined_dmg)
	var is_degraded := combined_dmg >= PartPenaltySystem.THRESHOLD_MILD

	if combined_dmg >= PartPenaltySystem.THRESHOLD_SEVERE:
		card_style.border_color = Color(1.0, 0.25, 0.25, 0.9)
	elif is_degraded:
		card_style.border_color = Color(1.0, 0.75, 0.25, 0.8)
	else:
		card_style.border_color = Color(0.2, 0.35, 0.5, 0.5)

	card.add_theme_stylebox_override("panel", card_style)

	var row_hbox := HBoxContainer.new()
	row_hbox.add_theme_constant_override("separation", 12)
	card.add_child(row_hbox)

	# Left Column: Slot Name & Subtitle
	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(210, 0)
	left_vbox.add_theme_constant_override("separation", 2)
	row_hbox.add_child(left_vbox)

	var status_icon := "🔴 " if combined_dmg >= PartPenaltySystem.THRESHOLD_SEVERE else ("🟡 " if is_degraded else "🟢 ")
	var title_l := Label.new()
	title_l.text = "%s%s" % [status_icon, slot_title]
	title_l.add_theme_font_size_override("font_size", 13)
	title_l.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4) if combined_dmg >= PartPenaltySystem.THRESHOLD_SEVERE else (Color(1.0, 0.85, 0.3) if is_degraded else Color(0.4, 0.95, 0.5)))
	left_vbox.add_child(title_l)

	var desc_l := Label.new()
	desc_l.text = slot_sub
	desc_l.add_theme_font_size_override("font_size", 10)
	desc_l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	left_vbox.add_child(desc_l)

	# Middle Column: Health Meters & Specific Symptom Breakdown
	var mid_vbox := VBoxContainer.new()
	mid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_vbox.add_theme_constant_override("separation", 4)
	row_hbox.add_child(mid_vbox)

	# HP Bars
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 16)
	mid_vbox.add_child(hp_row)

	var a_bar = HPPartBar.create_row("Armor", armor_cur_hp, armor_max_hp, false, false, 140, 8, 10)
	hp_row.add_child(a_bar)

	var f_bar = HPPartBar.create_row("Frame", frame_cur_hp, frame_max_hp, true, false, 140, 8, 10)
	hp_row.add_child(f_bar)

	# Symptom Label
	var sym_lbl := RichTextLabel.new()
	sym_lbl.bbcode_enabled = true
	sym_lbl.fit_content = true
	sym_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if penalties_for_slot.is_empty():
		sym_lbl.text = "[color=#44ff77]✓ Optimal: Operating at 100% combat performance.[/color]"
	else:
		sym_lbl.text = "[color=#ff6666]" + "\n".join(penalties_for_slot) + "[/color]"
	mid_vbox.add_child(sym_lbl)

	# Right Column: Action Buttons (Jump to Part, Quick Repair, Quick Overhaul)
	var act_vbox := VBoxContainer.new()
	act_vbox.custom_minimum_size = Vector2(170, 0)
	act_vbox.add_theme_constant_override("separation", 4)
	row_hbox.add_child(act_vbox)

	var jump_btn := Button.new()
	jump_btn.text = "🎯 JUMP TO SLOT"
	jump_btn.custom_minimum_size = Vector2(165, 26)
	jump_btn.pressed.connect(func():
		controller.slot_panel.select(slot)
		close()
	)
	act_vbox.add_child(jump_btn)

	var r_cost := RepairSystem.get_repair_cost(slot)
	if r_cost > 0:
		var rep_btn := Button.new()
		rep_btn.text = "🔧 REPAIR (%d cr)" % r_cost
		rep_btn.custom_minimum_size = Vector2(165, 26)
		rep_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		rep_btn.pressed.connect(func():
			if GlobalData.currency.try_spend_credits(r_cost):
				GlobalData.weapons.part_damage.erase(slot)
				GlobalData.weapons.part_damage.erase(slot + "_frame")
				GlobalData.weapons.part_hit_meta.erase(slot)
				var msg := "%s Repaired to Full Combat HP!" % slot_title
				controller.status_message_label.text = msg
				if controller.has_method("show_toast"):
					controller.show_toast(msg, false)
				GlobalData.save_run()
				controller.refresh_after_part_mutation(slot)
				open() # refresh
			else:
				var err := "Insufficient credits for repair (%d cr needed)!" % r_cost
				controller.status_message_label.text = err
				if controller.has_method("show_toast"):
					controller.show_toast(err, true)
		)
		act_vbox.add_child(rep_btn)

	return card


func _get_penalties_for_slot(slot: String, combined_dmg: float) -> Array[String]:
	var list: Array[String] = []
	match slot:
		"head":
			if combined_dmg >= PartPenaltySystem.THRESHOLD_MILD:
				var sp = PartPenaltySystem.head_spread_penalty() * 100.0
				var lck = int(round((1.0 - PartPenaltySystem.head_lock_on_multiplier()) * 100.0))
				list.append("• ⚠ Optics Failure: Weapon Spread +%.0f%%" % sp)
				list.append("• ⚠ Sensor Glitch: Lock-On Speed -%d%%" % lck)
			if combined_dmg >= PartPenaltySystem.HEAD_HUD_GLITCH_THRESHOLD:
				list.append("• ⚠ HUD Interference: Static scanlines active")
		"body":
			if combined_dmg >= PartPenaltySystem.THRESHOLD_MILD:
				var e_loss = int(round((1.0 - PartPenaltySystem.torso_energy_multiplier()) * 100.0))
				var h_stress = int(round((PartPenaltySystem.torso_heat_multiplier() - 1.0) * 100.0))
				list.append("• ⚠ Core Stress: Max Boost Energy -%d%%" % e_loss)
				list.append("• ⚠ Thermal Breach: Heat Accumulation +%d%%" % h_stress)
		"arm_left", "arm_right":
			if combined_dmg >= PartPenaltySystem.THRESHOLD_MILD:
				var r_gain = int(round((PartPenaltySystem.arm_recoil_multiplier() - 1.0) * 100.0))
				var m_loss = int(round((1.0 - PartPenaltySystem.arm_melee_speed_multiplier()) * 100.0))
				list.append("• ⚠ Gimbal Wobble: Weapon Recoil +%d%%" % r_gain)
				list.append("• ⚠ Servo Strain: Melee Attack Cadence -%d%%" % m_loss)
			if combined_dmg >= PartPenaltySystem.ARM_HEAVY_THRESHOLD:
				list.append("• ✖ Arm Integrity Critical: Cannot wield Heavy Weapons")
		"leg_left", "leg_right":
			if combined_dmg >= PartPenaltySystem.THRESHOLD_MILD:
				var s_loss = int(round((1.0 - PartPenaltySystem.leg_speed_multiplier()) * 100.0))
				list.append("• ⚠ Actuator Damage: Walk Speed -%d%%" % s_loss)
			if combined_dmg >= PartPenaltySystem.THRESHOLD_MODERATE:
				var d_loss = int(round((1.0 - PartPenaltySystem.leg_dash_multiplier()) * 100.0))
				list.append("• ⚠ Thruster Stutter: Roller Dash Speed -%d%% & malfunction" % d_loss)
	return list
