class_name HangarPilotsPanel
extends RefCounted

## PILOTS page: manages convoy pilot roster and player pilot skill progression / specialization.

const PilotSkillSys = preload("res://scripts/systems/pilot_skill_system.gd")
const PilotSkillCat = preload("res://scripts/systems/pilot_skill_catalog.gd")

var controller  # hangar_controller.gd

var pilots_panel: PanelContainer = null
var current_tab: String = "roster"  # "roster" or "skills"

# Tab Views
var tab_btn_roster: Button = null
var tab_btn_skills: Button = null
var roster_view: VBoxContainer = null
var skills_view: VBoxContainer = null

# Roster View Widgets
var pilot_list: VBoxContainer = null
var pilots_status_label: Label = null

# Skills View Widgets
var skills_header_label: Label = null
var xp_progress_bar: ProgressBar = null
var spec_container: VBoxContainer = null
var skills_scroll: ScrollContainer = null
var skills_grid: VBoxContainer = null


func build(root: Control) -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_top = 128
	panel.offset_bottom = -20
	panel.offset_left = 20
	panel.custom_minimum_size = Vector2(580, 0)
	panel.visible = false
	pilots_panel = panel
	root.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	style.corner_radius_top_left = 0
	style.corner_radius_bottom_left = 0
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	# --- Tab Navigation Bar ---
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	box.add_child(tab_bar)

	tab_btn_roster = Button.new()
	tab_btn_roster.text = "ROSTER (กองยาน)"
	tab_btn_roster.focus_mode = Control.FOCUS_NONE
	tab_btn_roster.custom_minimum_size = Vector2(140, 32)
	tab_btn_roster.pressed.connect(func(): _switch_tab("roster"))
	tab_bar.add_child(tab_btn_roster)

	tab_btn_skills = Button.new()
	tab_btn_skills.text = "PILOT SKILLS (ทักษะนักบิน)"
	tab_btn_skills.focus_mode = Control.FOCUS_NONE
	tab_btn_skills.custom_minimum_size = Vector2(170, 32)
	tab_btn_skills.pressed.connect(func(): _switch_tab("skills"))
	tab_bar.add_child(tab_btn_skills)

	var sep = HSeparator.new()
	box.add_child(sep)

	# --- ROSTER VIEW ---
	roster_view = VBoxContainer.new()
	roster_view.add_theme_constant_override("separation", 8)
	roster_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(roster_view)

	var desc = Label.new()
	desc.text = "Everyone riding with the convoy — the driver plus every researched fleet pilot. Pilots can be seated in any parked mech from the ROSTER page."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	roster_view.add_child(desc)

	pilot_list = VBoxContainer.new()
	pilot_list.add_theme_constant_override("separation", 6)
	pilot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_view.add_child(pilot_list)

	pilots_status_label = Label.new()
	pilots_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pilots_status_label.add_theme_font_size_override("font_size", 11)
	roster_view.add_child(pilots_status_label)

	# --- SKILLS VIEW ---
	skills_view = VBoxContainer.new()
	skills_view.add_theme_constant_override("separation", 8)
	skills_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_view.visible = false
	box.add_child(skills_view)

	skills_header_label = Label.new()
	skills_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skills_header_label.add_theme_font_size_override("font_size", 13)
	skills_view.add_child(skills_header_label)

	xp_progress_bar = ProgressBar.new()
	xp_progress_bar.custom_minimum_size = Vector2(0, 16)
	xp_progress_bar.show_percentage = false
	skills_view.add_child(xp_progress_bar)

	spec_container = VBoxContainer.new()
	spec_container.add_theme_constant_override("separation", 4)
	skills_view.add_child(spec_container)

	skills_scroll = ScrollContainer.new()
	skills_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_scroll.custom_minimum_size = Vector2(0, 240)
	skills_view.add_child(skills_scroll)

	skills_grid = VBoxContainer.new()
	skills_grid.add_theme_constant_override("separation", 6)
	skills_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_scroll.add_child(skills_grid)


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	if roster_view and skills_view:
		roster_view.visible = (tab_name == "roster")
		skills_view.visible = (tab_name == "skills")
	if tab_btn_roster and tab_btn_skills:
		tab_btn_roster.modulate = Color(1.2, 1.2, 1.2) if tab_name == "roster" else Color(0.7, 0.7, 0.7)
		tab_btn_skills.modulate = Color(1.2, 1.2, 1.2) if tab_name == "skills" else Color(0.7, 0.7, 0.7)
	refresh()


