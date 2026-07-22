extends CharacterBody3D

@export var chassis: ChassisData

var total_weight: float = 0.0
var current_speed: float = 0.0
var turn_rate: float = 0.0
var strafe_mode: bool = false
var input_dir: Vector2 = Vector2.ZERO

const GRAVITY := 20.0


func _ready() -> void:
	add_to_group("mecha")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	_recalculate_weight()
	EventBus.weight_changed.connect(_on_weight_changed)


func _physics_process(delta: float) -> void:
	_handle_movement_input()
	_apply_movement(delta)


func _handle_movement_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	strafe_mode = Input.is_action_pressed("strafe")


func _apply_movement(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_basis = cam.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x
	forward.y = 0.0
	forward = forward.normalized()
	right.y = 0.0
	right = right.normalized()

	var desired_velocity := Vector3.ZERO
	if strafe_mode:
		desired_velocity = (forward * -input_dir.y + right * input_dir.x) * current_speed
	else:
		desired_velocity = (forward * -input_dir.y + right * input_dir.x) * current_speed
		if desired_velocity.length() > 0.1:
			var target_angle = atan2(desired_velocity.x, desired_velocity.z)
			rotation.y = lerp_angle(rotation.y, target_angle, turn_rate * delta)

	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z
	velocity.y -= GRAVITY * delta
	move_and_slide()


func _recalculate_weight() -> void:
	total_weight = 0.0
	for slot in GlobalData.equipped_parts:
		var part: ArmorPart = GlobalData.equipped_parts[slot]
		if part and not GlobalData.part_damage.get(slot, 0.0) >= part.break_threshold:
			total_weight += part.weight

	if chassis:
		turn_rate = chassis.base_turn_rate * (chassis.weight_capacity / maxf(total_weight, 1.0))
		current_speed = chassis.base_speed * (1.0 - clampf(total_weight / chassis.weight_capacity, 0.0, 0.6))
	else:
		turn_rate = 2.0
		current_speed = 8.0

	EventBus.weight_changed.emit(total_weight)


func _on_weight_changed(_w: float) -> void:
	_recalculate_weight()
