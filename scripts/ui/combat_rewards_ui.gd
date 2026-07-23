extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var rewards_label: Label
var continue_button: Button

var rewards: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.combat_ended.connect(_on_combat_ended)


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Center panel
	panel = PanelContainer.new()
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
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(200, 40)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)


func _on_combat_ended(victory: bool) -> void:
	if victory:
		_show_victory_rewards()
	else:
		_show_defeat_screen()


func _show_victory_rewards() -> void:
	visible = true
	title_label.text = "COMBAT VICTORY"
	get_tree().paused = true

	# Calculate rewards
	var credits_gained = randi_range(30, 80)
	var spare_parts_gained = randi_range(1, 5)
	var heat_gained = 2

	GlobalData.credits += credits_gained
	GlobalData.spare_parts += spare_parts_gained

	rewards = {
		"credits": credits_gained,
		"spare_parts": spare_parts_gained,
		"heat": heat_gained,
	}

	rewards_label.text = "Rewards:\n"
	rewards_label.text += "+%d Credits\n" % credits_gained
	rewards_label.text += "+%d Spare Parts\n" % spare_parts_gained
	rewards_label.text += "+%d Heat\n" % heat_gained
	rewards_label.text += "\nTotal Credits: %d" % GlobalData.credits


func _show_defeat_screen() -> void:
	visible = true
	title_label.text = "DEFEATED"
	rewards_label.text = "Your mech has been destroyed.\n\nReturning to main menu..."
	get_tree().paused = true


func _on_continue_pressed() -> void:
	visible = false
	get_tree().paused = false
	if title_label.text == "DEFEATED":
		GameManager.game_over()
	else:
		GameManager.return_to_board()
