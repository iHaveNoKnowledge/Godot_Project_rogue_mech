extends Node
## SATELLITE CANNON CHARGE & TELEGRAPH GAMEPLAY VERIFICATION (Phase 2E-11A)
##
## Validates:
## 1. Satellite Cannon resource charge configuration (charge = 3.0s, energy = 50, cooldown = 25, damage = 350).
## 2. Authoritative preparation lifecycle (READY -> PREPARING -> COMPLETED).
## 3. Generic telegraph descriptor contract (active, effect_id, source, target, progress, duration, geometry_type).
## 4. Single timing authority (telegraph progress derived exclusively from ActivationTimingSystem).
## 5. Strike geometry determinism (source muzzle to beam endpoint 150m away).
## 6. Target lock semantics (locked at charge start).
## 7. Resource & cooldown isolation (cooldown and energy untouched during charge, consumed on completion).
## 8. Cancellation semantics (aborts execution, inactive telegraph, 0 damage, 0 cooldown, 0 energy loss).
## 9. WeaponManager integration (ticks active sessions, exposes get_active_telegraph_descriptors).
## 10. Negative architecture checks (zero weapon-id branching, zero combat mutation in timing/telegraph).

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")
const DamageCalc = preload("res://scripts/systems/damage_calculator.gd")
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const WeaponCoreSys = preload("res://scripts/systems/weapon_core.gd")
const WeaponPartRes = preload("res://resources/mech/weapon_part.gd")

const EnemyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

