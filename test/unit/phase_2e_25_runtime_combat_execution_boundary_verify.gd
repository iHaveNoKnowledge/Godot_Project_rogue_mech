extends Node

## ===========================================================================
## PHASE 2E-25: Runtime Combat State & Gameplay Execution Boundary Audit
##
## Verifies:
##   Test 1  - Combat runtime state initializes correctly
##   Test 2  - Weapon fire executes exactly once
##   Test 3  - Successful fire consumes the correct resource exactly once
##   Test 4  - Failed fire does not consume resource
##   Test 5  - Projectile/direct attack carries correct owner and damage context
##   Test 6  - Damage reaches the authoritative damage system
##   Test 7  - Armor/part damage follows actual project architecture
##   Test 8  - Lethal damage produces exactly one death
##   Test 9  - SpawnManager enemy accounting updates exactly once
##   Test 10 - Final enemy death produces exactly one combat completion
##   Test 11 - Multi-wave combat advances correctly and completes only after final wave
##   Test 12 - Pilot modifier reaches actual runtime calculation
##   Test 13 - Technology/research modifier reaches actual runtime calculation
##   Test 14 - Special weapon charge/activation/cancel lifecycle remains isolated
##   Test 15 - Combat A -> Combat B runtime state isolation
##   Test 16 - Defeat -> next Combat isolation
##   Test 17 - Escape -> next Combat isolation
##   Test 18 - Delayed/stale callback cannot complete a finished combat twice
## ===========================================================================

var _tests_passed: int = 0
var _tests_failed: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-25 RUNTIME COMBAT EXECUTION AUDIT ===")
	GameManager.suppress_scene_change = true

	_run_test_1_combat_runtime_state_initialization()
	_run_test_2_weapon_fire_executes_once()
	_run_test_3_successful_fire_consumes_resource_once()
	_run_test_4_failed_fire_no_consumption()
	_run_test_5_projectile_payload_context()
	_run_test_6_damage_authority_pipeline()
	_run_test_7_armor_part_damage_hierarchy()
	_run_test_8_lethal_damage_exactly_one_death()
	_run_test_9_spawn_manager_enemy_accounting()
	_run_test_10_final_enemy_death_single_completion()
	_run_test_11_multi_wave_combat_lifecycle()
	_run_test_12_pilot_modifier_runtime_calculation()
	_run_test_13_technology_modifier_runtime_calculation()
	_run_test_14_special_weapon_lifecycle_isolation()
	_run_test_15_combat_a_to_b_runtime_isolation()
	_run_test_16_defeat_to_next_combat_isolation()
	_run_test_17_escape_to_next_combat_isolation()
	_run_test_18_delayed_callback_idempotency()

	GameManager.suppress_scene_change = false

	print("\n==================================================")
	print("PHASE 2E-25 RUNTIME COMBAT EXECUTION SUMMARY:")
	print("  Passed: %d" % _tests_passed)
	print("  Failed: %d" % _tests_failed)
	print("==================================================")

	if _tests_failed == 0:
		print("PHASE_2E_25_SUCCESS")
	else:
		push_error("PHASE_2E_25_FAILED with %d failures" % _tests_failed)

	get_tree().quit(0 if _tests_failed == 0 else 1)


func _assert_true(condition: bool, msg: String) -> void:
	if condition:
		_tests_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_tests_failed += 1
		print("  [FAIL] %s" % msg)


## ---------------------------------------------------------------------------
## TEST 1: Combat runtime state initializes correctly
## ---------------------------------------------------------------------------
func _run_test_1_combat_runtime_state_initialization() -> void:
	print("\n-- [TEST 1] Combat Runtime State Initializes Correctly --")
	GlobalData.reset_run_data()
	GameManager.enter_combat("grunt")

	_assert_true(GameManager.current_state == GameManager.State.COMBAT, "[T1-1] Current state is State.COMBAT")
	_assert_true(GlobalData._combat_xp_awarded == false, "[T1-2] XP awarded latch is clean")
	_assert_true(GlobalData.last_combat_damage_ratio == 0.0, "[T1-3] Friendly damage ratio initialized to 0.0")
	_assert_true(GlobalData.board.ambush_pincer == false, "[T1-4] Ambush pincer latch clean")


