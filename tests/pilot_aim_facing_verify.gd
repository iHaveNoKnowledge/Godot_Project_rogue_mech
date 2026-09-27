extends Node
## PILOT AIM FACING VERIFY - pilot body follows the camera on RMB aim and snaps
## to the shooting direction when firing (TPS aim contract).
##
## Covers:
##  1. yaw_facing() math faces -Z-forward correctly for 4 cardinal directions.
##  2. Holding fire_right (RMB ADS) turns the body toward the camera yaw.
##  3. Firing snaps the body to the camera shooting direction + spends a round.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)


func _ready() -> void:
	print("--- Running pilot_aim_facing_verify ---")
	_test_yaw_math()
	_test_rmb_aim_turns_body()
	_test_shoot_faces_direction()
	print("PILOT_AIM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _spawn_pilot() -> CharacterBody3D:
	GameManager.current_state = GameManager.State.EJECT
	GlobalData.reset_run_data()
	GlobalData.pilot.pilot_ammo["sidearm"] = 120
	var pilot_scene = preload("res://scenes/pilot/pilot.tscn")
	var pilot = pilot_scene.instantiate()
	add_child(pilot)
	return pilot


func _spawn_camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	return cam


func _test_yaw_math() -> void:
	print("Testing yaw_facing math...")
	var pilot_scene = preload("res://scenes/pilot/pilot.tscn")
	var pilot = pilot_scene.instantiate()
	add_child(pilot)
	_check(is_equal_approx(pilot.yaw_facing(Vector3(0, 0, -1)), 0.0), "faces -Z at yaw 0")
	_check(is_equal_approx(pilot.yaw_facing(Vector3(1, 0, 0)), -PI / 2.0), "faces +X at yaw -PI/2")
	_check(absf(angle_difference(pilot.yaw_facing(Vector3(0, 0, 1)), PI)) < 0.001, "faces +Z at yaw PI")
	_check(is_equal_approx(pilot.yaw_facing(Vector3(-1, 0, 0)), PI / 2.0), "faces -X at yaw PI/2")
	pilot.queue_free()


func _test_rmb_aim_turns_body() -> void:
	print("Testing RMB ADS turns body to camera yaw...")
	var pilot := _spawn_pilot()
	var cam := _spawn_camera()
	cam.rotation = Vector3(0, -PI / 2.0, 0) # look toward +X
	pilot.rotation.y = 0.8
	# NOTE: headless has no capturable mouse, so the mouse_mode gate in
	# _physics_process can't be satisfied here; drive the RMB handler directly.
	Input.action_press("fire_right")
	_check(pilot.is_aiming(), "fire_right reads as aiming")
	pilot._update_aim_facing(0.5)
	Input.action_release("fire_right")
	_check(not pilot.is_aiming(), "aim releases with RMB")
	_check(absf(pilot.rotation.y - (-PI / 2.0)) < 0.05, "body turned to camera yaw on RMB (yaw=%.3f)" % pilot.rotation.y)
	pilot.queue_free()
	cam.queue_free()


func _test_shoot_faces_direction() -> void:
	print("Testing firing snaps body to shooting direction...")
	var pilot := _spawn_pilot()
	var cam := _spawn_camera() # default looks -Z
	pilot.rotation.y = 0.8
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mag_before: int = pilot.get_current_magazine()
	_check(mag_before > 0, "magazine loaded for live-fire check (%d)" % mag_before)
	pilot._try_fire()
	_check(absf(pilot.rotation.y) < 0.05, "body snapped to camera forward on shoot (yaw=%.3f)" % pilot.rotation.y)
	_check(pilot.get_current_magazine() == mag_before - 1, "shot consumed one round")
	pilot.queue_free()
	cam.queue_free()
