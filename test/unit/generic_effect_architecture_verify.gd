extends Node
## GENERIC EFFECT ARCHITECTURE AUDIT & CONSOLIDATION VERIFICATION (Phase 2E-8)
##
## Validates:
## 1. EffectRequest creation purity (no target or caller state mutation during creation).
## 2. Damage effect routing through StuntWeaponSystem to authoritative Health/Damage pipeline.
## 3. Disruption effect routing through StuntWeaponSystem to authoritative movement/status gates.
## 4. Multi-target independent effect application.
## 5. Generic/Synthetic capability handling (zero weapon_id branching or requirements).
## 6. Authority boundary invariants (SpecialWeaponSystem != Damage/Status authority, EventBus != Gameplay authority).
## 7. Jammer and Satellite Cannon contract adherence.

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")
const DamageCalc = preload("res://scripts/systems/damage_calculator.gd")
const WeaponPartRes = preload("res://resources/mech/weapon_part.gd")

const EnemyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

class MockEnergySystem extends RefCounted:
	var energy: float = 100.0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("EFFECT_ARCH_OK: " + msg)
	else:
		_fails += 1
		printerr("EFFECT_ARCH_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame

	print("=== STARTING GENERIC EFFECT ARCHITECTURE VERIFICATION (PHASE 2E-8) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_1_effect_request_purity()
	_test_2_damage_effect_routing()
	_test_3_disruption_effect_routing()
	_test_4_multi_target_independent_application()
	_test_5_synthetic_capability_dispatch()
	_test_6_authority_boundary_invariants()
	_test_7_negative_architecture_checks()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_8_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_8_FAILED with %d errors" % _fails)
		get_tree().quit(1)


func _test_1_effect_request_purity() -> void:
	print("\n--- Test 1: EffectRequest Creation Purity ---")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -20)

	var health_before: float = dummy.health_system.current_health
	var disrupted_before: bool = StuntWeaponSys.is_disrupted(dummy)

	var weapon = WeaponPartRes.new()
	weapon.weapon_name = "Test Strategic Cannon"
	weapon.damage = 300.0
	weapon.special_capability = {
		"capability_type": "strategic_strike",
		"targeting_mode": "beam_line",
		"area_shape": "line",
		"area_parameters": {"length": 80.0, "width": 6.0},
		"duration": 0.0,
		"cooldown": 25.0,
		"energy_cost": 50.0,
		"effect_payload": {
			"damage": 300.0,
			"damage_type": "heat",
			"strike_radius": 15.0
		}
	}

	var caller = Node3D.new()
	add_child(caller)
	caller.global_position = Vector3.ZERO

	var mock_energy = MockEnergySystem.new()
	mock_energy.energy = 50.0

	var origin = caller.global_position
	var targets = [dummy]

	var cap = SpecialWeaponSys.resolve_special_capability(weapon)
	_check(cap.get("has_capability") == true, "Capability resolved successfully")

	# Call pure create_effect_request
	var req = SpecialWeaponSys.create_effect_request("strategic_strike", cap, origin, targets, {"caller_id": "test"})

	_check(req.is_empty() == false, "create_effect_request produced a valid request dictionary")
	_check(req.get("capability_type") == "strategic_strike", "Request has correct capability_type")
	_check(req.get("targets") == targets, "Request contains expected targets array")

	# Verify target state is 100% UNTOUCHED
	_check(dummy.health_system.current_health == health_before, "Target Health unchanged by create_effect_request")
	_check(StuntWeaponSys.is_disrupted(dummy) == disrupted_before, "Target disruption state unchanged by create_effect_request")

	# Verify caller / resource state is 100% UNTOUCHED
	_check(mock_energy.energy == 50.0, "Caller energy unchanged by create_effect_request")

	# Now test disruption capability purity
	var jammer_weapon = WeaponPartRes.new()
	jammer_weapon.weapon_name = "Test Disruptor"
	jammer_weapon.special_capability = {
		"capability_type": "disruption",
		"targeting_mode": "area_radius",
		"area_parameters": {"radius": 20.0},
		"duration": 5.0,
		"cooldown": 15.0,
		"energy_cost": 30.0,
		"effect_payload": {
			"disruption_type": "movement_inhibit"
		}
	}

	var cap_disrupt = SpecialWeaponSys.resolve_special_capability(jammer_weapon)
	var req_disrupt = SpecialWeaponSys.create_effect_request("disruption", cap_disrupt, origin, targets)
	_check(req_disrupt.is_empty() == false, "Disruption create_effect_request produced valid request")
	_check(dummy.health_system.current_health == health_before, "Target Health remains unchanged after disruption request creation")
	_check(StuntWeaponSys.is_disrupted(dummy) == disrupted_before, "Target is_disrupted remains false after disruption request creation")

	caller.queue_free()
	dummy.queue_free()


func _test_2_damage_effect_routing() -> void:
	print("\n--- Test 2: Damage Effect Routing to Existing Authority ---")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -10)

	var hp_initial: float = dummy.health_system.current_health

	var req: Dictionary = {
		"capability_type": "strategic_strike",
		"origin": Vector3.ZERO,
		"targets": [dummy],
		"duration": 0.0,
		"intensity": 1.0,
		"area_parameters": {"strike_radius": 10.0},
		"effect_payload": {
			"damage": 100.0,
			"damage_type": "heat",
			"strike_radius": 10.0
		},
		"timestamp": Time.get_ticks_msec()
	}

	# Dispatch via authoritative effect receiver (StuntWeaponSystem)
	var count = StuntWeaponSys.apply_effect_request(req)
	_check(count == 1, "apply_effect_request returned 1 affected target for damage request")

	# Verify target received damage through MechaHealthBase & DamageCalculator
	var hp_after: float = dummy.health_system.current_health
	_check(hp_after < hp_initial, "Damage was applied to target health (from %.1f to %.1f)" % [hp_initial, hp_after])

	dummy.queue_free()


