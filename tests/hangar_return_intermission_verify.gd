extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	print("=== Running Hangar Return & Intermission Flow Verification ===")
	_test_intermission_opens_on_board_load()
	_test_move_on_board_and_esc_toggle()
	_test_hangar_transition_and_return()

	print("\n=== Test Results: %d Passed, %d Failed ===" % [passed, failed])
	if failed == 0:
		print("ALL_HANGAR_INTERMISSION_TESTS_PASSED")
	else:
		push_error("Some tests failed!")
	get_tree().quit(0 if failed == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[PASS] %s" % msg)
	else:
		failed += 1
		print("[FAIL] %s" % msg)
		push_error("Assertion failed: %s" % msg)


func _test_intermission_opens_on_board_load() -> void:
	GlobalData.reset_run_data()
	GameManager.current_state = GameManager.State.BOARD

	var intermission_scene = load("res://scenes/ui/intermission_ui.tscn")
	var intermission = intermission_scene.instantiate()
	add_child(intermission)

	_assert(intermission.visible == true, "Intermission UI starts visible when loading into Board")
	_assert(intermission.root_control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "root_control has MOUSE_FILTER_IGNORE so transparent areas don't block 3D clicks")

	intermission.queue_free()


func _test_move_on_board_and_esc_toggle() -> void:
	GlobalData.reset_run_data()
	GameManager.current_state = GameManager.State.BOARD

	var intermission_scene = load("res://scenes/ui/intermission_ui.tscn")
	var intermission = intermission_scene.instantiate()
	add_child(intermission)

	# 1. Clicking "Move on Board" hides the intermission
	intermission._on_move_pressed()
	_assert(intermission.visible == false, "Clicking 'Move on Board' sets visible = false")

	# 2. Pressing ESC toggles intermission back on
	var ev_esc = InputEventKey.new()
	ev_esc.keycode = KEY_ESCAPE
	ev_esc.physical_keycode = KEY_ESCAPE
	ev_esc.pressed = true
	intermission._input(ev_esc)
	_assert(intermission.visible == true, "Pressing ESC toggles intermission menu back ON")

	# 3. Pressing ESC again toggles intermission off
	intermission._input(ev_esc)
	_assert(intermission.visible == false, "Pressing ESC again toggles intermission menu OFF")

	intermission.queue_free()


func _test_hangar_transition_and_return() -> void:
	GlobalData.reset_run_data()
	GameManager.current_state = GameManager.State.BOARD

	var intermission_scene = load("res://scenes/ui/intermission_ui.tscn")
	var intermission = intermission_scene.instantiate()
	add_child(intermission)

	# Transition to Hangar
	EventBus.game_state_changed.emit("BOARD", "HANGAR")
	_assert(intermission.visible == false, "Intermission hides when entering Hangar")

	# Transition back to Board
	EventBus.game_state_changed.emit("HANGAR", "BOARD")
	_assert(intermission.visible == true, "Intermission reappears when returning to Board from Hangar")

	intermission.queue_free()
