extends Node

## =============================================================================
## CONE / SECTOR TELEGRAPH GEOMETRY AUDIT VERIFICATION (Phase 2E-12B)
##
## Validates that:
## 1. Generic Telegraph Descriptor cleanly represents directional cone/sector geometry:
##    - source, direction, range, angle, targeting mode, area shape, progress
## 2. Directional cone geometry supports angles: 0°, 60°, 90°, 180° and varying ranges.
## 3. Strike endpoint (target_position) is authoritative and does NOT displace to enemy targets.
## 4. TelegraphPresentation generically renders cone/sector without weapon-ID branching.
## 5. Concurrent coexistence of Line (Satellite), Area (Jammer), and Cone geometries.
## 6. Lifecycle cleanup on completion and cancellation.
## 7. Zero combat/physics authority in the presentation layer.
## 8. 100% mathematical parity with SpecialWeaponSystem.resolve_affected_targets.
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
	print("\n=== STARTING CONE / SECTOR TELEGRAPH GEOMETRY AUDIT VERIFICATION (Phase 2E-12B) ===\n")
	test_cone_descriptor_contract()
	test_epicenter_and_aim_invariance_with_targets()
	test_geometry_angle_and_range_variations()
	test_generic_cone_presentation()
	test_cone_progress_modulation()
	test_concurrent_multi_geometry_coexistence()
	test_cone_lifecycle_cleanup()
	test_zero_combat_and_physics_authority()
	test_gameplay_parity_with_special_weapon_targeting()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _failures])
	if _failures == 0:
		print("PHASE_2E_12B_SUCCESS\n")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_12B_FAILED: %d tests failed!\n" % _failures)
		get_tree().quit(1)


func test_cone_descriptor_contract() -> void:
	print("-- [Test 1] Cone Descriptor Contract --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "disruption",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {
			"range": 50.0,
			"angle": 60.0
		},
		"charge_time": 2.0,
		"cooldown": 15.0,
		"energy_cost": 30.0,
		"tech_id": "tech_emp_sweep"
	}
	var origin := Vector3(10, 0, 20)
	var forward_dir := Vector3(0, 0, -1)
	var ctx := {
		"origin": origin,
		"direction": forward_dir
	}

	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()
	session.tick(1.0) # 50% charged

	var desc: Dictionary = session.get_telegraph_descriptor()

	_check(desc.has("session_id") and str(desc["session_id"]) != "", "[1a] Descriptor contains non-empty session_id")
	_check(bool(desc.get("active", false)) == true, "[1b] Descriptor active is true during charge")
	_check(str(desc.get("geometry_type", "")) == "cone", "[1c] geometry_type is cone")
	_check(str(desc.get("targeting_mode", "")) == "sweep_cone", "[1d] targeting_mode is sweep_cone")
	_check(str(desc.get("area_shape", "")) == "cone", "[1e] area_shape is cone")
	_check(desc.get("source_position") == origin, "[1f] source_position matches origin")
	_check(desc.get("direction") == forward_dir, "[1g] direction matches forward vector")
	_check(float(desc.get("area_parameters", {}).get("range", 0.0)) == 50.0, "[1h] area_parameters range is 50.0m")
	_check(float(desc.get("area_parameters", {}).get("angle", 0.0)) == 60.0, "[1i] area_parameters angle is 60.0 deg")
	var expected_target := origin + forward_dir * 50.0
	_check(desc.get("target_position") == expected_target, "[1j] target_position matches centerline tip (origin + dir * range)")
	_check(is_equal_approx(float(desc.get("progress", 0.0)), 0.5), "[1k] progress is 0.5 at 1.0s / 2.0s")
	_check(is_equal_approx(float(desc.get("remaining", 0.0)), 1.0), "[1l] remaining is 1.0s at 1.0s / 2.0s")


