extends Node3D

## Verification test for Player Mech Facing Direction on Attack:
## Validates that when attacking (shooting / meleeing), the mech faces forward towards
## the crosshair / camera forward direction even when moving backward (S / backpedaling).

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("ATTACK_FACING_OK: %s" % msg)
	else:
		_fails += 1
		print("ATTACK_FACING_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Attack Facing Direction Verification ---")

	var mecha_script = load("res://scripts/mecha/mecha_controller.gd")
	var mecha: CharacterBody3D = CharacterBody3D.new()
	mecha.set_script(mecha_script)
	mecha.current_speed = 10.0
	mecha.turn_rate = 10.0
	add_child(mecha)

	# Add Camera3D looking forward (-Z)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3, 5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	cam.make_current()

	await get_tree().process_frame

	# 1. Test Moving Backward without attacking: mech turns towards backward direction
	mecha.input_dir = Vector2(0, 1) # S key (move_back)
	mecha._apply_movement(0.5)
	var angle_back = mecha.rotation.y
	_check(absf(angle_back) > 0.5, "Moving backwards without attack turns mech towards movement direction (angle=%.2f)" % angle_back)

	# 2. Test Moving Backward WHILE attacking (e.g. holding fire / Input action):
	# Camera forward is -Z (angle 0). When strafe_mode or attack is active, mech aligns with camera forward.
	Input.action_press("fire_left")
	mecha.input_dir = Vector2(0, 1)
	mecha._apply_movement(0.5)
	var angle_attack_back = absf(wrapf(mecha.rotation.y, -PI, PI))
	_check(angle_attack_back < 0.35, "Moving backwards WHILE attacking turns mech FORWARD towards aim direction (angle=%.2f close to 0)" % angle_attack_back)
	Input.action_release("fire_left")

	# 3. Test Strafing Right (D key) WHILE attacking: mech still faces forward towards aim
	Input.action_press("fire_right")
	mecha.input_dir = Vector2(1, 0)
	mecha._apply_movement(0.5)
	var angle_attack_strafe = absf(wrapf(mecha.rotation.y, -PI, PI))
	_check(angle_attack_strafe < 0.35, "Strafing right WHILE attacking turns mech FORWARD towards aim direction (angle=%.2f close to 0)" % angle_attack_strafe)
	Input.action_release("fire_right")

	mecha.queue_free()
	cam.queue_free()

	print("ATTACK_FACING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
