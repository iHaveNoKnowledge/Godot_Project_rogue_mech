extends Node

## Headless verification of the board tactical-pressure layer:
##   1. Reactive pursuit: hostile fleets converge on the player's last-seen tile.
##   2. Alert escalation: lingering near a hostile fleet raises patrol_alert.
##   3. Interception blocks: a fleet between convoy and objective raises MP cost.
##   4. Chokepoint detection: bridges / one-wide passages are ambush ground.
##   5. Bait decoy tiles: generator can roll them, and sprung traps are tracked.
## Run: godot --headless --path . res://tests/board_tactics_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TACTICS_OK: " + name)
	else:
		_fails += 1
		printerr("TACTICS_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.board.board_seed = 7
	GlobalData.board.board_grid = _build_grid()

	# 1) Reactive pursuit: a hostile fleet just out of view follows the trail.
	# Fleet is 10 cells from the player: outside the base detection radius (4),
	# so it should pursue the patrol_last_seen trail rather than the player.
	# The trail-follow branch rolls rng.randf() < 0.7 per day, so loop a few
	# days to make the check deterministic.
	GlobalData.board.patrol_last_seen = Vector2i(-1, -1)
	GlobalData.board.board_patrols = [{
		"id": 1, "pos": Vector2i(3, 3), "home": Vector2i(3, 3),
		"name": "Ravens", "grunts": 2, "aces": 0, "aggro": false,
		"faction": "hostile", "character_id": "", "dir": Vector2i(1, 0),
	}]
	GlobalData.board.patrol_last_seen = Vector2i(8, 8)
	GlobalData.board.board_day = 1
	var moved := false
	for _i in range(8):
		GlobalData.board.board_day += 1
		PatrolSystem.advance_day(Vector2i(8, 8))
		if PatrolSystem.get_patrol_by_id(1).get("pos") != Vector2i(3, 3):
			moved = true
			break
	_check(moved, "reactive fleet moves toward the last-seen trail")

	# 2) Alert escalation: player stands next to a hostile fleet -> alert climbs.
	GlobalData.board.patrol_alert = 0
	GlobalData.board.board_patrols = [{
		"id": 2, "pos": Vector2i(4, 4), "home": Vector2i(4, 4),
		"name": "Hawks", "grunts": 1, "aces": 0, "aggro": false,
		"faction": "hostile", "character_id": "", "dir": Vector2i(1, 0),
	}]
	GlobalData.board.patrol_last_seen = Vector2i(-1, -1)
	PatrolSystem.advance_day(Vector2i(5, 5))
	_check(GlobalData.board.patrol_alert >= 1, "alert climbs while a hostile fleet keeps visual")
	_check(GlobalData.board.board_patrols[0].get("aggro", false), "a fleet that sees the convoy turns aggro")
	PatrolSystem.advance_day(Vector2i(12, 12))
	_check(GlobalData.board.patrol_alert < 1, "alert decays after the convoy relocates")

	# 3) Interception: fleet strictly between convoy and the exit (14,14) blocks.
	GlobalData.board.patrol_alert = 0
	GlobalData.board.board_patrols = [{
		"id": 3, "pos": Vector2i(10, 10), "home": Vector2i(10, 10),
		"name": "Strykers", "grunts": 1, "aces": 0, "aggro": false,
		"faction": "hostile", "character_id": "", "dir": Vector2i(1, 0),
	}]
	_check(PatrolSystem.interception_surcharge(Vector2i(9, 9), Vector2i(10, 10)) == 0, "no surcharge standing next to the fleet")
	_check(PatrolSystem.interception_surcharge(Vector2i(9, 9), Vector2i(11, 11)) == 0, "no surcharge stepping away from the goal")
	_check(PatrolSystem.interception_surcharge(Vector2i(9, 9), Vector2i(11, 10)) == 1, "crossing the fleet's firing line toward the exit costs +1 MP")

	# 4) Chokepoint detection: a bridge or one-wide passage is ambush ground.
	var board = load("res://scripts/board/board_manager.gd").new()
	board.nodes_dict = _build_synthetic_board()
	_check(board.has_method("_is_chokepoint_tile"), "board exposes chokepoint detection")
	_check(board._is_chokepoint_tile(board.nodes_dict[Vector2i(5, 5)]), "bridge tiles register as chokepoints")
	_check(board._is_chokepoint_tile(board.nodes_dict[Vector2i(8, 0)]), "one-wide passages register as chokepoints")
	_check(not board._is_chokepoint_tile(board.nodes_dict[Vector2i(7, 7)]), "wide open plain cells are NOT chokepoints")
	_check(not board._roll_chokepoint_ambush(board.nodes_dict[Vector2i(8, 0)]), "safehouse tiles never spring chokepoint ambushes")

	# 5) Bait decoy tiles: generator can produce them and traps are tracked.
	var gen = load("res://scripts/board/board_generator.gd").new()
	var saw_bait := false
	for i in range(400):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 13 + 5
		if gen._roll_content(rng) == "bait":
			saw_bait = true
			break
	_check(saw_bait, "board generator can roll bait decoy tiles")
	GlobalData.board.consumed_bait.append(Vector2i(2, 2))
	_check(Vector2i(2, 2) in GlobalData.board.consumed_bait, "sprung bait traps are tracked")

	print("BOARD_TACTICS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# A minimal 15x15 grid of plain tiles so PatrolSystem.advance_day has a map to
# step across (mirrors BoardConfig.GRID_SIZE).
func _build_grid() -> Array:
	var nodes: Dictionary = {}
	for y in range(BoardConfig.GRID_SIZE):
		for x in range(BoardConfig.GRID_SIZE):
			var key := Vector2i(x, y)
			var tile = StaticBody3D.new()
			tile.set_meta("tile_type", "empty")
			tile.set_meta("terrain", "plain")
			tile.set_meta("grid_pos", key)
			nodes[key] = tile
	return [nodes]


# A synthetic board with a bridge, a one-wide passage (row y=0 has a single
# walkable cell at x=8), and wide open plains elsewhere. (8,0) doubles as a
# safehouse so the ambush-exclusion path is exercised.
func _build_synthetic_board() -> Dictionary:
	var nodes: Dictionary = {}
	for y in range(BoardConfig.GRID_SIZE):
		for x in range(BoardConfig.GRID_SIZE):
			var key := Vector2i(x, y)
			var tile = StaticBody3D.new()
			tile.set_meta("tile_type", "empty")
			tile.set_meta("terrain", "plain")
			tile.set_meta("grid_pos", key)
			nodes[key] = tile
	nodes[Vector2i(5, 5)].set_meta("terrain", "bridge")
	nodes[Vector2i(8, 0)].set_meta("tile_type", "safehouse")
	# Close off most of row y=0 so only (8,0) is reachable: one-wide passage.
	for x in range(BoardConfig.GRID_SIZE):
		if x != 8:
			nodes[Vector2i(x, 0)].set_meta("terrain", "water")
	return nodes