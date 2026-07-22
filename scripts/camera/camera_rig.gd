extends Node3D

@export var mouse_sensitivity: float = 0.003
@export var pitch_limit: Vector2 = Vector2(-80, 30)
@export var follow_speed: float = 10.0

@onready var pivot: Node3D = $CameraPivot
@onready var camera_offset: Node3D = $CameraPivot/CameraOffset
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraOffset/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraOffset/SpringArm3D/Camera3D
@onready var lock_on_ray: RayCast3D = $LockOnRay

var yaw: float = 0.0
var pitch: float = 0.0
var is_mouse_captured: bool = true
var target: Node3D = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.camera_mode_changed.connect(_on_camera_mode_changed)
	# Find mecha to follow
	await get_tree().process_frame
	target = get_tree().current_scene.get_node_or_null("Mecha")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_mouse_captured:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clampf(pitch, deg_to_rad(pitch_limit.x), deg_to_rad(pitch_limit.y))

	if event.is_action_pressed("camera_unlock"):
		_toggle_mouse_capture()


func _physics_process(delta: float) -> void:
	pivot.rotation.y = yaw
	pivot.rotation.x = pitch
	# Follow target
	if target and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, follow_speed * delta)
	_check_lock_on()


func _toggle_mouse_capture() -> void:
	is_mouse_captured = !is_mouse_captured
	if is_mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _check_lock_on() -> void:
	if lock_on_ray.enabled and lock_on_ray.is_colliding():
		var collider = lock_on_ray.get_collider()
		if collider and collider.is_in_group("enemy"):
			EventBus.lock_on_target_acquired.emit(collider)
			return
	EventBus.lock_on_target_lost.emit()


func _on_camera_mode_changed(new_mode: String) -> void:
	match new_mode:
		"exploration":
			lock_on_ray.enabled = false
		"combat":
			lock_on_ray.enabled = true
		"eject":
			lock_on_ray.enabled = false
		"board":
			lock_on_ray.enabled = false
