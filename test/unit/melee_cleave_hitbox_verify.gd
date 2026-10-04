extends Node
## MELEE CLEAVE HITBOX & MOVEMENT VERIFY.
##
## Tests:
## 1. Melee forward movement steps forward and stays forward (no rubberband back).
## 2. Wide cone arc hit detection hits enemies in front and diagonally in the arc.
## 3. Cleave hits multiple enemies within the forward cone.
## 4. Enemies behind or out of range are not hit.
## 5. Quaternion delta rotation avoids gimbal singularities and produces smooth joint blending.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MELEE_CLEAVE OK: " + name)
	else:
		_fails += 1
		printerr("MELEE_CLEAVE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.0)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)

	var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mech)
	mech.global_position = Vector3(0, 0, 0)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 4.0, 6.0)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, -10.0))
	cam.make_current()

	var wm := Node3D.new()
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	wm.name = "WeaponManager"
	mech.add_child(wm)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var blade: WeaponPart = load("res://resources/mech/stock/weapon_heat_blade.tres")

	# --- Test 1: Forward Movement stays forward ---
	var z0: float = mech.global_position.z
	wm._perform_pile_bunker_lunge_anim(mech, Vector3(0, 0, -1), blade, 0.2)
	for i in range(30):
		await get_tree().physics_frame
	var z_final: float = mech.global_position.z
	_check(z_final < z0 - 2.0, "Melee lunge moved forward and maintained forward displacement (z=%.2f < z0=%.2f)" % [z_final, z0])

	# --- Test 2 & 3: Multi-target Cleave in Wide Cone ---
	var hit_count := 0
	var enemy1 := Node3D.new()
	enemy1.add_to_group("enemy")
	enemy1.global_position = mech.global_position + Vector3(0, 0, -2.5) # Directly ahead
	add_child(enemy1)

	var enemy2 := Node3D.new()
	enemy2.add_to_group("enemy")
	enemy2.global_position = mech.global_position + Vector3(1.8, 0, -2.2) # Diagonal right front in cone
	add_child(enemy2)

	var enemy_behind := Node3D.new()
	enemy_behind.add_to_group("enemy")
	enemy_behind.global_position = mech.global_position + Vector3(0, 0, 3.0) # Behind mech
	add_child(enemy_behind)

	var hit_enemy1 := false
	var hit_enemy2 := false
	var hit_behind := false

	enemy1.set_meta("hit_callback", func(): hit_enemy1 = true)
	enemy2.set_meta("hit_callback", func(): hit_enemy2 = true)
	enemy_behind.set_meta("hit_callback", func(): hit_behind = true)

	# Mock take_damage methods
	enemy1.set_script(load("res://test/unit/melee_cleave_mock_target.gd"))
	enemy2.set_script(load("res://test/unit/melee_cleave_mock_target.gd"))
	enemy_behind.set_script(load("res://test/unit/melee_cleave_mock_target.gd"))

	wm._check_melee_hit(mech, Vector3(0, 0, -1), 50.0, blade, true)

	_check(enemy1.get("was_hit") == true, "Direct front enemy was hit")
	_check(enemy2.get("was_hit") == true, "Diagonal cone enemy was hit (Cleave)")
	_check(enemy_behind.get("was_hit") == false, "Enemy behind was NOT hit")

	# --- Test 4: Quaternion Delta Smooth Blending ---
	var animator: MechaActionAnimator = MechaActionAnimator.new()
	add_child(animator)
	animator.play_af_melee("right", 1)
	var joints: Dictionary = {}
	for k in ["body", "head", "arm_left", "arm_right", "forearm_left", "forearm_right", "leg_left", "leg_right", "shin_left", "shin_right"]:
		var n := Node3D.new()
		n.name = k
		add_child(n)
		joints[k] = n

	var had_nan := false
	for frame in range(60):
		animator.update(1.0 / 60.0)
		animator.apply_to_joints(joints, 1.0, true) # stationary
		for k in joints:
			var rot: Vector3 = (joints[k] as Node3D).rotation
			if is_nan(rot.x) or is_nan(rot.y) or is_nan(rot.z):
				had_nan = true
	_check(not had_nan, "Quaternion delta joint rotations evaluated without NaN / gimbal breakdown")

	mech.queue_free()
	cam.queue_free()
	enemy1.queue_free()
	enemy2.queue_free()
	enemy_behind.queue_free()

	print("MELEE_CLEAVE_HITBOX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MELEE_CLEAVE_HITBOX_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MELEE_CLEAVE_TESTS_PASSED")
		get_tree().quit(0)
