extends CanvasLayer

## Small hover tooltip over the open-grid board: shows cell info (terrain,
## MP cost, tile content) and reveals enemy patrol fleet strength on hover.

var root_control: Control
var panel: PanelContainer
var label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	show_tile("", Vector2(-1, -1), {})


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	panel = PanelContainer.new()
	root_control.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_color = Color(0.4, 0.5, 0.7, 0.8)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	label = Label.new()
	label.add_theme_font_size_override("font_size", 13)
	panel.add_child(label)
	panel.visible = false


func show_tile(text: String, screen_pos: Vector2, _extra: Dictionary) -> void:
	if text == "":
		panel.visible = false
		return
	label.text = text
	panel.visible = true
	var offset := Vector2(18, 18)
	var pos := screen_pos + offset
	# Keep the panel on screen.
	var vp := get_viewport().get_visible_rect().size
	var size := panel.get_minimum_size()
	pos.x = clampf(pos.x, 4, vp.x - size.x - 4)
	pos.y = clampf(pos.y, 4, vp.y - size.y - 4)
	panel.position = pos