func set_panel_visible(v: bool) -> void:
	if pilots_panel:
		pilots_panel.visible = v


func show_page() -> void:
	set_panel_visible(true)
	refresh()


func hide_page() -> void:
	set_panel_visible(false)


func refresh() -> void:
	if current_tab == "roster":
		_refresh_roster()
	else:
		_refresh_skills()


# --- Roster View Logic ---

func _refresh_roster() -> void:
	if pilot_list == null:
		return
	for child in pilot_list.get_children():
		child.queue_free()

	var active := HangarManager.get_active_mech()
	var active_id := str(active.get("id", ""))
	var driver_id := str(active.get("pilot", ""))
	var pilots := HangarManager.get_pilots()
	for pilot in pilots:
		_build_row(pilot, active_id, driver_id)

	if pilots_status_label:
		var fleet := HangarManager.get_fleet_size()
		var capacity := HangarManager.get_capacity()
		var convoy := "SOLO CONVOY · 1 trailer · 2 berths" if fleet <= 1 else \
			"FLEET CONVOY · %d pilots · %d trucks · %d berths" % [fleet, ceili(fleet / 2.0), capacity]
		var affiliation := ThemeSystem.get_affiliation()
		pilots_status_label.text = "MAIN DRIVER: %s · %s\n%s · %s\n%d pilot%s in the convoy · %d/%d berths filled" % [
			HangarManager.get_pilot_name(driver_id),
			str(active.get("name", "Mech")),
			affiliation.get("name", "Mech Convoy"),
			convoy,
			pilots.size(), "s" if pilots.size() != 1 else "",
			HangarManager.get_mechs().size(), capacity,
		]


func _build_row(pilot: Dictionary, active_id: String, driver_id: String) -> void:
	var pilot_id := str(pilot.get("id", ""))
	var name := str(pilot.get("name", "?"))
	var status := HangarManager.get_pilot_status(pilot_id)
	var is_wounded := status.contains("WOUNDED")
	var is_destroyed := status.contains("DESTROYED")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pilot_list.add_child(row)

	var marker := "⛔ " if is_destroyed else ("⚠ " if is_wounded else "")
	var name_lbl := Label.new()
	name_lbl.text = "%s%s%s%s" % [marker, name, status, _mech_label(pilot_id)]
	name_lbl.custom_minimum_size = Vector2(250, 0)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.5) if is_wounded or is_destroyed else Color(0.85, 0.9, 0.95))
	row.add_child(name_lbl)

	if pilot_id.begins_with("fleet_"):
		var template_id := pilot_id.trim_prefix("fleet_")
		var heal_cost := RecruitSystem.get_wound_heal_cost(template_id)
		if heal_cost > 0:
			var heal_btn := Button.new()
			heal_btn.text = "HEAL (%dcr)" % heal_cost
			heal_btn.custom_minimum_size = Vector2(96, 28)
			heal_btn.focus_mode = Control.FOCUS_NONE
			heal_btn.tooltip_text = "Spend %d credits to heal this pilot now (full HP, back in the field)." % heal_cost
			heal_btn.pressed.connect(func(): _heal(template_id))
			row.add_child(heal_btn)

	if not is_destroyed:
		var loadout_btn := Button.new()
		loadout_btn.text = "LOADOUT"
		loadout_btn.custom_minimum_size = Vector2(84, 28)
		loadout_btn.focus_mode = Control.FOCUS_NONE
		loadout_btn.tooltip_text = "Manage %s's personal weapons, ammo and items (what they carry when out of the mech)." % name
		loadout_btn.pressed.connect(_open_loadout_editor.bind(pilot_id, name))
		row.add_child(loadout_btn)

	var is_driver := pilot_id == driver_id
	var driver_btn := Button.new()
	driver_btn.custom_minimum_size = Vector2(112, 28)
	driver_btn.focus_mode = Control.FOCUS_NONE
	if is_driver:
		driver_btn.text = "★ DRIVER"
		driver_btn.disabled = true
		driver_btn.tooltip_text = "Currently drives the main mech%s." % _mech_label(pilot_id)
	else:
		driver_btn.text = "MAIN DRIVER"
		if is_destroyed:
			driver_btn.disabled = true
			driver_btn.tooltip_text = "This pilot was lost in combat — they cannot be assigned."
		elif is_wounded:
			driver_btn.tooltip_text = "WOUNDED — they can be seated, but will NOT fight until healed."
		else:
			driver_btn.tooltip_text = "Seat this pilot in the main mech (the machine you pilot into combat)."
		driver_btn.pressed.connect(_set_main_driver.bind(pilot_id))
	row.add_child(driver_btn)