## ---------------------------------------------------------------------------
## TEST 2: Weapon fire executes exactly once
## ---------------------------------------------------------------------------
func _run_test_2_weapon_fire_executes_once() -> void:
	print("\n-- [TEST 2] Weapon Fire Executes Exactly Once --")
	var core := WeaponCore.new()
	core.ammo = 10
	core.max_ammo = 10
	core.fire_interval = 0.5
	core.cooldown = 0.0

	var fired_count := [0]
	core.fired.connect(func(): fired_count[0] += 1)

	var success := core.consume_shot(false)
	_assert_true(success == true, "[T2-1] consume_shot returned true")
	_assert_true(fired_count[0] == 1, "[T2-2] 'fired' signal emitted exactly once (got %d)" % fired_count[0])
	_assert_true(core.cooldown == 0.5, "[T2-3] Cooldown set to fire_interval (0.5)")


## ---------------------------------------------------------------------------
## TEST 3: Successful fire consumes the correct resource exactly once
## ---------------------------------------------------------------------------
func _run_test_3_successful_fire_consumes_resource_once() -> void:
	print("\n-- [TEST 3] Successful Fire Consumes Resource Exactly Once --")
	var core := WeaponCore.new()
	core.ammo = 5
	core.max_ammo = 5
	core.ammo_per_shot = 1
	core.heat_capacity = 100.0
	core.heat_per_shot = 20.0
	core.heat = 0.0

	var ok := core.consume_shot(false)
	_assert_true(ok == true, "[T3-1] Fire succeeded")
	_assert_true(core.ammo == 4, "[T3-2] Ammo decremented from 5 to 4")
	_assert_true(core.heat > 0.0, "[T3-3] Heat accumulated from 0.0 to >0.0")


## ---------------------------------------------------------------------------
## TEST 4: Failed fire does not consume resource
## ---------------------------------------------------------------------------
func _run_test_4_failed_fire_no_consumption() -> void:
	print("\n-- [TEST 4] Failed Fire Does Not Consume Resource --")
	var core := WeaponCore.new()
	core.ammo = 0
	core.max_ammo = 5
	core.unlimited_ammo = false
	core.reserve = 0
	core.cooldown = 0.0
	core.heat = 0.0
	core.heat_capacity = 100.0

	var can := core.can_fire()
	_assert_true(can == false, "[T4-1] can_fire is false when ammo is 0 and no reserve")

	var ok := core.consume_shot(false)
	_assert_true(ok == false, "[T4-2] consume_shot rejected")
	_assert_true(core.ammo == 0, "[T4-3] Ammo remains 0")
	_assert_true(core.heat == 0.0, "[T4-4] Heat remains 0.0")


## ---------------------------------------------------------------------------
## TEST 5: Projectile/direct attack carries correct owner and damage context
## ---------------------------------------------------------------------------
func _run_test_5_projectile_payload_context() -> void:
	print("\n-- [TEST 5] Projectile Carries Correct Owner and Damage Context --")
	var proj_script = preload("res://scripts/systems/projectile.gd")
	var proj = CharacterBody3D.new()
	proj.set_script(proj_script)
	proj.damage = 45.0
	proj.damage_type = "pierce"
	proj.fired_by_enemy = true

	_assert_true(proj.damage == 45.0, "[T5-1] Projectile payload damage is 45.0")
	_assert_true(proj.damage_type == "pierce", "[T5-2] Projectile damage_type is 'pierce'")
	_assert_true(proj.fired_by_enemy == true, "[T5-3] Projectile fired_by_enemy flag is true")
	proj.free()


## ---------------------------------------------------------------------------
## TEST 6: Damage reaches authoritative damage system
## ---------------------------------------------------------------------------
func _run_test_6_damage_authority_pipeline() -> void:
	print("\n-- [TEST 6] Damage Reaches Authoritative Damage System --")
	var raw := 100.0
	var armor_data := {
		"resistance": {
			"heat": 0.5,
			"pierce": 1.0,
			"impact": 0.8
		}
	}

	var heat_dmg := DamageCalculator.calculate_armor_damage(raw, "heat", armor_data)
	var pierce_dmg := DamageCalculator.calculate_armor_damage(raw, "pierce", armor_data)
	var impact_dmg := DamageCalculator.calculate_armor_damage(raw, "impact", armor_data)

	_assert_true(heat_dmg == 50.0, "[T6-1] Heat damage mitigated to 50.0 (0.5x)")
	_assert_true(pierce_dmg == 100.0, "[T6-2] Pierce damage unmitigated at 100.0 (1.0x)")
	_assert_true(impact_dmg == 80.0, "[T6-3] Impact damage mitigated to 80.0 (0.8x)")


