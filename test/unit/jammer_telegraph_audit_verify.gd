extends Node3D

## =============================================================================
## JAMMER TELEGRAPH INTEGRATION AUDIT VERIFICATION (Phase 2E-12A)
##
## Validates that the generic Telegraph architecture supports area-radius
## geometry (Jammer) without weapon-ID branching or duplicating authority:
## 1. Jammer baseline data and instantaneous execution invariance
## 2. Jammer generic area-radius telegraph descriptor contract
## 3. Epicenter invariance (area center remains at origin with targets present)
## 4. Generic area geometry presentation (radius 25m, ring + disc, beam hidden)
## 5. Authoritative progress visual feedback (0.0 -> 0.5 -> 1.0)
## 6. Multi-geometry concurrence (Line + Area simultaneous active sessions)
## 7. Clean lifecycle cleanup on completion and cancellation
## 8. Zero combat, collision, and status authority in presentation
## =============================================================================

var _checks: int = 0
var _fails: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")
const TelegraphPres = preload("res://scripts/effects/telegraph_presentation.gd")
const EnemyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] %s" % msg)
	else:
		_fails += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("=== STARTING JAMMER TELEGRAPH INTEGRATION AUDIT VERIFICATION (Phase 2E-12A) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_1_jammer_baseline_invariance()
	_test_2_jammer_area_descriptor_contract()
	_test_3_area_epicenter_invariance_with_targets()
	_test_4_generic_area_presentation_geometry()
	_test_5_area_progress_modulation()
	_test_6_concurrent_line_and_area_sessions()
	_test_7_lifecycle_cleanup_on_complete_and_cancel()
	_test_8_zero_combat_and_physics_authority()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_12A_SUCCESS")
		get_tree().quit(0)
	else:
		print("PHASE_2E_12A_FAILED")
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# TEST 1: JAMMER BASELINE INVARIANCE
# -----------------------------------------------------------------------------
func _test_1_jammer_baseline_invariance() -> void:
	print("\n-- [Test 1] Jammer Baseline Invariance --")
	var jammer_res = load("res://resources/mech/stock/weapon_jammer.tres")
	_check(jammer_res != null, "[1a] weapon_jammer.tres loads successfully")

	var cap: Dictionary = SpecialWeaponSys.resolve_special_capability(jammer_res)
	_check(cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[1b] Capability is disruption")
	_check(cap.get("targeting_mode") == SpecialWeaponSys.TARGETING_AREA_RADIUS, "[1c] Targeting mode is area_radius")
	_check(cap.get("area_shape") == SpecialWeaponSys.SHAPE_SPHERE, "[1d] Area shape is sphere")
	_check(float(cap.get("area_parameters", {}).get("radius", 0.0)) == 25.0, "[1e] Radius is 25.0m")
	_check(float(cap.get("cooldown", 0.0)) == 10.0, "[1f] Cooldown is 10.0s")
	_check(float(cap.get("energy_cost", 0.0)) == 20.0, "[1g] Energy cost is 20.0")
	_check(float(cap.get("charge_time", 0.0)) == 0.0, "[1h] Baseline charge_time is 0.0s (instant)")

	# Authorize tech and frame
	TechSys._player_discovery["tech_modular_energy_interface"] = TechSys.DiscoveryState.USABLE
	FrameSys.equip_frame("arm_left", {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	})

	var dummy = EnemyScene.instantiate()
	dummy.position = Vector3(0, 0, -10)
	add_child(dummy)

	var user_ctx = {"current_energy": 50.0, "origin": Vector3.ZERO, "direction": Vector3.FORWARD}
	var act_res := SpecialWeaponSys.activate_special_weapon(jammer_res, null, user_ctx, [dummy])

	_check(act_res.get("success") == true, "[1i] Baseline Jammer activation succeeds")
	_check(act_res.get("is_charging") == false, "[1j] Baseline Jammer executes instantaneously (not charging)")
	_check(StuntWeaponSys.is_disrupted(dummy) == true, "[1k] Disruption applied immediately to dummy target")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST 2: JAMMER AREA DESCRIPTOR CONTRACT
# -----------------------------------------------------------------------------
func _test_2_jammer_area_descriptor_contract() -> void:
	print("\n-- [Test 2] Jammer Area Descriptor Contract --")
	var jammer_res = load("res://resources/mech/stock/weapon_jammer.tres")
	var cap: Dictionary = SpecialWeaponSys.resolve_special_capability(jammer_res)
	cap["charge_time"] = 2.0 # Test charging capability contract

	var origin_pos := Vector3(15, 0, 30)
	var session = ActivationTimingSys.create_session(cap, {
		"origin": origin_pos,
		"direction": Vector3.FORWARD
	})
	session.start()
	session.tick(1.0)

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("session_id") != "", "[2a] Descriptor contains non-empty session_id")
	_check(desc.get("active") == true, "[2b] Descriptor active is true during charge")
	_check(desc.get("effect_id") in [SpecialWeaponSys.CAPABILITY_DISRUPTION, "disruption", "temporary_disruption"],
		"[2c] effect_id matches disruption capability")
	_check(desc.get("targeting_mode") == "area_radius", "[2d] targeting_mode is area_radius")
	_check(desc.get("area_shape") == "sphere", "[2e] area_shape is sphere")
	_check(desc.get("geometry_type") == "sphere", "[2f] geometry_type is sphere")
	_check(desc.get("source_position") == origin_pos, "[2g] source_position matches origin")
	_check(desc.get("target_position") == origin_pos, "[2h] target_position matches origin (epicenter)")
	_check(float(desc.get("area_parameters", {}).get("radius", 0.0)) == 25.0, "[2i] area_parameters radius is 25.0")
	_check(is_equal_approx(float(desc.get("progress", 0.0)), 0.5), "[2j] progress is 0.5 at 1.0s / 2.0s")


# -----------------------------------------------------------------------------
# TEST 3: AREA EPICENTER INVARIANCE WITH TARGETS
# -----------------------------------------------------------------------------
func _test_3_area_epicenter_invariance_with_targets() -> void:
	print("\n-- [Test 3] Area Epicenter Invariance With Targets --")
	var jammer_res = load("res://resources/mech/stock/weapon_jammer.tres")
	var cap: Dictionary = SpecialWeaponSys.resolve_special_capability(jammer_res)
	cap["charge_time"] = 2.0

	var origin_pos := Vector3(5, 0, 5)

	var dummy1 = EnemyScene.instantiate()
	dummy1.position = Vector3(15, 0, 10) # within 25m
	add_child(dummy1)

	var dummy2 = EnemyScene.instantiate()
	dummy2.position = Vector3(5, 0, 25) # within 25m
	add_child(dummy2)

	# Session context populated with affected targets
	var session = ActivationTimingSys.create_session(cap, {
		"origin": origin_pos,
		"direction": Vector3.FORWARD,
		"targets": [dummy1, dummy2],
		"affected_targets": [dummy1, dummy2]
	})
	session.start()

	var desc: Dictionary = session.get_telegraph_descriptor()
	# Epicenter must remain at origin_pos, NOT jump to dummy1.global_position
	_check(desc.get("target_position") == origin_pos,
		"[3a] Area target_position remains strictly at origin (epicenter), NOT first target position")
	_check(desc.get("source_position") == origin_pos, "[3b] Area source_position matches origin")
	_check(desc.get("targets").size() == 2, "[3c] Targets array retained in descriptor")

	dummy1.queue_free()
	dummy2.queue_free()


# -----------------------------------------------------------------------------
# TEST 4: GENERIC AREA PRESENTATION GEOMETRY
# -----------------------------------------------------------------------------
func _test_4_generic_area_presentation_geometry() -> void:
	print("\n-- [Test 4] Generic Area Presentation Geometry --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var center_pos := Vector3(20, 2, -40)
	var area_desc: Dictionary = {
		"session_id": "jammer_sess_01",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"area_shape": "sphere",
		"source_position": center_pos,
		"target_position": center_pos,
		"area_parameters": {"radius": 25.0},
		"progress": 0.4
	}

	pres.sync_descriptors([area_desc])
	_check(pres.get_active_presentation_count() == 1, "[4a] Exactly 1 presentation instance spawned for area descriptor")

	var inst = pres.get_presentation("jammer_sess_01")
	_check(inst != null, "[4b] Instance found by session_id")

	# Directional beam corridor must be hidden
	var beam_container = inst.get_node_or_null("BeamContainer") as Node3D
	_check(beam_container != null and beam_container.visible == false,
		"[4c] BeamContainer is HIDDEN for area-radius geometry")

	# TargetReticle must be visible and placed at center_pos
	var reticle = inst.get_node_or_null("TargetReticle") as Node3D
	_check(reticle != null and reticle.visible == true, "[4d] TargetReticle is VISIBLE for area geometry")
	_check(reticle.global_position.is_equal_approx(center_pos), "[4e] TargetReticle positioned at epicenter")

	# Area disc mesh must be visible and sized to 25m radius
	var area_disc = reticle.get_node_or_null("AreaDisc") as MeshInstance3D
	_check(area_disc != null and area_disc.visible == true, "[4f] AreaDisc mesh is VISIBLE")
	var disc_cyl := area_disc.mesh as CylinderMesh
	_check(disc_cyl != null, "[4g] AreaDisc uses CylinderMesh")
	_check(is_equal_approx(disc_cyl.top_radius, 25.0), "[4h] AreaDisc top_radius matches 25.0m")
	_check(is_equal_approx(disc_cyl.bottom_radius, 25.0), "[4i] AreaDisc bottom_radius matches 25.0m")

	# Perimeter warning ring must match 25m radius
	var target_ring = reticle.get_node_or_null("TargetRing") as MeshInstance3D
	var ring_torus := target_ring.mesh as TorusMesh
	_check(ring_torus != null, "[4j] TargetRing uses TorusMesh")
	_check(is_equal_approx(ring_torus.outer_radius, 25.0), "[4k] TargetRing outer_radius matches 25.0m")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 5: AREA PROGRESS MODULATION
# -----------------------------------------------------------------------------
func _test_5_area_progress_modulation() -> void:
	print("\n-- [Test 5] Area Progress Modulation --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "prog_area",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"source_position": Vector3.ZERO,
		"target_position": Vector3.ZERO,
		"area_parameters": {"radius": 25.0},
		"progress": 0.0
	}

	# Progress = 0.0
	pres.sync_descriptors([desc])
	var inst = pres.get_presentation("prog_area")
	var alpha_disc_0: float = inst.disc_mat.albedo_color.a
	var reticle_emission_0: float = inst.reticle_mat.emission_energy_multiplier

	# Progress = 0.5
	desc["progress"] = 0.5
	pres.sync_descriptors([desc])
	var alpha_disc_50: float = inst.disc_mat.albedo_color.a
	var reticle_emission_50: float = inst.reticle_mat.emission_energy_multiplier

	# Progress = 1.0
	desc["progress"] = 1.0
	pres.sync_descriptors([desc])
	var alpha_disc_100: float = inst.disc_mat.albedo_color.a
	var reticle_emission_100: float = inst.reticle_mat.emission_energy_multiplier

	_check(alpha_disc_0 < alpha_disc_50 and alpha_disc_50 < alpha_disc_100,
		"[5a] Area ground disc alpha increases monotonically with progress (0.0 -> 0.5 -> 1.0)")
	_check(reticle_emission_0 < reticle_emission_50 and reticle_emission_50 < reticle_emission_100,
		"[5b] Perimeter ring emission increases monotonically with progress")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 6: CONCURRENT LINE AND AREA SESSIONS
# -----------------------------------------------------------------------------
func _test_6_concurrent_line_and_area_sessions() -> void:
	print("\n-- [Test 6] Concurrent Line and Area Sessions --")
	var pres = TelegraphPres.new()
	add_child(pres)

	# Session A: Satellite Cannon (Line / Beam corridor)
	var desc_satellite: Dictionary = {
		"session_id": "sess_satellite_cannon",
		"active": true,
		"geometry_type": "line",
		"targeting_mode": "beam_line",
		"area_shape": "line",
		"source_position": Vector3(0, 5, 0),
		"target_position": Vector3(0, 5, -150),
		"area_parameters": {"width": 12.0, "length": 150.0},
		"progress": 0.3
	}

	# Session B: Jammer (Area / Sphere pulse)
	var desc_jammer: Dictionary = {
		"session_id": "sess_jammer_pulse",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"area_shape": "sphere",
		"source_position": Vector3(30, 0, 0),
		"target_position": Vector3(30, 0, 0),
		"area_parameters": {"radius": 25.0},
		"progress": 0.7
	}

	pres.sync_descriptors([desc_satellite, desc_jammer])
	_check(pres.get_active_presentation_count() == 2, "[6a] Exactly 2 concurrent presentations active")

	var inst_sat = pres.get_presentation("sess_satellite_cannon")
	var inst_jam = pres.get_presentation("sess_jammer_pulse")
	_check(inst_sat != null and inst_jam != null, "[6b] Both instances exist independently")

	# Verify Satellite Cannon uses Line presentation
	_check(inst_sat.beam_container.visible == true, "[6c] Satellite Cannon beam corridor is VISIBLE")
	_check(inst_sat.area_disc_mesh.visible == false, "[6d] Satellite Cannon area disc is HIDDEN")

	# Verify Jammer uses Area presentation
	_check(inst_jam.beam_container.visible == false, "[6e] Jammer beam corridor is HIDDEN")
	_check(inst_jam.area_disc_mesh.visible == true, "[6f] Jammer area disc is VISIBLE")
	_check(is_equal_approx((inst_jam.area_disc_mesh.mesh as CylinderMesh).top_radius, 25.0),
		"[6g] Jammer area disc radius is 25.0m")

	# Pruning Satellite leaves Jammer active
	pres.sync_descriptors([desc_jammer])
	_check(pres.get_active_presentation_count() == 1, "[6h] Pruning Satellite leaves 1 active presentation")
	_check(pres.get_presentation("sess_satellite_cannon") == null, "[6i] Satellite presentation cleaned up")
	_check(pres.get_presentation("sess_jammer_pulse") != null, "[6j] Jammer presentation remains intact")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 7: LIFECYCLE CLEANUP ON COMPLETE AND CANCEL
# -----------------------------------------------------------------------------
func _test_7_lifecycle_cleanup_on_complete_and_cancel() -> void:
	print("\n-- [Test 7] Lifecycle Cleanup on Complete and Cancel --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "lifecycle_area",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"source_position": Vector3.ZERO,
		"target_position": Vector3.ZERO,
		"area_parameters": {"radius": 25.0},
		"progress": 0.5
	}

	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[7a] Presentation active during preparation")

	# Complete: descriptor removed
	pres.sync_descriptors([])
	_check(pres.get_active_presentation_count() == 0, "[7b] Presentation pruned when descriptor is absent (completed)")

	# Cancel: active = false
	desc["active"] = true
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[7c] Presentation spawned again")
	desc["active"] = false
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 0, "[7d] Presentation pruned when active = false (cancelled)")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 8: ZERO COMBAT AND PHYSICS AUTHORITY
# -----------------------------------------------------------------------------
func _test_8_zero_combat_and_physics_authority() -> void:
	print("\n-- [Test 8] Zero Combat and Physics Authority --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "auth_area",
		"active": true,
		"geometry_type": "sphere",
		"targeting_mode": "area_radius",
		"source_position": Vector3.ZERO,
		"target_position": Vector3.ZERO,
		"area_parameters": {"radius": 25.0},
		"progress": 0.5
	}
	pres.sync_descriptors([desc])
	var inst = pres.get_presentation("auth_area")

	var has_area3d := false
	var has_collision := false
	var has_body := false

	var stack: Array = [inst]
	while not stack.is_empty():
		var curr = stack.pop_back()
		if curr is Area3D:
			has_area3d = true
		if curr is CollisionShape3D or curr is CollisionPolygon3D:
			has_collision = true
		if curr is PhysicsBody3D:
			has_body = true
		for ch in curr.get_children():
			stack.push_back(ch)

	_check(has_area3d == false, "[8a] Area telegraph contains NO Area3D")
	_check(has_collision == false, "[8b] Area telegraph contains NO CollisionShape3D")
	_check(has_body == false, "[8c] Area telegraph contains NO PhysicsBody3D")
	_check(not pres.has_method("apply_disruption"), "[8d] Presentation has NO apply_disruption method")
	_check(not pres.has_method("apply_damage"), "[8e] Presentation has NO apply_damage method")

	pres.queue_free()
