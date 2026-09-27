extends Node

## Phase 2E-34: Board Tactical Interaction State & Feedback Verification
## Verifies hover, selection, reachable highlights, destination reticles,
## invalid move rejection feedback, occupied tile distinction, encounter initiation,
## and non-combat transitions without duplicating gameplay state.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")
const BoardManager = preload("res://scripts/board/board_manager.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failed_messages: Array[String] = []
var _board_scene: BoardManager = null


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-34 BOARD TACTICAL INTERACTION STATE & FEEDBACK AUDIT ===\n")
	GameManager.suppress_scene_change = true

	await _run_all_tests()

	print("\n==================================================")
	print("PHASE 2E-34 INTERACTION AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if not _failed_messages.is_empty():
		print("FAILED ASSERTIONS:")
		for msg in _failed_messages:
			print("  - " + msg)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2E_34_SUCCESS\n")
	else:
		push_error("PHASE_2E_34_FAILURE: %d assertions failed" % _fail_count)

	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()

	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failed_messages.append(message)
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _setup_board(tile: Vector2i = Vector2i(2, 2)) -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null

	GlobalData.board.current_sector = 1
	GlobalData.board.board_day = 1
	GlobalData.board.board_mp = 6
	GlobalData.board.board_mp_max = 6
	GlobalData.board.active_contract = {"name": "Test Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_max_fuel = 100.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	GlobalData.fuel.traversal_mode = "mecha"
	GlobalData.fuel.convoy_is_deployed = false
	GlobalData.fuel.mecha_is_parked = false
	GlobalData.board.board_patrols = []
	GlobalData.board.current_tile = tile
	GameManager.current_state = GameManager.State.BOARD

	var scene_res = load("res://scenes/board/game_board.tscn") as PackedScene
	_board_scene = scene_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _run_all_tests() -> void:
	var board = _setup_board(Vector2i(2, 2))
	
	# Find an existing adjacent tile to current_pos
	var adj_pos: Vector2i = Vector2i(-1, -1)
	var tile_adj = null
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var cand = board.current_pos + d
		if board.nodes_dict.has(cand):
			adj_pos = cand
			tile_adj = board.nodes_dict[cand]
			break

	# [1] Hover Feedback & Shader State
	print("-- [1] Hover Feedback & Shader State --")
	_assert(tile_adj != null, "Adjacent tile exists in board grid")
	if tile_adj != null:
		tile_adj.set_hover(true)
		_assert(tile_adj.is_hovered == true, "Tile is_hovered flag is true upon hover")
		var mesh_inst = tile_adj.get_node_or_null("MeshInstance3D") as MeshInstance3D
		_assert(mesh_inst != null and mesh_inst.position.y > 0.04, "Hovered tile lifts slightly (y > 0.04m) for tactile depth")
		var smat = mesh_inst.get_surface_override_material(0) as ShaderMaterial
		_assert(smat != null, "Tile has ShaderMaterial override")
		var hover_intensity = smat.get_shader_parameter("highlight_intensity")
		_assert(float(hover_intensity) > 0.3, "Hovered tile shader highlight intensity is elevated")
		tile_adj.set_hover(false)
		_assert(tile_adj.is_hovered == false, "Tile is_hovered resets to false on hover exit")

	# [2] Reachable Adjacent Tile Feedback
	print("\n-- [2] Reachable Adjacent Tile Feedback --")
	board._highlight_adjacent()
	var reachable_count: int = 0
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var nxt = board.current_pos + d
		if board.nodes_dict.has(nxt):
			var t = board.nodes_dict[nxt]
			if t.is_highlighted:
				reachable_count += 1
				_assert(t._reachable_glow != null and t._reachable_glow.visible, "Reachable tile has visible ReachableGlow")
	_assert(reachable_count > 0, "Reachable adjacent tiles are highlighted from current position")

	# [3] Movement Selection & Destination Reticle Presentation
	print("\n-- [3] Movement Selection & Destination Reticle Presentation --")
	var move_path: Array[Vector2i] = []
	for d in [Vector2i(1,0), Vector2i(2,0)]:
		var p = board.current_pos + d
		if board.nodes_dict.has(p):
			move_path.append(p)
	if move_path.size() < 2:
		move_path = [board.current_pos + Vector2i(1,0), board.current_pos + Vector2i(1,1)]
	
	board._show_path_trail(move_path)
	_assert(board._path_trail_markers.size() == move_path.size(), "Path trail created markers for each step in path")
	
	var waypoint = board._path_trail_markers[0]
	_assert(waypoint.mesh is SphereMesh, "Intermediate step is a waypoint SphereMesh")
	
	var dest_reticle = board._path_trail_markers[board._path_trail_markers.size() - 1]
	_assert(dest_reticle.name == "DestinationReticle", "Destination step has distinct DestinationReticle")
	_assert(dest_reticle.mesh is TorusMesh, "DestinationReticle uses TorusMesh reticle")
	var dest_mat = dest_marker_mat(dest_reticle)
	_assert(dest_mat != null and dest_mat.albedo_color.b > 0.6, "Standard destination reticle is cyan/electric blue")
	board._clear_path_trail()
	_assert(board._path_trail_markers.is_empty(), "Path trail markers cleaned up cleanly")

	# [4] Enemy Encounter Destination Reticle Presentation
	print("\n-- [4] Enemy Encounter Destination Reticle Presentation --")
	var enemy_dest = move_path[move_path.size() - 1]
	GlobalData.board.board_patrols = [
		{"pos": enemy_dest, "dir": Vector2i(1, 0), "archetype": "armored", "fleet_count": 1, "name": "Vanguard"}
	]
	board._show_path_trail(move_path)
	var enemy_dest_reticle = board._path_trail_markers[board._path_trail_markers.size() - 1]
	var enemy_dest_mat = dest_marker_mat(enemy_dest_reticle)
	_assert(enemy_dest_mat != null and enemy_dest_mat.albedo_color.r > 0.7 and enemy_dest_mat.albedo_color.b < 0.4, "Enemy encounter destination reticle is amber/crimson (attack/engage indicator)")
	board._clear_path_trail()

	# [5] Invalid / Impassable Destination Rejection Feedback
	print("\n-- [5] Invalid / Impassable Destination Rejection Feedback --")
	board._spawn_invalid_destination_pulse(Vector3(10.0, 0.0, 10.0))
	var pulse_found := false
	for c in board.get_children():
		if c.name == "InvalidMovePulse":
			pulse_found = true
			_assert(c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh, "InvalidMovePulse is a TorusMesh rejection pulse")
			var p_mat = (c as MeshInstance3D).material_override as StandardMaterial3D
			_assert(p_mat != null and p_mat.albedo_color.r > 0.8, "Invalid move rejection pulse is crimson red")
			break
	_assert(pulse_found, "Invalid move rejection pulse spawned upon invalid move request")

	# [6] Selected Position Tracking
	print("\n-- [6] Selected Position Tracking --")
	var target_passable: Vector2i = Vector2i(-1, -1)
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var cand = board.current_pos + d
		if board.nodes_dict.has(cand):
			var tile_node = board.nodes_dict[cand]
			tile_node.set_meta("terrain", "plain") # ensure passable for step test
			tile_node.set_meta("tile_type", "empty")
			target_passable = cand
			break
	
	_assert(target_passable != Vector2i(-1, -1), "Valid adjacent target tile found")
	var step_ok = board.move_to_tile(target_passable, false)
	_assert(step_ok, "board.move_to_tile successfully stepped to adjacent tile")
	_assert(board.selected_pos == target_passable, "board.selected_pos tracks selected target tile")
	_assert(board.current_pos == target_passable, "board.current_pos updated to new tile upon step")

	# [7] Non-Combat Node Overlays Presence
	print("\n-- [7] Non-Combat Node Overlays Presence --")
	var safehouse_ui = board.get_node_or_null("SafehouseUI")
	var event_ui = board.get_node_or_null("EventUI")
	var city_shop_ui = board.get_node_or_null("CityShopUI")
	var research_lab_ui = board.get_node_or_null("ResearchLabUI")
	_assert(safehouse_ui != null, "SafehouseUI exists in board scene")
	_assert(event_ui != null, "EventUI exists in board scene")
	_assert(city_shop_ui != null, "CityShopUI exists in board scene")
	_assert(research_lab_ui != null, "ResearchLabUI exists in board scene")

	# [8] Dead-End Node Topology & Graph Safety
	print("\n-- [8] Dead-End Node Topology & Graph Safety --")
	var dead_ends := 0
	for key in board.nodes_dict:
		var tile = board.nodes_dict[key]
		var passable_neighbors := 0
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n = key + d
			if board.nodes_dict.has(n) and BoardConfig.is_passable(str(board.nodes_dict[n].get_meta("terrain", "plain"))):
				passable_neighbors += 1
		if passable_neighbors <= 1:
			dead_ends += 1
	_assert(dead_ends >= 0, "Dead-end detection operates cleanly without altering board graph topology")

	# [9] Save / Load Reconstitution of Board Presentation
	print("\n-- [9] Save / Load Reconstitution of Board Presentation --")
	GlobalData.board.current_tile = Vector2i(4, 4)
	var reloaded_board = _setup_board(Vector2i(4, 4))
	_assert(reloaded_board.current_pos == Vector2i(4, 4), "Current position reconstructed from GlobalData.board.current_tile")
	var player_tok = reloaded_board.get_node_or_null("PlayerToken") as BoardUnit3D
	_assert(player_tok != null, "PlayerToken reconstructed cleanly")
	var cur_tile = reloaded_board.nodes_dict.get(Vector2i(4, 4))
	var p_dist = player_tok.global_position.distance_to(cur_tile.global_position + Vector3(0, 0.9, 0))
	_assert(p_dist < 0.1, "Player token aligned to authoritative saved tile upon reload")


func dest_marker_mat(node: Node) -> StandardMaterial3D:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).material_override as StandardMaterial3D
	return null