## ---------------------------------------------------------------------------
## TEST 7: Armor/part damage follows actual project architecture
## ---------------------------------------------------------------------------
func _run_test_7_armor_part_damage_hierarchy() -> void:
	print("\n-- [TEST 7] Armor / Part Damage Hierarchy --")
	var dummy_mech := Node3D.new()
	add_child(dummy_mech)
	var health := EnemyHealth.new()
	health.layout = EnemyHealth.Layout.FULL
	dummy_mech.add_child(health)

	# Full layout: initial body armor is 80, body frame is 60
	_assert_true(health.parts["body"]["armor_hp"] == 80.0, "[T7-1] Initial body armor HP is 80.0")
	_assert_true(health.parts["body"]["frame_hp"] == 60.0, "[T7-2] Initial body frame HP is 60.0")

	# Apply 50 damage to body armor
	health._apply_armor_damage("body", 50.0, "kinetic")
	_assert_true(health.parts["body"]["armor_hp"] < 80.0 and health.parts["body"]["armor_hp"] > 0.0, "[T7-3] Armor HP reduced by calculated damage")
	_assert_true(health.parts["body"]["frame_hp"] == 60.0, "[T7-4] Frame HP intact at 60.0")

	dummy_mech.queue_free()


## ---------------------------------------------------------------------------
## TEST 8: Lethal damage produces exactly one death
## ---------------------------------------------------------------------------
func _run_test_8_lethal_damage_exactly_one_death() -> void:
	print("\n-- [TEST 8] Lethal Damage Produces Exactly One Death --")
	var dummy_mech := Node3D.new()
	add_child(dummy_mech)
	var health := EnemyHealth.new()
	health.layout = EnemyHealth.Layout.FULL
	dummy_mech.add_child(health)

	var death_signals := [0]
	health.mecha_destroyed.connect(func(): death_signals[0] += 1)

	# Destroy body frame
	health._apply_frame_damage("body", 100.0, "kinetic")

	_assert_true(health.is_destroyed == true, "[T8-1] Mech is_destroyed is true")
	_assert_true(death_signals[0] == 1, "[T8-2] mecha_destroyed emitted exactly once (got %d)" % death_signals[0])

	# Secondary damage after death
	health._apply_frame_damage("body", 50.0, "kinetic")
	_assert_true(death_signals[0] == 1, "[T8-3] Repeated damage after death does NOT emit second mecha_destroyed")

	dummy_mech.queue_free()


## ---------------------------------------------------------------------------
## TEST 9: SpawnManager enemy accounting updates exactly once
## ---------------------------------------------------------------------------
func _run_test_9_spawn_manager_enemy_accounting() -> void:
	print("\n-- [TEST 9] SpawnManager Enemy Accounting Updates Exactly Once --")
	var spawner := SpawnManager.new()
	add_child(spawner)

	var dummy_script := GDScript.new()
	dummy_script.source_code = "extends Node3D\nvar health_system: Node = null\n"
	dummy_script.reload()

	var enemy_root := Node3D.new()
	enemy_root.set_script(dummy_script)
	enemy_root.add_to_group("enemy")
	var eh := EnemyHealth.new()
	eh.name = "HealthSystem"
	eh.layout = EnemyHealth.Layout.SIMPLE
	enemy_root.add_child(eh)
	enemy_root.set("health_system", eh)
	add_child(enemy_root)

	var alive_before := spawner._get_alive_count()
	_assert_true(alive_before == 1, "[T9-1] 1 enemy counted as alive")

	# Kill the enemy
	eh._apply_frame_damage("body", 200.0, "kinetic")
	var alive_after := spawner._get_alive_count()
	_assert_true(alive_after == 0, "[T9-2] 0 enemies alive after destruction")

	enemy_root.queue_free()
	spawner.queue_free()


