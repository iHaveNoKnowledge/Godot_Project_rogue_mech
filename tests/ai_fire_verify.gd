extends Node

## Headless verification that enemy/ally/tank firing routes through the shared
## WeaponCore: cores are built in _ready, try_fire spawns projectiles with the
## right ownership, finite magazines drain + auto-reload, tanks stay unlimited.
## Run: godot --headless --path . res://tests/ai_fire_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await _verify_enemy_ranged()
	await _verify_ally()
	await _verify_tank()
	print("AI_FIRE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


# Recursively collects spawned projectile nodes (anything exposing
# fired_by_enemy, which the shared projectile.gd sets).
func _projectiles() -> Array:
	var found: Array = []
	_collect_projectiles(self, found)
	return found


func _collect_projectiles(node: Node, into: Array) -> void:
	if node.get("fired_by_enemy") != null:
		into.append(node)
	for child in node.get_children():
		_collect_projectiles(child, into)


func _verify_enemy_ranged() -> void:
	# Instantiate the capsule rusher scene but force archetype 1 (RANGED) before
	# it enters the tree so _ready builds the 25-round core.
	var scene = load("res://scenes/mecha/enemy_dummy.tscn")
	var enemy = scene.instantiate()
	enemy.archetype = 1
	add_child(enemy)
	await get_tree().process_frame

	_check(enemy.fire_core != null, "enemy ranged has fire_core")
	if enemy.fire_core == null:
		enemy.queue_free()
		return

	var core = enemy.fire_core
	_check(core.max_ammo == 25, "enemy core max_ammo 25")
	_check(core.unlimited_ammo == false, "enemy core finite ammo")
	_check(core.damage == enemy.attack_damage, "enemy core damage matches archetype")
	_check(core.damage_type == "kinetic", "enemy core kinetic")
	_check(enemy.has_ammo(), "enemy has_ammo() true at full mag")

	var before = _projectiles().size()
	var fired = core.try_fire(Vector3.ZERO, Vector3.FORWARD, true, enemy)
	await get_tree().process_frame
	var after = _projectiles().size()
	_check(fired, "enemy try_fire returns true")
	_check(after == before + 1, "enemy try_fire spawned 1 projectile")
	_check(core.ammo == 24, "enemy ammo drained to 24")

	# Ownership + stats on the spawned projectile.
	var proj = _last_projectile()
	if proj:
		_check(proj.fired_by_enemy == true, "enemy projectile is enemy-owned")
		_check(proj.damage == enemy.attack_damage, "enemy projectile damage matches")
		_check(proj.damage_type == "kinetic", "enemy projectile kinetic")

	# Drain the magazine: after the final shot the core auto-reloads.
	for i in range(24):
		core.try_fire(Vector3.ZERO, Vector3.FORWARD, true, enemy)
	_check(core.ammo == 0, "enemy ammo fully drained")
	_check(not enemy.has_ammo(), "enemy has_ammo() false when empty")
	_check(core.reloading, "enemy core auto-reloaded after empty mag")

	# A full reload window refills the magazine (auto_reload on tick).
	core.tick(core.reload_time + 0.1)
	_check(core.ammo == 25, "enemy reload refills to 25")
	_check(enemy.has_ammo(), "enemy has_ammo() true after reload")

	enemy.queue_free()


func _verify_ally() -> void:
	var scene = load("res://scenes/mecha/ally_dummy.tscn")
	var ally = scene.instantiate()
	add_child(ally)
	await get_tree().process_frame

	_check(ally.fire_core != null, "ally has fire_core")
	if ally.fire_core == null:
		ally.queue_free()
		return

	var core = ally.fire_core
	_check(core.max_ammo == 25, "ally core max_ammo 25")
	_check(core.damage == ally.attack_damage, "ally core damage matches template")

	var before = _projectiles().size()
	var fired = core.try_fire(Vector3.ZERO, Vector3.FORWARD, false, ally)
	await get_tree().process_frame
	_check(fired, "ally try_fire returns true")
	_check(_projectiles().size() == before + 1, "ally try_fire spawned 1 projectile")
	_check(core.ammo == 24, "ally ammo drained to 24")

	var proj = _last_projectile()
	if proj:
		_check(proj.fired_by_enemy == false, "ally projectile is ally-owned")
		_check(proj.damage == ally.attack_damage, "ally projectile damage matches")

	ally.queue_free()


func _verify_tank() -> void:
	var scene = load("res://scenes/mecha/enemy_tank.tscn")
	var tank = scene.instantiate()
	add_child(tank)
	await get_tree().process_frame

	_check(tank.fire_core != null, "tank has fire_core")
	if tank.fire_core == null:
		tank.queue_free()
		return

	var core = tank.fire_core
	_check(core.unlimited_ammo, "tank core is unlimited (max_ammo 0)")
	_check(core.damage == tank.attack_damage, "tank core damage matches")
	_check(core.damage_type == "explosive", "tank core explosive")

	var before = _projectiles().size()
	# _fire_tank_cannon guards on target — set one so the real path fires.
	# NOTE: the count below is synchronous (try_fire add_childs the projectile
	# in the same call); awaiting a frame here would let the tank's own
	# _physics_process auto-fire extra shots and the diving projectile explode.
	var dummy_target = CharacterBody3D.new()
	dummy_target.name = "Target"
	add_child(dummy_target)
	tank.target = dummy_target
	tank._fire_tank_cannon()
	_check(_projectiles().size() == before + 1, "tank cannon spawned 1 projectile")

	var proj = _last_projectile()
	if proj:
		_check(proj.fired_by_enemy == true, "tank projectile is enemy-owned")
		_check(proj.damage_type == "explosive", "tank projectile explosive")

	# Unlimited: firing never drains or reloads.
	core.try_fire(Vector3.ZERO, Vector3.FORWARD, true, tank)
	_check(core.ammo == 0 and not core.reloading, "tank stays unlimited after firing")

	dummy_target.queue_free()
	tank.queue_free()


func _last_projectile() -> Node:
	var list = _projectiles()
	return list[list.size() - 1] if not list.is_empty() else null
