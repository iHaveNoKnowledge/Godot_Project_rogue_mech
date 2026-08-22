extends Node3D

## Automated Verification for Dynamic Start/Exit, Board Sunlight, Terrain Color Rendering, and Roaming Boss Fleet.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("DYNAMIC_BOARD_OK: %s" % msg)
	else:
		_fails += 1
		print("DYNAMIC_BOARD_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Dynamic Start, Lighting & Roaming Boss Verification ---")

	# 1. Test Dynamic Start & Exit in BoardGenerator
	var gen_scene = preload("res://scripts/board/board_generator.gd")
	var generator = gen_scene.new()
	add_child(generator)

	var data: Dictionary = generator.generate_board()
	var start_pos: Vector2i = data.get("start_pos", Vector2i(-1, -1))
	var exit_pos: Vector2i = data.get("exit_pos", Vector2i(-1, -1))
	var tile_types: Dictionary = data.get("tile_types", {})

	_check(start_pos != Vector2i(-1, -1), "Generated dynamic start position at %s" % str(start_pos))
	_check(exit_pos != Vector2i(-1, -1), "Generated dynamic exit position at %s" % str(exit_pos))
	_check(tile_types.get(start_pos) == "start", "Tile at start_pos is marked as 'start'")
	_check(tile_types.get(exit_pos) == "exit", "Tile at exit_pos is marked as 'exit'")

	# 2. Test Lighting and Environment
	var lighting: Node3D = generator.build_environment_and_light()
	_check(lighting != null, "Created BoardLighting container")
	_check(lighting.get_node_or_null("SunLight") is DirectionalLight3D, "Found DirectionalLight3D SunLight for vibrant board illumination")
	_check(lighting.get_node_or_null("BoardWorldEnv") is WorldEnvironment, "Found WorldEnvironment for ambient illumination")

	# 3. Test Terrain Shader Color Rendering (No black tile bug)
	var nodes: Dictionary = data.get("nodes", {})
	var sample_tile = nodes.values()[0]
	add_child(sample_tile)
	sample_tile._update_visual()
	var mesh_inst: MeshInstance3D = sample_tile.get_node_or_null("MeshInstance3D")
	var smat: ShaderMaterial = mesh_inst.get_surface_override_material(0) as ShaderMaterial
	_check(smat != null, "Tile has active ShaderMaterial")
	if smat:
		var base_col: Color = smat.get_shader_parameter("base_color") as Color
		_check(base_col.r > 0.05 or base_col.g > 0.05 or base_col.b > 0.05, "Tile base_color is brightly tinted (color=%s)" % str(base_col))

	# 4. Test Roaming Sector Supreme Commander (Boss)
	GlobalData.board.board_patrols.clear()
	PatrolSystem.spawn_patrols()
	var boss_found := false
	for patrol in GlobalData.board.board_patrols:
		if patrol.get("is_boss", false) or patrol.get("archetype", "") == "boss":
			boss_found = true
			print("Found Roaming Boss: %s at %s with %d aces" % [patrol.get("name", ""), str(patrol.get("pos", "")), patrol.get("aces", 0)])
			break

	_check(boss_found, "Roaming Sector Supreme Commander (Boss) successfully spawned in Fog of War")

	print("--- Dynamic Start, Lighting & Roaming Boss Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_DYNAMIC_START_LIGHTING_BOSS_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
