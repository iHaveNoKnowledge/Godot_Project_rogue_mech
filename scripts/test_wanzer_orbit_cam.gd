extends Camera3D
## Lightweight orbit preview camera for scenes/test_wanzer.tscn.
## Drag mouse (left/right/middle button) to orbit, wheel to zoom,
## arrow keys orbit as a fallback. No InputMap setup required.

@export var target: Vector3 = Vector3(0, 2.2, 0)
@export var distance: float = 10.0
@export var min_distance: float = 3.0
@export var max_distance: float = 30.0
@export var yaw_deg: float = 0.0
@export var pitch_deg: float = 11.0
@export var drag_speed_deg: float = 0.35
@export var key_speed_deg: float = 90.0
@export var zoom_step: float = 1.0


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var mask: int = int(mm.button_mask)
		var orbit_mask: int = int(MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)
		if (mask & orbit_mask) != 0:
			yaw_deg -= mm.relative.x * drag_speed_deg
			pitch_deg = clampf(pitch_deg - mm.relative.y * drag_speed_deg, -80.0, 80.0)
			_apply()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - zoom_step, min_distance, max_distance)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + zoom_step, min_distance, max_distance)
			_apply()


func _process(delta: float) -> void:
	var rot := Input.get_axis("ui_left", "ui_right")
	var tilt := Input.get_axis("ui_up", "ui_down")
	if rot != 0.0 or tilt != 0.0:
		yaw_deg -= rot * key_speed_deg * delta
		pitch_deg = clampf(pitch_deg - tilt * key_speed_deg * delta, -80.0, 80.0)
		_apply()


func _apply() -> void:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var off := Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y)) * distance
	global_position = target + off
	look_at(target, Vector3.UP)
