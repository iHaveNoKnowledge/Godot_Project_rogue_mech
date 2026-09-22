extends Node

## =============================================================================
## TRAJECTORY TELEGRAPH GEOMETRY AUDIT VERIFICATION (Phase 2E-12C)
##
## Validates that:
## 1. Generic Telegraph Descriptor cleanly represents travelling/ballistic trajectory geometry:
##    - source, target/impact position, arc_height, impact radius, progress, remaining
## 2. Authoritative Target & Impact Resolution:
##    - target_position derived authoritatively from context target or target entity position
## 3. TelegraphPresentation renders parabolic arc and tracer synchronized to authoritative progress:
##    - tracer follows src.lerp(dst, t) + 4.0 * arc_height * t * (1.0 - t) without presentation drift
## 4. Visual impact ground danger disc positioned at target_pos
## 5. 4-Way Concurrent Coexistence of Line, Area, Cone, and Trajectory geometries
## 6. Lifecycle cleanup on completion and cancellation
## 7. Zero combat/physics authority in the presentation layer (no RigidBody/Area3D/CharacterBody)
## 8. 100% gameplay parity with SpecialWeaponSystem.resolve_affected_targets (TARGETING_BALLISTIC_IMPACT)
## =============================================================================

const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const TelegraphPresentationScript = preload("res://scripts/effects/telegraph_presentation.gd")

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
	print("\n=== STARTING TRAJECTORY TELEGRAPH GEOMETRY AUDIT VERIFICATION (Phase 2E-12C) ===\n")
	test_trajectory_descriptor_contract()
	test_authoritative_impact_target_locking()
	test_parabolic_arc_and_tracer_synchronization()
	test_trajectory_progress_modulation()
	test_concurrent_four_way_geometry_coexistence()
	test_trajectory_lifecycle_cleanup()
	test_zero_combat_and_physics_authority()
	test_gameplay_parity_with_special_weapon_ballistic_impact()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _failures])
	if _failures == 0:
		print("PHASE_2E_12C_SUCCESS\n")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_12C_FAILED: %d tests failed!\n" % _failures)
		get_tree().quit(1)


func test_trajectory_descriptor_contract() -> void:
	print("-- [Test 1] Trajectory Descriptor Contract --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "strategic_strike",
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory",
		"area_parameters": {
			"radius": 12.0,
			"arc_height": 20.0,
			"range": 80.0
		},
		"charge_time": 3.0,
		"cooldown": 25.0,
		"energy_cost": 45.0,
		"tech_id": "tech_strategic_mortar"
	}
	var origin := Vector3(0, 0, 0)
	var target_pt := Vector3(0, 0, -80)
	var ctx := {
		"origin": origin,
		"target_position": target_pt,
		"direction": Vector3(0, 0, -1)
	}

	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()
	session.tick(1.5) # 50% progress

	var desc: Dictionary = session.get_telegraph_descriptor()

	_check(desc.has("session_id") and str(desc["session_id"]) != "", "[1a] Descriptor contains valid session_id")
	_check(bool(desc.get("active", false)) == true, "[1b] Descriptor active is true during flight/charge")
	_check(str(desc.get("geometry_type", "")) == "trajectory", "[1c] geometry_type is trajectory")
	_check(str(desc.get("targeting_mode", "")) == "ballistic_impact", "[1d] targeting_mode is ballistic_impact")
	_check(str(desc.get("area_shape", "")) == "trajectory", "[1e] area_shape is trajectory")
	_check(desc.get("source_position") == origin, "[1f] source_position matches origin")
	_check(desc.get("target_position") == target_pt, "[1g] target_position matches target_pt")
	_check(float(desc.get("area_parameters", {}).get("arc_height", 0.0)) == 20.0, "[1h] area_parameters arc_height is 20.0m")
	_check(float(desc.get("area_parameters", {}).get("radius", 0.0)) == 12.0, "[1i] area_parameters radius is 12.0m")
	_check(is_equal_approx(float(desc.get("progress", 0.0)), 0.5), "[1j] progress is 0.5 at 1.5s / 3.0s")
	_check(is_equal_approx(float(desc.get("remaining", 0.0)), 1.5), "[1k] remaining is 1.5s at 1.5s / 3.0s")