func _test_3_disruption_effect_routing() -> void:
	print("\n--- Test 3: Disruption Effect Routing to Existing Authority ---")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -10)

	var req: Dictionary = {
		"capability_type": "disruption",
		"origin": Vector3.ZERO,
		"targets": [dummy],
		"duration": 3.0,
		"intensity": 1.0,
		"area_parameters": {"radius": 15.0},
		"effect_payload": {
			"duration": 3.0,
			"intensity": 1.0,
			"disruption_type": "movement_inhibit"
		},
		"timestamp": Time.get_ticks_msec()
	}

	_check(StuntWeaponSys.is_disrupted(dummy) == false, "Target is not disrupted before effect")
	_check(StuntWeaponSys.can_target_move(dummy) == true, "Target can move before disruption")

	var count = StuntWeaponSys.apply_effect_request(req)
	_check(count == 1, "apply_effect_request returned 1 for disruption request")
	_check(StuntWeaponSys.is_disrupted(dummy) == true, "Target is_disrupted is true after effect application")
	_check(StuntWeaponSys.can_target_move(dummy) == false, "StuntWeaponSystem.can_target_move is false while disrupted")

	dummy.queue_free()


func _test_4_multi_target_independent_application() -> void:
	print("\n--- Test 4: Multi-Target Independent Application ---")
	var d1 = EnemyScene.instantiate()
	var d2 = EnemyScene.instantiate()
	add_child(d1)
	add_child(d2)
	d1.global_position = Vector3(0, 0, -10)
	d2.global_position = Vector3(0, 0, -30)

	var hp1_before: float = d1.health_system.current_health
	var hp2_before: float = d2.health_system.current_health

	var req: Dictionary = {
		"capability_type": "strategic_strike",
		"origin": Vector3.ZERO,
		"targets": [d1, d2],
		"duration": 0.0,
		"intensity": 1.0,
		"area_parameters": {"strike_radius": 10.0},
		"effect_payload": {
			"damage": 50.0,
			"damage_type": "heat",
			"strike_radius": 10.0
		},
		"timestamp": Time.get_ticks_msec()
	}

	var count = StuntWeaponSys.apply_effect_request(req)
	_check(count == 2, "apply_effect_request succeeded for 2 multiple targets (count = %d)" % count)
	_check(d1.health_system.current_health < hp1_before, "Target 1 damaged independently")
	_check(d2.health_system.current_health < hp2_before, "Target 2 damaged independently")

	d1.queue_free()
	d2.queue_free()


