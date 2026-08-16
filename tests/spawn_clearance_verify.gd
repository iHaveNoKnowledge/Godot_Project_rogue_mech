extends Node

## Verifies the player spawn-point fix: the mech must never be placed inside
## a solid obstacle's footprint (desert dunes, outcrops, forest rocks/logs,
## city buildings). Clearance is measured against each obstacle's WORLD AABB
## (not its center), so a 24m building or 45m dune blocks its full extent.
## Run: godot --headless --path . res://tests/spawn_clearance_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SPAWN_OK: " + name)
	else:
		_fails += 1
		printerr("SPAWN_FAIL: " + name)


func _ready() -> void:
	# --- 1. Point clearance vs a large obstacle AABB ---
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var arena := arena_script.new()
	arena.arena_size = 240.0
	add_child(arena)
	# Create a container so obstacle nodes can be parented under the tree.
	arena.structures_container = Node3D.new()
	arena.structures_container.name = "Structures"
	arena.add_child(arena.structures_container)

	# A desert dune: 40m wide x 30m deep box at ring distance, rotated.
	var dune := StaticBody3D.new()
	dune.add_to_group("solid_obstacle")
	var dune_col := CollisionShape3D.new()
	var dune_shape := BoxShape3D.new()
	dune_shape.size = Vector3(40, 5, 30)
	dune_col.shape = dune_shape
	dune.add_child(dune_col)
	dune.rotation.y = 0.6
	dune.position = Vector3(85, 2.5, 0)
	arena.structures_container.add_child(dune)

	# A city building: 24m footprint at another ring point.
	var building := StaticBody3D.new()
	building.add_to_group("solid_obstacle")
	var b_col := CollisionShape3D.new()
	var b_shape := BoxShape3D.new()
	b_shape.size = Vector3(24, 40, 24)
	b_col.shape = b_shape
	b_col.position.y = 20.0
	building.add_child(b_col)
	building.position = Vector3(0, 0, 90)
	arena.structures_container.add_child(building)

	# Inside the dune footprint must be rejected (even though it is 0m from the
	# AABB's face, the point is inside the box).
	_check(not arena._spawn_point_clear(Vector3(85, 0, 0), 4.0, []), "point inside dune footprint rejected")
	# Near the dune edge within margin must be rejected.
	_check(not arena._spawn_point_clear(Vector3(85 + 22.0, 0, 0), 4.0, []), "point at dune edge + margin rejected")
	# Well clear of the dune (47m away from its center, inside arena bounds) is
	# accepted.
	_check(arena._spawn_point_clear(Vector3(110, 0, 40), 4.0, []), "point far from dune accepted")
	# Inside the building footprint must be rejected — center-distance checks
	# would have allowed 8m-from-center (inside a 24m box).
	_check(not arena._spawn_point_clear(Vector3(8, 0, 90), 4.0, []), "point 8m inside building footprint rejected")
	# Outside the arena bounds must be rejected.
	_check(not arena._spawn_point_clear(Vector3(130, 0, 0), 4.0, []), "point outside arena bounds rejected")
	# Seed cover positions still apply (frame-later obstacle spawns).
	_check(not arena._spawn_point_clear(Vector3(40, 0, 0), 4.0, [{"pos": Vector3(40, 0, 0)}]), "future cover position still blocks")

	# --- 2. The real placement path never drops the mech inside an obstacle ---
	var host := Node3D.new()
	host.name = "Host"
	add_child(host)
	var mecha := Node3D.new()
	mecha.name = "Mecha"
	host.add_child(mecha)
	arena.reparent(host)
	# Re-seed the RNG so the placement loop's random angles are varied.
	for i in range(6):
		mecha.position = Vector3.ZERO
		arena._place_player_at_arena_edge()
		var pos: Vector3 = mecha.position
		_check(not _inside_aabb(pos, dune, 1.0), "placement avoids dune footprint (run %d at %s)" % [i, pos])
		_check(not _inside_aabb(pos, building, 1.0), "placement avoids building footprint (run %d at %s)" % [i, pos])
		_check(absf(pos.x) <= 120.0 - 6.0 and absf(pos.z) <= 120.0 - 6.0, "placement inside arena bounds (run %d at %s)" % [i, pos])

	print("SPAWN_CLEARANCE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _inside_aabb(point: Vector3, body: StaticBody3D, margin: float) -> bool:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s: Shape3D = child.shape
			var half: Vector3
			if s is BoxShape3D:
				half = (s as BoxShape3D).size * 0.5
			elif s is CylinderShape3D:
				var cyl := s as CylinderShape3D
				half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
			else:
				continue
			var t: Transform3D = (child as CollisionShape3D).global_transform
			var half_world: Vector3 = (t.basis * half).abs()
			var aabb := AABB(t.origin - half_world, half_world * 2.0)
			if point.x >= aabb.position.x - margin and point.x <= aabb.end.x + margin \
				and point.z >= aabb.position.z - margin and point.z <= aabb.end.z + margin:
				return true
	return false
