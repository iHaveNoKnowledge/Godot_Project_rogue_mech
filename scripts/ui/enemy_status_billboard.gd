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

var _color_armor_ok: Color = Color(0.7, 0.82, 0.92, 1.0)
var _color_armor_broken: Color = Color(0.12, 0.14, 0.18, 0.45)

var _color_frame_green: Color = Color(0.22, 0.92, 0.35, 1.0)
var _color_frame_yellow: Color = Color(0.95, 0.72, 0.12, 1.0)
var _color_frame_red: Color = Color(0.95, 0.20, 0.18, 1.0)
var _color_black: Color = Color(0.08, 0.08, 0.10, 0.8)

# Set by the owning enemy when it is concealed inside cover — hides the whole
# billboard (part blocks + name plate) so no UI betrays the hidden unit.
var concealed: bool = false
var _is_fading: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_concealed(on: bool) -> void:
	concealed = on
	if on:
		visible = false


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
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(name_label)


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

	# Top: Armor slim strip (Height 3px)
	var armor_bar = ColorRect.new()
	armor_bar.custom_minimum_size = Vector2(16, 3)
	armor_bar.size = Vector2(16, 3)
	armor_bar.color = _color_armor_ok
	container.add_child(armor_bar)

	# Bottom: Frame slim strip (Height 4px)
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


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	_update_position()
	_update_status()

	if _is_fading:
		modulate.a = maxf(0.0, modulate.a - delta * 2.0)
		if modulate.a <= 0.01:
			visible = false


func _update_position() -> void:
	if concealed:
		visible = false
		return

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

	if not _is_fading:
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

	var is_destroyed = health_system.get("is_destroyed") == true or (health_system.has_method("is_part_destroyed") and health_system.is_part_destroyed("body"))
	if is_destroyed:
		_is_fading = true
		for part_name in part_blocks:
			var block_data = part_blocks[part_name]
			block_data["armor"].color = _color_black
			block_data["frame"].color = _color_black
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
			# 1. Armor Bar status
			if part_data["armor_broken"]:
				armor_bar.color = _color_armor_broken
			else:
				var armor_ratio = clampf(part_data["armor_hp"] / maxf(part_data["max_armor"], 1.0), 0.0, 1.0)
				armor_bar.color = _color_armor_ok.lerp(_color_armor_broken, 1.0 - armor_ratio)

			# 2. Frame Bar status
			var frame_ratio = clampf(part_data["frame_hp"] / maxf(part_data["max_frame"], 1.0), 0.0, 1.0)
			if not part_data["armor_broken"]:
				frame_bar.color = _color_frame_green # Full integrity shielded
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
