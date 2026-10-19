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
## Run: godot --headless --path . res://test/unit/missile_lock_release_verify.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const MISSILE_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"
const PROJ_SCRIPT = preload("res://scripts/systems/projectile.gd")

var _fails := 0
var _checks := 0
# Per-case completion flags: a case counts as complete only when its body
# reaches its normal end. If a coroutine dies on a runtime error, its flag
# stays false and the missing completion is recorded as a failure below
# instead of silently passing with a clean exit code.
var _completed := {}

# Event-driven tracking: records projectile instances synchronously as they
# enter the SceneTree, avoiding the polling blind spot for short-lived projectiles.
var _tracked_test_projectiles: Array = []


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LOCK-RELEASE OK: " + name)
	else:
		_fails += 1
		printerr("LOCK-RELEASE FAIL: " + name)


func _on_node_added(node: Node) -> void:
	if node is CharacterBody3D and node.get_script() == PROJ_SCRIPT:
		if not _tracked_test_projectiles.has(node):
			_tracked_test_projectiles.append(node)


func _ready() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
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
	if get_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _fails > 0:
		printerr("MISSILE_LOCK_RELEASE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MISSILE_LOCK_RELEASE_TESTS_PASSED")
		get_tree().quit(0)


func _exit_tree() -> void:
	if get_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


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


func _wait_for_captured_projectiles(before_count: int, want_new: int, max_frames: int) -> void:
	var f := 0
	while (_tracked_test_projectiles.size() - before_count) < want_new and f < max_frames:
		await get_tree().physics_frame
		f += 1


func _observe_settled_captured_projectiles(before_count: int, want_new: int, max_frames: int, settle_seconds: float = 0.15) -> Array:
	await _wait_for_captured_projectiles(before_count, want_new, max_frames)
	var timer := get_tree().create_timer(settle_seconds)
	while timer.time_left > 0.0:
		await get_tree().physics_frame
	var out: Array = []
	for i in range(before_count, _tracked_test_projectiles.size()):
		out.append(_tracked_test_projectiles[i])
	return out


func _captured_since(before_count: int) -> Array:
	var out: Array = []
	for i in range(before_count, _tracked_test_projectiles.size()):
		out.append(_tracked_test_projectiles[i])
	return out


func _cleanup_rig(rig: Array) -> void:
	if rig.size() > 0 and is_instance_valid(rig[0]):
		(rig[0] as Node).queue_free()
	for p in _tracked_test_projectiles:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			p.queue_free()
	_tracked_test_projectiles.clear()


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
	_cleanup_rig(rig)


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
	var before_count := _tracked_test_projectiles.size()
	wm._handle_missile_release("right")
	var spawned := await _observe_settled_captured_projectiles(before_count, 1, 120, 0.15)
	_check(spawned.size() == 1, "tap: exactly one dumbfire projectile launches")
	var is_dumbfire: bool = spawned.size() >= 1 and is_instance_valid(spawned[0]) and (spawned[0] as Node).get("target_node") == null
	_check(is_dumbfire, "tap: no homing salvo follows the tap")
	_check(core.ammo < ammo0, "tap: ammunition consumed")
	_check(not lock_sys.is_locking, "tap: lock state cleared by release")
	_completed["tap"] = true
	_cleanup_rig(rig)


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
	var before_count := _tracked_test_projectiles.size()
	wm._handle_missile_release("right")
	var spawned := await _observe_settled_captured_projectiles(before_count, 2, 240, 0.15)
	_check(spawned.size() == 2, "sustained: two projectiles launch for two locks")
	var targets_ok: bool = (
		spawned.size() == 2
		and is_instance_valid(spawned[0])
		and is_instance_valid(spawned[1])
		and (
			((spawned[0] as Node).get("target_node") == targets[0] and (spawned[1] as Node).get("target_node") == targets[1])
			or ((spawned[0] as Node).get("target_node") == targets[1] and (spawned[1] as Node).get("target_node") == targets[0])
		)
	)
	_check(targets_ok, "sustained: no extra projectiles beyond locks")
	_check(core.ammo == ammo0 - 2, "sustained: ammo matches lock count")
	_check(not lock_sys.is_locking, "sustained: lock state cleared by release")
	_completed["sustained"] = true
	_cleanup_rig(rig)


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
	var before_count := _tracked_test_projectiles.size()
	lock_sys.cancel_locking()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not lock_sys.is_locking, "cancel: locking inactive")
	_check(lock_sys.get_total_locks() == 0, "cancel: lock count cleared")
	_check(lock_sys.active_slot == "", "cancel: active slot cleared")
	_check(_captured_since(before_count).is_empty(), "cancel: creates no projectile")
	_check(core.ammo == ammo0, "cancel: consumes no ammunition")
	_completed["cancel"] = true
	_cleanup_rig(rig)


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
	_cleanup_rig(rig)


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
	var before_count := _tracked_test_projectiles.size()
	wm._handle_missile_release("left")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_captured_since(before_count).is_empty(), "mismatch: no projectile from the wrong slot")
	_check(lock_sys.is_locking, "mismatch: live lock survives")
	_check(lock_sys.active_slot == "right", "mismatch: active slot unchanged")
	_check(lock_sys.get_total_locks() == 1, "mismatch: lock count preserved")
	_completed["mismatch"] = true
	lock_sys.cancel_locking()
	_cleanup_rig(rig)


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
	var before_count := _tracked_test_projectiles.size()
	wm._handle_missile_release("right")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_captured_since(before_count).is_empty(), "denied: no projectile created")
	_check(core.ammo == ammo0, "denied: no ammunition consumed")
	_check(not lock_sys.is_locking, "denied: no stale lock residue (stop_locking cleared)")
	_completed["denied"] = true
	_cleanup_rig(rig)


func _mount_for_slot(wm: Node3D, slot: String, weapon: WeaponPart) -> void:
	var mecha: Node3D = wm.get_parent() as Node3D
	if slot.begins_with("shoulder"):
		var side := "left" if slot == "shoulder_left" else "right"
		wm._update_shoulder_weapon_visual(mecha, side, weapon)
	else:
		wm._update_hand_weapon_visual(mecha, slot, weapon)

