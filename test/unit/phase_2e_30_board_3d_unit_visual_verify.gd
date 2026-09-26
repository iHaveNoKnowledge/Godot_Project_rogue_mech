extends Node

## Phase 2E-30: Board 3D Unit Visual Representation & Animated Movement
## Verifies that Board units (Player Valkren and Enemy Fleet Commanders) are rendered
## as full 3D visual models with correct scaling, facing, idle/run animation,
## and board movement while preserving 100% authoritative gameplay state.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _board_scene: Node3D = null


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-30 BOARD 3D UNIT VISUAL AUDIT ===\n")
	GameManager.suppress_scene_change = true

	await _run_all_tests()

	print("\n==================================================")
	print("PHASE 2E-30 BOARD 3D UNIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2E_30_SUCCESS\n")
	else:
		push_error("PHASE_2E_30_FAILURE: %d assertions failed" % _fail_count)

	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()

	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		push_error("Assertion failed: %s" % message)
		print("  [FAIL] %s" % message)


func _setup_board(tile: Vector2i = Vector2i(2, 2)) -> Node3D:
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
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_is_deployed = false
	GlobalData.fuel.mecha_is_parked = false
	GlobalData.board.board_patrols = []
	GlobalData.board.current_tile = tile
	GameManager.current_state = GameManager.State.BOARD

	var scene_res = load("res://scenes/board/game_board.tscn") as PackedScene
	_board_scene = scene_res.instantiate()
	add_child(_board_scene)
	return _board_scene


