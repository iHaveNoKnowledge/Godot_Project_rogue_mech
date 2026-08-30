extends CanvasLayer

const PartPenaltySystem = preload("res://scripts/systems/part_penalty_system.gd")

var root_control: Control
var menu_container: VBoxContainer
var info_panel: PanelContainer
var info_label: Label
var status_panel: PanelContainer
var status_label: Label
var action_container: VBoxContainer
# Visual armor+frame HP bars for the Mech Status view (mirrors the combat
# CoreHUD so the intermission shows the mech's real condition at a glance).
var status_bars_container: VBoxContainer
var current_view: String = "menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	_show_menu()
	# Intermission menu is the primary hub upon entering the board / returning from hangar.
	# The driver sees the intermission menu first, and can choose 'Move on Board'
	# (or press ESC) to close the menu and step across the board tiles.
	visible = true
	EventBus.game_state_changed.connect(_on_state_changed)
	# NOTE: the intermission music is owned by the board STATE (GameManager
	# enter_board / return_to_board / advance_to_next_sector), not by this panel.
	# Playing it here would restart the track every time the panel is shown or
	# the scene reloads; the state machine starts/resumes it exactly once per
	# board session.
	# The sector objective lives in the persistent BoardHUD right column, which
	# stays visible over the intermission, so this menu no longer draws its own
	# objective panel.


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameManager.current_state == GameManager.State.BOARD:
			# If an event popup is up (tree paused): ESC closes the popup, not the intermission
			var has_event_modal := get_tree().get_nodes_in_group("event_popup").size() > 0
			if get_tree().paused and has_event_modal:
				return
			if get_tree().paused and not has_event_modal:
				get_tree().paused = false

			visible = not visible
			if visible:
				_show_menu()
				status_label.text = _get_status_text()


func _create_ui() -> void:
	# Root control for full screen — IGNORE so clicks outside panels pass to 3D board
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	# Main menu panel (left side)
	var menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	menu_panel.offset_right = 250
	menu_panel.offset_left = 20
	menu_panel.offset_top = 20
	menu_panel.offset_bottom = -20
	root_control.add_child(menu_panel)

	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	menu_style.corner_radius_top_left = 0
	menu_style.corner_radius_top_right = 0
	menu_style.corner_radius_bottom_left = 0
	menu_style.corner_radius_bottom_right = 0
	menu_style.content_margin_left = 15
	menu_style.content_margin_right = 15
	menu_style.content_margin_top = 15
	menu_style.content_margin_bottom = 15
	menu_panel.add_theme_stylebox_override("panel", menu_style)

	menu_container = VBoxContainer.new()
	menu_container.add_theme_constant_override("separation", 8)
	menu_panel.add_child(menu_container)

	# Title
	var title = Label.new()
	title.text = "INTERMISSION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	menu_container.add_child(title)

	var separator = HSeparator.new()
	menu_container.add_child(separator)

	# Menu buttons
	_add_menu_button("Move on Board", _on_move_pressed)
	_add_menu_button("End Day", _on_end_day_pressed)
	_add_menu_button("Mech Status", _on_status_pressed)
	_add_menu_button("Inventory", _on_inventory_pressed)
	_add_menu_button("Pilot Status", _on_pilot_pressed)
	_add_menu_button("Research Base", _on_research_pressed)
	_add_menu_button("Fleet Roster", _on_fleet_pressed)
	_add_menu_button("Convoy", _on_convoy_pressed)
	_add_menu_button("Fleet Security", _on_security_pressed)
	_add_menu_button("Board Info", _on_board_info_pressed)
	_add_menu_button("Hangar", _on_hangar_pressed)
	_add_menu_button("Save Game", _on_save_pressed)
	_add_menu_button("Load Game", _on_load_pressed)
	_add_menu_button("Exit to Menu", _on_exit_pressed)

	# Info panel (right side)
	info_panel = PanelContainer.new()
	# FULL_RECT anchors so offset_left=285 means "285px from the LEFT edge" —
	# RIGHT_WIDE anchors pin the left edge to the viewport right edge, which
	# pushed the whole panel off-screen (left edge at width+285).
	info_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_panel.offset_left = 285
	# Ends short of the BoardHUD right column (objective/countdown/reserved
	# cards at ~270px from the right edge), which stays visible over the
	# intermission by design — content must never render underneath it.
	info_panel.offset_right = -270
	info_panel.offset_top = 160
	info_panel.offset_bottom = -75
	info_panel.visible = false
	root_control.add_child(info_panel)

	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	info_style.corner_radius_top_left = 0
	info_style.corner_radius_top_right = 0
	info_style.corner_radius_bottom_left = 0
	info_style.corner_radius_bottom_right = 0
	info_style.content_margin_left = 15
	info_style.content_margin_right = 15
	info_style.content_margin_top = 15
	info_style.content_margin_bottom = 15
	info_panel.add_theme_stylebox_override("panel", info_style)

	# Inner VBox so label + action buttons stack instead of overlapping.
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 10)
	info_panel.add_child(info_vbox)

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(info_label)

	# Dynamic action container (research/fleet buttons) rebuilt per view.
	action_container = VBoxContainer.new()
	action_container.add_theme_constant_override("separation", 6)
	info_vbox.add_child(action_container)

	# Visual HP bars for the Mech Status view: two skewed bars per equipped
	# part (armor on top, frame below) so the driver can read the mech's real
	# condition at a glance and decide fight-vs-repair before leaving the menu.
	status_bars_container = VBoxContainer.new()
	status_bars_container.add_theme_constant_override("separation", 6)
	status_bars_container.visible = false
	info_vbox.add_child(status_bars_container)

	# Status panel (bottom) - positioned cleanly with comfortable margins and proper padding
	status_panel = PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_panel.offset_top = -74
	status_panel.offset_left = 285
	status_panel.offset_right = -20
	status_panel.offset_bottom = -16
	root_control.add_child(status_panel)

	var status_style = StyleBoxFlat.new()
	status_style.bg_color = Color(0.06, 0.09, 0.16, 0.94)
	status_style.corner_radius_top_left = 0
	status_style.corner_radius_top_right = 0
	status_style.corner_radius_bottom_left = 0
	status_style.corner_radius_bottom_right = 0
	status_style.content_margin_left = 16
	status_style.content_margin_right = 16
	status_style.content_margin_top = 6
	status_style.content_margin_bottom = 6
	status_style.border_width_left = 1
	status_style.border_width_right = 1
	status_style.border_width_top = 1
	status_style.border_width_bottom = 1
	status_style.border_color = Color(0.22, 0.22, 0.22, 1.0)
	status_panel.add_theme_stylebox_override("panel", status_style)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = _get_status_text()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_panel.add_child(status_label)


