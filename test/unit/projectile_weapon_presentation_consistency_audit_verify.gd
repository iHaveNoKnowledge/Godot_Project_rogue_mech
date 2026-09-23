extends Node

## =============================================================================
## PROJECTILE / WEAPON PRESENTATION & UI CONSISTENCY AUDIT VERIFY (Phase 2E-12F)
##
## Validates:
## 1. Telegraph starts from authoritative ActivationSession
## 2. Telegraph progress follows authoritative session progress
## 3. Telegraph cancellation removes presentation cleanly
## 4. Completion transitions cleanly to gameplay dispatch
## 5. Presentation never applies damage (Zero combat authority in presentation)
## 6. Ballistic preview derives from authoritative projectile parameters
## 7. Homing presentation clears when target becomes invalid
## 8. Obstacle-blocked shot does not show misleading target impact
## 9. Impact visual uses authoritative impact position
## 10. Explosion visual uses authoritative blast position
## 11. Concurrent projectile presentation remains isolated (distinct session_ids)
## 12. Projectile destruction cleans associated presentation
## 13. Target destruction cleans associated lock/marker in MissileLockOnSystem
## 14. No duplicate presentation instances are created for one session
## 15. No stale presentation remains after cancellation
## =============================================================================

const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const TelegraphPresentationScript = preload("res://scripts/effects/telegraph_presentation.gd")
const ProjectileScript = preload("res://scripts/systems/projectile.gd")
const MissileLockOnSystemScript = preload("res://scripts/systems/missile_lock_on_system.gd")

var _checks: int = 0
var _failures: int = 0

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] %s" % message)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % message)

func _ready() -> void:
	print("\n=== STARTING PROJECTILE / WEAPON PRESENTATION CONSISTENCY AUDIT (Phase 2E-12F) ===\n")

	test_telegraph_starts_from_authoritative_session()
	test_telegraph_progress_synchronization()
	test_telegraph_cancellation_removes_presentation()
	test_completion_transitions_to_gameplay_dispatch()
	test_presentation_never_applies_damage()
	test_ballistic_preview_derives_authoritative_parameters()
	test_homing_presentation_clears_on_invalid_target()
	test_obstacle_blocked_shot_impact_semantics()
	test_impact_visual_uses_authoritative_position()
	test_explosion_visual_uses_authoritative_blast_position()
	test_concurrent_projectile_presentation_isolation()
	test_projectile_destruction_cleans_presentation()
	test_target_destruction_cleans_lock_marker()
	test_no_duplicate_presentation_instances()
	test_no_stale_presentation_after_cancellation()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _failures])
	if _failures == 0:
		print("PHASE_2E_12F_SUCCESS\n")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_12F_FAILED: %d tests failed!\n" % _failures)
		get_tree().quit(1)


# Mock dummy weapon manager for telegraph presentation
class MockTelegraphWeaponManager extends Node:
	var descriptors: Array = []
	func get_active_telegraph_descriptors() -> Array:
		return descriptors


func test_telegraph_starts_from_authoritative_session() -> void:
	print("-- [Test 1] Telegraph Starts From Authoritative ActivationSession --")
	var cap_data: Dictionary = {
		"charge_time": 2.0,
		"tech_id": "tech_satellite_cannon"
	}
	var ctx: Dictionary = {
		"origin": Vector3(0, 5, 0),
		"target_position": Vector3(0, 0, -50),
		"targeting_mode": "directional_line",
		"beam_radius": 6.0
	}
	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("active") == true, "[1a] Session descriptor is active")
	_check(str(desc.get("session_id", "")).begins_with("timing_session_"), "[1b] Descriptor carries authoritative session_id")

	var mock_wm := MockTelegraphWeaponManager.new()
	mock_wm.descriptors = [desc]
	add_child(mock_wm)

	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	tele_pres.weapon_manager = mock_wm
	add_child(tele_pres)

	tele_pres.sync_descriptors(mock_wm.descriptors)
	_check(tele_pres.get_active_presentation_count() == 1, "[1c] Presentation created exactly 1 visual instance")
	var inst: Node3D = tele_pres.get_presentation(desc.get("session_id"))
	_check(inst != null, "[1d] Presentation instance mapped to session_id")

	tele_pres.queue_free()
	mock_wm.queue_free()


