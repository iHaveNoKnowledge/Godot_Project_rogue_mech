extends Node3D

## Verification test for Mecha Foot IK & Ground Placement System:
## Tests node resolution, raycast setup, slope ankle alignment, and weight blending.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("FOOT_IK_OK: %s" % msg)
	else:
		_fails += 1
		print("FOOT_IK_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Mecha Foot IK Verification ---")

	# 1. Instantiate MechaBase scene
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null, "MechaBase scene loaded successfully")

	var mecha := mecha_scene.instantiate() as CharacterBody3D
	add_child(mecha)
	mecha.global_position = Vector3(0, 0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# 2. Verify FootIKSystem component
	var foot_ik := mecha.get_node_or_null("FootIKSystem") as MechaFootIK
	_check(foot_ik != null, "FootIKSystem node exists under MechaBase")
	_check(foot_ik.ray_left != null and foot_ik.ray_right != null, "FootIKSystem initialized left and right raycasts")
	_check(foot_ik.ray_left.collision_mask == 1, "Left raycast collision mask includes terrain (layer 1)")
	_check(foot_ik.ray_right.collision_mask == 1, "Right raycast collision mask includes terrain (layer 1)")

	# 3. Test Ankle Angle Calculation on a 25-degree slope normal
	var slope_normal := Vector3(0, cos(deg_to_rad(25.0)), -sin(deg_to_rad(25.0))).normalized()
	foot_ik.ik_weight = 1.0
	foot_ik._apply_ankle_alignment(foot_ik.foot_left, slope_normal, 1.0, true)

	var foot_rot_x: float = foot_ik.foot_left.rotation.x
	_check(absf(foot_rot_x) > 0.05, "FootLeft rotated to align with slope normal (pitch: %.2f deg)" % rad_to_deg(foot_rot_x))

	# 4. Test IK Weight Blending (airborne -> weight decreases toward 0)
	# Simulate airborne state
	var start_weight = foot_ik.ik_weight
	for i in range(10):
		foot_ik.update_ik(0.016)
	_check(foot_ik.ik_weight < start_weight, "FootIK weight blends down when airborne (weight: %.2f)" % foot_ik.ik_weight)

	print("--- Mecha Foot IK Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_FOOT_IK_TESTS_PASSED")
