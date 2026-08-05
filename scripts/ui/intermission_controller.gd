extends CanvasLayer

var root_control: Control
var menu_container: VBoxContainer
var info_panel: PanelContainer
var info_label: Label
var status_panel: PanelContainer
var status_label: Label
var action_container: VBoxContainer
var current_view: String = "menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	_show_menu()
	EventBus.game_state_changed.connect(_on_state_changed)
	visibility_changed.connect(_on_visibility_changed)
	if visible:
		AudioManager.play_menu_music()


func _on_visibility_changed() -> void:
	if visible:
		AudioManager.play_menu_music()


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
	_add_menu_button("Mech Status", _on_status_pressed)
	_add_menu_button("Inventory", _on_inventory_pressed)
	_add_menu_button("Research Base", _on_research_pressed)
	_add_menu_button("Fleet Roster", _on_fleet_pressed)
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
	info_panel.offset_top = 20
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


func _get_status_text() -> String:
	var base_info := ""
	if GlobalData.enemy_base_active:
		base_info = " | Enemy Base: %d%%" % int((GlobalData.enemy_base_progress / GlobalData.enemy_base_required) * 100.0)
	if not GlobalData.stalking_aces.is_empty():
		base_info += " | HUNTED by %s" % ", ".join(GlobalData.stalking_aces)
	return "Rep: %d | Heat: %d | Wanted: %d | Credits: %d | Scrap: %d | Enemy Tier: %d | Security: %d%s | Tile: %s" % [
		GlobalData.reputation,
		GlobalData.heat,
		GlobalData.wanted_level,
		GlobalData.credits,
		GlobalData.scrap,
		GlobalData.enemy_tech_tier,
		int(GlobalData.get_fleet_security()),
		base_info,
		str(GlobalData.current_tile)
	]


func _on_state_changed(old_state: String, new_state: String) -> void:
	if new_state == "BOARD":
		if old_state == "COMBAT":
			visible = false
		status_label.text = _get_status_text()
	elif new_state == "COMBAT":
		visible = false


func _show_menu() -> void:
	current_view = "menu"
	info_panel.visible = false


func _on_move_pressed() -> void:
	# Hide intermission UI, show board for tile selection
	visible = false
	get_tree().current_scene.set("showing_board", true)


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
	for project in GlobalData.gundam_research_projects:
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
	text += "Research advances 1 point per board move, +2 per combat won.\n\n"

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
	for project in GlobalData.gundam_research_projects:
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

	# Fielded toggle per unit
	for unit in GlobalData.fleet_roster:
		if not (unit is Dictionary):
			continue
		var template_id = unit.get("template_id", "")
		var fielded = unit.get("fielded", true)
		var destroyed = unit.get("destroyed", false)
		var btn = Button.new()
		btn.text = "%s: %s" % [unit.get("name", template_id), "FIELDED" if fielded else "STANDING DOWN"]
		btn.disabled = destroyed
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
	for unit in GlobalData.fleet_roster:
		var state = "ACTIVE" if unit.get("fielded", true) else "STANDBY"
		if unit.get("destroyed", false):
			state = "DESTROYED"
		text += "- %s [%s] HP: %d/%d\n" % [
			unit.get("name", unit.get("template_id", "?")),
			state,
			int(unit.get("hp", 0)),
			int(unit.get("max_hp", 0))
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
	text += "Position: %s\n" % str(GlobalData.current_tile)
	text += "Heat: %d / 15\n" % GlobalData.heat
	text += "Wanted Level: %d\n\n" % GlobalData.wanted_level

	text += "--- Tile Types ---\n"
	text += "Combat (40%) - Fight enemies\n"
	text += "Event (30%) - Random events\n"
	text += "Safehouse (15%) - Rest/repair\n"
	text += "Empty (15%) - Nothing\n\n"

	text += "--- Nearby Tiles ---\n"
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var dir_names = ["East", "West", "South", "North"]
	for i in range(4):
		var pos = GlobalData.current_tile + directions[i]
		text += "%s: %s\n" % [dir_names[i], str(pos)]
	return text