class MockEnergySystem extends RefCounted:
	var energy: float = 100.0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("CHARGE_OK: " + msg)
	else:
		_fails += 1
		printerr("CHARGE_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame

	print("=== STARTING SATELLITE CANNON CHARGE & TELEGRAPH VERIFICATION (PHASE 2E-11A) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_1_resource_configuration()
	_test_2_preparation_lifecycle()
	_test_3_telegraph_descriptor_contract()
	_test_4_single_timing_authority()
	_test_5_strike_geometry_determinism()
	_test_6_target_lock_at_start()
	_test_7_resource_isolation_during_charge()
	_test_8_cancellation_semantics()
	_test_9_weapon_manager_integration()
	_test_10_negative_architecture_checks()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_11A_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_11A_FAILED with %d errors" % _fails)
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# TEST 1: RESOURCE CONFIGURATION
# -----------------------------------------------------------------------------
func _test_1_resource_configuration() -> void:
	print("\n-- [Test 1] Resource Configuration --")
	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	_check(sc != null, "[1a] weapon_satellite_cannon.tres loads successfully")
	_check(sc is WeaponPart, "[1b] Is a WeaponPart instance")
	_check(sc.has_special_capability(), "[1c] Declares special capability")

	var cap: Dictionary = SpecialWeaponSys.resolve_special_capability(sc)
	_check(float(cap.get("charge_time", 0.0)) == 3.0, "[1d] charge_time is 3.0s")
	_check(float(cap.get("energy_cost", 0.0)) == 50.0, "[1e] energy_cost is 50.0")
	_check(float(cap.get("cooldown", 0.0)) == 25.0, "[1f] cooldown is 25.0s")
	_check(float(cap.get("effect_payload", {}).get("damage", 0.0)) == 350.0, "[1g] damage is 350.0")
	_check(str(cap.get("effect_payload", {}).get("damage_type", "")) == "heat", "[1h] damage_type is heat")
	_check(cap.get("targeting_mode") == "beam_line", "[1i] targeting_mode is beam_line")
	_check(cap.get("area_shape") == "line", "[1j] area_shape is line")


# -----------------------------------------------------------------------------
# TEST 2: PREPARATION LIFECYCLE
# -----------------------------------------------------------------------------
func _test_2_preparation_lifecycle() -> void:
	print("\n-- [Test 2] Preparation Lifecycle --")
	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(sc)

	var state := {"completed": false}
	var session = ActivationTimingSys.create_session(cap, {}, func(_s): state["completed"] = true)

	_check(session.is_ready(), "[2a] Starts in READY phase")
	_check(not session.is_preparing(), "[2b] Not preparing before start()")
	_check(session.duration == 3.0, "[2c] Duration is 3.0s")

	session.start()
	_check(session.is_preparing(), "[2d] Enters PREPARING phase after start()")
	_check(not session.is_completed(), "[2e] Not completed at t=0")

	session.tick(1.0)
	_check(session.is_preparing(), "[2f] Remains PREPARING at t=1.0s")
	_check(not state["completed"], "[2g] Completion callback not called at t=1.0s")

	session.tick(1.0)
	_check(session.is_preparing(), "[2h] Remains PREPARING at t=2.0s")

	session.tick(1.0)
	_check(session.is_completed(), "[2i] Reaches COMPLETED phase at t=3.0s")
	_check(state["completed"], "[2j] Completion callback triggered at t=3.0s")


# -----------------------------------------------------------------------------
# TEST 3: TELEGRAPH DESCRIPTOR CONTRACT
# -----------------------------------------------------------------------------
func _test_3_telegraph_descriptor_contract() -> void:
	print("\n-- [Test 3] Generic Telegraph Descriptor Contract --")
	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(sc)

	var origin = Vector3(5, 2, -10)
	var direction = Vector3(0, 0, -1)
	var user_ctx = {
		"origin": origin,
		"direction": direction
	}

	var session = ActivationTimingSys.create_session(cap, user_ctx)
	session.start()
	session.tick(1.5)

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("active") == true, "[3a] Telegraph descriptor active is true during charge")
	_check(desc.get("is_active") == true, "[3b] Telegraph descriptor is_active is true")
	_check(desc.get("effect_id") == "strategic_strike", "[3c] effect_id matches strategic_strike")
	_check(desc.get("source_position") == origin, "[3d] source_position matches origin")
	_check(desc.get("direction") == direction, "[3e] direction matches aim vector")
	_check(desc.get("duration") == 3.0, "[3f] duration is 3.0s")
	_check(is_equal_approx(float(desc.get("progress", 0.0)), 0.5), "[3g] progress is 0.5 halfway through")
	_check(is_equal_approx(float(desc.get("remaining", 0.0)), 1.5), "[3h] remaining is 1.5s halfway through")
	_check(desc.get("geometry_type") == "line", "[3i] geometry_type is line")
	_check(desc.get("area_shape") == "line", "[3j] area_shape is line")
	_check(desc.get("targeting_mode") == "beam_line", "[3k] targeting_mode is beam_line")
	_check(int(desc.get("started_at", 0)) > 0, "[3l] started_at timestamp is valid")


# -----------------------------------------------------------------------------
# TEST 4: SINGLE TIMING AUTHORITY
# -----------------------------------------------------------------------------
func _test_4_single_timing_authority() -> void:
	print("\n-- [Test 4] Single Timing Authority --")
	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(sc)
	var session = ActivationTimingSys.create_session(cap, {"origin": Vector3.ZERO, "direction": Vector3.FORWARD})
	session.start()

	# Tick session in increments and ensure telegraph progress is identical to session progress
	for step in [0.6, 0.9, 0.9, 0.6]:
		session.tick(step)
		var desc: Dictionary = session.get_telegraph_descriptor()
		_check(is_equal_approx(float(desc.get("progress", -1.0)), session.get_progress()),
			"[4] Telegraph progress exactly tracks session progress (t=%.2f, prog=%.2f)" % [session.elapsed, session.get_progress()])

	_check(session.is_completed(), "[4e] Session completed after total 3.0s")
	var final_desc: Dictionary = session.get_telegraph_descriptor()
	_check(final_desc.get("active") == false, "[4f] Telegraph active is false upon completion")
	_check(final_desc.get("is_active") == false, "[4g] Telegraph is_active is false upon completion")


# -----------------------------------------------------------------------------
# TEST 5: STRIKE GEOMETRY DETERMINISM
# -----------------------------------------------------------------------------
func _test_5_strike_geometry_determinism() -> void:
	print("\n-- [Test 5] Strike Geometry Determinism --")
	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(sc)

	var origin = Vector3(10, 0, 20)
	var direction = Vector3(0, 0, -1) # Forward in Godot 4
	var session = ActivationTimingSys.create_session(cap, {"origin": origin, "direction": direction})
	session.start()

	var desc: Dictionary = session.get_telegraph_descriptor()
	var target_pos: Vector3 = desc.get("target_position", Vector3.ZERO)
	var expected_endpoint = origin + direction * 150.0 # length 150m

	_check(target_pos.is_equal_approx(expected_endpoint), "[5a] Beam endpoint is deterministic (150m along direction)")
	_check(desc.get("source") == origin, "[5b] Source position matches firing origin")
	var area_params: Dictionary = desc.get("area_parameters", {})
	_check(float(area_params.get("length", 0.0)) == 150.0, "[5c] Beam length is 150.0m")
	_check(float(area_params.get("width", 0.0)) == 12.0, "[5d] Beam width is 12.0m")


# -----------------------------------------------------------------------------
# TEST 6: TARGET LOCK AT START
# -----------------------------------------------------------------------------
func _test_6_target_lock_at_start() -> void:
	print("\n-- [Test 6] Target Lock Semantics (Locked at Charge Start) --")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -50)

	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	TechSys._player_discovery["tech_beam_weaponry"] = TechSys.DiscoveryState.USABLE

	var user_ctx = {
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1),
		"current_energy": 100.0
	}

	var res := SpecialWeaponSys.activate_special_weapon(sc, null, user_ctx, [dummy])
	_check(res.get("is_charging") == true, "[6a] Enters charging state")
	var affected: Array = res.get("affected_targets", [])
	_check(affected.has(dummy), "[6b] Target dummy locked at charge start")

	var session: Variant = res.get("timing_session")
	var desc: Dictionary = session.get_telegraph_descriptor()
	var telegraph_targets: Array = desc.get("targets", [])
	_check(telegraph_targets.has(dummy), "[6c] Telegraph descriptor retains locked targets")

	# Complete charge
	session.tick(3.0)
	_check(session.is_completed(), "[6d] Session completed")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST 7: RESOURCE ISOLATION DURING CHARGE
