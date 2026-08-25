extends Node

## Verifies enemy mechs physically collide with scenery in battle:
##   1. A chasing enemy is stopped by a concrete barrier (never walks through).
##   2. The retreat light wall blocks ENEMIES but lets the PLAYER walk through:
##      the glow wall is walk-through only for the player mech (layer 1), while
##      enemies (mask includes layer 32) are stopped by the hidden barrier.
## Run: godot --headless --path . res://tests/enemy_cover_collide_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("COVER_COLLIDE_OK: " + name)
	else:
		_fails += 1
		printerr("COVER_COLLIDE_FAIL: " + name)


func _ready() -> void:
	await _verify_barrier_block()
	await _verify_retreat_wall_blocks_enemy_only()
	await _verify_arena_builds_barriers()
	print("ENEMY_COVER_COLLIDE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# The real arena generator must attach an enemy-only barrier (layer 32) to
# every escape zone, and the retreat glow wall stays a walk-through Area3D.
func _verify_arena_builds_barriers() -> void:
	var arena_script = preload("res://scripts/arena/arena_generator.gd")
	var arena := arena_script.new()
	arena.current_theme = arena_script.BiomeTheme.FOREST_ROAD
	arena.arena_size = 240.0
	arena.generate_arena()
	add_child(arena)

	var zones := get_tree().get_nodes_in_group("escape_zone")
	var barriers := 0
	var seen := {}
	for zone in zones:
		for child in zone.get_parent().get_children():
			if String(child.name).begins_with("RetreatWallBarrier") and child.collision_layer == 32:
				if not seen.has(child.get_instance_id()):
					seen[child.get_instance_id()] = true
					barriers += 1
	print("DBG arena barriers: zones=", zones.size(), " barriers=", barriers)
	_check(zones.size() >= 4, "arena builds 4+ escape zones (got %d)" % zones.size())
	_check(barriers == zones.size(), "every escape zone has an enemy-only barrier on layer 32 (%d zones, %d barriers)" % [zones.size(), barriers])
	_check(barriers >= 4, "at least one barrier per arena side (%d)" % barriers)

	arena.queue_free()
	await get_tree().process_frame


# A concrete barrier between the enemy and its target must physically stop the
# enemy. The enemy starts at x=-10, the barrier spans x=0 (thick 1.2m), and the
# target sits at x=+10. Crossing to x > +1.5 while the barrier is alive = bug.
func _verify_barrier_block() -> void:
	var ground := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(200, 0.8, 200)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position = Vector3(0, -0.4, 0)
	ground.collision_layer = 2
	ground.collision_mask = 1
	add_child(ground)

	var cover := StaticBody3D.new()
	cover.set_script(preload("res://scripts/arena/cover_object.gd"))
	cover.collision_layer = 2
	cover.collision_mask = 1
	var cshape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(6, 2.2, 1.2)
	cshape.shape = cbox
	cshape.position.y = 1.1
	cover.add_child(cshape)
	cover.position = Vector3(0, 0, 0)
	add_child(cover)
	cover.add_to_group("cover")

	var enemy = _spawn_enemy(Vector3(-10, 0, 0))
	var target = _spawn_target(Vector3(10, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy.target = target

	# With proper NavMesh + local avoidance the enemy should NAVIGATE AROUND
	# the 6m barrier via its side instead of ramming it and sticking.
	# Verify: never clipped through the interior, and did reach the east side.
	var entered := false
	var reached := false
	for i in range(240):
		await get_tree().physics_frame
		var p: Vector3 = enemy.global_position
		# Exact barrier interior (6 x 1.2) — entering means clipping through the wall
		if p.x > -3.0 and p.x < 3.0 and p.z > -0.6 and p.z < 0.6:
			entered = true
		if p.x > 5.0:
			reached = true
			break

	print("DBG barrier: enemy_pos=", enemy.global_position, " entered=", entered, " reached=", reached, " cover_alive=", is_instance_valid(cover))
	_check(not entered, "enemy never clipped through barrier interior (steered around)")
	_check(reached, "enemy navigated around barrier to reach target side")
	_check(is_instance_valid(cover), "barrier is still alive (enemy never destroyed it)")

	enemy.queue_free()
	target.queue_free()
	cover.queue_free()
	ground.queue_free()
	await get_tree().process_frame


# The retreat wall must block enemies but let the player through. Build the
# same geometry _create_escape_zones uses: an Area3D glow zone + a StaticBody3D
# barrier on layer 32. An enemy (mask 35) walking into it must be stopped; the
# player mech (mask 3) walks straight through.
func _verify_retreat_wall_blocks_enemy_only() -> void:
	var ground := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(200, 0.8, 200)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position = Vector3(0, -0.4, 0)
	ground.collision_layer = 2
	ground.collision_mask = 1
	add_child(ground)

	# Enemy-only barrier on layer 32 (exactly as _create_escape_zones builds it,
	# but spanning the whole edge like the real arena so the enemy can't flank).
	var barrier := StaticBody3D.new()
	barrier.name = "RetreatWallBarrier"
	barrier.collision_layer = 32
	barrier.collision_mask = 0
	barrier.position = Vector3(0, 4.0, 0)
	var bcol := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(1.5, 8.0, 200)
	bcol.shape = bshape
	barrier.add_child(bcol)
	add_child(barrier)

	# Enemy (mask 35 = 3 | 32) approaching from x=-10 must stop at the wall.
	var enemy = _spawn_enemy(Vector3(-10, 0, 0))
	print("DBG retreat spawn: enemy_pos=", enemy.global_position, " mask=", enemy.collision_mask)
	var target = _spawn_target(Vector3(10, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("DBG retreat after physics: enemy_pos=", enemy.global_position)
	enemy.target = target

	var enemy_crossed := false
	for i in range(180):
		await get_tree().physics_frame
		if i % 30 == 0:
			print("DBG retreat enemy frame ", i, ": pos=", enemy.global_position, " state=", enemy.state_machine.current_state.name if enemy.state_machine and enemy.state_machine.current_state else "?")
		if enemy.global_position.x > 1.0:
			enemy_crossed = true
			break
	print("DBG retreat: enemy_pos=", enemy.global_position, " enemy_crossed=", enemy_crossed)
	_check(not enemy_crossed, "enemy is stopped by the retreat wall barrier (layer 32)")

	enemy.queue_free()
	target.queue_free()

	# Player (mask 3, layer 1 — same collision profile as the player mech) must
	# walk straight through the barrier. A plain body is used so the mecha
	# controller doesn't fight the test's manual movement.
	var player := CharacterBody3D.new()
	player.collision_layer = 1
	player.collision_mask = 3
	var pcol := CollisionShape3D.new()
	var pcapsule := CapsuleShape3D.new()
	pcapsule.radius = 1.2
	pcapsule.height = 3.0
	pcol.shape = pcapsule
	player.add_child(pcol)
	player.position = Vector3(-10, 1.0, 0)
	add_child(player)
	await get_tree().physics_frame

	var moved := false
	for i in range(120):
		player.velocity = Vector3(8.0, 0.0, 0.0)
		player.move_and_slide()
		await get_tree().physics_frame
		if player.global_position.x > 1.0:
			moved = true
			break
	print("DBG retreat player: player_pos=", player.global_position, " moved_through=", moved)
	_check(moved, "player walks straight through the retreat wall barrier (layer 32 not in mask)")

	player.queue_free()
	barrier.queue_free()
	ground.queue_free()
	await get_tree().process_frame


func _spawn_enemy(pos: Vector3) -> Node:
	var scene := load("res://scenes/mecha/enemy_dummy.tscn") as PackedScene
	var enemy = scene.instantiate()
	enemy.archetype = 0
	enemy.position = pos
	add_child(enemy)
	return enemy


func _spawn_target(pos: Vector3) -> Node:
	var target := CharacterBody3D.new()
	target.name = "FakePlayer"
	target.add_to_group("mecha")
	target.position = pos
	add_child(target)
	return target
