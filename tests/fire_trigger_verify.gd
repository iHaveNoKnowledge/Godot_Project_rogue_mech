extends Node

## Headless verification of per-gun trigger discipline (TriggerState):
##   1. AUTO sprays while held; SEMI never fires on hold; BURST spends exactly
##      burst_total shots per press and resets on release / weapon swap.
##   2. Every stock weapon carries a valid trigger_mode, with the intended
##      SEMI/BURST assignments (big guns + pumps are press-per-shot).
## Run: godot --headless --path . res://tests/fire_trigger_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("TRIG_OK: " + name)
	else:
		_fails += 1
		printerr("TRIG_FAIL: " + name)


func _ready() -> void:
	_verify_auto()
	_verify_semi()
	_verify_burst()
	_verify_stock_data()
	await get_tree().process_frame

	print("FIRE_TRIGGER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_auto() -> void:
	var t := TriggerState.new()
	t.sync(null)
	_check(t.mode == TriggerState.AUTO, "null weapon syncs to AUTO")
	t.press()
	_check(t.allow_hold_shot(), "AUTO fires while held")
	t.on_hold_shot_fired()
	_check(t.allow_hold_shot(), "AUTO keeps firing after shots")
	t.release()
	_check(t.allow_hold_shot(), "AUTO still allows hold after release (next press sprays)")


func _verify_semi() -> void:
	var w: WeaponPart = load("res://resources/mech/stock/weapon_railgun.tres")
	var t := TriggerState.new()
	t.sync(w)
	_check(t.mode == TriggerState.SEMI, "railgun syncs to SEMI")
	t.press()
	_check(not t.allow_hold_shot(), "SEMI silent on hold after press")
	t.on_hold_shot_fired()
	_check(not t.allow_hold_shot(), "SEMI stays silent after a hold-frame attempt")
	t.release()
	_check(not t.allow_hold_shot(), "SEMI still silent until the next press")


func _verify_burst() -> void:
	var w: WeaponPart = load("res://resources/mech/stock/weapon_pilot_assault_rifle.tres")
	var t := TriggerState.new()
	t.sync(w)
	_check(t.mode == TriggerState.BURST and t.burst_total == 3, "assault rifle is BURST x3")
	_check(not t.allow_hold_shot(), "no burst without a press")
	t.press()
	for i in range(3):
		_check(t.allow_hold_shot(), "burst shot %d allowed" % (i + 1))
		t.on_hold_shot_fired()
	_check(not t.allow_hold_shot(), "burst stops after 3 counted shots")
	# Failed attempts (cooldown/empty) don't consume the burst.
	t.press()
	t.on_hold_shot_fired()
	_check(t.burst_left == 2, "one counted shot leaves 2")
	t.release()
	_check(not t.allow_hold_shot() and t.burst_left == 0, "release cancels the burst")
	# Swapping guns never carries a half burst over.
	var other: WeaponPart = load("res://resources/mech/stock/weapon_machine_gun.tres")
	t.press()
	t.sync(other)
	_check(t.burst_left == 0, "weapon swap clears burst leftovers")


func _verify_stock_data() -> void:
	var semi := [
		"weapon_railgun.tres",
		"weapon_beam_sniper.tres",
		"weapon_assault_cannon.tres",
		"weapon_missile.tres",
		"weapon_heavy_missile.tres",
		"weapon_shotgun.tres",
		"weapon_combat_shotgun.tres",
		"weapon_sawed_off.tres",
		"weapon_pilot_anti_tank_rifle.tres",
		"weapon_pilot_bazooka.tres",
	]
	var dir := DirAccess.open("res://resources/mech/stock")
	_check(dir != null, "stock weapon folder opens")
	if dir == null:
		return
	var checked := 0
	for file in dir.get_files():
		if not file.begins_with("weapon_") or not file.ends_with(".tres"):
			continue
		var w: WeaponPart = load("res://resources/mech/stock/" + file)
		if w == null:
			continue
		checked += 1
		_check(int(w.trigger_mode) >= 0 and int(w.trigger_mode) <= 2, "%s trigger_mode in range" % w.weapon_name)
		_check(int(w.burst_count) >= 1, "%s burst_count >= 1" % w.weapon_name)
		if file in semi:
			_check(int(w.trigger_mode) == TriggerState.SEMI, "%s is SEMI" % w.weapon_name)
		elif file == "weapon_pilot_assault_rifle.tres":
			_check(int(w.trigger_mode) == TriggerState.BURST and int(w.burst_count) == 3, "assault rifle is BURST x3")
		elif w.weapon_type != WeaponPart.WeaponType.MELEE and w.weapon_type != WeaponPart.WeaponType.SHIELD:
			_check(int(w.trigger_mode) == TriggerState.AUTO, "%s stays AUTO" % w.weapon_name)
	_check(checked >= 25, "audited %d stock weapons" % checked)