func _add_menu_button(text: String, callback: Callable) -> void:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 35)
	button.pressed.connect(callback)
	menu_container.add_child(button)


func _get_status_text() -> String:
	var base_info := ""
	if GlobalData.narrative.mech_less:
		base_info = "  •  ON FOOT"
	if GlobalData.board.patrol_alert > 0:
		base_info += "  •  HUNT ALERT %d" % GlobalData.board.patrol_alert
	if GlobalData.narrative.enemy_base_active:
		base_info += "  •  Enemy Base: %d%%" % int((GlobalData.narrative.enemy_base_progress / GlobalData.narrative.enemy_base_required) * 100.0)
	if not GlobalData.narrative.stalking_aces.is_empty():
		base_info += "  •  HUNTED by %s" % ", ".join(GlobalData.narrative.stalking_aces)
	return "Day %d  •  MP: %d/%d  •  %s%s\nCredits: %d cr   Scrap: %d   Rep: %d   Heat: %d   Wanted: %d   Security: %d%%   Tier: %d   Pos: %s" % [
		GlobalData.board.board_day,
		GlobalData.board.board_mp,
		GlobalData.board.board_mp_max,
		BoardSystem.progress_text(),
		base_info,
		GlobalData.currency.credits,
		GlobalData.currency.scrap,
		GlobalData.narrative.reputation,
		GlobalData.board.heat,
		GlobalData.board.wanted_level,
		int(FleetSystem.get_fleet_security()),
		GlobalData.narrative.enemy_tech_tier,
		str(GlobalData.board.current_tile)
	]


func _on_state_changed(old_state: String, new_state: String) -> void:
	if new_state == "BOARD":
		visible = true
		_show_menu()
		status_label.text = _get_status_text()
	elif new_state == "COMBAT" or new_state == "HANGAR":
		visible = false


func _show_menu() -> void:
	current_view = "menu"
	info_panel.visible = false


