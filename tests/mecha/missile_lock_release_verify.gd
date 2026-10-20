extends Node
## MISSILE LOCK RELEASE VERIFY (Gate R2-N2, test-only).
##
## Exercises the production lock -> release -> dumbfire/salvo integration
## path that the direct-call salvo suite does not cover:
##  A. Lock caps respect ammo/magazine and per-target caps.
##  B. Tap release takes the production dumbfire path (single projectile,
##     ammo consumed, no homing salvo).
##  C. Sustained release takes the homing-salvo path (projectiles == locks,
##     ammo delta matches, targets assigned from the lock result).
##  D. cancel_locking clears state without firing or consuming.
##  E. Dead/destroyed targets are pruned per the source contract.
##  F. Mismatched-slot release fires nothing and preserves the live lock.
##  G. Gate-denied release creates nothing and leaves coherent state.
## Lock state is driven programmatically (start/stop/cancel are plain
## methods); no UI hold-to-sweep input is simulated. Recoil-frequency intent
## and freed-mid-salvo target policy remain undecided and unasserted.
## Run: godot --headless --path . res://tests/mecha/missile_lock_release_verify.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const MISSILE_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"

var _fails := 0
var _checks := 0
# Per-case completion flags: a case counts as complete only when its body
# reaches its normal end. If a coroutine dies on a runtime error, its flag
# stays false and the missing completion is recorded as a failure below
# instead of silently passing with a clean exit code.
var _completed := {}


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LOCK-RELEASE OK: " + name)
	else:
		_fails += 1
		printerr("LOCK-RELEASE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_lock_caps()
	await _test_tap_release_dumbfire()
	await _test_sustained_release_salvo()
	await _test_cancel_clears()
	await _test_dead_target_pruning()
	await _test_mismatched_slot_release()
	await _test_gate_denied_release()
	for case_name in ["caps", "tap", "sustained", "cancel", "prune", "mismatch", "denied"]:
		_check(bool(_completed.get(case_name, false)), "case completed: " + case_name)
	print("MISSILE_LOCK_RELEASE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MISSILE_LOCK_RELEASE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MISSILE_LOCK_RELEASE_TESTS_PASSED")
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
	var lock_sys = wm.missile_lock_system
	return [mecha, wm, cam, targets, lock_sys]


func _proj_count() -> int:
	return get_tree().get_nodes_in_group("projectile").size()


func _wait_for_proj_count(want_total: int, max_frames: int) -> bool:
	var f := 0
	while get_tree().get_nodes_in_group("projectile").size() < want_total and f < max_frames:
		await get_tree().physics_frame
		f += 1
	return get_tree().get_nodes_in_group("projectile").size() >= want_total


# ---------------------------------------------------------------------------
# A. Lock caps respect ammo, magazine, and per-target caps.
# ---------------------------------------------------------------------------
func _test_lock_caps() -> void:
	var rig := await _spawn_rig(0)
	var wm: Node3D = rig[1]
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	var mag: int = missile.max_ammo
	_check(mag > 0, "caps: missile has a magazine size")
	lock_sys.start_locking("right", missile, 2)
	_check(lock_sys.is_locking, "caps: locking active after start")
	_check(lock_sys.active_slot == "right", "caps: active slot recorded")
	_check(lock_sys.max_total_locks == mini(2, mag), "caps: total capped by ammo")
	_check(lock_sys.max_locks_per_target == mag, "caps: per-target cap equals magazine")
	lock_sys.cancel_locking()
	_check(not lock_sys.is_locking, "caps: cancel ends locking")
	_completed["caps"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# B. Tap release takes the production dumbfire path.
# ---------------------------------------------------------------------------
func _test_tap_release_dumbfire() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[3]
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	wm.right_hand = missile
	_mount_for_slot(wm, "right", missile)
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.05
	var core = wm._core_for_weapon(missile)
	core.ammo = core.max_ammo
	core.cooldown = 0.0
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	_check(await _wait_for_proj_count(before + 1, 120), "tap: exactly one dumbfire projectile launches")
	_check(get_tree().get_nodes_in_group("projectile").size() == before + 1, "tap: no homing salvo follows the tap")
	_check(core.ammo < ammo0, "tap: ammunition consumed")
	_check(not lock_sys.is_locking, "tap: lock state cleared by release")
	_completed["tap"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# C. Sustained release takes the homing-salvo path.
# ---------------------------------------------------------------------------
func _test_sustained_release_salvo() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[3]
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	wm.right_hand = missile
	_mount_for_slot(wm, "right", missile)
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.locked_targets[targets[1]] = 1
	lock_sys.hold_duration = 1.0
	var core = wm._core_for_weapon(missile)
	core.ammo = core.max_ammo
	core.cooldown = 0.0
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	_check(await _wait_for_proj_count(before + 2, 240), "sustained: two projectiles launch for two locks")
	_check(get_tree().get_nodes_in_group("projectile").size() == before + 2, "sustained: no extra projectiles beyond locks")
	_check(core.ammo == ammo0 - 2, "sustained: ammo matches lock count")
	_check(not lock_sys.is_locking, "sustained: lock state cleared by release")
	_completed["sustained"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# D. Cancellation clears without firing or consuming.
# ---------------------------------------------------------------------------
func _test_cancel_clears() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[3]
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	wm.right_hand = missile
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 1.0
	var core = wm._core_for_weapon(missile)
	core.ammo = core.max_ammo
	var ammo0: int = core.ammo
	var before := _proj_count()
	lock_sys.cancel_locking()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not lock_sys.is_locking, "cancel: locking inactive")
	_check(lock_sys.get_total_locks() == 0, "cancel: lock count cleared")
	_check(lock_sys.active_slot == "", "cancel: active slot cleared")
	_check(get_tree().get_nodes_in_group("projectile").size() == before, "cancel: creates no projectile")
	_check(core.ammo == ammo0, "cancel: consumes no ammunition")
	_completed["cancel"] = true
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# E. Dead/destroyed targets are pruned per the source contract.
# ---------------------------------------------------------------------------
func _test_dead_target_pruning() -> void:
	var rig := await _spawn_rig(1)
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	var live: Node3D = rig[3][0]
	var dead := Node3D.new()
	add_child(dead)
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[live] = 1
	lock_sys.locked_targets[dead] = 1
	dead.queue_free()
	for i in range(10):
		await get_tree().physics_frame
	_check(not lock_sys.locked_targets.has(dead), "prune: freed target removed from locks")
	_check(lock_sys.locked_targets.get(live, 0) == 1, "prune: live target retained")
	_completed["prune"] = true
	lock_sys.cancel_locking()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# F. Mismatched-slot release fires nothing and preserves the live lock.
# ---------------------------------------------------------------------------
func _test_mismatched_slot_release() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[3]
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	wm.right_hand = missile
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var before := _proj_count()
	wm._handle_missile_release("left")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("projectile").size() == before, "mismatch: no projectile from the wrong slot")
	_check(lock_sys.is_locking, "mismatch: live lock survives")
	_check(lock_sys.active_slot == "right", "mismatch: active slot unchanged")
	_check(lock_sys.get_total_locks() == 1, "mismatch: lock count preserved")
	_completed["mismatch"] = true
	lock_sys.cancel_locking()
	(rig[0] as Node).queue_free()


# ---------------------------------------------------------------------------
# G. Gate-denied release creates nothing and stays coherent.
# ---------------------------------------------------------------------------
func _test_gate_denied_release() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[3]
	var lock_sys = rig[4]
	var missile: WeaponPart = load(MISSILE_PATH)
	# Slot deliberately left unarmed: the gate reads the slot, not the argument.
	lock_sys.start_locking("right", missile, 5)
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 1.0
	var core = wm._core_for_weapon(missile)
	core.ammo = core.max_ammo
	var ammo0: int = core.ammo
	var before := _proj_count()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("projectile").size() == before, "denied: no projectile created")
	_check(core.ammo == ammo0, "denied: no ammunition consumed")
	_check(not lock_sys.is_locking, "denied: no stale lock residue (stop_locking cleared)")
	_completed["denied"] = true
	(rig[0] as Node).queue_free()


func _mount_for_slot(wm: Node3D, slot: String, weapon: WeaponPart) -> void:
	var mecha: Node3D = wm.get_parent() as Node3D
	if slot.begins_with("shoulder"):
		var side := "left" if slot == "shoulder_left" else "right"
		wm._update_shoulder_weapon_visual(mecha, side, weapon)
	else:
		wm._update_hand_weapon_visual(mecha, slot, weapon)
