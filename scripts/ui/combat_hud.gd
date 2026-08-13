extends CanvasLayer

var panel: PanelContainer
var status_label: Label


func _ready() -> void:
	layer = 5
	_create_ui()


func _create_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sits just below the top edge (not glued to it) so it reads as a status
	# banner instead of part of the screen frame.
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = 64
	panel.offset_bottom = 104
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.6, 0.9, 0.6)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	status_label = Label.new()
	status_label.text = "COMBAT INITIALIZING..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	panel.add_child(status_label)


func _process(_delta: float) -> void:
	var spawn_mgr = get_tree().current_scene.get_node_or_null("SpawnManager") if get_tree().current_scene else null
	if spawn_mgr:
		var cur_wave = spawn_mgr.get_current_wave()
		var tot_waves = spawn_mgr.get_total_waves()
		var enemies_left = spawn_mgr._get_alive_count()

		if GameManager.is_boss_combat and cur_wave == tot_waves:
			status_label.text = "⚠️ BOSS ENCOUNTER | ENEMIES: %d" % enemies_left
			status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			status_label.text = "WAVE %d / %d  |  ENEMIES LEFT: %d" % [cur_wave, tot_waves, enemies_left]
			status_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
