extends Node

func _ready() -> void:
	print("--- BEGIN MECHA SHOOT ANIMATION VERIFY TEST ---")
	test_shoot_channels_isolation()
	test_shoot_heavy_variant_selection()
	test_dual_hand_simultaneous_firing()
	test_shoot_arm_splay_prevention()
	test_walking_arm_alignment()
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
	var names = ["arm_left", "arm_right", "forearm_left", "forearm_right", "body", "head", "leg_left", "leg_right"]
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


func test_shoot_arm_splay_prevention() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)
	var joints := _create_mock_joints()

	animator.play_shoot("right", false)
	animator.update(0.05)
	animator.apply_to_joints(joints)

	# Firing right arm must keep Y and Z at 0 (no T-pose flare)
	assert_true(absf(joints["arm_right"].rotation.y) < 0.001, "Right arm Y rotation remains 0.0 during shoot")
	assert_true(absf(joints["arm_right"].rotation.z) < 0.001, "Right arm Z rotation remains 0.0 during shoot (no T-pose flare)")

	# Let animation complete
	animator.update(1.0)
	assert_true(not animator.shoot_channel_right.is_active, "Right shoot channel finished")

	_free_mock_joints(joints)
	animator.queue_free()


func test_walking_arm_alignment() -> void:
	var walker := MechaWalkingSystem.new()
	add_child(walker)
	var joints := _create_mock_joints()

	var dummy_mecha := CharacterBody3D.new()
	dummy_mecha.velocity = Vector3(0, 0, -5.0) # Moving forward
	add_child(dummy_mecha)

	walker.is_moving = true
	walker.bob_timer = 1.0

	# Dirty the arm Y/Z rotation to simulate any potential external disturbance
	joints["arm_left"].rotation = Vector3(0.2, 0.8, -0.7)
	joints["arm_right"].rotation = Vector3(-0.2, -0.6, 0.9)

	walker.update_legs(0.1, dummy_mecha, joints)

	# Walking arm pump must restore Y and Z toward 0
	assert_true(absf(joints["arm_left"].rotation.y) < 0.5, "Walking pump recovers Left Arm Y rotation")
	assert_true(absf(joints["arm_left"].rotation.z) < 0.5, "Walking pump recovers Left Arm Z rotation")
	assert_true(absf(joints["arm_right"].rotation.y) < 0.5, "Walking pump recovers Right Arm Y rotation")
	assert_true(absf(joints["arm_right"].rotation.z) < 0.5, "Walking pump recovers Right Arm Z rotation")

	walker.queue_free()
	dummy_mecha.queue_free()
	_free_mock_joints(joints)