func _on_move_pressed() -> void:
	# Hide intermission UI, show board for tile selection
	visible = false


func _on_end_day_pressed() -> void:
	visible = false
	var board = get_tree().current_scene
	if board and board.has_method("_end_day"):
		board._end_day()


func _on_status_pressed() -> void:
	current_view = "status"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_mech_status_text()
	_rebuild_status_bars()


func _on_inventory_pressed() -> void:
	current_view = "inventory"
	info_panel.visible = false
	_clear_actions()
	var modal_script = load("res://scripts/ui/board_inventory_modal.gd")
	if modal_script:
		var modal = modal_script.new()
		add_child(modal)
		modal.modal_closed.connect(func():
			_rebuild_status_bars()
		)


# Pilot Status view: the pilot's own HP/weapons/ammo/items (separate from the
# mech). Healing items are used here — the pilot heals with items, not direct
# credits, so the buy option lives on the City (trading) node.
func _on_pilot_pressed() -> void:
	current_view = "pilot"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_pilot_text()

	for entry in PilotSystem.get_items():
		var item_id := str(entry.get("id", ""))
		var item := PilotSystem.get_heal_item(item_id)
		if item.is_empty():
			continue
		var heal_text := "full HP" if int(item.get("heal", 0)) <= 0 else "%d HP" % int(item.get("heal", 0))
		var btn = Button.new()
		btn.text = "Use %s (heals %s) x%d" % [
			item.get("name", item_id), heal_text, int(entry.get("count", 0))
		]
		btn.disabled = not PilotSystem.get_hp() < PilotSystem.get_max_hp()
		btn.tooltip_text = str(item.get("desc", ""))
		btn.pressed.connect(_use_pilot_item.bind(item_id))
		action_container.add_child(btn)


func _use_pilot_item(item_id: String) -> void:
	var restored := PilotSystem.use_heal_item(item_id)
	if restored > 0.0:
		status_label.text = _get_status_text() + "  [Pilot healed +%d HP]" % int(restored)
	else:
		status_label.text = _get_status_text() + "  [No item / pilot already at full HP]"
	_on_pilot_pressed()


func _build_pilot_text() -> String:
	var text := "=== PILOT STATUS (the pilot, not the mech) ===\n\n"
	text += "HP: %d / %d\n" % [int(PilotSystem.get_hp()), int(PilotSystem.get_max_hp())]
	if PilotSystem.get_hp() < PilotSystem.get_max_hp():
		text += "STATUS: INJURED — use healing items (bought at City nodes).\n"
	else:
		text += "STATUS: HEALTHY\n"
	text += "\n--- Personal Weapons ---\n"
	var weapons := PilotSystem.get_weapons()
	if weapons.is_empty():
		text += "(None)\n"
	else:
		for wp in weapons:
			text += "- %s\n" % (wp.weapon_name if wp else "?")
	text += "\n--- Personal Ammo ---\n"
	text += "Kinetic: %d | Energy: %d | Explosive: %d | Missile: %d\n" % [
		PilotSystem.get_ammo("kinetic"),
		PilotSystem.get_ammo("energy"),
		PilotSystem.get_ammo("explosive"),
		PilotSystem.get_ammo("missile"),
	]
	text += "\n--- Items ---\n"
	var items := PilotSystem.get_items()
	if items.is_empty():
		text += "(No items — visit a City trading node to buy medkits.)\n"
	else:
		for entry in items:
			var item := PilotSystem.get_heal_item(str(entry.get("id", "")))
			if item.is_empty():
				continue
			text += "- %s x%d (%s)\n" % [
				item.get("name", "?"), int(entry.get("count", 0)), item.get("desc", "")
			]
	return text


func _on_board_info_pressed() -> void:
	current_view = "board_info"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_board_info_text()


func _clear_actions() -> void:
	for child in action_container.get_children():
		child.queue_free()
	if status_bars_container:
		status_bars_container.visible = false


func _on_research_pressed() -> void:
	current_view = "research"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_research_text()

	# Start buttons for available projects
	for project in GlobalData.research_blueprints:
		var project_id = project.get("id", "")
		if FleetSystem.is_research_active(project_id) or FleetSystem.is_research_completed(project_id):
			continue
		var cost = int(project.get("data_cores", 1))
		var has_cores = GlobalData.currency.data_cores >= cost
		var btn = Button.new()
		btn.text = "Start: %s (%d core%s)" % [
			project.get("name", project_id), cost, "s" if cost != 1 else ""
		]
		btn.disabled = not has_cores
		btn.pressed.connect(_start_research.bind(project_id))
		action_container.add_child(btn)


