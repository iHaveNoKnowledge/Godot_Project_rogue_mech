extends CanvasLayer

@onready var crosshair_dot: TextureRect = $CrosshairDot
@onready var aim_ray: RayCast3D = null

var _crosshair_visible: bool = true
var lock_target: Node3D = null
var sensor_warning_label: Label = null
var lock_circle_radius: float = 150.0
var _lock_reticle: Control = null


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		aim_ray = mecha.get_node_or_null("AimRay")
		if aim_ray:
			aim_ray.collision_mask = 10
	_setup_warning_ui()
	_update_crosshair_position()


func _setup_warning_ui() -> void:
	sensor_warning_label = Label.new()
	sensor_warning_label.text = "⚠️ SENSOR OFF-LINE"
	sensor_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sensor_warning_label.add_theme_font_size_override("font_size", 16)
	sensor_warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	sensor_warning_label.set_anchors_preset(Control.PRESET_CENTER)
	sensor_warning_label.position = Vector2(-100, -60)
	sensor_warning_label.visible = false
	add_child(sensor_warning_label)


func _process(_delta: float) -> void:
	_update_crosshair_position()
	_update_lock_on()


func is_head_broken() -> bool:
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha and mecha.get("health_system") != null:
		var hs = mecha.health_system
		if hs.parts.has("head") and hs.parts["head"].get("destroyed", false):
			return true
	if GlobalData.part_damage.get("head", 0.0) >= 1.0 or GlobalData.part_damage.get("head_frame", 0.0) >= 1.0:
		return true
	return false


func _update_lock_on() -> void:
	if is_head_broken():
		if sensor_warning_label:
			sensor_warning_label.visible = true
		if lock_target != null:
			lock_target = null
			EventBus.lock_on_target_lost.emit()
		return

	if sensor_warning_label:
		sensor_warning_label.visible = false

	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var enemies = get_tree().get_nodes_in_group("enemy")

	var best_target: Node3D = null
	var best_dist: float = lock_circle_radius

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.get("health_system") != null and enemy.health_system.is_destroyed:
			continue

		var enemy_pos = enemy.global_position + Vector3(0, 1.5, 0)
		if cam.is_position_behind(enemy_pos):
			continue

		var screen_pos = cam.unproject_position(enemy_pos)
		var dist = screen_pos.distance_to(center)
		if dist <= lock_circle_radius and dist < best_dist:
			best_dist = dist
			best_target = enemy

	if best_target != lock_target:
		lock_target = best_target
		if lock_target:
			EventBus.lock_on_target_acquired.emit(lock_target)
		else:
			EventBus.lock_on_target_lost.emit()


func _update_crosshair_position() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	crosshair_dot.position = center - crosshair_dot.size / 2.0


func get_aim_point() -> Vector3:
	if lock_target and is_instance_valid(lock_target) and not is_head_broken():
		return lock_target.global_position + Vector3(0, 1.5, 0)

	if aim_ray == null:
		return Vector3.FORWARD

	aim_ray.force_raycast_update()
	if aim_ray.is_colliding():
		return aim_ray.get_collision_point()
	else:
		return aim_ray.global_position + aim_ray.global_transform.basis * aim_ray.target_position


func get_aim_direction() -> Vector3:
	if lock_target and is_instance_valid(lock_target) and not is_head_broken():
		var mecha = get_tree().current_scene.get_node_or_null("Mecha")
		var origin = mecha.global_position if mecha else Vector3.ZERO
		return (lock_target.global_position + Vector3(0, 1.5, 0) - origin).normalized()

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

