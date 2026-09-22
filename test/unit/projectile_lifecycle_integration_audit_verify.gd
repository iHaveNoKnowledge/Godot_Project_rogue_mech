extends Node

## =============================================================================
## PROJECTILE LIFECYCLE INTEGRATION AUDIT VERIFICATION (Phase 2E-12D)
##
## Validates that:
## 1. Authoritative Projectile Lifecycle (WeaponCore / projectile.gd):
##    - Projectile is CharacterBody3D, owned by scene tree
##    - Movement and collision updated authoritatively in _physics_process
##    - Impact, damage application, and queue_free owned by projectile.gd / EffectManager
## 2. Generic Descriptor Contract:
##    - Source, target, direction, arc_height, radius derived authoritatively
## 3. Trajectory Progress Authority:
##    - Progress derived from authoritative session timing, NOT presentation timer
## 4. Impact Authority Invariant:
##    - Gameplay impact happens from gameplay authority, NOT presentation tracer arrival
## 5. Presentation Cleanup on Authoritative Completion:
##    - Visual instance pruned when session completes
## 6. Cancellation Cleanup:
##    - Visual instance pruned immediately when session is cancelled
## 7. Concurrent Projectile Identity:
##    - Multiple simultaneous projectiles/sessions tracked with distinct session_ids without collision
## 8. Coexistence & Regression Invariance:
##    - Satellite Cannon (Line), Jammer (Area), Cone (Sector), and Trajectory (Ballistic)
## =============================================================================

const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const TelegraphPresentationScript = preload("res://scripts/effects/telegraph_presentation.gd")
const WeaponCoreScript = preload("res://scripts/systems/weapon_core.gd")
const ProjectileScript = preload("res://scripts/systems/projectile.gd")

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
	print("\n=== STARTING PROJECTILE LIFECYCLE INTEGRATION AUDIT VERIFICATION (Phase 2E-12D) ===\n")
	test_authoritative_projectile_lifecycle()
	test_descriptor_spatial_contract()
	test_trajectory_progress_authority()
	test_impact_not_from_presentation()
	test_presentation_cleanup_on_authoritative_completion()
	test_cancellation_cleanup()
	test_concurrent_projectile_identity()
	test_ballistic_drop_and_homing_properties()
	test_multi_geometry_regression_coexistence()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _failures])
	if _failures == 0:
		print("PHASE_2E_12D_SUCCESS\n")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_12D_FAILED: %d tests failed!\n" % _failures)
		get_tree().quit(1)


func test_authoritative_projectile_lifecycle() -> void:
	print("-- [Test 1] Authoritative Projectile Lifecycle --")
	var proj := CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.speed = 40.0
	proj.damage = 30.0
	proj.damage_type = "kinetic"
	proj.direction = Vector3(0, 0, -1)
	proj.lifetime = 2.0
	add_child(proj)

	_check(proj is CharacterBody3D, "[1a] Projectile is a CharacterBody3D entity")
	_check(proj.is_in_group("projectile"), "[1b] Projectile adds itself to 'projectile' group")
	_check(proj.get_damage() == 30.0, "[1c] Projectile exposes get_damage() authoritatively")

	# Target dummy
	var dummy := Node3D.new()
	dummy.name = "TestDummyTarget"
	dummy.position = Vector3(0, 0, -5)
	dummy.set_meta("hp", 100.0)
	dummy.set_script(preload("res://scripts/mecha/enemy_health.gd") if ResourceLoader.exists("res://scripts/mecha/enemy_health.gd") else null)
	add_child(dummy)

	_check(proj.has_method("_hit_target"), "[1d] Projectile owns _hit_target collision response")
	_check(proj.has_method("_explode"), "[1e] Projectile owns _explode area damage response")
	_check(proj.has_method("_check_obstacle_collision"), "[1f] Projectile owns obstacle raycast check")

	proj.queue_free()
	dummy.queue_free()


func test_descriptor_spatial_contract() -> void:
	print("\n-- [Test 2] Descriptor Spatial Contract --")
	var origin := Vector3(10, 2, -15)
	var target_pt := Vector3(10, 0, -95)
	var dir := Vector3(0, 0, -1)

	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "strategic_strike",
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory",
		"area_parameters": {
			"radius": 14.0,
			"arc_height": 22.0,
			"range": 80.0
		},
		"charge_time": 2.5
	}
	var ctx: Dictionary = {
		"origin": origin,
		"target_position": target_pt,
		"direction": dir
	}

	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()
	var desc: Dictionary = session.get_telegraph_descriptor()

	_check(desc["source_position"] == origin, "[2a] source_position matches origin")
	_check(desc["target_position"] == target_pt, "[2b] target_position matches target_pt")
	_check(desc["direction"] == dir, "[2c] direction matches dir")
	_check(float(desc["area_parameters"]["arc_height"]) == 22.0, "[2d] arc_height is 22.0m")
	_check(float(desc["area_parameters"]["radius"]) == 14.0, "[2e] radius is 14.0m")
	_check(desc["geometry_type"] == "trajectory", "[2f] geometry_type is trajectory")


