extends Node

@onready var mecha: CharacterBody3D = get_parent()
@onready var aim_ray: RayCast3D = $"../AimRay"

var lock_on_target: Node3D = null
var is_aiming: bool = false
# World-space point the weapons are currently aimed at (lock-on target or the
# crosshair ray). Refreshed every physics frame; the arm-aiming pose in
# AnimationSystem reads this so the gun arms physically point at it.
var current_aim_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	EventBus.lock_on_target_acquired.connect(_on_lock_on)
	EventBus.lock_on_target_lost.connect(_on_lock_off)


func _on_lock_on(target: Node3D) -> void:
	lock_on_target = target


func _on_lock_off() -> void:
	lock_on_target = null


func _physics_process(delta: float) -> void:
	# The mech is ragdolled in its core-breach death window: no aiming either.
	var mecha_hs = mecha.get_node_or_null("HealthSystem")
	if mecha_hs != null and bool(mecha_hs.get("is_destroyed")):
		is_aiming = false
		current_aim_point = Vector3.ZERO
		return
	is_aiming = Input.is_action_pressed("aim")
	current_aim_point = resolve_aim_point()
	if is_aiming:
		mecha.strafe_mode = true
		var aim_dir = _aim_from_camera()
		var target_angle = atan2(-aim_dir.x, -aim_dir.z)
		mecha.rotation.y = lerp_angle(mecha.rotation.y, target_angle, 8.0 * delta)


func _aim_from_camera() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return -mecha.global_transform.basis.z
	var ray_origin = cam.global_position
	var ray_dir = -cam.global_transform.basis.z
	if lock_on_target and is_instance_valid(lock_on_target):
		ray_dir = (lock_on_target.global_position + Vector3(0, 1.0, 0) - ray_origin).normalized()
	return ray_dir


## Resolves where the guns are pointed this frame: a locked target directly,
## otherwise the crosshair ray against the world (same collision mask the fire
## path uses), falling back 50 m along the camera when nothing is hit.
func resolve_aim_point() -> Vector3:
	if lock_on_target and is_instance_valid(lock_on_target):
		return lock_on_target.global_position + Vector3(0, 1.0, 0)
	if not is_inside_tree():
		return Vector3.ZERO if mecha == null else mecha.global_position
	var vp := get_viewport()
	if vp == null:
		return mecha.global_position + (-mecha.global_transform.basis.z * 50.0) if mecha else Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return mecha.global_position + (-mecha.global_transform.basis.z * 50.0) if mecha else Vector3.ZERO
	var ray_origin := cam.project_ray_origin(vp.get_visible_rect().size / 2.0)
	var ray_dir := cam.project_ray_normal(vp.get_visible_rect().size / 2.0)

	var world_3d := vp.get_world_3d()
	if world_3d == null:
		return ray_origin + ray_dir * 500.0
	var space_state := world_3d.direct_space_state
	if space_state == null:
		return ray_origin + ray_dir * 500.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result := space_state.intersect_ray(query)
	if result:
		return result["position"]
	return ray_origin + ray_dir * 500.0


func fire_weapon() -> void:
	# เล็งกระสุนเข้าจุดเดียวกับที่แขนชี้: lock-on โดยตรง หรือเป้า crosshair
	var target_pos: Vector3 = resolve_aim_point()
	EventBus.weapon_fired.emit(target_pos)
