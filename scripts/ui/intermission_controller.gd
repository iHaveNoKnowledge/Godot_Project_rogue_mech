extends CanvasLayer

var root_control: Control
var menu_container: VBoxContainer
var info_panel: PanelContainer
var info_label: Label
var status_panel: PanelContainer
var status_label: Label
var current_view: String = "menu"


func _ready() -> void:
	_create_ui()
	_show_menu()
	visible = true
	EventBus.game_state_changed.connect(_on_state_changed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameManager.current_state == GameManager.State.BOARD:
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
	menu_panel.offset_left = 10
	menu_panel.offset_top = 10
	menu_panel.offset_bottom = -10
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
	_add_menu_button("Board Info", _on_board_info_pressed)
	_add_menu_button("Hangar", _on_hangar_pressed)
	_add_menu_button("Save Game", _on_save_pressed)
	_add_menu_button("Load Game", _on_load_pressed)
	_add_menu_button("Exit to Menu", _on_exit_pressed)

	# Info panel (right side)
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	info_panel.offset_left = 270
	info_panel.offset_right = -10
	info_panel.offset_top = 10
	info_panel.offset_bottom = -10
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

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(info_label)

	# Status panel (bottom)
	status_panel = PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_panel.offset_top = -60
	status_panel.offset_left = 10
	status_panel.offset_right = -10
	status_panel.offset_bottom = -10
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
	return "Heat: %d | Wanted: %d | Credits: %d | Tile: %s" % [
		GlobalData.heat,
		GlobalData.wanted_level,
		GlobalData.credits,
		str(GlobalData.current_tile)
	]


func _on_state_changed(_old: String, new: String) -> void:
	if new == "BOARD":
		visible = true
		status_label.text = _get_status_text()
	elif new == "COMBAT":
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
	info_label.text = _build_mech_status_text()


func _on_inventory_pressed() -> void:
	current_view = "inventory"
	info_panel.visible = true
	info_label.text = _build_inventory_text()


func _on_board_info_pressed() -> void:
	current_view = "board_info"
	info_panel.visible = true
	info_label.text = _build_board_info_text()


func _on_hangar_pressed() -> void:
	var hangar = get_tree().current_scene.get_node_or_null("HangarUI")
	if hangar:
		hangar.show_hangar()


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
	text += "Spare Parts: %d\n" % GlobalData.spare_parts
	text += "Data Cores: %d\n\n" % GlobalData.data_cores

	text += "--- Armor Parts ---\n"
	for slot in GlobalData.equipped_parts:
		var part: ArmorPart = GlobalData.equipped_parts[slot]
		if part:
			var dmg = GlobalData.part_damage.get(slot, 0.0)
			var status = "OK" if dmg < part.break_threshold else "BROKEN"
			text += "%s: %s (HP: %.0f, W: %.1f) [%s]\n" % [
				part.part_name, slot, part.max_hp, part.weight, status
			]
	return text


func _build_inventory_text() -> String:
	var text = "=== INVENTORY ===\n\n"
	text += "Credits: %d\n" % GlobalData.credits
	text += "Spare Parts: %d\n" % GlobalData.spare_parts
	text += "Data Cores: %d\n\n" % GlobalData.data_cores

	text += "--- Equipped Weapons ---\n"
	# This would need weapon manager reference - for now show parts
	text += "(Weapons tracked in WeaponManager)\n\n"

	text += "--- Salvaged Weapons ---\n"
	if has_node("/root/SalvageSystem"):
		var salvage = get_node("/root/SalvageSystem")
		text += "Tagged: %d\n" % salvage.get_salvaged_count()
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
