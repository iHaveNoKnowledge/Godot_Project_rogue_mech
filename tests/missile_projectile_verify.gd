extends Node3D

## Verifies the missile projectile rework:
##   1. WeaponCore builds a real missile model (hull + cone warhead + cross
##      fins + exhaust flame) authored with the NOSE pointing down local -Z
##   2. Spawning a MISSILE-style shot points the nose ALONG the flight line —
##      the old sky-pointing +90° roll is gone — including straight-up shots
##   3. The visual re-aims every frame to the LIVE flight vector while gravity
##      arcs the round downward
##   4. Heat-type missiles detonate visibly on impact (fire/smoke FX) while
##      gameplay damage stays untouched, and plain rounds stay spark-only

var _checks: int = 0
var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("MISSILE_OK: %s" % msg)
	else:
		_fails += 1
		print("MISSILE_FAIL: %s" % msg)


func _count_fx_nodes(root: Node) -> int:
	var n := 0
	for child in root.get_children():
		if child is MeshInstance3D or child is GPUParticles3D:
			n += 1
		n += _count_fx_nodes(child)
	return n


func _ready() -> void:
	print("--- Starting Missile Projectile Verification ---")
	# Let this scene finish its own _ready before any spawning mutates it
	# (add_child into a parent mid-setup fails with "Parent node is busy").
	await get_tree().process_frame

	var missile_res: WeaponPart = preload("res://resources/mech/stock/weapon_missile.tres")

	# --- 1. Model structure ---
	var model := WeaponCore._build_missile_model(StandardMaterial3D.new())
	var body_m: MeshInstance3D = null
	var nose_m: MeshInstance3D = null
	var flame_m: MeshInstance3D = null
	var fin_count := 0
	for child in model.get_children():
		if child is MeshInstance3D:
			if child.mesh is CylinderMesh:
				var cm: CylinderMesh = child.mesh
				if cm.top_radius < cm.bottom_radius:
					nose_m = child
				else:
					body_m = child
			elif child.mesh is SphereMesh:
				flame_m = child
			elif child.mesh is BoxMesh:
				fin_count += 1
	_check(body_m != null, "missile hull is a proper cylinder (not a box)")
	_check(nose_m != null and nose_m.position.z < body_m.position.z,
		"cone warhead sits AHEAD of the hull (nose z=%.2f)" % (nose_m.position.z if nose_m else 0.0))
	_check(fin_count >= 2, "cross tail fins present (%d)" % fin_count)
	_check(flame_m != null and flame_m.position.z > 0.0, "exhaust flame burns behind the tail")

	# --- 2. Spawn orientation ---
	var core := WeaponCore.from_weapon(missile_res)
	_check(core.projectile_style == WeaponCore.Style.MISSILE, "missile weapon maps to MISSILE style")
	core.projectile_speed = 20.0

	var owner_node := CharacterBody3D.new()
	add_child(owner_node)

	core._spawn_projectile(Vector3(0, 1.5, 3), Vector3(0, 0, -1), false, owner_node)
	await get_tree().physics_frame
	var projectiles := get_tree().get_nodes_in_group("projectile")
	_check(projectiles.size() == 1, "missile projectile spawned into the scene")
	var proj = projectiles[0]
	_check(proj.visual_node != null, "projectile exposes its aligned visual node")
	if proj.visual_node != null:
		var nose_dir: Vector3 = (proj.visual_node.global_transform.basis * Vector3(0, 0, -1)).normalized()
		_check(nose_dir.dot(Vector3(0, 0, -1)) > 0.99,
			"Nose points ALONG the flight line, not at the sky (dot=%.3f)" % nose_dir.dot(Vector3(0, 0, -1)))

	# Straight-up launch must not trip look_at's colinear-up assertion.
	core._spawn_projectile(Vector3(2, 1.5, 0), Vector3.UP, false, owner_node)
	await get_tree().physics_frame
	projectiles = get_tree().get_nodes_in_group("projectile")
	_check(projectiles.size() == 2, "straight-up launch survives (colinear up guarded)")

	# --- 3. Live flight-vector alignment under gravity arc ---
	# Dedicated fresh round launched from a safe corner so nothing else can
	# free it mid-measurement; gravity sags the trajectory and the model must
	# visibly pitch its nose to follow the live flight vector.
	core._spawn_projectile(Vector3(-4, 3.0, 0), Vector3(0, 0, -1), false, owner_node)
	await get_tree().physics_frame
	var arc_proj = null
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p) and p.global_position.x < -3.0:
			arc_proj = p
			break
	_check(arc_proj != null, "dedicated arc-test round spawned")
	var arc_delta := 0.0
	var arc_ok := false
	if arc_proj != null:
		arc_proj.drop_gravity = 25.0
		arc_proj.drop_start_distance = 1.0
		for i in range(6):
			await get_tree().physics_frame
		if is_instance_valid(arc_proj) and is_instance_valid(arc_proj.visual_node):
			var rot_before: float = arc_proj.visual_node.rotation.x
			for i in range(24):
				await get_tree().physics_frame
				if not is_instance_valid(arc_proj):
					break
			if is_instance_valid(arc_proj) and is_instance_valid(arc_proj.visual_node):
				arc_delta = absf(arc_proj.visual_node.rotation.x - rot_before)
				arc_ok = arc_delta > 0.02 and arc_proj.global_position.y > -2.4
	_check(arc_ok, "Visual pitches to follow the arcing trajectory (delta %.3f rad)" % arc_delta)

	# --- 4. Impact FX gating ---
	var dummy_a := CharacterBody3D.new()
	dummy_a.set_script(load("res://tests/melee_dummy_target.gd"))
	dummy_a.collision_layer = 8
	dummy_a.add_to_group("enemy")
	add_child(dummy_a)
	var p_plain := CharacterBody3D.new()
	p_plain.set_script(load("res://scripts/systems/projectile.gd"))
	add_child(p_plain)
	p_plain.damage = 40.0
	p_plain.damage_type = "heat"
	p_plain.direction = Vector3(0, 0, -1)
	p_plain.speed = 10.0
	await get_tree().process_frame
	var before_plain := _count_fx_nodes(self)
	p_plain._hit_target(dummy_a)
	await get_tree().process_frame
	_check(_count_fx_nodes(self) == before_plain, "plain heat round stays spark-only (no detonation FX)")
	_check(dummy_a.damage_taken == 40.0, "plain round still applies full damage")

	var dummy_b := CharacterBody3D.new()
	dummy_b.set_script(load("res://tests/melee_dummy_target.gd"))
	dummy_b.collision_layer = 8
	dummy_b.add_to_group("enemy")
	add_child(dummy_b)
	var p_missile := CharacterBody3D.new()
	p_missile.set_script(load("res://scripts/systems/projectile.gd"))
	add_child(p_missile)
	p_missile.damage = 100.0
	p_missile.damage_type = "heat"
	p_missile.explosive_visual = true
	p_missile.direction = Vector3(0, 0, -1)
	p_missile.speed = 10.0
	await get_tree().process_frame
	var before_boom := _count_fx_nodes(self)
	p_missile._hit_target(dummy_b)
	await get_tree().process_frame
	_check(_count_fx_nodes(self) > before_boom, "MISSILE impact spawns detonation fire/smoke FX")
	_check(dummy_b.damage_taken == 100.0, "missile keeps its exact tuned damage")
	_check(not is_instance_valid(p_missile) or p_missile.is_queued_for_deletion(),
		"round is consumed after detonating")

	print("--- Missile Projectile Verification Finished: checks=%d fails=%d ---" % [_checks, _fails])
	if _fails == 0:
		print("ALL_MISSILE_PROJECTILE_TESTS_PASSED")
