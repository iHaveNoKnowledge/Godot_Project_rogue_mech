extends Camera3D

## Board camera: follows the player token and pans with WASD (W north, S south,
## A west, D east — world directions). Q / E rotate the view around the player
## (Q counter-clockwise, E clockwise). Middle-drag pans, wheel zooms, R
## re-centers on the player. The player token itself moves by clicking tiles.

@export var camera_height: float = 30.0
@export var camera_height_min: float = 12.0
@export var camera_height_max: float = 55.0
@export var follow_speed: float = 8.0
@export var drag_speed: float = 0.3
@export var key_pan_speed: float = 40.0
@export var rotate_speed: float = 1.2

var player_token: Node3D
var is_dragging: bool = false
var drag_offset: Vector3 = Vector3.ZERO
var follow_enabled: bool = true
var yaw: float = 0.0


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
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_height = maxf(camera_height_min, camera_height - 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_height = minf(camera_height_max, camera_height + 3.0)
	elif event is InputEventMouseMotion and is_dragging:
		var motion = event.relative
		var right = global_transform.basis.x
		var forward = -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		right.y = 0.0
		right = right.normalized()
		drag_offset -= (right * motion.x + forward * motion.y) * drag_speed

	# Reset camera to follow player with R key
	if event.is_action_pressed("camera_unlock"):
		drag_offset = Vector3.ZERO


func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.State.BOARD:
		# WASD pans the camera in world space (W = north, S = south, A = west,
		# D = east), independent of the current view rotation.
		var pan := Vector3.ZERO
		if Input.is_key_pressed(KEY_W):
			pan.z -= 1.0
		if Input.is_key_pressed(KEY_S):
			pan.z += 1.0
		if Input.is_key_pressed(KEY_A):
			pan.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			pan.x += 1.0
		drag_offset += pan * key_pan_speed * delta

		# Q / E rotate the orbit around the player (Q counter-clockwise).
		if Input.is_key_pressed(KEY_E):
			rotate_yaw(rotate_speed * delta)
		if Input.is_key_pressed(KEY_Q):
			rotate_yaw(-rotate_speed * delta)

	if player_token == null or not is_instance_valid(player_token):
		return

	var desired_pos = player_token.global_position + _get_offset() + drag_offset
	global_position = global_position.lerp(desired_pos, follow_speed * delta)
	var look_target = player_token.global_position + drag_offset * 0.5
	look_at(look_target, Vector3.UP)


# Rotates the camera's orbit around the player. Positive = clockwise when seen
# from above (the board's top-down view), negative = counter-clockwise.
func rotate_yaw(amount: float) -> void:
	yaw += amount


# Slight isometric tilt: the camera sits diagonal to the player (offset in both
# X and Z) instead of straight above, so the board reads with depth — tiles and
# props get a 3/4 view instead of a flat top-down look. The orbit yaw (Q/E)
# rotates this offset around the player.
func _get_offset() -> Vector3:
	var base := Vector3(camera_height * 0.45, camera_height, camera_height * 0.6)
	return base.rotated(Vector3.UP, yaw)