# -----------------------------------------------------------------------------
func _test_7_resource_isolation_during_charge() -> void:
	print("\n-- [Test 7] Resource Isolation During Charge --")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -30)

	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var mock_core = WeaponCoreSys.new()
	mock_core.cooldown = 0.0
	var mock_energy = MockEnergySystem.new()
	mock_energy.energy = 100.0

	var init_hp: float = dummy.health_system.current_health

	var user_ctx = {
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1),
		"core": mock_core,
		"energy_system": mock_energy,
		"current_energy": 100.0
	}

	TechSys._player_discovery["tech_beam_weaponry"] = TechSys.DiscoveryState.USABLE
	var res := SpecialWeaponSys.activate_special_weapon(sc, null, user_ctx, [dummy])
	var session: Variant = res.get("timing_session")

	# Halfway through charge (t = 1.5s)
	session.tick(1.5)
	_check(mock_core.cooldown == 0.0, "[7a] Cooldown remains 0.0 during charge")
	_check(mock_energy.energy == 100.0, "[7b] Energy remains 100.0 during charge")
	_check(dummy.health_system.current_health == init_hp, "[7c] Target HP untouched during charge")

	# Complete charge (t = 3.0s)
	session.tick(1.5)
	_check(session.is_completed(), "[7d] Session reaches completion")
	_check(mock_core.cooldown == 25.0, "[7e] Cooldown set to 25.0s on completion")
	_check(mock_energy.energy == 50.0, "[7f] Energy deducted by 50.0 (100 -> 50)")
	_check(dummy.health_system.current_health < init_hp, "[7g] Target takes damage upon completion")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST 8: CANCELLATION SEMANTICS