func test_authoritative_impact_target_locking() -> void:
	print("\n-- [Test 2] Authoritative Impact Target Locking --")
	# Target entity dummy
	var dummy := Node3D.new()
	dummy.name = "AuthoritativeImpactTarget"
	dummy.position = Vector3(45.0, 0.0, -60.0)
	add_child(dummy)

	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "strategic_strike",
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory",
		"area_parameters": {
			"radius": 10.0,
			"arc_height": 25.0
		},
		"charge_time": 2.0
	}
	var origin := Vector3(0, 0, 0)
	var ctx := {
		"origin": origin,
		"direction": (dummy.position - origin).normalized(),
		"targets": [dummy]
	}

	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("target_position") == dummy.global_position, "[2a] Impact position locked to authoritative target entity")

	# If dummy moves, locked impact target in context can be tracked or kept fixed
	dummy.position = Vector3(50.0, 0.0, -70.0)
	var desc_updated: Dictionary = session.get_telegraph_descriptor()
	_check(desc_updated.get("target_position") == dummy.global_position, "[2b] Trajectory target updates dynamically with target entity")

	dummy.queue_free()


func test_parabolic_arc_and_tracer_synchronization() -> void:
	print("\n-- [Test 3] Parabolic Arc & Tracer Synchronization --")
	var tele_node = TelegraphPresentationScript.new()
	add_child(tele_node)

	var src := Vector3(0, 5, 0)
	var dst := Vector3(0, 0, -100)
	var arc_h: float = 20.0

	var desc: Dictionary = {
		"session_id": "mortar_test_session_1",
		"active": true,
		"geometry_type": "trajectory",
		"targeting_mode": "ballistic_impact",
		"area_shape": "trajectory",
		"source_position": src,
		"target_position": dst,
		"progress": 0.0,
		"area_parameters": {
			"radius": 8.0,
			"arc_height": arc_h
		}
	}

	tele_node.sync_descriptors([desc])
	var inst = tele_node.get_presentation("mortar_test_session_1")
	_check(inst != null, "[3a] TelegraphVisualInstance spawned for trajectory")
	_check(inst.trajectory_container.visible == true, "[3b] trajectory_container is visible")
	_check(inst.beam_container.visible == false, "[3c] beam_container is hidden")
	_check(inst.cone_container.visible == false, "[3d] cone_container is hidden")
	_check(inst.area_disc_mesh.visible == true, "[3e] ground danger disc is visible at impact zone")
	_check(inst.target_reticle.position == dst, "[3f] target reticle positioned exactly at dst")

	# Check tracer at t = 0.0 (launch)
	# pt = src.lerp(dst, 0.0) + 0 = src
	_check(inst.trajectory_marker_mesh.position.is_equal_approx(src), "[3g] Tracer at t=0.0 is at src")

	# Check tracer at t = 0.5 (apex)
	# pt = src.lerp(dst, 0.5); pt.y += 4.0 * 20.0 * 0.5 * 0.5 = 20.0
	desc["progress"] = 0.5
	tele_node.sync_descriptors([desc])
	var expected_apex := src.lerp(dst, 0.5)
	expected_apex.y += arc_h # 4.0 * 20 * 0.25 = 20
	_check(inst.trajectory_marker_mesh.position.is_equal_approx(expected_apex), "[3h] Tracer at t=0.5 reaches peak arc height")

	# Check tracer at t = 1.0 (impact)
	# pt = src.lerp(dst, 1.0) + 0 = dst
	desc["progress"] = 1.0
	tele_node.sync_descriptors([desc])
	_check(inst.trajectory_marker_mesh.position.is_equal_approx(dst), "[3i] Tracer at t=1.0 lands exactly on dst")

	tele_node.clear()
	tele_node.queue_free()