func test_epicenter_and_aim_invariance_with_targets() -> void:
	print("\n-- [Test 2] Cone Aim Invariance With Targets --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "strategic_strike",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {
			"range": 40.0,
			"angle": 45.0
		},
		"charge_time": 2.0
	}
	var origin := Vector3(0, 0, 0)
	var dir := Vector3(1, 0, 0) # Firing right (+X)

	var dummy_enemy := Node3D.new()
	dummy_enemy.position = Vector3(25, 0, 15) # Flanking enemy

	var ctx := {
		"origin": origin,
		"direction": dir,
		"targets": [dummy_enemy]
	}

	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()

	var desc: Dictionary = session.get_telegraph_descriptor()
	var expected_target := origin + dir * 40.0 # (40, 0, 0)

	_check(desc.get("target_position") == expected_target, "[2a] target_position remains strictly along aim centerline, NOT enemy position")
	_check(desc.get("target_position") != dummy_enemy.position, "[2b] target_position is distinct from enemy position")
	_check(desc.get("direction") == dir, "[2c] direction remains pure aim vector")
	_check(desc.get("targets").size() == 1, "[2d] targets array retained in descriptor")

	dummy_enemy.free()


func test_geometry_angle_and_range_variations() -> void:
	print("\n-- [Test 3] Geometry Angle and Range Variations --")
	var origin := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)

	# 3a. 60° normal cone
	var session_60 = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 50.0, "angle": 60.0}
	}, {"origin": origin, "direction": fwd})
	session_60.start()
	var d60 = session_60.get_telegraph_descriptor()
	_check(float(d60["area_parameters"]["angle"]) == 60.0, "[3a] 60 deg cone preserved in descriptor")

	# 3b. 90° quadrant sweep
	var session_90 = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 30.0, "angle": 90.0}
	}, {"origin": origin, "direction": fwd})
	session_90.start()
	var d90 = session_90.get_telegraph_descriptor()
	_check(float(d90["area_parameters"]["angle"]) == 90.0, "[3b] 90 deg quadrant preserved in descriptor")

	# 3c. 180° frontal half-sweep
	var session_180 = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 20.0, "angle": 180.0}
	}, {"origin": origin, "direction": fwd})
	session_180.start()
	var d180 = session_180.get_telegraph_descriptor()
	_check(float(d180["area_parameters"]["angle"]) == 180.0, "[3c] 180 deg frontal sweep preserved in descriptor")

	# 3d. 0° minimum cone (pinpoint sweep)
	var session_0 = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 25.0, "angle": 0.0}
	}, {"origin": origin, "direction": fwd})
	session_0.start()
	var d0 = session_0.get_telegraph_descriptor()
	_check(float(d0["area_parameters"]["angle"]) == 0.0, "[3d] 0 deg boundary preserved without failure")

	# 3e. Short range (5.0m)
	var session_short = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 5.0, "angle": 45.0}
	}, {"origin": origin, "direction": fwd})
	session_short.start()
	var d_short = session_short.get_telegraph_descriptor()
	_check(d_short["target_position"] == Vector3(0, 0, -5), "[3e] 5.0m short range tip matches Vector3(0, 0, -5)")

	# 3f. Long range (100.0m)
	var session_long = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 100.0, "angle": 45.0}
	}, {"origin": origin, "direction": fwd})
	session_long.start()
	var d_long = session_long.get_telegraph_descriptor()
	_check(d_long["target_position"] == Vector3(0, 0, -100), "[3f] 100.0m long range tip matches Vector3(0, 0, -100)")

	# 3g. Diagonal aim (+X, -Z)
	var diag_dir := Vector3(1, 0, -1).normalized()
	var session_diag = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": {"range": 50.0, "angle": 60.0}
	}, {"origin": origin, "direction": diag_dir})
	session_diag.start()
	var d_diag = session_diag.get_telegraph_descriptor()
	var expected_diag := diag_dir * 50.0
	_check(d_diag["target_position"].is_equal_approx(expected_diag), "[3g] Diagonal aim direction produces accurate target_position")


