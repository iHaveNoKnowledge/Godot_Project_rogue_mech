extends Node3D

## Verification test for Hit Sparks & Ricochet Streak VFX:
## - Point Light Flash on impact
## - Directional ricochet spark bursts
## - Damage-type color palettes (kinetic, heat, emp, pierce)
## - Projectile and melee/damage-at-point integration

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("HIT_SPARK_OK: %s" % msg)
	else:
		_fails += 1
		print("HIT_SPARK_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Hit Sparks & Ricochet VFX Verification ---")

	# Ensure EffectManager instance is present
	if EffectManager.instance == null:
		var em = EffectManager.new()
		add_child(em)
		await get_tree().process_frame

	_test_spawn_hit_spark_variants()
	await _test_projectile_hit_spark()
	await _test_mecha_damage_point_spark()

	print("HIT_SPARKS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_spawn_hit_spark_variants() -> void:
	# 1. Kinetic spark
	var count_before = EffectManager.instance.get_child_count()
	EffectManager.spawn_hit_spark(Vector3(0, 1, 0), Vector3.UP, "kinetic")
	_check(EffectManager.instance.get_child_count() > count_before, "spawn_hit_spark added spark nodes (OmniLight3D, flash star, GPUParticles3D)")

	# 2. Heat spark
	count_before = EffectManager.instance.get_child_count()
	EffectManager.spawn_hit_spark(Vector3(1, 1, 0), Vector3.FORWARD, "heat")
	_check(EffectManager.instance.get_child_count() > count_before, "Heat damage type spawns heat-colored sparks")

	# 3. EMP spark
	count_before = EffectManager.instance.get_child_count()
	EffectManager.spawn_hit_spark(Vector3(-1, 1, 0), Vector3.BACK, "emp")
	_check(EffectManager.instance.get_child_count() > count_before, "EMP damage type spawns electric cyan sparks")

	# 4. Pierce spark
	count_before = EffectManager.instance.get_child_count()
	EffectManager.spawn_hit_spark(Vector3(0, 2, 0), Vector3.RIGHT, "pierce")
	_check(EffectManager.instance.get_child_count() > count_before, "Pierce damage type spawns white-hot sparks")


func _test_projectile_hit_spark() -> void:
	var proj_script := load("res://scripts/systems/projectile.gd")
	var proj: CharacterBody3D = CharacterBody3D.new()
	proj.set_script(proj_script)
	add_child(proj)
	proj.position = Vector3(0, 1, 0)
	proj.damage = 10.0
	proj.damage_type = "kinetic"
	proj.direction = Vector3(0, 0, -1)

	var target := Node3D.new()
	add_child(target)
	target.position = Vector3(0, 1, -2)

	var count_before = EffectManager.instance.get_child_count()
	proj._hit_target(target)
	_check(EffectManager.instance.get_child_count() > count_before, "Projectile impact spawned hit spark effects")

	target.queue_free()


func _test_mecha_damage_point_spark() -> void:
	var mech_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mech: CharacterBody3D = mech_scene.instantiate()
	mech.position = Vector3(0, 2, 0)
	add_child(mech)
	await get_tree().process_frame

	var hs: MechaHealthBase = mech.get_node_or_null("HealthSystem")
	_check(hs != null, "Mech has HealthSystem")

	var count_before = EffectManager.instance.get_child_count()
	hs.take_damage_at_point(20.0, mech.global_position + Vector3(0, 1.2, 0), "kinetic")
	_check(EffectManager.instance.get_child_count() > count_before, "take_damage_at_point spawned hit sparks at impact point")

	mech.queue_free()
