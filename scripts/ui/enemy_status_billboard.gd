extends Control

## Compact enemy status: small color-coded rectangles per body part.
## Green = OK, Yellow = damaged, Red = critical, Black = destroyed.

var target: Node3D = null
var health_system: Node = null
var panel: PanelContainer = null
var part_blocks: Dictionary = {}

## Optional pilot name shown above the part blocks. Allies pass their pilot's
## name so the combat HUD identifies friendlies; enemies leave it empty and the
## label is skipped entirely (their name plate stays the 3D Label3D only).
var name_label: Label = null

var _color_green: Color = Color(0.2, 0.8, 0.2, 1)
var _color_yellow: Color = Color(0.9, 0.9, 0.2, 1)
var _color_red: Color = Color(0.9, 0.2, 0.2, 1)
var _color_black: Color = Color(0.15, 0.15, 0.15, 1)

# Layout: [HEAD]
#          [L ARM] [BODY] [R ARM]
#          [L LEG]        [R LEG]
var _layout_order: Array = ["head", "arm_left", "body", "arm_right", "leg_left", "leg_right"]
var _layout_labels: Dictionary = {
	"head": "H", "body": "B", "arm_left": "L", "arm_right": "R",
	"leg_left": "LL", "leg_right": "RL"
}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup_target(enemy: Node3D, pilot_name: String = "") -> void:
	target = enemy
	health_system = enemy.get_node_or_null("HealthSystem")
	_create_ui()
	if pilot_name.strip_edges() != "":
		_add_name_label(pilot_name)
	visible = true


# Name plate above the part blocks, tinted friendly blue to match the ally
# theme (enemies never set it, so they keep the compact blocks-only billboard).
func _add_name_label(pilot_name: String) -> void:
	name_label = Label.new()
	name_label.text = pilot_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(name_label)


func _create_ui() -> void:
	panel = PanelContainer.new()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 3)
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
	var block = ColorRect.new()
	block.custom_minimum_size = Vector2(18, 14)
	block.size = Vector2(18, 14)
	block.color = _color_green
	parent.add_child(block)
	part_blocks[part_name] = block


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

	var world_pos = target.global_position + Vector3(0, 4.5, 0)
	if cam.is_position_behind(world_pos):
		visible = false
		return

	var dist = cam.global_position.distance_to(world_pos)
	if dist > 85.0:
		visible = false
		return

	visible = true
	var screen_pos = cam.unproject_position(world_pos)
	var panel_size = panel.size if panel else Vector2(80, 50)
	if name_label:
		panel_size.y += name_label.size.y
	panel.global_position = screen_pos - panel_size / 2.0
	if name_label:
		name_label.global_position = Vector2(panel.global_position.x, screen_pos.y - panel_size.y / 2.0)


func _update_status() -> void:
	if health_system == null:
		return

	for part_name in part_blocks:
		if not health_system.parts.has(part_name):
			continue

		var part_data = health_system.parts[part_name]
		var block: ColorRect = part_blocks[part_name]

		if part_data["destroyed"]:
			block.color = _color_black
		else:
			var hp_percent: float
			if not part_data["armor_broken"]:
				hp_percent = part_data["armor_hp"] / maxf(part_data["max_armor"], 1.0)
			else:
				hp_percent = part_data["frame_hp"] / maxf(part_data["max_frame"], 1.0)
			block.color = _get_hp_color(hp_percent)


func _get_hp_color(percent: float) -> Color:
	if percent <= 0.0:
		return _color_black
	elif percent < 0.3:
		return _color_red
	elif percent < 0.7:
		return _color_yellow
	else:
		return _color_green
