extends CanvasLayer

var root_control: Control
var panel: PanelContainer
var is_visible: bool = true

var _bg_color: Color = Color(0.08, 0.08, 0.12, 0.8)
var _key_color: Color = Color(0.3, 0.6, 1.0, 1)
var _label_color: Color = Color(0.75, 0.75, 0.75, 1)
var _title_color: Color = Color(1.0, 0.9, 0.3, 1)

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
	layer = 10
	_create_ui()
	_update_display()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_unlock"):
		_toggle_visibility()


func _toggle_visibility() -> void:
	is_visible = not is_visible
	if panel:
		panel.visible = is_visible


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.offset_left = 15
	panel.offset_top = 15
	panel.offset_right = 230
	panel.offset_bottom = 420

	var style = StyleBoxFlat.new()
	style.bg_color = _bg_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", _title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	for bind in KEYBINDS:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var key_label = Label.new()
		key_label.text = bind["key"]
		key_label.add_theme_font_size_override("font_size", 11)
		key_label.add_theme_color_override("font_color", _key_color)
		key_label.custom_minimum_size = Vector2(55, 0)
		row.add_child(key_label)

		var action_label = Label.new()
		action_label.text = bind["action"]
		action_label.add_theme_font_size_override("font_size", 11)
		action_label.add_theme_color_override("font_color", _label_color)
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action_label)


func _update_display() -> void:
	pass
