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


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.camera_mode_changed.connect(_on_camera_mode_changed)
	await get_tree().process_frame
	target = get_tree().current_scene.get_node_or_null("Mecha")


func _physics_process(delta: float) -> void:
	pivot.rotation.y = yaw
	pivot.rotation.x = pitch
	if target and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, follow_speed * delta)
	_check_lock_on()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_mouse_captured:
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


# ระบบล็อกเป้า Area แบบใหม่เช็คสภาพหัวแตก
func _check_lock_on() -> void:
	if not lock_on_ray.enabled:
		EventBus.lock_on_target_lost.emit()
		return

	# 1. เช็คสภาพพาร์ทหัวผู้เล่น
	var head_destroyed: bool = false
	if target and is_instance_valid(target):
		var health = target.get_node_or_null("HealthSystem")
		if health and health.has_method("is_part_destroyed") and health.is_part_destroyed("head"):
			head_destroyed = true
		elif health and health.get("parts") != null and health.parts.has("head") and health.parts["head"].get("destroyed", false):
			head_destroyed = true

	# 2. หัวแตก (Sensors Off-Line) เล็ง Manual เท่านั้น
	if head_destroyed:
		EventBus.lock_on_target_lost.emit()
		return

	# 3. สแกนหาเป้าหมายศัตรูในวงเป้ากึ่งกลางหน้าจอ (Area รัศมี 200 พิกเซล)
	var enemies = get_tree().get_nodes_in_group("enemy")
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var lock_radius: float = 200.0 # รัศมีกรอบเซนเซอร์สแกนล็อกเป้า
	
	var best_target: Node3D = null
	var min_distance: float = lock_radius
	
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.get("health_system") != null:
			var hs = enemy.health_system
			if not hs.get("is_destroyed"):
				# ใช้จุดกึ่งกลางลำตัวศัตรูเล็งยิง (บวกความสูงขึ้น 1 เมตรจากพื้นเท้า)
				var enemy_aim_pos = enemy.global_position + Vector3(0, 1.0, 0)
				
				# ข้ามหากเป้าหมายอยู่นอกระยะวิสัยทัศน์ด้านหลังกล้อง
				if camera.is_position_behind(enemy_aim_pos):
					continue
					
				var screen_pos = camera.unproject_position(enemy_aim_pos)
				var dist = screen_pos.distance_to(center)
				
				# หาศัตรูในวงที่อยู่ใกล้จุดศูนกลางจอมากที่สุด (Auto-Focus)
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
			lock_on_ray.enabled = true
		"eject":
			lock_on_ray.enabled = false
		"board":
			lock_on_ray.enabled = false