func _start_research(project_id: String) -> void:
	if FleetSystem.start_research(project_id):
		status_label.text = _get_status_text() + "  [Research started: %s]" % FleetSystem.get_research_project(project_id).get("name", project_id)
		_on_research_pressed()  # refresh list
	else:
		status_label.text = _get_status_text() + "  [Not enough data cores / already active]"


func _build_research_text() -> String:
	var text = "=== RESEARCH BASE ===\n\n"
	text += "Data Cores (blueprints): %d\n\n" % GlobalData.currency.data_cores
	text += "Research advances 1 point per day, +2 per combat won.\n\n"

	text += "--- Active Projects ---\n"
	if GlobalData.hangar.research_projects.is_empty():
		text += "(None)\n"
	else:
		for project_id in GlobalData.hangar.research_projects:
			var state = GlobalData.hangar.research_projects[project_id]
			var project = FleetSystem.get_research_project(project_id)
			text += "%s: %d/%d\n" % [
				project.get("name", project_id),
				int(state.get("progress", 0)),
				int(state.get("required", 1))
			]
	text += "\n"

	text += "--- Unlocked ---\n"
	if GlobalData.hangar.research_unlocked.is_empty():
		text += "(Nothing researched yet)\n"
	else:
		for project_id in GlobalData.hangar.research_unlocked:
			text += "- %s\n" % FleetSystem.get_research_project(project_id).get("name", project_id)
	text += "\n"

	text += "--- Available Blueprints ---\n"
	for project in GlobalData.research_blueprints:
		var project_id = project.get("id", "")
		if FleetSystem.is_research_active(project_id) or FleetSystem.is_research_completed(project_id):
			continue
		text += "%s — %d cores, %d turns\n" % [
			project.get("name", project_id),
			int(project.get("data_cores", 1)),
			int(project.get("research_time", 6))
		]
		text += "   %s\n" % project.get("desc", "")
	return text


func _on_fleet_pressed() -> void:
	current_view = "fleet"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_fleet_text()

	# Fielded toggle per unit. Wounded pilots cannot be toggled: they are
	# recovering and would be gated out of combat anyway (get_fielded_units),
	# so the toggle is locked with an explanation instead of silently doing
	# nothing (destroyed units stay locked for the same reason).
	#
	# Feature 7: only units with a pilot seated in a hangar mech can fight —
	# template-only units (researched blueprints with no berth) are dropped from
	# the field and not offered here. The hangar SORTIE page is the primary
	# control; this panel mirrors it for the same seated units.
	var seated := FleetSystem.get_seated_template_ids()
	for unit in GlobalData.hangar.fleet_roster:
		if not (unit is Dictionary):
			continue
		var template_id = unit.get("template_id", "")
		if not seated.has(template_id):
			continue
		var fielded = unit.get("fielded", true)
		var destroyed = unit.get("destroyed", false)
		var wounded = bool(unit.get("wounded", false))
		var wound_turns := maxi(int(unit.get("wound_turns", 1)), 1)
		var btn = Button.new()
		btn.text = "%s: %s" % [unit.get("name", template_id), "FIELDED" if fielded else "STANDING DOWN"]
		btn.disabled = destroyed or wounded
		# Only the wounded (not also destroyed) get the recovery explanation — a
		# dead pilot has nothing to recover from.
		if wounded and not destroyed:
			btn.tooltip_text = "WOUNDED — recovering (%d move%s). Cannot fight until healed (HEAL on the hangar roster)." % [
				wound_turns, "s" if wound_turns != 1 else ""]
		btn.pressed.connect(_toggle_fielded.bind(template_id))
		action_container.add_child(btn)


func _toggle_fielded(template_id: String) -> void:
	var unit = FleetSystem.get_fleet_unit(template_id)
	if unit.is_empty():
		return
	FleetSystem.set_unit_fielded(template_id, not unit.get("fielded", true))
	_on_fleet_pressed()  # refresh


