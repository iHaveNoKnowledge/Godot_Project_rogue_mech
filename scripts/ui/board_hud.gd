extends CanvasLayer

## Board HUD: a compact overlay on the map screen showing the current day and
## how many movement points remain out of the daily pool. The MP readout
## answers "how many more actions can I take today" at a glance, so the player
## never walks blind into an early end-of-day. The card hides entirely while
## the intermission is open (the intermission owns the objective display and
## its menu must not be overlapped), and the sector objective itself lives only
## in the intermission's top-right panel.

var _panel: PanelContainer
var _day_label: Label
var _mp_label: Label
var _mp_bar: ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 16
	_panel.offset_top = 16
	_panel.offset_right = 300
	_panel.offset_bottom = 120
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.88)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.45, 0.7, 0.5)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 15)
	_day_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	vbox.add_child(_day_label)

	var mp_row := HBoxContainer.new()
	mp_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mp_row)

	_mp_label = Label.new()
	_mp_label.add_theme_font_size_override("font_size", 18)
	_mp_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_mp_label.custom_minimum_size = Vector2(120, 0)
	mp_row.add_child(_mp_label)

	_mp_bar = ProgressBar.new()
	_mp_bar.min_value = 0.0
	_mp_bar.max_value = 1.0
	_mp_bar.value = 1.0
	_mp_bar.show_percentage = false
	_mp_bar.custom_minimum_size = Vector2(150, 10)
	_mp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.6, 1.0, 0.95)
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.15, 0.22, 0.9)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	_mp_bar.add_theme_stylebox_override("fill", fill)
	_mp_bar.add_theme_stylebox_override("background", bg)
	mp_row.add_child(_mp_bar)



func _process(_delta: float) -> void:
	if _day_label == null:
		return
	# The intermission menu has its own full objective panel (top-right) and
	# status bar, so the compact board card hides entirely while it is open —
	# the MP readout must never overlap the intermission menu buttons.
	var intermission := get_parent().get_node_or_null("IntermissionUI") if get_parent() else null
	_panel.visible = intermission == null or not intermission.visible
	_refresh()


func _refresh() -> void:
	var mp := maxi(GlobalData.board_mp, 0)
	var mp_max := maxi(GlobalData.board_mp_max, 1)
	_day_label.text = "DAY %d — %s" % [
		GlobalData.board_day,
		str(GlobalData.board_theme_id).to_upper(),
	]
	_mp_label.text = "MP %d/%d" % [mp, mp_max]
	_mp_bar.max_value = float(mp_max)
	_mp_bar.value = float(mp)
	# Red bar as the pool empties so "out of moves" is unmistakable.
	_mp_bar.modulate = Color(1.0, 0.45, 0.35) if mp <= 0 else Color.WHITE
