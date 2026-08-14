extends CanvasLayer

var root_control: Control
var menu_container: VBoxContainer
var info_panel: PanelContainer
var info_label: Label
var status_panel: PanelContainer
var status_label: Label
var objective_panel: PanelContainer
var objective_label: Label
var action_container: VBoxContainer
var current_view: String = "menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	_show_menu()
	_update_objective_panel()
	EventBus.game_state_changed.connect(_on_state_changed)
	visibility_changed.connect(_on_visibility_changed)
	if visible:
		AudioManager.play_intermission_music()


func _on_visibility_changed() -> void:
	if visible:
		AudioManager.play_intermission_music()
		_update_objective_panel()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameManager.current_state == GameManager.State.BOARD:
			if GlobalData.blocked_intermission:
				# Ambush aftermath: no time to reorganize at the menu.
				return
			visible = true
			info_panel.visible = false
			status_label.text = _get_status_text()


func _create_ui() -> void:
	# Root control for full screen
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	menu_style.corner_radius_top_left = 8
	menu_style.corner_radius_top_right = 8
	menu_style.corner_radius_bottom_left = 8
	menu_style.corner_radius_bottom_right = 8
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
	info_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	info_panel.offset_left = 285
	info_panel.offset_right = -20
	info_panel.offset_top = 160
	info_panel.offset_bottom = -20
	info_panel.visible = false
	root_control.add_child(info_panel)

	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	info_style.corner_radius_top_left = 8
	info_style.corner_radius_top_right = 8
	info_style.corner_radius_bottom_left = 8
	info_style.corner_radius_bottom_right = 8
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

	# Objective progress window — always pinned to the top-right corner so the
	# player can see how far along the current sector objective they are.
	objective_panel = PanelContainer.new()
	objective_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	objective_panel.offset_left = -260
	objective_panel.offset_right = -20
	objective_panel.offset_top = 20
	objective_panel.offset_bottom = 150
	root_control.add_child(objective_panel)

	var objective_style = StyleBoxFlat.new()
	objective_style.bg_color = Color(0.12, 0.12, 0.2, 0.92)
	objective_style.corner_radius_top_left = 8
	objective_style.corner_radius_top_right = 8
	objective_style.corner_radius_bottom_left = 8
	objective_style.corner_radius_bottom_right = 8
	objective_style.content_margin_left = 15
	objective_style.content_margin_right = 15
	objective_style.content_margin_top = 12
	objective_style.content_margin_bottom = 12
	objective_panel.add_theme_stylebox_override("panel", objective_style)

	objective_label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_panel.add_child(objective_label)

	# Status panel (bottom)
	status_panel = PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_panel.offset_top = -60
	status_panel.offset_left = 20
	status_panel.offset_right = -20
	status_panel.offset_bottom = -20
	root_control.add_child(status_panel)

	var status_style = StyleBoxFlat.new()
	status_style.bg_color = Color(0.1, 0.15, 0.1, 0.9)
	status_style.corner_radius_top_left = 8
	status_style.corner_radius_top_right = 8
	status_style.corner_radius_bottom_left = 8
	status_style.corner_radius_bottom_right = 8
	status_style.content_margin_left = 15
	status_style.content_margin_right = 15
	status_style.content_margin_top = 8
	status_style.content_margin_bottom = 8
	status_panel.add_theme_stylebox_override("panel", status_style)

	status_label = Label.new()
	status_label.text = _get_status_text()
	status_panel.add_child(status_label)


func _add_menu_button(text: String, callback: Callable) -> void:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 35)
	button.pressed.connect(callback)
	menu_container.add_child(button)


func _update_objective_panel() -> void:
	if objective_label == null:
		return
	var obj := BoardSystem.get_objective()
	var progress := GlobalData.board_objective_progress
	var required := GlobalData.board_objective_required
	var pct := int(float(progress) / maxi(required, 1) * 100.0)
	objective_label.text = "OBJECTIVE\n%s\n\nProgress: %d / %d  (%d%%)\n%s" % [
		obj.get("name", "Objective"),
		progress, required, pct,
		BoardSystem.objective_desc(),
	]