func _build_fleet_text() -> String:
	var text = "=== FLEET ROSTER ===\n\n"
	text += "Fielded units fight alongside you in combat.\n\n"
	if GlobalData.hangar.fleet_roster.is_empty():
		text += "No units yet. Research blueprints at the Research Base to unlock squadmates."
		return text
	# Feature 7: only units with a pilot seated in a hangar mech can field.
	# Template-only units (no berth) are dropped from the field and hidden here
	# — the hangar SORTIE page is where the lineup is chosen.
	var seated := FleetSystem.get_seated_template_ids()
	var shown := 0
	for unit in GlobalData.hangar.fleet_roster:
		var template_id := str(unit.get("template_id", ""))
		if not seated.has(template_id):
			continue
		shown += 1
		var state = "ACTIVE" if unit.get("fielded", true) else "STANDBY"
		if unit.get("destroyed", false):
			state = "DESTROYED"
		elif bool(unit.get("wounded", false)):
			# Recovering pilots read as WOUNDED (not ACTIVE/STANDBY): they are
			# locked out of the field until the countdown ends or the hangar's
			# HEAL clears it.
			state = "WOUNDED (%dT)" % int(unit.get("wound_turns", 0))
		text += "- %s [%s] HP: %d/%d\n" % [
			unit.get("name", template_id),
			state,
			int(unit.get("hp", 0)),
			int(unit.get("max_hp", 0))
		]
	if shown == 0:
		text += "No squadmates on standby. Seat a pilot in a hangar mech (ROSTER) to field them — see the hangar SORTIE page.\n"
	return text


func _on_convoy_pressed() -> void:
	current_view = "convoy"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_convoy_text()


func _build_convoy_text() -> String:
	var affiliation := ThemeSystem.get_affiliation()
	var text = "=== CONVOY ===\n\n"
	text += "Affiliation: %s\n" % affiliation.get("name", GlobalData.narrative.theme_id)
	text += "Transport: %s\n\n" % affiliation.get("transport", "Truck convoy")
	text += "%s\n\n" % affiliation.get("transport_desc", "")
	if GlobalData.narrative.mech_less:
		text += "STATUS: ON FOOT — every mech is gone.\n"
		text += "Board combat tiles become recovery missions until a replacement chassis is found.\n"
	else:
		text += "STATUS: %d/%d mech berths parked.\n" % [GlobalData.hangar.hangar_mechs.size(), HangarManager.get_capacity()]
	text += "\n"
	text += "Pilots in convoy: %d\n" % HangarManager.get_fleet_size()
	text += "Reserve ammo: Kin %d | En %d | Exp %d | Ms %d\n" % [
		LoadoutSystem.get_reserve_ammo("kinetic"),
		LoadoutSystem.get_reserve_ammo("energy"),
		LoadoutSystem.get_reserve_ammo("explosive"),
		LoadoutSystem.get_reserve_ammo("missile")
	]
	return text


func _on_security_pressed() -> void:
	current_view = "security"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_security_text()
	_upgrade_security_button()


func _upgrade_security_button() -> void:
	if FleetSystem.get_fleet_security() >= GlobalData.FLEET_SECURITY_MAX:
		return
	var cost := FleetSystem.get_security_upgrade_cost()
	var btn = Button.new()
	btn.text = "Upgrade Security (%d credits)" % cost
	btn.disabled = GlobalData.currency.credits < cost
	btn.pressed.connect(_on_upgrade_security_pressed)
	action_container.add_child(btn)


func _on_upgrade_security_pressed() -> void:
	if FleetSystem.upgrade_fleet_security():
		_on_security_pressed()  # refresh
	else:
		status_label.text = _get_status_text() + "  [Not enough credits / maxed out]"


func _build_security_text() -> String:
	var text = "=== FLEET SECURITY ===\n\n"
	text += "Fleet security hardens our ships and facility against enemy spies.\n\n"
	text += "Security: %d / %d\n" % [int(FleetSystem.get_fleet_security()), int(GlobalData.FLEET_SECURITY_MAX)]
	text += "Hardening level: %d\n" % GlobalData.hangar.security_upgrade_level
	text += "Spy counter chance: %d%%\n\n" % int(FleetSystem.get_spy_counter_chance() * 100.0)
	text += "Higher security makes enemy espionage against your mech data far more likely to be caught."
	return text


func _on_hangar_pressed() -> void:
	GameManager.enter_hangar()


func _on_save_pressed() -> void:
	GlobalData.save_run()
	status_label.text = _get_status_text() + "  [SAVED]"


