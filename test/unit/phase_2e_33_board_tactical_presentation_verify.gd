extends Node

## Phase 2E-33: Board Tactical Presentation & Readability Verification
## Verifies that Board units are immediately readable, visually clean,
## tactically distinguishable (Player / Enemy Archetypes / Boss), have correct
## scaling, grounding, facing, non-occluding badges/tags, and support multi-unit
## coexistence without any loss of authoritative identity.

const BoardUnit3D = preload("res://scripts/board/board_unit_3d.gd")
const PatrolMarker = preload("res://scripts/board/patrol_marker.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _board_scene: Node3D = null


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-33 BOARD TACTICAL PRESENTATION & READABILITY AUDIT ===\n")
	GameManager.suppress_scene_change = true

	await _run_all_tests()

	print("\n==================================================")
	print("PHASE 2E-33 PRESENTATION AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	print("==================================================")

	if _fail_count == 0:
		print("PHASE_2E_33_SUCCESS\n")
	else:
		push_error("PHASE_2E_33_FAILURE: %d assertions failed" % _fail_count)

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
	GlobalData.fuel.traversal_mode = "mecha"
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
	# [1] Player Tactical Identity & Base Ring Presentation
	print("-- [1] Player Tactical Identity & Base Ring Presentation --")
	var player_unit := BoardUnit3D.new()
	player_unit.setup_player()
	add_child(player_unit)
	_assert(player_unit.unit_type == BoardUnit3D.UnitType.PLAYER, "Player unit is configured as PLAYER")
	_assert(player_unit.unit_scale.is_equal_approx(Vector3(0.58, 0.58, 0.58)), "Player unit scale is well-proportioned for 4.0m tiles (0.58)")
	_assert(player_unit.tactical_ring != null, "Player unit possesses TacticalRing node")
	
	var ring_mesh = player_unit.tactical_ring.get_node_or_null("RingMesh") as MeshInstance3D
	_assert(ring_mesh != null, "TacticalRing contains RingMesh")
	var ring_mat = ring_mesh.material_override as StandardMaterial3D
	_assert(ring_mat != null and ring_mat.albedo_color.b > 0.6, "Player TacticalRing has electric cyan/blue hue")
	
	var heading_ptr = player_unit.tactical_ring.get_node_or_null("HeadingPointer") as MeshInstance3D
	_assert(heading_ptr != null, "TacticalRing contains HeadingPointer chevron")
	_assert(heading_ptr.position.z < -0.8, "HeadingPointer is positioned at forward edge (-Z)")

	# [2] Enemy Commander Archetype Rings & Production Scenes
	print("\n-- [2] Enemy Commander Archetype Rings & Production Scenes --")
	var archetypes_to_test := [
		{"arch": "armored", "scene": "enemy_heavy", "color_check": func(c: Color): return c.r > 0.7 and c.b < 0.3},
		{"arch": "recon", "scene": "enemy_ranged", "color_check": func(c: Color): return c.r > 0.8 and c.g > 0.3 and c.b < 0.2},
		{"arch": "artillery", "scene": "enemy_support", "color_check": func(c: Color): return c.r > 0.8 and c.g > 0.6},
		{"arch": "hunter_killer", "scene": "enemy_shield_melee", "color_check": func(c: Color): return c.r > 0.7 and c.b > 0.3},
	]

	for entry in archetypes_to_test:
		var cmdr_unit := BoardUnit3D.new()
		cmdr_unit.setup_commander({"archetype": entry["arch"], "faction": "hostile"})
		add_child(cmdr_unit)
		_assert(cmdr_unit.unit_type == BoardUnit3D.UnitType.COMMANDER, "Commander %s has type COMMANDER" % entry["arch"])
		_assert(cmdr_unit.production_model != null, "Commander %s instantiated production model" % entry["arch"])
		_assert(cmdr_unit.production_model.scene_file_path.contains(entry["scene"]), "Commander %s model matches %s" % [entry["arch"], entry["scene"]])
		_assert(cmdr_unit.tactical_ring != null, "Commander %s possesses TacticalRing" % entry["arch"])
		var c_ring_mesh = cmdr_unit.tactical_ring.get_node_or_null("RingMesh") as MeshInstance3D
		var c_mat = c_ring_mesh.material_override as StandardMaterial3D
		var color_valid: bool = entry["color_check"].call(c_mat.albedo_color)
		_assert(color_valid, "Commander %s TacticalRing has distinct archetype color" % entry["arch"])
		cmdr_unit.queue_free()

	# [3] Boss Overlord Presentation
	print("\n-- [3] Boss Overlord Presentation --")
	var boss_unit := BoardUnit3D.new()
	boss_unit.setup_boss()
	add_child(boss_unit)
	_assert(boss_unit.unit_type == BoardUnit3D.UnitType.BOSS, "Boss unit has type BOSS")
	_assert(boss_unit.unit_scale.is_equal_approx(Vector3(0.68, 0.68, 0.68)), "Boss unit has imposing scale (0.68)")
	_assert(boss_unit.production_model != null and boss_unit.production_model.scene_file_path.contains("enemy_boss"), "Boss unit instantiates enemy_boss.tscn")
	var b_ring_mesh = boss_unit.tactical_ring.get_node_or_null("RingMesh") as MeshInstance3D
	var b_mat = b_ring_mesh.material_override as StandardMaterial3D
	_assert(b_mat != null and b_mat.albedo_color.r > 0.5 and b_mat.albedo_color.b > 0.8, "Boss TacticalRing has distinctive violet hue")
	boss_unit.queue_free()

	# [4] 8-Direction Facing & Heading Pointer Alignment
	print("\n-- [4] 8-Direction Facing & Heading Pointer Alignment --")
	var dirs := [
		{"dir": Vector2i(0, -1), "expected_yaw": 0.0, "name": "North"},
		{"dir": Vector2i(1, -1), "expected_yaw": -PI * 0.25, "name": "North-East"},
		{"dir": Vector2i(1, 0), "expected_yaw": -PI * 0.5, "name": "East"},
		{"dir": Vector2i(1, 1), "expected_yaw": -PI * 0.75, "name": "South-East"},
		{"dir": Vector2i(0, 1), "expected_yaw": PI, "name": "South"},
		{"dir": Vector2i(-1, 1), "expected_yaw": PI * 0.75, "name": "South-West"},
		{"dir": Vector2i(-1, 0), "expected_yaw": PI * 0.5, "name": "West"},
		{"dir": Vector2i(-1, -1), "expected_yaw": PI * 0.25, "name": "North-West"},
	]

	for d in dirs:
		player_unit.face_heading(d["dir"], true)
		var diff = wrapf(player_unit.rotation.y - d["expected_yaw"], -PI, PI)
		_assert(absf(diff) < 0.05, "Unit facing %s heading rotates to target yaw" % d["name"])

	player_unit.queue_free()

	# [5] FleetCountBadge Non-Occlusion & Scaling
	print("\n-- [5] FleetCountBadge Non-Occlusion & Scaling --")
	var single_patrol_marker := PatrolMarker.new()
	single_patrol_marker.setup({"archetype": "armored", "fleet_count": 1, "dir": Vector2i(1, 0)})
	add_child(single_patrol_marker)
	_assert(single_patrol_marker.get_node_or_null("FleetCountBadge") == null, "Single-fleet patrol (count=1) does not spawn unnecessary badge")
	single_patrol_marker.queue_free()

	var multi_patrol_marker := PatrolMarker.new()
	multi_patrol_marker.setup({"archetype": "armored", "fleet_count": 3, "dir": Vector2i(1, 0)})
	add_child(multi_patrol_marker)
	var badge = multi_patrol_marker.get_node_or_null("FleetCountBadge") as Label3D
	_assert(badge != null, "Multi-fleet patrol (count=3) spawns FleetCountBadge")
	_assert(badge.text == "x3", "FleetCountBadge displays 'x3'")
	_assert(badge.position.y >= 2.0, "FleetCountBadge is elevated above mecha shoulder/head (y >= 2.0m) to preserve silhouette")
	_assert(badge.position.x > 0.4, "FleetCountBadge is offset to the side (x > 0.4m)")
	multi_patrol_marker.queue_free()

	# [6] ModeTag Non-Occlusion on Board
	print("\n-- [6] ModeTag Non-Occlusion on Board --")
	var board := _setup_board(Vector2i(2, 2))
	var player_token = board.get_node_or_null("PlayerToken") as BoardUnit3D
	_assert(player_token != null, "PlayerToken exists on board")
	board._update_token_position()
	var mode_tag = player_token.get_node_or_null("ModeTag") as Label3D
	_assert(mode_tag != null, "ModeTag exists on PlayerToken")
	_assert(mode_tag.position.y >= 2.4, "ModeTag floats cleanly above player Valkren head (y >= 2.4m)")

	# [7] Multi-Unit Coexistence & Separation (Player + Adjacent Enemies)
	print("\n-- [7] Multi-Unit Coexistence & Separation --")
	GlobalData.board.board_patrols = [
		{"pos": Vector2i(2, 2), "dir": Vector2i(1, 0), "archetype": "armored", "fleet_count": 1, "name": "Vanguard"},
		{"pos": Vector2i(2, 3), "dir": Vector2i(0, 1), "archetype": "recon", "fleet_count": 2, "name": "Scouts"},
		{"pos": Vector2i(3, 2), "dir": Vector2i(-1, 0), "archetype": "hunter_killer", "fleet_count": 1, "name": "Elite Strike"},
	]
	board._refresh_patrol_markers()

	var patrol_container = board.get_node_or_null("PatrolMarkers")
	_assert(patrol_container != null and patrol_container.get_child_count() >= 3, "All patrol markers instantiated simultaneously")
	
	# Check shared-tile separation at (2,2)
	board._update_token_position()
	var tile_pos = board.nodes_dict[Vector2i(2, 2)].global_position
	var p_pos = player_token.global_position
	_assert(p_pos.x < tile_pos.x, "Player token is offset West (-0.55m) on shared tile to prevent overlap")
	
	var shared_marker = patrol_container.get_child(0)
	_assert(shared_marker.global_position.x > tile_pos.x, "Patrol token is offset East (+0.55m) on shared tile to prevent overlap")
	var separation = absf(shared_marker.global_position.x - p_pos.x)
	_assert(separation >= 1.0, "Physical separation between player and enemy on same tile is >= 1.0m (clear side-by-side spacing)")

	# [8] Board Lighting & Rim Readability
	print("\n-- [8] Board Lighting & Rim Readability --")
	var bg = board.get_node_or_null("BoardGenerator")
	var lighting = bg.build_environment_and_light()
	_assert(lighting != null, "BoardLighting is built")
	var sun = lighting.get_node_or_null("SunLight") as DirectionalLight3D
	_assert(sun != null and sun.shadow_enabled, "SunLight is configured with soft shadows")
	var fill = lighting.get_node_or_null("FillLight") as DirectionalLight3D
	_assert(fill != null, "FillLight exists for rim separation on dark production armor")
	_assert(fill.light_energy >= 0.5, "FillLight energy is adequate for tactical readability")
	lighting.queue_free()

	# [9] Locomotion & Stance Transitions
	print("\n-- [9] Locomotion & Stance Transitions --")
	player_token.play_run()
	_assert(player_token.anim_state == "run" and player_token.is_moving, "Unit transitions to run state smoothly")
	player_token.play_idle()
	_assert(player_token.anim_state == "idle" and not player_token.is_moving, "Unit transitions back to idle stance smoothly")
