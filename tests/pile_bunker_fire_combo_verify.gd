extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running pile_bunker_fire_combo_verify ---")
	await _verify_pile_bunker_loaded_and_empty_combo()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_pile_bunker_loaded_and_empty_combo() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	var wm := Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)
	await get_tree().process_frame

	var pile: WeaponPart = load("res://resources/mech/stock/weapon_pile_bunker.tres").duplicate()
	pile.max_ammo = 3
	pile.ammo_per_shot = 1
	wm.left_hand = pile
	wm._set_ammo(pile, 3)

	var fired_loaded: bool = false
	var fired_empty: bool = false

	var conn = func(is_loaded: bool, _pos: Vector3):
		if is_loaded:
			fired_loaded = true
		else:
			fired_empty = true

	EventBus.pile_bunker_fired.connect(conn)

	# 1. Fire when loaded (ammo = 3)
	wm._try_fire("left", pile)
	_check(wm._get_ammo(pile) == 2, "firing loaded pile bunker consumes 1 ammo (3 -> 2)")
	_check(fired_loaded, "fired_loaded signal emitted for explosive blast")

	# Drain ammo to 0
	wm._set_ammo(pile, 0)
	var core = wm._core_for_weapon(pile)
	if core:
		core.cooldown = 0.0

	# 2. Fire when empty (ammo = 0)
	wm._try_fire("left", pile)
	_check(wm._get_ammo(pile) == 0, "firing empty pile bunker stays at 0 ammo")
	_check(fired_empty, "fired_empty signal emitted for physical hammer combo")
	_check(core != null and core.cooldown > 0.0, "cooldown engaged for empty hammer combo cadence")

	EventBus.pile_bunker_fired.disconnect(conn)
	mecha.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All pile_bunker_fire_combo_verify tests passed.")
		get_tree().quit(0)
	else:
		print("pile_bunker_fire_combo_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
