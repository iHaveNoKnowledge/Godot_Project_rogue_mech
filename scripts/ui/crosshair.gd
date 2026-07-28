extends CanvasLayer

@onready var crosshair_dot: TextureRect = $CrosshairDot
@onready var aim_ray: RayCast3D = null

var _crosshair_visible: bool = true
var is_head_destroyed: bool = false


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		aim_ray = mecha.get_node_or_null("AimRay")
		if aim_ray:
			aim_ray.collision_mask = 10
	_update_crosshair_position()


func _process(_delta: float) -> void:
	_check_head_status()
	_update_crosshair_position()
	queue_redraw() # สั่งให้ Draw เส้นกราฟิกเป้าเล็งใหม่ทุกเฟรม


# ตรวจจับสภาพส่วนหัวแบบเรียลไทม์เพื่อรีเซ็ตหน้าจอ UI
func _check_head_status() -> void:
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		var health = mecha.get_node_or_null("HealthSystem")
		if health:
			if health.has_method("is_part_destroyed"):
				is_head_destroyed = health.is_part_destroyed("head")
			elif health.get("parts") != null and health.parts.has("head"):
				is_head_destroyed = health.parts["head"].get("destroyed", false)


func _update_crosshair_position() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	crosshair_dot.position = center - crosshair_dot.size / 2.0


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


# วาดเส้นกราฟิกช่วยเล็งลงบนหน้าจอ (2D Canvas Drawing)
func _draw() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	
	if is_head_destroyed:
		# หน้าจอเสียหาย: วาดตัวอักษรเตือนภัยสีแดง
		draw_string(ThemeDB.fallback_font, center + Vector2(-100, -30), "⚠️ SENSORS OFFLINE (MANUAL AIM ONLY)", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 0.2, 0.2, 1))
		# เปลี่ยนเป้าเล็งหลักให้เป็นกากบาทขนาดเล็กสีแดง บ่งบอกการเล็งกระบอกปืนเปล่าๆ
		draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color.RED, 2.0)
		draw_line(center + Vector2(0, -10), center + Vector2(0, 10), Color.RED, 2.0)
	else:
		# หัวปกติ: วาดวงสแกน Area ล็อกเป้าอัจฉริยะ สีเขียวเซนเซอร์บางตา (รัศมี 200px)
		draw_arc(center, 200.0, 0.0, TAU, 64, Color(0.1, 0.8, 0.1, 0.2), 2.0)
		# วาดเส้นสี่ทิศชี้เข้าจุดศูนย์กลางเพื่อความเท่ไซไฟ
		draw_line(center + Vector2(-210, 0), center + Vector2(-180, 0), Color(0.1, 0.8, 0.1, 0.4), 1.5)
		draw_line(center + Vector2(180, 0), center + Vector2(210, 0), Color(0.1, 0.8, 0.1, 0.4), 1.5)
		draw_line(center + Vector2(0, -210), center + Vector2(0, -180), Color(0.1, 0.8, 0.1, 0.4), 1.5)
		draw_line(center + Vector2(0, 180), center + Vector2(0, 210), Color(0.1, 0.8, 0.1, 0.4), 1.5)
