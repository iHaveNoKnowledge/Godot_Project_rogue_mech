extends Node

## Headless verification of the dead-end "clear the path" choice:
##   - a dead end offers a CHOICE event (clear the rubble for MP + skip a day,
##     or turn back) and hides the clear option when the MP pool is empty
##   - the clear choice spends MP up front and records the tile to open
##   - clearing converts the dead-end tile to ordinary ground and advances the
##     day (MP refills, patrols move)
## Run: godot --headless --path . res://tests/board_dead_end_verify.tscn

var _fails: int = 0
var _checks: int = 0
var _last_event: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	GlobalData.reset_run_data()
	GlobalData.current_sector = 1
	GlobalData.board_seed = 777
	GlobalData.board_objective_intro_consumed = true
	GameManager.current_state = GameManager.State.BOARD
	EventBus.event_triggered.connect(_on_event)

	var board = load("res://scenes/board/game_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	await _verify_choice_event(board)
	_verify_effect()
	_verify_clear_and_day_skip(board)

	print("BOARD_DEAD_END_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _on_event(event: Dictionary) -> void:
	_last_event = event


func _verify_choice_event(board: Node) -> void:
	var cost: int = board._dead_end_clear_cost()
	_check(cost >= 2, "clear cost is at least 2 MP")

	# With a full MP pool the dead end offers both choices.
	GlobalData.board_mp = GlobalData.board_mp_max
	board.current_pos = Vector2i(1, 0)
	_last_event = {}
	board._trigger_dead_end_event()
	get_tree().paused = false
	_check(_last_event.get("effect") == "choice", "dead end emits a choice event")
	var choices: Array = _last_event.get("params", {}).get("choices", [])
	_check(choices.size() == 2, "affordable dead end offers both choices")
	var clear_label := ""
	for c in choices:
		if str(c.get("effect", "")) == "dead_end_clear":
			clear_label = str(c.get("label", ""))
	_check(clear_label.contains("%d MP" % cost), "clear choice shows the MP cost")

	# With an empty MP pool the clear option disappears (can't afford it).
	GlobalData.board_mp = 0
	_last_event = {}
	board._trigger_dead_end_event()
	get_tree().paused = false
	var cheap_choices: Array = _last_event.get("params", {}).get("choices", [])
	var can_clear := false
	for c in cheap_choices:
		if str(c.get("effect", "")) == "dead_end_clear":
			can_clear = true
	_check(not can_clear, "unaffordable dead end hides the clear option")


func _verify_effect() -> void:
	GlobalData.board_mp = GlobalData.board_mp_max
	GlobalData.pending_tile_clear = Vector2i(-1, -1)
	var forced := ThemeSystem.apply_event_effect({
		"effect": "dead_end_clear",
		"amount": 3,
		"params": {"pos": {"x": 2, "y": 2}},
	})
	_check(not forced, "dead_end_clear does not force a scene transition")
	_check(GlobalData.board_mp == GlobalData.board_mp_max - 3, "clear choice spends the MP up front")
	_check(GlobalData.pending_tile_clear == Vector2i(2, 2), "clear choice records the tile to open")


func _verify_clear_and_day_skip(board: Node) -> void:
	# Find (or force) a dead-end tile and mark it as the one to clear.
	var clear_pos := Vector2i(-1, -1)
	for key in board.nodes_dict:
		if str(board.nodes_dict[key].get_meta("tile_type", "empty")) == "dead_end":
			clear_pos = key
			break
	if clear_pos == Vector2i(-1, -1):
		for key in board.nodes_dict:
			if str(board.nodes_dict[key].get_meta("tile_type", "empty")) == "empty":
				clear_pos = key
				board.nodes_dict[key].set_meta("tile_type", "dead_end")
				break
	_check(clear_pos != Vector2i(-1, -1), "found a dead-end tile to clear")

	# The player stands on the start tile (patrols can never step there, so the
	# skipped day cannot ambush the convoy mid-test).
	board.current_pos = Vector2i(0, 0)
	var day_before: int = GlobalData.board_day
	GlobalData.board_mp = 0
	GlobalData.pending_tile_clear = clear_pos
	board._apply_pending_tile_clear()
	get_tree().paused = false
	_check(str(board.nodes_dict[clear_pos].get_meta("tile_type", "empty")) == "empty", "cleared dead-end tile becomes ordinary ground")
	_check(GlobalData.board_day == day_before + 1, "clearing the path skips a day")
	_check(GlobalData.board_mp == GlobalData.board_mp_max, "the skipped day refills MP")
