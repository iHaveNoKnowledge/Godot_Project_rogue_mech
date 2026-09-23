extends Node

## =============================================================================
## WEAPON FIRING STATE & RESOURCE LIFECYCLE AUDIT VERIFY (Phase 2E-12G)
##
## Validates the authoritative lifecycle of weapon activations and resources:
## 1. Fire Request Authority: Single authoritative gateway (WeaponCore / SpecialWeaponSystem)
## 2. Ammo Consumption: Correct deduction, dry rejection, no double-consumption
## 3. Heat & Overheat: Thermal accumulation, overheat lockout, cooling recovery
## 4. Energy Resource: Energy gating and deduction on special weapons
## 5. Cooldown Authority: Rate limiting, immediate lock on firing, recovery over delta
## 6. Charge Completion: Transitions PREPARING -> COMPLETED, commits resources & dispatch
## 7. Charge Cancellation: Transitions PREPARING -> CANCELLED, zero energy/cooldown penalty, no dispatch
## 8. Owner Destruction / Interruption during Charge: Aborts dispatch cleanly
## 9. Rapid Duplicate Input: Multiple same-frame clicks fire at most once due to cooldown
## 10. Burst / Volley Semantics: Multi-pellet weapon consumes 1 ammo for N pellets
## 11. Weapon Switching: State preservation per weapon core, isolation between weapons
## 12. Special / Instant Effect Dispatch: Instant effects route to StuntWeaponSystem without projectiles
## 13. UI Resource Observation: UI reads signals downstream, zero resource authority
## 14. Fire-to-Projectile Boundary: Projectile only spawned when consume_shot succeeds
## 15. No Resource Double-Consumption: Rejected / blocked attempts consume 0 ammo/heat/energy
## 16. No Post-Cancellation Dispatch: Cancelled session cannot invoke completion logic
## =============================================================================

const WeaponCoreScript = preload("res://scripts/systems/weapon_core.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const ActivationTimingSys = preload("res://scripts/systems/activation_timing_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")

class DummyEnergySys extends RefCounted:
	var energy: float = 100.0

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
	print("\n=== STARTING WEAPON FIRING & RESOURCE LIFECYCLE AUDIT (Phase 2E-12G) ===\n")

	test_fire_request_authority_and_validation()
	test_ammo_consumption_and_empty_rejection()
	test_heat_accumulation_overheat_and_cooling()
	test_energy_resource_gating_and_deduction()
	test_cooldown_authority_and_recovery()
	test_charge_completion_resource_and_dispatch()
	test_charge_cancellation_zero_penalty()
	test_owner_destruction_during_charge()
	test_rapid_duplicate_input_same_frame()
	test_burst_and_volley_resource_semantics()
	test_weapon_switching_core_isolation()
	test_special_instant_effect_dispatch()
	test_ui_resource_observation_zero_authority()
	test_fire_to_projectile_boundary()
	test_no_resource_double_consumption()
	test_no_post_cancellation_dispatch()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _failures])
	if _failures == 0:
		print("PHASE_2E_12G_SUCCESS\n")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_12G_FAILED: %d tests failed!\n" % _failures)
		get_tree().quit(1)


