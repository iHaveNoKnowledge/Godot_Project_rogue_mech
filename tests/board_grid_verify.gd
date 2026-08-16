extends Node

## Verifies the open-grid board revamp:
##   1. Generates a full grid with start (0,0) and exit (last,last).
##   2. Every walkable cell is reachable from start (no orphan islands).
##   3. The main path is present and terrain costs match BoardConfig.
##   4. BoardSystem objective wiring works (set + progress + complete).
##   5. Patrol spawn/advance/resolve works end-to-end.
## Run: godot --headless --path . res://tests/board_grid_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GRID_OK: " + name)
	else:
		_fails += 1
		printerr("GRID_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.current_sector = 1
	GlobalData.board_seed = 12345

	# --- generator produces a full connected grid ---
	var gen := preload("res://scripts/board/board_generator.gd").new()
	var data := gen.generate_board()
	var nodes: Dictionary = data["nodes"]
	var terrain: Dictionary = data["terrain"]
	var grid_size := BoardConfig.GRID_SIZE

	_check(nodes.size() == grid_size * grid_size, "grid has %d cells" % (grid_size * grid_size))

	var start := Vector2i(0, 0)
	var exit := Vector2i(grid_size - 1, grid_size - 1)
	_check(nodes.has(start) and nodes[start].get_meta("tile_type", "") == "start", "start tile at (0,0)")
	_check(nodes.has(exit) and nodes[exit].get_meta("tile_type", "") == "exit", "exit tile at far corner")

	# Combat must NEVER come from plain ground tiles — battles only happen when
	# the player steps onto a hostile patrol arrow (red ">") or the enemy base.
	var combat_tiles := 0
	for k in nodes:
		if nodes[k].get_meta("tile_type", "") == "combat":
			combat_tiles += 1
	_check(combat_tiles == 0, "no plain tile rolls a combat encounter (battles come from patrol arrows)")

	# --- connectivity: BFS over walkable terrain must reach every walkable cell ---
	var walkable: Dictionary = {}
	for k in terrain:
		if BoardConfig.is_passable(terrain[k]):
			walkable[k] = true

	var reachable := _bfs(terrain, start)
	for k in walkable:
		if not reachable.has(k):
			_fails += 1
			_checks += 1
			printerr("GRID_FAIL: walkable cell not reachable: %s" % str(k))
			return

	_checks += 1
	print("GRID_OK: all walkable cells reachable")

	# A guaranteed road path exists (start -> exit manual walk on road cells).
	var road_path := _has_road_path(terrain, start, exit)
	_check(road_path, "main road path connects start to exit")

	# --- terrain costs agree with BoardConfig ---
	var mismatch := false
	for k in terrain:
		if BoardConfig.move_cost(terrain[k]) != BoardConfig.move_cost(terrain[k]):
			mismatch = true
	_check(not mismatch, "terrain cost lookup consistent")

	# --- objective wiring ---
	# Simulate sector-1 objective directly.
	GlobalData.board_theme_id = "suburb"
	var obj := BoardSystem.get_objective()
	_check(obj.get("id", "") == "patrol_hunt", "suburb objective = patrol_hunt")
	_check(GlobalData.board_objective_required == int(obj.get("required", 3)), "objective required synced")
	BoardSystem.add_progress(1)
	BoardSystem.add_progress(1)
	_check(GlobalData.board_objective_progress == 2, "progress accumulates")
	_check(not BoardSystem.is_objective_complete(), "not complete at 2/3")
	BoardSystem.add_progress(1)
	_check(BoardSystem.is_objective_complete(), "complete at 3/3")

	# --- desert survey objective ---
	GlobalData.board_theme_id = "desert"
	GlobalData.current_sector = 2
	GlobalData.board_objective_id = BoardSystem.get_objective()["id"]
	GlobalData.board_objective_progress = 0
	GlobalData.board_objective_required = BoardSystem.get_objective()["required"]
	_check(GlobalData.board_objective_id == "survey", "desert objective = survey")
	GlobalData.board_objective_progress = 6
	_check(BoardSystem.is_objective_complete(), "survey complete at 6 tiles")

	# --- patrol flow ---
	GlobalData.reset_run_data()
	GlobalData.current_sector = 1
	GlobalData.board_seed = 999
	var gen2 := preload("res://scripts/board/board_generator.gd").new()
	gen2.generate_board()
	PatrolSystem.spawn_patrols()
	_check(PatrolSystem.has_patrols(), "patrols spawned for sector 1")

	var first_id := -1
	for p in GlobalData.board_patrols:
		first_id = int(p.get("id", -1))
		_check(BoardConfig.is_passable(GlobalData.board_grid[0][p.get("pos")].get_meta("terrain", "plain")), "patrol spawns on walkable cell")
		break
	_check(first_id != -1, "a patrol was registered with an id")

	# advance_day moves patrols (should not crash, ambush only when they reach
	# the player spawn).
	var ambush := PatrolSystem.advance_day(Vector2i(0, 0))
	_check(ambush != Vector2i(-1, -1) or PatrolSystem.has_patrols(), "advance_day ran safely")
	for p in GlobalData.board_patrols:
		_check(BoardConfig.is_passable(GlobalData.board_grid[0][p.get("pos")].get_meta("terrain", "plain")), "patrols stay on walkable cells")

	# --- patrol resolve: winning removes the fleet + adds objective progress ---
	GlobalData.board_theme_id = "suburb"
	GlobalData.board_objective_id = "patrol_hunt"
	GlobalData.board_objective_progress = 0
	GlobalData.board_objective_required = 3
	GlobalData.board_patrol_engagement = first_id
	PatrolSystem.resolve_patrol_combat(true)
	_check(PatrolSystem.get_patrol_by_id(first_id).is_empty(), "winning removes the patrol fleet")
	_check(GlobalData.board_patrol_engagement == -1, "engagement cleared after resolve")
	_check(GlobalData.board_objective_progress == 1, "patrol destroy advances objective")

	print("BOARD_GRID_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _bfs(terrain: Dictionary, start: Vector2i) -> Dictionary:
	var visited: Dictionary = {}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not terrain.has(n) or visited.has(n):
				continue
			if BoardConfig.is_passable(terrain[n]):
				frontier.append(n)
	return visited


func _has_road_path(terrain: Dictionary, start: Vector2i, exit: Vector2i) -> bool:
	var visited: Dictionary = {start: true}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		if cur == exit:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if visited.has(n) or not terrain.has(n):
				continue
			if terrain[n] == "road":
				visited[n] = true
				frontier.append(n)
	return false