extends Node
## WEAPON INSTANCE BADGE VERIFY — one physical copy = one [E] badge.
## Reproduces: equipping one weapon shows [E] on every same-model spare in
## the hangar list (the path fallback matched the model, not the instance).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("BADGE OK: " + name)
	else:
		_fails += 1
		printerr("BADGE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	GlobalData.reset_run_data()
	var panel := HangarPartListPanel.new()

	var rifle_path := "res://resources/mech/stock/weapon_beam_rifle.tres"
	var uid_a: String = LoadoutSystem.register_weapon(rifle_path, "Rifle A")
	var uid_b: String = LoadoutSystem.register_weapon(rifle_path, "Rifle B")
	var inst_a := LoadoutSystem.get_weapon_instance(uid_a)
	var inst_b := LoadoutSystem.get_weapon_instance(uid_b)
	_check(not inst_a.is_empty() and not inst_b.is_empty(), "two copies registered as separate instances")

	# Hand: only the equipped copy badges.
	LoadoutSystem.set_hand_weapon("left", uid_a)
	_check(panel.weapon_in_loadout("weapon_left", inst_a), "[E] on the equipped copy")
	_check(not panel.weapon_in_loadout("weapon_left", inst_b), "no [E] on the spare same-model copy")
	_check(panel.is_item_equipped("weapon_left", inst_a), "is_item_equipped agrees for equipped copy")
	_check(not panel.is_item_equipped("weapon_left", inst_b), "is_item_equipped agrees for spare copy")
	# ... and not on the other hand either.
	_check(not panel.weapon_in_loadout("weapon_right", inst_a), "left-hand copy not badged on right hand")

	# Shoulder: same rule.
	var missile_path := "res://resources/mech/stock/weapon_missile.tres"
	var uid_c: String = LoadoutSystem.register_weapon(missile_path, "Missile C")
	var uid_d: String = LoadoutSystem.register_weapon(missile_path, "Missile D")
	var inst_c := LoadoutSystem.get_weapon_instance(uid_c)
	var inst_d := LoadoutSystem.get_weapon_instance(uid_d)
	LoadoutSystem.set_shoulder_weapon("left", uid_c)
	_check(panel.weapon_in_loadout("shoulder_left", inst_c), "[E] on the equipped shoulder copy")
	_check(not panel.weapon_in_loadout("shoulder_left", inst_d), "no [E] on the spare shoulder copy")

	# Carry: same rule.
	LoadoutSystem.set_hand_weapon("left", "")
	LoadoutSystem.set_shoulder_weapon("left", "")
	LoadoutSystem.add_carry_weapon(uid_a)
	_check(panel.weapon_in_loadout("weapon_carry", inst_a), "[E] on the carried copy")
	_check(not panel.weapon_in_loadout("weapon_carry", inst_b), "no [E] on the spare copy for carry")

	# Legacy path refs (old saves): model match still works.
	GlobalData.weapons.weapon_loadout["left"] = rifle_path
	_check(panel.weapon_in_loadout("weapon_left", inst_a), "legacy path ref still badges the model")
	GlobalData.weapons.weapon_loadout["left"] = ""
	GlobalData.weapons.weapon_loadout["carry"] = [rifle_path]
	_check(panel.weapon_in_loadout("weapon_carry", inst_b), "legacy carry path still badges the model")

	print("WEAPON_BADGE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("WEAPON_BADGE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_WEAPON_BADGE_TESTS_PASSED")
		get_tree().quit(0)
