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
##   5. Walkable EscapeApron ground continues past the arena edge BEHIND the
##      wall (up to the void barrier), and the trigger covers it — the player
##      can physically walk through the wall and stand behind it while the
##      retreat hold charges.
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

	# --- Walkable ground continues BEHIND the retreat wall -------------------
	# The apron is a static floor ring past the arena edge, and the void
	# barrier sits beyond IT (not right behind the wall), so the player has
	# solid ground to stand on after walking through the light wall.
	var apron: StaticBody3D = null
	for ch in gen.get_node_or_null("ThemeStructures").get_children():
		if ch is StaticBody3D and ch.name == "EscapeApron":
			apron = ch as StaticBody3D
			break
	_check(apron != null, "walkable EscapeApron ring generated")
	if apron != null:
		var apron_out := 0.0
		for ch in apron.get_children():
			if ch is CollisionShape3D and ch.shape is BoxShape3D:
				var s: Vector3 = (ch.shape as BoxShape3D).size
				var center: Vector3 = ch.position
				# The THIN dimension points radially (the slab runs along the wall),
				# so half of it is the slab's reach beyond the arena edge.
				apron_out = maxf(apron_out, maxf(absf(center.x), absf(center.z)) + minf(s.x, s.z) * 0.5)
		_check(apron_out > arena_half, "apron ground extends past the arena edge (outer face %.1f)" % apron_out)

	# The void barrier sits BEYOND the apron, leaving room to stand behind the
	# wall — its inner face is past the apron's outer face (no floor gap).
	var barrier_inner := INF
	for ch in gen.get_node_or_null("EscapeZones").get_children():
		if ch is StaticBody3D and ch.name == "VoidBarrier":
			for col in ch.get_children():
				if col is CollisionShape3D and col.shape is BoxShape3D:
					var s2: Vector3 = (col.shape as BoxShape3D).size
					var c2: Vector3 = col.position + ch.position
					# Inner face toward the arena = radial coordinate minus half the
					# thin (radial) dimension.
					barrier_inner = minf(barrier_inner, absf(maxf(absf(c2.x), absf(c2.z))) - minf(s2.x, s2.z) * 0.5)
	_check(barrier_inner < INF, "void barrier generated")
	_check(barrier_inner > arena_half + 1.0, "void barrier sits past the arena edge (inner face %.1f)" % barrier_inner)

	# The trigger reaches PAST the wall to the barrier, so the retreat hold
	# keeps charging while standing behind the wall.
	var trigger_out := 0.0
	for z in zones:
		for ch in z.get_children():
			if ch is CollisionShape3D and ch.shape is BoxShape3D:
				var st: Vector3 = (ch.shape as BoxShape3D).size
				var ct: Vector3 = ch.position + z.position
				trigger_out = maxf(trigger_out, absf(maxf(absf(ct.x), absf(ct.z))) + minf(st.x, st.z) * 0.5)
	_check(trigger_out >= barrier_inner - 0.01, "escape trigger covers the strip up to the void barrier (%.1f)" % trigger_out)

	# --- Physical walk-through -------------------------------------------------
	# A real CharacterBody3D (player-sized capsule) walks from inside the field
	# through the light wall and must end up standing BEHIND it, on the apron.
	var probe := CharacterBody3D.new()
	probe.collision_layer = 1
	probe.collision_mask = 2
	var probe_col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 2.8
	probe_col.shape = capsule
	probe_col.position.y = 1.4
	probe.add_child(probe_col)
	add_child(probe)
	probe.position = Vector3(0, 5.0, arena_half - 6.0)
	var reached_behind := false
	var fell_into_void := false
	for i in range(300):
		await get_tree().physics_frame
		if probe.is_on_floor():
			probe.velocity = Vector3(0, 0, 4.0)
		else:
			probe.velocity += Vector3(0, -20.0 / 60.0, 0)
		probe.move_and_slide()
		if probe.global_position.z > arena_half + 2.0 and probe.is_on_floor():
			reached_behind = true
			break
		if probe.global_position.y < -3.0:
			fell_into_void = true
			break
	_check(reached_behind, "player walks THROUGH the retreat wall and stands behind it (z=%.1f)" % probe.global_position.z)
	_check(not fell_into_void, "no void pit behind the wall — the apron holds the player up")
	probe.queue_free()

	print("ESCAPE_ZONE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
