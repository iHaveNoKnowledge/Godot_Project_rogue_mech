extends Node3D

## Verification test for 3D Starburst Spike Muzzle Flash Mesh:
## Validates that muzzle flashes use procedural sharp star/spike flame geometry instead of simple ovals/spheres.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("MUZZLE_OK: %s" % msg)
	else:
		_fails += 1
		print("MUZZLE_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Muzzle Flash Star Mesh Verification ---")

	# 1. Verify EffectManager instance
	var em := EffectManager.new()
	add_child(em)
	EffectManager.instance = em
	_check(EffectManager.instance != null, "EffectManager initialized")

	# 2. Verify Starburst Spike Mesh generation
	var star_mesh: ArrayMesh = EffectManager._get_muzzle_star_mesh()
	_check(star_mesh != null, "Starburst spike mesh generated")
	if star_mesh:
		_check(star_mesh.get_surface_count() > 0, "Starburst mesh has valid surface data")
		var aabb: AABB = star_mesh.get_aabb()
		_check(aabb.size.z > 0.5, "Starburst mesh has forward flame spike length (%.2fm > 0.5m)" % aabb.size.z)
		_check(aabb.size.x > 0.2, "Starburst mesh has lateral muzzle brake vent spread (%.2fm > 0.2m)" % aabb.size.x)

	# 3. Test spawn_muzzle_flash execution
	EffectManager.spawn_muzzle_flash(Vector3(0, 1.5, 0), Vector3(0, 0, -1), Color(1.0, 0.8, 0.2))
	await get_tree().physics_frame
	_check(em.get_child_count() > 0, "Spawned muzzle flash mesh instance and dynamic flash light")

	em.queue_free()

	print("MUZZLE_FLASH_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
