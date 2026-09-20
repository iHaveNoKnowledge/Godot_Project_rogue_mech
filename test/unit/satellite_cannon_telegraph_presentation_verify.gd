extends Node3D

## =============================================================================
## SATELLITE CANNON TELEGRAPH PRESENTATION VERIFICATION (Phase 2E-11B)
##
## Validates the presentation layer for Satellite Cannon charge and telegraph:
## 1. Descriptor consumption & hierarchy creation
## 2. Geometry determinism & source/target alignment
## 3. Authoritative progress feedback (0.0 -> 1.0)
## 4. Target lock invariance (no moving reticle)
## 5. Clean lifecycle cleanup on completion & cancellation
## 6. Multi-session independent tracking
## 7. Zero combat/physics authority (No Area3D, no damage, no cooldown/energy mutation)
## 8. WeaponManager end-to-end integration
## =============================================================================

var _checks: int = 0
var _fails: int = 0

const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const TelegraphPres = preload("res://scripts/effects/telegraph_presentation.gd")
const WeaponMgrClass = preload("res://scripts/mecha/weapon_manager.gd")
const EnemyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] %s" % msg)
	else:
		_fails += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("=== STARTING SATELLITE CANNON TELEGRAPH PRESENTATION VERIFICATION (Phase 2E-11B) ===")

	_test_1_descriptor_consumption()
	_test_2_geometry_alignment()
	_test_3_progress_visual_feedback()
	_test_4_target_lock_invariance()
	_test_5_cleanup_on_completion_and_cancellation()
	_test_6_multiple_concurrent_telegraphs()
	_test_7_zero_combat_and_physics_authority()
	_test_8_weapon_manager_end_to_end_integration()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_11B_SUCCESS")
		get_tree().quit(0)
	else:
		print("PHASE_2E_11B_FAILED")
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# TEST 1: DESCRIPTOR CONSUMPTION
# -----------------------------------------------------------------------------
func _test_1_descriptor_consumption() -> void:
	print("\n-- [Test 1] Descriptor Consumption --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var mock_desc: Dictionary = {
		"session_id": "test_sess_01",
		"active": true,
		"is_active": true,
		"progress": 0.0,
		"source_position": Vector3(0, 2, 0),
		"target_position": Vector3(0, 2, -100),
		"area_parameters": {"width": 12.0}
	}

	pres.sync_descriptors([mock_desc])

	_check(pres.get_active_presentation_count() == 1, "[1a] Single active descriptor creates exactly 1 presentation instance")
	var inst = pres.get_presentation("test_sess_01")
	_check(inst != null and is_instance_valid(inst), "[1b] Presentation instance accessible via session_id")
	_check(inst.get_node_or_null("BeamContainer") != null, "[1c] Instance has BeamContainer")
	_check(inst.get_node_or_null("TargetReticle") != null, "[1d] Instance has TargetReticle")

	pres.clear()
	_check(pres.get_active_presentation_count() == 0, "[1e] clear() cleans all instances")
	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 2: GEOMETRY ALIGNMENT
