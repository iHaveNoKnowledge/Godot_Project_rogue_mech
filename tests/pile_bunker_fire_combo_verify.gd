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

	# Test-only combat camera: _melee_attack resolves melee aiming via the
	# viewport's current Camera3D and refuses to run without one
	# (weapon_manager.gd 1666-1668), so pile_bunker_fired is never emitted in
	# this bare rig. Reproduce mecha_camera.tscn's end state (offset 3.4/5.2 +
	# SpringArm 11.0, identity basis facing -Z) on a plain Camera3D so the
	# _try_fire emission path runs exactly as in combat.
	var cam := Camera3D.new()
	cam.name = "TestCombatCamera"
	mecha.add_child(cam)
	cam.position = Vector3(3.4, 5.2, 11.0)
	cam.current = true

	var pile: WeaponPart = load("res://resources/mech/stock/weapon_pile_bunker.tres").duplicate()
	pile.max_ammo = 3
	pile.ammo_per_shot = 1
	wm.left_hand = pile
	wm._set_ammo(pile, 3)

	# GDScript lambdas capture local variables by value, so writing a bool
	# inside the handler never reaches this scope. Hold receipts in a
	# Dictionary (captured by value, but the value is a shared reference) so
	# emissions are observable here.
	var fired := {"loaded": false, "empty": false}

	var conn = func(is_loaded: bool, _pos: Vector3):
		if is_loaded:
			fired["loaded"] = true
		else:
			fired["empty"] = true

	EventBus.pile_bunker_fired.connect(conn)

	# 1. Fire when loaded (ammo = 3)
	wm._try_fire("left", pile)
	_check(wm._get_ammo(pile) == 2, "firing loaded pile bunker consumes 1 ammo (3 -> 2)")
	_check(fired["loaded"], "fired_loaded signal emitted for explosive blast")

	# Fire #1's melee action plays across a frame (rotation tween + pending
	# melee execution), so advance one idle frame before the dry phase to avoid
	# overlapping melee actions inside a single tick.
	await get_tree().process_frame

	# Drain the ammo and clear the 2.0s loaded-blast cooldown. WeaponCore
	# snapshots ammo_per_shot at creation, and with the default floor of 1 its
	# can_fire() refuses a fire whose magazine is empty before the melee
	# branch's dry hammer combo runs. That combo swing is ammunition-free by
	# design ("Fast combo hammer cadence when empty"), so lift the snapshot
	# floor to 0 for the dry phase.
	wm._set_ammo(pile, 0)
	var core = wm._core_for_weapon(pile)
	if core:
		core.cooldown = 0.0
		core.ammo_per_shot = 0

	# 2. Fire when empty (ammo = 0)
	wm._try_fire("left", pile)
	_check(wm._get_ammo(pile) == 0, "firing empty pile bunker stays at 0 ammo")
	_check(fired["empty"], "fired_empty signal emitted for physical hammer combo")
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
