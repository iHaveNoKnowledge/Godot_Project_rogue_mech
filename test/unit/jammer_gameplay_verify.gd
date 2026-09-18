extends Node
## JAMMER GAMEPLAY INTEGRATION VERIFICATION (Phase 2E-6)
##
## Validates the data-driven Jammer definition, generic capability resolution,
## authorization gating, area targeting, movement inhibition, duration expiry,
## deterministic reapplication, multi-target handling, technology observation,
## and architectural invariants without weapon-ID branching.

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("JAMMER_OK: " + msg)
	else:
		_fails += 1
		printerr("JAMMER_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame

	print("=== STARTING JAMMER GAMEPLAY VERIFICATION (PHASE 2E-6) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_a_data_definition()
	_test_b_generic_resolution()
	_test_c_activation_authorization()
	_test_d_area_targeting()
	_test_e_effect_application()
	_test_f_movement_inhibition()
	_test_g_duration_and_expiration()
	_test_h_deterministic_reapplication()
	_test_i_multiple_targets()
	_test_j_technology_observation()
	_test_k_no_weapon_id_branching()
	_test_l_normal_weapon_regression()
	_test_architecture_boundary()
	_test_negative_invariants()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_6_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_6_FAILURE")
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# TEST A: DATA DEFINITION
# -----------------------------------------------------------------------------
func _test_a_data_definition() -> void:
	print("\n-- [Test A] Jammer Data Definition --")
	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	_check(jammer_res != null, "[A1] weapon_jammer.tres loads successfully")
	_check(jammer_res.has_special_capability(), "[A2] Jammer declares special capability")

	var cap_type := jammer_res.get_special_capability_type()
	_check(cap_type in [SpecialWeaponSys.CAPABILITY_DISRUPTION, "temporary_disruption"], "[A3] Capability type is disruption / temporary_disruption")
	_check(jammer_res.get_targeting_mode() == SpecialWeaponSys.TARGETING_AREA_RADIUS, "[A4] Targeting mode is area_radius")
	_check(jammer_res.get_duration() == 4.0, "[A5] Disruption duration is 4.0s")


# -----------------------------------------------------------------------------
# TEST B: GENERIC RESOLUTION
# -----------------------------------------------------------------------------
func _test_b_generic_resolution() -> void:
	print("\n-- [Test B] Generic Resolution --")
	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(jammer_res)

	_check(bool(cap.get("has_capability", false)), "[B1] resolve_special_capability reports has_capability true")
	_check(cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[B2] Capability normalized to canonical disruption")
	_check(cap.get("targeting_mode") == SpecialWeaponSys.TARGETING_AREA_RADIUS, "[B3] Targeting mode is area_radius")
	_check(cap.get("area_shape") == SpecialWeaponSys.SHAPE_SPHERE, "[B4] Area shape is sphere")
	_check(cap.get("area_parameters", {}).get("radius", 0.0) == 25.0, "[B5] Radius is 25.0")
	_check(float(cap.get("cooldown", 0.0)) == 10.0, "[B6] Cooldown is 10.0s")
	_check(float(cap.get("energy_cost", 0.0)) == 20.0, "[B7] Energy cost is 20.0")


# -----------------------------------------------------------------------------
# TEST C: ACTIVATION AUTHORIZATION
# -----------------------------------------------------------------------------
func _test_c_activation_authorization() -> void:
	print("\n-- [Test C] Activation Authorization --")
	TechSys.reset_discovery_states()

	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	var tech_id := jammer_res.tech_id

	# 1. Unknown / Locked Tech
	var val_locked := SpecialWeaponSys.validate_special_activation(jammer_res)
	_check(not bool(val_locked.get("can_activate", false)), "[C1] Activation rejected when technology is locked")
	_check(val_locked.get("reason") == "technology_locked", "[C2] Reason is technology_locked")

	# 2. Incompatible Frame
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE
	var incompatible_frame: Dictionary = {
		"id": "frame_ballistic_only",
		"native_generation": 1,
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	var val_incompat := SpecialWeaponSys.validate_special_activation(jammer_res, {"frame_data": incompatible_frame})
	_check(not bool(val_incompat.get("can_activate", false)), "[C3] Activation rejected on incompatible frame")
	_check(val_incompat.get("reason") == "physically_incompatible", "[C4] Reason is physically_incompatible")

	# 3. Compatible Frame & Usable Tech
	var compatible_frame: Dictionary = {
		"id": "frame_energy_interface",
		"native_generation": 2,
		"supported_families": [TechSys.FAMILY_INTERFACE, TechSys.FAMILY_ENERGY]
	}
	var val_compat := SpecialWeaponSys.validate_special_activation(jammer_res, {"frame_data": compatible_frame})
	_check(bool(val_compat.get("can_activate", false)), "[C5] Activation permitted with compatible frame and usable tech")


# -----------------------------------------------------------------------------
# TEST D: AREA TARGETING & FILTERING
# -----------------------------------------------------------------------------
func _test_d_area_targeting() -> void:
	print("\n-- [Test D] Area Targeting & Filtering --")
	var origin := Vector3(0, 0, 0)
	var forward := Vector3(0, 0, -1)

	var target_inside := {"name": "Target Near", "position": Vector3(10, 0, -10)} # dist ~14.1 <= 25.0
	var target_outside := {"name": "Target Far", "position": Vector3(35, 0, 0)} # dist 35.0 > 25.0
	var target_terrain := {"name": "Static Rock", "position": Vector3(5, 0, -5), "type": "terrain"} # Inside but invalid type

	var filtered := SpecialWeaponSys.filter_valid_targets(
		[target_inside, target_outside, target_terrain],
		SpecialWeaponSys.CAPABILITY_DISRUPTION
	)
	_check(filtered.size() == 2, "[D1] Filter excludes static terrain prop")
	_check(not filtered.has(target_terrain), "[D2] Terrain prop omitted from disruption target list")

	var affected := SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_AREA_RADIUS,
		origin,
		forward,
		{"radius": 25.0},
		filtered
	)
	_check(affected.size() == 1 and affected[0]["name"] == "Target Near", "[D3] Area radius resolves exactly the valid target inside radius")


# -----------------------------------------------------------------------------
# TEST E: EFFECT APPLICATION & PAYLOAD
# -----------------------------------------------------------------------------
func _test_e_effect_application() -> void:
	print("\n-- [Test E] Effect Application & Request --")
	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	var dummy := Node3D.new()
	add_child(dummy)

	var req := SpecialWeaponSys.create_effect_request(
		SpecialWeaponSys.CAPABILITY_DISRUPTION,
		jammer_res.special_capability,
		Vector3.ZERO,
		[dummy]
	)
	_check(req.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[E1] EffectRequest capability_type matches")
	_check(req.get("duration") == 4.0, "[E2] EffectRequest duration is 4.0")
	_check(not dummy.has_meta("disrupted_until"), "[E3] create_effect_request is pure (does NOT mutate dummy)")

	var affected := StuntWeaponSys.apply_effect_request(req)
	_check(affected == 1, "[E4] StuntWeaponSystem applied effect request to dummy")
	_check(StuntWeaponSys.is_disrupted(dummy), "[E5] Dummy is now disrupted according to StuntWeaponSystem")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST F: MOVEMENT INHIBITION (BEFORE, DURING, AFTER)
# -----------------------------------------------------------------------------
func _test_f_movement_inhibition() -> void:
	print("\n-- [Test F] Movement Inhibition State Gate --")
	var enemy := Node3D.new()
	add_child(enemy)

	# 1. Before Disruption
	_check(StuntWeaponSys.can_target_move(enemy) == true, "[F1] Target is cleared to move before disruption")
	_check(StuntWeaponSys.is_disrupted(enemy) == false, "[F2] Target is not disrupted before disruption")

	# 2. Apply Disruption
	StuntWeaponSys.apply_disruption(enemy, 1.0, {"movement_inhibition": 1.0})
	_check(StuntWeaponSys.is_disrupted(enemy) == true, "[F3] Target is disrupted during active disruption")
	_check(StuntWeaponSys.can_target_move(enemy) == false, "[F4] Target movement is inhibited during active disruption")

	# 3. Simulate Duration Expiry deterministically
	enemy.set_meta("disrupted_until", Time.get_ticks_msec() - 10)
	_check(StuntWeaponSys.is_disrupted(enemy) == false, "[F5] Target disruption is false after timestamp expiry")
	_check(StuntWeaponSys.can_target_move(enemy) == true, "[F6] Target is cleared to move again after duration expires")

	enemy.queue_free()


# -----------------------------------------------------------------------------
# TEST G: DURATION & EXPIRATION
# -----------------------------------------------------------------------------
func _test_g_duration_and_expiration() -> void:
	print("\n-- [Test G] Duration & Expiration --")
	var dummy := Node3D.new()
	add_child(dummy)

	var start_time := Time.get_ticks_msec()
	StuntWeaponSys.apply_disruption(dummy, 3.5)

	var expire_ms := int(dummy.get_meta("disrupted_until", 0))
	var expected_expire := start_time + 3500
	_check(abs(expire_ms - expected_expire) < 100, "[G1] Expiration timestamp accurately set to ~3500ms in future")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST H: DETERMINISTIC REAPPLICATION POLICY
# -----------------------------------------------------------------------------
func _test_h_deterministic_reapplication() -> void:
	print("\n-- [Test H] Deterministic Reapplication Policy --")
	var dummy := Node3D.new()
	add_child(dummy)

	# First pulse: 5 seconds
	StuntWeaponSys.apply_disruption(dummy, 5.0)
	var first_expire := int(dummy.get_meta("disrupted_until", 0))

	# Second pulse: 2 seconds (should NOT reduce remaining duration)
	StuntWeaponSys.apply_disruption(dummy, 2.0)
	var second_expire := int(dummy.get_meta("disrupted_until", 0))
	_check(second_expire >= first_expire, "[H1] Shorter reapplication does not shorten ongoing disruption")

	# Third pulse: 8 seconds (should extend duration to new latest expiry)
	StuntWeaponSys.apply_disruption(dummy, 8.0)
	var third_expire := int(dummy.get_meta("disrupted_until", 0))
	_check(third_expire > second_expire, "[H2] Longer reapplication successfully extends expiry timestamp")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST I: MULTIPLE TARGETS INDEPENDENCE
# -----------------------------------------------------------------------------
func _test_i_multiple_targets() -> void:
	print("\n-- [Test I] Multiple Targets Independence --")
	var t1 := Node3D.new()
	var t2 := Node3D.new()
	var t3 := Node3D.new()
	add_child(t1)
	add_child(t2)
	add_child(t3)

	var req := {
		"capability_type": SpecialWeaponSys.CAPABILITY_DISRUPTION,
		"duration": 3.0,
		"targets": [t1, t2, t3],
		"effect_payload": {"dampen": 1.0}
	}
	var count := StuntWeaponSys.apply_effect_request(req)
	_check(count == 3, "[I1] All 3 targets affected by single pulse request")
	_check(StuntWeaponSys.is_disrupted(t1), "[I2] Target 1 is disrupted")
	_check(StuntWeaponSys.is_disrupted(t2), "[I3] Target 2 is disrupted")
	_check(StuntWeaponSys.is_disrupted(t3), "[I4] Target 3 is disrupted")

	# Clearing one target does not affect others
	t2.set_meta("disrupted_until", Time.get_ticks_msec() - 10)
	_check(StuntWeaponSys.is_disrupted(t1), "[I5] Target 1 remains disrupted")
	_check(not StuntWeaponSys.is_disrupted(t2), "[I6] Target 2 has recovered")
	_check(StuntWeaponSys.is_disrupted(t3), "[I7] Target 3 remains disrupted")

	t1.queue_free()
	t2.queue_free()
	t3.queue_free()


# -----------------------------------------------------------------------------
# TEST J: TECHNOLOGY OBSERVATION
# -----------------------------------------------------------------------------
func _test_j_technology_observation() -> void:
	print("\n-- [Test J] Technology Observation Path --")
	TechSys.reset_discovery_states()

	var tech_id := "tech_modular_energy_interface"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[J1] Tech starts UNKNOWN")

	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	var source := Node3D.new()
	add_child(source)

	SpecialWeaponSys.report_special_weapon_observed(jammer_res.tech_id, source, SpecialWeaponSys.CAPABILITY_DISRUPTION)

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[J2] Activating jammer observed tech via generic EventBus path")

	source.queue_free()


# -----------------------------------------------------------------------------
# TEST K: NO WEAPON-ID BRANCHING
# -----------------------------------------------------------------------------
func _test_k_no_weapon_id_branching() -> void:
	print("\n-- [Test K] No Weapon-ID Branching --")
	TechSys._player_discovery["tech_modular_energy_interface"] = TechSys.DiscoveryState.USABLE

	var synthetic_emitter: Dictionary = {
		"id": "unmarked_synthetic_pulse_device_99",
		"name": "Classified Pulse Field Grid",
		"tech_id": "tech_modular_energy_interface",
		"special_capability": {
			"capability_type": "temporary_disruption",
			"targeting_mode": "area_radius",
			"area_parameters": {"radius": 30.0},
			"duration": 5.0,
			"cooldown": 12.0,
			"energy_cost": 15.0
		}
	}

	var source := Node3D.new()
	var victim := Node3D.new()
	add_child(source)
	add_child(victim)
	victim.global_position = Vector3(10, 0, 0)

	var res := SpecialWeaponSys.activate_special_weapon(
		synthetic_emitter,
		source,
		{"current_energy": 50.0},
		[victim]
	)
	_check(bool(res.get("success", false)), "[K1] Synthetic weapon without 'jammer' in ID or name activates successfully")
	_check(res.get("targets_affected", 0) == 1, "[K2] Synthetic weapon affects target through same generic pipeline")
	_check(StuntWeaponSys.is_disrupted(victim), "[K3] Victim is disrupted by synthetic weapon")

	source.queue_free()
	victim.queue_free()


# -----------------------------------------------------------------------------
# TEST L: NORMAL WEAPON REGRESSION
# -----------------------------------------------------------------------------
func _test_l_normal_weapon_regression() -> void:
	print("\n-- [Test L] Normal Weapon Regression --")
	var rifle: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(not rifle.has_special_capability(), "[L1] Beam rifle reports has_special_capability false")

	var val := SpecialWeaponSys.validate_special_activation(rifle)
	_check(not bool(val.get("can_activate", false)), "[L2] Normal weapon activation rejected by special weapon system")


# -----------------------------------------------------------------------------
# ARCHITECTURE TEST: MUTATION AUTHORITY BOUNDARY
# -----------------------------------------------------------------------------
func _test_architecture_boundary() -> void:
	print("\n-- [Architecture Test] Authority Boundary Verification --")
	var victim := Node3D.new()
	add_child(victim)

	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	var req := SpecialWeaponSys.create_effect_request(
		SpecialWeaponSys.CAPABILITY_DISRUPTION,
		jammer_res.special_capability,
		Vector3.ZERO,
		[victim]
	)
	_check(not victim.has_meta("disrupted_until"), "[ARCH1] SpecialWeaponSystem.create_effect_request does not mutate victim")
	_check(not victim.has_meta("is_stunned"), "[ARCH2] SpecialWeaponSystem does not set stunned flag")

	var count := SpecialWeaponSys.dispatch_effect_request(req)
	_check(count == 1, "[ARCH3] dispatch_effect_request delegates to StuntWeaponSystem")
	_check(victim.has_meta("disrupted_until"), "[ARCH4] StuntWeaponSystem mutates victim metadata authoritatively")

	victim.queue_free()


# -----------------------------------------------------------------------------
# NEGATIVE TESTS: ARCHITECTURAL INVARIANTS
# -----------------------------------------------------------------------------
func _test_negative_invariants() -> void:
	print("\n-- [Negative Tests] Architectural Invariants --")
	TechSys.reset_discovery_states()

	# Invariant 1: Spawn != Observe
	var jammer_res: WeaponPart = load("res://resources/mech/stock/weapon_jammer.tres")
	var unused_node := Node3D.new()
	add_child(unused_node)
	_check(TechSys.get_discovery_state(jammer_res.tech_id) == TechSys.DiscoveryState.UNKNOWN, "[NEG1] Spawning/instantiating weapon does NOT observe technology")

	# Invariant 2: Technology authorization != Effect execution
	TechSys._player_discovery[jammer_res.tech_id] = TechSys.DiscoveryState.USABLE
	_check(not StuntWeaponSys.is_disrupted(unused_node), "[NEG2] Authorizing technology does NOT execute effect")

	# Invariant 3: Capability resolution != State mutation
	var cap := SpecialWeaponSys.resolve_special_capability(jammer_res)
	_check(not StuntWeaponSys.is_disrupted(unused_node), "[NEG3] Resolving capability does NOT mutate node state")

	# Invariant 4: Target resolution != State mutation
	var targets := SpecialWeaponSys.resolve_affected_targets(
		cap.targeting_mode,
		Vector3.ZERO,
		Vector3.FORWARD,
		cap.area_parameters,
		[unused_node]
	)
	_check(targets.size() == 1, "[NEG4] Target resolved geometrically")
	_check(not StuntWeaponSys.is_disrupted(unused_node), "[NEG5] Target resolution does NOT mutate target state")

	unused_node.queue_free()
