extends Node
## GENERIC ACTIVATION TIMING & TELEGRAPH VERIFICATION (Phase 2E-9)
##
## Validates:
## 1. Zero-duration and positive-duration activation timing.
## 2. Progress and remaining time calculation.
## 3. No premature completion.
## 4. Cancellation semantics (aborts execution, prevents effect dispatch, leaves target untouched).
## 5. Cooldown separation (cooldown != charge_time, WeaponCore remains cooldown authority).
## 6. Purity & authority invariants (timing does not directly mutate HP, armor, status; uses EffectRequest).
## 7. Genericity (capability-driven, zero weapon-ID dependencies).
## 8. Telegraph descriptor generation (pure visual/warning metadata).
## 9. Compatibility with Jammer (instant) and Satellite Cannon (instant) and synthetic charged weapons.

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")
const DamageCalc = preload("res://scripts/systems/damage_calculator.gd")
const WeaponPartRes = preload("res://resources/mech/weapon_part.gd")
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const WeaponCoreSys = preload("res://scripts/systems/weapon_core.gd")

const EnemyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

class MockEnergySystem extends RefCounted:
	var energy: float = 100.0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("TIMING_OK: " + msg)
	else:
		_fails += 1
		printerr("TIMING_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame

	print("=== STARTING GENERIC ACTIVATION TIMING VERIFICATION (PHASE 2E-9) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_1_zero_duration_activation()
	_test_2_positive_duration_timing_and_progress()
	_test_3_no_premature_completion()
	_test_4_cancellation_semantics()
	_test_5_cooldown_separation_from_activation()
	_test_6_purity_and_authority_invariants()
	_test_7_generic_telegraph_descriptor()
	_test_8_integration_with_existing_weapons()
	_test_9_negative_architecture_checks()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_9_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_9_FAILED with %d errors" % _fails)
		get_tree().quit(1)


func _test_1_zero_duration_activation() -> void:
	print("\n--- Test 1: Zero-Duration Activation ---")
	var state := {"completed": false}
	var cap_data: Dictionary = {
		"capability_type": "strategic_strike",
		"charge_time": 0.0,
		"cooldown": 20.0
	}

	var session = ActivationTimingSys.create_session(cap_data, {}, func(_s): state["completed"] = true)
	_check(session.is_ready(), "Session starts in READY phase")
	_check(session.get_progress() == 1.0, "Zero-duration session progress is 1.0")

	session.start()
	_check(session.is_completed(), "Zero-duration session transitions to COMPLETED immediately on start()")
	_check(state["completed"] == true, "Completion callback called synchronously for zero-duration")
	_check(session.get_remaining_time() == 0.0, "Remaining time is 0.0")


func _test_2_positive_duration_timing_and_progress() -> void:
	print("\n--- Test 2: Positive Duration Timing & Progress ---")
	var state := {"completed": false}
	var cap_data: Dictionary = {
		"capability_type": "strategic_strike",
		"charge_time": 3.0,
		"cooldown": 25.0
	}

	var session = ActivationTimingSys.create_session(cap_data, {}, func(_s): state["completed"] = true)
	_check(session.duration == 3.0, "Session duration matches charge_time 3.0s")
	session.start()

	_check(session.is_preparing(), "Session enters PREPARING phase after start()")
	_check(is_equal_approx(session.get_progress(), 0.0), "Initial progress is 0.0")
	_check(is_equal_approx(session.get_remaining_time(), 3.0), "Initial remaining time is 3.0s")

	# Advance 1.5s (halfway)
	session.tick(1.5)
	_check(session.is_preparing(), "Session still in PREPARING phase halfway through")
	_check(is_equal_approx(session.get_progress(), 0.5), "Progress is 0.5 at 1.5s")
	_check(is_equal_approx(session.get_remaining_time(), 1.5), "Remaining time is 1.5s")
	_check(state["completed"] == false, "Completion callback not yet called halfway through")

	# Advance another 1.5s (full completion)
	session.tick(1.5)
	_check(session.is_completed(), "Session is COMPLETED after full 3.0s")
	_check(is_equal_approx(session.get_progress(), 1.0), "Progress is 1.0 at completion")
	_check(is_equal_approx(session.get_remaining_time(), 0.0), "Remaining time is 0.0s")
	_check(state["completed"] == true, "Completion callback triggered exactly on completion")


func _test_3_no_premature_completion() -> void:
	print("\n--- Test 3: No Premature Completion ---")
	var state := {"completed": false}
	var cap_data: Dictionary = {
		"charge_time": 5.0
	}
	var session = ActivationTimingSys.create_session(cap_data, {}, func(_s): state["completed"] = true)
	session.start()

	# Tick many tiny steps up to 4.95s
	for i in range(99):
		session.tick(0.05)

	_check(session.is_preparing(), "Session remains in PREPARING at 4.95s / 5.0s")
	_check(state["completed"] == false, "Completion has not fired prematurely")

	# Final tick triggers completion
	session.tick(0.05)
	_check(session.is_completed(), "Session reaches COMPLETED at exactly 5.0s")
	_check(state["completed"] == true, "Completion fired on reaching threshold")


func _test_4_cancellation_semantics() -> void:
	print("\n--- Test 4: Cancellation Semantics ---")
	var state := {
		"completed": false,
		"cancelled": false,
		"reason": ""
	}

	var cap_data: Dictionary = {
		"charge_time": 4.0
	}
	var session = ActivationTimingSys.create_session(
		cap_data,
		{},
		func(_s): state["completed"] = true,
		func(_s, r):
			state["cancelled"] = true
			state["reason"] = r
	)
	session.start()
	session.tick(2.0)

	_check(session.is_preparing(), "Session in progress before cancellation")

	var did_cancel = session.cancel("interrupted_by_enemy")
	_check(did_cancel == true, "cancel() returned true for active session")
	_check(session.is_cancelled(), "Session phase is CANCELLED")
	_check(state["cancelled"] == true, "Cancellation callback was invoked")
	_check(state["reason"] == "interrupted_by_enemy", "Cancellation reason passed correctly")

	# Ticking after cancellation does NOT advance or complete
	session.tick(5.0)
	_check(session.is_cancelled(), "Session remains CANCELLED after subsequent ticks")
	_check(state["completed"] == false, "Completion callback NEVER executes on cancelled session")


func _test_5_cooldown_separation_from_activation() -> void:
	print("\n--- Test 5: Cooldown Separation from Activation Timing ---")
	var weapon = WeaponPartRes.new()
	weapon.weapon_name = "Heavy Particle Beam"
	weapon.special_capability = {
		"capability_type": "strategic_strike",
		"charge_time": 2.0,
		"cooldown": 18.0,
		"energy_cost": 30.0,
		"effect_payload": {"damage": 200.0, "damage_type": "heat"}
	}

	var core = WeaponCoreSys.from_weapon(weapon)
	core.cooldown = 0.0 # Ready

	var mock_energy = MockEnergySystem.new()
	mock_energy.energy = 100.0

	var user_ctx: Dictionary = {
		"core": core,
		"energy_system": mock_energy,
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1)
	}

	# Activation begins
	var res := SpecialWeaponSys.activate_special_weapon(weapon, null, user_ctx, [])
	_check(res.get("success") == true, "activate_special_weapon returned success")
	_check(res.get("is_charging") == true, "Capability is in charging state")

	var session: Variant = res.get("timing_session")
	_check(session != null, "Timing session instance returned")
	_check(session.is_preparing(), "Timing session is PREPARING")

	# During charge: core.cooldown has NOT been set to 18.0 yet, but activation is charging
	_check(core.cooldown == 0.0, "WeaponCore cooldown not consumed prematurely during charge")
	_check(mock_energy.energy == 100.0, "Energy not consumed prematurely during charge")

	# Tick 1.0s (halfway)
	session.tick(1.0)
	_check(core.cooldown == 0.0, "Cooldown remains untouched halfway through charge")

	# Tick final 1.0s -> Complete execution
	session.tick(1.0)
	_check(session.is_completed(), "Session completed after 2.0s")
	_check(core.cooldown == 18.0, "WeaponCore cooldown set to 18.0s upon completion")
	_check(mock_energy.energy == 70.0, "Energy consumed (100 - 30 = 70.0) upon completion")


func _test_6_purity_and_authority_invariants() -> void:
	print("\n--- Test 6: Purity & Authority Invariants ---")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -10)

	var hp_initial: float = dummy.health_system.current_health
	var disrupted_initial: bool = StuntWeaponSys.is_disrupted(dummy)

	var weapon = WeaponPartRes.new()
	weapon.weapon_name = "Charged Disruption Lance"
	weapon.special_capability = {
		"capability_type": "disruption",
		"charge_time": 2.0,
		"cooldown": 10.0,
		"duration": 5.0,
		"effect_payload": {"disruption_type": "movement_inhibit"}
	}

	var user_ctx: Dictionary = {
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1)
	}

	var res := SpecialWeaponSys.activate_special_weapon(weapon, null, user_ctx, [dummy])
	var session: Variant = res.get("timing_session")
	_check(session != null, "Session created for charged weapon")

	# Advance halfway
	session.tick(1.0)

	# Invariant check: While charging, target HP and status MUST NOT be touched!
	_check(dummy.health_system.current_health == hp_initial, "Target HP untouched during charge")
	_check(StuntWeaponSys.is_disrupted(dummy) == disrupted_initial, "Target disruption untouched during charge")

	# Advance to completion -> Now effect is dispatched to StuntWeaponSystem
	session.tick(1.0)
	_check(session.is_completed(), "Session is completed")
	_check(StuntWeaponSys.is_disrupted(dummy) == true, "Target disrupted authoritatively after charge completes")

	dummy.queue_free()


