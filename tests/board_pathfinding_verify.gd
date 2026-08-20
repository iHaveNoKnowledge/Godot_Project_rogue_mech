extends Node

## Verifies:
## 1. Multi-tile pathfinding movement on the board
## 2. Walking up to available MP
## 3. Large readable tactical badges on tiles

var _fails: int = 0
var _checks: int = 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)
	else:
		print("PATH_OK: " + label)

func _ready() -> void:
	GlobalData.reset_run_data()
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board_mp = 5
	GlobalData.mech_energy = 100.0
	GlobalData.current_tile = Vector2i(0, 0)

	var bm_script = preload("res://scripts/board/board_manager.gd")
	var bm = Node3D.new()
	bm.name = "BoardManager"
	bm.set_script(bm_script)

	var tile_container := Node3D.new()
	tile_container.name = "TileContainer"
	bm.add_child(tile_container)

	var player_token := Node3D.new()
	player_token.name = "PlayerToken"
	bm.add_child(player_token)

	add_child(bm)

	# Build a 5x5 grid of mock plain tiles
	var tile_script = preload("res://scripts/board/board_tile.gd")
	for x in range(5):
		for y in range(5):
			var pos := Vector2i(x, y)
			var tile: StaticBody3D = StaticBody3D.new()
			tile.set_script(tile_script)
			tile.set_meta("grid_pos", pos)
			tile.set_meta("terrain", "plain")
			tile.set_meta("tile_type", "safehouse" if pos == Vector2i(3, 0) else "empty")
			bm.nodes_dict[pos] = tile
			tile_container.add_child(tile)

	bm.current_pos = Vector2i(0, 0)

	# Test 1: Pathfinding from (0,0) to (3,0)
	var path: Array[Vector2i] = bm._find_path(Vector2i(0, 0), Vector2i(3, 0))
	_check(path.size() == 3, "found 3-step path from (0,0) to (3,0) (got %d)" % path.size())
	_check(path[0] == Vector2i(1, 0) and path[1] == Vector2i(2, 0) and path[2] == Vector2i(3, 0), "path is [(1,0), (2,0), (3,0)]")

	# Test 2: Multi-step move_to_tile from (0,0) to (3,0)
	var moved: bool = bm.move_to_tile(Vector2i(3, 0))
	_check(moved, "move_to_tile succeeded for multi-tile movement")
	_check(bm.current_pos == Vector2i(3, 0), "player token reached destination (3,0)")
	_check(GlobalData.board_mp == 2, "MP correctly deducted from 5 to 2 (consumed 3 MP)")

	# Test 3: Tactical badge readability on POI tile
	var safehouse_tile = bm.nodes_dict[Vector2i(3, 0)]
	var badge = safehouse_tile.find_child("TacticalBadge", true, false)
	_check(badge != null, "TacticalBadge exists on safehouse tile")
	if badge is Label3D:
		_check(badge.font_size >= 30, "Badge font size is large and readable (>= 30, got %d)" % badge.font_size)
		_check(badge.pixel_size >= 0.008, "Badge pixel size is scaled for 3D distance (>= 0.008, got %.4f)" % badge.pixel_size)

	print("BOARD_PATHFINDING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