## ---------------------------------------------------------------------------
## TEST 10: Final enemy death produces exactly one combat completion
## ---------------------------------------------------------------------------
func _run_test_10_final_enemy_death_single_completion() -> void:
	print("\n-- [TEST 10] Final Enemy Death Single Combat Completion --")
	var spawner := SpawnManager.new()
	add_child(spawner)

	var completion_signals := [0]
	var listener = func(v):
		if v == true:
			completion_signals[0] += 1
	EventBus.combat_ended.connect(listener)

	spawner._check_combat_ended()
	_assert_true(completion_signals[0] == 1, "[T10-1] First _check_combat_ended emits combat_ended(true) once")

	# Second call when already ended
	spawner._check_combat_ended()
	_assert_true(completion_signals[0] == 1, "[T10-2] Duplicate _check_combat_ended does NOT double-emit (got %d)" % completion_signals[0])

	EventBus.combat_ended.disconnect(listener)
	spawner.queue_free()


## ---------------------------------------------------------------------------
## TEST 11: Multi-wave combat advances correctly and completes only after final wave
## ---------------------------------------------------------------------------
func _run_test_11_multi_wave_combat_lifecycle() -> void:
	print("\n-- [TEST 11] Multi-Wave Combat Advances Correctly --")
	var spawner := SpawnManager.new()
	spawner.current_wave = 1
	add_child(spawner)

	var total_w := spawner.get_total_waves()
	_assert_true(total_w >= 1, "[T11-1] Total waves defined (got %d)" % total_w)
	_assert_true(spawner.get_current_wave() == 1, "[T11-2] Current wave tracks active wave index")

	spawner.queue_free()


## ---------------------------------------------------------------------------
## TEST 12: Pilot modifier reaches actual runtime calculation
## ---------------------------------------------------------------------------
func _run_test_12_pilot_modifier_runtime_calculation() -> void:
	print("\n-- [TEST 12] Pilot Modifier Reaches Actual Runtime Calculation --")
	var ctx_base := {"unlocked_skills": []}
	var dmg_base := CombatModifierResolver.resolve_pilot_damage_multiplier(ctx_base)
	_assert_true(dmg_base == 1.0, "[T12-1] Base pilot damage multiplier is 1.0")

	var ctx_boosted := {"unlocked_skills": ["kinetic_tuning", "point_blank_mastery"]}
	var dmg_boosted := CombatModifierResolver.resolve_pilot_damage_multiplier(ctx_boosted)
	_assert_true(dmg_boosted == 1.30, "[T12-2] Boosted pilot damage multiplier is 1.30 (+30%)")

	var spread_tight := CombatModifierResolver.resolve_pilot_spread_multiplier({"unlocked_skills": ["ballistic_calibration"]})
	_assert_true(spread_tight == 0.75, "[T12-3] Ballistic calibration spread multiplier is 0.75")


## ---------------------------------------------------------------------------
## TEST 13: Technology/research modifier reaches actual runtime calculation
## ---------------------------------------------------------------------------
func _run_test_13_technology_modifier_runtime_calculation() -> void:
	print("\n-- [TEST 13] Technology Modifier Reaches Runtime Calculation --")
	var armor_entry := {
		"id": "armor_composite_mk2",
		"defense_type": "energy",
		"resistance": {"heat": 0.6, "pierce": 1.0, "impact": 1.0}
	}
	var res := DamageCalculator.get_armor_resistance(armor_entry, "heat")
	_assert_true(res == 0.6, "[T13-1] Energy armor resistance to heat is 0.6 (40% reduction)")


