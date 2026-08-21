extends Node

## Headless verification of the intermission "NO MOVEMENT LEFT" stuck bug:
##   1. Running out of MP clears blocked_intermission (the ambush-aftermath flag
##      that otherwise soft-locks the menu when the player can't move).
##   2. ESC while an event popup is open CLOSES the popup (EventUI handles the
##      pause key) instead of stacking the intermission menu on top.
##   3. ESC while the tree is paused does NOT open the intermission menu.
##   4. Once the popup is closed, ESC opens the intermission menu again.
## Run: godot --headless --path . res://tests/board_popup_intermission_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("POPUP_OK: " + name)
	else:
		_fails += 1
		printerr("POPUP_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.board.board_seed = 4242
	GlobalData.board.board_objective_intro_consumed = true
	GameManager.current_state = GameManager.State.BOARD

	var board = load("res://scenes/board/game_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	var event_ui: Node = board.get_node_or_null("EventUI")
	var intermission: Node = board.get_node_or_null("IntermissionUI")
	_check(event_ui != null, "board hosts the EventUI popup")
	_check(intermission != null, "board hosts the IntermissionUI menu")
	if event_ui == null or intermission == null:
		get_tree().quit(1)
		return

	await _verify_no_movement_clears_block(board, event_ui)
	await _verify_esc_closes_popup(board, event_ui, intermission)
	await _verify_esc_after_popup_opens_menu(intermission)

	print("BOARD_POPUP_INTERMISSION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# Standing on a tile with 0 MP and clicking the neighbor fires the NO MOVEMENT
# LEFT event AND must clear blocked_intermission — otherwise the menu stays
# locked forever and the player soft-locks (the reported bug).
func _verify_no_movement_clears_block(board: Node, event_ui: Node) -> void:
	GlobalData.narrative.blocked_intermission = true
	GlobalData.board.board_mp = 0
	# Walk to a plain empty tile first so the player actually stands somewhere.
	board.current_pos = Vector2i(0, 0)
	GlobalData.board.current_tile = Vector2i(0, 0)

	# GDScript lambdas capture primitives by value — use a Dictionary so the
	# listener can flag the event back out.
	var flag := {"fired": false}
	var listener := func(_e: Dictionary) -> void:
		flag["fired"] = true
	EventBus.event_triggered.connect(listener)
	var target := Vector2i(-1, -1)
	for d: Vector2i in board.DIRS:
		var t: Vector2i = board.current_pos + d
		if board.nodes_dict.has(t) and BoardConfig.is_passable(str(board.nodes_dict[t].get_meta("terrain", "plain"))):
			target = t
			break
	_check(target != Vector2i(-1, -1), "found an adjacent walkable tile to test")
	if target == Vector2i(-1, -1):
		EventBus.event_triggered.disconnect(listener)
		return
	board._try_step(target)
	await get_tree().process_frame
	_check(bool(flag["fired"]), "clicking with 0 MP fires the NO MOVEMENT LEFT event")
	_check(GlobalData.narrative.blocked_intermission == false, "NO MOVEMENT LEFT clears blocked_intermission")
	EventBus.event_triggered.disconnect(listener)
	# The event popup may be open now (it pauses the tree) — close it.
	if event_ui.visible:
		event_ui._on_continue_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
	_check(not get_tree().paused, "tree is unpaused after closing the event popup")


# While the event popup is open (tree paused), ESC must close the popup and NOT
# open the intermission menu on top of it.
func _verify_esc_closes_popup(board: Node, event_ui: Node, intermission: Node) -> void:
	EventBus.event_triggered.emit({
		"name": "TEST POPUP",
		"effect": "none",
		"amount": 0,
		"desc": "Integration popup for ESC handling.",
	})
	await get_tree().process_frame
	_check(event_ui.visible, "event popup opens over the board")
	_check(get_tree().paused, "tree pauses while the popup is open")

	# Pressing ESC while paused must NOT open the intermission menu.
	intermission.visible = false
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	intermission._input(esc)
	await get_tree().process_frame
	_check(not intermission.visible, "ESC while a popup is open does NOT stack the intermission menu")

	# ESC closes the popup itself.
	event_ui._input(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not event_ui.visible, "ESC closes the event popup")
	_check(not get_tree().paused, "closing the popup with ESC unpauses the tree")


# With no popup up, ESC opens the intermission menu as usual.
func _verify_esc_after_popup_opens_menu(intermission: Node) -> void:
	intermission.visible = false
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	intermission._input(esc)
	await get_tree().process_frame
	_check(intermission.visible, "ESC opens the intermission menu after the popup is gone")
	intermission.visible = false
