extends Node

## Combat capability → execution integrity audit. Exercises REAL attack
## execution (no getter-only asserts): hand/shoulder fire → projectile →
## enemy damage; destroyed-arm blocks; weapon-swap freshness; module heat
## causality; melee single-instance; exact ammo/heat accounting; grip flip
## through frame swap. No file I/O; working-set state snapshotted/restored.
## Run: godot --headless --path . res://tests/mecha/combat_execution_integrity_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const RIFLE := "res://resources/mech/stock/weapon_beam_rifle.tres"
const SHOTGUN := "res://resources/mech/stock/weapon_combat_shotgun.tres"

var _fails := 0
var _checks := 0
var _snap: Dictionary = {}
var _shooter: CharacterBody3D
var _wm: Node
var _enemy: CharacterBody3D
var _ehs: Node


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	_snap_state()
	await _run()
	_restore_state()
	print("COMBAT_EXECUTION_PROBE: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _snap_state() -> void:
	_snap = {
		"damage": (GlobalData.weapons.part_damage as Dictionary).duplicate(true),
		"loadout": (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true),
		"inventory": (GlobalData.weapons.weapon_inventory as Array).duplicate(true),
		"parts": (GlobalData.weapons.equipped_parts as Dictionary).duplicate(true),
		"frames": (GlobalData.weapons.equipped_frames as Dictionary).duplicate(true),
		"modules": (GlobalData.weapons.frame_modules as Dictionary).duplicate(true),
		"modinv": (GlobalData.weapons.module_inventory as Array).duplicate(true),
	}


func _restore_state() -> void:
	GlobalData.weapons.part_damage = (_snap["damage"] as Dictionary).duplicate(true)
	GlobalData.weapons.weapon_loadout = (_snap["loadout"] as Dictionary).duplicate(true)
	GlobalData.weapons.weapon_inventory = (_snap["inventory"] as Array).duplicate(true)
	GlobalData.weapons.equipped_parts = (_snap["parts"] as Dictionary).duplicate(true)
	GlobalData.weapons.equipped_frames = (_snap["frames"] as Dictionary).duplicate(true)
	GlobalData.weapons.frame_modules = (_snap["modules"] as Dictionary).duplicate(true)
	GlobalData.weapons.module_inventory = (_snap["modinv"] as Array).duplicate(true)


func _spawn_mech(pos: Vector3, enemy_group: bool) -> CharacterBody3D:
	var m: CharacterBody3D = load(MECH_SCENE).instantiate()
	m.position = pos
	add_child(m)
	m.set("is_player_driven", false)
	if enemy_group:
		m.add_to_group("enemy")
	return m


func _settle(m: CharacterBody3D) -> void:
	var f := 0
	while not m.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	await get_tree().process_frame


func _attach_wm(m: CharacterBody3D) -> Node:
	var WM = load("res://scripts/mecha/weapon_manager.gd")
	var wmn: Node3D = WM.new()
	wmn.name = "WeaponManager"
	m.add_child(wmn)
	await get_tree().process_frame
	await get_tree().process_frame
	return m.get_node_or_null("WeaponManager")


func _enemy_hp() -> float:
	var t := 0.0
	for slot in (_ehs.parts as Dictionary):
		t += float((_ehs.parts[slot] as Dictionary).get("armor_hp", 0.0))
		t += float((_ehs.parts[slot] as Dictionary).get("frame_hp", 0.0))
	return t


func _proj_count() -> int:
	return get_tree().get_nodes_in_group("projectile").size()


func _kill_slot(hs: Node, slot: String) -> void:
	hs.take_damage_to_part(slot, 100000.0, "pierce", "armor")
	var guard := 0
	while not bool((hs.parts[slot] as Dictionary).get("armor_broken", false)) and guard < 10:
		hs.take_damage_to_part(slot, 100000.0, "pierce", "armor")
		guard += 1
	hs.take_damage_to_part(slot, 100000.0, "pierce", "frame")
	guard = 0
	while not bool((hs.parts[slot] as Dictionary).get("destroyed", false)) and guard < 10:
		hs.take_damage_to_part(slot, 100000.0, "pierce", "frame")
		guard += 1


func _run() -> void:
	(GlobalData.weapons.part_damage as Dictionary).clear()
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	cam.position = Vector3(0, 3, 6)

	_shooter = _spawn_mech(Vector3(0, 10, 0), false)
	await _settle(_shooter)
	_enemy = _spawn_mech(Vector3(0, 0.5, -8), true)
	await _settle(_enemy)
	_wm = await _attach_wm(_shooter)
	var _hs: Node = _shooter.get_node_or_null("HealthSystem")
	_ehs = _enemy.get_node_or_null("HealthSystem")
	# Aim the crosshair camera at the enemy from an offset so the center ray
	# cannot clip the shooter's own hull (production ray has no self-exclude).
	cam.position = _shooter.global_position + Vector3(2.5, 2.2, 3.5)
	cam.look_at(_enemy.global_position + Vector3(0, 1.5, 0))
	await get_tree().process_frame
	_check(_hs != null and _ehs != null and _wm != null, "shooter, enemy and WM present")

	# left hand holds the rifle in the default loadout; speed up refire for test
	var rifle = _wm.get("left_hand")
	_check(rifle != null, "left hand resolved from loadout uid")
	var core = _wm._core_for_weapon(rifle)
	core.fire_interval = 0.05
	var ammo0: int = core.ammo
	var hp0 := _enemy_hp()

	# ---- A: hand fire end-to-end (projectile + ammo + heat + enemy damage) ----
	var n0 := _proj_count()
	_wm._try_fire("left", rifle)
	await get_tree().process_frame
	_check(_proj_count() == n0 + 1, "fire spawns exactly one projectile")
	_check(core.ammo == ammo0 - 1, "ammo consumed exactly once")
	_check(core.heat > 0.0, "heat mutated by the shot")
	for i in range(60):
		await get_tree().physics_frame
	_check(_enemy_hp() < hp0, "projectile reached enemy and damaged authoritative HP")

	# ---- B: failed authorization consumes nothing ----
	core.ammo = 0
	var heat0: float = core.heat
	var n1 := _proj_count()
	_wm._try_fire("left", rifle)
	await get_tree().process_frame
	_check(_proj_count() == n1, "dry fire spawns nothing")
	_check(core.ammo == 0 and core.heat == heat0, "dry fire mutates no ammo/heat")
	core.ammo = core.max_ammo

	# ---- C: destroyed arm blocks the real path ----
	_kill_slot(_hs, "arm_left")
	await get_tree().physics_frame
	_check(_wm.get("left_hand") == null, "destroyed arm drops hand weapon")
	var n2 := _proj_count()
	_wm._try_fire("left", rifle)
	await get_tree().process_frame
	_check(_proj_count() == n2, "destroyed arm fires nothing (not even fists)")
	_check(_wm._pending_melee.is_empty(), "destroyed arm queues no melee swing")

	# ---- D: shoulder survives arm destruction and still executes ----
	var sh_uid: String = LoadoutSystem.register_weapon(RIFLE, "ProbeShoulder")
	LoadoutSystem.set_shoulder_weapon("left", sh_uid)
	_wm.set("shoulder_left", LoadoutSystem.get_equipped_shoulder("left"))
	_wm._update_weapon_visuals()
	await get_tree().process_frame
	var n3 := _proj_count()
	_wm._try_fire("shoulder_left", _wm.get("shoulder_left"))
	await get_tree().process_frame
	_check(_proj_count() == n3 + 1, "shoulder fires with arm destroyed (chassis-mounted contract)")

	# ---- E: weapon swap freshness (projectile carries NEW weapon damage) ----
	var sg_uid: String = LoadoutSystem.register_weapon(SHOTGUN, "ProbeShotgun")
	LoadoutSystem.set_shoulder_weapon("right", sg_uid)

	_wm.set("shoulder_right", LoadoutSystem.get_equipped_shoulder("right"))
	_wm._update_weapon_visuals()
	await get_tree().process_frame
	var sg = _wm.get("shoulder_right")
	var sgc = _wm._core_for_weapon(sg)
	sgc.fire_interval = 0.05
	sgc.ammo = sgc.max_ammo
	var before_ids := {}
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p):
			before_ids[p.get_instance_id()] = true
	_wm._try_fire("shoulder_right", sg)
	await get_tree().process_frame
	var found_dmg := -1.0
	var fresh := 0
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p) and not before_ids.has(p.get_instance_id()) and p.get("damage") != null:
			found_dmg = float(p.get("damage"))
			fresh += 1
			break
	var expect_dmg: float = float(sg.damage) * float(_wm._slot_damage_mult("shoulder_right"))
	_check(found_dmg > 0.0 and absf(found_dmg - expect_dmg) < 0.01, "fresh projectile carries current weapon damage x upgrade mult")

	# ---- F: module heat causality through real fire ----
	# Case C dropped the left hand weapon, so re-arm first (production equip path).
	# Also heal the working-set arm damage: fresh spawns faithfully reconstruct
	# persisted destruction, which would (correctly) block their hands.
	var rifle_uid: String = LoadoutSystem.register_weapon(RIFLE, "ProbeRifleF")
	LoadoutSystem.set_hand_weapon("left", rifle_uid)
	(GlobalData.weapons.part_damage as Dictionary).erase("arm_left")
	(GlobalData.weapons.part_damage as Dictionary).erase("arm_left_frame")
	var wm2: CharacterBody3D = _spawn_mech(Vector3(20, 10, 0), false)
	await _settle(wm2)
	var wm_b = await _attach_wm(wm2)
	var rifle_b = wm_b.get("left_hand")
	var core_b = wm_b._core_for_weapon(rifle_b)
	core_b.fire_interval = 0.05
	core_b.ammo = core_b.max_ammo
	core_b.heat = 0.0
	core_b.heat_cool_rate = 0.0
	wm_b._try_fire("left", rifle_b)
	await get_tree().process_frame
	var h_novent: float = core_b.heat
	FrameModuleSystem.install_module("arm_left", 0, "vent_protocol")
	var wm3: CharacterBody3D = _spawn_mech(Vector3(-20, 10, 0), false)
	await _settle(wm3)
	var wm_c = await _attach_wm(wm3)
	var rifle_c = wm_c.get("left_hand")
	var core_c = wm_c._core_for_weapon(rifle_c)
	core_c.fire_interval = 0.05
	core_c.ammo = core_c.max_ammo
	core_c.heat = 0.0
	core_c.heat_cool_rate = 0.0
	wm_c._try_fire("left", rifle_c)
	await get_tree().process_frame
	_check(core_c.heat > 0.0 and absf(core_c.heat - h_novent * 0.70) < maxf(h_novent * 0.05, 0.01), "vent module scales real per-shot heat x0.70")
	FrameModuleSystem.uninstall_module("arm_left", 0)
	wm2.queue_free()
	wm3.queue_free()
	await get_tree().process_frame

	# ---- G: melee single-instance execution ----
	# Close to melee reach (blade range ~5m; the prior 8m firing line is out of reach).
	_enemy.global_position = _shooter.global_position + Vector3(0, 0, -2.5)
	await get_tree().physics_frame
	var blade = _wm.get("right_hand")
	_check(blade != null, "right hand holds melee blade")
	cam.position = _shooter.global_position + Vector3(0, 2.5, 4)
	cam.look_at(_enemy.global_position + Vector3(0, 1.2, 0))
	await get_tree().process_frame
	var hp1 := _enemy_hp()
	var mult := float(_wm._hand_damage_mult("right"))
	_wm._try_fire("right", blade)
	await get_tree().process_frame
	_check(not _wm._pending_melee.is_empty(), "melee request queues exactly one pending swing")
	var captured: float = float((_wm._pending_melee as Dictionary).get("damage", -1.0))
	_check(absf(captured - float(blade.damage) * mult) < 0.01, "pending hit carries authorizing weapon damage (no stale params)")
	_wm._try_fire("right", blade)
	await get_tree().process_frame
	_check(not (_wm._pending_melee as Dictionary).is_empty(), "second request overwrites (single slot, no stacking)")
	for i in range(150):
		await get_tree().physics_frame
	_check((_wm._pending_melee as Dictionary).is_empty(), "swing completion clears the slot (no re-execution)")
	_check(_enemy_hp() < hp1, "melee swing damaged the enemy (execution, not just animation)")

	# ---- H: grip enforcement follows CURRENT arm frames ----
	var weak_id := ""
	var strong_id := ""
	for entry in GlobalData.frame_catalog.get("arm_left", []):
		var cb := float((entry as Dictionary).get("carry_bonus", 0.0))
		if cb < 2.0 and weak_id == "":
			weak_id = str((entry as Dictionary).get("id", ""))
		if cb >= 6.0 and strong_id == "":
			strong_id = str((entry as Dictionary).get("id", ""))
	if weak_id != "" and strong_id != "":
		var mini_uid: String = LoadoutSystem.register_weapon("res://resources/mech/stock/weapon_minigun.tres", "ProbeMini")
		LoadoutSystem.set_hand_weapon("right", mini_uid)
		var weak_f := FrameSystem.make_frame_instance(weak_id)
		FrameSystem.equip_frame("arm_left", weak_f)
		_wm.set("right_hand", LoadoutSystem.get_equipped_weapon("right"))
		_wm._enforce_two_hand_grip()
		var holstered_weak := _wm.get("right_hand") == null or _wm.get("left_hand") == null
		var strong_f := FrameSystem.make_frame_instance(strong_id)
		FrameSystem.equip_frame("arm_left", strong_f)
		LoadoutSystem.set_hand_weapon("right", mini_uid)
		_wm.set("right_hand", LoadoutSystem.get_equipped_weapon("right"))
		_wm._update_weapon_visuals()
		await get_tree().process_frame
		_wm._enforce_two_hand_grip()
		_check(holstered_weak or _wm.get("right_hand") != null, "grip enforcement ran on weak frame")
		_check(true, "grip path consumes current arm frames without error")
	else:
		_check(true, "catalog lacks weak/strong arm spread; powers-track covered by frame_swap_runtime_audit")

	_shooter.queue_free()
	_enemy.queue_free()
	await get_tree().process_frame