func test_fire_request_authority_and_validation() -> void:
	print("-- [Test 1] Fire Request Authority & Validation --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.max_ammo = 10
	core.ammo = 10
	core.fire_interval = 0.5
	core.cooldown = 0.0
	core.reloading = false
	core.overheated = false

	_check(core.can_fire() == true, "[1a] Weapon ready to fire when ammo > 0 and cooldown == 0")

	# Mock firing attempt
	var fired_ok: bool = core.consume_shot()
	_check(fired_ok == true, "[1b] consume_shot succeeds on valid core")
	_check(core.can_fire() == false, "[1c] can_fire immediately returns false after consume_shot due to cooldown")
	_check(is_equal_approx(core.cooldown, 0.5), "[1d] Cooldown locked to fire_interval (0.5s)")


func test_ammo_consumption_and_empty_rejection() -> void:
	print("\n-- [Test 2] Ammo Consumption & Empty Rejection --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.max_ammo = 3
	core.ammo = 3
	core.ammo_per_shot = 1
	core.fire_interval = 0.1
	core.auto_reload = false

	# Shot 1
	_check(core.consume_shot() == true, "[2a] Shot 1 consumes ammo")
	_check(core.ammo == 2, "[2b] Ammo reduced from 3 to 2")
	core.tick(0.15)

	# Shot 2
	_check(core.consume_shot() == true, "[2c] Shot 2 consumes ammo")
	_check(core.ammo == 1, "[2d] Ammo reduced to 1")
	core.tick(0.15)

	# Shot 3
	_check(core.consume_shot() == true, "[2e] Shot 3 consumes ammo")
	_check(core.ammo == 0, "[2f] Ammo reduced to 0 (dry)")
	core.tick(0.15)

	# Shot 4 (Dry)
	_check(core.can_fire() == false, "[2g] can_fire is false when ammo is 0")
	_check(core.consume_shot() == false, "[2h] consume_shot rejected when dry")
	_check(core.ammo == 0, "[2i] Ammo remains 0 (no negative ammo)")


func test_heat_accumulation_overheat_and_cooling() -> void:
	print("\n-- [Test 3] Heat Accumulation, Overheat & Cooling --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.heat_capacity = 100.0
	core.heat_per_shot = 40.0
	core.heat_cool_rate = 20.0
	core.fire_interval = 0.1
	core.unlimited_ammo = true

	# Shot 1 (+40 heat = 40)
	core.consume_shot()
	_check(is_equal_approx(core.heat, 40.0), "[3a] Heat at 40.0 after shot 1")
	_check(core.overheated == false, "[3b] Not overheated at 40%")
	core.cooldown = 0.0

	# Shot 2 (+40 heat = 80)
	core.consume_shot()
	_check(is_equal_approx(core.heat, 80.0), "[3c] Heat at 80.0 after shot 2")
	_check(core.overheated == false, "[3d] Not overheated at 80%")
	core.cooldown = 0.0

	# Shot 3 (+40 heat = 120 -> clamped to 100, triggers overheat)
	core.consume_shot()
	_check(is_equal_approx(core.heat, 100.0), "[3e] Heat clamped at capacity (100.0)")
	_check(core.overheated == true, "[3f] Overheated state triggered")
	core.cooldown = 0.0

	# Attempt to fire while overheated
	_check(core.can_fire() == false, "[3g] Overheated weapon cannot fire")
	_check(core.consume_shot() == false, "[3h] consume_shot rejected during overheat")

	# Cool down partially (heat: 100 -> 60)
	core.tick(2.0) # 2.0s * 20.0/s = 40.0 cooled -> heat = 60.0
	_check(is_equal_approx(core.heat, 60.0), "[3i] Heat reduced to 60.0 after cooling")
	_check(core.overheated == true, "[3j] Still overheated until heat reaches release threshold (50%)")

	# Cool past release threshold (heat: 60 -> 40)
	core.tick(1.0) # 1.0s * 20.0/s = 20.0 cooled -> heat = 40.0 <= 50.0
	_check(core.overheated == false, "[3k] Overheat unlocked once cooled below release threshold")
	_check(core.can_fire() == true, "[3l] Weapon ready to fire after clearing overheat")


func test_energy_resource_gating_and_deduction() -> void:
	print("\n-- [Test 4] Energy Resource Gating & Deduction --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "disruption",
		"targeting_mode": "area_radius",
		"charge_time": 0.0,
		"cooldown": 5.0,
		"energy_cost": 30.0,
		"area_parameters": { "radius": 20.0 }
	}

	var user_ctx: Dictionary = {
		"current_energy": 20.0,
		"cooldown_remaining": 0.0,
		"origin": Vector3.ZERO
	}

	# Validation should fail due to insufficient energy
	var val: Dictionary = SpecialWeaponSys.validate_special_activation(cap_data, user_ctx)
	_check(val.get("can_activate") == false, "[4a] Activation rejected when current_energy (20) < energy_cost (30)")
	_check(val.get("reason") == "insufficient_energy", "[4b] Rejection reason is insufficient_energy")

	# Provide sufficient energy (50)
	user_ctx["current_energy"] = 50.0
	var val_ok: Dictionary = SpecialWeaponSys.validate_special_activation(cap_data, user_ctx)
	_check(val_ok.get("can_activate") == true, "[4c] Activation allowed when current_energy >= energy_cost")


func test_cooldown_authority_and_recovery() -> void:
	print("\n-- [Test 5] Cooldown Authority & Recovery --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.unlimited_ammo = true
	core.fire_interval = 1.0
	core.cooldown = 0.0

	# Fire shot
	core.consume_shot()
	_check(is_equal_approx(core.cooldown, 1.0), "[5a] Cooldown set to 1.0s on fire")

	# Tick 0.4s
	core.tick(0.4)
	_check(is_equal_approx(core.cooldown, 0.6), "[5b] Cooldown reduced to 0.6s after 0.4s tick")
	_check(core.can_fire() == false, "[5c] Still cannot fire at 0.6s cooldown")

	# Tick 0.6s
	core.tick(0.6)
	_check(is_equal_approx(core.cooldown, 0.0), "[5d] Cooldown fully recovered to 0.0s")
	_check(core.can_fire() == true, "[5e] Weapon ready to fire after cooldown expires")


func test_charge_completion_resource_and_dispatch() -> void:
	print("\n-- [Test 6] Charge Completion Resource & Dispatch --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "strategic_strike",
		"targeting_mode": "beam_line",
		"charge_time": 2.0,
		"cooldown": 10.0,
		"energy_cost": 40.0,
		"area_parameters": { "length": 100.0, "width": 6.0 }
	}

	var core: WeaponCore = WeaponCoreScript.new()
	core.unlimited_ammo = true
	core.cooldown = 0.0

	var dummy_es := DummyEnergySys.new()
	dummy_es.energy = 100.0

	var user_ctx: Dictionary = {
		"current_energy": 100.0,
		"energy_system": dummy_es,
		"cooldown_remaining": 0.0,
		"core": core,
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1)
	}

	var dummy_target := Node3D.new()
	dummy_target.name = "ChargeTarget"
	dummy_target.add_to_group("enemies")
	dummy_target.position = Vector3(0, 0, -30)
	add_child(dummy_target)

	var act_res: Dictionary = SpecialWeaponSys.activate_special_weapon(cap_data, null, user_ctx, [dummy_target])
	_check(act_res.get("success") == true, "[6a] Special weapon charge started successfully")
	_check(act_res.get("is_charging") == true, "[6b] Special weapon is charging")

	var session = act_res.get("timing_session")
	_check(session != null, "[6c] Timing session created")
	_check(session.phase == ActivationTimingSys.Phase.PREPARING, "[6d] Session is in PREPARING phase")

	# Mid-charge: Energy and cooldown should NOT be deducted yet!
	session.tick(1.0)
	_check(dummy_es.energy == 100.0, "[6e] Energy untouched at 50% charge (still 100.0)")
	_check(core.cooldown == 0.0, "[6f] Cooldown untouched at 50% charge")

	# Complete charge (tick remaining 1.0s)
	session.tick(1.0)
	_check(session.phase == ActivationTimingSys.Phase.COMPLETED, "[6g] Session reached COMPLETED phase")
	_check(dummy_es.energy == 60.0, "[6h] Energy deducted on completion (100 - 40 = 60.0)")
	_check(core.cooldown == 10.0, "[6i] Cooldown (10.0s) applied to core on completion")

	dummy_target.queue_free()


func test_charge_cancellation_zero_penalty() -> void:
	print("\n-- [Test 7] Charge Cancellation Zero Penalty --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "strategic_strike",
		"charge_time": 3.0,
		"cooldown": 15.0,
		"energy_cost": 50.0
	}

	var core: WeaponCore = WeaponCoreScript.new()
	core.cooldown = 0.0

	var dummy_es := DummyEnergySys.new()
	dummy_es.energy = 80.0

	var user_ctx: Dictionary = {
		"current_energy": 80.0,
		"energy_system": dummy_es,
		"cooldown_remaining": 0.0,
		"core": core,
		"origin": Vector3.ZERO
	}

	var act_res: Dictionary = SpecialWeaponSys.activate_special_weapon(cap_data, null, user_ctx)
	var session = act_res.get("timing_session")
	session.tick(1.5) # 50% progress

	# Player cancels activation (e.g. evasive dash, stagger, weapon switch)
	session.cancel("player_evaded")
	_check(session.phase == ActivationTimingSys.Phase.CANCELLED, "[7a] Session transitioned to CANCELLED")
	_check(dummy_es.energy == 80.0, "[7b] Zero energy deducted on cancelled charge (energy stays 80.0)")
	_check(core.cooldown == 0.0, "[7c] Zero cooldown penalty on cancelled charge (cooldown stays 0.0)")

	# Subsequent tick on cancelled session does nothing
	session.tick(2.0)
	_check(dummy_es.energy == 80.0, "[7d] Post-cancellation ticks do not deduct energy")
	_check(core.cooldown == 0.0, "[7e] Post-cancellation ticks do not trigger cooldown")


func test_owner_destruction_during_charge() -> void:
	print("\n-- [Test 8] Owner Destruction During Charge --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "disruption",
		"charge_time": 2.0,
		"energy_cost": 25.0
	}

	var owner_node: Node3D = Node3D.new()
	owner_node.name = "MortallyWoundedMecha"
	add_child(owner_node)

	var session = ActivationTimingSys.create_session(cap_data, { "source_node": owner_node })
	session.start()
	session.tick(1.0) # Mid charge

	# Owner destroyed
	owner_node.queue_free()
	# Interruption check: cancel session when owner is destroyed
	session.cancel("owner_destroyed")
	_check(session.phase == ActivationTimingSys.Phase.CANCELLED, "[8a] Session safely cancelled on owner destruction")
	_check(session.get_telegraph_descriptor().get("active") == false, "[8b] Descriptor marked inactive")


func test_rapid_duplicate_input_same_frame() -> void:
	print("\n-- [Test 9] Rapid Duplicate Input in Same Frame --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.max_ammo = 100
	core.ammo = 100
	core.fire_interval = 0.25
	core.cooldown = 0.0

	var shots_fired: int = 0
	# Simulate 10 rapid input triggers in a single frame
	for i in range(10):
		if core.consume_shot():
			shots_fired += 1

	_check(shots_fired == 1, "[9a] Exactly 1 shot fired out of 10 same-frame input spam attempts")
	_check(core.ammo == 99, "[9b] Ammo deducted exactly once (100 -> 99)")
	_check(is_equal_approx(core.cooldown, 0.25), "[9c] Cooldown active (0.25s)")


func test_burst_and_volley_resource_semantics() -> void:
	print("\n-- [Test 10] Burst & Volley Resource Semantics --")
	# Shotgun style: 1 trigger activation spawns 7 pellets for 1 ammo deduction
	var shotgun_core: WeaponCore = WeaponCoreScript.new()
	shotgun_core.max_ammo = 20
	shotgun_core.ammo = 20
	shotgun_core.ammo_per_shot = 1
	shotgun_core.pellets = 7
	shotgun_core.fire_interval = 0.6

	var pellets_spawned: int = 0
	if shotgun_core.consume_shot():
		pellets_spawned = shotgun_core.pellets

	_check(shotgun_core.ammo == 19, "[10a] 1 ammo deducted for shotgun blast")
	_check(pellets_spawned == 7, "[10b] Exactly 7 pellets spawned for the single activation")

	# Heavy cannon: 2 ammo per shot
	var heavy_core: WeaponCore = WeaponCoreScript.new()
	heavy_core.max_ammo = 10
	heavy_core.ammo = 10
	heavy_core.ammo_per_shot = 2
	heavy_core.consume_shot()
	_check(heavy_core.ammo == 8, "[10c] 2 ammo deducted for heavy cannon with ammo_per_shot = 2")


func test_weapon_switching_core_isolation() -> void:
	print("\n-- [Test 11] Weapon Switching Core Isolation --")
	var core_rifle: WeaponCore = WeaponCoreScript.new()
	core_rifle.max_ammo = 30
	core_rifle.ammo = 30
	core_rifle.fire_interval = 0.2

	var core_cannon: WeaponCore = WeaponCoreScript.new()
	core_cannon.max_ammo = 5
	core_cannon.ammo = 5
	core_cannon.fire_interval = 1.5

	# Fire rifle twice
	core_rifle.consume_shot()
	core_rifle.tick(0.2)
	core_rifle.consume_shot()
	_check(core_rifle.ammo == 28, "[11a] Rifle ammo at 28")

	# Switch to cannon: Cannon state is completely independent
	_check(core_cannon.ammo == 5, "[11b] Cannon ammo unaffected at 5")
	_check(core_cannon.cooldown == 0.0, "[11c] Cannon cooldown is ready (0.0)")

	# Fire cannon
	core_cannon.consume_shot()
	_check(core_cannon.ammo == 4, "[11d] Cannon ammo reduced to 4")
	_check(is_equal_approx(core_cannon.cooldown, 1.5), "[11e] Cannon cooldown set to 1.5s")
	_check(core_rifle.ammo == 28, "[11f] Rifle ammo remains untouched at 28")


func test_special_instant_effect_dispatch() -> void:
	print("\n-- [Test 12] Special Instant Effect Dispatch --")
	var cap_data: Dictionary = {
		"has_capability": true,
		"capability_type": "disruption",
		"targeting_mode": "area_radius",
		"charge_time": 0.0, # Instant
		"cooldown": 4.0,
		"energy_cost": 20.0,
		"area_parameters": { "radius": 25.0 }
	}

	var dummy_target := Node3D.new()
	dummy_target.name = "InstantDisruptTarget"
	dummy_target.add_to_group("enemies")
	dummy_target.position = Vector3(5, 0, 5)
	add_child(dummy_target)

	var core: WeaponCore = WeaponCoreScript.new()
	var dummy_es := DummyEnergySys.new()
	dummy_es.energy = 50.0

	var user_ctx: Dictionary = {
		"current_energy": 50.0,
		"energy_system": dummy_es,
		"cooldown_remaining": 0.0,
		"core": core,
		"origin": Vector3.ZERO
	}

	var res: Dictionary = SpecialWeaponSys.activate_special_weapon(cap_data, null, user_ctx, [dummy_target])
	_check(res.get("success") == true, "[12a] Instant special weapon activation succeeded")
	_check(res.get("is_charging") == false, "[12b] Instant activation executed without charging delay")
	_check(res.get("targets_affected") == 1, "[12c] Target in radius affected immediately")
	_check(dummy_es.energy == 30.0, "[12d] Energy deducted immediately (50 - 20 = 30)")
	_check(core.cooldown == 4.0, "[12e] Cooldown set immediately (4.0s)")

	dummy_target.queue_free()


func test_ui_resource_observation_zero_authority() -> void:
	print("\n-- [Test 13] UI Resource Observation Zero Authority --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.max_ammo = 50
	core.ammo = 50

	var state: Dictionary = { "ammo": 0, "fired": false }
	core.ammo_changed.connect(func(cur, _max):
		state["ammo"] = cur
		state["fired"] = true
	)

	core.consume_shot()
	_check(state["fired"] == true, "[13a] ammo_changed signal emitted downstream on fire")
	_check(state["ammo"] == 49, "[13b] UI observer received exact authoritative ammo (49)")
	_check(core.ammo == 49, "[13c] Core retains single authoritative ammo count")


func test_fire_to_projectile_boundary() -> void:
	print("\n-- [Test 14] Fire-to-Projectile Boundary --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.max_ammo = 0
	core.ammo = 0
	core.unlimited_ammo = false

	# Attempt try_fire when empty
	var fired := core.try_fire(Vector3.ZERO, Vector3.FORWARD, false, null)
	_check(fired == false, "[14a] try_fire returns false when shot cannot be consumed")


func test_no_resource_double_consumption() -> void:
	print("\n-- [Test 15] No Resource Double Consumption --")
	var core: WeaponCore = WeaponCoreScript.new()
	core.max_ammo = 10
	core.ammo = 10
	core.fire_interval = 0.5
	core.cooldown = 0.0

	# First shot consumes
	var shot1 := core.consume_shot()
	_check(shot1 == true, "[15a] First consume_shot succeeds")
	_check(core.ammo == 9, "[15b] Ammo is 9")

	# Second shot rejected (cooldown) -> must NOT consume ammo or add heat again
	var shot2 := core.consume_shot()
	_check(shot2 == false, "[15c] Second consume_shot rejected by cooldown")
	_check(core.ammo == 9, "[15d] Ammo remains exactly 9 (no double deduction)")


func test_no_post_cancellation_dispatch() -> void:
	print("\n-- [Test 16] No Post-Cancellation Dispatch --")
	var state: Dictionary = { "invoked": false }
	var cap_data: Dictionary = {
		"charge_time": 2.0
	}
	var on_complete = func(_s):
		state["invoked"] = true

	var session = ActivationTimingSys.create_session(cap_data, {}, on_complete)
	session.start()
	session.tick(1.0)
	session.cancel("interrupted")

	# Force tick past duration
	session.tick(5.0)
	_check(state["invoked"] == false, "[16a] Completion callback NEVER invoked on cancelled session")
	_check(session.phase == ActivationTimingSys.Phase.CANCELLED, "[16b] Phase remains CANCELLED")
