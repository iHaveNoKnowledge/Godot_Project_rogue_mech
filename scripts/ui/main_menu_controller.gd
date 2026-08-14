extends Control


func _ready() -> void:
	_create_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if AudioManager:
		AudioManager.play_menu_music()


func _create_ui() -> void:
	# Root fills screen but lets children handle mouse
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 300)
	center.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "MECHA ROGUELIKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# New Game
	var new_game_btn = _make_button("New Game", Color(0.3, 0.7, 0.4))
	new_game_btn.pressed.connect(_on_new_game_pressed)
	vbox.add_child(new_game_btn)

	# Continue
	var continue_btn = _make_button("Continue", Color(0.3, 0.6, 1.0))
	continue_btn.pressed.connect(_on_continue)
	continue_btn.disabled = not FileAccess.file_exists(GlobalData.SAVE_PATH)
	vbox.add_child(continue_btn)

	# Quit
	var quit_btn = _make_button("Quit", Color(0.9, 0.3, 0.3))
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)


func _make_button(text: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 40)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.18, 0.25, 0.9)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = accent.darkened(0.4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = accent.darkened(0.6)
	hover.corner_radius_top_left = 6
	hover.corner_radius_top_right = 6
	hover.corner_radius_bottom_left = 6
	hover.corner_radius_bottom_right = 6
	hover.border_width_left = 2
	hover.border_width_right = 2
	hover.border_width_top = 2
	hover.border_width_bottom = 2
	hover.border_color = accent
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	return btn


func _on_new_game() -> void:
	GlobalData.reset_run_data()
	GameManager.enter_board()


func _on_new_game_pressed() -> void:
	_show_theme_select()


func _show_theme_select() -> void:
	var overlay = CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.name = "ThemeSelect"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel = PanelContainer.new()
	overlay.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.16, 0.98)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "CHOOSE YOUR STORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	for theme in GlobalData.run_themes:
		if not (theme is Dictionary):
			continue
		var btn = Button.new()
		btn.text = "%s\n%s" % [theme.get("name", "?"), theme.get("flavor", "")]
		btn.custom_minimum_size = Vector2(360, 60)
		btn.pressed.connect(_on_theme_chosen.bind(str(theme.get("id", "soldier"))))
		vbox.add_child(btn)

	var cancel = Button.new()
	cancel.text = "Back"
	cancel.pressed.connect(overlay.queue_free)
	vbox.add_child(cancel)


func _on_theme_chosen(theme_id: String) -> void:
	var theme_select = get_node_or_null("ThemeSelect")
	if theme_select:
		theme_select.queue_free()
	GlobalData.reset_run_data()
	GlobalData.theme_id = theme_id
	GlobalData.roll_random_start()
	GameManager.enter_board()


func _on_continue() -> void:
	if GlobalData.load_run():
		GameManager.enter_board()


func _on_quit() -> void:
	get_tree().quit(0)