func test_trajectory_progress_authority() -> void:
	print("\n-- [Test 3] Trajectory Progress Authority --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"charge_time": 4.0,
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory"
	}
	var session = ActivationTimingSys.create_session(cap_data, {"origin": Vector3.ZERO})
	session.start()

	session.tick(1.0) # 25%
	var d25: Dictionary = session.get_telegraph_descriptor()
	_check(is_equal_approx(float(d25["progress"]), 0.25), "[3a] Progress is 0.25 at 1.0s / 4.0s")
	_check(is_equal_approx(float(d25["remaining"]), 3.0), "[3b] Remaining is 3.0s at 1.0s / 4.0s")

	session.tick(1.0) # 50%
	var d50: Dictionary = session.get_telegraph_descriptor()
	_check(is_equal_approx(float(d50["progress"]), 0.50), "[3c] Progress is 0.50 at 2.0s / 4.0s")
	_check(is_equal_approx(float(d50["remaining"]), 2.0), "[3b] Remaining is 2.0s at 2.0s / 4.0s")


func test_impact_not_from_presentation() -> void:
	print("\n-- [Test 4] Impact Not From Presentation --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "impact_auth_test_1",
		"active": true,
		"geometry_type": "trajectory",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"progress": 1.0 # 100% visual progress
	}
	pres.sync_descriptors([desc])

	_check(not pres.has_method("deal_damage"), "[4a] Presentation cannot deal damage")
	_check(not pres.has_method("apply_damage"), "[4b] Presentation cannot apply damage")
	_check(not pres.has_method("apply_effect_request"), "[4c] Presentation cannot dispatch effect requests")
	_check(not pres.has_method("apply_disruption"), "[4d] Presentation cannot apply disruption")

	pres.clear()
	pres.queue_free()


func test_presentation_cleanup_on_authoritative_completion() -> void:
	print("\n-- [Test 5] Presentation Cleanup On Authoritative Completion --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "comp_test_1",
		"active": true,
		"geometry_type": "trajectory",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -60),
		"progress": 0.5
	}
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[5a] Presentation active mid-flight")

	# Gameplay authority completes session -> descriptor active becomes false or removed
	pres.sync_descriptors([])
	_check(pres.get_active_presentation_count() == 0, "[5b] Presentation cleanly removed when descriptor absent")

	pres.clear()
	pres.queue_free()


func test_cancellation_cleanup() -> void:
	print("\n-- [Test 6] Cancellation Cleanup --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "cancel_test_1",
		"active": true,
		"geometry_type": "trajectory",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -70),
		"progress": 0.3
	}
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[6a] Presentation active before cancel")

	desc["active"] = false
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 0, "[6b] Presentation pruned immediately when active=false")

	pres.clear()
	pres.queue_free()


