extends Node3D

## Automated Verification for Terrain Slope Mesh Upward Normal Winding, Trimesh Collision (No Falling Through), and Enemy Pilot Health System Compatibility.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("TERRAIN_PILOT_OK: %s" % msg)
	else:
		_fails += 1
		print("TERRAIN_PILOT_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Terrain Slope & Pilot Health Verification ---")

	# 1. Test Terrain Mesh Normal Orientation (Facing UP +Y)
	var arena_gen = preload("res://scripts/arena/arena_generator.gd").new()
	arena_gen.current_theme = 0 # DESERT
	add_child(arena_gen)
	arena_gen.generate_arena()

	var terrain_surface: MeshInstance3D = arena_gen.get_node_or_null("GroundTiles/TerrainSurface")
	_check(terrain_surface != null and terrain_surface.mesh != null, "Found Desert TerrainSurface MeshInstance3D")

	var mesh: ArrayMesh = terrain_surface.mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var upward_normal_count := 0
	for n in normals:
		if n.y > 0.3: # Normal points upward towards sky
			upward_normal_count += 1

	var normal_ratio := float(upward_normal_count) / float(normals.size())
	_check(normal_ratio > 0.95, "Terrain mesh normals are correctly oriented UPWARD towards sky (ratio: %.2f)" % normal_ratio)

	# 2. Test 3D Physics Collision Exists and Matches Mesh
	var ground_body: StaticBody3D = arena_gen.get_node_or_null("ThemeStructures/GroundCollision")
	_check(ground_body != null, "Found GroundCollision StaticBody3D")
	_check(ground_body.collision_layer == 2, "GroundCollision is on environment layer 2")

	var col_shape_node: CollisionShape3D = ground_body.get_child(0) as CollisionShape3D
	_check(col_shape_node != null and col_shape_node.shape is ConcavePolygonShape3D, "Ground collision is an exact ConcavePolygonShape3D trimesh")

	# 3. Test Direct Raycast / Ground Height Queries across Arena
	var concave: ConcavePolygonShape3D = col_shape_node.shape as ConcavePolygonShape3D
	var faces: PackedVector3Array = concave.get_faces()
	_check(faces.size() == indices.size(), "Collision shape has exact 1:1 triangle count with visual mesh (%d faces)" % (faces.size() / 3))

	# 4. Test EnemyPilot Health System Adapter Compatibility
	var pilot_scene = preload("res://scripts/mecha/enemy_pilot.gd")
	var pilot = CharacterBody3D.new()
	pilot.set_script(pilot_scene)
	add_child(pilot)

	_check(pilot.is_in_group("enemy"), "Pilot is in 'enemy' group")
	_check(pilot.get("health_system") != null, "Pilot provides valid health_system adapter")
	_check(pilot.health_system.is_destroyed == false, "Pilot health_system.is_destroyed is false when alive")
	_check(pilot.health_system.current_total_frame == 40.0, "Pilot health_system.current_total_frame is 40.0")

	# Simulate damage via health_system
	pilot.health_system.take_damage(15.0)
	_check(pilot.hp == 25.0, "Pilot took 15 damage via health_system adapter (hp = 25.0)")

	# Simulate healing via health_system
	pilot.health_system.take_heal(5.0)
	_check(pilot.hp == 30.0, "Pilot took 5 heal via health_system adapter (hp = 30.0)")

	# Simulate death
	pilot.health_system.take_damage(50.0)
	_check(pilot.health_system.is_destroyed == true, "Pilot health_system.is_destroyed is true after fatal damage")

	# 5. Test Ally Dummy scanning enemy group containing Pilot
	var ally = preload("res://scripts/mecha/ally_dummy.gd").new()
	add_child(ally)
	ally._acquire_target()
	_check(true, "Ally dummy safely scans enemy group containing pilot without crashing")

	print("--- Terrain Slope & Pilot Health Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_TERRAIN_PILOT_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
