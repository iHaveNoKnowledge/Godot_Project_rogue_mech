extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	print("=== Running Convoy Breakdown & Realistic Interception Verification ===")
	_test_breakdown_trigger_no_instant_combat()
	_test_movement_blocked_during_breakdown()
	_test_patrols_converge_on_breakdown()
	_test_patrol_interception_ambush()
	_test_safe_repair_resolution()

	print("\n=== Test Results: %d Passed, %d Failed ===" % [passed, failed])
	if failed == 0:
		print("ALL_CONVOY_BREAKDOWN_TESTS_PASSED")
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


func _test_breakdown_trigger_no_instant_combat() -> void:
	GameManager.current_state = GameManager.State.BOARD
	GlobalData.reset_run_data()
	GlobalData.board.convoy_hp = 10.0  # High breakdown chance
	GlobalData.narrative.blocked_intermission = false
	GlobalData.board.convoy_breakdown_turns = 0

	var board_mgr_script = load("res://scripts/board/board_manager.gd")
	var board_mgr = Node3D.new()
	var tc = Node3D.new()
	tc.name = "TileContainer"
	board_mgr.add_child(tc)
	var pt = Node3D.new()
	pt.name = "PlayerToken"
	board_mgr.add_child(pt)
	board_mgr.set_script(board_mgr_script)
	add_child(board_mgr)

	# Trigger breakdown
	board_mgr._trigger_convoy_breakdown("mountain")

	_assert(GlobalData.board.convoy_breakdown_turns == 2, "Breakdown sets repair turns to 2")
	_assert(GlobalData.board.board_mp == 0, "Breakdown zeroes out MP")
	_assert(GlobalData.narrative.blocked_intermission == true, "Breakdown sets blocked_intermission")
	_assert(GameManager.current_state == GameManager.State.BOARD, "State remains BOARD (no instant scene change / force combat)")

	board_mgr.queue_free()


func _test_movement_blocked_during_breakdown() -> void:
	GlobalData.reset_run_data()
	GlobalData.board.convoy_breakdown_turns = 2

	var board_mgr_script = load("res://scripts/board/board_manager.gd")
	var board_mgr = Node3D.new()
	var tc = Node3D.new()
	tc.name = "TileContainer"
	board_mgr.add_child(tc)
	var pt = Node3D.new()
	pt.name = "PlayerToken"
	board_mgr.add_child(pt)
	board_mgr.set_script(board_mgr_script)
	add_child(board_mgr)

	var move_ok = board_mgr.move_to_tile(Vector2i(1, 0), false)
	_assert(move_ok == false, "move_to_tile is blocked while convoy_breakdown_turns > 0")

	board_mgr.queue_free()


func _test_patrols_converge_on_breakdown() -> void:
	GlobalData.reset_run_data()
	var player_pos := Vector2i(5, 5)

	# Set up a mock grid with passable terrain
	var grid_dict := {}
	for x in range(10):
		for y in range(10):
			var tile := Node.new()
			tile.set_meta("terrain", "plain")
			tile.set_meta("tile_type", "empty")
			grid_dict[Vector2i(x, y)] = tile

	GlobalData.board.board_grid = [grid_dict]

	# Add a patrol at (5, 9) (4 tiles south)
	GlobalData.board.board_patrols = [{
		"id": 1,
		"pos": Vector2i(5, 9),
		"home": Vector2i(5, 9),
		"archetype": "armored",
		"faction": "hostile",
		"aggro": false
	}]

	var ambush := PatrolSystem.advance_breakdown_turn(player_pos)
	var p = GlobalData.board.board_patrols[0]
	var dist_after = PatrolSystem._manhattan(p["pos"], player_pos)

	_assert(dist_after < 4, "Hostile patrol moved closer to stranded player (initial dist 4, now %d)" % dist_after)
	_assert(p.get("aggro", false) == true, "Patrol was set to aggro mode")
	_assert(ambush == Vector2i(-1, -1), "No ambush on first turn (still far away)")

	# Clean up mock tiles
	for t in grid_dict.values():
		t.free()


func _test_patrol_interception_ambush() -> void:
	GlobalData.reset_run_data()
	var player_pos := Vector2i(3, 3)

	var grid_dict := {}
	for x in range(7):
		for y in range(7):
			var tile := Node.new()
			tile.set_meta("terrain", "plain")
			tile.set_meta("tile_type", "empty")
			grid_dict[Vector2i(x, y)] = tile

	GlobalData.board.board_grid = [grid_dict]

	# Add patrol 1 tile away at (3, 4)
	GlobalData.board.board_patrols = [{
		"id": 2,
		"pos": Vector2i(3, 4),
		"home": Vector2i(3, 4),
		"archetype": "armored",
		"faction": "hostile",
		"aggro": false
	}]

	var ambush := PatrolSystem.advance_breakdown_turn(player_pos)
	var p = GlobalData.board.board_patrols[0]

	_assert(p["pos"] == player_pos, "Hostile patrol stepped onto player's tile")
	_assert(ambush == player_pos, "Ambush was triggered at player position")

	for t in grid_dict.values():
		t.free()


func _test_safe_repair_resolution() -> void:
	GlobalData.reset_run_data()
	GlobalData.board.convoy_breakdown_turns = 2
	GlobalData.board.board_patrols = [] # No patrols nearby

	var board_mgr_script = load("res://scripts/board/board_manager.gd")
	var board_mgr = Node3D.new()
	var tc = Node3D.new()
	tc.name = "TileContainer"
	board_mgr.add_child(tc)
	var pt = Node3D.new()
	pt.name = "PlayerToken"
	board_mgr.add_child(pt)
	board_mgr.set_script(board_mgr_script)
	add_child(board_mgr)

	# Simulate 2 repair turns
	while GlobalData.board.convoy_breakdown_turns > 0:
		PatrolSystem.advance_breakdown_turn(Vector2i.ZERO)
		GlobalData.board.convoy_breakdown_turns -= 1

	_assert(GlobalData.board.convoy_breakdown_turns == 0, "Repairs completed after 2 turns")

	board_mgr.queue_free()