func _test_7_generic_telegraph_descriptor() -> void:
	print("\n--- Test 7: Generic Telegraph Descriptor ---")
	var cap_data: Dictionary = {
		"capability_type": "strategic_strike",
		"targeting_mode": "beam_line",
		"area_shape": "line",
		"area_parameters": {"length": 120.0, "width": 8.0},
		"charge_time": 2.5
	}
	var ctx: Dictionary = {
		"origin": Vector3(10, 0, 5),
		"direction": Vector3(0, 0, -1)
	}

	var session = ActivationTimingSys.create_session(cap_data, ctx)
	session.start()
	session.tick(1.25)

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("is_active") == true, "Telegraph is active while session is preparing")
	_check(is_equal_approx(float(desc.get("progress", 0.0)), 0.5), "Telegraph progress is 0.5")
	_check(desc.get("targeting_mode") == "beam_line", "Telegraph preserves targeting_mode")
	_check(desc.get("area_shape") == "line", "Telegraph preserves area_shape")
	_check(desc.get("origin") == Vector3(10, 0, 5), "Telegraph preserves origin")
	_check(desc.get("direction") == Vector3(0, 0, -1), "Telegraph preserves direction")


func _test_8_integration_with_existing_weapons() -> void:
	print("\n--- Test 8: Integration With Existing Weapons ---")
	# 1. Jammer (Instant, charge_time == 0.0)
	var jammer_res = load("res://resources/mech/stock/weapon_jammer.tres")
	var dummy1 = EnemyScene.instantiate()
	add_child(dummy1)
	dummy1.global_position = Vector3(0, 0, -10)

	TechSys._player_discovery["tech_modular_energy_interface"] = TechSys.DiscoveryState.USABLE
	var j_res := SpecialWeaponSys.activate_special_weapon(jammer_res, null, {"current_energy": 50.0}, [dummy1])

	_check(j_res.get("success") == true, "Jammer activates successfully")
	_check(j_res.get("is_charging") == false, "Jammer is NOT charging (executes instantly)")
	_check(StuntWeaponSys.is_disrupted(dummy1) == true, "Jammer applied disruption immediately")

	# 2. Satellite Cannon (Instant, charge_time == 0.0)
	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var dummy2 = EnemyScene.instantiate()
	add_child(dummy2)
	dummy2.global_position = Vector3(0, 0, -10)

	TechSys._player_discovery["tech_beam_weaponry"] = TechSys.DiscoveryState.USABLE
	var hp_before: float = float(dummy2.health_system.current_health)
	var sc_res_act := SpecialWeaponSys.activate_special_weapon(sc_res, null, {"current_energy": 100.0}, [dummy2])

	_check(sc_res_act.get("success") == true, "Satellite Cannon activates successfully")
	_check(sc_res_act.get("is_charging") == false, "Satellite Cannon is NOT charging (executes instantly)")
	_check(dummy2.health_system.current_health < hp_before, "Satellite Cannon applied damage immediately")

	dummy1.queue_free()
	dummy2.queue_free()


func _test_9_negative_architecture_checks() -> void:
	print("\n--- Test 9: Negative Architecture Checks ---")
	# Verify ActivationTimingSystem script does not define combat mutation methods
	var timing_inst = ActivationTimingSys.new()
	_check(not timing_inst.has_method("take_damage"), "ActivationTimingSystem does not define take_damage")
	_check(not timing_inst.has_method("apply_damage"), "ActivationTimingSystem does not define apply_damage")
	_check(not timing_inst.has_method("apply_disruption"), "ActivationTimingSystem does not define apply_disruption")
	_check(not timing_inst.has_method("calculate_damage"), "ActivationTimingSystem does not define calculate_damage")

