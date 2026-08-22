extends Control

## Compact enemy status: small color-coded rectangles per body part.

var target: Node3D = null
var health_system: Node = null
var panel: PanelContainer = null

var part_blocks: Dictionary = {}

var _color_armor_ok: Color = Color(0.7, 0.82, 0.92, 1.0)
var _color_armor_broken: Color = Color(0.12, 0.14, 0.18, 0.45)

var _color_frame_green: Color = Color(0.22, 0.92, 0.35, 1.0)
var _color_frame_yellow: Color = Color(0.95, 0.72, 0.12, 1.0)
var _color_frame_red: Color = Color(0.95, 0.20, 0.18, 1.0)
var _color_black: Color = Color(0.08, 0.08, 0.10, 0.8)


func _ready() -> void:
	visible = false


func setup_target(enemy: Node3D) -> void:
	target = enemy
	health_system = enemy.get_node_or_null("HealthSystem")
	if health_system:
		_create_ui()
		visible = true


func _create_ui() -> void:
	panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.10, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.3, 0.4, 0.6)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 2)
	root_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(root_vbox)

	# Row 1: HEAD
	var row1 = HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 2)
	root_vbox.add_child(row1)
	_add_block(row1, "head")

	# Row 2: L.ARM | BODY | R.ARM
	var row2 = HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 2)
	root_vbox.add_child(row2)
	_add_block(row2, "arm_left")
	_add_block(row2, "body")
	_add_block(row2, "arm_right")

	# Row 3: L.LEG | R.LEG
	var row3 = HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	row3.add_theme_constant_override("separation", 2)
	root_vbox.add_child(row3)
	_add_block(row3, "leg_left")
	_add_block(row3, "leg_right")


func _add_block(parent: Control, part_name: String) -> void:
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 1)

	var armor_bar = ColorRect.new()
	armor_bar.custom_minimum_size = Vector2(16, 3)
	armor_bar.size = Vector2(16, 3)
	armor_bar.color = _color_armor_ok
	container.add_child(armor_bar)

	var frame_bar = ColorRect.new()
	frame_bar.custom_minimum_size = Vector2(16, 4)
	frame_bar.size = Vector2(16, 4)
	frame_bar.color = _color_frame_green
	container.add_child(frame_bar)

	parent.add_child(container)
	part_blocks[part_name] = {
		"container": container,
		"armor": armor_bar,
		"frame": frame_bar
	}


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	_update_status()


func _update_status() -> void:
	if health_system == null:
		return

	var is_destroyed = health_system.get("is_destroyed") == true or (health_system.has_method("is_part_destroyed") and health_system.is_part_destroyed("body"))
	if is_destroyed:
		for part_name in part_blocks:
			var block_data = part_blocks[part_name]
			block_data["armor"].color = _color_black
			block_data["frame"].color = _color_black
		visible = false
		return

	for part_name in part_blocks:
		if not health_system.parts.has(part_name):
			continue

		var part_data = health_system.parts[part_name]
		var block_data = part_blocks[part_name]
		var armor_bar: ColorRect = block_data["armor"]
		var frame_bar: ColorRect = block_data["frame"]

		if part_data["destroyed"]:
			armor_bar.color = _color_black
			frame_bar.color = _color_black
		else:
			if part_data["armor_broken"]:
				armor_bar.color = _color_armor_broken
			else:
				var armor_ratio = clampf(part_data["armor_hp"] / maxf(part_data["max_armor"], 1.0), 0.0, 1.0)
				armor_bar.color = _color_armor_ok.lerp(_color_armor_broken, 1.0 - armor_ratio)

			var frame_ratio = clampf(part_data["frame_hp"] / maxf(part_data["max_frame"], 1.0), 0.0, 1.0)
			if not part_data["armor_broken"]:
				frame_bar.color = _color_frame_green
			else:
				frame_bar.color = _get_frame_color(frame_ratio)


func _get_frame_color(percent: float) -> Color:
	if percent <= 0.0:
		return _color_black
	elif percent < 0.3:
		return _color_red
	elif percent < 0.7:
		return _color_yellow
	else:
		return _color_frame_green
