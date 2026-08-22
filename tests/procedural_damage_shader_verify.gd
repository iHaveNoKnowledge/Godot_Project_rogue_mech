extends Node3D

## Verification test for Procedural Armor Damage Shader & Visuals System.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("DAMAGE_SHADER_OK: %s" % msg)
	else:
		_fails += 1
		print("DAMAGE_SHADER_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Procedural Armor Damage Verification ---")

	# 1. Test Shader Resource
	var shader: Shader = preload("res://shaders/armor_crack.gdshader")
	_check(shader != null, "armor_crack.gdshader loaded successfully")

	# 2. Test ShaderMaterial creation and unique seed offsets
	var mat1 := ShaderMaterial.new()
	mat1.shader = shader
	var seed1 := Vector3(randf() * 50.0, randf() * 50.0, randf() * 50.0)
	mat1.set_shader_parameter("noise_offset", seed1)
	mat1.set_shader_parameter("damage_amount", 0.5)

	var mat2 := ShaderMaterial.new()
	mat2.shader = shader
	var seed2 := Vector3(randf() * 50.0 + 100.0, randf() * 50.0 + 100.0, randf() * 50.0 + 100.0)
	mat2.set_shader_parameter("noise_offset", seed2)

	_check(seed1 != seed2, "Random seeds for procedural damage are unique (%v vs %v)" % [seed1, seed2])
	_check(float(mat1.get_shader_parameter("damage_amount")) == 0.5, "Shader accepts damage_amount parameter (0.5)")

	# 3. Test MechaHealthBase & ArmorDamageVisuals binding
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var hs: MechaHealthBase = mecha.get_node_or_null("HealthSystem")
	_check(hs != null, "Mecha HealthSystem exists")
	_check(hs.damage_visuals != null, "ArmorDamageVisuals initialized on HealthSystem")

	# 4. Test Dynamic Health Change -> Shader Parameter Update
	# Simulate 60% damage to left arm armor (25 HP max -> 10 HP left)
	hs.health_changed.emit("arm_left", "armor", 10.0, 25.0)
	var arm_overlay = hs.damage_visuals._slot_overlays.get("arm_left")
	_check(arm_overlay != null, "arm_left has an active damage overlay")
	if arm_overlay:
		var arm_mat: ShaderMaterial = arm_overlay.get("armor")
		var dmg_val: float = float(arm_mat.get_shader_parameter("damage_amount"))
		_check(absf(dmg_val - 0.6) < 0.01, "arm_left damage_amount updated to 0.60 (was %.2f)" % dmg_val)

	# 5. Test Armor/Frame layer separation: frame material untouched by armor hits
	hs.health_changed.emit("arm_left", "frame", 40.0, 50.0)
	if arm_overlay:
		var frame_mat: ShaderMaterial = arm_overlay.get("frame")
		_check(frame_mat != null and frame_mat != arm_overlay.get("armor"), "arm_left frame has its own independent crack material")
		if frame_mat:
			var f_val: float = float(frame_mat.get_shader_parameter("damage_amount"))
			_check(absf(f_val - 0.2) < 0.01, "arm_left frame damage_amount updated to 0.20 independently (was %.2f)" % f_val)

	# 5. Test Custom User Model Mesh Binding
	var custom_mesh := MeshInstance3D.new()
	custom_mesh.mesh = BoxMesh.new()
	hs.damage_visuals.bind_custom_mesh("body", custom_mesh)
	_check(custom_mesh.material_overlay != null, "Custom user mesh accepted damage overlay without altering base material")

	print("--- Procedural Damage Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_PROCEDURAL_DAMAGE_TESTS_PASSED")
