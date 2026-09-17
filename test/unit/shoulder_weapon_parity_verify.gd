extends Node
## SHOULDER PARITY VERIFY — shoulders must run the SAME WeaponCore rules as hands.
## Regression for: "ยิงได้ครั้งเดียวแล้วยิงไม่ได้ แถมความร้อนขึ้นแล้วไม่ลด"
## Root causes fixed in weapon_manager.gd:
##   1. _physics_process() never ticked shoulder cores -> cooldown stuck, heat never cooled.
##   2. _hand_of_weapon() / _forward_*() only mapped left/right -> HUD never got shoulder updates.

var _fails := 0
var _checks := 0
var _got_ammo: Array = []
var _got_heat: Array = []

func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SHLDR-PARITY OK: " + name)
	else:
		_fails += 1
		printerr("SHLDR-PARITY FAIL: " + name)

func _on_shoulder_ammo(side: String, cur: int, max_ammo: int) -> void:
	_got_ammo.append([side, cur, max_ammo])

func _on_shoulder_heat(side: String, cur: float, max_h: float, over: bool) -> void:
	_got_heat.append([side, cur, max_h, over])

func _ready() -> void:
	await get_tree().process_frame
	var beam: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(beam != null, "beam rifle resource loads")
	_check(beam.uses_heat(), "beam rifle uses heat (test weapon)")

	var mgr_script: Script = load("res://scripts/mecha/weapon_manager.gd")
	var mgr: Node3D = Node3D.new()
	mgr.set_script(mgr_script)
	add_child(mgr)
	await get_tree().process_frame

	# Equip shoulders with independent copies so instance-id keys don't collide with hands.
	mgr.shoulder_left = beam.duplicate() as WeaponPart
	mgr.shoulder_right = beam.duplicate() as WeaponPart
	mgr.left_hand = beam.duplicate() as WeaponPart
	_check(mgr.shoulder_left != null and mgr.shoulder_right != null, "shoulders equip")

	# 1. Slot mapping covers shoulders (was "" before the fix).
	var key_l := str(mgr.shoulder_left.get_instance_id())
	var key_r := str(mgr.shoulder_right.get_instance_id())
	_check(mgr._hand_of_weapon(key_l) == "shoulder_left", "mapping finds shoulder_left")
	_check(mgr._hand_of_weapon(key_r) == "shoulder_right", "mapping finds shoulder_right")
	_check(mgr._hand_of_weapon(str(mgr.left_hand.get_instance_id())) == "left", "hand mapping still works")

	# 2. Forwarding emits SHOULDER signals (was silent before the fix).
	mgr.shoulder_ammo_changed.connect(_on_shoulder_ammo)
	mgr.shoulder_heat_changed.connect(_on_shoulder_heat)
	mgr._forward_ammo_changed(5, 10, key_l)
	_check(_got_ammo.size() == 1 and str(_got_ammo[0][0]) == "left" and int(_got_ammo[0][1]) == 5, "ammo forwards to shoulder_ammo_changed(left)")
	mgr._forward_heat_changed(3.0, 10.0, false, key_r)
	_check(_got_heat.size() == 1 and str(_got_heat[0][0]) == "right", "heat forwards to shoulder_heat_changed(right)")

	# 3. Same WeaponCore rules: fire -> cooldown+heat, tick -> recovers (the reported bug).
	var core: WeaponCore = mgr._core_for_weapon(mgr.shoulder_left)
	_check(core != null, "shoulder has a WeaponCore (shared system with hands)")
	core.unlimited_ammo = true
	core.cooldown = 0.0
	core.heat = 0.0
	core.overheated = false
	_check(core.can_fire(), "shoulder can fire when fresh")
	_check(core.consume_shot(), "shoulder consume_shot works")
	_check(core.cooldown > 0.0, "shoulder gains cooldown after shot")
	_check(core.heat > 0.0, "shoulder gains heat after shot")
	_check(not core.can_fire(), "shoulder locked during cooldown (same as hands)")
	core.tick(5.0)
	_check(core.cooldown <= 0.0, "shoulder cooldown clears after tick (was stuck before fix)")
	_check(core.heat <= 0.001 or core.heat < core.heat_per_shot, "shoulder heat cools after tick (was stuck before fix)")
	_check(core.can_fire(), "shoulder can fire again after cooldown+cooling")

	# 4. Overheat lock + release parity.
	var hot: WeaponCore = mgr._core_for_weapon(mgr.shoulder_right)
	hot.unlimited_ammo = true
	hot.cooldown = 0.0
	hot.heat = 0.0
	hot.overheated = false
	var shots := 0
	while not hot.is_overheated() and shots < 200:
		hot.cooldown = 0.0
		if not hot.consume_shot():
			break
		shots += 1
	_check(hot.is_overheated(), "sustained shoulder fire overheats (same as hands)")
	hot.tick(60.0)
	_check(not hot.is_overheated() and hot.can_fire(), "shoulder unlocks after cooling")

	# 5. Read helpers exist for HUD.
	_check(mgr.has_method("get_shoulder_heat_percent"), "get_shoulder_heat_percent exists")
	_check(mgr.has_method("is_shoulder_overheated"), "is_shoulder_overheated exists")

	mgr.queue_free()
	print("SHOULDER_PARITY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