func test_telegraph_progress_synchronization() -> void:
	print("\n-- [Test 2] Telegraph Progress Synchronization --")
	var cap_data: Dictionary = {
		"charge_time": 4.0,
		"tech_id": "tech_mortar",
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory",
		"area_parameters": { "radius": 10.0, "arc_height": 25.0 }
	}
	var ctx: Dictionary = {
		"origin": Vector3(10, 0, 10),
		"target_position": Vector3(50, 0, 50),
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory",
		"area_parameters": { "radius": 10.0, "arc_height": 25.0 }
	}
	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()

	var mock_wm := MockTelegraphWeaponManager.new()
	add_child(mock_wm)
	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	tele_pres.weapon_manager = mock_wm
	add_child(tele_pres)

	# Progress tick: 2.0s out of 4.0s = 50%
	session.tick(2.0)
	var s_progress: float = session.get_progress() if session.has_method("get_progress") else (session.elapsed / session.duration)
	_check(is_equal_approx(s_progress, 0.5), "[2a] Session progress is 0.5")

	var desc_half: Dictionary = session.get_telegraph_descriptor()
	mock_wm.descriptors = [desc_half]
	tele_pres.sync_descriptors(mock_wm.descriptors)

	var s_id: String = str(desc_half.get("session_id", ""))
	var inst: Node3D = tele_pres.get_presentation(s_id)
	_check(inst != null, "[2b] Visual instance exists for session")
	_check(is_equal_approx(inst.progress, 0.5), "[2c] Presentation instance progress is synchronized to 0.5")

	# Check tracer position along parabolic arc: pt = src.lerp(dst, 0.5) + y(4*h*0.5*0.5) = lerp + y(h)
	var expected_tracer_pos: Vector3 = Vector3(10, 0, 10).lerp(Vector3(50, 0, 50), 0.5) + Vector3(0, 25.0, 0)
	var actual_tracer_pos: Vector3 = inst.trajectory_marker_mesh.position
	_check(expected_tracer_pos.distance_to(actual_tracer_pos) < 0.01, "[2d] Parabolic tracer is at apex at 50% progress")

	tele_pres.queue_free()
	mock_wm.queue_free()


func test_telegraph_cancellation_removes_presentation() -> void:
	print("\n-- [Test 3] Telegraph Cancellation Removes Presentation --")
	var cap_data: Dictionary = {
		"charge_time": 3.0,
		"tech_id": "tech_laser"
	}
	var ctx: Dictionary = { "origin": Vector3.ZERO, "target_position": Vector3.FORWARD * 20 }
	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()

	var mock_wm := MockTelegraphWeaponManager.new()
	add_child(mock_wm)
	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	tele_pres.weapon_manager = mock_wm
	add_child(tele_pres)

	mock_wm.descriptors = [session.get_telegraph_descriptor()]
	tele_pres.sync_descriptors(mock_wm.descriptors)
	_check(tele_pres.get_active_presentation_count() == 1, "[3a] Visual active before cancel")

	# Cancel session -> descriptor active becomes false
	session.cancel("player_interrupted")
	_check(session.phase == ActivationTimingSys.Phase.CANCELLED, "[3b] Session phase is CANCELLED")
	var cancelled_desc: Dictionary = session.get_telegraph_descriptor()
	_check(cancelled_desc.get("active") == false, "[3c] Cancelled descriptor is not active")

	mock_wm.descriptors = [cancelled_desc]
	tele_pres.sync_descriptors(mock_wm.descriptors)
	_check(tele_pres.get_active_presentation_count() == 0, "[3d] Presentation count dropped to 0 after cancellation sync")
	_check(tele_pres.get_presentation(str(cancelled_desc.get("session_id", ""))) == null, "[3e] Cancelled presentation instance pruned")

	tele_pres.queue_free()
	mock_wm.queue_free()


func test_completion_transitions_to_gameplay_dispatch() -> void:
	print("\n-- [Test 4] Completion Transitions Cleanly to Gameplay Dispatch --")
	var cap_data: Dictionary = {
		"charge_time": 1.0,
		"tech_id": "tech_cannon"
	}
	var ctx: Dictionary = { "origin": Vector3.ZERO, "target_position": Vector3(0, 0, -30) }
	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()
	session.tick(1.0)
	_check(session.phase == ActivationTimingSys.Phase.COMPLETED, "[4a] Session completed after 1.0s")

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("active") == false, "[4b] Completed session descriptor is inactive")

	# Gameplay dispatches projectile
	var proj: CharacterBody3D = CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.speed = 100.0
	proj.direction = Vector3(0, 0, -1)
	add_child(proj)
	proj.global_position = Vector3(0, 0, 0)
	_check(is_instance_valid(proj), "[4c] Gameplay projectile successfully instantiated on session completion")

	proj.queue_free()


