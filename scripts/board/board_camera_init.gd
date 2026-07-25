extends Camera3D

## Board camera: follows player token, supports mouse drag + arrow keys to pan.

@export var camera_height: float = 18.0
@export var follow_speed: float = 8.0
@export var drag_speed: float = 0.3
@export var key_pan_speed: float = 40.0

var player_token: Node3D
var is_dragging: bool = false
var drag_offset: Vector3 = Vector3.ZERO
var follow_enabled: bool = true


func _ready() -> void:
	await get_tree().process_frame
	var board = get_tree().current_scene
	if board:
		player_token = board.get_node_or_null("PlayerToken")
	if player_token:
		global_position = player_token.global_position + _get_offset()
		look_at(player_token.global_position, Vector3.UP)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	# Mouse drag to pan camera
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and Input.is_key_pressed(KEY_CTRL):
			is_dragging = event.pressed
	elif event is InputEventMouseMotion and is_dragging:
		var motion = event.relative
		var right = global_transform.basis.x
		var forward = -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		right.y = 0.0
		right = right.normalized()
		drag_offset -= (right * motion.x + forward * motion.y) * drag_speed

	# Arrow keys / WASD to pan camera while on board
	if GameManager.current_state == GameManager.State.BOARD:
		var pan_dir = Vector3.ZERO
		if Input.is_action_pressed("move_forward"):
			pan_dir.z -= 1.0
		if Input.is_action_pressed("move_back"):
			pan_dir.z += 1.0
		if Input.is_action_pressed("move_left"):
			pan_dir.x -= 1.0
		if Input.is_action_pressed("move_right"):
			pan_dir.x += 1.0

		if pan_dir.length() > 0.01:
			# Move in world XZ plane based on camera orientation
			var forward = -global_transform.basis.z
			var right = global_transform.basis.x
			forward.y = 0.0
			forward = forward.normalized()
			right.y = 0.0
			right = right.normalized()
			drag_offset += (right * pan_dir.x + forward * pan_dir.z) * key_pan_speed * get_process_delta_time()

	# Reset camera to follow player with R key
	if event.is_action_pressed("camera_unlock"):
		drag_offset = Vector3.ZERO


func _process(delta: float) -> void:
	if player_token == null or not is_instance_valid(player_token):
		return

	var desired_pos = player_token.global_position + _get_offset() + drag_offset
	global_position = global_position.lerp(desired_pos, follow_speed * delta)
	var look_target = player_token.global_position + drag_offset * 0.5
	look_at(look_target, Vector3.UP)


func _get_offset() -> Vector3:
	return Vector3(0, camera_height, 10)
