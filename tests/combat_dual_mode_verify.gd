extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running combat_dual_mode_verify ---")
	await _verify_combat_mode_toggling()
	await _verify_mode_weapon_sorting()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_combat_mode_toggling() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)
	var combat := Node.new()
	combat.name = "MechaCombat"
	combat.set_script(preload("res://scripts/mecha/mecha_combat.gd"))
	mecha.add_child(combat)
	await get_tree().process_frame

	_check(not combat.is_close_combat(), "starts in Ranged mode by default")
	combat.toggle_combat_mode()
	_check(combat.is_close_combat(), "toggles into Close Combat mode")
	combat.toggle_combat_mode()
	_check(not combat.is_close_combat(), "toggles back into Ranged mode")

	mecha.queue_free()
	await get_tree().process_frame


func _verify_mode_weapon_sorting() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)
	var combat := Node.new()
	combat.name = "MechaCombat"
	combat.set_script(preload("res://scripts/mecha/mecha_combat.gd"))
	mecha.add_child(combat)

	var wm := Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)
	await get_tree().process_frame

	var gun: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	var blade: WeaponPart = load("res://resources/mech/stock/weapon_heat_blade.tres")
	wm.carry = [gun, blade]

	# Close Combat Mode sorting: Melee appears first
	combat.set_combat_mode(combat.Mode.CLOSE_COMBAT)
	wm._start_selection("left")
	_check(wm.carry.size() >= 2 and wm.carry[0].weapon_type == WeaponPart.WeaponType.MELEE, "in Close Combat Mode, melee weapons are prioritized first in selection wheel")

	# Ranged Mode sorting: Guns appear first
	combat.set_combat_mode(combat.Mode.RANGED)
	wm._start_selection("left")
	_check(wm.carry.size() >= 2 and wm.carry[0].weapon_type != WeaponPart.WeaponType.MELEE, "in Ranged Mode, firearms are prioritized first in selection wheel")

	mecha.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All combat_dual_mode_verify tests passed.")
		get_tree().quit(0)
	else:
		print("combat_dual_mode_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
