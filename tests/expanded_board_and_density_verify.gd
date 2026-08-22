extends Node3D

## Automated Verification for Expanded 25x25 Board Map, Open Wilderness Ratio, and Uncrowded Event Density.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("EXPANDED_BOARD_OK: %s" % msg)
	else:
		_fails += 1
		print("EXPANDED_BOARD_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Expanded Board Map & Open Space Verification ---")

	# 1. Test Grid Size
	_check(BoardConfig.GRID_SIZE == 25, "BoardConfig.GRID_SIZE is expanded to 25 (25x25 map)")

	# 2. Test Board Generation on 25x25
	var gen_scene = preload("res://scripts/board/board_generator.gd")
	var generator = gen_scene.new()
	add_child(generator)

	var board_data: Dictionary = generator.generate_board()
	var nodes: Dictionary = board_data.get("nodes", {})
	var tile_types: Dictionary = board_data.get("tile_types", {})
	var terrain: Dictionary = board_data.get("terrain", {})

	_check(nodes.size() == 625, "Generated full 25x25 grid with 625 tile nodes (found: %d)" % nodes.size())
	_check(tile_types.get(Vector2i(0, 0)) == "start", "Start tile is located at (0, 0)")
	_check(tile_types.get(Vector2i(24, 24)) == "exit", "Exit tile is located at (24, 24)")

	# 3. Test Open Terrain vs Event Density
	var empty_count := 0
	var event_count := 0
	for key in tile_types:
		var type: String = tile_types[key]
		if type == "empty":
			empty_count += 1
		elif type not in ["start", "exit", "rock", "water"]:
			event_count += 1

	var empty_ratio := float(empty_count) / float(nodes.size())
	_check(empty_ratio >= 0.45, "Open wilderness/empty ratio is healthy and uncrowded (%.1f%% empty, %d empty tiles)" % [empty_ratio * 100.0, empty_count])
	_check(event_count > 0, "Event and POI distribution present across large map (%d POIs/events)" % event_count)

	# 4. Test Seamless Ground Plane Size
	var ground_mesh := generator.build_ground()
	var plane_mesh: PlaneMesh = ground_mesh.mesh as PlaneMesh
	_check(plane_mesh != null and plane_mesh.size.x >= 100.0, "Board ground plane spans full 25x25 map (size=%.1fx%.1f)" % [plane_mesh.size.x, plane_mesh.size.y])

	print("--- Expanded Board Map & Open Space Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_EXPANDED_BOARD_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
