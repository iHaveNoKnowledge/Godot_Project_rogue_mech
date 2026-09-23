extends Node

## ===========================================================================
## PHASE 2E-20A COMBAT RESOLUTION LIFECYCLE & ENEMY DAMAGE VERIFICATION SUITE
## ===========================================================================

const SpawnManagerCls = preload("res://scripts/systems/spawn_manager.gd")
const EnemyDummyCls = preload("res://scripts/mecha/enemy_dummy.gd")
const EnemyHealthCls = preload("res://scripts/mecha/enemy_health.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-20A COMBAT PIPELINE & LIFECYCLE VERIFICATION ===")
	_run_all_tests()
	_print_summary()
	if _fail_count == 0:
		print("PHASE_2E_20A_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_20A_FAILED with %d errors" % _fail_count)
		get_tree().quit(1)


func _run_all_tests() -> void:
	_test_spawn_manager_completion_idempotency()
	_test_spawn_manager_encounter_reset_lifecycle()
	_test_enemy_full_layout_body_armor_break()
	_test_enemy_simple_layout_compatibility()
	_test_forward_base_completion_idempotency()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % test_name)
	else:
		_fail_count += 1
		push_error("  [FAIL] %s" % test_name)


# --- [TEST A] SpawnManager Combat-End Idempotency ---
func _test_spawn_manager_completion_idempotency() -> void:
	print("\n-- [TEST A] SpawnManager Combat-End Idempotency (F-01) --")
	var sm = SpawnManagerCls.new()
	add_child(sm)
	sm.is_active = true
	sm._combat_ended = false

	var counts := {"combat_ended": 0}
	var test_cb := func(victory: bool) -> void:
		if victory:
			counts["combat_ended"] += 1
	EventBus.combat_ended.connect(test_cb)

	# Simulate empty stalkers and 0 enemies alive
	GlobalData.narrative.stalking_aces.clear()
	sm.enemies_alive = 0

	# First completion check
	sm._check_combat_ended()
	_check(counts["combat_ended"] == 1, "First _check_combat_ended emits combat_ended(true) once")
	_check(sm._combat_ended == true, "SpawnManager._combat_ended is committed to true")

	# Subsequent simultaneous/repeated completion checks
	sm._check_combat_ended()
	sm._check_combat_ended()
	_check(counts["combat_ended"] == 1, "Repeated _check_combat_ended calls do NOT produce duplicate emissions (emissions == 1)")

	EventBus.combat_ended.disconnect(test_cb)
	sm.queue_free()


# --- [TEST B] SpawnManager Encounter Reset Lifecycle ---
func _test_spawn_manager_encounter_reset_lifecycle() -> void:
	print("\n-- [TEST B] SpawnManager Encounter Reset Lifecycle (F-01) --")
	var sm = SpawnManagerCls.new()
	add_child(sm)
	sm._combat_ended = true

	# Simulate new combat encounter start
	sm._ready()
	_check(sm._combat_ended == false, "New encounter initialization (_ready) resets _combat_ended to false")

	var counts := {"combat_ended": 0}
	var test_cb := func(victory: bool) -> void:
		if victory:
			counts["combat_ended"] += 1
	EventBus.combat_ended.connect(test_cb)

	GlobalData.narrative.stalking_aces.clear()
	sm.enemies_alive = 0
	sm._check_combat_ended()

	_check(counts["combat_ended"] == 1, "New encounter successfully emits combat_ended(true) after reset")
	_check(sm._combat_ended == true, "_combat_ended set to true for the new encounter")

	EventBus.combat_ended.disconnect(test_cb)
	sm.queue_free()


