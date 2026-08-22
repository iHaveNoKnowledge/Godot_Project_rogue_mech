extends Node3D

## Automated Verification for High-Velocity Needle Spark Streaks, Starburst Impact Flash, and Snapping Armor Micro-Arcs.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("IMPACT_VFX_OK: %s" % msg)
	else:
		_fails += 1
		print("IMPACT_VFX_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Impact Sparks & Needle Streaks Verification ---")

	# 1. Setup EffectManager instance
	var fx_mgr := EffectManager.new()
	add_child(fx_mgr)
	EffectManager.instance = fx_mgr

	# 2. Test Mesh Generation Helpers
	var starburst_mesh := EffectManager._get_cached_impact_starburst()
	_check(starburst_mesh != null and starburst_mesh is ArrayMesh, "Generated 8-point Starburst Impact Flash Mesh")

	var needle_mesh := EffectManager._get_cached_needle_spark_box()
	_check(needle_mesh != null and needle_mesh.size.z >= 0.35, "Generated high-velocity Needle Streak Spark Box Mesh (len=%.2f)" % needle_mesh.size.z)

	var arc_mesh := EffectManager._get_cached_micro_arc_box()
	_check(arc_mesh != null and arc_mesh.size.x <= 0.05, "Generated snapping Micro-Arc / Molten Debris Spark Box Mesh")

	# 3. Test spawn_hit_spark Spawning Children
	var initial_children := fx_mgr.get_child_count()
	EffectManager.spawn_hit_spark(Vector3(0, 1.5, 0), Vector3.UP, "kinetic")
	var new_children := fx_mgr.get_child_count()

	_check(new_children > initial_children, "spawn_hit_spark spawned %d impact VFX nodes (Flash/Starburst/Needles/Arcs)" % (new_children - initial_children))

	# 4. Test Damage Types (Heat, Pierce, EMP)
	EffectManager.spawn_hit_spark(Vector3(1, 1.5, 0), Vector3.RIGHT, "heat")
	EffectManager.spawn_hit_spark(Vector3(-1, 1.5, 0), Vector3.LEFT, "emp")
	EffectManager.spawn_hit_spark(Vector3(0, 1.5, 1), Vector3.FORWARD, "pierce")

	_check(fx_mgr.get_child_count() >= 8, "Successfully spawned colored multi-element impact spark bursts (total nodes=%d)" % fx_mgr.get_child_count())

	print("--- Impact Sparks & Needle Streaks Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_IMPACT_VFX_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
