extends Node

## Headless verification of the board token / camera / tile revamp:
##   1. BoardArrow builds the ">" chevron (2 arm boxes; 4 when double for aces)
##      and face_heading() aims it at the right world heading.
##   2. patrol_marker wires a fleet's color/aces/heading into the arrow.
##   3. BoardCamera rotate_yaw() orbits the isometric offset around the player.
##   4. board_tile: event/data-node tiles spawn a hidden glowing beacon that
##      appears on reveal; highlight() toggles a faint reachable glow disc.
##   5. PatrolSystem tracks each fleet's movement heading (dir).
## Run: godot --headless --path . res://tests/board_tokens_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_arrow_shape()
	await _verify_arrow_heading()
	await _verify_patrol_marker()
	await _verify_camera_yaw()
	await _verify_tile_beacon()
	await _verify_tile_highlight()
	await _verify_enemy_base_model()
	_verify_patrol_dir()
	print("BOARD_TOKENS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _count_mesh_children(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			count += 1
	return count


func _make_arrow(c: Color, is_double: bool) -> Node3D:
	var arrow := Node3D.new()
	arrow.set_script(preload("res://scripts/board/board_arrow.gd"))
	arrow.setup(c, is_double, 1.0, false)
	add_child(arrow)
	return arrow


func _verify_arrow_shape() -> void:
	var single := _make_arrow(BoardArrow.PLAYER_BLUE, false)
	_check(_count_mesh_children(single) == 2, "single chevron builds two arm boxes")
	single.queue_free()

	var ace := _make_arrow(BoardArrow.HOSTILE_RED, true)
	_check(_count_mesh_children(ace) == 4, "ace double chevron builds four arm boxes")
	ace.queue_free()
	await get_tree().process_frame


func _verify_arrow_heading() -> void:
	var arrow := _make_arrow(BoardArrow.PLAYER_BLUE, false)
	await get_tree().process_frame

	# The chevron tip is local +X. East = (1, 0) keeps it at 0 yaw.
	arrow.face_heading(Vector2i(1, 0))
	_check(absf(arrow.rotation.y) < 0.001, "east heading keeps the arrow at 0 yaw")
	# South = +Z: -atan2(1, 0) = -PI/2 rotates local +X onto +Z.
	arrow.face_heading(Vector2i(0, 1))
	_check(absf(arrow.rotation.y - (-PI / 2.0)) < 0.001, "south heading rotates the arrow -90 deg")
	# West = -X: yaw lands at -PI (|yaw| = PI).
	arrow.face_heading(Vector2i(-1, 0))
	_check(absf(absf(arrow.rotation.y) - PI) < 0.001, "west heading rotates the arrow 180 deg")
	# North = -Z: -atan2(-1, 0) = +PI/2.
	arrow.face_heading(Vector2i(0, -1))
	_check(absf(arrow.rotation.y - PI / 2.0) < 0.001, "north heading rotates the arrow +90 deg")

	arrow.queue_free()
	await get_tree().process_frame


func _verify_patrol_marker() -> void:
	var marker := Node3D.new()
	marker.set_script(preload("res://scripts/board/patrol_marker.gd"))
	add_child(marker)
	marker.setup({"faction": "hostile", "aces": 1, "dir": Vector2i(0, -1)})
	await get_tree().process_frame

	_check(marker.get_child_count() == 1, "patrol marker hosts a single arrow")
	var arrow: Node3D = marker.get_child(0)
	_check(_count_mesh_children(arrow) == 4, "ace patrol arrow is a double chevron")
	# North heading -> the arrow faces -Z (+PI/2 yaw on a +X-pointing chevron).
	_check(absf(arrow.rotation.y - PI / 2.0) < 0.001, "patrol arrow faces its fleet heading")

	marker.queue_free()
	await get_tree().process_frame


func _verify_camera_yaw() -> void:
	var cam := Camera3D.new()
	cam.set_script(preload("res://scripts/board/board_camera_init.gd"))
	cam.camera_height = 30.0
	add_child(cam)

	var base := Vector3(30.0 * 0.45, 30.0, 30.0 * 0.6)
	_check(cam._get_offset().distance_to(base) < 0.001, "default camera offset is the isometric base")
	cam.rotate_yaw(PI / 2.0)
	var expected := base.rotated(Vector3.UP, PI / 2.0)
	_check(cam._get_offset().distance_to(expected) < 0.001, "rotate_yaw orbits the offset around the player")
	cam.rotate_yaw(-PI / 2.0)
	_check(cam._get_offset().distance_to(base) < 0.001, "rotate_yaw is reversible")

	cam.queue_free()
	await get_tree().process_frame


func _make_tile(tile_type: String, grid_pos: Vector2i) -> Node:
	var tile = load("res://scenes/board/board_tile.tscn").instantiate()
	tile.set_meta("tile_type", tile_type)
	tile.set_meta("grid_pos", grid_pos)
	tile.set_meta("terrain", "plain")
	tile.set_meta("connections", [])
	add_child(tile)
	return tile


func _verify_tile_beacon() -> void:
	var tile := _make_tile("event", Vector2i(1, 1))
	await get_tree().process_frame

	_check(tile._event_beacon != null, "event tile spawns a glowing beacon")
	_check(not tile._event_beacon.visible, "beacon stays hidden under fog of war")
	tile.reveal()
	_check(tile._event_beacon.visible, "beacon appears once the tile is revealed")
	_check(tile._reachable_glow == null, "no reachable glow until the tile is highlighted")
	tile.queue_free()

	var data_node := _make_tile("data_node", Vector2i(2, 2))
	await get_tree().process_frame
	_check(data_node._event_beacon != null, "data-node tile spawns a glowing beacon")
	data_node.queue_free()

	var empty := _make_tile("empty", Vector2i(3, 3))
	await get_tree().process_frame
	_check(empty._event_beacon == null, "plain tiles have no beacon")
	empty.queue_free()
	await get_tree().process_frame


func _verify_tile_highlight() -> void:
	var tile := _make_tile("empty", Vector2i(4, 4))
	await get_tree().process_frame

	tile.highlight(true)
	_check(tile._reachable_glow != null, "highlight creates the reachable glow disc")
	_check(tile._reachable_glow.visible, "glow disc is visible while highlighted")
	_check(tile._reachable_glow.material_override != null, "glow disc carries a transparent glow material")
	tile.highlight(false)
	_check(not tile._reachable_glow.visible, "glow disc hides when unhighlighted")

	tile.queue_free()
	await get_tree().process_frame


func _collect_meshes(node: Node, found: Array) -> void:
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		_collect_meshes(child, found)


func _verify_enemy_base_model() -> void:
	var tile := _make_tile("enemy_base", Vector2i(5, 5))
	await get_tree().process_frame

	# Temporary camp: a triangular tent — polygonal (prism/box) only.
	tile.set_enemy_base_model("camp")
	_check(tile._enemy_base_model != null, "enemy base tile spawns a 3D model")
	var camp_meshes: Array = []
	_collect_meshes(tile._enemy_base_model, camp_meshes)
	_check(camp_meshes.size() >= 2, "camp model builds a tent body + entrance")
	var camp_angular := true
	for m in camp_meshes:
		if m.mesh is CylinderMesh or m.mesh is CapsuleMesh or m.mesh is SphereMesh:
			camp_angular = false
	_check(camp_angular, "camp model is built from angular primitives only (no cylinders)")

	# Rooted base: a tall fortified tower of stacked boxes.
	tile.set_enemy_base_model("rooted")
	var rooted_meshes: Array = []
	_collect_meshes(tile._enemy_base_model, rooted_meshes)
	_check(rooted_meshes.size() >= 5, "rooted model builds a multi-storey tower")
	var rooted_angular := true
	for m in rooted_meshes:
		if not (m.mesh is BoxMesh or m.mesh is PrismMesh):
			rooted_angular = false
	_check(rooted_angular, "rooted model is boxes/prisms only (no cylinders)")
	var tallest := 0.0
	for m in rooted_meshes:
		var box := m.mesh as BoxMesh
		if box:
			tallest = maxf(tallest, m.global_position.y + box.size.y * 0.5)
	_check(tallest > 4.5, "rooted tower is a tall building (> 4.5m high)")

	tile.clear_enemy_base_model()
	_check(tile._enemy_base_model == null, "clearing the base removes its model")
	tile.queue_free()
	await get_tree().process_frame


func _verify_patrol_dir() -> void:
	GlobalData.reset_run_data()
	GlobalData.board.current_sector = 1
	GlobalData.board.board_seed = 4242
	var gen := preload("res://scripts/board/board_generator.gd").new()
	gen.generate_board()
	PatrolSystem.spawn_patrols()

	var all_default := true
	for p in GlobalData.board.board_patrols:
		if p.get("dir", Vector2i.ZERO) != Vector2i(1, 0):
			all_default = false
	_check(all_default, "patrols spawn with a default east heading")

	# Whatever a fleet moves this day, its heading must match the displacement.
	var before: Dictionary = {}
	for p in GlobalData.board.board_patrols:
		before[p.get("id")] = p.get("pos")
	PatrolSystem.advance_day(Vector2i(0, 0))
	var in_sync := true
	for p in GlobalData.board.board_patrols:
		var old: Vector2i = before.get(p.get("id"), p.get("pos"))
		if old != p.get("pos") and p.get("dir") != p.get("pos") - old:
			in_sync = false
	_check(in_sync, "advance_day keeps each fleet's heading in sync with its movement")

	# A JSON save/load round-trip must keep pos/home/dir as real Vector2i — the
	# old code only converted pos/home, so dir flattened to a String and the
	# fleet's arrow marker crashed/broke on load.
	var raw_save := SaveGameIO._serialize_patrols()
	var round_tripped = JSON.parse_string(JSON.stringify(raw_save))
	SaveGameIO.restore_from_dict({"board_patrols": round_tripped})
	var all_vec := true
	for p in GlobalData.board.board_patrols:
		if not (p.get("pos") is Vector2i) or not (p.get("home") is Vector2i) or not (p.get("dir") is Vector2i):
			all_vec = false
	_check(all_vec, "patrol pos/home/dir round-trip through JSON as real Vector2i")

	# normalize_dir parses every stored shape a patrol field can arrive in.
	_check(PatrolSystem.normalize_dir("(1, 0)") == Vector2i(1, 0), "normalize_dir parses a JSON-flattened String")
	_check(PatrolSystem.normalize_dir({"x": 0, "y": -1}) == Vector2i(0, -1), "normalize_dir parses an {x, y} dict")
	_check(PatrolSystem.normalize_dir(Vector2i(-1, 0)) == Vector2i(-1, 0), "normalize_dir passes a Vector2i through")
	_check(PatrolSystem.normalize_dir(null) == Vector2i(1, 0), "normalize_dir defaults a missing dir to east")

	# normalize_patrol heals an old-save patrol entry in place.
	var heal: Dictionary = {"pos": "(3, 4)", "home": "(3, 4)", "dir": "(0, 1)"}
	PatrolSystem.normalize_patrol(heal)
	_check(heal["pos"] == Vector2i(3, 4) and heal["dir"] == Vector2i(0, 1), "normalize_patrol heals an old-save patrol in place")
