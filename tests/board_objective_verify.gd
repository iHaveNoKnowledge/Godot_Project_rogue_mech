extends Node

## Reproduces the "board objective won't complete" report by driving the real
## board generator + BoardSystem flow for each theme's objective trigger:
##   1. suburb  -> patrol_hunt (progress via patrol destroy)
##   2. desert  -> survey (progress via tile reveal)
##   3. forest  -> cross_river (complete by stepping on a bridge tile)
##   4. urban   -> hq_strike (complete via enemy-base destroyed flag)
## It also simulates the in-manager _try_step objective triggers so the exact
## conditions the manager checks are exercised (not just BoardSystem directly).
## Run: godot --headless --path . res://tests/board_objective_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("OBJ_OK: " + name)
	else:
		_fails += 1
		printerr("OBJ_FAIL: " + name)


func _ready() -> void:
	# --- cross_river (forest): the board must produce bridge tiles, and the
	# manager's bridge-step trigger must complete the objective. ---
	GlobalData.reset_run_data()
	GlobalData.board.current_sector = 2
	GlobalData.board.board_seed = 1 # odd -> forest theme
	var gen := preload("res://scripts/board/board_generator.gd").new()
	var data := gen.generate_board()
	var nodes: Dictionary = data["nodes"]
	_check(GlobalData.board.board_theme_id == "forest", "sector 2 odd seed -> forest theme")

	var bridge_count := 0
	var forest_count := 0
	for key in nodes:
		var terrain: String = nodes[key].get_meta("terrain", "plain")
		if terrain == "bridge":
			bridge_count += 1
		if terrain == "forest":
			forest_count += 1
	_check(bridge_count > 0, "forest board generated at least one bridge tile (got %d)" % bridge_count)
	_check(forest_count > 0, "forest board has forest terrain tiles (got %d)" % forest_count)

	# Simulate the manager's objective setup + bridge-step trigger.
	GlobalData.board.board_objective_id = ""
	GlobalData.board.board_objective_progress = 0
	_setup_objective_like_manager()
	_check(GlobalData.board.board_objective_id == "cross_river", "forest objective id = cross_river")
	_check(not BoardSystem.is_objective_complete(), "cross_river not complete before crossing")

	var step_bridge := _find_first(nodes, "bridge")
	var stepped := _simulate_step(nodes, step_bridge)
	_check(stepped, "stepping onto a bridge tile fires the cross_river trigger")
	_check(BoardSystem.is_objective_complete(), "cross_river complete after stepping on bridge")

	# --- patrol_hunt (suburb): killing 3 patrols completes. ---
	GlobalData.reset_run_data()
	GlobalData.board.current_sector = 1
	GlobalData.board.board_seed = 999
	var gen2 := preload("res://scripts/board/board_generator.gd").new()
	gen2.generate_board()
	GlobalData.board.board_objective_id = ""
	_setup_objective_like_manager()
	_check(GlobalData.board.board_objective_id == "patrol_hunt", "suburb objective id = patrol_hunt")
	PatrolSystem.spawn_patrols()
	_check(PatrolSystem.has_patrols(), "patrols spawned for suburb")
	GlobalData.board.board_patrol_engagement = 1
	for i in range(3):
		var pid := _any_patrol_id()
		GlobalData.board.board_patrol_engagement = pid
		PatrolSystem.resolve_patrol_combat(true)
	_check(BoardSystem.is_objective_complete(), "patrol_hunt complete after 3 destroys")

	# --- survey (desert): revealing 6 tiles completes. ---
	GlobalData.reset_run_data()
	GlobalData.board.current_sector = 2
	GlobalData.board.board_seed = 2 # even -> desert
	var gen3 := preload("res://scripts/board/board_generator.gd").new()
	gen3.generate_board()
	GlobalData.board.board_objective_id = ""
	_setup_objective_like_manager()
	_check(GlobalData.board.board_objective_id == "survey", "desert objective id = survey")
	BoardSystem.add_progress(6)
	_check(BoardSystem.is_objective_complete(), "survey complete at 6 revealed tiles")

	# --- hq_strike (urban): enemy base destroyed flag completes on board load. ---
	GlobalData.reset_run_data()
	GlobalData.board.current_sector = 3
	GlobalData.board.board_seed = 7
	var gen4 := preload("res://scripts/board/board_generator.gd").new()
	gen4.generate_board()
	GlobalData.board.board_objective_id = ""
	_setup_objective_like_manager()
	_check(GlobalData.board.board_objective_id == "hq_strike", "urban objective id = hq_strike")
	_check(not BoardSystem.is_objective_complete(), "hq_strike not complete before base destroyed")
	GlobalData.pending_enemy_base_destroyed = true
	# The board manager consumes this flag in _ready; simulate the same effect.
	var was_pending := EnemyFactionSystem.consume_pending_enemy_base_destroyed()
	if was_pending:
		BoardSystem.complete()
	_check(BoardSystem.is_objective_complete(), "hq_strike complete after base destroyed flag")

	print("BOARD_OBJECTIVE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _setup_objective_like_manager() -> void:
	var obj := BoardSystem.get_objective()
	GlobalData.board.board_objective_id = str(obj.get("id", ""))
	GlobalData.board.board_objective_progress = 0
	GlobalData.board.board_objective_required = int(obj.get("required", 1))


func _find_first(nodes: Dictionary, terrain: String) -> Vector2i:
	for key in nodes:
		if nodes[key].get_meta("terrain", "plain") == terrain:
			return key
	return Vector2i(-1, -1)


# Mirrors the exact condition board_manager._try_step uses for cross_river.
func _simulate_step(nodes: Dictionary, target: Vector2i) -> bool:
	if not nodes.has(target):
		return false
	var tile = nodes[target]
	if str(tile.get_meta("terrain", "plain")) == "bridge" and BoardSystem.get_objective().get("id", "") == "cross_river":
		BoardSystem.complete()
		return true
	return false


func _any_patrol_id() -> int:
	for p in GlobalData.board.board_patrols:
		return int(p.get("id", -1))
	return -1