func _get_status_text() -> String:
	var base_info := ""
	if GlobalData.mech_less:
		base_info = " | ON FOOT — no mech"
	if GlobalData.enemy_base_active:
		base_info += " | Enemy Base: %d%%" % int((GlobalData.enemy_base_progress / GlobalData.enemy_base_required) * 100.0)
	if not GlobalData.stalking_aces.is_empty():
		base_info += " | HUNTED by %s" % ", ".join(GlobalData.stalking_aces)
	return "Day %d | MP: %d/%d | %s%s | Rep: %d | Heat: %d | Wanted: %d | Credits: %d | Scrap: %d | Enemy Tier: %d | Security: %d | Pos: %s" % [
		GlobalData.board_day,
		GlobalData.board_mp,
		GlobalData.board_mp_max,
		BoardSystem.progress_text(),
		base_info,
		GlobalData.reputation,
		GlobalData.heat,
		GlobalData.wanted_level,
		GlobalData.credits,
		GlobalData.scrap,
		GlobalData.enemy_tech_tier,
		int(GlobalData.get_fleet_security()),
		str(GlobalData.current_tile)
	]


func _on_state_changed(old_state: String, new_state: String) -> void:
	if new_state == "BOARD":
		if old_state == "COMBAT":
			visible = false
		status_label.text = _get_status_text()
		_update_objective_panel()
	elif new_state == "COMBAT":
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


func _on_inventory_pressed() -> void:
	current_view = "inventory"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_inventory_text()


# Pilot Status view: the pilot's own HP/weapons/ammo/items (separate from the
# mech). Healing items are used here — the pilot heals with items, not direct
# credits, so the buy option lives on the City (trading) node.
func _on_pilot_pressed() -> void:
	current_view = "pilot"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_pilot_text()

	for entry in GlobalData.get_pilot_items():
		var item_id := str(entry.get("id", ""))
		var item := PilotSystem.get_heal_item(item_id)
		if item.is_empty():
			continue
		var heal_text := "full HP" if int(item.get("heal", 0)) <= 0 else "%d HP" % int(item.get("heal", 0))
		var btn = Button.new()
		btn.text = "Use %s (heals %s) x%d" % [
			item.get("name", item_id), heal_text, int(entry.get("count", 0))
		]
		btn.disabled = not GlobalData.get_pilot_hp() < GlobalData.get_pilot_max_hp()
		btn.tooltip_text = str(item.get("desc", ""))
		btn.pressed.connect(_use_pilot_item.bind(item_id))
		action_container.add_child(btn)


func _use_pilot_item(item_id: String) -> void:
	var restored := GlobalData.use_pilot_heal_item(item_id)
	if restored > 0.0:
		status_label.text = _get_status_text() + "  [Pilot healed +%d HP]" % int(restored)
	else:
		status_label.text = _get_status_text() + "  [No item / pilot already at full HP]"
	_on_pilot_pressed()


func _build_pilot_text() -> String:
	var text := "=== PILOT STATUS (the pilot, not the mech) ===\n\n"
	text += "HP: %d / %d\n" % [int(GlobalData.get_pilot_hp()), int(GlobalData.get_pilot_max_hp())]
	if GlobalData.get_pilot_hp() < GlobalData.get_pilot_max_hp():
		text += "STATUS: INJURED — use healing items (bought at City nodes).\n"
	else:
		text += "STATUS: HEALTHY\n"
	text += "\n--- Personal Weapons ---\n"
	var weapons := GlobalData.get_pilot_weapons()
	if weapons.is_empty():
		text += "(None)\n"
	else:
		for wp in weapons:
			text += "- %s\n" % (wp.weapon_name if wp else "?")
	text += "\n--- Personal Ammo ---\n"
	text += "Kinetic: %d | Energy: %d | Explosive: %d | Missile: %d\n" % [
		GlobalData.get_pilot_ammo("kinetic"),
		GlobalData.get_pilot_ammo("energy"),
		GlobalData.get_pilot_ammo("explosive"),
		GlobalData.get_pilot_ammo("missile"),
	]
	text += "\n--- Items ---\n"
	var items := GlobalData.get_pilot_items()
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


