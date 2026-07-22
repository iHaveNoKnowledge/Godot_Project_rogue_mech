extends Node3D

var target: Node3D = null
var health_system: Node = null
var canvas: CanvasLayer = null
var panel: PanelContainer = null
var bars: Dictionary = {}
var name_label: Label = null

var _color_green: Color = Color(0.2, 0.8, 0.2, 1)
var _color_yellow: Color = Color(0.9, 0.9, 0.2, 1)
var _color_red: Color = Color(0.9, 0.2, 0.2, 1)
var _color_black: Color = Color(0.1, 0.1, 0.1, 1)
var _bg_color: Color = Color(0.15, 0.15, 0.15, 0.85)


func _ready() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	panel = PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.offset_left = -80
	panel.offset_right = 80
	panel.offset_top = -50
	panel.offset_bottom = 50

	var style = StyleBoxFlat.new()
	style.bg_color = _bg_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	_add_name_label(vbox)
	_add_bar_row(vbox, "HEAD", "head")
	_add_bar_row(vbox, "BODY", "body")
	_add_arms_row(vbox)
	_add_bar_row(vbox, "LEGS", "leg_left")

	visible = false


func _add_name_label(parent: Control) -> void:
	name_label = Label.new()
	name_label.text = "ENEMY"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(name_label)


func _add_bar_row(parent: Control, label_text: String, part_name: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.custom_minimum_size.x = 40
	hbox.add_child(label)

	_create_bar(hbox, part_name)


func _add_arms_row(parent: Control) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	var l_label = Label.new()
	l_label.text = "L.ARM"
	l_label.add_theme_font_size_override("font_size", 10)
	l_label.custom_minimum_size.x = 35
	hbox.add_child(l_label)
	_create_bar(hbox, "arm_left")

	var r_label = Label.new()
	r_label.text = "R.ARM"
	r_label.add_theme_font_size_override("font_size", 10)
	r_label.custom_minimum_size.x = 35
	hbox.add_child(r_label)
	_create_bar(hbox, "arm_right")


func _create_bar(parent: Control, part_name: String) -> void:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(50, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.25, 0.25, 0.25, 1)
	bar.add_theme_stylebox_override("background", bg_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = _color_green
	bar.add_theme_stylebox_override("fill", fill_style)

	parent.add_child(bar)
	bars[part_name] = {"bar": bar, "style": fill_style}


func setup_target(enemy: Node3D) -> void:
	target = enemy
	health_system = enemy.get_node_or_null("HealthSystem")
	visible = true


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	_update_status()


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