func test_generic_cone_presentation() -> void:
	print("\n-- [Test 4] Generic Cone Presentation Geometry --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var cone_desc: Dictionary = {
		"session_id": "cone_sess_01",
		"active": true,
		"effect_id": "emp_sweep",
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"source_position": Vector3(5, 0, 10),
		"target_position": Vector3(5, 0, -40), # 50m forward
		"direction": Vector3(0, 0, -1),
		"area_parameters": {
			"range": 50.0,
			"angle": 60.0
		},
		"progress": 0.25
	}

	pres.sync_descriptors([cone_desc])

	_check(pres.get_active_presentation_count() == 1, "[4a] Exactly 1 presentation instance spawned for cone")
	var inst = pres.get_presentation("cone_sess_01")
	_check(inst != null, "[4b] Instance found by session_id")

	var cone_container: Node3D = inst.get_node_or_null("ConeContainer")
	var beam_container: Node3D = inst.get_node_or_null("BeamContainer")
	var target_reticle: Node3D = inst.get_node_or_null("TargetReticle")
	var area_disc: MeshInstance3D = inst.find_child("AreaDisc", true, false)
	var target_ring: MeshInstance3D = inst.find_child("TargetRing", true, false)
	var cone_sector: MeshInstance3D = inst.find_child("ConeSector", true, false)
	var cone_border: MeshInstance3D = inst.find_child("ConeBorder", true, false)

	_check(cone_container != null and cone_container.visible == true, "[4c] ConeContainer is VISIBLE")
	_check(beam_container != null and beam_container.visible == false, "[4d] BeamContainer is HIDDEN for cone")
	_check(area_disc != null and area_disc.visible == false, "[4e] AreaDisc is HIDDEN for cone")
	_check(target_ring != null and target_ring.visible == false, "[4f] TargetRing is HIDDEN for cone")
	_check(target_reticle != null and target_reticle.visible == true, "[4g] TargetReticle is VISIBLE at endpoint")
	_check(target_reticle.position == Vector3(5, 0, -40) or target_reticle.global_position == Vector3(5, 0, -40), "[4h] TargetReticle placed at target_position")

	_check(cone_sector != null and cone_sector.mesh is ArrayMesh, "[4i] ConeSector mesh exists and is an ArrayMesh")
	_check(cone_border != null and cone_border.mesh is ArrayMesh, "[4j] ConeBorder mesh exists and is an ArrayMesh")

	pres.clear()
	pres.queue_free()


func test_cone_progress_modulation() -> void:
	print("\n-- [Test 5] Cone Progress Visual Modulation --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc_template := {
		"session_id": "cone_prog_sess",
		"active": true,
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"direction": Vector3(0, 0, -1),
		"area_parameters": {"range": 50.0, "angle": 60.0}
	}

	# t=0.0
	var d0 = desc_template.duplicate(true)
	d0["progress"] = 0.0
	pres.sync_descriptors([d0])
	var inst = pres.get_presentation("cone_prog_sess")
	var fill_mat: StandardMaterial3D = inst.cone_mat
	var border_mat: StandardMaterial3D = inst.cone_border_mat
	var alpha_0 := fill_mat.albedo_color.a
	var border_emit_0 := border_mat.emission_energy_multiplier

	# t=0.5
	var d5 = desc_template.duplicate(true)
	d5["progress"] = 0.5
	pres.sync_descriptors([d5])
	var alpha_5 := fill_mat.albedo_color.a
	var border_emit_5 := border_mat.emission_energy_multiplier

	# t=1.0
	var d1 = desc_template.duplicate(true)
	d1["progress"] = 1.0
	pres.sync_descriptors([d1])
	var alpha_1 := fill_mat.albedo_color.a
	var border_emit_1 := border_mat.emission_energy_multiplier

	_check(alpha_0 < alpha_5 and alpha_5 < alpha_1, "[5a] Sector fill alpha increases monotonically with progress (0.0=%.2f -> 0.5=%.2f -> 1.0=%.2f)" % [alpha_0, alpha_5, alpha_1])
	_check(border_emit_0 < border_emit_5 and border_emit_5 < border_emit_1, "[5b] Border emission increases monotonically with progress (0.0=%.1f -> 0.5=%.1f -> 1.0=%.1f)" % [border_emit_0, border_emit_5, border_emit_1])

	pres.clear()
	pres.queue_free()


