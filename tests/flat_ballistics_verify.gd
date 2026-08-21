extends Node3D

## Verification test for Direct Flat Ballistics (No bullet drop for standard weapons):
## Ensures standard weapon projectiles fly 100% straight to crosshair aim point
## without dropping, while allowing dedicated mortar/grenade weapons to specify drop_gravity.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("BALLISTICS_OK: %s" % msg)
	else:
		_fails += 1
		print("BALLISTICS_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Direct Flat Ballistics Verification ---")

	var proj_script = load("res://scripts/systems/projectile.gd")

	# 1. Standard Projectile: drop_gravity = 0.0 (Direct fire)
	var standard_proj = CharacterBody3D.new()
	standard_proj.set_script(proj_script)
	standard_proj.speed = 100.0
	standard_proj.direction = Vector3(0, 0, -1)
	add_child(standard_proj)

	_check(standard_proj.drop_gravity == 0.0, "Standard projectile has drop_gravity = 0.0 by default")

	# Simulate 1.0 second of flight (100 meters traveled)
	for i in range(60):
		standard_proj._physics_process(1.0 / 60.0)

	_check(is_equal_approx(standard_proj.position.y, 0.0), "Standard projectile flew 100m with ZERO bullet drop (position.y=%.4f)" % standard_proj.position.y)
	_check(is_equal_approx(standard_proj.position.z, -100.0), "Standard projectile reached z=-100m on direct crosshair line")

	# 2. Dedicated Mortar/Grenade Projectile with custom drop_gravity > 0.0
	var mortar_proj = CharacterBody3D.new()
	mortar_proj.set_script(proj_script)
	mortar_proj.speed = 40.0
	mortar_proj.direction = Vector3(0, 0.5, -1).normalized()
	mortar_proj.drop_gravity = 12.0
	mortar_proj.drop_start_distance = 5.0
	add_child(mortar_proj)

	for i in range(60):
		mortar_proj._physics_process(1.0 / 60.0)

	_check(mortar_proj.position.y < 20.0, "Mortar projectile with drop_gravity=12.0 drops over distance as expected")

	standard_proj.queue_free()
	mortar_proj.queue_free()

	print("FLAT_BALLISTICS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