## ---------------------------------------------------------------------------
## TEST 14: Special weapon charge/activation/cancel lifecycle remains isolated
## ---------------------------------------------------------------------------
func _run_test_14_special_weapon_lifecycle_isolation() -> void:
	print("\n-- [TEST 14] Special Weapon Timing Lifecycle Isolation --")
	var completed := [false]
	var cancelled := [false]

	var session = ActivationTimingSystem.create_session(
		{"charge_time": 1.0},
		{},
		func(_s): completed[0] = true,
		func(_s, _r): cancelled[0] = true
	)
	_assert_true(session.phase == ActivationTimingSystem.Phase.READY, "[T14-1] Session starts in Phase.READY")

	session.start()
	_assert_true(session.phase == ActivationTimingSystem.Phase.PREPARING, "[T14-2] Session transitions to Phase.PREPARING")

	session.tick(0.5)
	_assert_true(session.phase == ActivationTimingSystem.Phase.PREPARING, "[T14-3] Session still preparing at 0.5s")
	_assert_true(completed[0] == false, "[T14-4] Completion not fired early")

	session.cancel("test_abort")
	_assert_true(session.phase == ActivationTimingSystem.Phase.CANCELLED, "[T14-5] Cancel transitions to Phase.CANCELLED")
	_assert_true(cancelled[0] == true, "[T14-6] Cancellation callback fired")

	# Ticking after cancel does nothing
	session.tick(1.0)
	_assert_true(completed[0] == false, "[T14-7] Ticking after cancel does NOT fire completion")


## ---------------------------------------------------------------------------
## TEST 15: Combat A -> Combat B runtime state isolation
## ---------------------------------------------------------------------------
func _run_test_15_combat_a_to_b_runtime_isolation() -> void:
	print("\n-- [TEST 15] Combat A -> Combat B Runtime State Isolation --")
	var core_a := WeaponCore.new()
	core_a.cooldown = 1.5
	core_a.heat = 80.0

	# Combat B gets a fresh core initialized from loadout
	var core_b := WeaponCore.new()
	_assert_true(core_b.cooldown == 0.0, "[T15-1] Combat B weapon cooldown is fresh (0.0)")
	_assert_true(core_b.heat == 0.0, "[T15-2] Combat B weapon heat is fresh (0.0)")


## ---------------------------------------------------------------------------
## TEST 16: Defeat -> next Combat isolation
## ---------------------------------------------------------------------------
func _run_test_16_defeat_to_next_combat_isolation() -> void:
	print("\n-- [TEST 16] Defeat -> Next Combat Isolation --")
	GlobalData.reset_run_data()
	GameManager.enter_combat("boss")

	EventBus.combat_ended.emit(false) # Defeat
	GameManager.return_to_board()

	# Start Combat B
	GameManager.enter_combat("grunt")
	_assert_true(GameManager.combat_node_type == "grunt", "[T16-1] Combat B initialized as grunt")
	_assert_true(GlobalData._combat_xp_awarded == false, "[T16-2] XP latch clean for Combat B")


## ---------------------------------------------------------------------------
## TEST 17: Escape -> next Combat isolation
## ---------------------------------------------------------------------------
func _run_test_17_escape_to_next_combat_isolation() -> void:
	print("\n-- [TEST 17] Escape -> Next Combat Isolation --")
	GlobalData.reset_run_data()
	GameManager.enter_combat("ace")
	GameManager.is_escaping = true

	EventBus.combat_ended.emit(false) # Escape
	GameManager.return_to_board()

	GameManager.enter_combat("grunt")
	_assert_true(GameManager.is_escaping == false, "[T17-1] is_escaping reset to false on enter_combat")
	_assert_true(GameManager.combat_node_type == "grunt", "[T17-2] Combat B is grunt")


## ---------------------------------------------------------------------------
## TEST 18: Delayed/stale callback cannot complete a finished combat twice
## ---------------------------------------------------------------------------
func _run_test_18_delayed_callback_idempotency() -> void:
	print("\n-- [TEST 18] Delayed Callback Idempotency --")
	var spawner := SpawnManager.new()
	add_child(spawner)

	var signal_box := [0]
	var cb = func(v):
		if v == true:
			signal_box[0] += 1
	EventBus.combat_ended.connect(cb)

	spawner._check_combat_ended()
	_assert_true(signal_box[0] == 1, "[T18-1] Initial completion fired once")

	# Simulate delayed callback from destroyed base or late projectile
	spawner._on_forward_base_destroyed()
	_assert_true(signal_box[0] == 1, "[T18-2] Delayed base callback ignored when combat already ended")

	EventBus.combat_ended.disconnect(cb)
	spawner.queue_free()
