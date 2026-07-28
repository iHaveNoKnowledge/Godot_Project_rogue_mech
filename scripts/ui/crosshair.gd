extends CanvasLayer

@onready var crosshair_dot: TextureRect = $CrosshairDot
@onready var aim_ray: RayCast3D = null

var _crosshair_visible: bool = true
var is_head_destroyed: bool = false
var warning_label: Label = null


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		aim_ray = mecha.get_node_or_null("AimRay")
		if aim_ray:
			aim_ray.collision_mask = 10
	_setup_warning_label()
	_update_crosshair_position()


func _setup_warning_label() -> void:
	warning_label = Label.new()
	warning_label.text = "WARNING: SENSORS OFFLINE (MANUAL AIM ONLY)"
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	warning_label.add_theme_font_size_override("font_size", 14)
	warning_label.set_anchors_preset(Control.PRESET_CENTER)
	warning_label.position = Vector2(-180, -40)
	warning_label.visible = false
	add_child(warning_label)


func _process(_delta: float) -> void:
	_check_head_status()
	_update_crosshair_position()
	queue_redraw()


func _check_head_status() -> void:
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		var health = mecha.get_node_or_null("HealthSystem")
		if health:
			if health.has_method("is_part_destroyed"):
				is_head_destroyed = health.is_part_destroyed("head")
			elif health.get("parts") != null and health.parts.has("head"):
				is_head_destroyed = health.parts["head"].get("destroyed", false)

	if warning_label:
		warning_label.visible = is_head_destroyed


func _update_crosshair_position() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	if crosshair_dot:
		crosshair_dot.position = center - crosshair_dot.size / 2.0
	if warning_label:
		warning_label.position = center + Vector2(-180, -40)


func get_aim_point() -> Vector3:
	if aim_ray == null:
		return Vector3.FORWARD

	aim_ray.force_raycast_update()
	if aim_ray.is_colliding():
		return aim_ray.get_collision_point()
	else:
		return aim_ray.global_position + aim_ray.global_transform.basis * aim_ray.target_position


func get_aim_direction() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return -Vector3.FORWARD

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 200.0)
	query.collision_mask = 10
	var result = space_state.intersect_ray(query)

	if result:
		return (result["position"] - get_parent().global_position).normalized()
	else:
		return ray_dir


func _draw() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0

	if is_head_destroyed:
		draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color.RED, 2.0)
		draw_line(center + Vector2(0, -10), center + Vector2(0, 10), Color.RED, 2.0)
	else:
		draw_arc(center, 200.0, 0.0, TAU, 64, Color(0.1, 0.8, 0.1, 0.2), 2.0)
		draw_line(center + Vector2(-210, 0), center + Vector2(-180, 0), Color(0.1, 0.8, 0.1, 0.4), 1.5)
		draw_line(center + Vector2(180, 0), center + Vector2(210, 0), Color(0.1, 0.8, 0.1, 0.4), 1.5)
		draw_line(center + Vector2(0, -210), center + Vector2(0, -180), Color(0.1, 0.8, 0.1, 0.4), 1.5)
		draw_line(center + Vector2(0, 180), center + Vector2(0, 210), Color(0.1, 0.8, 0.1, 0.4), 1.5)
