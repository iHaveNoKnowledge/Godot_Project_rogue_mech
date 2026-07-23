extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var info_label: Label
var heal_button: Button
var repair_button: Button
var leave_button: Button
var status_label: Label

var heal_cost: int = 20
var repair_cost: int = 30
var heal_amount: float = 0.3  # 30% of max HP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false
	EventBus.tile_entered.connect(_on_tile_entered)


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Center panel
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -150
	panel.offset_bottom = 150
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.2, 0.1, 0.95)
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
	title_label.text = "SAFEHOUSE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_label)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	info_label = Label.new()
	info_label.text = "You found a safehouse.\nRest to heal or repair your mech."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info_label)

	# Buttons
	heal_button = Button.new()
	heal_button.text = "Rest (Heal 30%%) - %d credits" % heal_cost
	heal_button.custom_minimum_size = Vector2(300, 40)
	heal_button.pressed.connect(_on_heal_pressed)
	vbox.add_child(heal_button)

	repair_button = Button.new()
	repair_button.text = "Full Repair - %d credits" % repair_cost
	repair_button.custom_minimum_size = Vector2(300, 40)
	repair_button.pressed.connect(_on_repair_pressed)
	vbox.add_child(repair_button)

	leave_button = Button.new()
	leave_button.text = "Leave Safehouse"
	leave_button.custom_minimum_size = Vector2(300, 40)
	leave_button.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_button)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)


func _on_tile_entered(pos: Vector2i, _data) -> void:
	var tile_type = _get_tile_type(pos)
	if tile_type == "safehouse":
		visible = true
		_update_info()
		get_tree().paused = true


func _get_tile_type(pos: Vector2i) -> String:
	# Get tile type from the board
	var board_manager = get_tree().current_scene
	if board_manager and board_manager.has_method("get_tile_type"):
		return board_manager.get_tile_type(pos)
	return "empty"


func _update_info() -> void:
	var health = _get_player_health()
	info_label.text = "You found a safehouse.\nRest to heal or repair your mech.\n\nCurrent HP: %d%%" % int(health * 100)
	status_label.text = "Credits: %d" % GlobalData.credits


func _get_player_health() -> float:
	# This will be called from the board scene
	# For now, return a default value
	return 1.0


func _on_heal_pressed() -> void:
	if GlobalData.credits >= heal_cost:
		GlobalData.credits -= heal_cost
		status_label.text = "Healed! Credits: %d" % GlobalData.credits
		EventBus.heal_requested.emit(heal_amount)
	else:
		status_label.text = "Not enough credits!"
	_update_info()


func _on_repair_pressed() -> void:
	if GlobalData.credits >= repair_cost:
		GlobalData.credits -= repair_cost
		GlobalData.part_damage.clear()
		status_label.text = "Repaired! Credits: %d" % GlobalData.credits
		EventBus.repair_requested.emit()
	else:
		status_label.text = "Not enough credits!"
	_update_info()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
	GameManager.return_to_board()