func test_trajectory_progress_modulation() -> void:
	print("\n-- [Test 4] Trajectory Progress Modulation --")
	var tele_node = TelegraphPresentationScript.new()
	add_child(tele_node)

	var desc: Dictionary = {
		"session_id": "mortar_mod_1",
		"active": true,
		"geometry_type": "trajectory",
		"targeting_mode": "ballistic_impact",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"progress": 0.1,
		"area_parameters": {"radius": 10.0, "arc_height": 15.0}
	}
	tele_node.sync_descriptors([desc])
	var inst = tele_node.get_presentation("mortar_mod_1")

	var emission_low: float = inst.tracer_mat.emission_energy_multiplier
	var traj_emission_low: float = inst.trajectory_mat.emission_energy_multiplier

	desc["progress"] = 0.95
	tele_node.sync_descriptors([desc])

	var emission_high: float = inst.tracer_mat.emission_energy_multiplier
	var traj_emission_high: float = inst.trajectory_mat.emission_energy_multiplier

	_check(emission_high > emission_low, "[4a] Tracer emission increases as projectile approaches impact")
	_check(traj_emission_high > traj_emission_low, "[4b] Trajectory arc emission intensifies as impact nears")

	tele_node.clear()
	tele_node.queue_free()


func test_concurrent_four_way_geometry_coexistence() -> void:
	print("\n-- [Test 5] Concurrent Four-Way Geometry Coexistence --")
	var tele_node = TelegraphPresentationScript.new()
	add_child(tele_node)

	var line_desc := {
		"session_id": "line_satellite",
		"active": true,
		"geometry_type": "line",
		"targeting_mode": "beam_line",
		"source_position": Vector3(0, 10, 0),
		"target_position": Vector3(0, 0, -100),
		"progress": 0.4,
		"area_parameters": {"width": 8.0}
	}
	var area_desc := {
		"session_id": "area_jammer",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"source_position": Vector3(50, 0, 0),
		"target_position": Vector3(50, 0, 0),
		"progress": 0.6,
		"area_parameters": {"radius": 20.0}
	}
	var cone_desc := {
		"session_id": "cone_sweep",
		"active": true,
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"source_position": Vector3(-50, 0, 0),
		"target_position": Vector3(-50, 0, -40),
		"direction": Vector3(0, 0, -1),
		"progress": 0.7,
		"area_parameters": {"range": 40.0, "angle": 60.0}
	}
	var traj_desc := {
		"session_id": "traj_mortar",
		"active": true,
		"geometry_type": "trajectory",
		"targeting_mode": "ballistic_impact",
		"source_position": Vector3(0, 0, 50),
		"target_position": Vector3(0, 0, -50),
		"progress": 0.8,
		"area_parameters": {"radius": 15.0, "arc_height": 30.0}
	}

	tele_node.sync_descriptors([line_desc, area_desc, cone_desc, traj_desc])

	_check(tele_node.get_active_presentation_count() == 4, "[5a] All 4 distinct geometry instances coexisting concurrently")

	var line_inst = tele_node.get_presentation("line_satellite")
	var area_inst = tele_node.get_presentation("area_jammer")
	var cone_inst = tele_node.get_presentation("cone_sweep")
	var traj_inst = tele_node.get_presentation("traj_mortar")

	_check(line_inst.beam_container.visible == true and line_inst.trajectory_container.visible == false, "[5b] Line instance only renders beam")
	_check(area_inst.area_disc_mesh.visible == true and area_inst.beam_container.visible == false and area_inst.cone_container.visible == false and area_inst.trajectory_container.visible == false, "[5c] Area instance only renders area disc/ring")
	_check(cone_inst.cone_container.visible == true and cone_inst.beam_container.visible == false and cone_inst.trajectory_container.visible == false, "[5d] Cone instance only renders cone")
	_check(traj_inst.trajectory_container.visible == true and traj_inst.beam_container.visible == false and traj_inst.cone_container.visible == false, "[5e] Trajectory instance only renders arc/tracer/impact zone")

	tele_node.clear()
	tele_node.queue_free()


