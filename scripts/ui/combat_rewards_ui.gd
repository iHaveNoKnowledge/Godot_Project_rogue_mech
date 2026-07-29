extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var rewards_label: Label
var continue_button: Button

var rewards: Dictionary = {}


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.combat_ended.connect(_on_combat_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_pressed() and not event.is_echo():
		if event is InputEventKey:
			if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
				get_viewport().set_input_as_handled()
				_on_continue_pressed()


func _create_ui() -> void:
	root_control = Control.new()
	root_control.process_mode = Node.PROCESS_MODE_ALWAYS
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Center panel
	panel = PanelContainer.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -150
	panel.offset_bottom = 150
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 25
	style.content_margin_right = 25
	style.content_margin_top = 25
	style.content_margin_bottom = 25
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "COMBAT VICTORY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	rewards_label = Label.new()
	rewards_label.text = ""
	rewards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(rewards_label)

	continue_button = Button.new()
	continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	continue_button.text = "Continue [Enter / Space / Click]"
	continue_button.custom_minimum_size = Vector2(200, 44)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)


func _on_combat_ended(victory: bool) -> void:
	if victory:
		_show_victory_rewards()
	else:
		_show_defeat_screen()


func _show_victory_rewards() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var is_boss = GameManager.is_boss_combat
	var is_final_sector = (GlobalData.current_sector >= GlobalData.max_sectors)

	var credits_gained = randi_range(30, 80)
	var spare_parts_gained = randi_range(1, 5)
	var heat_gained = 2
	var data_cores_gained = 0

	if is_boss:
		title_label.text = "SECTOR %d CLEARED!" % GlobalData.current_sector
		credits_gained += 100
		spare_parts_gained += 5
		data_cores_gained = 1
		GlobalData.data_cores += data_cores_gained

		if is_final_sector:
			title_label.text = "CAMPAIGN VICTORY!"
			continue_button.text = "Finish Run [Enter / Space]"
		else:
			continue_button.text = "Proceed to Sector %d [Enter / Space]" % (GlobalData.current_sector + 1)
	else:
		title_label.text = "COMBAT VICTORY"
		continue_button.text = "Continue [Enter / Space / Click]"

	GlobalData.credits += credits_gained
	GlobalData.spare_parts += spare_parts_gained

	rewards = {
		"credits": credits_gained,
		"spare_parts": spare_parts_gained,
		"heat": heat_gained,
		"data_cores": data_cores_gained
	}

	rewards_label.text = "Rewards:\n"
	rewards_label.text += "+%d Credits\n" % credits_gained
	rewards_label.text += "+%d Spare Parts\n" % spare_parts_gained
	if data_cores_gained > 0:
		rewards_label.text += "+%d Data Cores (Boss Bonus)\n" % data_cores_gained
	rewards_label.text += "+%d Heat\n" % heat_gained
	rewards_label.text += "\nTotal Credits: %d" % GlobalData.credits

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _show_defeat_screen() -> void:
	visible = true
	title_label.text = "DEFEATED"
	rewards_label.text = "Your mech has been destroyed.\n\nReturning to main menu..."
	continue_button.text = "Continue [Enter / Space / Click]"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()


func _on_continue_pressed() -> void:
	visible = false
	get_tree().paused = false
	if title_label.text == "DEFEATED":
		GameManager.game_over()
	elif GameManager.is_boss_combat:
		if GlobalData.current_sector >= GlobalData.max_sectors:
			GameManager.end_run(true)
		else:
			GameManager.advance_to_next_sector()
	else:
		GameManager.return_to_board()
