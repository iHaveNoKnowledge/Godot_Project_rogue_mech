extends Control

var new_game_button: Button
var continue_button: Button
var quit_button: Button


func _ready() -> void:
	_create_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _create_ui() -> void:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	center.add_child(vbox)

	var title_label = Label.new()
	title_label.text = "MECHA ROGUELIKE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	new_game_button = Button.new()
	new_game_button.text = "New Game"
	new_game_button.pressed.connect(_on_new_game)
	new_game_button.add_to_group("ui_button")
	vbox.add_child(new_game_button)

	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.pressed.connect(_on_continue)
	continue_button.disabled = not FileAccess.file_exists(GlobalData.SAVE_PATH)
	continue_button.add_to_group("ui_button")
	vbox.add_child(continue_button)

	quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(_on_quit)
	quit_button.add_to_group("ui_button")
	vbox.add_child(quit_button)


func _on_new_game() -> void:
	GlobalData.equipped_parts.clear()
	GlobalData.part_damage.clear()
	GlobalData.heat = 0
	GlobalData.wanted_level = 0
	GlobalData.credits = 100
	GameManager.enter_board()


func _on_continue() -> void:
	if GlobalData.load_run():
		GameManager.enter_board()


func _on_quit() -> void:
	get_tree().quit()