func _on_load_pressed() -> void:
	if GlobalData.load_run():
		status_label.text = _get_status_text() + "  [LOADED]"
	else:
		status_label.text = _get_status_text() + "  [NO SAVE FOUND]"


func _on_exit_pressed() -> void:
	GameManager.game_over()


func _build_mech_status_text() -> String:
	var text = "=== MECH STATUS ===\n\n"
	if GlobalData.narrative.mech_less:
		text += "ON FOOT — no mech.\n"
		text += "Find a replacement chassis before the next combat tile.\n"
		return text
	text += "Chassis: %s\n" % GlobalData.weapons.chassis_id
	text += "Credits: %d\n" % GlobalData.currency.credits
	text += "Scrap: %d\n" % GlobalData.currency.scrap
	text += "Data Cores: %d\n\n" % GlobalData.currency.data_cores

	var total_armor := 0.0
	var total_max_armor := 0.0
	var total_frame := 0.0
	var total_max_frame := 0.0
	for slot in GlobalData.MECHA_SLOTS:
		var part = GlobalData.weapons.equipped_parts.get(slot)
		var a_hp: float = _slot_armor_max(slot, part)
		var f_hp: float = _slot_frame_max(slot)
		var a_dmg = clampf(GlobalData.weapons.part_damage.get(slot, 0.0), 0.0, 1.0)
		var f_dmg = clampf(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0), 0.0, 1.0)
		total_armor += a_hp * (1.0 - a_dmg)
		total_max_armor += a_hp
		total_frame += f_hp * (1.0 - f_dmg)
		total_max_frame += f_hp

	var armor_pct := int((total_armor / maxf(total_max_armor, 1.0)) * 100.0)
	var frame_pct := int((total_frame / maxf(total_max_frame, 1.0)) * 100.0)
	text += "ARMOR: %d%% (%.0f/%.0f)\n" % [armor_pct, total_armor, total_max_armor]
	text += "FRAME: %d%% (%.0f/%.0f)\n\n" % [frame_pct, total_frame, total_max_frame]

	# Active Part Penalties Report (shows strikethrough base values and debuff reasons)
	var penalty_report := PartPenaltySystem.get_detailed_penalty_report()
	if penalty_report != "":
		text += penalty_report + "\n\n"

	# Every parked mech's condition too, so the driver sees the whole fleet's HP
	# at a glance — not just the piloted mech's live working set.
	var mechs := HangarManager.get_mechs()
	if mechs.size() > 0:
		text += "--- HANGAR FLEET ---\n"
		var sorted_mechs: Array = mechs.duplicate()
		sorted_mechs.sort_custom(func(a, b): return int((a as Dictionary).get("slot", 0)) < int((b as Dictionary).get("slot", 0)))
		for mech in sorted_mechs:
			if not (mech is Dictionary):
				continue
			var totals := _mech_armor_frame_totals(mech)
			var fleet_id := str((mech as Dictionary).get("id", ""))
			var fleet_pilot := HangarManager.get_mech_pilot_name(fleet_id)
			var fleet_mark := "★ " if fleet_id == GlobalData.hangar.active_hangar_mech_id else ""
			var fleet_a_pct := int((totals.armor_cur / maxf(totals.armor_max, 1.0)) * 100.0)
			var fleet_f_pct := int((totals.frame_cur / maxf(totals.frame_max, 1.0)) * 100.0)
			text += "%s%s (SLOT %d) · %s\n" % [
				fleet_mark, str((mech as Dictionary).get("name", "Mech")),
				int((mech as Dictionary).get("slot", 0)), fleet_pilot]
			text += "   ARMOR: %d%% (%.0f/%.0f)   FRAME: %d%% (%.0f/%.0f)\n" % [
				fleet_a_pct, totals.armor_cur, totals.armor_max,
				fleet_f_pct, totals.frame_cur, totals.frame_max]
		text += "\n"

	text += "(All 6 limb HP bars below — Armor on top, Frame underneath.)\n"
	return text


