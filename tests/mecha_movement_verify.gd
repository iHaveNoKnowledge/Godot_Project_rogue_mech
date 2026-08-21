extends Node3D

## Verification test for Player Mech Movement (Walking, Running, Strafing, Turning):
## Ensures WASD movement inputs properly translate to velocity and displacement.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("MOVE_OK: %s" % msg)
	else:
		_fails += 1
		print("MOVE_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Player Mech Movement Verification ---")

	# 1. Spawn Floor
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_col.shape = box
	floor_body.add_child(floor_col)
	floor_body.position.y = -0.5
	add_child(floor_body)

	# 2. Spawn Camera looking -Z
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 8)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()

	# 3. Spawn Mecha
	var mecha_script = load("res://scripts/mecha/mecha_controller.gd")
	var mecha: CharacterBody3D = CharacterBody3D.new()
	mecha.set_script(mecha_script)
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 2.4
	col.shape = capsule
	col.position.y = 1.2
	mecha.add_child(col)
	add_child(mecha)
	mecha.global_position = Vector3(0, 0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# Test 1: Forward Movement (W key -> input_dir = Vector2(0, -1))
	var start_pos: Vector3 = mecha.global_position
	Input.action_press("move_forward")
	for i in range(30):
		await get_tree().physics_frame
	Input.action_release("move_forward")

	var forward_disp := start_pos.distance_to(mecha.global_position)
	_check(forward_disp > 1.0, "Player walked forward successfully (moved %.2fm > 1.0m)" % forward_disp)
	_check(mecha.global_position.z < start_pos.z, "Player moved in forward -Z direction (z=%.2f < %.2f)" % [mecha.global_position.z, start_pos.z])

	# Test 2: Right Strafing Movement (D key -> input_dir = Vector2(1, 0))
	var strafe_start: Vector3 = mecha.global_position
	Input.action_press("move_right")
	for i in range(30):
		await get_tree().physics_frame
	Input.action_release("move_right")

	var strafe_disp := strafe_start.distance_to(mecha.global_position)
	_check(strafe_disp > 1.0, "Player walked right successfully (moved %.2fm > 1.0m)" % strafe_disp)
	_check(mecha.global_position.x > strafe_start.x, "Player moved in +X direction (x=%.2f > %.2f)" % [mecha.global_position.x, strafe_start.x])

	mecha.queue_free()
	cam.queue_free()
	floor_body.queue_free()

	print("MECHA_MOVEMENT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
