extends Node3D

## Verifies the escape zones are a square frame of tall light walls OUTSIDE
## the combat field:
##   1. Four zones sit at the arena's outer edge (|x|/|z| >= 115), clear of the
##      spawn ring and combat area.
##   2. Each zone is an 8m-tall wall trigger whose GlowWall visual matches the
##      trigger shape exactly — no flat floor strip.
## Run: godot --headless --path . res://tests/escape_zone_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ZONE_OK: " + name)
	else:
		_fails += 1
		print("ZONE_FAIL: " + name)


func _ready() -> void:
	var gen := preload("res://scripts/arena/arena_generator.gd").new()
	add_child(gen)
	await get_tree().process_frame
	await get_tree().process_frame

	var zones := get_tree().get_nodes_in_group("escape_zone")
	_check(zones.size() == 4, "four escape walls generated (got %d)" % zones.size())

	for z in zones:
		var p: Vector3 = z.global_position
		var edge: float = maxf(absf(p.x), absf(p.z))
		_check(edge > 115.0, "escape wall sits at the arena edge (%.1f)" % edge)
		_check(p.y > 3.5, "escape wall is raised so the 8m wall stands on the ground (y=%.1f)" % p.y)

		var col: CollisionShape3D = null
		for ch in z.get_children():
			if ch is CollisionShape3D:
				col = ch as CollisionShape3D
				break
		var shape := Vector3.ZERO
		if col and col.shape is BoxShape3D:
			shape = (col.shape as BoxShape3D).size
		_check(shape.y >= 7.9, "escape wall trigger is 8m tall (%.1f)" % shape.y)

		var wall_mesh := z.get_node_or_null("GlowWall") as MeshInstance3D
		var mesh_size := Vector3.ZERO
		if wall_mesh and wall_mesh.mesh is BoxMesh:
			mesh_size = (wall_mesh.mesh as BoxMesh).size
		_check(mesh_size == shape, "GlowWall visual matches trigger shape (%.0fx%.0fx%.0f)" % [mesh_size.x, mesh_size.y, mesh_size.z])
		_check(z.get_node_or_null("GlowStrip") == null, "no flat floor strip remains")

	print("ESCAPE_ZONE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