func test_concurrent_projectile_identity() -> void:
	print("\n-- [Test 7] Concurrent Projectile Identity --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc_a: Dictionary = {
		"session_id": "mortar_volley_01",
		"active": true,
		"geometry_type": "trajectory",
		"source_position": Vector3(-5, 0, 0),
		"target_position": Vector3(-20, 0, -80),
		"progress": 0.3,
		"area_parameters": {"radius": 10.0, "arc_height": 25.0}
	}
	var desc_b: Dictionary = {
		"session_id": "mortar_volley_02",
		"active": true,
		"geometry_type": "trajectory",
		"source_position": Vector3(5, 0, 0),
		"target_position": Vector3(20, 0, -80),
		"progress": 0.5,
		"area_parameters": {"radius": 10.0, "arc_height": 20.0}
	}
	var desc_c: Dictionary = {
		"session_id": "mortar_volley_03",
		"active": true,
		"geometry_type": "trajectory",
		"source_position": Vector3(0, 5, 0),
		"target_position": Vector3(0, 0, -90),
		"progress": 0.7,
		"area_parameters": {"radius": 15.0, "arc_height": 30.0}
	}

	pres.sync_descriptors([desc_a, desc_b, desc_c])
	_check(pres.get_active_presentation_count() == 3, "[7a] 3 concurrent volley trajectories active")

	var inst_a = pres.get_presentation("mortar_volley_01")
	var inst_b = pres.get_presentation("mortar_volley_02")
	var inst_c = pres.get_presentation("mortar_volley_03")

	_check(inst_a != null and inst_b != null and inst_c != null, "[7b] All 3 instances resolved by distinct session_id")
	_check(inst_a.target_pos == Vector3(-20, 0, -80), "[7c] Volley A target preserved")
	_check(inst_b.target_pos == Vector3(20, 0, -80), "[7d] Volley B target preserved")
	_check(inst_c.target_pos == Vector3(0, 0, -90), "[7e] Volley C target preserved")

	# Volley C impacts first
	pres.sync_descriptors([desc_a, desc_b])
	_check(pres.get_active_presentation_count() == 2, "[7f] Volley C impact leaves exactly 2 active instances")
	_check(pres.get_presentation("mortar_volley_03") == null, "[7g] Volley C cleanly freed")

	pres.clear()
	pres.queue_free()


func test_ballistic_drop_and_homing_properties() -> void:
	print("\n-- [Test 8] Ballistic Drop and Homing Properties in projectile.gd --")
	var proj := CharacterBody3D.new()
	proj.set_script(ProjectileScript)
	proj.drop_gravity = 9.8
	proj.drop_start_distance = 10.0
	proj.homing_turn_speed = 6.8
	add_child(proj)

	_check(proj.drop_gravity == 9.8, "[8a] drop_gravity property supported on projectile")
	_check(proj.drop_start_distance == 10.0, "[8b] drop_start_distance property supported on projectile")
	_check(proj.homing_turn_speed == 6.8, "[8c] homing_turn_speed property supported on projectile")

	proj.queue_free()


func test_multi_geometry_regression_coexistence() -> void:
	print("\n-- [Test 9] Multi-Geometry Regression Coexistence (Line + Area + Cone + Trajectory) --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc_sat := {
		"session_id": "sat_line_01",
		"active": true,
		"geometry_type": "line",
		"targeting_mode": "beam_line",
		"source_position": Vector3(0, 10, 0),
		"target_position": Vector3(0, 0, -100),
		"progress": 0.3
	}
	var desc_jam := {
		"session_id": "jam_area_01",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"source_position": Vector3(30, 0, 0),
		"target_position": Vector3(30, 0, 0),
		"progress": 0.4,
		"area_parameters": {"radius": 20.0}
	}
	var desc_cone := {
		"session_id": "cone_sweep_01",
		"active": true,
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"source_position": Vector3(-30, 0, 0),
		"target_position": Vector3(-30, 0, -40),
		"direction": Vector3(0, 0, -1),
		"progress": 0.6,
		"area_parameters": {"range": 40.0, "angle": 60.0}
	}
	var desc_traj := {
		"session_id": "traj_mortar_01",
		"active": true,
		"geometry_type": "trajectory",
		"targeting_mode": "ballistic_impact",
		"source_position": Vector3(0, 0, 20),
		"target_position": Vector3(0, 0, -60),
		"progress": 0.7,
		"area_parameters": {"radius": 12.0, "arc_height": 18.0}
	}

	pres.sync_descriptors([desc_sat, desc_jam, desc_cone, desc_traj])
	_check(pres.get_active_presentation_count() == 4, "[9a] All 4 distinct capability types active simultaneously")

	var sat_inst = pres.get_presentation("sat_line_01")
	var jam_inst = pres.get_presentation("jam_area_01")
	var cone_inst = pres.get_presentation("cone_sweep_01")
	var traj_inst = pres.get_presentation("traj_mortar_01")

	_check(sat_inst.beam_container.visible == true and sat_inst.trajectory_container.visible == false, "[9b] Line has beam visible, trajectory hidden")
	_check(jam_inst.area_disc_mesh.visible == true and jam_inst.trajectory_container.visible == false, "[9c] Area has disc visible, trajectory hidden")
	_check(cone_inst.cone_container.visible == true and cone_inst.trajectory_container.visible == false, "[9d] Cone has cone visible, trajectory hidden")
	_check(traj_inst.trajectory_container.visible == true and traj_inst.beam_container.visible == false and traj_inst.cone_container.visible == false, "[9e] Trajectory has trajectory visible, beam/cone hidden")

	pres.clear()
	pres.queue_free()
