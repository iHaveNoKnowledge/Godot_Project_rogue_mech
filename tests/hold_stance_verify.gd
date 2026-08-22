extends Node3D

## Verification test for Weapon Hold Stance System (Blade Upright, Pile Bunker Under-Arm, Rifle Aim).

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("STANCE_OK: %s" % msg)
	else:
		_fails += 1
		print("STANCE_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Weapon Hold Stance Verification ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().process_frame

	# 1. Test Blade / Mace -> MELEE_UPRIGHT
	var blade := WeaponPart.new()
	blade.weapon_name = "Heat Blade"
	blade.weapon_type = WeaponPart.WeaponType.MELEE

	var stance_blade = WeaponVisualFactory.get_effective_hold_stance(blade)
	_check(stance_blade == WeaponPart.HoldStance.MELEE_UPRIGHT, "Heat Blade inferred as MELEE_UPRIGHT")

	var mount_blade = WeaponVisualFactory.mount_hand(mecha, "left", blade, "TestBlade")
	_check(mount_blade != null and mount_blade.rotation_degrees.is_equal_approx(Vector3.ZERO), "Blade mount holds upright (rotation 0, 0, 0)")

	# 2. Test Pile Bunker -> PILE_BUNKER_GRIP (Under Forearm)
	var bunker := WeaponPart.new()
	bunker.weapon_name = "Heavy Pile Bunker"
	bunker.weapon_type = WeaponPart.WeaponType.MELEE

	var stance_bunker = WeaponVisualFactory.get_effective_hold_stance(bunker)
	_check(stance_bunker == WeaponPart.HoldStance.PILE_BUNKER_GRIP, "Pile Bunker inferred as PILE_BUNKER_GRIP")

	var mount_bunker = WeaponVisualFactory.mount_hand(mecha, "left", bunker, "TestBunker")
	_check(mount_bunker != null and mount_bunker.rotation_degrees.x < -70.0, "Pile Bunker aims forward under forearm")

	# 3. Test Rifle -> RANGED_RIFLE
	var rifle := WeaponPart.new()
	rifle.weapon_name = "Beam Rifle"
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE

	var stance_rifle = WeaponVisualFactory.get_effective_hold_stance(rifle)
	_check(stance_rifle == WeaponPart.HoldStance.RANGED_RIFLE, "Beam Rifle inferred as RANGED_RIFLE")

	var mount_rifle = WeaponVisualFactory.mount_hand(mecha, "right", rifle, "TestRifle")
	_check(mount_rifle != null and mount_rifle.rotation_degrees.x < -70.0, "Rifle aims forward")

	# 4. Test Forearm Mounted Hardpoint override
	var arm_bunker := WeaponPart.new()
	arm_bunker.weapon_name = "Arm Mounted Drill"
	arm_bunker.hold_stance = WeaponPart.HoldStance.FOREARM_MOUNTED

	var stance_arm = WeaponVisualFactory.get_effective_hold_stance(arm_bunker)
	_check(stance_arm == WeaponPart.HoldStance.FOREARM_MOUNTED, "Manual override to FOREARM_MOUNTED respected")

	var mount_arm = WeaponVisualFactory.mount_hand(mecha, "right", arm_bunker, "TestArmDrill")
	_check(mount_arm != null and mount_arm.position.y > -0.55, "FOREARM_MOUNTED attaches directly to mid-forearm chassis")

	print("--- Hold Stance Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_HOLD_STANCE_TESTS_PASSED")
