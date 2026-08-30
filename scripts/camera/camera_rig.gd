extends Node3D

@export var mouse_sensitivity: float = 0.003
@export var pitch_limit: Vector2 = Vector2(-80, 50)
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

# Screen Shake System
var shake_amount: float = 0.0
var shake_decay: float = 4.5

# Camera Presets - matches MechaScaleSystem.COMBAT_CAM (true 4.73m) — newest
const MECHA_SPRING_LENGTH: float = 11.0
const MECHA_OFFSET_X: float = 3.4
const MECHA_OFFSET_Y: float = 5.2
const MECHA_FOV: float = 76.0

const PILOT_SPRING_LENGTH: float = 2.4 # Close tactical over-the-shoulder
const PILOT_OFFSET_X: float = 0.55 # Right beside pilot shoulder
const PILOT_OFFSET_Y: float = 1.45 # Human shoulder/eye height (1.45m)
const PILOT_FOV: float = 75.0

# Combat Mode Camera Stances (High Over-The-Shoulder TPS Framing)
var _target_spring_length: float = MECHA_SPRING_LENGTH
var _target_offset_x: float = MECHA_OFFSET_X
var _target_offset_y: float = MECHA_OFFSET_Y
var _target_fov: float = MECHA_FOV


func _ready() -> void:
	add_to_group("camera_rig")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_mouse_captured = true
	EventBus.camera_mode_changed.connect(_on_camera_mode_changed)
	if EventBus.has_signal("camera_target_changed"):
		EventBus.camera_target_changed.connect(_on_camera_target_changed)
	EventBus.combat_mode_toggled.connect(_on_combat_mode_toggled)
	EventBus.pilot_spawned.connect(_on_pilot_spawned)
	EventBus.combat_ended.connect(_on_combat_ended)

	# Snap initial framing immediately so start of battle never feels crowded or obstructed
	if spring_arm:
		spring_arm.spring_length = _target_spring_length
	if camera_offset:
		camera_offset.position.x = _target_offset_x
		camera_offset.position.y = _target_offset_y
	if camera:
		camera.fov = _target_fov

	await get_tree().process_frame
	target = GameManager.get_player_mecha()
	if target and spring_arm:
		spring_arm.add_excluded_object(target.get_rid())


func _on_camera_target_changed(new_target: Node3D) -> void:
	if new_target and is_instance_valid(new_target):
		target = new_target
		if spring_arm:
			spring_arm.add_excluded_object(target.get_rid())
		if target.is_in_group("pilot"):
			_target_spring_length = PILOT_SPRING_LENGTH
			_target_offset_x = PILOT_OFFSET_X
			_target_offset_y = PILOT_OFFSET_Y
			_target_fov = PILOT_FOV
			pitch_limit = Vector2(-85, 75)
		else:
			_target_spring_length = MECHA_SPRING_LENGTH
			_target_offset_x = MECHA_OFFSET_X
			_target_offset_y = MECHA_OFFSET_Y
			_target_fov = MECHA_FOV
			pitch_limit = Vector2(-80, 50)


func _on_combat_mode_toggled(mode: String) -> void:
	if target and target.is_in_group("pilot"):
		return
	if mode == "close_combat":
		_target_spring_length = 8.0
		_target_offset_x = 3.0
		_target_offset_y = 4.6
		_target_fov = 78.0
		add_shake(0.25)
	else:
		_target_spring_length = MECHA_SPRING_LENGTH
		_target_offset_x = MECHA_OFFSET_X
		_target_offset_y = MECHA_OFFSET_Y
		_target_fov = MECHA_FOV


func _on_pilot_spawned(pilot_node: Node3D) -> void:
	_on_camera_target_changed(pilot_node)


func add_shake(amount: float) -> void:
	shake_amount = clampf(shake_amount + amount, 0.0, 1.0)


