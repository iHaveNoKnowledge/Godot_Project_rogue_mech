extends CanvasLayer

## Board HUD: a persistent overlay on the map screen.
##   - Top-center: compact day + MP card, always visible (even while the
##     intermission menu is open) so the player never walks blind into an
##     early end-of-day.
##   - Right column of three stacked slots: the sector objective on top, a
##     ceasefire countdown under it (visible while a political ceasefire is
##     active), and an empty reserved slot below for future status widgets.

var _panel: PanelContainer
var _day_label: Label
var _mp_label: Label
var _mp_bar: ProgressBar

var _objective_panel: PanelContainer
var _objective_label: Label
var _ceasefire_panel: PanelContainer
var _ceasefire_label: Label
var _reserved_panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh()


func _build_ui() -> void:
	# --- Top-center MP card ---
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -170
	_panel.offset_right = 170
	_panel.offset_top = 12
	_panel.offset_bottom = 88
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
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", 15)
	_day_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	vbox.add_child(_day_label)

	var mp_row := HBoxContainer.new()
	mp_row.add_theme_constant_override("separation", 10)
	mp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(mp_row)

	_mp_label = Label.new()
	_mp_label.add_theme_font_size_override("font_size", 18)
	_mp_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_mp_label.custom_minimum_size = Vector2(110, 0)
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

	# --- Right column: objective / ceasefire countdown / reserved ---
	_objective_panel = _make_side_panel(20, 130)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_panel.add_child(_objective_label)

	_ceasefire_panel = _make_side_panel(140, 210, true)
	_ceasefire_label = Label.new()
	_ceasefire_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ceasefire_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_ceasefire_panel.add_child(_ceasefire_label)

	_reserved_panel = _make_side_panel(220, 290, true)


# A stacked slot in the right column. `dim` renders the slot as an empty
# reserved cell (subtle outline) instead of a filled card.
func _make_side_panel(offset_top: int, offset_bottom: int, dim: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -270
	panel.offset_right = -20
	panel.offset_top = offset_top
	panel.offset_bottom = offset_bottom
	add_child(panel)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.12, 0.85) if not dim else Color(0.05, 0.07, 0.12, 0.5)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.45, 0.7, 0.35)
	panel.add_theme_stylebox_override("panel", s)
	return panel


func _process(_delta: float) -> void:
	if _mp_label == null:
		return
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
	_update_objective_panel()
	_update_ceasefire_panel()


func _update_objective_panel() -> void:
	if _objective_label == null:
		return
	var obj := BoardSystem.get_objective()
	var progress := GlobalData.board_objective_progress
	var required := GlobalData.board_objective_required
	var pct := int(float(progress) / maxi(required, 1) * 100.0)
	_objective_label.text = "OBJECTIVE\n%s\n\nProgress: %d / %d  (%d%%)\n%s" % [
		obj.get("name", "Objective"),
		progress, required, pct,
		BoardSystem.objective_desc(),
	]


func _update_ceasefire_panel() -> void:
	if _ceasefire_label == null:
		return
	var turns := maxi(GlobalData.ceasefire_turns, 0)
	if turns > 0:
		_ceasefire_label.text = "CEASEFIRE\n%d TURN%s LEFT — no combat on the front." % [
			turns, "S" if turns != 1 else ""
		]
	else:
		# Reserved slot: keep the panel as a dim empty cell.
		_ceasefire_label.text = ""