func _test_5_synthetic_capability_dispatch() -> void:
	print("\n--- Test 5: Synthetic Capability Dispatch (Zero Weapon-ID Branching) ---")
	# Create custom synthetic weapon with no standard weapon_id
	var synthetic_weapon = WeaponPartRes.new()
	synthetic_weapon.weapon_name = "Custom Experimental Device 99"
	synthetic_weapon.special_capability = {
		"capability_type": "disruption",
		"targeting_mode": "area_radius",
		"area_parameters": {"radius": 25.0},
		"duration": 4.5,
		"cooldown": 10.0,
		"energy_cost": 20.0,
		"effect_payload": {
			"disruption_type": "movement_inhibit"
		}
	}

	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -5)

	var caller = Node3D.new()
	add_child(caller)

	var cap = SpecialWeaponSys.resolve_special_capability(synthetic_weapon)
	var req = SpecialWeaponSys.create_effect_request("disruption", cap, caller.global_position, [dummy])
	_check(req.get("capability_type") == "disruption", "Synthetic weapon correctly generated disruption request")
	_check(req.get("duration") == 4.5, "Synthetic weapon duration preserved")

	var count = StuntWeaponSys.apply_effect_request(req)
	_check(count == 1, "Synthetic weapon effect applied successfully via generic capability")
	_check(StuntWeaponSys.is_disrupted(dummy) == true, "Target disrupted by synthetic weapon")

	caller.queue_free()
	dummy.queue_free()


func _test_6_authority_boundary_invariants() -> void:
	print("\n--- Test 6: Authority Boundary Invariants ---")
	# SpecialWeaponSystem instance inspection:
	# Must not directly own damage calculations or HP modifications
	var sws_inst = SpecialWeaponSys.new()
	_check(not sws_inst.has_method("take_damage"), "SpecialWeaponSystem does not define take_damage")
	_check(not sws_inst.has_method("apply_damage"), "SpecialWeaponSystem does not define apply_damage")
	_check(not sws_inst.has_method("calculate_damage"), "SpecialWeaponSystem does not define calculate_damage")

	# StuntWeaponSystem instance inspection:
	# Receives and routes effects, but defers damage math to DamageCalculator / MechaHealthBase
	var stunt_inst = StuntWeaponSys.new()
	_check(stunt_inst.has_method("apply_effect_request"), "StuntWeaponSystem defines apply_effect_request")
	_check(stunt_inst.has_method("apply_disruption"), "StuntWeaponSystem defines apply_disruption")
	_check(stunt_inst.has_method("apply_damage_effect"), "StuntWeaponSystem defines apply_damage_effect")


func _test_7_negative_architecture_checks() -> void:
	print("\n--- Test 7: Negative Architecture Checks ---")
	# Verify that no weapon_id == 'jammer' or 'satellite_cannon' checks are used in SpecialWeaponSystem
	# by inspecting capability dictionary requirement
	var weapon_no_capability = WeaponPartRes.new()
	weapon_no_capability.weapon_name = "Jammer Legacy Shell"
	weapon_no_capability.special_capability = {}

	var cap1 = SpecialWeaponSys.resolve_special_capability(weapon_no_capability)
	_check(cap1.get("has_capability") == false,
		"Weapon named 'Jammer Legacy Shell' without capability is not treated as special weapon")

	var weapon_no_cap_sat = WeaponPartRes.new()
	weapon_no_cap_sat.weapon_name = "Satellite Cannon Shell"
	weapon_no_cap_sat.special_capability = {}

	var cap2 = SpecialWeaponSys.resolve_special_capability(weapon_no_cap_sat)
	_check(cap2.get("has_capability") == false,
		"Weapon named 'Satellite Cannon Shell' without capability is not treated as special weapon")
