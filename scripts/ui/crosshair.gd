extends CanvasLayer

@onready var crosshair_dot: TextureRect = $CrosshairDot
@onready var aim_ray: RayCast3D = null

var is_visible: bool = true


func _ready() -> void:
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		aim_ray = mecha.get_node_or_null("AimRay")
	_update_crosshair_position()


func _process(_delta: float) -> void:
	_update_crosshair_position()


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
	query.collision_mask = 5
	var result = space_state.intersect_ray(query)

	if result:
		return (result["position"] - get_parent().global_position).normalized()
	else:
		return ray_dir
