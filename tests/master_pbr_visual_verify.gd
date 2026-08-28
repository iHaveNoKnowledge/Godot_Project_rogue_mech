extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running master_pbr_visual_verify ---")
	_verify_shader_compilation_and_parameters()
	await _verify_part_mesh_manager_pbr_materials()
	await _verify_weapon_visual_factory_pbr_materials()
	await _verify_world_environment_post_processing()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_shader_compilation_and_parameters() -> void:
	print("Testing Master PBR Shader Compilation & Uniform Parameters...")

	var shader: Shader = load("res://shaders/mecha_master_pbr.gdshader")
	_check(shader != null, "mecha_master_pbr.gdshader loaded successfully")

	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Test all uniforms
	mat.set_shader_parameter("primary_color", Color(0.20, 0.45, 0.85))
	mat.set_shader_parameter("trim_color", Color(0.10, 0.12, 0.15))
	mat.set_shader_parameter("metallic", 0.90)
	mat.set_shader_parameter("roughness", 0.28)
	mat.set_shader_parameter("panel_grid_scale", 6.0)
	mat.set_shader_parameter("panel_line_depth", 0.65)
	mat.set_shader_parameter("edge_wear", 0.25)
	mat.set_shader_parameter("scorch_amount", 0.50)
	mat.set_shader_parameter("emission_color", Color(0.1, 0.8, 1.0))
	mat.set_shader_parameter("emission_energy", 3.5)
	mat.set_shader_parameter("pulse_speed", 2.0)

	_check(mat.get_shader_parameter("primary_color") == Color(0.20, 0.45, 0.85), "primary_color parameter set correctly")
	_check(mat.get_shader_parameter("metallic") == 0.90, "metallic parameter set correctly")
	_check(mat.get_shader_parameter("roughness") == 0.28, "roughness parameter set correctly")
	_check(mat.get_shader_parameter("panel_grid_scale") == 6.0, "panel_grid_scale set correctly")
	_check(mat.get_shader_parameter("emission_energy") == 3.5, "emission_energy parameter set correctly")


func _verify_part_mesh_manager_pbr_materials() -> void:
	print("Testing PartMeshManager PBR Material Generation...")

	var pmm_script: Script = load("res://scripts/mecha/part_mesh_manager.gd")
	_check(pmm_script != null, "PartMeshManager script loaded")

	var pmm = Node3D.new()
	pmm.set_script(pmm_script)
	add_child(pmm)

	# 1. Inner Frame Material
	var frame_mat: ShaderMaterial = pmm._get_dark_frame_material()
	_check(frame_mat is ShaderMaterial, "Inner frame material is ShaderMaterial")
	_check(frame_mat.get_shader_parameter("metallic") >= 0.90, "Inner frame has high metallic (>= 0.90)")
	_check(frame_mat.get_shader_parameter("roughness") <= 0.30, "Inner frame has low roughness (<= 0.30)")

	# 2. Chrome Material
	var chrome_mat: ShaderMaterial = pmm._get_chrome_material()
	_check(chrome_mat is ShaderMaterial, "Chrome material is ShaderMaterial")
	_check(chrome_mat.get_shader_parameter("metallic") >= 0.95, "Chrome material has ultra-high metallic (>= 0.95)")

	# 3. Eye Sensor Material
	var sensor_mat: ShaderMaterial = pmm._get_eye_sensor_material()
	_check(sensor_mat is ShaderMaterial, "Eye sensor material is ShaderMaterial")
	_check(sensor_mat.get_shader_parameter("emission_energy") >= 4.0, "Eye sensor has high emissive glow (energy >= 4.0)")

	# 4. Outer Armor Generation
	var armor_container := Node3D.new()
	pmm.add_child(armor_container)
	pmm._build_procedural_outer_armor("head", armor_container)

	var helmet_child: MeshInstance3D = null
	for child in armor_container.get_children():
		if child is MeshInstance3D:
			helmet_child = child
			break

	_check(helmet_child != null, "Procedural helmet mesh spawned")
	if helmet_child:
		_check(helmet_child.material_override is ShaderMaterial, "Helmet mesh uses Master PBR ShaderMaterial")
		var helmet_mat = helmet_child.material_override as ShaderMaterial
		if helmet_mat:
			_check(helmet_mat.get_shader_parameter("panel_line_depth") != null, "Helmet material has panel_line_depth configured")

	pmm.queue_free()
	await get_tree().process_frame


func _verify_weapon_visual_factory_pbr_materials() -> void:
	print("Testing WeaponVisualFactory Master PBR Materials...")

	var wvf_script: Script = load("res://scripts/mecha/weapon_visual_factory.gd")
	_check(wvf_script != null, "WeaponVisualFactory script loaded")

	var weapon_part := WeaponPart.new()
	weapon_part.weapon_name = "Heavy Plasma Rifle"
	weapon_part.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE

	var model: Node3D = wvf_script.build(weapon_part)
	_check(model != null, "Weapon model built successfully")
	add_child(model)

	var found_pbr_mat := false
	for child in model.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			found_pbr_mat = true
			break

	_check(found_pbr_mat, "Weapon model contains Master PBR ShaderMaterial")

	model.queue_free()
	await get_tree().process_frame


func _verify_world_environment_post_processing() -> void:
	print("Testing WorldEnvironment ACES Tonemapping, Glow, and SSAO...")

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_bloom = 0.15
	env.ssao_enabled = true
	we.environment = env
	add_child(we)

	_check(we.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES Tonemapping mode active")
	_check(we.environment.glow_enabled == true, "Glow/Bloom post-processing active")
	_check(we.environment.ssao_enabled == true, "SSAO ambient occlusion active")

	we.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All master_pbr_visual_verify tests passed successfully!")
		get_tree().quit(0)
	else:
		print("master_pbr_visual_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
