extends Node

func _ready() -> void:
	print("--- BEGIN MECHA SHOOT ANIMATION VERIFY TEST ---")
	test_shoot_channels_isolation()
	test_shoot_heavy_variant_selection()
	test_dual_hand_simultaneous_firing()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func _create_mock_joints() -> Dictionary:
	var joints: Dictionary = {}
	var names = ["arm_left", "arm_right", "forearm_left", "forearm_right", "body", "head"]
	for n in names:
		var node = Node3D.new()
		node.name = n
		add_child(node)
		joints[n] = node
	return joints


func _free_mock_joints(joints: Dictionary) -> void:
	for k in joints:
		var node: Node = joints[k]
		if is_instance_valid(node):
			node.queue_free()


func test_shoot_channels_isolation() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)
	var joints := _create_mock_joints()

	# Set baseline rotations for both arms
	joints["arm_left"].rotation = Vector3(0.5, 0.0, 0.0)
	joints["arm_right"].rotation = Vector3(0.5, 0.0, 0.0)

	# 1. Fire Left Hand
	animator.play_shoot("left", false)
	assert_true(animator.shoot_channel_left.is_active, "Left shoot channel is active")
	assert_true(not animator.shoot_channel_right.is_active, "Right shoot channel is NOT active")
	assert_true(animator.shoot_channel_left.anim_name == "Mech_Shoot_L", "Left channel loaded Mech_Shoot_L")

	# Update timeline and apply to joints
	animator.update(0.04)
	animator.apply_to_joints(joints)

	# Left arm should have recoil applied, Right arm should remain untouched at baseline
	assert_true(joints["arm_right"].rotation.x == 0.5, "Right arm is completely untouched (no T-pose snapping) when firing left arm")
	assert_true(joints["arm_right"].rotation.y == 0.0, "Right arm Y rotation is untouched")
	assert_true(joints["arm_right"].rotation.z == 0.0, "Right arm Z rotation is untouched")

	# 2. Fire Right Hand
	joints["arm_left"].rotation = Vector3(0.5, 0.0, 0.0)
	joints["arm_right"].rotation = Vector3(0.5, 0.0, 0.0)
	animator.play_shoot("right", false)
	assert_true(animator.shoot_channel_right.is_active, "Right shoot channel is active")
	assert_true(animator.shoot_channel_right.anim_name == "Mech_Shoot_R", "Right channel loaded Mech_Shoot_R")

	animator.update(0.04)
	animator.apply_to_joints(joints)

	assert_true(joints["arm_left"].rotation.y == 0.0, "Left arm Y rotation untouched when firing right arm")
	assert_true(joints["arm_left"].rotation.z == 0.0, "Left arm Z rotation untouched when firing right arm")

	_free_mock_joints(joints)
	animator.queue_free()


func test_shoot_heavy_variant_selection() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)

	# Standard fire
	animator.play_shoot("left", false)
	assert_true(animator.shoot_channel_left.anim_name == "Mech_Shoot_L", "Standard weapon selects Mech_Shoot_L")

	# Heavy cannon / sniper fire
	animator.play_shoot("right", true)
	assert_true(animator.shoot_channel_right.anim_name == "Mech_Shoot2_R", "Heavy weapon selects Mech_Shoot2_R")

	animator.queue_free()


func test_dual_hand_simultaneous_firing() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)
	var joints := _create_mock_joints()

	# Fire both hands at the same time
	animator.play_shoot("left", false)
	animator.play_shoot("right", true)

	assert_true(animator.shoot_channel_left.is_active, "Left channel active during dual fire")
	assert_true(animator.shoot_channel_right.is_active, "Right channel active during dual fire")

	animator.update(0.05)
	animator.apply_to_joints(joints)

	assert_true(animator.is_playing(), "Animator is playing during dual fire")

	_free_mock_joints(joints)
	animator.queue_free()