func test_concurrent_multi_geometry_coexistence() -> void:
	print("\n-- [Test 6] Concurrent Multi-Geometry Coexistence (Line + Area + Cone) --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc_sat: Dictionary = {
		"session_id": "sess_line_sat",
		"active": true,
		"effect_id": "strategic_strike",
		"geometry_type": "line",
		"targeting_mode": "beam_line",
		"area_shape": "line",
		"source_position": Vector3(0, 5, 0),
		"target_position": Vector3(0, 5, -150),
		"area_parameters": {"length": 150.0, "width": 12.0},
		"progress": 0.4
	}

	var desc_jam: Dictionary = {
		"session_id": "sess_area_jam",
		"active": true,
		"effect_id": "disruption",
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"area_shape": "sphere",
		"source_position": Vector3(50, 0, 50),
		"target_position": Vector3(50, 0, 50),
		"area_parameters": {"radius": 25.0},
		"progress": 0.7
	}

	var desc_cone: Dictionary = {
		"session_id": "sess_cone_emp",
		"active": true,
		"effect_id": "emp_sweep",
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"source_position": Vector3(-50, 0, 0),
		"target_position": Vector3(-50, 0, -40),
		"direction": Vector3(0, 0, -1),
		"area_parameters": {"range": 40.0, "angle": 90.0},
		"progress": 0.3
	}

	pres.sync_descriptors([desc_sat, desc_jam, desc_cone])

	_check(pres.get_active_presentation_count() == 3, "[6a] Exactly 3 concurrent presentations active")
	var inst_sat = pres.get_presentation("sess_line_sat")
	var inst_jam = pres.get_presentation("sess_area_jam")
	var inst_cone = pres.get_presentation("sess_cone_emp")

	_check(inst_sat != null and inst_jam != null and inst_cone != null, "[6b] All 3 instances exist simultaneously")

	# Satellite (Line)
	_check(inst_sat.beam_container.visible == true, "[6c] Satellite Cannon beam is VISIBLE")
	_check(inst_sat.area_disc_mesh.visible == false, "[6d] Satellite Cannon area disc is HIDDEN")
	_check(inst_sat.cone_container.visible == false, "[6e] Satellite Cannon cone container is HIDDEN")

	# Jammer (Area)
	_check(inst_jam.beam_container.visible == false, "[6f] Jammer beam is HIDDEN")
	_check(inst_jam.area_disc_mesh.visible == true, "[6g] Jammer area disc is VISIBLE")
	_check(inst_jam.cone_container.visible == false, "[6h] Jammer cone container is HIDDEN")

	# Cone
	_check(inst_cone.beam_container.visible == false, "[6i] Cone beam is HIDDEN")
	_check(inst_cone.area_disc_mesh.visible == false, "[6j] Cone area disc is HIDDEN")
	_check(inst_cone.cone_container.visible == true, "[6k] Cone container is VISIBLE")

	# Prune Satellite Cannon
	pres.sync_descriptors([desc_jam, desc_cone])
	_check(pres.get_active_presentation_count() == 2, "[6l] Pruning Satellite leaves exactly 2 active instances")
	_check(pres.get_presentation("sess_line_sat") == null, "[6m] Satellite Cannon presentation cleanly removed")
	_check(pres.get_presentation("sess_area_jam") != null, "[6n] Jammer presentation remains intact")
	_check(pres.get_presentation("sess_cone_emp") != null, "[6o] Cone presentation remains intact")

	# Prune Jammer
	pres.sync_descriptors([desc_cone])
	_check(pres.get_active_presentation_count() == 1, "[6p] Pruning Jammer leaves 1 active instance")
	_check(pres.get_presentation("sess_cone_emp") != null, "[6q] Cone presentation still valid")

	# Prune Cone
	pres.sync_descriptors([])
	_check(pres.get_active_presentation_count() == 0, "[6r] Pruning all leaves 0 active instances")

	pres.clear()
	pres.queue_free()