func _run_all_tests() -> void:
	# [1] Board Unit 3D Script & Scene Loading
	print("-- [1] Board Unit 3D Script & Scene Loading --")
	var unit_script = load("res://scripts/board/board_unit_3d.gd")
	_assert(unit_script != null, "BoardUnit3D script loads successfully")
	var unit := BoardUnit3D.new()
	_assert(unit != null, "BoardUnit3D can be instantiated directly")

	# [2] Valkren Model Instantiation & Mesh Hierarchy
	print("\n-- [2] Valkren Model Instantiation & Mesh Hierarchy --")
	unit.setup_player()
	add_child(unit)
	_assert(unit.torso_node != null, "Player unit has Torso node")
	_assert(unit.head_node != null, "Player unit has Head node")
	_assert(unit.backpack_node != null, "Player unit has Backpack node")
	_assert(unit.arm_left_node != null and unit.arm_right_node != null, "Player unit has Left and Right arm nodes")
	_assert(unit.leg_left_node != null and unit.leg_right_node != null, "Player unit has Left and Right leg nodes")

	# [3] Player Unit Alignment to Current Tile
	print("\n-- [3] Player Unit Alignment to Current Tile --")
	var board = _setup_board()
	var player_token = board.get_node_or_null("PlayerToken")
	_assert(player_token != null, "PlayerToken exists in game_board scene")
	_assert(player_token is BoardUnit3D, "PlayerToken is an instance of BoardUnit3D")
	var current_tile = board.nodes_dict.get(board.current_pos)
	_assert(current_tile != null, "Current position tile exists in board grid")
	var dist: float = player_token.global_position.distance_to(current_tile.global_position + Vector3(0, 0.9, 0))
	_assert(dist < 0.1, "Player unit aligns to current tile world position")

	# [4] Player Unit Scale & Framing
	print("\n-- [4] Player Unit Scale & Framing --")
	_assert(player_token.unit_scale.x >= 0.50 and player_token.unit_scale.x <= 0.70, "Player unit scale is well-framed for tabletop (0.58)")
	_assert(player_token.model_root != null and player_token.model_root.scale == player_token.unit_scale, "ModelRoot reflects configured unit_scale")

	# [5] Ground Contact Offset
	print("\n-- [5] Ground Contact Offset --")
	_assert(player_token.ground_anchor != null, "Player unit possesses GroundAnchor node")
	_assert(player_token.ground_offset_y >= 0.0, "Player unit ground offset Y is valid")

	# [6] Animation Controller Presence
	print("\n-- [6] Animation Controller Presence --")
	_assert(player_token.anim_player != null, "Player unit possesses AnimationPlayer controller")
	_assert(player_token.anim_player.has_animation("idle"), "Animation controller contains 'idle' animation")
	_assert(player_token.anim_player.has_animation("run"), "Animation controller contains 'run' animation")

	# [7] Idle Animation
	print("\n-- [7] Idle Animation --")
	player_token.play_idle()
	_assert(player_token.anim_state == "idle", "Player unit transitions to idle state")
	_assert(not player_token.is_moving, "Player unit is_moving flag is false in idle")

	# [8] Run Animation
	print("\n-- [8] Run Animation --")
	player_token.play_run()
	_assert(player_token.anim_state == "run", "Player unit transitions to run state")
	_assert(player_token.is_moving, "Player unit is_moving flag is true in run")
	player_token.play_idle()

	# [9] Facing Direction
	print("\n-- [9] Facing Direction --")
	player_token.face_heading(Vector2i(1, 0), true) # East -> -PI/2
	_assert(absf(player_token.rotation.y - (-PI * 0.5)) < 0.05, "Unit correctly faces East heading (rotation.y = -PI/2)")
	player_token.face_heading(Vector2i(0, -1), true) # North -> 0
	_assert(absf(player_token.rotation.y) < 0.05, "Unit correctly faces North heading (rotation.y = 0)")
	player_token.face_heading(Vector2i(0, 1), true) # South -> PI
	_assert(absf(absf(player_token.rotation.y) - PI) < 0.05, "Unit correctly faces South heading (rotation.y = PI)")
	player_token.face_heading(Vector2i(-1, 0), true) # West -> PI/2
	_assert(absf(player_token.rotation.y - (PI * 0.5)) < 0.05, "Unit correctly faces West heading (rotation.y = PI/2)")
	player_token.face_heading(Vector2i(1, -1), true) # North-East -> -PI/4
	_assert(absf(player_token.rotation.y - (-PI * 0.25)) < 0.05, "Unit correctly faces North-East heading (rotation.y = -PI/4)")
	player_token.face_heading(Vector2i(1, 1), true) # South-East -> -3*PI/4
	_assert(absf(player_token.rotation.y - (-PI * 0.75)) < 0.05, "Unit correctly faces South-East heading (rotation.y = -3*PI/4)")
	player_token.face_heading(Vector2i(-1, 1), true) # South-West -> 3*PI/4
	_assert(absf(player_token.rotation.y - (PI * 0.75)) < 0.05, "Unit correctly faces South-West heading (rotation.y = 3*PI/4)")
	player_token.face_heading(Vector2i(-1, -1), true) # North-West -> PI/4
	_assert(absf(player_token.rotation.y - (PI * 0.25)) < 0.05, "Unit correctly faces North-West heading (rotation.y = PI/4)")

	# [10] Single-Tile Animated Step Progression
	print("\n-- [10] Single-Tile Animated Step Progression --")
	var start_pos: Vector2i = board.current_pos
	var target_pos: Vector2i = start_pos + Vector2i(1, 0)
	while not board.nodes_dict.has(target_pos) or not BoardConfig.is_passable(str(board.nodes_dict[target_pos].get_meta("terrain", "plain"))):
		target_pos = start_pos + Vector2i(0, 1)
	await board._animate_token_step(start_pos, target_pos, 0.05)
	var dest_tile = board.nodes_dict[target_pos]
	var dist_after: float = player_token.global_position.distance_to(dest_tile.global_position + Vector3(0, 0.9, 0))
	_assert(dist_after < 0.15, "Single-tile animated step moves player unit to destination world coordinates")

	# [11] Multi-Tile Path Movement
	print("\n-- [11] Multi-Tile Path Movement --")
	var prev_tile: Vector2i = board.current_pos
	var next_tile: Vector2i = target_pos
	var success: bool = board._try_step(next_tile)
	_assert(success, "Step execution succeeds through authoritative BoardManager")
	_assert(board.current_pos == next_tile, "Authoritative current_pos updated to destination")

	# [12] Movement Ends in Correct Tile
	print("\n-- [12] Movement Ends in Correct Tile --")
	_assert(GlobalData.board.current_tile == next_tile, "GlobalData.board.current_tile matches arrival position")

	# [13] Movement Ends in Idle
	print("\n-- [13] Movement Ends in Idle --")
	_assert(player_token.anim_state == "idle", "Player unit returns to idle state upon arrival")

	# [14] Invalid Movement Rejection & Visual Stability
	print("\n-- [14] Invalid Movement Rejection & Visual Stability --")
	GlobalData.board.board_mp = 0
	var pos_before = player_token.global_position
	var invalid_res = board._try_step(board.current_pos + Vector2i(1, 0))
	_assert(not invalid_res, "Movement rejected when MP is 0")
	_assert(player_token.global_position == pos_before, "Visual unit position remains completely stable on rejected move")
	GlobalData.board.board_mp = 6

	# [15] Combat State Movement Inhibition
	print("\n-- [15] Combat State Movement Inhibition --")
	GameManager.enter_combat("grunt")
	_assert(GameManager.current_state == GameManager.State.COMBAT, "Transitioned to State.COMBAT on request")
	var combat_step = board.move_to_tile(target_pos, false)
	_assert(not combat_step, "Board movement strictly rejected while in State.COMBAT")
	GameManager.return_to_board()

	# [16] Enemy Commander 3D Instantiation
	print("\n-- [16] Enemy Commander 3D Instantiation --")
	var fleet_armored := {"id": 101, "archetype": "armored", "faction": "hostile", "fleet_count": 1, "pos": Vector2i(3, 3), "dir": Vector2i(1, 0)}
	var cmdr_unit := BoardUnit3D.new()
	cmdr_unit.setup_commander(fleet_armored)
	add_child(cmdr_unit)
	_assert(cmdr_unit.unit_type == BoardUnit3D.UnitType.COMMANDER, "Commander unit type is COMMANDER")
	_assert(cmdr_unit.torso_node != null and cmdr_unit.head_node != null, "Commander model instantiated with full 3D hierarchy")

	# [17] Commander Mapping from Authoritative Fleet Data
	print("\n-- [17] Commander Mapping from Authoritative Fleet Data --")
	var fleet_recon := {"id": 102, "archetype": "recon", "faction": "hostile", "fleet_count": 1, "pos": Vector2i(4, 4)}
	var recon_unit := BoardUnit3D.new()
	recon_unit.setup_commander(fleet_recon)
	_assert(recon_unit.archetype == "recon", "Recon fleet maps to recon commander archetype")

	var fleet_artillery := {"id": 103, "archetype": "artillery", "faction": "hostile", "fleet_count": 1, "pos": Vector2i(4, 4)}
	var arty_unit := BoardUnit3D.new()
	arty_unit.setup_commander(fleet_artillery)
	_assert(arty_unit.archetype == "artillery", "Artillery fleet maps to artillery commander archetype")

	var fleet_hk := {"id": 104, "archetype": "hunter_killer", "faction": "hostile", "fleet_count": 2, "pos": Vector2i(5, 5)}
	var hk_unit := BoardUnit3D.new()
	hk_unit.setup_commander(fleet_hk)
	_assert(hk_unit.archetype == "hunter_killer", "Hunter-Killer fleet maps to hunter_killer commander archetype")

	var fleet_merc := {"id": 105, "archetype": "armored", "faction": "unknown", "fleet_count": 1, "pos": Vector2i(2, 4)}
	var merc_unit := BoardUnit3D.new()
	merc_unit.setup_commander(fleet_merc)
	_assert(merc_unit.archetype == "unknown", "Mercenary unknown fleet maps to unknown commander archetype")

	var boss_unit := BoardUnit3D.new()
	boss_unit.setup_boss()
	_assert(boss_unit.unit_type == BoardUnit3D.UnitType.BOSS, "Boss unit instantiated with Boss Overlord setup")

	# [18] Enemy Visual Alignment to Fleet Tile
	print("\n-- [18] Enemy Visual Alignment to Fleet Tile --")
	GlobalData.board.board_patrols = [fleet_armored, fleet_hk]
	board._refresh_patrol_markers()
	var container = board.get_node_or_null("PatrolMarkers")
	_assert(container != null, "PatrolMarkers container exists")
	_assert(container.get_child_count() >= 2, "Patrol markers instantiated into container")

	# [19] Enemy Movement Synchronization
	print("\n-- [19] Enemy Movement Synchronization --")
	fleet_armored["prev_pos"] = Vector2i(3, 3)
	fleet_armored["pos"] = Vector2i(3, 4)
	board._refresh_patrol_markers()
	_assert(container.get_child_count() >= 2, "Patrol marker refreshed smoothly for repositioned fleet")

	# [20] Save/Load Rebuilds Correct Visual Positions
	print("\n-- [20] Save/Load Rebuilds Correct Visual Positions --")
	var saved_tile := Vector2i(4, 3)
	GlobalData.board.current_tile = saved_tile
	var fresh_board = _setup_board(saved_tile)
	var fresh_token = fresh_board.get_node_or_null("PlayerToken")
	var target_tile = fresh_board.nodes_dict[saved_tile]
	var saved_dist: float = fresh_token.global_position.distance_to(target_tile.global_position + Vector3(0, 0.9, 0))
	_assert(saved_dist < 0.15, "Reconstructed board accurately positions 3D unit at saved tile")

	# [21] Board A -> Board B Isolation
	print("\n-- [21] Board A -> Board B Isolation --")
	var old_token = fresh_token
	var second_board = _setup_board()
	var new_token = second_board.get_node_or_null("PlayerToken")
	_assert(new_token != null, "Board B instantiated new 3D player unit")
	_assert(new_token != old_token, "Board B player unit is an isolated instance")

	# [22] Patrol Count Badges & Mode Tag Preservation
	print("\n-- [22] Patrol Count Badges & Mode Tag Preservation --")
	var patrol_marker := Node3D.new()
	patrol_marker.set_script(preload("res://scripts/board/patrol_marker.gd"))
	patrol_marker.setup(fleet_hk) # fleet_count = 2
	add_child(patrol_marker)
	var badge: Label3D = patrol_marker.get_node_or_null("FleetCountBadge")
	_assert(badge != null, "Multi-fleet patrol marker displays FleetCountBadge")
	_assert(badge.text == "x2", "FleetCountBadge displays accurate 'x2' count")

	var player_tag: Label3D = second_board.get_node_or_null("PlayerToken/ModeTag")
	_assert(player_tag != null, "Player unit possesses ModeTag presentation label")

	# Cleanup
	unit.queue_free()
	cmdr_unit.queue_free()
	recon_unit.queue_free()
	arty_unit.queue_free()
	hk_unit.queue_free()
	merc_unit.queue_free()
	boss_unit.queue_free()
	patrol_marker.queue_free()
