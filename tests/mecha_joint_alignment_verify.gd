extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running mecha_joint_alignment_verify ---")
	await _verify_joint_transforms()
	await _verify_carry_weapon_orientation()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_joint_transforms() -> void:
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().process_frame

	var head = mecha.get_node_or_null("Head")
	var body = mecha.get_node_or_null("Body")
	var arm_l = mecha.get_node_or_null("ArmLeft")
	var arm_r = mecha.get_node_or_null("ArmRight")

	_check(head != null and is_equal_approx(head.position.y, 2.30), "Head Y positioned at 2.30m (lowered to connect with neck base)")
	_check(head != null and is_equal_approx(head.position.z, -0.04), "Head Z aligned forward with body collar (-0.04m)")

	_check(arm_l != null and is_equal_approx(arm_l.position.y, 2.05), "ArmLeft Y aligned with shoulder socket (2.05m)")
	_check(arm_r != null and is_equal_approx(arm_r.position.y, 2.05), "ArmRight Y aligned with shoulder socket (2.05m)")

	mecha.queue_free()
	await get_tree().process_frame


func _verify_carry_weapon_orientation() -> void:
	_check(WeaponVisualFactory.BACK_ROT_DEG.x <= -90.0, "Back carry rotation pitches weapon vertically upright (<= -90 deg on X)")
	_check(WeaponVisualFactory.BACK_Z >= 0.60, "Back carry mount is positioned clear behind backpack (Z >= 0.60m)")


func _finish() -> void:
	if _failures == 0:
		print("All mecha_joint_alignment_verify tests passed.")
		get_tree().quit(0)
	else:
		print("mecha_joint_alignment_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
