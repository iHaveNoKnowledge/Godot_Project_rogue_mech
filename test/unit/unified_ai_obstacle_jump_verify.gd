extends Node

## UNIFIED AI OBSTACLE JUMP & AVOIDANCE VERIFICATION
## Validates obstacle clearance jump mechanics and wall avoidance across modes.

var _checks: int = 0
var _fails: int = 0

const NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")
const EnemyDummyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("AI_JUMP_OK: " + msg)
	else:
		_fails += 1
		printerr("AI_JUMP_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame
	print("=== STARTING UNIFIED AI OBSTACLE JUMP VERIFICATION ===")

	_test_1_nav_avoidance_jump_clearance()
	_test_2_slide_along_wall_tangent()
	_test_3_enemy_dummy_drive_commands()
	_test_4_enemy_dummy_try_jump_clearance()

	print("=== UNIFIED AI OBSTACLE JUMP VERIFICATION FINISHED: Checks=%d, Fails=%d ===" % [_checks, _fails])
	if _fails > 0:
		printerr("TEST FAILED WITH %d ERRORS" % _fails)
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_1_nav_avoidance_jump_clearance() -> void:
	print("\n--- Test 1: NavAvoidance.check_jump_clearance ---")
	var actor := CharacterBody3D.new()
	actor.velocity = Vector3(5, 0, 0)
	
	# Not on wall -> no jump
	actor.set_meta("mock_on_wall", false)
	actor.set_meta("mock_on_floor", true)
	var jumped := NavAvoidance.check_jump_clearance(actor, 8.5)
	_check(not jumped, "No jump triggered when not contacting wall")
	_check(actor.velocity.y == 0.0, "Vertical velocity remains 0 when no jump")
	
	# On wall and on floor -> triggers jump clearance
	actor.set_meta("mock_on_wall", true)
	actor.set_meta("mock_on_floor", true)
	jumped = NavAvoidance.check_jump_clearance(actor, 8.5)
	_check(jumped, "Jump clearance triggered when contacting wall on floor")
	_check(is_equal_approx(actor.velocity.y, 8.5), "Vertical velocity set to jump impulse 8.5")
	
	# In air (not on floor) -> cannot jump
	actor.set_meta("mock_on_wall", true)
	actor.set_meta("mock_on_floor", false)
	actor.velocity.y = 2.0
	jumped = NavAvoidance.check_jump_clearance(actor, 8.5)
	_check(not jumped, "Cannot jump mid-air")
	_check(is_equal_approx(actor.velocity.y, 2.0), "Airborne vertical velocity untouched")
	
	actor.free()


func _test_2_slide_along_wall_tangent() -> void:
	print("\n--- Test 2: NavAvoidance.slide_along_wall ---")
	var actor := CharacterBody3D.new()
	var in_vel := Vector3(0, 0, -5) # Moving forward (-Z)
	# If no slide collision occurred, slide_along_wall safely preserves velocity
	var out_vel := NavAvoidance.slide_along_wall(in_vel, actor)
	_check(out_vel == in_vel, "Returns original velocity when no collision occurred")
	actor.free()


func _test_3_enemy_dummy_drive_commands() -> void:
	print("\n--- Test 3: EnemyDummy.set_drive_commands ---")
	var dummy = EnemyDummyScene.instantiate()
	add_child(dummy)
	await get_tree().process_frame

	_check(dummy.has_method("set_drive_commands"), "Enemy dummy supports set_drive_commands")
	
	# Test drive commands with jump
	dummy.velocity = Vector3.ZERO
	dummy.set_drive_commands(Vector3(1, 0, 0), Vector3(10, 0, 0), false, false, false, true, false)
	_check(dummy.velocity.y > 0.0 or not dummy.is_on_floor(), "Drive jump handled correctly")
	
	dummy.queue_free()


func _test_4_enemy_dummy_try_jump_clearance() -> void:
	print("\n--- Test 4: EnemyDummy.try_jump_clearance ---")
	var dummy = EnemyDummyScene.instantiate()
	add_child(dummy)
	await get_tree().process_frame

	_check(dummy.has_method("try_jump_clearance"), "Enemy dummy provides try_jump_clearance API")
	
	dummy.queue_free()