# Total armor/frame HP for a PARKED mech snapshot (not the live working set), so
# the fleet readout can show every hangar mech's condition at a glance.
func _mech_armor_frame_totals(mech: Dictionary) -> Dictionary:
	var saved_parts: Dictionary = mech.get("parts", {})
	var saved_frames: Dictionary = mech.get("frames", {})
	var saved_damage: Dictionary = mech.get("damage", {})
	var armor_cur := 0.0
	var armor_max := 0.0
	var frame_cur := 0.0
	var frame_max := 0.0
	for slot in GlobalData.MECHA_SLOTS:
		var part = SaveGameIO.resolve_equipped_part(saved_parts.get(slot))
		var a_hp := _slot_armor_max(slot, part)
		if a_hp > 0.0:
			var a_dmg := clampf(float(saved_damage.get(slot, 0.0)), 0.0, 1.0)
			armor_cur += a_hp * (1.0 - a_dmg)
			armor_max += a_hp
		var f_hp := _slot_frame_max(slot)
		if f_hp > 0.0:
			var f_dmg := clampf(float(saved_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)
			frame_cur += f_hp * (1.0 - f_dmg)
			frame_max += f_hp
	return {"armor_cur": armor_cur, "armor_max": armor_max, "frame_cur": frame_cur, "frame_max": frame_max}


# Max armor HP for a part (ArmorPart resource or Dictionary instance).
func _slot_armor_max(slot: String, part: Variant) -> float:
	var base_hp := 0.0
	if part is ArmorPart:
		base_hp = part.max_hp
	elif part is Dictionary:
		base_hp = float((part as Dictionary).get("hp", (part as Dictionary).get("max_hp", 0.0)))
	if base_hp <= 0.0:
		base_hp = _default_slot_armor(slot)
	return base_hp


# Max frame HP for a slot (equipped inner frame).
func _slot_frame_max(slot: String) -> float:
	var f = GlobalData.weapons.equipped_frames.get(slot)
	var base_hp := 0.0
	if f is Dictionary:
		base_hp = float(f.get("hp", 0.0)) + LoadoutSystem.get_frame_upgrade_hp_bonus()
	if base_hp <= 0.0:
		base_hp = _default_slot_frame(slot) + LoadoutSystem.get_frame_upgrade_hp_bonus()
	return base_hp


func _default_slot_armor(slot: String) -> float:
	match slot:
		"head": return 30.0
		"body": return 60.0
		"arm_left", "arm_right": return 25.0
		"leg_left", "leg_right": return 30.0
		_: return 25.0


func _default_slot_frame(slot: String) -> float:
	match slot:
		"head": return 20.0
		"body": return 40.0
		"arm_left", "arm_right": return 15.0
		"leg_left", "leg_right": return 20.0
		_: return 15.0


# Rebuilds the visual armor/frame HP bars shown under the Mech Status text.
# Shows all 6 limbs in a clean 2-column grid.
func _rebuild_status_bars() -> void:
	for child in status_bars_container.get_children():
		child.queue_free()
	status_bars_container.visible = true

	if GlobalData.narrative.mech_less:
		var note = Label.new()
		note.text = "(No mech — inspecting the pilot instead.)"
		status_bars_container.add_child(note)
		return

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	status_bars_container.add_child(grid)

	for slot in GlobalData.MECHA_SLOTS:
		var part = GlobalData.weapons.equipped_parts.get(slot)
		var armor_max := _slot_armor_max(slot, part)
		var frame_max := _slot_frame_max(slot)

		var a_dmg = clampf(GlobalData.weapons.part_damage.get(slot, 0.0), 0.0, 1.0)
		var f_dmg = clampf(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0), 0.0, 1.0)
		var armor_cur: float = armor_max * (1.0 - a_dmg)
		var frame_cur: float = frame_max * (1.0 - f_dmg)

		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.custom_minimum_size = Vector2(250, 0)

		var header := Label.new()
		var part_name: String = ""
		if part is ArmorPart:
			part_name = part.part_name
		elif part is Dictionary:
			part_name = str(part.get("name", part.get("part_name", "Standard Armor")))
		else:
			part_name = "Standard Armor"

		var dur_ratio := GlobalData.get_part_durability(slot)
		var dur_text := ""
		if dur_ratio < 0.99:
			dur_text = " [DUR: %.0f%%]" % [dur_ratio * 100.0]

		header.text = "%s: %s%s" % [slot.replace("_", " ").capitalize(), part_name, dur_text]
		header.add_theme_font_size_override("font_size", 12)
		if a_dmg >= 0.40 or f_dmg >= 0.40 or dur_ratio < 0.70:
			header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		else:
			header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		cell.add_child(header)

		cell.add_child(_make_status_bar("Armor", armor_cur, armor_max, Color(0.77, 0.76, 0.75), Color(0.6, 0.6, 0.6)))
		cell.add_child(_make_status_bar("Frame", frame_cur, frame_max, Color(0.376, 0.82, 0.43), Color(0.537, 1.0, 0.53)))

		grid.add_child(cell)


