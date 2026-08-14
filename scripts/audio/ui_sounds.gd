extends Node

## UI sound effects - connect to button presses.
##
## Automatically wires a click sound to every BaseButton in the scene tree,
## including buttons created at runtime (e.g. the hangar builds all of its UI
## in code). Drop custom sound files into res://resources/audio/ui/ to replace
## the procedurally generated tones (see AudioManager._generate_sounds()):
##   - click.wav / click.ogg / click.mp3  -> button press (ui_click)
##   - confirm.wav / confirm.ogg / confirm.mp3 -> play_menu_open() (ui_confirm)
## When a matching file exists it is used automatically; otherwise the built-in
## tone plays.


func _ready() -> void:
	# Wire buttons that already exist, then keep wiring ones added later.
	_connect_buttons()
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)


func _connect_buttons() -> void:
	var all_buttons := get_tree().get_nodes_in_group("ui_button")
	all_buttons.append_array(get_tree().root.find_children("*", "BaseButton", true, false))
	for button in all_buttons:
		_connect_button(button)


func _connect_button(button: BaseButton) -> void:
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: Node = null) -> void:
	if AudioManager:
		AudioManager.play_ui_click()


func play_menu_open() -> void:
	if AudioManager:
		AudioManager.play_ui_confirm()
