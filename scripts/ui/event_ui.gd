extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var desc_label: Label
var continue_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.event_triggered.connect(_on_event_triggered)


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Center panel
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -100
	panel.offset_bottom = 100
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.2, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "RANDOM EVENT"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	desc_label = Label.new()
	desc_label.text = ""
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_label)

	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(200, 40)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)


func _on_event_triggered(event: Dictionary) -> void:
	visible = true
	title_label.text = event.get("name", "RANDOM EVENT")
	desc_label.text = event.get("desc", "Something happened!")
	get_tree().paused = true


func _on_continue_pressed() -> void:
	visible = false
	get_tree().paused = false
	GameManager.return_to_board()
