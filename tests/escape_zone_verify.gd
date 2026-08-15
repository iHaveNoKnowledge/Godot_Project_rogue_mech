extends Node3D

## Verifies the escape zones are a square frame of tall light walls OUTSIDE
## the combat field:
##   1. Four zones sit at the arena's outer edge (|x|/|z| >= 115), clear of the
##      spawn ring and combat area.
##   2. Each trigger is an 8m-tall zone that now extends PAST the visible wall
##      into the outside strip (its outer face lies beyond the arena edge).
##   3. The GlowWall visual is a slim, more transparent slab (not the full
##      trigger thickness) — a light veil the player walks through.
##   4. No world-space text: the "RETREAT ZONE" status label is gone, replaced
##      by the HUD accessors the combat HUD polls.
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

	var arena_half := 120.0  # default arena_size 240 / 2
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

		# The trigger extends PAST the wall: its outer face lies beyond the arena
		# edge, so the retreat hold keeps charging out in the dead zone behind
		# the light wall.
		var thickness: float = minf(shape.x, shape.z)
		var outward: float = edge + thickness * 0.5
		_check(outward > arena_half, "trigger reaches past the arena edge into the outside strip (outer face %.1f)" % outward)

		# The visible wall is a slim slab: it never matches the trigger's full
		# thickness (min horizontal dimension <= 1.5).
		var wall_mesh := z.get_node_or_null("GlowWall") as MeshInstance3D
		var mesh_size := Vector3.ZERO
		if wall_mesh and wall_mesh.mesh is BoxMesh:
			mesh_size = (wall_mesh.mesh as BoxMesh).size
		var wall_thin: float = minf(mesh_size.x, mesh_size.z)
		_check(wall_thin > 0.0 and wall_thin <= 1.5, "GlowWall is a slim light veil (%.1fm thick)" % wall_thin)
		_check(wall_thin < thickness, "GlowWall is thinner than the trigger it is built from (%.1f < %.1f)" % [wall_thin, thickness])

		# No world-space text anymore — the RETREAT readout lives on the HUD.
		_check(z.get_node_or_null("StatusLabel") == null, "world-space RETREAT ZONE label removed")
		_check(z.get_node_or_null("GlowStrip") == null, "no flat floor strip remains")

		# The HUD polls these accessors to paint the screen-top RETREAT banner.
		_check(z.has_method("is_player_inside"), "escape zone exposes is_player_inside()")
		_check(z.has_method("get_hold_progress"), "escape zone exposes get_hold_progress()")
		_check(z.has_method("get_hold_remaining"), "escape zone exposes get_hold_remaining()")
		_check(z.has_method("is_escape_complete"), "escape zone exposes is_escape_complete()")

	print("ESCAPE_ZONE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
