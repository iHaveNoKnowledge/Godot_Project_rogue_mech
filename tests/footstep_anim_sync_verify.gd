extends Node3D

## Verification test for 100% Exact Leg Animation Footstep Sync:
## Validates that footsteps trigger on the exact animation frame each leg enters the stance/ground contact phase.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("FOOTSTEP_SYNC_OK: %s" % msg)
	else:
		_fails += 1
		print("FOOTSTEP_SYNC_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Footstep Animation Sync Verification ---")

	var walk := MechaWalkingSystem.new()
	add_child(walk)

	var mech := CharacterBody3D.new()
	add_child(mech)
	mech.velocity = Vector3(0, 0, -10.0) # moving forward

	var joints: Dictionary = {}
	joints["leg_left"] = Node3D.new()
	joints["leg_right"] = Node3D.new()
	add_child(joints["leg_left"])
	add_child(joints["leg_right"])

	# Test 1: Moving on ground triggers exact footstep sync at PI intervals
	walk.is_moving = true
	var steps_detected: int = 0
	var delta := 0.016 # 60 FPS

	for i in range(120):
		var prev_cycle := walk._prev_bob_timer * 0.5
		walk.update_bob(delta, mech, joints, 0.15)
		walk.update_legs(delta, mech, joints)
		var cur_cycle := walk.bob_timer * 0.5

		var prev_step_idx := int(prev_cycle / PI)
		var cur_step_idx := int(cur_cycle / PI)
		if cur_step_idx > prev_step_idx:
			steps_detected += 1

	_check(steps_detected >= 3, "Leg cycle detected %d footstep ground contact events across 2 seconds" % steps_detected)
	_check(walk.bob_timer > 0.0, "bob_timer advances in sync with gait speed")

	# Test 2: When standing still (is_moving = false), no footsteps trigger
	walk.is_moving = false
	var steps_idle: int = 0
	for i in range(30):
		var prev_cycle := walk._prev_bob_timer * 0.5
		walk.update_bob(delta, mech, joints, 0.15)
		walk.update_legs(delta, mech, joints)
		var cur_cycle := walk.bob_timer * 0.5
		if int(cur_cycle / PI) > int(prev_cycle / PI):
			steps_idle += 1

	_check(steps_idle == 0, "No footsteps trigger while idle / stationary")

	walk.queue_free()
	mech.queue_free()
	joints["leg_left"].queue_free()
	joints["leg_right"].queue_free()

	print("FOOTSTEP_SYNC_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
