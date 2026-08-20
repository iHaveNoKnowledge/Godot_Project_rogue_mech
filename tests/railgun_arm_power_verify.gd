extends Node

## Verifies the weapon balance + railgun pass:
##   1. get_arm_power() is per-arm: a strong arm one-hands a railgun, a weak
##      arm still needs the other hand to brace it.
##   2. Machine Gun ammo dropped (minigun/LMG own the high-ammo role).
##   3. Railgun uses the heavy recoil kick (stance-recovery window) and its
##      recovery scales with leg power + total weight.
##   4. Railgun: high damage + sonic-boom flag on its core.
## Run: godot --headless --path . res://tests/railgun_arm_power_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RAIL_OK: " + name)
	else:
		_fails += 1
		printerr("RAIL_FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await _verify_arm_power()
	_verify_machine_gun_ammo()
	_verify_railgun_core()
	_verify_recoil_recovery()
	print("RAILGUN_ARM_POWER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_arm_power() -> void:
	# Default equipped frames: standard arms (carry_bonus 3) on a standard
	# chassis (power 12) -> arm power 15, below the railgun's 18 requirement.
	GlobalData.reset_run_data()
	GlobalData.chassis_id = "standard"
	var left_power := GlobalData.get_arm_power("left")
	_check(left_power == 15.0, "standard left arm power = 15 (chassis 12 + frame 3)")

	var railgun := preload("res://resources/mech/stock/weapon_railgun.tres")
	_check(railgun.requires_two_hand(left_power), "standard arm still needs both hands for the railgun")

	# Equip the heavy siege arm frame (carry_bonus 9) on the RIGHT arm.
	var frames := GlobalData.equipped_frames.duplicate(true)
	frames["arm_right"] = ArmorSystem.get_frame_catalog_entry("frame_arm_right_04")
	GlobalData.equipped_frames = frames
	var right_power := GlobalData.get_arm_power("right")
	_check(right_power == 21.0, "heavy right arm power = 21 (chassis 12 + frame 9)")
	_check(not railgun.requires_two_hand(right_power), "heavy right arm one-hands the railgun")
	# Left stays weak even with the strong right arm fitted.
	_check(GlobalData.get_arm_power("left") == 15.0, "left arm power unchanged by right-arm frame")


func _verify_machine_gun_ammo() -> void:
	var mg := preload("res://resources/mech/stock/weapon_machine_gun.tres")
	_check(mg.max_ammo < 200, "Machine Gun ammo reduced below the high-ammo guns (now %d)" % mg.max_ammo)
	var lmg := preload("res://resources/mech/stock/weapon_light_machine_gun.tres")
	var mini := preload("res://resources/mech/stock/weapon_minigun.tres")
	_check(lmg.max_ammo > mg.max_ammo, "Light MG keeps the high-ammo role (%d > %d)" % [lmg.max_ammo, mg.max_ammo])
	_check(mini.max_ammo > mg.max_ammo, "Minigun keeps the high-ammo role (%d > %d)" % [mini.max_ammo, mg.max_ammo])


func _verify_railgun_core() -> void:
	var railgun := preload("res://resources/mech/stock/weapon_railgun.tres")
	_check(railgun.damage >= 250.0, "railgun damage is very high (%.0f)" % railgun.damage)
	_check(railgun.weapon_type == WeaponPart.WeaponType.RAILGUN, "railgun is typed RAILGUN")

	var core := WeaponCore.from_weapon(railgun)
	_check(core.sonic_boom, "railgun core enables the sonic boom")
	_check(core.damage == railgun.damage, "railgun core carries the high damage")
	_check(core.projectile_color.b > core.projectile_color.r, "railgun bolt is electric blue")


func _verify_recoil_recovery() -> void:
	# Build a real mecha controller to measure the stance-recovery behavior.
	var controller_script := preload("res://scripts/mecha/mecha_controller.gd")
	var mech := CharacterBody3D.new()
	mech.set_script(controller_script)
	mech.collision_layer = 1
	add_child(mech)
	await get_tree().process_frame
	await get_tree().process_frame

	# Baseline: light mech with strong legs recovers fast.
	GlobalData.reset_run_data()
	GlobalData.chassis_id = "standard"
	var frames := GlobalData.equipped_frames.duplicate(true)
	frames["leg_left"] = ArmorSystem.get_frame_catalog_entry("frame_leg_left_04")   # carry 10
	frames["leg_right"] = ArmorSystem.get_frame_catalog_entry("frame_leg_right_04") # carry 10
	GlobalData.equipped_frames = frames
	mech._recalculate_weight()
	var light_rate := mech._recoil_decay_rate()
	var light_recovery := mech._recoil_recovery
	mech.apply_heavy_recoil_impulse(Vector3.FORWARD * 22.0)
	_check(mech._recoil_recovery > 0.5, "heavy kick opens a stance-recovery window")
	_check(mech.recoil_vector.length() > 12.0, "heavy kick pushes harder than normal recoil")
	_check(mech._recoil_recovery > light_recovery, "heavy kick extends the recovery timer")

	# Heavy mech (much more weight) recovers slower than the light one.
	GlobalData.reset_run_data()
	mech.total_weight = 180.0
	var heavy_rate := mech._recoil_decay_rate()
	_check(heavy_rate < light_rate, "heavier mech recovers from recoil slower (%.1f < %.1f)" % [heavy_rate, light_rate])

	# Stronger legs (even on the same weight) recover faster.
	var strong_frames := GlobalData.equipped_frames.duplicate(true)
	strong_frames["leg_left"] = ArmorSystem.get_frame_catalog_entry("frame_leg_left_04")
	strong_frames["leg_right"] = ArmorSystem.get_frame_catalog_entry("frame_leg_right_04")
	GlobalData.equipped_frames = strong_frames
	mech.total_weight = 60.0
	var strong_rate := mech._recoil_decay_rate()
	var weak_frames := GlobalData.equipped_frames.duplicate(true)
	weak_frames["leg_left"] = ArmorSystem.get_frame_catalog_entry("frame_leg_left_01")
	weak_frames["leg_right"] = ArmorSystem.get_frame_catalog_entry("frame_leg_right_01")
	GlobalData.equipped_frames = weak_frames
	mech.total_weight = 60.0
	var weak_rate := mech._recoil_decay_rate()
	_check(strong_rate > weak_rate, "stronger legs re-balance faster (%.1f > %.1f)" % [strong_rate, weak_rate])
