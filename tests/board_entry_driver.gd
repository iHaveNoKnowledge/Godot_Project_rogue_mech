extends Node

## Board-entry driver (lives on /root, survives the scene swap). Enters the real
## board, dismisses the day-1 objective popup, clicks "Move on Board", then
## walks one tile through the REAL move_to_tile() gate.

var _fails := 0
var _checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func run() -> void:
	GlobalData.reset_run_data()
	HangarManager.ensure_roster()
	GlobalData.save_run()

	GameManager.enter_board()
	var board: Node = await _wait_for_board()
	_check(board != null, "board scene loads on enter_board")
	if board == null:
		_finish()
		return

	var intermission = board.get_node_or_null("IntermissionUI")
	var event_ui = board.get_node_or_null("EventUI")
	_check(intermission != null, "IntermissionUI node exists")
	_check(intermission.has_method("_on_move_pressed"), "intermission script parsed (has Move handler)")
	_check(event_ui != null, "EventUI node exists")
	await get_tree().process_frame
	await get_tree().process_frame

	# Day-1 objective popup is up and pauses the tree; close it like a player.
	if event_ui != null and event_ui.visible:
		event_ui._on_continue_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
	_check(not get_tree().paused, "tree unpauses after the day-1 popup closes")

	# The intermission menu is visible by design on entry; "Move on Board" must
	# dismiss it so movement is possible.
	_check(intermission.visible, "intermission menu is up on entry (by design)")
	intermission._on_move_pressed()
	await get_tree().process_frame
	_check(not intermission.visible, "Move on Board dismisses the intermission menu")

	# Walk one adjacent walkable tile through the real gate.
	var target := Vector2i(-1, -1)
	for d: Vector2i in board.DIRS:
		var t: Vector2i = board.current_pos + d
		if board.nodes_dict.has(t):
			var tile = board.nodes_dict[t]
			if BoardConfig.is_passable(str(tile.get_meta("terrain", "plain"))):
				target = t
				break
	_check(target != Vector2i(-1, -1), "an adjacent walkable tile exists")
	if target != Vector2i(-1, -1):
		_check(board.move_to_tile(target), "move_to_tile() succeeds through the real gate")

	# Intermission BGM is playing on the board; stop it and wait out the full
	# 1s fade so no MP3 stream is decoding when the audio thread tears down.
	AudioManager.stop_music()
	for i in range(90):
		await get_tree().process_frame

	print("BOARD_ENTRY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	queue_free()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("ENTRY_OK: " + label)
	else:
		_fails += 1
		printerr("ENTRY_FAIL: " + label)


func _finish() -> void:
	get_tree().quit(1 if _fails > 0 else 0)


func _wait_for_board(max_frames: int = 300) -> Node:
	for i in range(max_frames):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("move_to_tile"):
			return scene
	return null