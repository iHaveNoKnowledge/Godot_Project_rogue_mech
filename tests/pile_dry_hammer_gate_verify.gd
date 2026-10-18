extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running pile_dry_hammer_gate_verify ---")
	await _verify_dry_hammer_reachability_and_gate_persistence()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _rig() -> CharacterBody3D:
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
	# this bare rig. Same rig reproduction as pile_bunker_fire_combo_verify
	# (mecha_camera.tscn end state: offset 3.4/5.2 + 11.0, identity basis).
	var cam := Camera3D.new()
	cam.name = "TestCombatCamera"
	mecha.add_child(cam)
	cam.position = Vector3(3.4, 5.2, 11.0)
	cam.current = true
	return mecha


func _verify_dry_hammer_reachability_and_gate_persistence() -> void:
	var mecha := await _rig()
	var wm = mecha.get_node("WeaponManager")

	# GDScript lambdas capture local variables by value, so receipts live in
	# Dictionaries (shared references the handlers mutate).
	var receipts := {"loaded": 0, "empty": 0}
	var conn = func(is_loaded: bool, _pos: Vector3):
		if is_loaded:
			receipts["loaded"] += 1
		else:
			receipts["empty"] += 1
	EventBus.pile_bunker_fired.connect(conn)

	# Authored loadout: the pile bunker keeps its authored ammo_per_shot=1
	# snapshot (WeaponCore.from_weapon lifts per_shot at creation). This suite
	# NEVER lifts core.ammo_per_shot — reachability must come from the gate,
	# not from a test-only data override.
	var pile: WeaponPart = load("res://resources/mech/stock/weapon_pile_bunker.tres").duplicate()
	wm.left_hand = pile
	wm._set_ammo(pile, 3)
	var core = wm._core_for_weapon(pile)
	_check(core != null and core.ammo_per_shot == 1, "authored snapshot intact: core.ammo_per_shot == 1")

	# 1) Empty magazine + authored floor -> the dry hammer combo must stay
	# reachable through the weapon-action gate (the production fix).
	wm._set_ammo(pile, 0)
	_check(core != null and not core.can_fire(), "empty pile refuses can_fire() (ammunition floor intact)")
	_check(core != null and core.can_swing(), "can_swing() is TRUE for the same empty state (exact API delta)")
	wm._try_fire("left", pile)
	_check(receipts["empty"] == 1 and receipts["loaded"] == 0, "empty press emits pile_bunker_fired(false): dry hammer combo reachable")
	_check(wm._get_ammo(pile) == 0, "dry hammer consumes no ammo (stays 0)")
	_check(core != null and core.cooldown > 0.0, "dry hammer engages the 0.45 combo cadence cooldown")

	# 2) The hammer still respects the cooldown gate.
	var empty_before: int = receipts["empty"]
	wm._try_fire("left", pile)
	_check(receipts["empty"] == empty_before, "immediate second dry press is cooldown-blocked (no extra receipt)")
	_check(core != null and not core.can_swing(), "can_swing() honors cooldown while cooling")

	# 3) The hammer still respects overheat and reload (can_swing contract).
	core.cooldown = 0.0
	core.overheated = true
	_check(core != null and not core.can_swing(), "can_swing() honors overheat")
	wm._try_fire("left", pile)
	_check(receipts["empty"] == empty_before, "overheated pile refuses the dry hammer press")
	core.reloading = true
	_check(core != null and not core.can_swing(), "can_swing() honors the reloading state")
	core.reloading = false
	core.overheated = false

	# 4) A loaded pile still pays the full spike blast: pricing + consumption.
	core.cooldown = 0.0
	wm._set_ammo(pile, 3)
	var loaded_before: int = receipts["loaded"]
	wm._try_fire("left", pile)
	_check(receipts["loaded"] == loaded_before + 1, "loaded press emits pile_bunker_fired(true): spike blast")
	_check(wm._get_ammo(pile) == 2, "loaded blast consumes exactly 1 spike (3 -> 2)")
	_check(receipts["empty"] == empty_before, "loaded press never emits the dry hammer receipt")

	await get_tree().process_frame

	# 5) Non-melee presses keep the uniform can_fire() ammunition floor. The
	# machine gun fires at a full magazine first, proving its permission path
	# (the gate capability is stateless, so the ONLY variable in the second
	# attempt is ammo == 0 -> the elif core floor itself rejects).
	var gun: WeaponPart = load("res://resources/mech/stock/weapon_machine_gun.tres").duplicate()
	wm.left_hand = gun
	await get_tree().process_frame
	var gun_core = wm._core_for_weapon(gun)
	var gun_hits := {"fired": 0}
	var gun_conn = func():
		gun_hits["fired"] += 1
	gun_core.fired.connect(gun_conn)
	wm._set_ammo(gun, 120)
	var control_ammo: int = wm._get_ammo(gun)
	wm._try_fire("left", gun)
	# fired is emitted by consume_shot (weapon_core.gd 233) AND re-emitted by
	# try_fire (274), so one live shot counts at least 2 here.
	_check(gun_hits["fired"] >= 1, "full machine gun fires through the normal permission path (control)")
	_check(wm._get_ammo(gun) == control_ammo - 1, "control press consumed exactly 1 bullet")
	_check(gun_core.cooldown > 0.0, "control press armed cooldown")
	gun_core.cooldown = 0.0
	wm._set_ammo(gun, 0)
	_check(gun_core != null and not gun_core.can_fire(), "ranged floor intact: empty machine gun can_fire() is FALSE")
	var heat_before_reject: float = gun_core.heat
	var fired_before_reject: int = gun_hits["fired"]
	wm._try_fire("left", gun)
	_check(gun_hits["fired"] == fired_before_reject, "ranged press at 0 ammo is rejected: no shot consumed (fired counter unchanged)")
	_check(wm._get_ammo(gun) == 0, "rejected ranged press consumed no ammo")
	_check(gun_core.heat == heat_before_reject, "rejected ranged press accumulated no heat")
	_check(gun_core.cooldown == 0.0, "rejected ranged press consumed no cooldown")

	# 6) Authored ammunition-free melee (ammo_per_shot == 0) keep firing with
	# the UNIFORM gate: they never needed (and never get) the pile exemption.
	var bus_total: int = receipts["loaded"] + receipts["empty"]
	for weapon_path in ["res://resources/mech/stock/weapon_heat_blade.tres",
			"res://resources/mech/stock/weapon_combat_knife.tres",
			"res://resources/mech/stock/weapon_mace.tres"]:
		var w: WeaponPart = load(weapon_path).duplicate()
		wm.left_hand = w
		await get_tree().process_frame
		var mc = wm._core_for_weapon(w)
		var mc_hits := {"fired": 0}
		var mconn = func():
			mc_hits["fired"] += 1
		mc.fired.connect(mconn)
		_check(w != null and w.ammo_per_shot == 0, "%s authored ammo_per_shot == 0 (ammunition-free by design)" % w.weapon_name)
		wm._set_ammo(w, 0)
		wm._try_fire("left", w)
		_check(mc_hits["fired"] == 1, "%s fires at 0 ammo through its own ammo_per_shot==0 floor" % w.weapon_name)
		_check(wm._get_ammo(w) == 0, "%s consumed no ammo" % w.weapon_name)
		_check(mc != null and mc.cooldown > 0.0, "%s engaged cooldown" % w.weapon_name)
		_check(receipts["loaded"] + receipts["empty"] == bus_total, "%s never touches the pile bunker bus signal" % w.weapon_name)

	EventBus.pile_bunker_fired.disconnect(conn)
	mecha.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All pile_dry_hammer_gate_verify tests passed.")
		get_tree().quit(0)
	else:
		print("pile_dry_hammer_gate_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
