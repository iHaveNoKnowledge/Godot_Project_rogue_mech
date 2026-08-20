extends Node

## Verifies the RUSHER melee fix:
##   1. RUSHER attack_range is a real melee reach (3.5), not 15.0.
##   2. Enemies no longer deal lock-on damage from outside melee range.
##   3. The swing connects only via a forward collision check (can be dodged).
##   4. Ally RUSHERs use the same collision-based swing against enemies.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MELEE OK: " + name)
	else:
		_fails += 1
		print("MELEE FAIL: " + name)


func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.position = Vector3(0, -1.0, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120, 2, 120)
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _build_target(collision_layer: int, group: String, pos: Vector3) -> CharacterBody3D:
	var target := CharacterBody3D.new()
	target.collision_layer = collision_layer
	target.set_script(preload("res://tests/melee_dummy_target.gd"))
	target.add_to_group(group)
	var col := CollisionShape3D.new()
	# Mimic the player mech body: a tall capsule (radius 1.0, ~y 0..4.5) so a
	# RUSHER can physically close to within its 3.5 melee reach and the swing
	# ray (fired at y=3.0) connects.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.0
	capsule.height = 4.5
	col.shape = capsule
	col.position = Vector3(0, 2.25, 0)
	target.add_child(col)
	# Position must be set before add_child, or the body briefly spawns at the
	# parent origin and the physics engine depenetrates it (launching it away).
	target.position = pos
	add_child(target)
	return target


# Waits wall-clock seconds so the test is independent of the physics tick rate
# (headless can run physics at a different rate than the configured 60 Hz).
func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await get_tree().physics_frame


func _current_state_name(enemy: Node) -> String:
	var st = enemy.state_machine
	if st and st.current_state:
		return str(st.current_state.name)
	return "none"


func _ready() -> void:
	await get_tree().process_frame
	_add_floor()

	# --- stat templates ---
	var full := EnemyAttackTemplates.get_stats(EnemyAttackTemplates.Archetype.RUSHER, true)
	var normal := EnemyAttackTemplates.get_stats(EnemyAttackTemplates.Archetype.RUSHER, false)
	_check(full["attack_range"] == 3.5, "RUSHER full template attack_range is melee (3.5)")
	_check(normal["attack_range"] == 3.5, "RUSHER normal template attack_range is melee (3.5)")
	_check(full["attack_range"] < 10.0, "RUSHER no longer attacks from range")

	var blade := FleetSystem.get_ally_template("ally_blade")
	_check(blade.get("attack_range", -1.0) == 3.5, "ally_blade template attack_range is melee (3.5)")

	# --- enemy RUSHER vs player dummy ---
	var enemy := preload("res://scenes/mecha/enemy_dummy_full.tscn").instantiate()
	enemy.archetype = 0
	enemy.position = Vector3(0, 1.5, 0)
	add_child(enemy)
	await get_tree().physics_frame
	_check(enemy.attack_range == 3.5, "spawned RUSHER reads melee attack_range")
	_check(enemy.state_machine != null, "RUSHER state machine initialised")

	# Player parked 30 units away: far beyond melee reach even at the enemy's
	# actual (2x) movement speed, so it cannot be attacked during Phase 1.
	var player := _build_target(1, "mecha", Vector3(30, 1.5, 0))

	# Phase 1: far away -> the enemy must chase and never deal lock-on damage.
	var chase_deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < chase_deadline:
		if _current_state_name(enemy) == "StateChase":
			break
		await get_tree().physics_frame
	_check(player.damage_taken == 0.0, "no lock-on damage while outside melee range")
	_check(_current_state_name(enemy) == "StateChase", "enemy chases instead of attacking from range")

	# Phase 2: once it closes to melee reach, the swing connects via the forward
	# collision check (the player dummy is in front of it).
	var timeout := Time.get_ticks_msec() + 20000
	while player.damage_taken <= 0.0 and Time.get_ticks_msec() < timeout:
		await get_tree().physics_frame
	_check(player.damage_taken > 0.0, "melee swing deals damage once in range")

	# Phase 3: dodging — park the player in front, then yank it behind the enemy
	# once a telegraph commits. The enemy stays in attack range, so the swing
	# still fires — but along the committed arc, which must now whiff because the
	# hit check is collision-based, not lock-on.
	player.damage_taken = 0.0
	var parked := false
	var dodged := false
	var resolved := false
	timeout = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < timeout:
		await get_tree().physics_frame
		var st = enemy.state_machine
		if not (st and st.current_state and st.current_state.name == "StateAttack"):
			continue
		var att = st.current_state
		if not parked:
			# Park only on a fresh attack cycle so no half-wound swing is aimed at it.
			if att.attack_timer > 1.0:
				player.position = enemy.position + Vector3(2, 0, 0)
				parked = true
		elif att.get("_telegraph_active") == true:
			# Committed: the swing will follow the arc aimed where the player was
			# at telegraph time. Pull the player behind (still within attack range
			# so the enemy doesn't transition out) and let the swing resolve.
			player.position = enemy.position + Vector3(0, 0, -3)
			dodged = true
			var res_end := Time.get_ticks_msec() + 3000
			while Time.get_ticks_msec() < res_end:
				await get_tree().physics_frame
				var s2 = enemy.state_machine
				if s2 and s2.current_state and s2.current_state.name == "StateAttack":
					if s2.current_state.attack_timer > 1.5:
						resolved = true
						break
				else:
					resolved = true
					break
			break
	_check(parked and dodged and resolved, "enemy committed a swing the player can dodge")
	_check(player.damage_taken == 0.0, "dodged swing deals no damage (collision-based)")

	# --- ally RUSHER vs enemy dummy ---
	# Free the RUSHER so it can't interfere, and park the ally in melee range of
	# the grunt so the first swing (attack_timer starts at 0) fires immediately.
	enemy.queue_free()
	await get_tree().physics_frame

	var ally := preload("res://scenes/mecha/ally_dummy.tscn").instantiate()
	ally.archetype = 0
	ally.template_id = "ally_blade"
	ally.position = Vector3(-26.6, 1.5, 0)
	add_child(ally)
	await get_tree().physics_frame
	_check(ally.attack_range == 3.5, "spawned ally_blade reads melee attack_range")

	var grunt := _build_target(8, "enemy", Vector3(-24, 1.5, 0))
	timeout = Time.get_ticks_msec() + 5000
	while grunt.damage_taken <= 0.0 and Time.get_ticks_msec() < timeout:
		await get_tree().physics_frame
	_check(grunt.damage_taken > 0.0, "ally melee swing deals damage via collision")

	print("MELEE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