# --- [TEST C] Enemy FULL Layout Body Armor Break vs Frame Destruction ---
func _test_enemy_full_layout_body_armor_break() -> void:
	print("\n-- [TEST C] Enemy FULL Layout Body Armor Break (F-02) --")
	var enemy: Node = null
	var full_scene := load("res://scenes/mecha/enemy_dummy_full.tscn") as PackedScene
	if full_scene != null:
		enemy = full_scene.instantiate()
	else:
		enemy = EnemyDummyCls.new()
		var eh_custom = EnemyHealthCls.new()
		eh_custom.layout = EnemyHealthCls.Layout.FULL
		eh_custom.name = "HealthSystem"
		enemy.add_child(eh_custom)

	add_child(enemy)
	var eh: EnemyHealth = enemy.get("health_system") as EnemyHealth
	_check(eh != null, "Enemy has valid HealthSystem")
	eh.layout = EnemyHealthCls.Layout.FULL
	eh._init_parts()
	eh._calculate_totals()

	var counts := {"mecha_destroyed": 0}
	var destroyed_cb := func() -> void:
		counts["mecha_destroyed"] += 1
	eh.mecha_destroyed.connect(destroyed_cb)

	# Full layout body initial stats: max_armor 80, max_frame 60
	_check(eh.parts["body"]["armor_hp"] == 80.0, "Initial body armor HP is 80")
	_check(eh.parts["body"]["frame_hp"] == 60.0, "Initial body frame HP is 60")
	_check(not eh.is_destroyed, "Enemy is not destroyed initially")

	# Break BODY ARMOR completely (deal 100 pierce damage)
	eh.take_damage_to_part("body", 100.0, "pierce", "armor")

	# Verification after body armor break:
	_check(eh.parts["body"]["armor_hp"] == 0.0, "Body armor HP is reduced to 0")
	_check(eh.parts["body"]["armor_broken"] == true, "Body armor is marked broken")
	_check(eh.parts["body"]["frame_hp"] == 60.0, "Body frame HP remains pristine (60.0)")
	_check(eh.is_destroyed == false, "FULL layout enemy is NOT destroyed when body armor breaks")
	_check(counts["mecha_destroyed"] == 0, "mecha_destroyed signal was NOT emitted on body armor break")

	# Now destroy BODY FRAME (deal 80 damage to frame)
	eh.take_damage_to_part("body", 80.0, "pierce", "frame")

	_check(eh.parts["body"]["frame_hp"] == 0.0, "Body frame HP is reduced to 0")
	_check(eh.parts["body"]["destroyed"] == true, "Body part is marked destroyed")
	_check(eh.is_destroyed == true, "FULL layout enemy is destroyed when body frame is destroyed")
	_check(counts["mecha_destroyed"] == 1, "mecha_destroyed signal is emitted exactly once on body frame destruction")

	eh.mecha_destroyed.disconnect(destroyed_cb)
	enemy.queue_free()


# --- [TEST D] Enemy SIMPLE Layout Compatibility ---
func _test_enemy_simple_layout_compatibility() -> void:
	print("\n-- [TEST D] Enemy SIMPLE Layout Compatibility (F-02) --")
	var enemy: Node = null
	var simple_scene := load("res://scenes/mecha/enemy_dummy.tscn") as PackedScene
	if simple_scene != null:
		enemy = simple_scene.instantiate()
	else:
		enemy = EnemyDummyCls.new()
		var eh_custom = EnemyHealthCls.new()
		eh_custom.layout = EnemyHealthCls.Layout.SIMPLE
		eh_custom.name = "HealthSystem"
		enemy.add_child(eh_custom)

	add_child(enemy)
	var eh: EnemyHealth = enemy.get("health_system") as EnemyHealth
	_check(eh != null, "Enemy has valid HealthSystem")
	eh.layout = EnemyHealthCls.Layout.SIMPLE
	eh._init_parts()
	eh._calculate_totals()

	var counts := {"mecha_destroyed": 0}
	var destroyed_cb := func() -> void:
		counts["mecha_destroyed"] += 1
	eh.mecha_destroyed.connect(destroyed_cb)

	_check(eh.parts["body"]["armor_hp"] == 100.0, "Initial SIMPLE body armor HP is 100")

	# Break body armor on SIMPLE layout
	eh.take_damage_to_part("body", 150.0, "pierce", "armor")

	_check(eh.parts["body"]["armor_hp"] == 0.0, "SIMPLE body armor HP is 0")
	_check(eh.is_destroyed == true, "SIMPLE layout terminates on body armor break as intended")
	_check(counts["mecha_destroyed"] == 1, "SIMPLE layout emits mecha_destroyed on body armor break")

	eh.mecha_destroyed.disconnect(destroyed_cb)
	enemy.queue_free()


# --- [TEST E] Forward Base Completion Idempotency ---
func _test_forward_base_completion_idempotency() -> void:
	print("\n-- [TEST E] Forward Base Completion Idempotency (F-01) --")
	var sm = SpawnManagerCls.new()
	add_child(sm)
	sm.is_active = true
	sm._combat_ended = false

	var counts := {"combat_ended": 0}
	var test_cb := func(victory: bool) -> void:
		if victory:
			counts["combat_ended"] += 1
	EventBus.combat_ended.connect(test_cb)

	# Simulate base destroyed callback
	sm._combat_ended = true # If already ended
	sm._on_forward_base_destroyed() # Async timer
	_check(counts["combat_ended"] == 0, "_on_forward_base_destroyed does not emit if _combat_ended is true")

	EventBus.combat_ended.disconnect(test_cb)
	sm.queue_free()


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-20A COMBAT PIPELINE VERIFICATION SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	print("==================================================")
