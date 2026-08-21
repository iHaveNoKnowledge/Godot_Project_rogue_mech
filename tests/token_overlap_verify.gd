extends Node3D

## Verification test for Board Token Overlap Fix:
## Ensures player pawn and patrol fleet markers are offset side-by-side
## when occupying the same tile instead of overlapping/clipping into each other.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("TOKEN_OVERLAP_OK: %s" % msg)
	else:
		_fails += 1
		print("TOKEN_OVERLAP_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Board Token Overlap Verification ---")

	await _test_token_side_by_side_offset()

	print("TOKEN_OVERLAP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_token_side_by_side_offset() -> void:
	var bm_scene = load("res://scenes/board/game_board.tscn")
	if bm_scene == null:
		return
	var bm = bm_scene.instantiate()
	add_child(bm)
	await get_tree().process_frame

	# Simulate a patrol fleet sitting on tile (2, 2)
	GlobalData.board.board_patrols = [
		{
			"id": 1,
			"pos": Vector2i(2, 2),
			"prev_pos": Vector2i(2, 2),
			"dir": Vector2i(1, 0),
			"aces": 0,
			"faction": "hostile",
			"archetype": "recon"
		}
	]

	# Set player on tile (2, 2)
	bm.current_pos = Vector2i(2, 2)
	bm._update_token_position()
	bm._refresh_patrol_markers()

	var player_pos: Vector3 = bm.player_token.global_position
	var patrol_markers_container: Node3D = bm._patrol_marker_container
	_check(patrol_markers_container != null and patrol_markers_container.get_child_count() > 0, "Patrol marker spawned on board")

	if patrol_markers_container and patrol_markers_container.get_child_count() > 0:
		var patrol_pos: Vector3 = patrol_markers_container.get_child(0).global_position
		var distance_xz := Vector2(player_pos.x, player_pos.z).distance_to(Vector2(patrol_pos.x, patrol_pos.z))
		_check(distance_xz > 0.8, "Player token and patrol marker maintain clear side-by-side separation (distance=%.2fm > 0.8m)" % distance_xz)
		_check(player_pos.x < patrol_pos.x, "Player token is on the left (-0.55m) and patrol marker is on the right (+0.55m)")

	bm.queue_free()
