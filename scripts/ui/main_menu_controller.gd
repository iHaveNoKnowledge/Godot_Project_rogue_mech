extends Control


func _ready() -> void:
	_create_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if AudioManager:
		AudioManager.play_menu_music()


func _create_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Mono Tactical — Ultra Minimal: flat near-black + 1px hairlines, no gradients
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.06, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Subtle tactical grid (1px lines every 64px, very low alpha)
	var grid = _build_grid_overlay()
	add_child(grid)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 360)
	center.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.09, 1.0)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.22, 0.22, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header block: readable mono-tactical (Medium/SemiBold, higher contrast)
	var title = Label.new()
	title.text = "MECHA  ROGUELIKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96, 1.0))
	title.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-SemiBold.ttf"))
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "TACTICAL  //  SECTOR 01  //  CONVOY OPS"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68, 1.0))
	subtitle.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	vbox.add_child(subtitle)

	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", _hairline_style(Color(0.20, 0.20, 0.20, 1.0)))
	vbox.add_child(sep)

	var hint = Label.new()
	hint.text = "SELECT  OPERATION"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72, 1.0))
	hint.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	vbox.add_child(hint)

	# New Game — primary (inverted on hover)
	var new_game_btn = _make_button("NEW  GAME", true)
	new_game_btn.pressed.connect(_on_new_game_pressed)
	vbox.add_child(new_game_btn)

	# Continue — secondary
	var continue_btn = _make_button("CONTINUE", false)
	continue_btn.pressed.connect(_on_continue)
	continue_btn.disabled = not FileAccess.file_exists(GlobalData.SAVE_PATH)
	vbox.add_child(continue_btn)

	# Quit — minimal text button (no fill)
	var quit_btn = _make_button("QUIT", false, true)
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	var footer = Label.new()
	footer.text = "v0.6  //  GODOT 4.6  //  MONO TACTICAL"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 9)
	footer.add_theme_color_override("font_color", Color(0.52, 0.52, 0.52, 1.0))
	footer.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	vbox.add_child(footer)


func _hairline_style(col: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = 0
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s

func _build_grid_overlay() -> Control:
	var overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Drawn via shader-less ColorRect grid: use a CanvasItem script draw callback
	overlay.set_script(preload("res://scripts/ui/main_menu_grid.gd"))
	return overlay

func _make_button(text: String, is_primary: bool = false, is_ghost: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(284, 38)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Ultra-minimal: 1px border, 0 radius, flat fills, no shadow
	var normal = StyleBoxFlat.new()
	var hover = StyleBoxFlat.new()
	var pressed = StyleBoxFlat.new()
	var disabled = StyleBoxFlat.new()
	for s in [normal, hover, pressed, disabled]:
		s.corner_radius_top_left = 0
		s.corner_radius_top_right = 0
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 1

	if is_ghost:
		# Text-only ghost: transparent, 1px border only on hover
		normal.bg_color = Color(0, 0, 0, 0)
		normal.border_color = Color(0, 0, 0, 0)
		hover.bg_color = Color(0.09, 0.09, 0.09, 1.0)
		hover.border_color = Color(0.26, 0.26, 0.26, 1.0)
		pressed.bg_color = Color(0.07, 0.07, 0.07, 1.0)
		pressed.border_color = Color(0.22, 0.22, 0.22, 1.0)
		disabled.bg_color = Color(0, 0, 0, 0)
		disabled.border_color = Color(0, 0, 0, 0)
		btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.85, 0.85, 0.85, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.75, 0.75, 0.75, 1.0))
		btn.add_theme_color_override("font_disabled_color", Color(0.30, 0.30, 0.30, 1.0))
	else:
		normal.bg_color = Color(0.11, 0.11, 0.11, 1.0) if not is_primary else Color(0.14, 0.14, 0.14, 1.0)
		normal.border_color = Color(0.20, 0.20, 0.20, 1.0) if not is_primary else Color(0.28, 0.28, 0.28, 1.0)
		hover.bg_color = Color(0.92, 0.92, 0.92, 1.0)
		hover.border_color = Color(0.92, 0.92, 0.92, 1.0)
		pressed.bg_color = Color(0.82, 0.82, 0.82, 1.0)
		pressed.border_color = Color(0.82, 0.82, 0.82, 1.0)
		disabled.bg_color = Color(0.08, 0.08, 0.08, 1.0)
		disabled.border_color = Color(0.15, 0.15, 0.15, 1.0)
		btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.06, 0.06, 0.06, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.06, 1.0))
		btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.35, 1.0))

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	btn.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))

	return btn


func _on_new_game() -> void:
	GlobalData.reset_run_data()
	GameManager.enter_board()


func _on_new_game_pressed() -> void:
	_show_theme_select()


func _show_theme_select() -> void:
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.name = "ThemeSelect"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.09, 1.0)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.22, 0.22, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "CHOOSE  STORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	title.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "SELECT  RUN  THEME  //  1  OF  %d" % GlobalData.run_themes.size()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 8)
	sub.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 1.0))
	vbox.add_child(sub)

	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", _hairline_style(Color(0.18, 0.18, 0.18, 1.0)))
	vbox.add_child(sep)

	for theme in GlobalData.run_themes:
		if not (theme is Dictionary):
			continue
		var tname = str(theme.get("name", "?")).to_upper()
		var tflavor = str(theme.get("flavor", ""))
		var btn = _make_button("%s  //  %s" % [tname, tflavor], false)
		# Theme buttons: single line, denser
		btn.custom_minimum_size = Vector2(332, 36)
		btn.pressed.connect(_on_theme_chosen.bind(str(theme.get("id", "soldier"))))
		vbox.add_child(btn)

	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _hairline_style(Color(0.18, 0.18, 0.18, 1.0)))
	vbox.add_child(sep2)

	var cancel = _make_button("BACK", false, true)
	cancel.pressed.connect(overlay.queue_free)
	vbox.add_child(cancel)


func _on_theme_chosen(theme_id: String) -> void:
	var theme_select = get_node_or_null("ThemeSelect")
	if theme_select:
		theme_select.queue_free()
	GlobalData.reset_run_data()
	GlobalData.narrative.theme_id = theme_id
	RunStartSystem.roll_random_start()
	GameManager.enter_board()


func _on_continue() -> void:
	if GlobalData.load_run():
		GameManager.enter_board()


func _on_quit() -> void:
	get_tree().quit(0)
