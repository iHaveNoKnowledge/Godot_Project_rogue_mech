extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running river_bridge_visual_verify ---")
	_test_river_bridge_arena_generation()

	print("RIVER_BRIDGE_VISUAL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_river_bridge_arena_generation() -> void:
	# Set board state to river/bridge encounter
	GlobalData.reset_run_data()
	GlobalData.board.board_theme_id = "forest"
	GlobalData.board.combat_tile_terrain = "bridge"

	var arena_gen_script = load("res://scripts/arena/arena_generator.gd")
	var arena_gen = arena_gen_script.new()
	add_child(arena_gen)

	_check(arena_gen.current_theme == 3, "Arena current_theme resolved to RIVER_BRIDGE (3)")

	var struct_container = arena_gen.get_node_or_null("ThemeStructures")
	_check(struct_container != null, "ThemeStructures container created")

	# Check Water volumes
	var water_volumes := []
	for child in struct_container.get_children():
		if child is Area3D and child.is_in_group("water_volume"):
			water_volumes.append(child)
	_check(water_volumes.size() >= 4, "Generated %d water volume sections across river" % water_volumes.size())

	if not water_volumes.is_empty():
		var first_water = water_volumes[0]
		var mesh_inst: MeshInstance3D = null
		for c in first_water.get_children():
			if c is MeshInstance3D:
				mesh_inst = c
				break
		_check(mesh_inst != null, "Water volume contains MeshInstance3D visual surface")
		if mesh_inst:
			var mat = mesh_inst.material_override
			_check(mat is ShaderMaterial, "Water surface uses custom ShaderMaterial")
			if mat is ShaderMaterial:
				_check(mat.shader != null, "Water shader is compiled")
				_check(mat.get_shader_parameter("normal_map1") != null, "Water shader has normal_map1 parameter assigned")

	# Check Bridge static bodies and riverbed
	var bridges := []
	var riverbed: StaticBody3D = null
	for child in struct_container.get_children():
		if child is StaticBody3D:
			if child.get_child_count() > 10:
				bridges.append(child)
			elif child.get_child_count() >= 2 and child.position.y < -1.0:
				riverbed = child

	_check(riverbed != null, "Submerged riverbed StaticBody3D generated at Y = -1.5")
	_check(not bridges.is_empty(), "Main central steel & asphalt bridge generated")

	if not bridges.is_empty():
		var main_b = bridges[0]
		var child_meshes := 0
		var has_asphalt := false
		var has_concrete := false
		var has_steel_truss := false
		var has_yellow_lines := false
		for c in main_b.get_children():
			if c is MeshInstance3D:
				child_meshes += 1
				var mat = c.material_override
				if mat is StandardMaterial3D:
					if mat.roughness > 0.85 and mat.metallic < 0.05 and mat.normal_enabled:
						has_asphalt = true
					if mat.albedo_texture != null or mat.albedo_color.r > 0.45:
						has_concrete = true
					if mat.metallic > 0.5 and mat.albedo_color.r > 0.6:
						has_steel_truss = true
					if mat.albedo_color.r > 0.9 and mat.albedo_color.g > 0.7:
						has_yellow_lines = true

		_check(child_meshes >= 15, "Main bridge has detailed architecture (%d mesh parts)" % child_meshes)
		_check(has_asphalt, "Main bridge has textured asphalt roadway surface")
		_check(has_yellow_lines, "Main bridge has painted road dividing lane stripes")
		_check(has_concrete, "Main bridge has concrete sidewalks / safety barriers / piers")
		_check(has_steel_truss, "Main bridge has industrial structural steel truss arch")

	arena_gen.queue_free()
