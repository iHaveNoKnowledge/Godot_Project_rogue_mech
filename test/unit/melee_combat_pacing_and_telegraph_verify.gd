extends Node

const GroundTelegraphScript = preload("res://scripts/effects/ground_telegraph_indicator.gd")

## =============================================================================
## MELEE COMBAT PACING & TELEGRAPH VERIFICATION SUITE (Phase R21)
## =============================================================================
## Validates:
##   1. Pacing distance & personal space (back-pedal when < 5.5m, circle-strafe at 6-8.5m)
##   2. Direction lock commitment in the final 0.2s of wind-up
##   3. Ground telegraph indicator lifecycle and locked state
##   4. Attacker token mutual exclusion in EnemySquadCoordinator
##   5. Archetype differences (Rusher agile dash vs Shield Melee shield-drop window)
##   6. Recovery punish window (stationary, 0.55-0.70s)
## =============================================================================

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + msg)
	else:
		_fails += 1
		printerr("  FAIL: " + msg)


func _ready() -> void:
	print("--- BEGIN MELEE COMBAT PACING & TELEGRAPH VERIFY ---")
	_test_pacing_and_back_pedal()
	_test_direction_lock_and_tracking()
	_test_ground_telegraph_indicator()
	_test_attacker_token_system()
	_test_archetype_distinction_and_shield_drop()
	_test_recovery_punish_window()
	_test_parry_stagger_interruption()

	print("MELEE_COMBAT_PACING_AND_TELEGRAPH_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


## Test 1: Pacing Distance & Personal Space Maintenance
func _test_pacing_and_back_pedal() -> void:
	print("Test 1: Pacing Distance & Personal Space Maintenance...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy: CharacterBody3D = enemy_scene.instantiate()
	enemy.archetype = 0 # Rusher
	add_child(enemy)

	var target = Node3D.new()
	add_child(target)
	enemy.target = target

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	_check(state_attack != null, "StateAttack exists on enemy")
	state_attack.enter()

	# Case A: Target is too close (< 5.5m, e.g. 3.5m) -> Enemy must back-pedal away
	enemy.global_position = Vector3(0, 0, 0)
	target.global_position = Vector3(0, 0, -3.5) # Ahead at 3.5m
	state_attack.physics_process(0.016)

	var to_target: Vector3 = (target.global_position - enemy.global_position).normalized()
	var forward_dot: float = enemy.velocity.normalized().dot(to_target)
	_check(forward_dot < -0.4, "Enemy back-pedals firmly away from target when closer than 5.5m (dot=%.2f < -0.4)" % forward_dot)

	# Case B: Target is in sweet spot (7.0m) -> Enemy circle-strafes (velocity perpendicular)
	target.global_position = Vector3(0, 0, -7.0)
	state_attack.physics_process(0.016)

	var vel_norm := enemy.velocity.normalized()
	var dot_radial := absf(vel_norm.dot(to_target))
	_check(dot_radial < 0.65, "Enemy circle-strafes laterally rather than rushing straight at target (radial_dot=%.2f < 0.65)" % dot_radial)
	_check(enemy.velocity.length() > 1.0, "Enemy has active pacing velocity at 7.0m (%.2f m/s)" % enemy.velocity.length())

	target.queue_free()
	enemy.queue_free()


## Test 2: Direction Lock & Tracking in Wind-up Phase
func _test_direction_lock_and_tracking() -> void:
	print("Test 2: Direction Lock & Tracking in Wind-up Phase...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy: CharacterBody3D = enemy_scene.instantiate()
	enemy.archetype = 0 # Rusher
	add_child(enemy)

	var target = Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -7.0)
	enemy.target = target

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	state_attack.enter()

	# Start windup
	state_attack._start_melee_windup()
	_check(state_attack.melee_phase == state_attack.MeleePhase.WINDUP, "StateAttack transitioned to WINDUP phase")
	_check(not state_attack.is_direction_locked, "is_direction_locked is initially false at start of windup")

	# Tracking window (> 0.35s)
	state_attack.melee_phase_timer = 0.45
	target.global_position = Vector3(5.0, 0, -5.0) # Player moves sideways
	state_attack.physics_process(0.016)

	var dir_at_045: Vector3 = state_attack._melee_swing_dir
	_check(dir_at_045.x > 0.3, "Enemy tracks target dynamically during early windup (dir.x=%.2f > 0.3)" % dir_at_045.x)
	_check(not state_attack.is_direction_locked, "is_direction_locked remains false while timer > 0.35s")

	# Direction Lock window (<= 0.35s for Rusher)
	state_attack.melee_phase_timer = 0.25
	state_attack.physics_process(0.016)
	_check(state_attack.is_direction_locked, "is_direction_locked engages true early at 0.35s window")

	var locked_dir: Vector3 = state_attack._melee_swing_dir
	# Player dashes further right during locked window
	target.global_position = Vector3(15.0, 0, 0.0)
	state_attack.physics_process(0.016)

	_check(state_attack._melee_swing_dir.is_equal_approx(locked_dir), "Swing direction remains strictly locked despite player movement (Direction Lock holds)")

	target.queue_free()
	enemy.queue_free()


## Test 3: Ground Telegraph Indicator Lifecycle
func _test_ground_telegraph_indicator() -> void:
	print("Test 3: Ground Telegraph Indicator Lifecycle...")
	var indicator: Node3D = GroundTelegraphScript.new()
	add_child(indicator)
	indicator.setup(2.4, 5.5)

	_check(indicator.corridor_width == 2.4, "Indicator corridor_width is 2.4m")
	_check(indicator.corridor_length == 5.5, "Indicator corridor_length is 5.5m")
	_check(not indicator.is_locked(), "Indicator is_locked is false initially")

	indicator.update_orientation(Vector3(1, 0, 2), Vector3(0, 0, -1))
	_check(indicator.global_position == Vector3(1, 0, 2), "Indicator anchor matches enemy position")

	indicator.set_locked(true)
	_check(indicator.is_locked(), "Indicator is_locked is true after lock engagement")

	# Check integration with StateAttack
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy: CharacterBody3D = enemy_scene.instantiate()
	enemy.archetype = 0
	add_child(enemy)

	var target = Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -7.0)
	enemy.target = target

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	state_attack.enter()
	state_attack._start_melee_windup()

	_check(state_attack.ground_telegraph != null, "ground_telegraph instance spawned during windup")
	_check(is_instance_valid(state_attack.ground_telegraph), "ground_telegraph is valid Node in scene tree")

	# Transition to lunge -> indicator dismissed
	state_attack._start_melee_lunge()
	_check(state_attack.ground_telegraph == null, "ground_telegraph dismissed and cleared upon entering LUNGE")

	target.queue_free()
	enemy.queue_free()
	indicator.queue_free()


## Test 4: Attacker Token System in EnemySquadCoordinator
func _test_attacker_token_system() -> void:
	print("Test 4: Attacker Token System in EnemySquadCoordinator...")
	var coordinator := EnemySquadCoordinator.new()
	add_child(coordinator)
	coordinator.setup_squad("test_squad", "Alpha Team")

	var m1 = Node3D.new()
	var m2 = Node3D.new()
	var m3 = Node3D.new()
	add_child(m1)
	add_child(m2)
	add_child(m3)

	coordinator.register_member(m1, {"name": "Grunt1"})
	coordinator.register_member(m2, {"name": "Grunt2"})
	coordinator.register_member(m3, {"name": "Grunt3"})

	_check(coordinator.get_living_count() == 3, "Squad has 3 living members")

	# Mech 1 requests attacker token
	var ok1 := coordinator.request_attacker_token(m1)
	_check(ok1, "Mech 1 successfully acquires attacker token")
	_check(coordinator.has_attacker_token(m1), "Coordinator tracks Mech 1 token")

	# Mech 2 requests attacker token (should be denied because max=1 for squad <= 4)
	var ok2 := coordinator.request_attacker_token(m2)
	_check(not ok2, "Mech 2 is denied attacker token while Mech 1 is attacking (swarming prevented)")
	_check(not coordinator.has_attacker_token(m2), "Mech 2 does not hold token")

	# Mech 1 re-requests (idempotent hold)
	_check(coordinator.request_attacker_token(m1), "Mech 1 re-request is permitted (already holding)")

	# Mech 1 finishes attack & releases token
	coordinator.release_attacker_token(m1)
	_check(not coordinator.has_attacker_token(m1), "Mech 1 token released")

	# Mech 2 now can acquire token
	var ok2_after := coordinator.request_attacker_token(m2)
	_check(ok2_after, "Mech 2 successfully acquires token after Mech 1 release")

	# Unregistering Mech 2 auto-releases token
	coordinator.unregister_member(m2)
	_check(not coordinator.has_attacker_token(m2), "Unregistering member releases token automatically")

	m1.queue_free()
	m2.queue_free()
	m3.queue_free()
	coordinator.queue_free()


## Test 5: Archetype Distinction & Shield-Drop Window
func _test_archetype_distinction_and_shield_drop() -> void:
	print("Test 5: Archetype Distinction & Shield-Drop Window...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")

	# Rusher (0)
	var rusher: CharacterBody3D = enemy_scene.instantiate()
	rusher.archetype = 0
	add_child(rusher)
	var rusher_state = rusher.state_machine.get_node_or_null("StateAttack")
	rusher_state.enter()
	rusher_state._start_melee_windup()

	_check(rusher_state.melee_windup_duration == 0.60, "Rusher has agile 0.60s windup duration")
	_check(rusher_state.melee_recovery_duration == 0.85, "Rusher has 0.85s recovery duration")

	# Shield Melee (4)
	var shield_m: CharacterBody3D = enemy_scene.instantiate()
	shield_m.archetype = 4
	add_child(shield_m)
	var shield_state = shield_m.state_machine.get_node_or_null("StateAttack")
	shield_state.enter()

	_check(shield_m.is_shield_active(), "Shield Melee has barrier active during pacing")

	# Commit to windup
	shield_state._start_melee_windup()
	_check(shield_state.melee_windup_duration == 0.80, "Shield Melee has deliberate 0.80s windup duration")
	_check(shield_state.melee_recovery_duration == 1.00, "Shield Melee has 1.00s recovery duration")
	_check(not shield_m.is_shield_active(), "Shield Melee DROPS barrier during wind-up (exposed punish window)")

	# End of recovery & disengage restores shield
	shield_state._start_melee_disengage()
	_check(shield_m.is_shield_active(), "Shield Melee re-raises barrier upon disengaging back to pacing")

	rusher.queue_free()
	shield_m.queue_free()


## Test 6: Recovery Punish Window
func _test_recovery_punish_window() -> void:
	print("Test 6: Recovery Punish Window...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy: CharacterBody3D = enemy_scene.instantiate()
	enemy.archetype = 0
	add_child(enemy)

	var target = Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -7.0)
	enemy.target = target

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	state_attack.enter()

	state_attack._start_melee_recovery()
	_check(state_attack.melee_phase == state_attack.MeleePhase.RECOVERY, "StateAttack is in RECOVERY phase")
	_check(enemy.velocity == Vector3.ZERO, "Enemy is completely stationary at start of recovery (velocity=ZERO)")

	state_attack.physics_process(0.016)
	_check(enemy.velocity.x == 0.0 and enemy.velocity.z == 0.0, "Enemy remains frozen horizontally during recovery window")

	target.queue_free()
	enemy.queue_free()

## Test 7: Parry Stagger Interruption & Stun Window
func _test_parry_stagger_interruption() -> void:
	print("Test 7: Parry Stagger Interruption & Stun Window...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy: CharacterBody3D = enemy_scene.instantiate()
	enemy.archetype = 4 # Shield Melee
	add_child(enemy)

	var target = Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -7.0)
	enemy.target = target

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	state_attack.enter()
	state_attack._start_melee_windup()

	_check(state_attack.ground_telegraph != null, "Telegraph exists during windup")

	# Player parries enemy strike
	enemy.parry_stagger(1.5, Vector3(0, 0, 1))

	_check(state_attack.melee_phase == state_attack.MeleePhase.RECOVERY, "Parry forces StateAttack immediately into RECOVERY phase")
	_check(state_attack.melee_phase_timer == 1.5, "Parry sets full 1.5s heavy stagger duration")
	_check(state_attack.ground_telegraph == null, "Ground telegraph immediately cancelled on parry")
	_check(not enemy.is_shield_active(), "Shield remains down during parry stun window")
	_check(enemy.velocity.x == 0.0 and enemy.velocity.z == 0.0, "Attacker velocity cancelled horizontally on parry")

	target.queue_free()
	enemy.queue_free()