# One skewed HP bar row (label + bar + value) for the Mech Status view.
func _make_status_bar(label_text: String, current: float, max_value: float, fill_a: Color, fill_b: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name := Label.new()
	name.text = label_text
	name.custom_minimum_size = Vector2(44, 0)
	name.add_theme_font_size_override("font_size", 9)
	name.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(name)

	var bar := Control.new()
	bar.set_script(preload("res://scripts/ui/hp_part_bar.gd"))
	bar.custom_minimum_size = Vector2(180, 8)
	bar.fill_color_a = fill_a
	bar.fill_color_b = fill_b
	bar.setup(current, max_value, current <= 0.001 and max_value > 0.0)
	row.add_child(bar)

	var value := Label.new()
	value.text = "%d / %d" % [int(round(current)), int(round(max_value))]
	value.add_theme_font_size_override("font_size", 9)
	row.add_child(value)
	return row


func _build_inventory_text() -> String:
	var text = "=== INVENTORY & RESERVES ===\n\n"
	text += "Credits: %d\n" % GlobalData.currency.credits
	text += "Scrap (Material): %d\n" % GlobalData.currency.scrap
	text += "Data Cores (Research): %d\n\n" % GlobalData.currency.data_cores

	text += "--- Reserve Ammo Stock ---\n"
	text += "Kinetic Ammo: %d\n" % LoadoutSystem.get_reserve_ammo("kinetic")
	text += "Energy Cells: %d\n" % LoadoutSystem.get_reserve_ammo("energy")
	text += "Explosive Shells: %d\n" % LoadoutSystem.get_reserve_ammo("explosive")
	text += "Missile Pods: %d\n\n" % LoadoutSystem.get_reserve_ammo("missile")

	text += "--- Weapon Inventory ---\n"
	if GlobalData.weapons.weapon_inventory.is_empty():
		text += "(No weapons in stash)\n"
	else:
		for item in GlobalData.weapons.weapon_inventory:
			var w_name = item.get("name", "Unknown Weapon")
			text += "- %s (%.0f%%)\n" % [w_name, GlobalData.get_durability_ratio(item) * 100.0]
	text += "\n"

	text += "--- Armor Inventory ---\n"
	if GlobalData.weapons.armor_inventory.is_empty():
		text += "(No armor in inventory)\n"
	else:
		for item in GlobalData.weapons.armor_inventory:
			text += "- %s [%s] (HP: %.0f, Armor: %.0f, Weight: %.1f, Dur: %.0f%%)\n" % [
				item.get("name", "Armor"),
				item.get("slot", "body"),
				item.get("hp", 0.0),
				item.get("armor", 0.0),
				item.get("weight", 0.0),
				GlobalData.get_durability_ratio(item) * 100.0
			]
	return text


func _build_board_info_text() -> String:
	var text = "=== BOARD INFO ===\n\n"
	text += "Map theme: %s\n" % GlobalData.board.board_theme_id.capitalize()
	text += "Position: %s\n" % str(GlobalData.board.current_tile)
	text += "Day: %d | MP: %d / %d\n" % [GlobalData.board.board_day, GlobalData.board.board_mp, GlobalData.board.board_mp_max]
	text += "Objective: %s\n" % BoardSystem.objective_desc()
	text += "Progress: %s\n\n" % BoardSystem.progress_text()

	text += "--- Movement ---\n"
	text += "WASD / click an adjacent tile to move. Each cell costs MP by terrain.\n"
	text += "End key = end the day (refill MP, advance patrols).\n\n"

	text += "--- Terrains ---\n"
	text += "Road/Plain (1 MP) | Bridge (1 MP)\n"
	text += "Sand/Forest (2 MP) | Water/Rock (impassable)\n\n"

	text += "--- Tiles ---\n"
	text += "Combat (red) - Fight enemies\n"
	text += "Event (blue) - Random events\n"
	text += "Safehouse (green) - Rest/repair\n"
	text += "City (orange) - Trade post\n"
	text += "Data node (gold) - Data cores\n"
	text += "Exit (magenta) - Boss (requires objective)\n"
	return text