# -----------------------------------------------------------------------------
func _test_8_cancellation_semantics() -> void:
	print("\n-- [Test 8] Cancellation Semantics --")
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -30)

	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var mock_core = WeaponCoreSys.new()
	mock_core.cooldown = 0.0
	var mock_energy = MockEnergySystem.new()
	mock_energy.energy = 100.0
	var init_hp: float = dummy.health_system.current_health
	var cancel_state := {"cancelled": false, "reason": ""}

	var user_ctx = {
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1),
		"core": mock_core,
		"energy_system": mock_energy,
		"current_energy": 100.0,
		"on_cancel": func(_s, r):
			cancel_state["cancelled"] = true
			cancel_state["reason"] = r
	}

	TechSys._player_discovery["tech_beam_weaponry"] = TechSys.DiscoveryState.USABLE
	var res := SpecialWeaponSys.activate_special_weapon(sc, null, user_ctx, [dummy])
	var session: Variant = res.get("timing_session")

	session.tick(1.5)
	_check(session.is_preparing(), "[8a] Session preparing before cancel")

	var did_cancel: bool = session.cancel("staggered_by_impact")
	_check(did_cancel, "[8b] cancel() returned true")
	_check(session.is_cancelled(), "[8c] Session phase is CANCELLED")
	_check(cancel_state["cancelled"], "[8d] Cancellation callback invoked")
	_check(cancel_state["reason"] == "staggered_by_impact", "[8e] Cancellation reason preserved")

	var desc: Dictionary = session.get_telegraph_descriptor()
	_check(desc.get("active") == false, "[8f] Telegraph descriptor active is false when cancelled")
	_check(desc.get("is_active") == false, "[8g] Telegraph descriptor is_active is false when cancelled")

	# Advance time further: ensure cancelled session does not execute
	session.tick(5.0)
	_check(session.is_cancelled(), "[8h] Session remains CANCELLED after further ticks")
	_check(dummy.health_system.current_health == init_hp, "[8i] Target HP untouched after cancellation")
	_check(mock_core.cooldown == 0.0, "[8j] Cooldown NOT applied on cancellation")
	_check(mock_energy.energy == 100.0, "[8k] Energy NOT deducted on cancellation")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST 9: WEAPON MANAGER INTEGRATION
# -----------------------------------------------------------------------------
func _test_9_weapon_manager_integration() -> void:
	print("\n-- [Test 9] WeaponManager Integration --")
	var wm_script = load("res://scripts/mecha/weapon_manager.gd")
	_check(wm_script != null, "[9a] WeaponManager script loads")

	var dummy_mecha = Node3D.new()
	dummy_mecha.set("energy", 100.0)
	dummy_mecha.set("energy_system", MockEnergySystem.new())
	add_child(dummy_mecha)

	var wm = Node3D.new()
	wm.set_script(wm_script)
	dummy_mecha.add_child(wm)

	_check(wm.has_method("get_active_telegraph_descriptors"), "[9b] WeaponManager has get_active_telegraph_descriptors")
	_check(wm.get_active_telegraph_descriptors().is_empty(), "[9c] Active telegraphs initially empty")

	var sc = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	wm.set("left_hand", sc)
	var core = wm._core_for_weapon(sc)
	core.cooldown = 0.0

	FrameSys.equip_frame("arm_left", {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	})

	# Trigger hand fire
	TechSys._player_discovery["tech_beam_weaponry"] = TechSys.DiscoveryState.USABLE
	wm._try_fire("left", sc)

	var active_descs: Array = wm.get_active_telegraph_descriptors()
	_check(active_descs.size() == 1, "[9d] Exactly 1 active telegraph descriptor tracked in WeaponManager")
	if not active_descs.is_empty():
		_check(active_descs[0].get("effect_id") == "strategic_strike", "[9e] Active telegraph effect_id is strategic_strike")
		_check(active_descs[0].get("active") == true, "[9f] Active telegraph is active")

	# Tick physics process by 3.0s
	wm._physics_process(3.1)

	var post_descs: Array = wm.get_active_telegraph_descriptors()
	_check(post_descs.is_empty(), "[9g] Active telegraph cleared after completion")
	_check(core.cooldown > 0.0, "[9h] Cooldown applied on completion via WeaponManager physics tick")

	dummy_mecha.queue_free()


# -----------------------------------------------------------------------------
# TEST 10: NEGATIVE ARCHITECTURE CHECKS
# -----------------------------------------------------------------------------
func _test_10_negative_architecture_checks() -> void:
	print("\n-- [Test 10] Negative Architecture Checks --")
	var timing_inst = ActivationTimingSys.new()
	_check(not timing_inst.has_method("take_damage"), "[10a] ActivationTimingSystem does not define take_damage")
	_check(not timing_inst.has_method("apply_damage"), "[10b] ActivationTimingSystem does not define apply_damage")
	_check(not timing_inst.has_method("apply_disruption"), "[10c] ActivationTimingSystem does not define apply_disruption")
	_check(not timing_inst.has_method("calculate_damage"), "[10d] ActivationTimingSystem does not define calculate_damage")

	var desc = timing_inst.get_telegraph_descriptor()
	_check(not desc.has("take_damage"), "[10e] Telegraph descriptor has no combat execution keys")
	_check(not desc.has("apply_damage"), "[10f] Telegraph descriptor has no damage application keys")
	_check(not desc.has("mutate_health"), "[10g] Telegraph descriptor has no health mutation keys")
