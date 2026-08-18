extends Node3D

## Verifies the escape zones frame the combat field:
##   1. On a flat-theme arena the zones hug the irregular footprint outline
##      (one per merged boundary run, always >= 4) instead of a square frame.
##   2. Each trigger is an 8m-tall band spanning from ~12m inside the outline to
##      the apron behind the glow wall.
##   3. The GlowWall visual is a slim, transparent slab the player walks through,
##      pinned outward (toward the outline) of the trigger center.
##   4. No world-space text: the "RETREAT ZONE" label is gone, replaced by the
##      HUD accessors the combat HUD polls.
##   5. Walkable EscapeApron ground continues past the outline BEHIND the wall
##      (up to the void barrier), with one slab per boundary run.
##   6. A probe walks through a wall and stands on the apron without falling
##      into the void.
## Run: godot --headless --path . res://tests/escape_zone_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ZONE_OK: " + name)
	else:
		_fails += 1
		printerr("ZONE_FAIL: " + name)


func _ready() -> void:
	var gen := preload("res://scripts/arena/arena_generator.gd").new()
	add_child(gen)
	await get_tree().process_frame
	await get_tree().process_frame

	var fp: ArenaFootprint = gen.footprint
	_check(fp != null, "flat-theme arena builds an irregular footprint")
	if fp == null:
		print("ESCAPE_ZONE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
		get_tree().quit(1)
		return

	var zones := get_tree().get_nodes_in_group("escape_zone")
	_check(zones.size() >= 4, "escape zones frame the outline (got %d)" % zones.size())
	_check(zones.size() == fp.segments.size(), "one escape zone per boundary run (zones=%d segments=%d)" % [zones.size(), fp.segments.size()])

	for z in zones:
		var p: Vector3 = z.global_position
		_check(p.y > 3.5, "escape wall is raised so the 8m wall stands on the ground (y=%.1f)" % p.y)

		# The trigger is built around the footprint outline, not a square edge.
		var d: float = fp.distance_to_outline(Vector2(p.x, p.z))
		_check(d < 9.5, "zone hugs the footprint outline (%.1fm from it)" % d)

		var col: CollisionShape3D = null
		for ch in z.get_children():
			if ch is CollisionShape3D:
				col = ch as CollisionShape3D
				break
		var shape := Vector3.ZERO
		if col and col.shape is BoxShape3D:
			shape = (col.shape as BoxShape3D).size
		_check(shape.y >= 7.9, "escape wall trigger is 8m tall (%.1f)" % shape.y)
		var thickness: float = minf(shape.x, shape.z)
		_check(thickness > 16.5, "trigger spans 12m-inside + apron-outside (%.1fm)" % thickness)

		# The visible wall is a slim slab: it never matches the trigger's full
		# thickness (min horizontal dimension <= 1.5).
		var wall_mesh := z.get_node_or_null("GlowWall") as MeshInstance3D
		var mesh_size := Vector3.ZERO
		if wall_mesh and wall_mesh.mesh is BoxMesh:
			mesh_size = (wall_mesh.mesh as BoxMesh).size
		var wall_thin: float = minf(mesh_size.x, mesh_size.z)
		_check(wall_thin > 0.0 and wall_thin <= 1.5, "GlowWall is a slim light veil (%.1fm thick)" % wall_thin)
		_check(wall_thin < thickness, "GlowWall is thinner than the trigger it is built from (%.1f < %.1f)" % [wall_thin, thickness])

		# The glow wall sits OUTWARD of the trigger center (closer to the
		# outline), so the trigger extends deeper into the field than the wall.
		var trigger_center: Vector2 = Vector2(p.x, p.z)
		var wall_xz: Vector2 = trigger_center + Vector2(z.wall_local.x, z.wall_local.z)
		_check(fp.distance_to_outline(wall_xz) < fp.distance_to_outline(trigger_center) - 1.0,
			"glow wall pinned outward of the trigger center")

		# No world-space text anymore — the RETREAT readout lives on the HUD.
		_check(z.get_node_or_null("StatusLabel") == null, "world-space RETREAT ZONE label removed")
		_check(z.get_node_or_null("GlowStrip") == null, "no flat floor strip remains")

		# The HUD polls these accessors to paint the screen-top RETREAT banner.
		_check(z.has_method("is_player_inside"), "escape zone exposes is_player_inside()")
		_check(z.has_method("get_hold_progress"), "escape zone exposes get_hold_progress()")
		_check(z.has_method("get_hold_remaining"), "escape zone exposes get_hold_remaining()")
		_check(z.has_method("is_escape_complete"), "escape zone exposes is_escape_complete()")

	# --- Walkable ground continues BEHIND the retreat wall -------------------
	var apron: StaticBody3D = null
	for ch in gen.get_node_or_null("ThemeStructures").get_children():
		if ch is StaticBody3D and ch.name == "EscapeApron":
			apron = ch as StaticBody3D
			break
	_check(apron != null, "walkable EscapeApron ring generated")
	if apron != null:
		# One slab per boundary run (2 nodes each: collision + mesh).
		_check(apron.get_child_count() >= fp.segments.size() * 2, "apron has a slab per boundary run (nodes=%d segments=%d)" % [apron.get_child_count(), fp.segments.size()])
		# Every boundary run gets an apron slab straddling its outline.
		var covered := 0
		for seg in fp.segments:
			var mid: Vector2 = (seg["a"] as Vector2 + seg["b"] as Vector2) * 0.5
			var normal: Vector2 = seg["normal"]
			var target: Vector2 = mid + normal * 2.5  # middle of the 5m apron
			var hit := false
			for ch in apron.get_children():
				if ch is CollisionShape3D and ch.shape is BoxShape3D:
					var s: Vector3 = (ch.shape as BoxShape3D).size
					var c: Vector3 = ch.position
					var hx := s.x * 0.5
					var hz := s.z * 0.5
					if target.x >= c.x - hx - 0.5 and target.x <= c.x + hx + 0.5 \
						and target.y >= c.z - hz - 0.5 and target.y <= c.z + hz + 0.5:
						hit = true
						break
			if hit:
				covered += 1
		_check(covered == fp.segments.size(), "every boundary run has an apron slab (%d/%d)" % [covered, fp.segments.size()])

	# The void barrier sits BEYOND the apron: one box per boundary run, with its
	# inner face past the apron (outline + apron + 0.5). Godot renames duplicate
	# siblings (only the first keeps "VoidBarrier"), so count via the group.
	var void_barriers := 0
	var barrier_inner := INF
	for ch in get_tree().get_nodes_in_group("void_barrier"):
		if ch is StaticBody3D:
			void_barriers += 1
			for col in ch.get_children():
				if col is CollisionShape3D and col.shape is BoxShape3D:
					var s2: Vector3 = (col.shape as BoxShape3D).size
					var c2: Vector3 = ch.position
					# Radial distance from center to the inner face along the
					# outward normal (thin dimension is the radial one).
					barrier_inner = minf(barrier_inner, c2.length() - minf(s2.x, s2.z) * 0.5)
	_check(void_barriers == fp.segments.size(), "void barrier per boundary run (got %d)" % void_barriers)
	_check(barrier_inner < INF, "void barrier generated")

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

	# Walk across a boundary run (prefer a north-facing segment so the probe
	# heads in +z, matching the classic walk-through direction).
	var seg: Dictionary = fp.segments[0]
	var seg_mid: Vector2 = (seg["a"] as Vector2 + seg["b"] as Vector2) * 0.5
	var seg_normal: Vector2 = seg["normal"]
	for s in fp.segments:
		if (s["normal"] as Vector2).y > 0.9:
			seg = s
			seg_mid = (s["a"] as Vector2 + s["b"] as Vector2) * 0.5
			seg_normal = s["normal"]
			break
	var start := Vector3(seg_mid.x - seg_normal.x * 25.0, 5.0, seg_mid.y - seg_normal.y * 25.0)
	var target := Vector3(seg_mid.x + seg_normal.x * 4.0, 0.0, seg_mid.y + seg_normal.y * 4.0)
	probe.position = start
	var reached_behind := false
	var fell_into_void := false
	for i in range(400):
		await get_tree().physics_frame
		if probe.is_on_floor():
			probe.velocity = Vector3(seg_normal.x * 6.0, 0.0, seg_normal.y * 6.0)
		else:
			probe.velocity += Vector3(0, -20.0 / 60.0, 0)
		probe.move_and_slide()
		var to_target: Vector3 = target - probe.global_position
		to_target.y = 0.0
		if to_target.length() < 1.5 and probe.is_on_floor():
			reached_behind = true
			break
		if probe.global_position.y < -3.0:
			fell_into_void = true
			break
	_check(reached_behind, "player walks THROUGH the retreat wall and stands behind it")
	_check(not fell_into_void, "no void pit behind the wall — the apron holds the player up")
	probe.queue_free()

	print("ESCAPE_ZONE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