func _on_combat_ended(_victory: bool) -> void:
	is_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	pivot.rotation.y = yaw
	pivot.rotation.x = pitch
	if target and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, follow_speed * delta)
	
	# Smoothly interpolate spring arm length and camera framing based on combat mode
	var eff_spring := _target_spring_length
	var eff_offset_x := _target_offset_x
	var eff_offset_y := _target_offset_y
	var eff_fov := _target_fov

	if target and target.is_in_group("pilot"):
		if Input.is_action_pressed("fire_right"):
			# Precision ADS Scope / Shoulder Focus Zoom
			eff_spring = 1.4
			eff_offset_x = 0.42
			eff_offset_y = 1.48
			eff_fov = 52.0

	if spring_arm:
		spring_arm.spring_length = lerpf(spring_arm.spring_length, eff_spring, 10.0 * delta)
	if camera_offset:
		camera_offset.position.x = lerpf(camera_offset.position.x, eff_offset_x, 10.0 * delta)
		camera_offset.position.y = lerpf(camera_offset.position.y, eff_offset_y, 10.0 * delta)
	if camera:
		camera.fov = lerpf(camera.fov, eff_fov, 10.0 * delta)

	_process_screen_shake(delta)
	_check_lock_on()


func _process_screen_shake(delta: float) -> void:
	if shake_amount > 0.0:
		shake_amount = maxf(shake_amount - shake_decay * delta, 0.0)
		var shake_offset = Vector3(
			randf_range(-1.0, 1.0) * shake_amount * 0.45,
			randf_range(-1.0, 1.0) * shake_amount * 0.55,
			randf_range(-1.0, 1.0) * shake_amount * 0.45
		)
		camera.position = shake_offset
	else:
		camera.position = Vector3.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_mouse_captured and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clampf(pitch, deg_to_rad(pitch_limit.x), deg_to_rad(pitch_limit.y))

	if event.is_action_pressed("camera_unlock"):
		_toggle_mouse_capture()


func _toggle_mouse_capture() -> void:
	is_mouse_captured = !is_mouse_captured
	if is_mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _check_lock_on() -> void:
	if not lock_on_ray.enabled:
		EventBus.lock_on_target_lost.emit()
		return

	if GlobalData.board.current_hazard == GlobalData.HAZARD_EMP_ZONE:
		EventBus.lock_on_target_lost.emit()
		return

	var head_destroyed: bool = false
	if target and is_instance_valid(target):
		var health = target.get_node_or_null("HealthSystem")
		if health and health.has_method("is_part_destroyed") and health.is_part_destroyed("head"):
			head_destroyed = true
		elif health and health.get("parts") != null and health.parts.has("head") and health.parts["head"].get("destroyed", false):
			head_destroyed = true

	if head_destroyed:
		EventBus.lock_on_target_lost.emit()
		return

	var enemies = get_tree().get_nodes_in_group("enemy")
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var lock_radius: float = 200.0
	
	var best_target: Node3D = null
	var min_distance: float = lock_radius
	
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.get("health_system") != null:
			var hs = enemy.health_system
			if not hs.get("is_destroyed"):
				var enemy_aim_pos = enemy.global_position + Vector3(0, 1.0, 0)
				if camera.is_position_behind(enemy_aim_pos):
					continue
				var screen_pos = camera.unproject_position(enemy_aim_pos)
				var dist = screen_pos.distance_to(center)
				if dist < min_distance:
					min_distance = dist
					best_target = enemy
				
	if best_target:
		EventBus.lock_on_target_acquired.emit(best_target)
	else:
		EventBus.lock_on_target_lost.emit()


func _on_camera_mode_changed(new_mode: String) -> void:
	match new_mode:
		"exploration":
			lock_on_ray.enabled = false
		"combat":
			target = GameManager.get_player_mecha()
			lock_on_ray.enabled = true
		"eject", "pilot":
			lock_on_ray.enabled = false
		"board":
			lock_on_ray.enabled = false
