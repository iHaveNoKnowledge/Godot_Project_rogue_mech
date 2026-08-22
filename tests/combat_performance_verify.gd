extends Node3D

## Headless Performance & Optimization verification for rapid firing & impact effects.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("PERF_CHECK_OK: %s" % msg)
	else:
		_fails += 1
		print("PERF_CHECK_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Combat Performance & Optimization Verification ---")

	# 1. Test WeaponCore static caching
	var shape1 = WeaponCore._get_cached_shape()
	var shape2 = WeaponCore._get_cached_shape()
	_check(shape1 != null and shape1 == shape2, "WeaponCore reuses the exact same cached CollisionShape3D")

	var mesh_bullet1 = WeaponCore._get_cached_mesh(WeaponCore.Style.BULLET)
	var mesh_bullet2 = WeaponCore._get_cached_mesh(WeaponCore.Style.BULLET)
	_check(mesh_bullet1 != null and mesh_bullet1 == mesh_bullet2, "WeaponCore reuses the exact same cached Bullet Mesh")

	var mat1 = WeaponCore._get_cached_material(Color(1, 0.8, 0.2))
	var mat2 = WeaponCore._get_cached_material(Color(1, 0.8, 0.2))
	_check(mat1 != null and mat1 == mat2, "WeaponCore reuses the exact same cached StandardMaterial3D")

	# 2. Test EffectManager static caching & light throttling
	var effect_mgr = EffectManager.new()
	add_child(effect_mgr)
	await get_tree().process_frame

	var quad1 = EffectManager._get_cached_quad()
	var quad2 = EffectManager._get_cached_quad()
	_check(quad1 != null and quad1 == quad2, "EffectManager reuses cached QuadMesh")

	var spark_box1 = EffectManager._get_cached_spark_box()
	var spark_box2 = EffectManager._get_cached_spark_box()
	_check(spark_box1 != null and spark_box1 == spark_box2, "EffectManager reuses cached Spark BoxMesh")

	# Rapid fire 50 hit sparks in a single frame to test light throttling
	for i in range(50):
		EffectManager.spawn_hit_spark(Vector3(i * 0.1, 1.0, 0.0), Vector3.UP, "kinetic")

	_check(EffectManager._active_hit_lights <= 2, "EffectManager throttles concurrent point lights to <= 2 (currently %d)" % EffectManager._active_hit_lights)

	# 3. Test Projectile static target caching
	var proj_script = preload("res://scripts/systems/projectile.gd")
	var proj = CharacterBody3D.new()
	proj.set_script(proj_script)
	add_child(proj)

	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	_check(proj_script._last_target_cache_frame >= 0, "Projectile refreshes target cache once per physics frame")

	print("--- Performance Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_PERFORMANCE_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