# -----------------------------------------------------------------------------
func _test_2_geometry_alignment() -> void:
	print("\n-- [Test 2] Geometry Alignment --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var src := Vector3(10, 5, 20)
	var tgt := Vector3(10, 5, -130) # Distance = 150m along -Z
	var expected_dist: float = src.distance_to(tgt)

	var mock_desc: Dictionary = {
		"session_id": "geom_sess",
		"active": true,
		"progress": 0.3,
		"source_position": src,
		"target_position": tgt,
		"area_parameters": {"width": 12.0}
	}

	pres.sync_descriptors([mock_desc])
	var inst = pres.get_presentation("geom_sess")
	_check(inst != null, "[2a] Presentation instance created for geometry test")

	var mid_point: Vector3 = (src + tgt) * 0.5
	var beam_container = inst.get_node_or_null("BeamContainer") as Node3D
	_check(beam_container != null, "[2b] BeamContainer exists")
	_check(beam_container.global_position.is_equal_approx(mid_point), "[2c] BeamContainer centered at midpoint")

	var outer_mesh = beam_container.get_node_or_null("OuterCorridor") as MeshInstance3D
	_check(outer_mesh != null, "[2d] OuterCorridor mesh exists")
	var cyl := outer_mesh.mesh as CylinderMesh
	_check(cyl != null, "[2e] OuterCorridor uses CylinderMesh")
	_check(is_equal_approx(cyl.height, expected_dist), "[2f] Cylinder height matches distance (150m)")
	_check(is_equal_approx(cyl.top_radius, 6.0), "[2g] Cylinder radius matches half width (6m)")

	var target_reticle = inst.get_node_or_null("TargetReticle") as Node3D
	_check(target_reticle != null, "[2h] TargetReticle node exists")
	_check(target_reticle.global_position.is_equal_approx(tgt), "[2i] TargetReticle placed exactly at target position")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 3: PROGRESS VISUAL FEEDBACK
# -----------------------------------------------------------------------------
func _test_3_progress_visual_feedback() -> void:
	print("\n-- [Test 3] Progress Visual Feedback --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "prog_sess",
		"active": true,
		"progress": 0.0,
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"area_parameters": {"width": 12.0}
	}

	# Progress = 0.0
	pres.sync_descriptors([desc])
	var inst = pres.get_presentation("prog_sess")
	var outer_mat0 = inst.outer_mat
	var inner_mat0 = inst.inner_mat
	var alpha_corridor_0: float = outer_mat0.albedo_color.a
	var core_emission_0: float = inner_mat0.emission_energy_multiplier
	var core_radius_0: float = (inst.inner_mesh_inst.mesh as CylinderMesh).top_radius

	# Progress = 0.5
	desc["progress"] = 0.5
	pres.sync_descriptors([desc])
	var alpha_corridor_50: float = outer_mat0.albedo_color.a
	var core_emission_50: float = inner_mat0.emission_energy_multiplier
	var core_radius_50: float = (inst.inner_mesh_inst.mesh as CylinderMesh).top_radius

	# Progress = 1.0
	desc["progress"] = 1.0
	pres.sync_descriptors([desc])
	var alpha_corridor_100: float = outer_mat0.albedo_color.a
	var core_emission_100: float = inner_mat0.emission_energy_multiplier
	var core_radius_100: float = (inst.inner_mesh_inst.mesh as CylinderMesh).top_radius

	_check(alpha_corridor_0 < alpha_corridor_50 and alpha_corridor_50 < alpha_corridor_100,
		"[3a] Corridor warning alpha increases monotonically (0.0 -> 0.5 -> 1.0)")
	_check(core_emission_0 < core_emission_50 and core_emission_50 < core_emission_100,
		"[3b] Inner core emission increases monotonically (0.0 -> 0.5 -> 1.0)")
	_check(core_radius_0 < core_radius_50 and core_radius_50 < core_radius_100,
		"[3c] Inner core radius thickens monotonically with progress")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 4: TARGET LOCK INVARIANCE
# -----------------------------------------------------------------------------
func _test_4_target_lock_invariance() -> void:
	print("\n-- [Test 4] Target Lock Invariance --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var initial_tgt := Vector3(0, 0, -75)
	var desc: Dictionary = {
		"session_id": "lock_sess",
		"active": true,
		"progress": 0.2,
		"source_position": Vector3.ZERO,
		"target_position": initial_tgt,
		"area_parameters": {"width": 12.0}
	}

	pres.sync_descriptors([desc])
	var inst = pres.get_presentation("lock_sess")
	_check(inst.target_reticle.global_position.is_equal_approx(initial_tgt), "[4a] Reticle starts at locked target")

	# Even if external target or enemy moved, descriptor target position remains locked
	desc["progress"] = 0.8
	# Notice target_position remains initial_tgt
	pres.sync_descriptors([desc])
	_check(inst.target_reticle.global_position.is_equal_approx(initial_tgt), "[4b] Reticle remains locked at start target despite progress")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 5: CLEANUP ON COMPLETION & CANCELLATION
# -----------------------------------------------------------------------------
func _test_5_cleanup_on_completion_and_cancellation() -> void:
	print("\n-- [Test 5] Cleanup on Completion & Cancellation --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "clean_sess",
		"active": true,
		"progress": 0.5,
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"area_parameters": {"width": 12.0}
	}

	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[5a] Presentation active during charging")

	# 1. Simulate Completion: descriptor removed / inactive
	pres.sync_descriptors([])
	_check(pres.get_active_presentation_count() == 0, "[5b] Presentation pruned when descriptor is removed on completion")
	_check(pres.get_presentation("clean_sess") == null, "[5c] Reference to presentation cleared")

	# 2. Simulate Cancellation
	desc["active"] = true
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 1, "[5d] New presentation spawned")
	desc["active"] = false # Cancelled flag
	pres.sync_descriptors([desc])
	_check(pres.get_active_presentation_count() == 0, "[5e] Presentation pruned when descriptor active == false")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 6: MULTIPLE CONCURRENT TELEGRAPHS
# -----------------------------------------------------------------------------
func _test_6_multiple_concurrent_telegraphs() -> void:
	print("\n-- [Test 6] Multiple Concurrent Telegraphs --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc_a: Dictionary = {
		"session_id": "sess_alpha",
		"active": true,
		"progress": 0.2,
		"source_position": Vector3(-5, 0, 0),
		"target_position": Vector3(-5, 0, -80),
		"area_parameters": {"width": 12.0}
	}
	var desc_b: Dictionary = {
		"session_id": "sess_beta",
		"active": true,
		"progress": 0.6,
		"source_position": Vector3(5, 0, 0),
		"target_position": Vector3(5, 0, -60),
		"area_parameters": {"width": 8.0}
	}

	pres.sync_descriptors([desc_a, desc_b])
	_check(pres.get_active_presentation_count() == 2, "[6a] 2 concurrent descriptors create 2 instances")

	var inst_a = pres.get_presentation("sess_alpha")
	var inst_b = pres.get_presentation("sess_beta")
	_check(inst_a != null and inst_b != null, "[6b] Both instances exist independently")
	_check(inst_a != inst_b, "[6c] Instances are distinct objects")
	_check(inst_a.source_pos.x == -5.0 and inst_b.source_pos.x == 5.0, "[6d] Distinct geometries preserved")

	# Remove session A, keep session B
	pres.sync_descriptors([desc_b])
	_check(pres.get_active_presentation_count() == 1, "[6e] Pruning session A leaves session B intact")
	_check(pres.get_presentation("sess_alpha") == null, "[6f] Session A presentation removed")
	_check(pres.get_presentation("sess_beta") != null, "[6g] Session B presentation still valid")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 7: ZERO COMBAT & PHYSICS AUTHORITY
# -----------------------------------------------------------------------------
func _test_7_zero_combat_and_physics_authority() -> void:
	print("\n-- [Test 7] Zero Combat & Physics Authority --")
	var pres = TelegraphPres.new()
	add_child(pres)

	var desc: Dictionary = {
		"session_id": "safety_sess",
		"active": true,
		"progress": 0.5,
		"source_position": Vector3.ZERO,
		"target_position": Vector3(0, 0, -50),
		"area_parameters": {"width": 12.0}
	}
	pres.sync_descriptors([desc])
	var inst = pres.get_presentation("safety_sess")

	# Check recursive node hierarchy for illegal collision / physics nodes
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

	_check(has_area3d == false, "[7a] Presentation contains NO Area3D")
	_check(has_collision == false, "[7b] Presentation contains NO CollisionShape3D")
	_check(has_body == false, "[7c] Presentation contains NO PhysicsBody3D")
	_check(not pres.has_method("apply_damage"), "[7d] Presentation has NO apply_damage method")
	_check(not pres.has_method("consume_energy"), "[7e] Presentation has NO consume_energy method")
	_check(not pres.has_method("start_cooldown"), "[7f] Presentation has NO start_cooldown method")

	pres.queue_free()


# -----------------------------------------------------------------------------
# TEST 8: WEAPON MANAGER END-TO-END INTEGRATION
# -----------------------------------------------------------------------------
func _test_8_weapon_manager_end_to_end_integration() -> void:
	print("\n-- [Test 8] WeaponManager End-to-End Integration --")
	var mecha = Node3D.new()
	mecha.name = "MechaRoot"
	add_child(mecha)

	var wm = WeaponMgrClass.new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)

	# Ensure TelegraphPresentation is instantiated on WeaponManager
	_check(wm.telegraph_presentation != null, "[8a] WeaponManager has telegraph_presentation node instantiated")
	_check(wm.telegraph_presentation.weapon_manager == wm, "[8b] telegraph_presentation bound to WeaponManager")

	var TechSys = load("res://scripts/systems/technology_system.gd")
	var FrameSys = load("res://scripts/systems/frame_system.gd")
	TechSys._player_discovery["tech_beam_weaponry"] = TechSys.DiscoveryState.USABLE
	FrameSys.equip_frame("arm_left", {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	})

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	wm.left_hand = sc_res

	var dummy = EnemyScene.instantiate()
	dummy.position = Vector3(0, 0, -30)
	add_child(dummy)

	var hp_before = dummy.health_system.current_health
	var mock_energy = 100.0
	var user_ctx = {
		"current_energy": mock_energy,
		"origin": Vector3.ZERO,
		"direction": Vector3.FORWARD
	}

	# 1. Fire Satellite Cannon -> enters 3.0s charge
	var act_res := SpecialWeaponSys.activate_special_weapon(sc_res, wm, user_ctx, [dummy])
	_check(act_res.get("success") == true, "[8c] Satellite Cannon activation initiated")
	_check(act_res.get("is_charging") == true, "[8d] Weapon enters charging phase")

	var session = act_res.get("timing_session")
	wm._active_timing_sessions.append(session)

	# Ticking physics frame updates session and synchronizes presentation
	wm._physics_process(0.1)
	_check(wm.telegraph_presentation.get_active_presentation_count() == 1,
		"[8e] TelegraphPresentation displays 1 active visual after physics tick")

	var p_inst = wm.telegraph_presentation.get_presentation(session.session_id)
	_check(p_inst != null, "[8f] Visual instance matches session_id")
	_check(p_inst.target_pos.is_equal_approx(Vector3(0, 0, -150)), "[8g] Visual target is at 150m endpoint")

	# Halfway through charge (1.5s): target HP untouched, presentation still active
	wm._physics_process(1.4)
	_check(dummy.health_system.current_health == hp_before, "[8h] Target HP untouched mid-charge")
	_check(wm.telegraph_presentation.get_active_presentation_count() == 1, "[8i] Presentation active mid-charge")

	# Complete charge (remaining 1.5s)
	wm._physics_process(1.5)
	_check(session.is_completed(), "[8j] Timing session completed")
	_check(dummy.health_system.current_health < hp_before, "[8k] Target HP reduced upon completion strike")
	_check(wm.telegraph_presentation.get_active_presentation_count() == 0,
		"[8l] TelegraphPresentation automatically cleaned up after completion")

	# 2. Cancellation Path: start another charge and abort
	var act_res2 := SpecialWeaponSys.activate_special_weapon(sc_res, wm, user_ctx, [dummy])
	var session2 = act_res2.get("timing_session")
	wm._active_timing_sessions.append(session2)
	wm._physics_process(0.1)
	_check(wm.telegraph_presentation.get_active_presentation_count() == 1, "[8m] New charge displays presentation")

	session2.cancel("player_evade")
	wm._physics_process(0.1)
	_check(wm.telegraph_presentation.get_active_presentation_count() == 0,
		"[8n] TelegraphPresentation immediately cleaned up upon session cancellation")

	dummy.queue_free()
	mecha.queue_free()
