extends Node

const MissileLockOnSystemClass = preload("res://scripts/systems/missile_lock_on_system.gd")

func _ready() -> void:
	print("--- Running test_missile_and_shoulder ---")
	var success: bool = true

	# Test 1: Shoulder weapon loadout manipulation
	var test_path: String = "res://resources/mech/stock/weapon_missile.tres"
	var uid1 = LoadoutSystem.register_weapon(test_path, "Missile Pod 1")
	var uid2 = LoadoutSystem.register_weapon(test_path, "Missile Pod 2")

	var ok_l: bool = LoadoutSystem.set_shoulder_weapon("left", uid1)
	var shoulder_l = LoadoutSystem.get_equipped_shoulder("left")
	if not ok_l or shoulder_l == null:
		printerr("[FAIL] Test 1: Failed to set shoulder_left weapon")
		success = false
	else:
		print("  PASS: shoulder_left equipped successfully with uid: ", uid1)

	var ok_r: bool = LoadoutSystem.set_shoulder_weapon("right", uid2)
	var shoulder_r = LoadoutSystem.get_equipped_shoulder("right")
	if not ok_r or shoulder_r == null:
		printerr("[FAIL] Test 1: Failed to set shoulder_right weapon")
		success = false
	else:
		print("  PASS: shoulder_right equipped successfully with uid: ", uid2)

	# Test 2: Missile Lock-on System logic
	var lock_sys = MissileLockOnSystemClass.new()
	add_child(lock_sys)

	var dummy_weapon := WeaponPart.new()
	dummy_weapon.weapon_name = "Missile Launcher"
	dummy_weapon.weapon_type = WeaponPart.WeaponType.MISSILE
	dummy_weapon.max_ammo = 6
	dummy_weapon.range_distance = 150.0

	lock_sys.start_locking("shoulder_left", dummy_weapon, 6)
	if not lock_sys.is_locking or lock_sys.max_total_locks != 6:
		printerr("[FAIL] Test 2: MissileLockOnSystem failed to start locking")
		success = false
	else:
		print("  PASS: MissileLockOnSystem started locking with max_total_locks=6")

	# Mock dummy enemies
	var dummy_enemy_1 := Node3D.new()
	dummy_enemy_1.name = "Enemy1"
	dummy_enemy_1.add_to_group("enemy")
	add_child(dummy_enemy_1)
	dummy_enemy_1.global_position = Vector3(0, 0, -20)

	var dummy_enemy_2 := Node3D.new()
	dummy_enemy_2.name = "Enemy2"
	dummy_enemy_2.add_to_group("enemy")
	add_child(dummy_enemy_2)
	dummy_enemy_2.global_position = Vector3(5, 0, -25)

	# Simulate stacking
	lock_sys.locked_targets[dummy_enemy_1] = 2
	lock_sys.locked_targets[dummy_enemy_2] = 3

	if lock_sys.get_total_locks() != 5:
		printerr("[FAIL] Test 3: Total locks mismatch: ", lock_sys.get_total_locks())
		success = false
	else:
		print("  PASS: Total locks stacked properly = 5")

	var release_res: Dictionary = lock_sys.stop_locking()
	if lock_sys.is_locking or int(release_res.get("total_locks", 0)) != 5 or (release_res.get("targets") as Dictionary).size() != 2:
		printerr("[FAIL] Test 4: stop_locking returned incorrect results")
		success = false
	else:
		print("  PASS: stop_locking cleanly returned 5 locks across 2 targets")

	# Test 5: Projectile homing turning
	var proj := CharacterBody3D.new()
	proj.set_script(preload("res://scripts/systems/projectile.gd"))
	add_child(proj)
	proj.global_position = Vector3(0, 0, 0)
	proj.direction = Vector3(0, 0, -1)
	proj.speed = 40.0
	proj.target_node = dummy_enemy_2 # positioned at (5, 0, -25) -> needs positive X turn
	proj.initial_boost_timer = 0.0 # activate homing immediately
	proj.timer = 0.01

	var initial_x: float = proj.direction.x
	proj._physics_process(0.1)
	var new_x: float = proj.direction.x
	if new_x <= initial_x:
		printerr("[FAIL] Test 5: Projectile did not turn towards target: initial_x=", initial_x, " new_x=", new_x)
		success = false
	else:
		print("  PASS: Projectile homing steered correctly towards target (direction.x changed from %f to %f)" % [initial_x, new_x])

	# Cleanup
	proj.queue_free()
	dummy_enemy_1.queue_free()
	dummy_enemy_2.queue_free()
	lock_sys.queue_free()

	if success:
		print("ALL MISSILE & SHOULDER TESTS PASSED SUCCESSFULLY!")
		get_tree().quit(0)
	else:
		printerr("TESTS FAILED")
		get_tree().quit(1)