func _on_research_pressed() -> void:
	current_view = "research"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_research_text()

	# Start buttons for available projects
	for project in GlobalData.research_blueprints:
		var project_id = project.get("id", "")
		if GlobalData.is_research_active(project_id) or GlobalData.is_research_completed(project_id):
			continue
		var cost = int(project.get("data_cores", 1))
		var has_cores = GlobalData.data_cores >= cost
		var btn = Button.new()
		btn.text = "Start: %s (%d core%s)" % [
			project.get("name", project_id), cost, "s" if cost != 1 else ""
		]
		btn.disabled = not has_cores
		btn.pressed.connect(_start_research.bind(project_id))
		action_container.add_child(btn)


func _start_research(project_id: String) -> void:
	if GlobalData.start_research(project_id):
		status_label.text = _get_status_text() + "  [Research started: %s]" % GlobalData.get_research_project(project_id).get("name", project_id)
		_on_research_pressed()  # refresh list
	else:
		status_label.text = _get_status_text() + "  [Not enough data cores / already active]"


func _build_research_text() -> String:
	var text = "=== RESEARCH BASE ===\n\n"
	text += "Data Cores (blueprints): %d\n\n" % GlobalData.data_cores
	text += "Research advances 1 point per day, +2 per combat won.\n\n"

	text += "--- Active Projects ---\n"
	if GlobalData.research_projects.is_empty():
		text += "(None)\n"
	else:
		for project_id in GlobalData.research_projects:
			var state = GlobalData.research_projects[project_id]
			var project = GlobalData.get_research_project(project_id)
			text += "%s: %d/%d\n" % [
				project.get("name", project_id),
				int(state.get("progress", 0)),
				int(state.get("required", 1))
			]
	text += "\n"

	text += "--- Unlocked ---\n"
	if GlobalData.research_unlocked.is_empty():
		text += "(Nothing researched yet)\n"
	else:
		for project_id in GlobalData.research_unlocked:
			text += "- %s\n" % GlobalData.get_research_project(project_id).get("name", project_id)
	text += "\n"

	text += "--- Available Blueprints ---\n"
	for project in GlobalData.research_blueprints:
		var project_id = project.get("id", "")
		if GlobalData.is_research_active(project_id) or GlobalData.is_research_completed(project_id):
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
	var seated := GlobalData.get_seated_template_ids()
	for unit in GlobalData.fleet_roster:
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
	var unit = GlobalData.get_fleet_unit(template_id)
	if unit.is_empty():
		return
	GlobalData.set_unit_fielded(template_id, not unit.get("fielded", true))
	_on_fleet_pressed()  # refresh


func _build_fleet_text() -> String:
	var text = "=== FLEET ROSTER ===\n\n"
	text += "Fielded units fight alongside you in combat.\n\n"
	if GlobalData.fleet_roster.is_empty():
		text += "No units yet. Research blueprints at the Research Base to unlock squadmates."
		return text
	# Feature 7: only units with a pilot seated in a hangar mech can field.
	# Template-only units (no berth) are dropped from the field and hidden here
	# — the hangar SORTIE page is where the lineup is chosen.
	var seated := GlobalData.get_seated_template_ids()
	var shown := 0
	for unit in GlobalData.fleet_roster:
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
	var affiliation := GlobalData.get_run_affiliation()
	var text = "=== CONVOY ===\n\n"
	text += "Affiliation: %s\n" % affiliation.get("name", GlobalData.theme_id)
	text += "Transport: %s\n\n" % affiliation.get("transport", "Truck convoy")
	text += "%s\n\n" % affiliation.get("transport_desc", "")
	if GlobalData.mech_less:
		text += "STATUS: ON FOOT — every mech is gone.\n"
		text += "Board combat tiles become recovery missions until a replacement chassis is found.\n"
	else:
		text += "STATUS: %d/%d mech berths parked.\n" % [GlobalData.hangar_mechs.size(), GlobalData.get_hangar_capacity()]
	text += "\n"
	text += "Pilots in convoy: %d\n" % GlobalData.get_hangar_fleet_size()
	text += "Reserve ammo: Kin %d | En %d | Exp %d | Ms %d\n" % [
		GlobalData.get_reserve_ammo("kinetic"),
		GlobalData.get_reserve_ammo("energy"),
		GlobalData.get_reserve_ammo("explosive"),
		GlobalData.get_reserve_ammo("missile")
	]
	return text


