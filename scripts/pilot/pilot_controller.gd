extends CharacterBody3D

@export var move_speed: float = 5.0
@export var jump_force: float = 4.5

var gravity := 20.0


func _ready() -> void:
	add_to_group("pilot")


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.State.EJECT:
		return
	var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var forward = -cam.global_transform.basis.z
	var right = cam.global_transform.basis.x
	forward.y = 0.0
	forward = forward.normalized()
	right.y = 0.0
	right = right.normalized()
	var velocity_dir = (forward * -input.y + right * input.x)
	velocity.x = velocity_dir.x * move_speed
	velocity.z = velocity_dir.z * move_speed
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force
	velocity.y -= gravity * delta
	move_and_slide()
