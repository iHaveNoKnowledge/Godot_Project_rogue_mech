extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running directional_walk_verify ---")
	await _verify_directional_gait()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_directional_gait() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	var leg_left := Node3D.new()
	leg_left.name = "LegLeft"
	mecha.add_child(leg_left)

	var leg_right := Node3D.new()
	leg_right.name = "LegRight"
	mecha.add_child(leg_right)

	var body := Node3D.new()
	body.name = "Body"
	mecha.add_child(body)

	var walking := MechaWalkingSystem.new()
	mecha.add_child(walking)

	var joints := {
		"leg_left": leg_left,
		"leg_right": leg_right,
		"body_mesh": body,
		"original_leg_left_pos": Vector3.ZERO,
		"original_leg_right_pos": Vector3.ZERO,
		"original_body_pos": Vector3.ZERO
	}

	walking.is_moving = true
	walking.bob_timer = 1.5

	# 1. Forward Walk (Velocity: -Z)
	mecha.velocity = Vector3(0, 0, -8)
	walking.update_legs(0.1, mecha, joints)
	walking.update_bob(0.1, mecha, joints, 0.15)
	_check(absf(leg_left.rotation.y) < deg_to_rad(15.0), "forward walk keeps hip yaw aligned forward")
	_check(body.rotation.x < 0.0, "forward sprint tilts torso forward")

	# 2. Right Strafe (Velocity: +X)
	mecha.velocity = Vector3(8, 0, 0)
	walking.update_legs(0.1, mecha, joints)
	walking.update_bob(0.1, mecha, joints, 0.15)
	_check(leg_left.rotation.y > deg_to_rad(10.0), "right strafe turns leg yaw toward right movement direction")
	_check(body.rotation.z < 0.0, "right strafe banks torso toward right")

	# 3. Left Strafe (Velocity: -X)
	mecha.velocity = Vector3(-8, 0, 0)
	walking.update_legs(0.1, mecha, joints)
	walking.update_bob(0.1, mecha, joints, 0.15)
	_check(leg_left.rotation.y < -deg_to_rad(10.0), "left strafe turns leg yaw toward left movement direction")
	_check(body.rotation.z > 0.0, "left strafe banks torso toward left")

	mecha.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All directional_walk_verify tests passed.")
		get_tree().quit(0)
	else:
		print("directional_walk_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