# --- Skills View Logic ---

func _refresh_skills() -> void:
	if skills_header_label == null:
		return

	var lvl := PilotSkillSys.get_level()
	var xp := PilotSkillSys.get_xp()
	var req_xp := PilotSkillSys.get_xp_required_for_next_level(lvl)
	var pts := PilotSkillSys.get_skill_points()
	var spec := PilotSkillSys.get_specialization()

	var spec_text := spec.to_upper() if spec != "" else "NONE (ยังไม่ได้เลือก)"
	var xp_text := "%d / %d XP" % [xp, req_xp] if lvl < PilotSkillSys.MAX_PILOT_LEVEL else "MAX LEVEL"

	skills_header_label.text = "PILOT LEVEL: %d / %d   |   %s   |   SKILL POINTS: %d\nSPECIALIZATION: %s" % [
		lvl, PilotSkillSys.MAX_PILOT_LEVEL, xp_text, pts, spec_text
	]

	if xp_progress_bar:
		if lvl >= PilotSkillSys.MAX_PILOT_LEVEL:
			xp_progress_bar.value = 100.0
			xp_progress_bar.max_value = 100.0
		else:
			xp_progress_bar.max_value = maxf(float(req_xp), 1.0)
			xp_progress_bar.value = float(xp)

	# Specialization selector / status
	for child in spec_container.get_children():
		child.queue_free()

	if spec == "":
		if lvl < 3:
			var lock_lbl := Label.new()
			lock_lbl.text = "🔒 SPECIALIZATION LOCKED: Requires Pilot Level 3"
			lock_lbl.add_theme_font_size_override("font_size", 11)
			lock_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			spec_container.add_child(lock_lbl)
		else:
			var prompt_lbl := Label.new()
			prompt_lbl.text = "CHOOSE SPECIALIZATION (เลือกสายความชำนาญ):"
			prompt_lbl.add_theme_font_size_override("font_size", 11)
			prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
			spec_container.add_child(prompt_lbl)

			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 8)
			spec_container.add_child(btn_row)

			for s in PilotSkillSys.VALID_SPECIALIZATIONS:
				var s_btn := Button.new()
				s_btn.text = s.to_upper()
				s_btn.custom_minimum_size = Vector2(120, 28)
				s_btn.focus_mode = Control.FOCUS_NONE
				s_btn.pressed.connect(_select_specialization.bind(s))
				btn_row.add_child(s_btn)

	# Skills Grid
	for child in skills_grid.get_children():
		child.queue_free()

	var skills := PilotSkillCat.get_all_skills()
	for skill in skills:
		_build_skill_card(skill)


