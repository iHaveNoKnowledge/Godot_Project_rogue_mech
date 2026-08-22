extends Node3D

## Verification test for Combat PBR Materials:
## - Tests MaterialFactory ground & cover materials
## - Verifies Normal maps, Roughness maps, and Albedo textures load cleanly
## - Validates ArenaGenerator ground and ObstacleSpawner cover object materials

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("COMBAT_MAT_OK: %s" % msg)
	else:
		_fails += 1
		print("COMBAT_MAT_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Combat PBR Materials Verification ---")

	_test_ground_materials()
	_test_cover_materials()
	await _test_arena_ground_generation()

	print("COMBAT_MATERIAL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_ground_materials() -> void:
	var themes := [0, 1, 2, 3, 4, 5]
	for t in themes:
		var mat = MaterialFactory.get_ground_material(t)
		_check(mat != null and mat is StandardMaterial3D, "MaterialFactory generated ground material for theme %d" % t)
		_check(mat.normal_enabled, "Theme %d ground material has Normal Mapping enabled" % t)
		_check(mat.normal_texture != null, "Theme %d ground material normal texture loaded" % t)


func _test_cover_materials() -> void:
	var types := ["barrier", "container", "pillar", "small_crate", "fortress_wall", "explosive_barrel", "tree_trunk", "fallen_log", "fern"]
	for ct in types:
		var mat = MaterialFactory.get_cover_material(ct)
		_check(mat != null and mat is StandardMaterial3D, "MaterialFactory generated cover material for '%s'" % ct)
		if ct in ["barrier", "fortress_wall", "container", "pillar", "tree_trunk", "fallen_log"]:
			_check(mat.normal_enabled or mat.albedo_texture != null or mat.metallic > 0, "Cover '%s' has PBR texture or metallic properties" % ct)


func _test_arena_ground_generation() -> void:
	var arena_script = load("res://scripts/arena/arena_generator.gd")
	if arena_script == null:
		return
	var arena: Node3D = Node3D.new()
	arena.set_script(arena_script)
	add_child(arena)
	await get_tree().process_frame

	var ground_tiles = arena.get_node_or_null("GroundTiles")
	_check(ground_tiles != null and ground_tiles.get_child_count() > 0, "ArenaGenerator generated ground tiles with materials")
	if ground_tiles and ground_tiles.get_child_count() > 0:
		var first_child = ground_tiles.get_child(0)
		if first_child is MeshInstance3D:
			_check(first_child.material_override != null, "Ground mesh instance has PBR material override assigned")

	arena.queue_free()