func test_cone_lifecycle_cleanup() -> void:
	print("\n-- [Test 7] Cone Lifecycle Cleanup on Complete and Cancel --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "cone_lifecycle_sess",
		"active": true,
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -30),
		"area_parameters": {"range": 30.0, "angle": 45.0},
		"progress": 0.95
	}

	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[7a] Presentation active during preparation")

	# Complete -> descriptor absent
	pres.sync_descriptors([])
	_check(pres.get_active_presentation_count() == 0, "[7b] Presentation pruned on completion")
	_check(pres.get_presentation("cone_lifecycle_sess") == null, "[7c] Reference cleanly cleared")

	# Spawn again -> Cancel
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[7d] Presentation spawned for second session")

	desc["active"] = false
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 0, "[7e] Presentation pruned immediately on cancellation (active=false)")

	pres.clear()
	pres.queue_free()


func test_zero_combat_and_physics_authority() -> void:
	print("\n-- [Test 8] Zero Combat and Physics Authority --")
	var pres := TelegraphPresentationScript.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "cone_auth_test",
		"active": true,
		"geometry_type": "cone",
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"area_parameters": {"range": 50.0, "angle": 60.0}
	}
	pres.sync_descriptors([desc])
	var inst = pres.get_presentation("cone_auth_test")

	_check(inst.find_child("*Area3D*", true, false) == null, "[8a] Presentation contains NO Area3D")
	_check(inst.find_child("*CollisionShape3D*", true, false) == null, "[8b] Presentation contains NO CollisionShape3D")
	_check(inst.find_child("*PhysicsBody3D*", true, false) == null, "[8c] Presentation contains NO PhysicsBody3D")

	_check(not pres.has_method("apply_damage"), "[8d] Presentation has NO apply_damage method")
	_check(not pres.has_method("apply_disruption"), "[8e] Presentation has NO apply_disruption method")
	_check(not pres.has_method("consume_energy"), "[8f] Presentation has NO consume_energy method")
	_check(not pres.has_method("start_cooldown"), "[8g] Presentation has NO start_cooldown method")

	pres.clear()
	pres.queue_free()


func test_gameplay_parity_with_special_weapon_targeting() -> void:
	print("\n-- [Test 9] Gameplay Parity With SpecialWeaponSystem.resolve_affected_targets --")
	var origin := Vector3(0, 0, 0)
	var forward := Vector3(0, 0, -1)
	var area_params := {"range": 50.0, "angle": 60.0} # half-angle is 30 deg

	# Center (0 deg, 20m dist) -> INSIDE
	var t_center := {"name": "Center", "position": Vector3(0, 0, -20)}
	# Edge (~18.4 deg, 31.6m dist <= 50m) -> INSIDE
	var t_edge := {"name": "Edge", "position": Vector3(10, 0, -30)}
	# Outside angle (~71.5 deg > 30 deg) -> OUTSIDE
	var t_out_angle := {"name": "Out Angle", "position": Vector3(30, 0, -10)}
	# Center beyond range (0 deg, 60m dist > 50m) -> OUTSIDE
	var t_out_range := {"name": "Out Range", "position": Vector3(0, 0, -60)}

	var affected = SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_SWEEP_CONE,
		origin,
		forward,
		area_params,
		[t_center, t_edge, t_out_angle, t_out_range]
	)

	_check(affected.size() == 2, "[9a] Gameplay targeting resolves exactly 2 targets")
	var names: Array = []
	for a in affected:
		names.append(a["name"])
	_check(names.has("Center") and names.has("Edge"), "[9b] Resolved targets are Center and Edge")
	_check(not names.has("Out Angle"), "[9c] Target outside angle excluded")
	_check(not names.has("Out Range"), "[9d] Target outside range excluded")

	# Confirm descriptor convention matches
	var session = ActivationTimingSys.create_session({
		"charge_time": 1.0,
		"targeting_mode": "sweep_cone",
		"area_shape": "cone",
		"area_parameters": area_params
	}, {"origin": origin, "direction": forward})
	session.start()
	var desc = session.get_telegraph_descriptor()
	_check(float(desc["area_parameters"]["angle"]) == 60.0, "[9e] Descriptor full angle (60 deg) exactly matches gameplay contract")
	_check(float(desc["area_parameters"]["range"]) == 50.0, "[9f] Descriptor range (50m) exactly matches gameplay contract")
