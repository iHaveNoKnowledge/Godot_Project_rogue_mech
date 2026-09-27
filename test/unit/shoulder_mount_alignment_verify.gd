extends Node
## VALKREN — SHOULDER WEAPON ATTACHMENT ALIGNMENT & RUNTIME INVARIANT VERIFY
## Validates that shoulder weapons mount under ArmLeft/ArmRight, use correct coordinate space,
## follow shoulder animation transforms, do not leak into legs or break arm/leg/carry attachments.

const MECHA_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _checks := 0
var _fails := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + msg)
	else:
		_fails += 1
		printerr("  FAIL: " + msg)

func _ready() -> void:
	print("--- Running shoulder_mount_alignment_verify ---")
	await get_tree().process_frame

	var missile_res: WeaponPart = load("res://resources/mech/stock/weapon_combat_shotgun.tres")
	if missile_res == null:
		missile_res = WeaponPart.new()
		missile_res.weapon_name = "Shoulder Test Cannon"
		missile_res.weapon_type = WeaponPart.WeaponType.MISSILE

	var rifle_res: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	if rifle_res == null:
		rifle_res = WeaponPart.new()
		rifle_res.weapon_name = "Hand Test Rifle"
		rifle_res.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE

	# Instantiate live MechaBase scene
	var mecha_scene: PackedScene = load(MECHA_SCENE)
	_check(mecha_scene != null, "mecha_base.tscn loads successfully")
	var mecha: Node3D = mecha_scene.instantiate() as Node3D
	add_child(mecha)
	await get_tree().process_frame

	var arm_l := mecha.get_node_or_null("ArmLeft") as Node3D
	var arm_r := mecha.get_node_or_null("ArmRight") as Node3D
	var leg_l := mecha.get_node_or_null("LegLeft") as Node3D
	var leg_r := mecha.get_node_or_null("LegRight") as Node3D
	var forearm_l := mecha.get_node_or_null("ArmLeft/ForearmLeft") as Node3D

	_check(arm_l != null and arm_r != null, "Mecha has ArmLeft and ArmRight joints")
	_check(leg_l != null and leg_r != null, "Mecha has LegLeft and LegRight joints")

	# =========================================================================
	# Case A: Left Shoulder Weapon
	# =========================================================================
	print("\n-- Case A: Left Shoulder Weapon --")
	var mount_sl = WeaponVisualFactory.mount_shoulder(mecha, "left", missile_res, "ShoulderMesh_left")
	_check(mount_sl != null, "Left shoulder mount created")
	_check(mount_sl.get_parent() == arm_l, "Left shoulder is parented to ArmLeft (NOT root or Leg)")
	_check(mount_sl.position.is_equal_approx(WeaponVisualFactory.SHOULDER_ARM_POS), "Left shoulder uses SHOULDER_ARM_POS")
	_check(mount_sl.global_position.y > leg_l.global_position.y + 1.0, "Left shoulder is high above leg joint (> 1.0m above LegLeft)")
	_check(mount_sl.get_parent() != leg_l and mount_sl.get_parent() != leg_r, "Left shoulder is NOT parented to legs")

	# =========================================================================
	# Case B: Right Shoulder Weapon
	# =========================================================================
	print("\n-- Case B: Right Shoulder Weapon --")
	var mount_sr = WeaponVisualFactory.mount_shoulder(mecha, "right", missile_res, "ShoulderMesh_right")
	_check(mount_sr != null, "Right shoulder mount created")
	_check(mount_sr.get_parent() == arm_r, "Right shoulder is parented to ArmRight (NOT root or Leg)")
	_check(mount_sr.position.is_equal_approx(WeaponVisualFactory.SHOULDER_ARM_POS), "Right shoulder uses SHOULDER_ARM_POS")
	_check(mount_sr.global_position.y > leg_r.global_position.y + 1.0, "Right shoulder is high above leg joint (> 1.0m above LegRight)")

	print("\n-- Case C: Both Shoulder Weapons Coexistence & Symmetry --")
	_check(mount_sl.is_inside_tree() and mount_sr.is_inside_tree(), "Both shoulder mounts coexist in tree")
	print("  SL Y=%f, SR Y=%f (diff=%f)" % [mount_sl.global_position.y, mount_sr.global_position.y, absf(mount_sl.global_position.y - mount_sr.global_position.y)])
	_check(absf(mount_sl.global_position.y - mount_sr.global_position.y) < 0.15, "Both shoulder weapons are level on Y (within 0.15m tolerance)")
	_check(mount_sl.global_position.x < 0.0 and mount_sr.global_position.x > 0.0, "Left is on -X, Right is on +X")
	_check(absf(mount_sl.global_position.x + mount_sr.global_position.x) < 0.15, "Bilateral symmetry about mecha center")

	# =========================================================================
	# Case D: Shoulder Weapon + Arm Weapon (Hand)
	# =========================================================================
	print("\n-- Case D: Shoulder Weapon + Hand Weapon Isolation --")
	var mount_hand = WeaponVisualFactory.mount_hand(mecha, "left", rifle_res, "WeaponMesh_left")
	_check(mount_hand != null, "Hand mount created")
	_check(mount_hand.get_parent() == forearm_l, "Hand weapon parented to ForearmLeft")
	_check(mount_sl.get_parent() == arm_l, "Shoulder weapon remains parented to ArmLeft")
	_check(mount_hand.global_position.y < mount_sl.global_position.y - 0.5, "Hand weapon sits well below shoulder weapon")

	# =========================================================================
	# Case E: Shoulder Weapon + Leg Equipment Independence
	# =========================================================================
	print("\n-- Case E: Leg Joints Untouched --")
	var leg_child_count_before = leg_l.get_child_count()
	_check(leg_l.get_node_or_null("ShoulderMesh_left") == null, "LegLeft has no shoulder weapon child")
	_check(leg_r.get_node_or_null("ShoulderMesh_right") == null, "LegRight has no shoulder weapon child")

	# =========================================================================
	# Case F: Animation / Joint Articulation Invariant
	# =========================================================================
	print("\n-- Case F: Animation Joint Rotation Invariant --")
	var sl_world_before = mount_sl.global_position
	# Rotate shoulder joint (simulate walk / combat aim / recoil)
	arm_l.rotation.x = deg_to_rad(35.0)
	arm_l.rotation.z = deg_to_rad(-15.0)
	await get_tree().process_frame

	_check(mount_sl.position.is_equal_approx(WeaponVisualFactory.SHOULDER_ARM_POS), "Shoulder weapon local position remains invariant during joint rotation")
	_check(not mount_sl.global_position.is_equal_approx(sl_world_before), "Shoulder weapon global position follows the rotated ArmLeft joint")
	var dist_to_arm: float = mount_sl.global_position.distance_to(arm_l.global_position)
	_check(absf(dist_to_arm - WeaponVisualFactory.SHOULDER_ARM_POS.length()) < 0.05, "Distance from shoulder mount to ArmLeft pivot remains constant (%f)" % dist_to_arm)

	# Reset arm rotation
	arm_l.rotation = Vector3.ZERO
	await get_tree().process_frame

	# =========================================================================
	# Equip / Unequip Lifecycle
	# =========================================================================
	print("\n-- Equip / Unequip Lifecycle --")
	# Null weapon clears children
	WeaponVisualFactory.mount_shoulder(mecha, "left", null, "ShoulderMesh_left")
	await get_tree().process_frame
	_check(mount_sl.get_child_count() == 0, "Null weapon unmounts model children from shoulder")

	# Remount restores model
	var remount = WeaponVisualFactory.mount_shoulder(mecha, "left", missile_res, "ShoulderMesh_left")
	_check(remount == mount_sl, "Remount reuses existing shoulder mount node")
	_check(remount.get_child_count() > 0, "Remount creates fresh model child")

	# Clean up
	mecha.queue_free()
	await get_tree().process_frame

	# =========================================================================
	# Fallback Rig Compatibility
	# =========================================================================
	print("\n-- Fallback Plain Rig Compatibility --")
	var plain_mech = Node3D.new()
	add_child(plain_mech)
	var fallback_sl = WeaponVisualFactory.mount_shoulder(plain_mech, "left", missile_res, "ShoulderMesh_left")
	_check(fallback_sl.get_parent() == plain_mech, "Fallback rig mounts shoulder to mech root")
	_check(fallback_sl.position.is_equal_approx(WeaponVisualFactory.SHOULDER_LEFT_POS), "Fallback rig uses SHOULDER_LEFT_POS (%s)" % str(fallback_sl.position))
	_check(fallback_sl.position.y > 4.0, "Fallback SHOULDER_LEFT_POS is at shoulder height (> 4.0m, not leg level)")
	plain_mech.queue_free()

	print("\n========================================================")
	if _fails == 0:
		print("ALL SHOULDER MOUNT ALIGNMENT CHECKS PASSED: %d/%d" % [_checks, _checks])
		get_tree().quit(0)
	else:
		printerr("SHOULDER MOUNT ALIGNMENT FAILED: %d errors out of %d checks" % [_fails, _checks])
		get_tree().quit(1)
