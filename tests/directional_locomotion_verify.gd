extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running directional_locomotion_verify ---")
	_verify_forward_and_reverse_gait_math()
	_verify_strafe_gait_math()
	await _verify_8way_locomotion_joints()
	await _verify_torso_banking_and_pitch()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_forward_and_reverse_gait_math() -> void:
	print("Testing Forward & Reverse Gait Mathematical Bounds...")

	# Sample across full phase circle
	for i in range(20):
		var phase: float = (float(i) / 20.0) * TAU
		var fwd := MechaWalkingSystem.calc_sprint_leg(phase)
		var rev := MechaWalkingSystem.calc_reverse_leg(phase)

		# Knee flexion must always bend backwards (shin angle <= 0) to avoid hyperextension
		_check(fwd["shin"] <= 0.001, "Forward sprint knee flexes backwards at phase %.2f (shin=%.2f)" % [phase, fwd["shin"]])
		_check(rev["shin"] <= 0.001, "Reverse backpedal knee flexes backwards at phase %.2f (shin=%.2f)" % [phase, rev["shin"]])

		# Step lift during swing phase [0, PI]
		if phase < PI and phase > 0.1:
			_check(fwd["lift"] > 0.0, "Forward leg has positive ground lift during swing (lift=%.3f)" % fwd["lift"])
			_check(rev["lift"] > 0.0, "Reverse leg has positive ground lift during swing (lift=%.3f)" % rev["lift"])


func _verify_strafe_gait_math() -> void:
	print("Testing Strafe Gait Math...")
	var strafe_out := MechaWalkingSystem.calc_strafe_leg(PI * 0.5, true)
	var strafe_in := MechaWalkingSystem.calc_strafe_leg(PI * 0.5, false)

	_check(strafe_out["roll"] > 0.0, "Outward strafe leg abducts outward (roll=%.2f)" % strafe_out["roll"])
	_check(strafe_out["lift"] > 0.1, "Strafe leg has positive step lift during swing (lift=%.3f)" % strafe_out["lift"])
	_check(strafe_in["roll"] > 0.0, "Inward strafe leg roll calculated correctly")


func _verify_8way_locomotion_joints() -> void:
	print("Testing 8-Directional Locomotion Simulation...")

	var mecha := CharacterBody3D.new()
	mecha.name = "TestMecha"
	add_child(mecha)

	var leg_left := Node3D.new()
	leg_left.name = "LegLeft"
	mecha.add_child(leg_left)

	var shin_left := Node3D.new()
	shin_left.name = "ShinLeft"
	leg_left.add_child(shin_left)

	var leg_right := Node3D.new()
	leg_right.name = "LegRight"
	mecha.add_child(leg_right)

	var shin_right := Node3D.new()
	shin_right.name = "ShinRight"
	leg_right.add_child(shin_right)

	var walk := MechaWalkingSystem.new()
	mecha.add_child(walk)

	var joints := {
		"leg_left": leg_left,
		"leg_right": leg_right,
		"shin_left": shin_left,
		"shin_right": shin_right,
		"original_leg_left_pos": Vector3(-0.5, 0, 0),
		"original_leg_right_pos": Vector3(0.5, 0, 0),
	}

	var test_directions := {
		"Forward": Vector3(0, 0, -10),
		"Backward": Vector3(0, 0, 10),
		"Left": Vector3(-10, 0, 0),
		"Right": Vector3(10, 0, 0),
		"Forward-Left": Vector3(-7.07, 0, -7.07),
		"Forward-Right": Vector3(7.07, 0, -7.07),
		"Backward-Left": Vector3(-7.07, 0, 7.07),
		"Backward-Right": Vector3(7.07, 0, 7.07),
	}

	for dir_name in test_directions:
		var vel: Vector3 = test_directions[dir_name]
		mecha.velocity = vel
		walk.is_moving = true
		walk.bob_timer = 1.2 # Mid-stride

		walk.update_legs(0.1, mecha, joints)

		# Hip swivel must stay within +/- 60 deg (+/- 1.05 rad)
		_check(absf(leg_left.rotation.y) <= deg_to_rad(65.0), "%s: Left hip swivel (%.2f deg) within +/-60 deg limit" % [dir_name, rad_to_deg(leg_left.rotation.y)])
		_check(absf(leg_right.rotation.y) <= deg_to_rad(65.0), "%s: Right hip swivel (%.2f deg) within +/-60 deg limit" % [dir_name, rad_to_deg(leg_right.rotation.y)])

		# Shins must remain flexed naturally
		_check(shin_left.rotation.x <= 0.05, "%s: Left knee properly flexed without forward hyperextension (shin=%.2f)" % [dir_name, shin_left.rotation.x])
		_check(shin_right.rotation.x <= 0.05, "%s: Right knee properly flexed without forward hyperextension (shin=%.2f)" % [dir_name, shin_right.rotation.x])

	mecha.queue_free()
	await get_tree().process_frame


func _verify_torso_banking_and_pitch() -> void:
	print("Testing Torso Banking & Acceleration Pitch...")

	var mecha := CharacterBody3D.new()
	add_child(mecha)

	var body := Node3D.new()
	mecha.add_child(body)
	var head := Node3D.new()
	mecha.add_child(head)

	var walk := MechaWalkingSystem.new()
	mecha.add_child(walk)

	var joints := {
		"body_mesh": body,
		"head_mesh": head,
		"original_body_pos": Vector3.ZERO,
		"original_head_pos": Vector3(0, 1.5, 0),
	}

	walk.is_moving = true

	# 1. Forward Sprint lean
	mecha.velocity = Vector3(0, 0, -10)
	for _i in range(10):
		walk.update_bob(0.05, mecha, joints, 0.15)
	_check(body.rotation.x < 0.0, "Torso leans forward when moving forward (pitch=%.2f deg)" % rad_to_deg(body.rotation.x))

	# 2. Backward walk counter-pitch
	body.rotation = Vector3.ZERO
	mecha.velocity = Vector3(0, 0, 10)
	for _i in range(10):
		walk.update_bob(0.05, mecha, joints, 0.15)
	_check(body.rotation.x > 0.0, "Torso counter-leans when backpedaling (pitch=%.2f deg)" % rad_to_deg(body.rotation.x))

	# 3. Strafe right banking
	body.rotation = Vector3.ZERO
	mecha.velocity = Vector3(10, 0, 0)
	for _i in range(10):
		walk.update_bob(0.05, mecha, joints, 0.15)
	_check(body.rotation.z < 0.0, "Torso banks into right strafe (bank=%.2f deg)" % rad_to_deg(body.rotation.z))

	# 4. Strafe left banking
	body.rotation = Vector3.ZERO
	mecha.velocity = Vector3(-10, 0, 0)
	for _i in range(10):
		walk.update_bob(0.05, mecha, joints, 0.15)
	_check(body.rotation.z > 0.0, "Torso banks into left strafe (bank=%.2f deg)" % rad_to_deg(body.rotation.z))

	mecha.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All directional_locomotion_verify tests passed successfully!")
		get_tree().quit(0)
	else:
		print("directional_locomotion_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
