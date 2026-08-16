extends Node3D

## Headless verification that enemy spawns rest on the arena terrain:
##   1. snap_to_ground() snaps spawn points onto the actual surface (dunes,
##      rocks, riverbanks) instead of a hardcoded y that left some enemies
##      buried inside desert dunes.
##   2. body_bottom_offset() lifts the root so each enemy's collision body
##      (and its visual mech) rests ON the ground, not half-buried.
##   3. Every enemy scene settles with its lowest visual mesh on the surface —
##      flat ground and dune tops alike.
## Run: godot --headless --path . res://tests/spawn_ground_verify.tscn

const SPAWN_SCRIPT := preload("res://scripts/systems/spawn_manager.gd")

# name, scene path, archetype. Covers every enemy the SpawnManager fields.
const TYPES: Array = [
	["enemy_dummy", "res://scenes/mecha/enemy_dummy.tscn", 0],
	["enemy_dummy_full", "res://scenes/mecha/enemy_dummy_full.tscn", 0],
	["enemy_ranged", "res://scenes/mecha/enemy_ranged.tscn", 1],
	["enemy_heavy", "res://scenes/mecha/enemy_heavy.tscn", 2],
	["enemy_support", "res://scenes/mecha/enemy_support.tscn", 3],
	["enemy_tank", "res://scenes/mecha/enemy_tank.tscn", 1],
	["enemy_boss", "res://scenes/mecha/enemy_boss.tscn", 2],
	["enemy_shield_melee", "res://scenes/mecha/enemy_shield_melee.tscn", 4],
	["enemy_shield_ranged", "res://scenes/mecha/enemy_shield_ranged.tscn", 5],
]

var _fails := 0
var _checks := 0

# Flat theme ground: arena_generator puts the collision box at y=-0.8 (height
# 0.8), so the walkable surface sits at y=-0.4.
const FLAT_SURFACE := -0.4
# Dune top: a 5m desert dune spans y=-0.2..4.8 (position height/2 - 0.2).
const DUNE_SURFACE := 4.8


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SPAWN_OK: " + name)
	else:
		_fails += 1
		print("SPAWN_FAIL: " + name)


func _add_flat_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.position = Vector3(0, -0.8, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(240, 0.8, 240)
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _add_dune() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, DUNE_SURFACE + 0.2, 30)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, (DUNE_SURFACE - 0.2) * 0.5, 0)
	add_child(body)


func _ready() -> void:
	await get_tree().process_frame

	_add_flat_ground()
	_add_dune()

	# Let the physics server register the static bodies before raycasting.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_world_3d().direct_space_state

	# --- snap_to_ground unit checks ---
	var flat := SPAWN_SCRIPT.snap_to_ground(Vector3(60, 0.05, 60), space)
	_check(absf(flat.y - (FLAT_SURFACE + 0.05)) < 0.001, "flat spawn snaps onto ground surface")
	_check(absf(flat.x - 60.0) < 0.001 and absf(flat.z - 60.0) < 0.001, "flat spawn keeps x/z")

	var on_dune := SPAWN_SCRIPT.snap_to_ground(Vector3(0, 0.05, 0), space)
	_check(absf(on_dune.y - (DUNE_SURFACE + 0.05)) < 0.001, "spawn over dune snaps onto dune top")

	var miss := SPAWN_SCRIPT.snap_to_ground(Vector3(500, 3.0, 500), space)
	_check(miss.y == 3.0, "spawn without ground below keeps original y")

	# --- body_bottom_offset matches each scene's collision shape (WORLD
	# units, so scaled roots like the boss's 1.5x rig are accounted for) ---
	var expected_bottoms := {
		"enemy_dummy": -0.6,
		"enemy_dummy_full": -0.6,
		"enemy_ranged": -0.7,
		"enemy_heavy": -0.45,
		"enemy_support": -0.824,
		"enemy_tank": 0.0,
		"enemy_boss": -0.126,
		"enemy_shield_melee": -0.45,
		"enemy_shield_ranged": -0.7,
	}
	for t in TYPES:
		var probe := (load(t[1]) as PackedScene).instantiate()
		var got := SPAWN_SCRIPT.body_bottom_offset(probe)
		_check(absf(got - expected_bottoms[t[0]]) < 0.05, "%s collision bottom at %s (%.2f)" % [t[0], expected_bottoms[t[0]], got])
		probe.free()

	# --- end-to-end: every enemy settles with its feet on the surface ---
	for t in TYPES:
		await _verify_settles(t, Vector3(60, 0, 60), FLAT_SURFACE, space)
		await _verify_settles(t, Vector3(0, 0, 0), DUNE_SURFACE, space)

	print("SPAWN_GROUND_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# Spawns one enemy via the same placement SpawnManager uses (snap_to_ground +
# body_bottom_offset), then FREEZES it (AI + animation) so the measurement
# captures the resting pose instead of a mid-hunt walk frame — the idle state
# actively hunts and would walk the mech off the surface during a settle wait.
# Asserts the lowest visual mesh rests on the expected surface.
func _verify_settles(t: Array, pos: Vector3, surface_y: float, space: PhysicsDirectSpaceState3D) -> void:
	var enemy := (load(t[1]) as PackedScene).instantiate()
	enemy.archetype = t[2]
	var spawn_pos := SPAWN_SCRIPT.snap_to_ground(pos, space)
	spawn_pos.y -= SPAWN_SCRIPT.body_bottom_offset(enemy)
	enemy.position = spawn_pos
	add_child(enemy)  # _ready runs synchronously; the catalog body is built here.

	# Freeze the whole rig: enemy physics (state machine delegate), animation
	# node, and any other children that process.
	enemy.set_physics_process(false)
	for child in enemy.get_children():
		if child.has_method("set_physics_process"):
			child.set_physics_process(false)
		if child.has_method("set_process"):
			child.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var lowest := _lowest_mesh_y(enemy)
	_check(absf(lowest - surface_y) < 0.2, "%s settles on surface %.2f (lowest %.2f)" % [t[0], surface_y, lowest])
	enemy.queue_free()
	await get_tree().physics_frame


func _lowest_mesh_y(node: Node) -> float:
	return _collect_lowest(node, INF)


func _collect_lowest(node: Node, lowest: float) -> float:
	if node is MeshInstance3D:
		var aabb: AABB = (node as MeshInstance3D).get_aabb()
		var world_min: Vector3 = (node as MeshInstance3D).global_transform * aabb.position
		lowest = minf(lowest, world_min.y)
	for child in node.get_children():
		lowest = _collect_lowest(child, lowest)
	return lowest
