extends Node
## MISSILE SALVO EXECUTION VERIFY (Gate R2-L, test-only).
##
## Exercises the live `_fire_missile_salvo` call chain for multi-missile
## behavior that the single-target routing suite does not cover:
##  A. Two-target salvo: exactly two launches, ammo -2, no extras.
##  B. Three-target salvo: exactly three launches in queue order, ammo -3.
##  C. Partial salvo: one round vs three locks -> exactly one launch, ammo
##     floors at zero, no further launches.
##  D. Gate-denied salvo: unarmed slot -> zero launches, zero ammo change.
## Recoil-frequency intent is unresolved: no assertion constrains per-missile
## vs per-salvo recoil. Durability is not asserted (bare fixtures lack the
## loadout-uid inventory linkage the implementation resolves through).
## Fixture: full production mech + real WeaponManager + camera + ground +
## dummy targets; live salvo calls only; gate never bypassed.
## Run: godot --headless --path . res://test/unit/missile_salvo_execution_verify.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const MISSILE_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"
const SWARM_MISSILE_PATH := "res://resources/mech/stock/weapon_swarm_missile.tres"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SALVO-EXEC OK: " + name)
	else:
		_fails += 1
		printerr("SALVO-EXEC FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_two_target_salvo()
	await _test_three_target_salvo()
	await _test_partial_salvo()
	await _test_gate_denied_salvo()
	await _test_swarm_salvo_pricing()
	await _test_shoulder_salvo_execution()
	await _test_shoulder_gate_denied_salvo()
	print("MISSILE_SALVO_EXECUTION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MISSILE_SALVO_EXECUTION_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MISSILE_SALVO_EXECUTION_TESTS_PASSED")
		get_tree().quit(0)


func _spawn_rig(target_count: int) -> Array:
	var mecha: CharacterBody3D = (load(MECH_SCENE) as PackedScene).instantiate()
	mecha.position = Vector3(0, 1.5, 0)
	add_child(mecha)
	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	var targets: Array = []
	for i in range(target_count):
		var t := Node3D.new()
		t.position = Vector3(-4.0 + float(i) * 4.0, 1.5, -20.0)
		add_child(t)
		targets.append(t)
	await get_tree().process_frame
	return [mecha, wm, targets]


func _proj_count() -> int:
	return get_tree().get_nodes_in_group("projectile").size()


func _new_projectiles(before: Array) -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("projectile"):
		if not before.has(n):
			out.append(n)
	return out


func _wait_for_proj_count(want_total: int, max_frames: int) -> bool:
	var f := 0
	while get_tree().get_nodes_in_group("projectile").size() < want_total and f < max_frames:
		await get_tree().physics_frame
		f += 1
	return get_tree().get_nodes_in_group("projectile").size() >= want_total


func _mount_for_slot(wm: Node3D, slot: String, weapon: WeaponPart) -> void:
	var mecha: Node3D = wm.get_parent() as Node3D
	if slot.begins_with("shoulder"):
		var side := "left" if slot == "shoulder_left" else "right"
		wm._update_shoulder_weapon_visual(mecha, side, weapon)
	else:
		wm._update_hand_weapon_visual(mecha, slot, weapon)


func _prep_salvo(wm: Node3D, slot: String, weapon: WeaponPart, ammo: int) -> void:
	# Arm the authoritative slot with the exact instance under test, mount
	# visuals through the production path, and set deterministic ammo.
	if slot == "left" or slot == "right":
		if slot == "left":
			wm.left_hand = weapon
		else:
			wm.right_hand = weapon
	else:
		if slot == "shoulder_left":
			wm.shoulder_left = weapon
		else:
			wm.shoulder_right = weapon
	_mount_for_slot(wm, slot, weapon)
	var core = wm._core_for_weapon(weapon)
	core.ammo = ammo
	core.cooldown = 0.0


func _targets_dict(targets: Array) -> Dictionary:
	var d := {}
	for t in targets:
		d[t] = 1
	return d


func _test_two_target_salvo() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var ammo0: int = core.ammo
	var before_list := get_tree().get_nodes_in_group("projectile")
	var proj0 := before_list.size()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	_check(await _wait_for_proj_count(proj0 + 2, 240), "two-target salvo launches exactly two projectiles")
	var fresh := _new_projectiles(before_list)
	_check(fresh.size() >= 2, "two new projectiles observed")
	_check(core.ammo == ammo0 - 2, "two-target salvo consumes two rounds (%d -> %d)" % [ammo0, core.ammo])
	_check(core.ammo >= 0, "ammunition never negative")
	await get_tree().create_timer(0.5).timeout
	_check(get_tree().get_nodes_in_group("projectile").size() == proj0 + 2, "no extra projectiles after salvo completes")
	(rig[0] as Node).queue_free()


func _test_three_target_salvo() -> void:
	var rig := await _spawn_rig(3)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 5)
	var core = wm._core_for_weapon(missile)
	var ammo0: int = core.ammo
	var before := get_tree().get_nodes_in_group("projectile")
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	_check(await _wait_for_proj_count(before.size() + 3, 300), "three-target salvo launches exactly three projectiles")
	var fresh := _new_projectiles(before)
	_check(fresh.size() == 3, "three new projectiles observed in order")
	if fresh.size() == 3:
		var aimed := true
		for k in range(3):
			if (fresh[k] as Node).get("target_node") != targets[k]:
				aimed = false
		_check(aimed, "launches follow queue order across the three targets")
	_check(core.ammo == ammo0 - 3, "three-target salvo consumes three rounds")
	(rig[0] as Node).queue_free()


