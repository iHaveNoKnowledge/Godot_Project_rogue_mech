extends Node3D

## Dedicated windowed test for Mecha Player Movement:
## Verifies the complete in-engine player input path using synthesized InputEventKey:
## InputEventKey -> InputMap -> Input.get_vector() -> player authority and mouse-capture guard -> camera-relative movement -> CharacterBody3D displacement.

var _checks: int = 0
var _fails: int = 0
var _failure_reasons: Array[String] = []

var _prev_combat_muted: bool = false
var _audio_muted_changed: bool = false
var _spawned_nodes: Array[Node] = []
var _pressed_keys: Array[Key] = []


func _check(condition: bool, msg: String, failure_reason: String = "") -> void:
	_checks += 1
	if condition:
		print("WINDOWED_MOVE_OK: %s" % msg)
	else:
		_fails += 1
		var err_msg := "WINDOWED_MOVE_FAIL: %s" % msg
		if failure_reason != "":
			err_msg += " (Reason: %s)" % failure_reason
			_failure_reasons.append(failure_reason)
		else:
			_failure_reasons.append(msg)
		print(err_msg)


func _inject_key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	if pressed:
		if not _pressed_keys.has(key):
			_pressed_keys.append(key)
	else:
		_pressed_keys.erase(key)


func _release_all_keys() -> void:
	for key in _pressed_keys.duplicate():
		_inject_key(key, false)
	_pressed_keys.clear()
	for key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.keycode = key
		ev.pressed = false
		Input.parse_input_event(ev)
	Input.flush_buffered_events()
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _cleanup_and_quit(exit_code: int) -> void:
	# 1. Release all keys and actions
	_release_all_keys()

	# 2. Restore mouse mode to VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 3. Clean up spawned nodes
	for node in _spawned_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	_spawned_nodes.clear()

	# Await process frame to allow queue_free to process
	await get_tree().process_frame

	# 4. Restore audio mute state
	if _audio_muted_changed and AudioManager:
		AudioManager.combat_muted = _prev_combat_muted

	# 5. Print summary
	print("MECHA_MOVEMENT_WINDOWED_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _failure_reasons.size() > 0:
		print("MECHA_MOVEMENT_WINDOWED_VERIFY FAILURES: %s" % ", ".join(_failure_reasons))

	get_tree().quit(exit_code)


func _ready() -> void:
	print("--- Starting Mecha Movement Windowed Verification ---")

	# Section 5.A: Windowed-only guard
	if DisplayServer.get_name() == "headless":
		print("WINDOWED_TEST_BLOCKED_HEADLESS: This test requires a windowed display server.")
		get_tree().quit(2)
		return

	# Section 5.B: Audio suppression state preservation
	_prev_combat_muted = AudioManager.combat_muted if AudioManager else false
	if AudioManager:
		AudioManager.combat_muted = true
	_audio_muted_changed = true

	# Section 5.C: Floor setup
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_col.shape = box
	floor_body.add_child(floor_col)
	floor_body.position.y = -0.5
	add_child(floor_body)
	_spawned_nodes.append(floor_body)

	# Camera setup looking toward -Z
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 8)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()
	_spawned_nodes.append(cam)

	# Mecha setup
	var mecha_script = load("res://scripts/mecha/mecha_controller.gd")
	var mecha: CharacterBody3D = CharacterBody3D.new()
	mecha.set_script(mecha_script)
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 2.4
	col.shape = capsule
	col.position.y = 1.2
	mecha.add_child(col)
	mecha.is_player_driven = false
	add_child(mecha)
	mecha.global_position = Vector3(0, 0, 0)
	_spawned_nodes.append(mecha)

	# Establish player authority
	mecha.claim_player_authority()

	# Initial settling frames for physics
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(mecha.is_player_driven == true, "Mecha is_player_driven is true after claim_player_authority()")
	_check(mecha_script.active_player == mecha, "MechaController.active_player matches mecha instance")
	_check(not bool(mecha.get_meta("is_tuning_in_hangar", false)), "Mecha is not in hangar tuning mode")

	# Section 5.D: Window focus and mouse capture
	var win := get_window()
	if win:
		win.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var capture_ok: bool = false
	for frame_idx in range(10):
		await get_tree().physics_frame
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			capture_ok = true
			break

	_check(capture_ok, "Mouse mode captured successfully", "FOCUS_ACQUISITION_TIMEOUT" if not capture_ok else "")
	if not capture_ok:
		await _cleanup_and_quit(1)
		return

	# Section 5.E: Phase 1 — Forward Movement (-Z direction via synthesized KEY_W)
	var forward_start_pos: Vector3 = mecha.global_position
	_inject_key(KEY_W, true)

	for i in range(30):
		await get_tree().physics_frame

	_inject_key(KEY_W, false)
	await get_tree().physics_frame

	var forward_disp := forward_start_pos.distance_to(mecha.global_position)
	_check(forward_disp > 1.0, "Player walked forward via KEY_W (moved %.2fm > 1.0m)" % forward_disp)
	_check(mecha.global_position.z < forward_start_pos.z, "Player moved in forward -Z direction (z=%.2f < %.2f)" % [mecha.global_position.z, forward_start_pos.z])
	_check(mecha.is_player_driven == true, "Mecha remained player-driven during forward movement")
	_check(mecha_script.active_player == mecha, "MechaController.active_player maintained during forward movement")
	_check(mecha.cmd_move_vector == Vector2.ZERO, "Decoupled cmd_move_vector was never set during forward movement")

	# Settling frames between phases
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Section 5.E: Phase 2 — Right Strafing Movement (+X direction via synthesized KEY_D)
	var strafe_start_pos: Vector3 = mecha.global_position
	_inject_key(KEY_D, true)

	for i in range(30):
		await get_tree().physics_frame

	_inject_key(KEY_D, false)
	await get_tree().physics_frame

	var strafe_disp := strafe_start_pos.distance_to(mecha.global_position)
	_check(strafe_disp > 1.0, "Player strafed right via KEY_D (moved %.2fm > 1.0m)" % strafe_disp)
	_check(mecha.global_position.x > strafe_start_pos.x, "Player moved in right +X direction (x=%.2f > %.2f)" % [mecha.global_position.x, strafe_start_pos.x])
	_check(mecha.is_player_driven == true, "Mecha remained player-driven during strafe movement")
	_check(mecha_script.active_player == mecha, "MechaController.active_player maintained during strafe movement")
	_check(mecha.cmd_move_vector == Vector2.ZERO, "Decoupled cmd_move_vector was never set during strafe movement")

	# Section 5.B: Full cleanup and exit
	var final_exit_code: int = 1 if _fails > 0 else 0
	await _cleanup_and_quit(final_exit_code)
