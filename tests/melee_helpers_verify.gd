extends Node

## Headless verification of the shared melee helpers in EffectManager:
##   spawn_melee_trail() -> 5 fading box meshes on the current scene
##   melee_hit_ray()      -> collision-based hit, wall whiff, damage applied
## Run: godot --headless --path . res://tests/melee_helpers_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_trail()
	await _verify_hit()
	await _verify_wall_whiff()
	await _verify_player_mask()
	print("MELEE_HELPERS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _trail_nodes() -> Array:
	var found: Array = []
	for child in get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			found.append(child)
	return found


# Lets the physics server register freshly added bodies before raycasting.
func _settle() -> void:
	for i in range(3):
		await get_tree().physics_frame


func _build_target(collision_layer: int, pos: Vector3) -> CharacterBody3D:
	var target := CharacterBody3D.new()
	target.collision_layer = collision_layer
	target.set_script(preload("res://tests/melee_dummy_target.gd"))
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.0
	capsule.height = 4.5
	col.shape = capsule
	col.position = Vector3(0, 2.25, 0)
	target.add_child(col)
	target.position = pos
	add_child(target)
	return target


func _verify_trail() -> void:
	# Default AI-style arc (red palette) spawns the full 5-segment sweep.
	EffectManager.spawn_melee_trail(Vector3.ZERO, Vector3.FORWARD, Color(1.0, 0.35, 0.2), Color(1.0, 0.3, 0.1))
	await get_tree().process_frame
	_check(_trail_nodes().size() == 5, "spawn_melee_trail spawns 5 arc segments")

	# Custom offsets + reversed sweep (player combo 2nd swing) still spawn 5.
	EffectManager.spawn_melee_trail(
		Vector3.ZERO, Vector3.FORWARD,
		Color(0.8, 0.9, 1.0), Color(0.3, 0.5, 1.0),
		1.5, 1.0, -1.0,
	)
	await get_tree().process_frame
	_check(_trail_nodes().size() == 10, "custom trail call adds 5 more segments")


func _verify_hit() -> void:
	var attacker := Node3D.new()
	attacker.name = "Attacker"
	add_child(attacker)
	var target := _build_target(8, Vector3(4, 0, 0))
	await _settle()
	var dir := (target.global_position - attacker.global_position).normalized()
	var hit := EffectManager.melee_hit_ray(attacker, dir, 5.0, 8 | 2, 25.0)
	_check(hit, "melee_hit_ray hits enemy body in front (layer 8)")
	_check(target.damage_taken == 25.0, "melee damage applied to hit target")
	target.queue_free()
	attacker.queue_free()


func _verify_wall_whiff() -> void:
	var attacker := Node3D.new()
	attacker.name = "Attacker"
	add_child(attacker)
	var target := _build_target(8, Vector3(4, 0, 0))
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 4.0, 4.0)
	col.shape = shape
	wall.add_child(col)
	wall.position = Vector3(2, 0, 0)
	add_child(wall)
	await _settle()

	var hit := EffectManager.melee_hit_ray(attacker, Vector3.RIGHT, 5.0, 8 | 2, 25.0)
	_check(not hit, "wall in front makes the swing whiff")
	_check(target.damage_taken == 0.0, "no damage dealt through a wall")
	wall.queue_free()
	target.queue_free()
	attacker.queue_free()


func _verify_player_mask() -> void:
	# Enemy swings use mask 1 | 2 (player mecha on layer 1).
	var attacker := Node3D.new()
	attacker.name = "Attacker"
	add_child(attacker)
	var player := _build_target(1, Vector3(4, 0, 0))
	await _settle()
	var dir := (player.global_position - attacker.global_position).normalized()
	var hit := EffectManager.melee_hit_ray(attacker, dir, 5.0, 1 | 2, 10.0)
	_check(hit, "enemy swing hits player body (layer 1)")
	_check(player.damage_taken == 10.0, "enemy melee damage applied to player")
	player.queue_free()
	attacker.queue_free()
