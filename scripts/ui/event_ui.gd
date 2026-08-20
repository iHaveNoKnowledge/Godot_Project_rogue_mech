extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var title_label: Label
var desc_label: Label
var continue_button: Button
var choice_container: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_create_ui()
	visible = false
	EventBus.event_triggered.connect(_on_event_triggered)


# ESC closes the popup exactly like the Continue button. This also stops the
# pause key from bubbling to the intermission menu while a popup is up (the
# intermission skips opening when the tree is paused), so closing a "NO
# MOVEMENT LEFT" popup can never leave the player stuck with no menu access.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_on_continue_pressed()


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

	# Choice buttons are added dynamically for choice/theme_switch events.
	choice_container = VBoxContainer.new()
	choice_container.add_theme_constant_override("separation", 8)
	vbox.add_child(choice_container)


func _on_event_triggered(event: Dictionary) -> void:
	# The board scene can emit events during a scene swap (e.g. a forced combat
	# entry frees the board before its end-of-day event fires). An EventUI that
	# is no longer in the tree must ignore the popup instead of crashing on
	# get_tree() == null.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	visible = true
	title_label.text = event.get("name", "RANDOM EVENT")
	desc_label.text = event.get("desc", "Something happened!")
	tree.paused = true

	# Multi-choice events swap the single Continue button for one button per choice.
	var choices: Array = event.get("params", {}).get("choices", [])
	_clear_choices()
	if choices is Array and not choices.is_empty():
		continue_button.visible = false
		for choice in choices:
			if not (choice is Dictionary):
				continue
			var btn = Button.new()
			btn.text = str(choice.get("label", "Continue"))
			btn.custom_minimum_size = Vector2(200, 36)
			btn.pressed.connect(_on_choice_pressed.bind(choice))
			choice_container.add_child(btn)
		if choice_container.get_child_count() > 0:
			choice_container.get_child(0).grab_focus()
	else:
		continue_button.visible = true
		continue_button.grab_focus()


func _clear_choices() -> void:
	for child in choice_container.get_children():
		child.queue_free()


func _on_choice_pressed(choice: Dictionary) -> void:
	if not is_inside_tree():
		return
	var forced := ThemeSystem.apply_event_effect(choice)
	if forced:
		# The choice sprang a trap — jump straight into battle.
		visible = false
		if get_tree():
			get_tree().paused = false
		GameManager.enter_combat(str(choice.get("params", {}).get("combat_type", "grunt")))
	else:
		_resume_from_popup()


func _on_continue_pressed() -> void:
	if not is_inside_tree():
		return
	_resume_from_popup()


# Closes the popup and returns to walking. While already on the BOARD the scene
# must NOT be reloaded — reloading regenerates the board layout and restarts the
# intermission music, interrupting the walk after every event popup. Instead the
# popup just unpauses (the effects were already applied to GlobalData) and the
# board refreshes its patrol markers / highlights. After combat / hangar the
# state is not BOARD, so return_to_board() (which loads the board scene) runs.
func _resume_from_popup() -> void:
	visible = false
	if get_tree():
		get_tree().paused = false
	if GameManager.current_state == GameManager.State.BOARD:
		GlobalData.save_run()
		var board = get_tree().current_scene if get_tree() else null
		if board and board.has_method("refresh_after_event"):
			board.refresh_after_event()
		return
	GameManager.return_to_board()
