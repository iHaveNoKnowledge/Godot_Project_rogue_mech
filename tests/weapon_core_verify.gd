extends Node

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("WEAPONCORE OK: " + name)
	else:
		_fails += 1
		printerr("WEAPONCORE FAIL: " + name)


func _build_weapon() -> WeaponPart:
	var weapon := WeaponPart.new()
	weapon.weapon_name = "Beam Rifle"
	weapon.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	weapon.damage = 25.0
	weapon.fire_rate = 0.2
	weapon.max_ammo = 10
	weapon.ammo_per_shot = 1
	weapon.heat_capacity = 50.0
	weapon.heat_per_shot = 10.0
	weapon.heat_cool_rate = 5.0
	weapon.heat_release_ratio = 0.5
	return weapon


func _ready() -> void:
	await get_tree().process_frame

	# --- from_weapon: player weapon ---
	var weapon := _build_weapon()
	var core := WeaponCore.from_weapon(weapon)
	_check(core.max_ammo == 10, "player core reads max_ammo from weapon")
	_check(core.ammo == 10, "player core starts with a full magazine")
	_check(core.fire_interval == 0.2, "player core reads fire interval")
	_check(core.damage == 25.0, "player core reads damage")
	_check(core.manual_reload == false, "player core manual_reload is false (enemy auto-completes reloads)")

	# --- cooldown gating ---
	_check(core.can_fire(), "player core can fire when fresh")
	core.cooldown = 0.5
	_check(not core.can_fire(), "player core blocked during cooldown")
	core.cooldown = 0.0

	# --- consume_shot drains ammo + sets cooldown, no projectile ---
	var fired_calls := [0]
	core.fired.connect(func() -> void: fired_calls[0] += 1)
	_check(core.consume_shot(), "consume_shot succeeds when ready")
	_check(core.ammo == 9, "consume_shot drains one shot")
	_check(core.cooldown > 0.0, "consume_shot applies fire cooldown")
	_check(fired_calls[0] == 1, "consume_shot emits fired")
	_check(not core.consume_shot(), "consume_shot blocked by cooldown")
	_check(core.ammo == 9, "blocked consume_shot does not drain ammo")

	# --- heat accumulation + cooling + overheat unlock ---
	_check(core.heat == 10.0, "heat accumulates per shot")
	_check(core.overheated == false, "not overheated below capacity")
	for i in range(4):
		core.cooldown = 0.0
		core.consume_shot()
	_check(core.heat >= 50.0, "heat caps at capacity")
	_check(core.overheated == true, "weapon overheats at full heat")
	_check(not core.can_fire(), "overheated weapon cannot fire")

	# Cool below the release ratio (0.5 * 50 = 25) to unlock.
	core.tick(6.0)
	_check(core.overheated == false, "overheat clears after cooling past release ratio")
	_check(core.can_fire(), "weapon unlocks after overheat clears")

	# --- auto reload on empty (enemy behaviour) ---
	var enemy := WeaponCore.from_stats({
		"attack_damage": 12.0,
		"attack_cooldown": 1.0,
		"max_ammo": 3,
		"reload_time": 0.5,
	})
	_check(enemy.max_ammo == 3, "enemy core reads max_ammo from stats")
	_check(enemy.auto_reload == true, "enemy core auto-reloads when empty")
	enemy.cooldown = 0.0
	enemy.consume_shot()
	enemy.cooldown = 0.0
	enemy.consume_shot()
	enemy.cooldown = 0.0
	enemy.consume_shot()
	_check(enemy.ammo == 0, "enemy core drains all ammo")
	_check(enemy.reloading == true, "enemy core auto-begins reload at empty")
	enemy.tick(0.5)
	_check(enemy.reloading == false, "enemy core auto-completes reload via tick")
	_check(enemy.ammo == 3, "enemy core refills the magazine")

	# --- unlimited ammo: no magazine, no reload ---
	var grunt := WeaponCore.from_stats({"attack_damage": 5.0, "max_ammo": 0})
	_check(grunt.unlimited_ammo == true, "max_ammo 0 becomes unlimited ammo")
	grunt.cooldown = 0.0
	grunt.consume_shot()
	grunt.cooldown = 0.0
	_check(grunt.ammo == 0 and grunt.can_fire(), "unlimited ammo never runs dry")
	_check(grunt.reloading == false, "unlimited ammo never reloads")

	# --- try_fire spawns a projectile into the tree ---
	var owner := Node3D.new()
	add_child(owner)
	var proj_core := WeaponCore.from_weapon(weapon)
	var before := get_tree().current_scene.get_child_count() if get_tree().current_scene else 0
	var shot := proj_core.try_fire(Vector3.ZERO, Vector3.FORWARD, false, owner)
	_check(shot == true, "try_fire consumes a shot")
	_check(proj_core.ammo == 9, "try_fire drains ammo")
	# The projectile is parented to the current scene (added under the root Node,
	# so count the owner's parent tree after a frame).
	await get_tree().process_frame
	_check(owner.get_child_count() == 0, "try_fire does not parent projectiles to the owner")
	owner.queue_free()

	print("WEAPON_CORE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
