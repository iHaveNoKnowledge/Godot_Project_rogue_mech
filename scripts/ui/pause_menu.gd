extends CanvasLayer

var is_paused: bool = false
var root_control: Control
var overlay: ColorRect
var panel: PanelContainer

var _bg_color: Color = Color(0.05, 0.05, 0.08, 0.92)
var _panel_color: Color = Color(0.1, 0.12, 0.18, 0.95)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1)
var _hover_color: Color = Color(0.4, 0.7, 1.0, 1)
var _danger_color: Color = Color(0.9, 0.3, 0.3, 1)
var _dim_color: Color = Color(0.5, 0.5, 0.5, 1)
var _text_color: Color = Color(0.85, 0.85, 0.85, 1)

# Control hints live in the pause screen instead of cluttering the combat HUD.
const KEYBINDS: Array = [
	{"key": "W/A/S/D", "action": "ขยับ Mecha"},
	{"key": "Mouse", "action": "หมุนกล้อง 360"},
	{"key": "LMB", "action": "ยิงมือซ้าย"},
	{"key": "RMB", "action": "ยิงมือขวา"},
	{"key": "Shift", "action": "Dash / Strafe"},
	{"key": "Space", "action": "กระโดด"},
	{"key": "F", "action": "โต้ตอบ / เก็บอาวุธ / ขึ้น Mecha"},
	{"key": "G", "action": "Eject (ทิ้ง Mecha)"},
	{"key": "E / Q", "action": "ยิงอาวุธจากไหล่ (เร็วๆ นี้)"},
	{"key": "1", "action": "สลับอาวุธมือซ้าย"},
	{"key": "3", "action": "สลับอาวุธมือขวา"},
	{"key": "X", "action": "ทิ้งอาวุธ"},
	{"key": "Tab", "action": "ล็อคเป้า / ปลดล็อคกล้อง"},
	{"key": "Esc", "action": "หยุดเกม (Pause)"},
]


func _ready() -> void:
	layer = 20
	_create_ui()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_paused:
			resume()
		elif GameManager.current_state == GameManager.State.COMBAT:
			pause()


func pause() -> void:
	is_paused = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	is_paused = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root_control)

	# Dark overlay
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	root_control.add_child(overlay)

	# Center panel — left column: menu actions, right column: control hints.
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -215
	panel.offset_bottom = 215

	var style = StyleBoxFlat.new()
	style.bg_color = _panel_color
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.4, 0.6, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(panel)

	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	panel.add_child(columns)

	# --- Left column: pause menu actions ---
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	columns.add_child(vbox)

	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var resume_btn = _create_button("Resume", _accent_color)
	resume_btn.pressed.connect(_on_resume)
	vbox.add_child(resume_btn)

	var restart_btn = _create_button("Restart Combat", Color(0.9, 0.8, 0.3, 1))
	restart_btn.pressed.connect(_on_restart)
	vbox.add_child(restart_btn)

	var abandon_btn = _create_button("Abandon Run", Color(0.8, 0.5, 0.2, 1))
	abandon_btn.pressed.connect(_on_abandon)
	vbox.add_child(abandon_btn)

	var menu_btn = _create_button("Main Menu", _danger_color)
	menu_btn.pressed.connect(_on_main_menu)
	vbox.add_child(menu_btn)

	var hint = Label.new()
	hint.text = "Press ESC to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(hint)

	# --- Right column: control hints ---
	var controls = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 3)
	columns.add_child(controls)

	var controls_title = Label.new()
	controls_title.text = "CONTROLS"
	controls_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_title.add_theme_font_size_override("font_size", 16)
	controls_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1))
	controls.add_child(controls_title)

	var controls_sep = HSeparator.new()
	controls.add_child(controls_sep)

	for bind in KEYBINDS:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		controls.add_child(row)

		var key_label = Label.new()
		key_label.text = str(bind["key"])
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", _accent_color)
		key_label.custom_minimum_size = Vector2(80, 0)
		row.add_child(key_label)

		var action_label = Label.new()
		action_label.text = str(bind["action"])
		action_label.add_theme_font_size_override("font_size", 12)
		action_label.add_theme_color_override("font_color", _text_color)
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action_label)


func _create_button(text: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 40)

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.18, 0.25, 0.9)
	normal_style.corner_radius_top_left = 0
	normal_style.corner_radius_top_right = 0
	normal_style.corner_radius_bottom_left = 0
	normal_style.corner_radius_bottom_right = 0
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = accent.darkened(0.4)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = accent.darkened(0.6)
	hover_style.corner_radius_top_left = 0
	hover_style.corner_radius_top_right = 0
	hover_style.corner_radius_bottom_left = 0
	hover_style.corner_radius_bottom_right = 0
	hover_style.border_width_left = 1
	hover_style.border_width_right = 1
	hover_style.border_width_top = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = accent
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", _text_color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	return btn


func _on_resume() -> void:
	resume()


func _on_restart() -> void:
	get_tree().paused = false
	is_paused = false
	get_tree().reload_current_scene()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_abandon() -> void:
	get_tree().paused = false
	is_paused = false
	GameManager.return_to_board()


func _on_main_menu() -> void:
	get_tree().paused = false
	is_paused = false
	GameManager.game_over()