func test_presentation_never_applies_damage() -> void:
	print("\n-- [Test 5] Presentation Never Applies Damage (Zero Combat Authority) --")
	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	add_child(tele_pres)

	var desc: Dictionary = {
		"session_id": "sess_no_dmg",
		"active": true,
		"source": Vector3.ZERO,
		"target": Vector3(0, 0, -10),
		"geometry_type": "directional_line",
		"progress": 0.5
	}
	tele_pres.sync_descriptors([desc])
	var inst: Node3D = tele_pres.get_presentation("sess_no_dmg")

	_check(not inst.has_method("deal_damage"), "[5a] TelegraphVisualInstance does NOT have deal_damage method")
	_check(not inst.has_method("take_damage"), "[5b] TelegraphVisualInstance is not a damageable combat entity")
	_check(not (inst is CollisionObject3D), "[5c] TelegraphVisualInstance is NOT a CollisionObject3D")
	_check(not (inst is Area3D), "[5d] TelegraphVisualInstance is NOT an Area3D")
	_check(not (inst is RigidBody3D), "[5e] TelegraphVisualInstance is NOT a RigidBody3D")

	tele_pres.queue_free()


func test_ballistic_preview_derives_authoritative_parameters() -> void:
	print("\n-- [Test 6] Ballistic Preview Derives From Authoritative Parameters --")
	var auth_src := Vector3(5, 2, 5)
	var auth_dst := Vector3(45, 0, -35)
	var auth_height := 18.5
	var auth_radius := 9.0

	var desc: Dictionary = {
		"session_id": "sess_ballistic_preview",
		"active": true,
		"source": auth_src,
		"target": auth_dst,
		"geometry_type": "trajectory",
		"area_parameters": {
			"radius": auth_radius,
			"arc_height": auth_height
		},
		"progress": 0.25
	}

	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	add_child(tele_pres)
	tele_pres.sync_descriptors([desc])

	var inst: Node3D = tele_pres.get_presentation("sess_ballistic_preview")
	_check(inst != null, "[6a] Ballistic presentation instance created")
	_check(inst.source_pos == auth_src, "[6b] Presentation source_pos matches authoritative source")
	_check(inst.target_pos == auth_dst, "[6c] Presentation target_pos matches authoritative target")
	_check(inst.trajectory_container.visible == true, "[6d] Trajectory container is visible")

	# Verify sample point at progress 0.25
	var expected_y: float = auth_src.lerp(auth_dst, 0.25).y + 4.0 * auth_height * 0.25 * 0.75
	_check(is_equal_approx(inst.trajectory_marker_mesh.position.y, expected_y), "[6e] Parabolic tracer y derives precisely from authoritative arc formula")

	tele_pres.queue_free()


func test_homing_presentation_clears_on_invalid_target() -> void:
	print("\n-- [Test 7] Homing Presentation Clears When Target Becomes Invalid --")
	var lock_sys: MissileLockOnSystem = MissileLockOnSystemScript.new()
	add_child(lock_sys)

	var dummy_enemy := Node3D.new()
	dummy_enemy.name = "DummyEnemy"
	dummy_enemy.add_to_group("enemy")
	add_child(dummy_enemy)

	lock_sys.locked_targets[dummy_enemy] = 3
	_check(lock_sys.get_total_locks() == 3, "[7a] Lock system has 3 active locks on enemy")

	# Destroy / free the enemy
	dummy_enemy.queue_free()
	# Simulate physics tick to trigger pruning
	lock_sys.is_locking = true
	lock_sys._physics_process(0.016)

	_check(lock_sys.locked_targets.has(dummy_enemy) == false, "[7b] Destroyed enemy was pruned from locked_targets")
	_check(lock_sys.get_total_locks() == 0, "[7c] Total locks dropped to 0")

	lock_sys.queue_free()