func _on_security_pressed() -> void:
	current_view = "security"
	info_panel.visible = true
	_clear_actions()
	info_label.text = _build_security_text()
	_upgrade_security_button()


func _upgrade_security_button() -> void:
	if GlobalData.get_fleet_security() >= GlobalData.FLEET_SECURITY_MAX:
		return
	var cost := GlobalData.get_security_upgrade_cost()
	var btn = Button.new()
	btn.text = "Upgrade Security (%d credits)" % cost
	btn.disabled = GlobalData.credits < cost
	btn.pressed.connect(_on_upgrade_security_pressed)
	action_container.add_child(btn)


func _on_upgrade_security_pressed() -> void:
	if GlobalData.upgrade_fleet_security():
		_on_security_pressed()  # refresh
	else:
		status_label.text = _get_status_text() + "  [Not enough credits / maxed out]"


func _build_security_text() -> String:
	var text = "=== FLEET SECURITY ===\n\n"
	text += "Fleet security hardens our ships and facility against enemy spies.\n\n"
	text += "Security: %d / %d\n" % [int(GlobalData.get_fleet_security()), int(GlobalData.FLEET_SECURITY_MAX)]
	text += "Hardening level: %d\n" % GlobalData.security_upgrade_level
	text += "Spy counter chance: %d%%\n\n" % int(GlobalData.get_spy_counter_chance() * 100.0)
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
	text += "Chassis: %s\n" % GlobalData.chassis_id
	text += "Credits: %d\n" % GlobalData.credits
	text += "Scrap: %d\n" % GlobalData.scrap
	text += "Data Cores: %d\n\n" % GlobalData.data_cores

	text += "--- Armor Parts ---\n"
	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		if not part:
			continue
		var dmg = GlobalData.part_damage.get(slot, 0.0)
		if part is ArmorPart:
			var status = "OK" if dmg < part.break_threshold else "BROKEN"
			text += "%s: %s (HP: %.0f, W: %.1f) [%s]\n" % [
				part.part_name, slot, part.max_hp, part.weight, status
			]
		elif part is Dictionary:
			var status = "OK" if dmg < 0.9 else "BROKEN"
			text += "%s: %s (HP: %.0f, W: %.1f) [%s]\n" % [
				part.get("name", part.get("part_name", "Part")), slot,
				part.get("hp", part.get("max_hp", 0.0)), part.get("weight", 0.0), status
			]
	return text


func _build_inventory_text() -> String:
	var text = "=== INVENTORY & RESERVES ===\n\n"
	text += "Credits: %d\n" % GlobalData.credits
	text += "Scrap (Material): %d\n" % GlobalData.scrap
	text += "Data Cores (Research): %d\n\n" % GlobalData.data_cores

	text += "--- Reserve Ammo Stock ---\n"
	text += "Kinetic Ammo: %d\n" % GlobalData.get_reserve_ammo("kinetic")
	text += "Energy Cells: %d\n" % GlobalData.get_reserve_ammo("energy")
	text += "Explosive Shells: %d\n" % GlobalData.get_reserve_ammo("explosive")
	text += "Missile Pods: %d\n\n" % GlobalData.get_reserve_ammo("missile")

	text += "--- Weapon Inventory ---\n"
	if GlobalData.weapon_inventory.is_empty():
		text += "(No weapons in stash)\n"
	else:
		for item in GlobalData.weapon_inventory:
			var w_name = item.get("name", "Unknown Weapon")
			text += "- %s (%.0f%%)\n" % [w_name, GlobalData.get_durability_ratio(item) * 100.0]
	text += "\n"

	text += "--- Armor Inventory ---\n"
	if GlobalData.armor_inventory.is_empty():
		text += "(No armor in inventory)\n"
	else:
		for item in GlobalData.armor_inventory:
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
	text += "Map theme: %s\n" % GlobalData.board_theme_id.capitalize()
	text += "Position: %s\n" % str(GlobalData.current_tile)
	text += "Day: %d | MP: %d / %d\n" % [GlobalData.board_day, GlobalData.board_mp, GlobalData.board_mp_max]
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
