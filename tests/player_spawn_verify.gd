extends Node

## Verifies the off-center player spawn placement (arena_generator):
##   1. The mech does NOT stay at the arena center (0, 0).
##   2. The chosen spot sits inside the escape walls.
##   3. The spot is clear of concealment objects and future cover spawns.
## Run: godot --headless --path . res://tests/player_spawn_verify.tscn

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
	GlobalData.reset_run_data()
	GlobalData.board_theme_id = "desert"
	GlobalData.combat_tile_terrain = "sand"
	GlobalData.current_sector = 2
	GlobalData.current_tile = Vector2i(7, 7)

	# Mimic game_world layout: GameWorld hosts Mecha + ArenaGenerator + seed sys.
	var host := Node3D.new()
	host.name = "GameWorld"
	add_child(host)

	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	mecha.position = Vector3(0, 5, 5)  # the scene's original center-ish spawn
	host.add_child(mecha)

	var seed_sys := preload("res://scripts/arena/arena_seed_system.gd").new()
	seed_sys.name = "ArenaSeedSystem"
	host.add_child(seed_sys)

	var arena := preload("res://scripts/arena/arena_generator.gd").new()
	arena.name = "ArenaGenerator"
	arena.current_theme = arena.BiomeTheme.DESERT
	arena.arena_size = 240.0
	host.add_child(arena)

	# Build the arena so concealment objects (dunes/rocks) exist, then place.
	arena.generate_arena()
	arena._place_player_at_arena_edge()

	var pos: Vector3 = mecha.position
	var dist_from_center := Vector2(pos.x, pos.z).length()
	_check(dist_from_center > 30.0,
		"player spawns off-center (%.0fm from center)" % dist_from_center)

	# Inside the escape walls: the arena half is 120m, walls sit ~1.5m inside.
	_check(absf(pos.x) < 110.0 and absf(pos.z) < 110.0,
		"spawn is inside the escape walls (%.0f, %.0f)" % [pos.x, pos.z])

	# Clear of every concealment object already placed (dunes/rocks).
	var clear_of_objects := true
	for node in get_tree().get_nodes_in_group("concealment"):
		if node is Node3D:
			var d := Vector2(pos.x, pos.z).distance_to(
				Vector2(node.global_position.x, node.global_position.z))
			if d < 8.0:
				clear_of_objects = false
	_check(clear_of_objects, "spawn is clear of concealment objects")

	# Clear of the upcoming cover spawns (same seed the obstacle spawner uses).
	seed_sys.set_seed(GlobalData.current_sector, GlobalData.current_tile)
	var cover := seed_sys.get_obstacle_positions(int(arena.current_theme), 240.0)
	var clear_of_cover := true
	for c in cover:
		if c is Dictionary:
			var cpos: Vector3 = c.get("pos", Vector3.ZERO)
			if Vector2(pos.x, pos.z).distance_to(Vector2(cpos.x, cpos.z)) < 8.0:
				clear_of_cover = false
	_check(clear_of_cover, "spawn is clear of upcoming cover spawns")

	print("PLAYER_SPAWN_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