func test_trajectory_lifecycle_cleanup() -> void:
	print("\n-- [Test 6] Trajectory Lifecycle Cleanup --")
	var tele_node = TelegraphPresentationScript.new()
	add_child(tele_node)

	var desc := {
		"session_id": "traj_cleanup_1",
		"active": true,
		"geometry_type": "trajectory",
		"targeting_mode": "ballistic_impact",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -60),
		"progress": 0.2
	}
	tele_node.sync_descriptors([desc])
	_check(tele_node.get_active_presentation_count() == 1, "[6a] Instance active before completion")

	# Authoritative completion (descriptor removed or active=false)
	tele_node.sync_descriptors([])
	_check(tele_node.get_active_presentation_count() == 0, "[6b] Instance cleanly purged on completion")

	# Authoritative cancellation
	tele_node.sync_descriptors([desc])
	_check(tele_node.get_active_presentation_count() == 1, "[6c] Second instance active before cancellation")
	desc["active"] = false
	tele_node.sync_descriptors([desc])
	_check(tele_node.get_active_presentation_count() == 0, "[6d] Instance cleanly purged on cancellation")

	tele_node.clear()
	tele_node.queue_free()


func test_zero_combat_and_physics_authority() -> void:
	print("\n-- [Test 7] Zero Combat & Physics Authority --")
	var tele_node = TelegraphPresentationScript.new()
	add_child(tele_node)

	var desc := {
		"session_id": "phys_check_1",
		"active": true,
		"geometry_type": "trajectory",
		"targeting_mode": "ballistic_impact",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -40),
		"progress": 0.5,
		"area_parameters": {"radius": 10.0, "arc_height": 15.0}
	}
	tele_node.sync_descriptors([desc])
	var inst = tele_node.get_presentation("phys_check_1")

	var nodes_to_check: Array[Node] = [tele_node, inst]
	var found_physics_or_collision := false

	while not nodes_to_check.is_empty():
		var curr = nodes_to_check.pop_back()
		if curr is RigidBody3D or curr is CharacterBody3D or curr is Area3D or curr is CollisionShape3D:
			found_physics_or_collision = true
			break
		for child in curr.get_children():
			nodes_to_check.append(child)

	_check(not found_physics_or_collision, "[7a] Zero physics bodies or collision shapes in TelegraphPresentation hierarchy")
	_check(not tele_node.has_method("apply_damage"), "[7b] Presentation layer does not expose apply_damage")
	_check(not tele_node.has_method("deal_damage"), "[7c] Presentation layer does not expose deal_damage")
	_check(not tele_node.has_method("apply_effect"), "[7d] Presentation layer does not expose apply_effect")

	tele_node.clear()
	tele_node.queue_free()


func test_gameplay_parity_with_special_weapon_ballistic_impact() -> void:
	print("\n-- [Test 8] Gameplay Parity With SpecialWeaponSystem Ballistic Impact --")
	var origin := Vector3(0, 0, 0)
	var impact_pos := Vector3(0, 0, -50)
	var impact_rad := 15.0

	var dummy_inside := Node3D.new()
	dummy_inside.name = "DummyInsideImpact"
	dummy_inside.position = impact_pos + Vector3(5, 0, 5) # dist = sqrt(50) = 7.07 <= 15
	add_child(dummy_inside)

	var dummy_outside := Node3D.new()
	dummy_outside.name = "DummyOutsideImpact"
	dummy_outside.position = impact_pos + Vector3(20, 0, 0) # dist = 20 > 15
	add_child(dummy_outside)

	var area_params: Dictionary = {
		"impact_position": impact_pos,
		"radius": impact_rad,
		"arc_height": 20.0
	}

	var candidates: Array = [dummy_inside, dummy_outside]
	var affected = SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_BALLISTIC_IMPACT,
		origin,
		Vector3(0, 0, -1),
		area_params,
		candidates
	)

	_check(affected.has(dummy_inside), "[8a] SpecialWeaponSystem includes dummy within ballistic impact radius")
	_check(not affected.has(dummy_outside), "[8b] SpecialWeaponSystem excludes dummy outside ballistic impact radius")

	dummy_inside.queue_free()
	dummy_outside.queue_free()
