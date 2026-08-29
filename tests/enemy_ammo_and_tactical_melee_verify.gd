extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running enemy_ammo_and_tactical_melee_verify ---")
	_test_weapon_core_finite_reserve()
	_test_enemy_archetype_finite_ammo_and_melee_fallback()
	_test_state_attack_melee_execution_when_dry()

	print("ENEMY_AMMO_AND_TACTICAL_MELEE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_weapon_core_finite_reserve() -> void:
	print("Testing WeaponCore finite reserve ammo and dry detection...")
	var core = WeaponCore.from_stats({
		"max_ammo": 10,
		"reserve_ammo": 20,
		"reload_time": 0.1,
		"attack_cooldown": 0.0,
		"unlimited_ammo": false
	})
	_check(core.max_ammo == 10, "WeaponCore max_ammo is 10")
	_check(core.ammo == 10, "WeaponCore starts with full magazine (10)")
	_check(core.reserve == 20, "WeaponCore starts with finite reserve (20)")
	_check(not core.is_completely_dry(), "WeaponCore is not dry initially")

	# Fire 10 shots
	for i in range(10):
		_check(core.consume_shot(), "Shot %d consumed" % (i + 1))
	_check(core.ammo == 0, "Magazine is empty (0)")
	_check(not core.is_completely_dry(), "WeaponCore not dry yet because reserve remains (20)")

	# Reload 1
	core.begin_reload()
	core.complete_reload()
	_check(core.ammo == 10, "Magazine refilled to 10")
	_check(core.reserve == 10, "Reserve reduced to 10")

	# Fire 10 shots
	for i in range(10):
		core.consume_shot()
	_check(core.ammo == 0, "Magazine empty again (0)")

	# Reload 2
	core.begin_reload()
	core.complete_reload()
	_check(core.ammo == 10, "Magazine refilled to 10")
	_check(core.reserve == 0, "Reserve depleted to 0")

	# Fire final 10 shots
	for i in range(10):
		core.consume_shot()
	_check(core.ammo == 0, "Magazine is 0")
	_check(core.reserve == 0, "Reserve is 0")
	_check(core.is_completely_dry(), "WeaponCore is now completely dry (is_completely_dry == true)")

	# Attempt reload when dry
	var can_reload = core.begin_reload()
	_check(not can_reload, "begin_reload() returns false when reserve is 0")


func _test_enemy_archetype_finite_ammo_and_melee_fallback() -> void:
	print("Testing Enemy Dummy finite ammo setup & melee fallback trigger...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.archetype = 1 # RANGED
	add_child(enemy)

	_check(enemy.fire_core != null, "Enemy has fire_core instantiated")
	_check(enemy.max_ammo == 25, "Ranged enemy has max_ammo = 25")
	_check(enemy.reserve_ammo > 0, "Ranged enemy has finite reserve ammo (%d)" % enemy.reserve_ammo)
	_check(enemy.attack_range >= 15.0, "Ranged enemy initial attack range is >= 15.0 (%.1f)" % enemy.attack_range)
	_check(not enemy.is_melee_fallback_active, "is_melee_fallback_active is false initially")

	# Deplete enemy ammo
	enemy.fire_core.ammo = 0
	enemy.fire_core.reserve = 0
	_check(enemy.is_out_of_ammo(), "enemy.is_out_of_ammo() is true")

	# Process frame
	enemy._process(0.016)

	_check(enemy.is_melee_fallback_active, "enemy.is_melee_fallback_active triggered true")
	_check(enemy.attack_range <= 4.0, "attack_range reduced to melee range (%.1f)" % enemy.attack_range)
	_check(enemy.move_speed > 3.0, "move_speed boosted for melee charge (%.1f)" % enemy.move_speed)

	enemy.queue_free()


func _test_state_attack_melee_execution_when_dry() -> void:
	print("Testing StateAttack melee strike execution when enemy is dry...")
	var enemy_scene = preload("res://scenes/mecha/enemy_dummy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.archetype = 1 # RANGED
	add_child(enemy)

	var dummy_target = Node3D.new()
	add_child(dummy_target)
	dummy_target.global_position = enemy.global_position + Vector3(0, 0, 3.0)
	enemy.target = dummy_target

	# Deplete ammo & trigger melee fallback
	enemy.fire_core.ammo = 0
	enemy.fire_core.reserve = 0
	enemy.switch_to_melee_fallback()

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	_check(state_attack != null, "StateAttack exists on enemy state_machine")

	if state_attack:
		state_attack._snapshot_melee_swing_dir()
		_check(state_attack._melee_swing_dir.length() > 0.0, "Melee swing direction snapped for dry ranged enemy")

	dummy_target.queue_free()
	enemy.queue_free()