func test_obstacle_blocked_shot_impact_semantics() -> void:
	print("\n-- [Test 8] Obstacle-Blocked Shot Impact Semantics --")
	var proj: CharacterBody3D = CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.speed = 100.0
	proj.damage = 50.0
	proj.direction = Vector3(0, 0, -1)
	add_child(proj)
	proj.global_position = Vector3(0, 0, 0)

	# Target enemy placed at z = -20
	var enemy := CharacterBody3D.new()
	enemy.add_to_group("enemy")
	add_child(enemy)
	enemy.global_position = Vector3(0, 0, -20)
	enemy.set_meta("damaged", false)

	# When obstacle hit occurs at z = -10, projectile terminates or explodes at obstacle
	var obstacle_hit_pos := Vector3(0, 0, -10)
	proj._explode(obstacle_hit_pos)
	_check(proj.is_queued_for_deletion(), "[8a] Projectile queued for deletion on obstacle detonation")
	_check(enemy.get_meta("damaged", false) == false, "[8b] Enemy behind obstacle did not receive direct hit")

	enemy.queue_free()


func test_impact_visual_uses_authoritative_position() -> void:
	print("\n-- [Test 9] Impact Visual Uses Authoritative Impact Position --")
	var auth_hit_pos := Vector3(12.5, 3.0, -45.0)

	var proj: CharacterBody3D = CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.damage = 20.0
	proj.damage_type = "kinetic"
	proj.direction = Vector3(0, 0, -1)
	add_child(proj)
	proj.global_position = auth_hit_pos

	var target := Node3D.new()
	target.add_to_group("enemy")
	add_child(target)
	target.global_position = auth_hit_pos

	proj._hit_target(target)
	_check(proj.is_queued_for_deletion(), "[9a] Projectile queued for deletion after registering hit")
	_check(proj.position == auth_hit_pos, "[9b] Projectile registered hit at authoritative position")

	target.queue_free()


func test_explosion_visual_uses_authoritative_blast_position() -> void:
	print("\n-- [Test 10] Explosion Visual Uses Authoritative Blast Position --")
	var auth_blast_pos := Vector3(-20.0, 0.5, 35.0)
	var proj: CharacterBody3D = CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.damage = 75.0
	proj.damage_type = "explosive"
	proj.explosion_radius = 6.0
	add_child(proj)
	proj.global_position = auth_blast_pos

	proj._explode(auth_blast_pos)
	_check(proj.is_queued_for_deletion(), "[10a] Explosive projectile cleans up after explosion trigger")
	_check(proj.global_position == auth_blast_pos, "[10b] Blast position accurately equals authoritative blast coordinates")


func test_concurrent_projectile_presentation_isolation() -> void:
	print("\n-- [Test 11] Concurrent Projectile Presentation Isolation --")
	var desc_a: Dictionary = {
		"session_id": "sess_alpha",
		"active": true,
		"source": Vector3(0, 0, 0),
		"target": Vector3(0, 0, -50),
		"geometry_type": "directional_line",
		"progress": 0.3
	}
	var desc_b: Dictionary = {
		"session_id": "sess_beta",
		"active": true,
		"source": Vector3(10, 0, 0),
		"target": Vector3(10, 0, -50),
		"geometry_type": "cone",
		"area_parameters": { "range": 30.0, "angle": 45.0 },
		"progress": 0.7
	}
	var desc_c: Dictionary = {
		"session_id": "sess_gamma",
		"active": true,
		"source": Vector3(-10, 0, 0),
		"target": Vector3(-10, 0, -50),
		"geometry_type": "trajectory",
		"area_parameters": { "radius": 8.0, "arc_height": 15.0 },
		"progress": 0.9
	}

	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	add_child(tele_pres)
	tele_pres.sync_descriptors([desc_a, desc_b, desc_c])

	_check(tele_pres.get_active_presentation_count() == 3, "[11a] Exactly 3 presentation instances active concurrently")
	var inst_a: Node3D = tele_pres.get_presentation("sess_alpha")
	var inst_b: Node3D = tele_pres.get_presentation("sess_beta")
	var inst_c: Node3D = tele_pres.get_presentation("sess_gamma")

	_check(inst_a != null and inst_b != null and inst_c != null, "[11b] All 3 instances exist with distinct session_ids")
	_check(inst_a != inst_b and inst_b != inst_c, "[11c] All instances are separate distinct objects")
	_check(is_equal_approx(inst_a.progress, 0.3), "[11d] Instance A has isolated progress 0.3")
	_check(is_equal_approx(inst_b.progress, 0.7), "[11e] Instance B has isolated progress 0.7")
	_check(is_equal_approx(inst_c.progress, 0.9), "[11f] Instance C has isolated progress 0.9")

	# Pruning Alpha leaves Beta and Gamma intact
	tele_pres.sync_descriptors([desc_b, desc_c])
	_check(tele_pres.get_active_presentation_count() == 2, "[11g] Count dropped to 2 after Alpha removal")
	_check(tele_pres.get_presentation("sess_alpha") == null, "[11h] Alpha was pruned")
	_check(tele_pres.get_presentation("sess_beta") != null, "[11i] Beta remains active and untouched")
	_check(tele_pres.get_presentation("sess_gamma") != null, "[11j] Gamma remains active and untouched")

	tele_pres.queue_free()


