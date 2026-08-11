extends Node

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HANDMOUNT OK: " + name)
	else:
		_fails += 1
		printerr("HANDMOUNT FAIL: " + name)


func _build_weapon() -> WeaponPart:
	var weapon := WeaponPart.new()
	weapon.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	weapon.weapon_name = "Beam Rifle"
	return weapon


# Builds a minimal mech rig mirroring mecha_base.tscn's arm hierarchy so the
# factory can resolve the Arm*/Forearm* nodes exactly like the real scene.
func _build_mech_rig() -> Node3D:
	var mech := Node3D.new()
	var arm_left := Node3D.new()
	arm_left.name = "ArmLeft"
	var forearm_left := Node3D.new()
	forearm_left.name = "ForearmLeft"
	forearm_left.position = Vector3(0, -0.38, 0)
	arm_left.add_child(forearm_left)
	mech.add_child(arm_left)
	var arm_right := Node3D.new()
	arm_right.name = "ArmRight"
	var forearm_right := Node3D.new()
	forearm_right.name = "ForearmRight"
	forearm_right.position = Vector3(0, -0.38, 0)
	arm_right.add_child(forearm_right)
	mech.add_child(arm_right)
	return mech


func _ready() -> void:
	await get_tree().process_frame

	var weapon := _build_weapon()

	# 1. Weapon mounts under the Forearm node, NOT the mech root.
	var mech := _build_mech_rig()
	add_child(mech)
	await get_tree().process_frame
	var mount := WeaponVisualFactory.mount_hand(mech, "left", weapon, "WeaponVisual_left")
	_check(mount != null, "mount node created")
	_check(mount.get_parent() == mech.get_node("ArmLeft/ForearmLeft"),
		"left weapon is parented to ArmLeft/ForearmLeft")
	_check(mount.position.is_equal_approx(WeaponVisualFactory.HAND_FOREARM_POS),
		"left weapon sits at the hand position (forearm-local)")
	_check(mount.get_child_count() == 1, "left weapon has a rendered model child")

	# 2. Right hand mirrors the left.
	var mount_r := WeaponVisualFactory.mount_hand(mech, "right", weapon, "WeaponVisual_right")
	_check(mount_r.get_parent() == mech.get_node("ArmRight/ForearmRight"),
		"right weapon is parented to ArmRight/ForearmRight")
	_check(mount_r.position.is_equal_approx(WeaponVisualFactory.HAND_FOREARM_POS),
		"right weapon sits at the hand position (forearm-local)")

	# 3. Re-mounting the same hand reuses the node (no pile-up / no orphan).
	var before_count := mech.get_node("ArmLeft/ForearmLeft").get_child_count()
	var mount2 := WeaponVisualFactory.mount_hand(mech, "left", weapon, "WeaponVisual_left")
	_check(mount2 == mount, "re-mount reuses the same mount node")
	_check(mech.get_node("ArmLeft/ForearmLeft").get_child_count() == before_count,
		"no duplicate mount nodes pile up on re-mount")

	# 4. Passing a null weapon clears the hand mount (weapon removed).
	#    queue_free is deferred, so wait a frame before asserting.
	WeaponVisualFactory.mount_hand(mech, "left", null, "WeaponVisual_left")
	await get_tree().process_frame
	_check(mount.get_child_count() == 0, "null weapon clears the hand mount children")

	# 5. The weapon still follows the forearm when the arm rotates (mount is a
	#    child of the animated node, so it inherits the transform).
	var forearm_left: Node3D = mech.get_node("ArmLeft/ForearmLeft")
	var mount3 := WeaponVisualFactory.mount_hand(mech, "left", weapon, "WeaponVisual_left")
	var local_before: Vector3 = mount3.global_position
	forearm_left.rotation.x = deg_to_rad(55.0)
	await get_tree().process_frame
	_check(not mount3.global_position.is_equal_approx(local_before),
		"weapon moves with the animated forearm")

	# 6. Fallback: a rig WITHOUT Arm*/Forearm* nodes mounts on the mech root at
	#    the legacy fixed offset (never crashes, stays backward compatible).
	var plain := Node3D.new()
	add_child(plain)
	await get_tree().process_frame
	var fallback := WeaponVisualFactory.mount_hand(plain, "left", weapon, "WeaponVisual_left")
	_check(fallback.get_parent() == plain, "fallback rig parents the mount to the mech root")
	_check(fallback.position == WeaponVisualFactory.hand_mount_position("left"),
		"fallback rig uses the legacy fixed hand offset")

	print("HAND_MOUNT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
