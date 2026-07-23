extends Control

var target: Node3D = null
var health_system: Node = null
var panel: PanelContainer = null
var bars: Dictionary = {}

var _color_green: Color = Color(0.2, 0.8, 0.2, 1)
var _color_yellow: Color = Color(0.9, 0.9, 0.2, 1)
var _color_red: Color = Color(0.9, 0.2, 0.2, 1)
var _color_black: Color = Color(0.1, 0.1, 0.1, 1)
var _bg_color: Color = Color(0.15, 0.15, 0.15, 0.9)


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup_target(enemy: Node3D) -> void:
	target = enemy
	health_system = enemy.get_node_or_null("HealthSystem")
	_create_ui()
	visible = true


func _create_ui() -> void:
	panel = PanelContainer.new()
	panel.size = Vector2(180, 110)

	var style = StyleBoxFlat.new()
	style.bg_color = _bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	_add_name_label(vbox)
	_add_bar_row(vbox, "HEAD", "head")
	_add_bar_row(vbox, "BODY", "body")
	_add_arms_row(vbox)
	_add_bar_row(vbox, "LEGS", "leg_left")


func _add_name_label(parent: Control) -> void:
	var label = Label.new()
	label.text = "ENEMY"
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _add_bar_row(parent: Control, label_text: String, part_name: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size.x = 45
	hbox.add_child(label)

	_create_bar(hbox, part_name)


func _add_arms_row(parent: Control) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var l_label = Label.new()
	l_label.text = "L.ARM"
	l_label.add_theme_font_size_override("font_size", 10)
	l_label.custom_minimum_size.x = 40
	hbox.add_child(l_label)
	_create_bar(hbox, "arm_left")

	var r_label = Label.new()
	r_label.text = "R.ARM"
	r_label.add_theme_font_size_override("font_size", 10)
	r_label.custom_minimum_size.x = 40
	hbox.add_child(r_label)
	_create_bar(hbox, "arm_right")


func _create_bar(parent: Control, part_name: String) -> void:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(60, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.3, 0.3, 0.3, 1)
	bar.add_theme_stylebox_override("background", bg_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = _color_green
	bar.add_theme_stylebox_override("fill", fill_style)

	parent.add_child(bar)
	bars[part_name] = {"bar": bar, "style": fill_style}


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	_update_position()
	_update_status()


func _update_position() -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var world_pos = target.global_position + Vector3(0, 4.0, 0)
	var screen_pos = cam.unproject_position(world_pos)

	var viewport_size = get_viewport().get_visible_rect().size
	screen_pos.x = clampf(screen_pos.x, 100, viewport_size.x - 100)
	screen_pos.y = clampf(screen_pos.y, 70, viewport_size.y - 70)

	panel.global_position = screen_pos - panel.size / 2.0


func _update_status() -> void:
	if health_system == null:
		return

	for part in health_system.parts:
		if not bars.has(part):
			continue

		var part_data = health_system.parts[part]
		var hp_percent = part_data["armor_hp"] / part_data["max_armor"] * 100.0
		var entry = bars[part]

		entry["bar"].value = hp_percent
		entry["style"].bg_color = _get_hp_color(hp_percent / 100.0)


func _get_hp_color(percent: float) -> Color:
	if percent <= 0.0:
		return _color_black
	elif percent < 0.3:
		return _color_red
	elif percent < 0.7:
		return _color_yellow
	else:
		return _color_green
