extends Node

@onready var mecha: CharacterBody3D = get_parent()
@onready var aim_ray: RayCast3D = $"../AimRay"

var lock_on_target: Node3D = null
var is_aiming: bool = false


func _ready() -> void:
	EventBus.lock_on_target_acquired.connect(_on_lock_on)
	EventBus.lock_on_target_lost.connect(_on_lock_off)


func _on_lock_on(target: Node3D) -> void:
	lock_on_target = target


func _on_lock_off() -> void:
	lock_on_target = null


func _physics_process(delta: float) -> void:
	is_aiming = Input.is_action_pressed("aim")
	if is_aiming:
		mecha.strafe_mode = true
		var aim_dir = _aim_from_camera()
		var target_angle = atan2(aim_dir.x, aim_dir.z)
		mecha.rotation.y = lerp_angle(mecha.rotation.y, target_angle, 8.0 * delta)


func _aim_from_camera() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return -mecha.global_transform.basis.z
	var ray_origin = cam.global_position
	var ray_dir = -cam.global_transform.basis.z
	if lock_on_target:
		ray_dir = (lock_on_target.global_position - ray_origin).normalized()
	return ray_dir


func fire_weapon() -> void:
	var target_pos: Vector3
	if lock_on_target:
		target_pos = lock_on_target.global_position
	else:
		target_pos = _aim_from_camera() * 50.0
	EventBus.weapon_fired.emit(target_pos)