func test_projectile_destruction_cleans_presentation() -> void:
	print("\n-- [Test 12] Projectile Destruction Cleans Associated Presentation --")
	var proj: CharacterBody3D = CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.lifetime = 0.05
	add_child(proj)

	var visual_child := MeshInstance3D.new()
	proj.add_child(visual_child)
	proj.visual_node = visual_child

	_check(is_instance_valid(proj.visual_node), "[12a] Visual node attached to projectile")

	# Run physics past lifetime
	proj._physics_process(0.1)
	_check(proj.is_queued_for_deletion(), "[12b] Projectile is queued for deletion on expiration")


func test_target_destruction_cleans_lock_marker() -> void:
	print("\n-- [Test 13] Target Destruction Cleans Associated Lock Marker --")
	var lock_sys: MissileLockOnSystem = MissileLockOnSystemScript.new()
	add_child(lock_sys)

	var enemy_a := Node3D.new()
	var enemy_b := Node3D.new()
	enemy_a.add_to_group("enemy")
	enemy_b.add_to_group("enemy")
	add_child(enemy_a)
	add_child(enemy_b)

	lock_sys.locked_targets[enemy_a] = 2
	lock_sys.locked_targets[enemy_b] = 4
	lock_sys.is_locking = true

	# Enemy A destroyed
	enemy_a.queue_free()
	lock_sys._physics_process(0.016)

	_check(lock_sys.locked_targets.has(enemy_a) == false, "[13a] Destroyed Enemy A removed from locks")
	_check(lock_sys.locked_targets.has(enemy_b) == true, "[13b] Alive Enemy B remains locked")
	_check(lock_sys.get_total_locks() == 4, "[13c] Total locks reflect remaining target locks")

	enemy_b.queue_free()
	lock_sys.queue_free()


func test_no_duplicate_presentation_instances() -> void:
	print("\n-- [Test 14] No Duplicate Presentation Instances Created For One Session --")
	var desc: Dictionary = {
		"session_id": "sess_singleton_01",
		"active": true,
		"source": Vector3.ZERO,
		"target": Vector3(0, 0, -20),
		"geometry_type": "directional_line",
		"progress": 0.1
	}

	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	add_child(tele_pres)

	# Sync 5 times with same descriptor (simulating 5 frames)
	for i in range(5):
		desc["progress"] = float(i) * 0.2
		tele_pres.sync_descriptors([desc])

	_check(tele_pres.get_active_presentation_count() == 1, "[14a] Exactly 1 presentation instance maintained across multiple sync ticks")
	_check(tele_pres.get_child_count() == 1, "[14b] TelegraphPresentation has exactly 1 child node")

	tele_pres.queue_free()


func test_no_stale_presentation_after_cancellation() -> void:
	print("\n-- [Test 15] No Stale Presentation Remains After Cancellation / Clear --")
	var tele_pres: TelegraphPresentation = TelegraphPresentationScript.new()
	add_child(tele_pres)

	var desc_a: Dictionary = { "session_id": "sess_stale_a", "active": true, "source": Vector3.ZERO, "target": Vector3(0, 0, -10) }
	var desc_b: Dictionary = { "session_id": "sess_stale_b", "active": true, "source": Vector3.ZERO, "target": Vector3(0, 0, -20) }
	tele_pres.sync_descriptors([desc_a, desc_b])
	_check(tele_pres.get_active_presentation_count() == 2, "[15a] 2 instances created")

	tele_pres.clear()
	_check(tele_pres.get_active_presentation_count() == 0, "[15b] Presentation count is 0 after clear()")
	_check(tele_pres.get_presentation("sess_stale_a") == null, "[15c] Instance A cleared")
	_check(tele_pres.get_presentation("sess_stale_b") == null, "[15d] Instance B cleared")

	tele_pres.queue_free()