func _build_skill_card(skill: Dictionary) -> void:
	var sid := str(skill.get("id", ""))
	var sname := str(skill.get("name", sid))
	var sdesc := str(skill.get("desc", ""))
	var scateg := str(skill.get("category", "")).to_upper()
	var sspec := str(skill.get("specialization", "universal")).to_upper()
	var req_lvl := int(skill.get("required_level", 1))
	var prereqs := Array(skill.get("prerequisites", []))

	var is_unlocked := PilotSkillSys.is_skill_unlocked(sid)
	var val := PilotSkillSys.validate_unlock(sid)
	var can_unlock := bool(val.get("allowed", false))
	var reason := str(val.get("reason", ""))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.18, 0.14, 0.9) if is_unlocked else Color(0.12, 0.12, 0.12, 0.9)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	skills_grid.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var title_lbl := Label.new()
	var prefix := "✓ " if is_unlocked else "• "
	title_lbl.text = "%s%s [%s | %s]" % [prefix, sname, scateg, sspec]
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4) if is_unlocked else Color(1.0, 0.9, 0.7))
	info_vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = sdesc
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_lbl)

	if not is_unlocked:
		var req_str := "Req: Level %d" % req_lvl
		if sspec != "UNIVERSAL":
			req_str += " · %s" % sspec
		if not prereqs.is_empty():
			req_str += " · Prereq: %s" % ", ".join(prereqs)
		var req_lbl := Label.new()
		req_lbl.text = req_str
		req_lbl.add_theme_font_size_override("font_size", 10)
		req_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		info_vbox.add_child(req_lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(110, 32)
	btn.focus_mode = Control.FOCUS_NONE
	if is_unlocked:
		btn.text = "UNLOCKED"
		btn.disabled = true
	else:
		btn.text = "UNLOCK (1 PT)"
		btn.disabled = not can_unlock
		if not can_unlock:
			btn.tooltip_text = "Cannot unlock: %s" % reason
		else:
			btn.pressed.connect(_unlock_skill.bind(sid))
	hbox.add_child(btn)


func _select_specialization(spec_id: String) -> void:
	var res := PilotSkillSys.select_specialization(spec_id)
	if bool(res.get("allowed", false)):
		GlobalData.save_run()
		refresh()


func _unlock_skill(skill_id: String) -> void:
	var res := PilotSkillSys.unlock_skill(skill_id)
	if bool(res.get("allowed", false)):
		GlobalData.save_run()
		refresh()


# --- Loadout & Assignment Helpers ---

func _open_loadout_editor(pilot_id: String, pilot_name: String) -> void:
	if controller and controller.has_method("open_pilot_loadout_editor"):
		controller.open_pilot_loadout_editor(pilot_id, pilot_name)


func _set_main_driver(pilot_id: String) -> void:
	var active := HangarManager.get_active_mech()
	var active_id := str(active.get("id", ""))
	if active_id == "":
		return
	if not HangarManager.assign_pilot(active_id, pilot_id):
		return
	GlobalData.save_run()
	if controller and controller.status_message_label:
		controller.status_message_label.text = "%s is now the main driver of %s." % [
			HangarManager.get_pilot_name(pilot_id), str(active.get("name", "the main mech"))]
	refresh()


func _mech_label(pilot_id: String) -> String:
	for mech in HangarManager.get_mechs():
		if str(mech.get("pilot", "")) == pilot_id:
			return " · %s" % str(mech.get("name", "Mech"))
	return " · (no mech)"


func _heal(template_id: String) -> void:
	var cost := RecruitSystem.get_wound_heal_cost(template_id)
	if cost <= 0:
		if controller and controller.status_message_label:
			controller.status_message_label.text = "That pilot is not wounded — nothing to heal."
		return
	if not RecruitSystem.heal_wounded_pilot(template_id):
		if controller and controller.status_message_label:
			controller.status_message_label.text = "Need %d credits to heal this pilot." % cost \
				if GlobalData.currency.credits < cost else "The pilot could not be healed."
		return
	GlobalData.save_run()
	var unit := FleetSystem.get_fleet_unit(template_id)
	if controller and controller.status_message_label:
		controller.status_message_label.text = "%s is healed and ready to fight (-%d credits)." % [
			str(unit.get("name", "The pilot")), cost]
	refresh()