func _test_partial_salvo() -> void:
	var rig := await _spawn_rig(3)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "right", missile, 1)
	var core = wm._core_for_weapon(missile)
	var before := get_tree().get_nodes_in_group("projectile").size()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	_check(await _wait_for_proj_count(before + 1, 240), "partial salvo launches exactly one projectile")
	await get_tree().create_timer(0.5).timeout
	_check(get_tree().get_nodes_in_group("projectile").size() == before + 1, "no further launches once ammunition is spent")
	_check(core.ammo == 0, "ammunition floors at zero (got %d)" % core.ammo)
	(rig[0] as Node).queue_free()


func _test_gate_denied_salvo() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	# Slot deliberately left unarmed: the gate reads the slot, not the argument.
	var core = wm._core_for_weapon(missile)
	core.ammo = core.max_ammo
	var ammo0: int = core.ammo
	var before := get_tree().get_nodes_in_group("projectile").size()
	wm._fire_missile_salvo("right", missile, _targets_dict(targets))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("projectile").size() == before, "gate-denied salvo creates no projectile")
	_check(core.ammo == ammo0, "gate-denied salvo consumes no ammunition")
	(rig[0] as Node).queue_free()


func _test_swarm_salvo_pricing() -> void:
	var rig := await _spawn_rig(3)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var swarm: WeaponPart = load(SWARM_MISSILE_PATH)
	_check(swarm != null and swarm.weapon_name == "Swarm Missile", "swarm: real Swarm Missile resource loaded")
	_check(swarm.ammo_per_shot == 3, "swarm: resource defines ammo_per_shot = 3 (volley pricing)")
	_prep_salvo(wm, "right", swarm, 15)
	var core = wm._core_for_weapon(swarm)
	_check(core.ammo_per_shot == 3, "swarm: core.ammo_per_shot equals 3 before firing")
	var ammo0: int = core.ammo
	var before := get_tree().get_nodes_in_group("projectile")
	wm._fire_missile_salvo("right", swarm, _targets_dict(targets))
	_check(await _wait_for_proj_count(before.size() + 3, 300), "swarm: three-target salvo launches three projectiles")
	var fresh := _new_projectiles(before)
	_check(fresh.size() == 3, "swarm: three new projectiles observed")
	_check(core.ammo == ammo0 - 3, "swarm: salvo consumes 1 ammo per missile (15 -> 12), not 3 per missile (15 -> 6)")
	_check(core.ammo_per_shot == 3, "swarm: core.ammo_per_shot restored to original value 3 after salvo")
	_check(core.ammo >= 0, "swarm: ammunition never negative")
	(rig[0] as Node).queue_free()


func _test_shoulder_salvo_execution() -> void:
	var rig := await _spawn_rig(2)
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	_prep_salvo(wm, "shoulder_right", missile, 5)
	_check(wm.shoulder_right == missile, "shoulder: missile mounted in shoulder_right slot")
	var core = wm._core_for_weapon(missile)
	var ammo0: int = core.ammo

	var expected_spawn: Vector3 = wm._get_shoulder_muzzle_world_pos("right")
	if expected_spawn == Vector3.INF:
		expected_spawn = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.shoulder_fallback_for(mecha, "right")
	_check(expected_spawn != Vector3.INF and is_finite(expected_spawn.y), "shoulder: expected shoulder spawn position resolved")

	var shoulder_signals: Array = []
	var on_shoulder_ammo := func(side: String, cur_ammo: int, max_ammo: int) -> void:
		shoulder_signals.append({"side": side, "ammo": cur_ammo, "max": max_ammo})
	wm.shoulder_ammo_changed.connect(on_shoulder_ammo)

	var before := get_tree().get_nodes_in_group("projectile")
	wm._fire_missile_salvo("shoulder_right", missile, _targets_dict(targets))
	_check(await _wait_for_proj_count(before.size() + 2, 240), "shoulder: two-target salvo launches two projectiles from shoulder")
	var fresh := _new_projectiles(before)
	_check(fresh.size() >= 2, "shoulder: two new projectiles observed")

	var first_proj: Node3D = fresh[0] as Node3D
	var y_diff: float = absf(first_proj.global_position.y - expected_spawn.y)
	_check(y_diff < 1.0, "shoulder: projectile Y origin (%.2f) consistent with shoulder muzzle (%.2f, diff=%.2f < 1.0m)" % [first_proj.global_position.y, expected_spawn.y, y_diff])

	_check(not shoulder_signals.is_empty(), "shoulder: shoulder_ammo_changed observed during salvo")
	var all_right := true
	for sig in shoulder_signals:
		if sig.get("side") != "right":
			all_right = false
	_check(all_right, "shoulder: all emitted signals report side 'right'")
	_check(shoulder_signals.back()["ammo"] == ammo0 - 2, "shoulder: final signal reports decremented ammo (%d -> %d)" % [ammo0, shoulder_signals.back()["ammo"]])

	_check(core.ammo == ammo0 - 2, "shoulder: core ammo decremented by two (5 -> 3)")
	_check(core.ammo >= 0, "shoulder: ammo never negative")

	wm.shoulder_ammo_changed.disconnect(on_shoulder_ammo)
	(rig[0] as Node).queue_free()


func _test_shoulder_gate_denied_salvo() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var missile: WeaponPart = load(MISSILE_PATH)
	var core = wm._core_for_weapon(missile)
	core.ammo = core.max_ammo
	var ammo0: int = core.ammo
	var before := get_tree().get_nodes_in_group("projectile").size()
	wm._fire_missile_salvo("shoulder_right", missile, _targets_dict(targets))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("projectile").size() == before, "shoulder-denied: unarmed shoulder salvo creates no projectile")
	_check(core.ammo == ammo0, "shoulder-denied: unarmed shoulder salvo consumes no ammunition")
	(rig[0] as Node).queue_free()
