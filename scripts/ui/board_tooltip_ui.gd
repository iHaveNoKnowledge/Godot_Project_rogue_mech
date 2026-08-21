extends CanvasLayer

## Small hover tooltip over the open-grid board: shows cell info (terrain,
## MP cost, tile content) and reveals enemy patrol fleet strength on hover.

var root_control: Control
var panel: PanelContainer
var label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	_create_ui()
	show_tile("", Vector2(-1, -1), {})


func _create_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A plain full-rect Control defaults to MOUSE_FILTER_STOP and, being the
	# topmost layer on the board, would swallow every click (blocking the event
	# popup Continue button and tile clicks). The tooltip is informational only.
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# Keep the panel comfortably on screen.
	var vp := get_viewport().get_visible_rect().size
	var size := panel.get_minimum_size()
	pos.x = clampf(pos.x, 24.0, vp.x - size.x - 24.0)
	pos.y = clampf(pos.y, 24.0, vp.y - size.y - 24.0)
	panel.position = pos