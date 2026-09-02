extends Node

const MechaBaseScene = preload("res://scenes/mecha/mecha_base.tscn")
const AllyDummyScene = preload("res://scenes/mecha/ally_dummy.tscn")
const EnemyDummyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("=== Starting AI Mecha Forward Facing & Speed Parity Verification ===")
	_test_ai_mecha_cardinal_facing()
	_test_ai_mecha_speed_and_roller_dash()
	_test_ally_dummy_facing_and_speed()
	_test_enemy_dummy_facing_and_speed()
	_test_walking_animation_forward_gait()

	print("=== AI Facing & Speed Finished: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL_AI_FACING_AND_SPEED_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("AI_FACING_OK: %s" % label)
	else:
		_failed += 1
		push_error("AI_FACING_FAIL: %s" % label)


func _test_ai_mecha_cardinal_facing() -> void:
	var world := Node3D.new()
	add_child(world)

	var mecha = MechaBaseScene.instantiate()
	mecha.is_player_driven = false
	world.add_child(mecha)
	mecha.global_position = Vector3(0, 0, 0)

	var cardinal_dirs = [
		{"name": "North (-Z)", "dir": Vector3(0, 0, -1)},
		{"name": "South (+Z)", "dir": Vector3(0, 0, 1)},
		{"name": "East (+X)", "dir": Vector3(1, 0, 0)},
		{"name": "West (-X)", "dir": Vector3(-1, 0, 0)},
	]

	for c in cardinal_dirs:
		var dir: Vector3 = c["dir"]
		# Send drive command
		mecha.set_drive_commands(dir, Vector3.ZERO)
		# Step physics
		for step in range(15):
			mecha._physics_process(0.05)

		var fwd_heading: Vector3 = -mecha.global_transform.basis.z.normalized()
		var dot = fwd_heading.dot(dir)
		_assert(dot > 0.85, "AI Mecha moving %s faces forward along movement vector (dot = %.3f > 0.85)" % [c["name"], dot])
		_assert(dot > 0.0, "AI Mecha does NOT face backward (180 deg off) when moving %s" % c["name"])

	world.queue_free()


func _test_ai_mecha_speed_and_roller_dash() -> void:
	var world := Node3D.new()
	add_child(world)

	var mecha = MechaBaseScene.instantiate()
	mecha.is_player_driven = false
	world.add_child(mecha)

	_assert(mecha.current_speed >= 10.0, "AI Mecha base speed is >= 10.0 m/s matching player (got %.2f)" % mecha.current_speed)

	# Test walking speed
	mecha.set_drive_commands(Vector3(0, 0, 1), Vector3.ZERO)
	mecha._physics_process(0.05)
	var walk_vel = Vector3(mecha.velocity.x, 0, mecha.velocity.z).length()
	_assert(walk_vel >= 10.0, "AI Mecha walks at full battle speed (velocity = %.2f m/s)" % walk_vel)

	# Test high-speed roller dash capability
	mecha.set_drive_commands(Vector3(0, 0, 1), Vector3.ZERO, false, false, false, false, true)
	mecha._physics_process(0.05)
	var sprint_vel = Vector3(mecha.velocity.x, 0, mecha.velocity.z).length()
	_assert(sprint_vel >= 20.0, "AI Mecha roller dash reaches sprint velocity (%.2f >= 20.0 m/s)" % sprint_vel)

	world.queue_free()


func _test_ally_dummy_facing_and_speed() -> void:
	var world := Node3D.new()
	add_child(world)

	var ally = AllyDummyScene.instantiate()
	world.add_child(ally)

	_assert(ally.move_speed >= 13.5, "AllyDummy move_speed upgraded to player parity (%.2f >= 13.5 m/s)" % ally.move_speed)

	# Simulate target south (+Z)
	var target = Node3D.new()
	world.add_child(target)
	target.global_position = Vector3(0, 0, 50)
	ally.target = target

	# Chase target
	for step in range(12):
		ally._move_toward_target(0.05)

	var fwd_heading = -ally.global_transform.basis.z.normalized()
	var to_target = (target.global_position - ally.global_position).normalized()
	var dot = fwd_heading.dot(to_target)
	_assert(dot > 0.85, "AllyDummy faces forward toward target while chasing (dot = %.3f > 0.85)" % dot)
	_assert(dot > 0.0, "AllyDummy is NOT facing backward away from chase target")

	world.queue_free()


func _test_enemy_dummy_facing_and_speed() -> void:
	var world := Node3D.new()
	add_child(world)

	var enemy = EnemyDummyScene.instantiate()
	world.add_child(enemy)

	_assert(enemy.move_speed >= 13.0, "EnemyDummy move_speed upgraded to player parity (%.2f >= 13.0 m/s)" % enemy.move_speed)

	# Test dash facing
	enemy.dash_direction = Vector3(1, 0, 0)
	enemy.is_dashing = true
	enemy.dash_timer = 0.5
	enemy._physics_process(0.1)

	var fwd_heading = -enemy.global_transform.basis.z.normalized()
	var dot = fwd_heading.dot(Vector3(1, 0, 0))
	_assert(dot > 0.85, "EnemyDummy faces forward in dash direction (dot = %.3f > 0.85)" % dot)

	world.queue_free()


func _test_walking_animation_forward_gait() -> void:
	var world := Node3D.new()
	add_child(world)

	var mecha = MechaBaseScene.instantiate()
	mecha.is_player_driven = false
	world.add_child(mecha)

	# Drive south (+Z)
	mecha.set_drive_commands(Vector3(0, 0, 1), Vector3.ZERO)
	for i in range(10):
		mecha._physics_process(0.05)

	# Check local velocity relative to mecha transform
	var local_vel = mecha.global_transform.basis.inverse() * mecha.velocity
	local_vel.y = 0.0
	var speed = local_vel.length()
	var fwd_ratio = clampf(-local_vel.z / speed, -1.0, 1.0)

	_assert(fwd_ratio > 0.85, "MechaWalkingSystem fwd_ratio is positive forward sprint (fwd_ratio = %.3f > 0.85, NOT negative backpedal)" % fwd_ratio)

	world.queue_free()
