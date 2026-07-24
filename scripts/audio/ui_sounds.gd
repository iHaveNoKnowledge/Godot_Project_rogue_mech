extends Node

## UI sound effects - connect to button presses.


func _ready() -> void:
	# Connect to all buttons in the scene tree
	await get_tree().process_frame
	_connect_buttons()


func _connect_buttons() -> void:
	var buttons = get_tree().get_nodes_in_group("ui_button")
	for button in buttons:
		if button is BaseButton and not button.pressed.is_connected(_on_button_pressed):
			button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: Node = null) -> void:
	if has_node("/root/AudioManager"):
		AudioManager.play_ui_click()


func play_menu_open() -> void:
	if has_node("/root/AudioManager"):
		AudioManager.play_ui_confirm()
