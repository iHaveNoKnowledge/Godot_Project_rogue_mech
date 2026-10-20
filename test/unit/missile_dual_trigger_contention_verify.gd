extends Node
## MISSILE DUAL TRIGGER CONTENTION VERIFY (Phase R2-CE, Option A implementation).
##
## Verifies the approved gameplay policy:
## When one missile slot is actively locking, pressing another missile slot
## immediately fires one dumbfire missile from the secondary slot without
## interrupting, overwriting, resetting, or cancelling the existing lock session.
##
## Minimum test requirements covered:
##  1. Single-slot control (single-trigger lock and release)
##  2. Secondary trigger fallback (fires 1 dumbfire, primary state preserved)
##  3. Release order A then B (primary fires salvo, secondary release inert)
##  4. Release order B then A (secondary release inert, primary fires salvo)
##  5. Failed secondary fire (empty ammo, reload, cooldown, arm destroyed, gate denial)
##  6. No accidental lock restart (repeated press on active slot does not reset)
##  7. Slot routing hand-to-shoulder (shoulder dumbfire fallback from shoulder muzzle)
##  8. Slot routing shoulder-to-hand (hand dumbfire fallback from hand muzzle)
##  9. Normal missile tap dumbfire release (tap release produces 1 dumbfire)
## 10. Action handler path integration (canonical _handle_missile_press/release dispatch)
##
## Run: cmd /c "h:\hack\project\godot\Godot_v4.6.2-stable_win64.exe --headless test/unit/missile_dual_trigger_contention_verify.tscn"

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const HEAVY_MISSILE_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"
const STD_MISSILE_PATH := "res://resources/mech/stock/weapon_missile.tres"

var _fails := 0
var _checks := 0
var _completed := {}


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CONTENTION OK: " + name)
	else:
		_fails += 1
		printerr("CONTENTION FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame

	await _test_single_trigger_control()
	await _test_secondary_trigger_fallback_and_primary_preserved()
	await _test_release_order_a_then_b()
	await _test_release_order_b_then_a()
	await _test_failed_secondary_fire_preserves_primary()
	await _test_no_accidental_lock_restart()
	await _test_slot_routing_hand_to_shoulder()
	await _test_slot_routing_shoulder_to_hand()
	await _test_normal_tap_dumbfire_release()
	await _test_input_event_integration()

	for case_name in [
		"single_control",
		"fallback_and_preserved",
		"release_a_then_b",
		"release_b_then_a",
		"failed_secondary_fire",
		"no_accidental_restart",
		"routing_hand_to_shoulder",
		"routing_shoulder_to_hand",
		"normal_tap_dumbfire",
		"input_event_integration"
	]:
		_check(bool(_completed.get(case_name, false)), "case completed: " + case_name)

	print("MISSILE_DUAL_TRIGGER_CONTENTION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MISSILE_DUAL_TRIGGER_CONTENTION_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MISSILE_DUAL_TRIGGER_CONTENTION_TESTS_PASSED")
		get_tree().quit(0)


# ---------------------------------------------------------------------------
# Rig Management & Test Helpers
# ---------------------------------------------------------------------------

func _spawn_rig(target_count: int = 2) -> Array:
	var mecha: CharacterBody3D = (load(MECH_SCENE) as PackedScene).instantiate()
	mecha.position = Vector3(0, 1.5, 0)
	add_child(mecha)

	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)

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
		t.add_to_group("enemy")
		add_child(t)
		targets.append(t)

	await get_tree().process_frame
	return [mecha, wm, targets]


func _cleanup_rig(rig: Array) -> void:
	if rig.size() >= 1 and is_instance_valid(rig[0]):
		(rig[0] as Node).queue_free()
	if rig.size() >= 3 and rig[2] is Array:
		for t in rig[2]:
			if is_instance_valid(t):
				(t as Node).queue_free()
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p):
			p.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _mount_weapon(wm: Node3D, slot: String, weapon: WeaponPart, ammo: int) -> void:
	var mecha: Node3D = wm.get_parent() as Node3D
	if slot == "left":
		wm.left_hand = weapon
		wm._update_hand_weapon_visual(mecha, "left", weapon)
	elif slot == "right":
		wm.right_hand = weapon
		wm._update_hand_weapon_visual(mecha, "right", weapon)
	elif slot == "shoulder_left":
		wm.shoulder_left = weapon
		wm._update_shoulder_weapon_visual(mecha, "left", weapon)
	elif slot == "shoulder_right":
		wm.shoulder_right = weapon
		wm._update_shoulder_weapon_visual(mecha, "right", weapon)

	var core = wm._core_for_weapon(weapon)
	if core:
		core.ammo = ammo
		core.cooldown = 0.0


func _wait_for_proj_count(want_total: int, max_frames: int = 120) -> bool:
	var f := 0
	while get_tree().get_nodes_in_group("projectile").size() < want_total and f < max_frames:
		await get_tree().physics_frame
		f += 1
	return get_tree().get_nodes_in_group("projectile").size() >= want_total


# ---------------------------------------------------------------------------
# 1. Single-Slot Control: Standard Lock & Salvo Release
# ---------------------------------------------------------------------------

func _test_single_trigger_control() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system
	var missile: WeaponPart = load(HEAVY_MISSILE_PATH)

	_mount_weapon(wm, "left", missile, 5)
	var core = wm._core_for_weapon(missile)

	# Single trigger press routes through production _handle_missile_press
	wm._handle_missile_press("left", missile)
	_check(lock_sys.is_locking, "single: lock_sys is_locking active")
	_check(lock_sys.active_slot == "left", "single: active_slot is 'left'")
	_check(lock_sys.locking_weapon == missile, "single: locking_weapon is left missile")

	# Accumulate 1 lock on target
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 0.5

	var before_count := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_release("left")

	var ok := await _wait_for_proj_count(before_count + 1)
	_check(ok, "single: exactly 1 salvo projectile launched")
	_check(core.ammo == 4, "single: left ammo decremented by 1 (5 -> 4)")
	_check(not lock_sys.is_locking, "single: lock_sys returned to idle")
	_check(lock_sys.locked_targets.is_empty(), "single: locked_targets cleared after release")

	_completed["single_control"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 2. Secondary Trigger Fallback & Primary State Preserved
# ---------------------------------------------------------------------------

func _test_secondary_trigger_fallback_and_primary_preserved() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH) # max_ammo 5
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)   # max_ammo 8

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Step A: Primary trigger (left) establishes active lock session
	wm._handle_missile_press("left", left_missile)
	_check(lock_sys.is_locking, "fallback: left trigger establishes session")
	_check(lock_sys.active_slot == "left", "fallback: active_slot is 'left'")

	# Primary accumulates 2 locks
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.target_lock_progress[targets[0]] = 0.08
	lock_sys.hold_duration = 0.40

	var before_projs := get_tree().get_nodes_in_group("projectile").size()

	# Step B: Secondary trigger (right) pressed while left is locking
	wm._handle_missile_press("right", right_missile)

	var ok := await _wait_for_proj_count(before_projs + 1)
	_check(ok, "fallback: pressing secondary slot immediately launches exactly 1 projectile")
	_check(core_right.ammo == 7, "fallback: secondary weapon ammo decremented (8 -> 7)")
	_check(core_left.ammo == 5, "fallback: primary weapon ammo untouched (5/5)")

	# Verify dumbfire nature of the secondary projectile (target_node == null)
	var fresh_projs: Array = []
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p):
			fresh_projs.append(p)
	var last_proj: Node3D = fresh_projs.back() as Node3D
	_check(last_proj != null and last_proj.get("target_node") == null, "fallback: secondary projectile is unguided dumbfire")

	# Step C: Verify primary session state is completely preserved
	_check(lock_sys.is_locking, "fallback: primary session is_locking remains true")
	_check(lock_sys.active_slot == "left", "fallback: active_slot remains 'left' (NOT overwritten)")
	_check(lock_sys.locking_weapon == left_missile, "fallback: locking_weapon remains left_missile")
	_check(lock_sys.hold_duration == 0.40, "fallback: hold_duration preserved at 0.40s")
	_check(int(lock_sys.locked_targets.get(targets[0], 0)) == 2, "fallback: locked_targets preserved (2 locks on target 0)")
	_check(float(lock_sys.target_lock_progress.get(targets[0], 0.0)) == 0.08, "fallback: target_lock_progress preserved")
	_check(lock_sys.max_total_locks == 5, "fallback: max_total_locks preserved at left pod cap 5")

	_completed["fallback_and_preserved"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 3. Contention Release Order: Release Primary (A), Then Secondary (B)
# ---------------------------------------------------------------------------

func _test_release_order_a_then_b() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	# Secondary pressed -> dumbfire fires 1 round
	var count0 := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_press("right", right_missile)
	await _wait_for_proj_count(count0 + 1)
	_check(core_right.ammo == 7, "rel_ab: right dumbfire decrements ammo (8 -> 7)")

	# Action 1: Release primary trigger (left)
	var count1 := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_release("left")

	# Wait for 2 salvo projectiles from left hand
	var ok := await _wait_for_proj_count(count1 + 2)
	_check(ok, "rel_ab: releasing primary launches full 2-projectile salvo")
	_check(core_left.ammo == 3, "rel_ab: left hand ammo decremented by 2 (5 -> 3)")
	_check(core_right.ammo == 7, "rel_ab: right hand ammo unchanged (7)")
	_check(not lock_sys.is_locking, "rel_ab: lock_sys returned to idle")

	# Action 2: Release secondary trigger (right)
	var count2 := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_release("right")

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == count2, "rel_ab: secondary release launches ZERO additional projectiles")
	_check(core_right.ammo == 7, "rel_ab: right ammo remains 7")
	_check(not lock_sys.is_locking, "rel_ab: lock_sys remains idle")

	_completed["release_a_then_b"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 4. Contention Release Order: Release Secondary (B) First, Then Primary (A)
# ---------------------------------------------------------------------------

func _test_release_order_b_then_a() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	# Secondary pressed -> dumbfire fires 1 round
	var count0 := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_press("right", right_missile)
	await _wait_for_proj_count(count0 + 1)
	_check(core_right.ammo == 7, "rel_ba: right dumbfire fired 1 projectile")

	# Action 1: Release secondary trigger FIRST (right)
	var count1 := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_release("right")

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == count1, "rel_ba: early secondary release launches ZERO projectiles")
	_check(core_right.ammo == 7, "rel_ba: secondary ammo remains 7")
	_check(lock_sys.is_locking, "rel_ba: primary session still actively locking")
	_check(lock_sys.active_slot == "left", "rel_ba: primary active_slot still 'left'")
	_check(int(lock_sys.locked_targets.get(targets[0], 0)) == 2, "rel_ba: 2 locks preserved on target 0")

	# Action 2: Release primary trigger SECOND (left)
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(count1 + 2)
	_check(ok, "rel_ba: late primary release fires full 2-projectile salvo")
	_check(core_left.ammo == 3, "rel_ba: left ammo decremented by 2 (5 -> 3)")
	_check(not lock_sys.is_locking, "rel_ba: lock_sys returned to idle")

	_completed["release_b_then_a"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 5. Failed Secondary Fire Rejection Paths Preserve Primary Lock Session
# ---------------------------------------------------------------------------

func _test_failed_secondary_fire_preserves_primary() -> void:
	# Sub-case A: Empty Ammo (Dry-Fire)
	await _subtest_secondary_rejection_empty_ammo()

	# Sub-case B: Active Reload (C1)
	await _subtest_secondary_rejection_active_reload()

	# Sub-case C: Active Cooldown (C2)
	await _subtest_secondary_rejection_active_cooldown()

	# Sub-case D: Destroyed Secondary Arm (C3)
	await _subtest_secondary_rejection_destroyed_arm()

	# Sub-case E: Structural Capability Denial (C4)
	await _subtest_secondary_rejection_capability_denial()

	_completed["failed_secondary_fire"] = true


func _subtest_secondary_rejection_empty_ammo() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 0) # empty secondary magazine
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)
	_check(core_right.ammo == 0, "rej_empty: secondary ammo is 0")

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	var snap_targets: Dictionary = lock_sys.locked_targets.duplicate()
	var snap_progress: Dictionary = lock_sys.target_lock_progress.duplicate()
	var snap_hold: float = lock_sys.hold_duration
	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Secondary press with 0 ammo
	wm._handle_missile_press("right", right_missile)

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == before_count, "rej_empty: empty secondary launches ZERO projectiles")
	_check(core_right.ammo == 0, "rej_empty: secondary ammo remains 0")
	_check(lock_sys.is_locking, "rej_empty: primary session unaffected by secondary dry fire")
	_check(lock_sys.active_slot == "left", "rej_empty: active_slot still 'left'")
	_check(lock_sys.locked_targets == snap_targets, "rej_empty: primary locked_targets preserved")
	_check(lock_sys.target_lock_progress == snap_progress, "rej_empty: primary target_lock_progress preserved")
	_check(lock_sys.hold_duration >= snap_hold, "rej_empty: hold_duration was not reset")

	# Primary releases normally
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(before_count + 2)
	_check(ok, "rej_empty: primary release successfully fires 2-projectile salvo")
	_check(core_left.ammo == 3, "rej_empty: left ammo decremented (5 -> 3)")

	await _cleanup_rig(rig)


func _subtest_secondary_rejection_active_reload() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	# Gate condition: Secondary slot is actively reloading
	wm.reloading_right = true
	_check(wm._is_reloading("right"), "rej_reload: secondary slot reports reloading active")

	var snap_targets: Dictionary = lock_sys.locked_targets.duplicate()
	var snap_progress: Dictionary = lock_sys.target_lock_progress.duplicate()
	var snap_hold: float = lock_sys.hold_duration
	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Secondary press while reloading
	wm._handle_missile_press("right", right_missile)

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == before_count, "rej_reload: reloading secondary launches ZERO projectiles")
	_check(core_right.ammo == 8, "rej_reload: secondary ammo remains 8 (no round consumed)")
	_check(lock_sys.is_locking, "rej_reload: primary session remains actively locking")
	_check(lock_sys.active_slot == "left", "rej_reload: active_slot remains 'left'")
	_check(lock_sys.locked_targets == snap_targets, "rej_reload: primary locked_targets preserved")
	_check(lock_sys.target_lock_progress == snap_progress, "rej_reload: primary target_lock_progress preserved")
	_check(lock_sys.hold_duration >= snap_hold, "rej_reload: hold_duration was not reset")

	# Primary releases normally
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(before_count + 2)
	_check(ok, "rej_reload: primary release successfully fires 2-projectile salvo")
	_check(core_left.ammo == 3, "rej_reload: left ammo decremented (5 -> 3)")

	wm.reloading_right = false
	await _cleanup_rig(rig)


func _subtest_secondary_rejection_active_cooldown() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	# Gate condition: Secondary core has active cooldown
	core_right.cooldown = 1.5
	_check(not core_right.can_fire(), "rej_cd: secondary core can_fire rejected due to cooldown (1.5s)")

	var snap_targets: Dictionary = lock_sys.locked_targets.duplicate()
	var snap_progress: Dictionary = lock_sys.target_lock_progress.duplicate()
	var snap_hold: float = lock_sys.hold_duration
	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Secondary press while cooling down
	wm._handle_missile_press("right", right_missile)

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == before_count, "rej_cd: cooling-down secondary launches ZERO projectiles")
	_check(core_right.ammo == 8, "rej_cd: secondary ammo remains 8 (no round consumed)")
	_check(lock_sys.is_locking, "rej_cd: primary session remains actively locking")
	_check(lock_sys.active_slot == "left", "rej_cd: active_slot remains 'left'")
	_check(lock_sys.locked_targets == snap_targets, "rej_cd: primary locked_targets preserved")
	_check(lock_sys.target_lock_progress == snap_progress, "rej_cd: primary target_lock_progress preserved")
	_check(lock_sys.hold_duration >= snap_hold, "rej_cd: hold_duration was not reset")

	# Primary releases normally
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(before_count + 2)
	_check(ok, "rej_cd: primary release successfully fires 2-projectile salvo")
	_check(core_left.ammo == 3, "rej_cd: left ammo decremented (5 -> 3)")

	core_right.cooldown = 0.0
	await _cleanup_rig(rig)


func _subtest_secondary_rejection_destroyed_arm() -> void:
	var rig := await _spawn_rig(2)
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	# Gate condition: Right arm is destroyed in HealthSystem
	var hs: MechaHealthBase = mecha.get_node_or_null("HealthSystem")
	_check(hs != null, "rej_arm: HealthSystem exists on mecha")
	hs.parts["arm_right"]["destroyed"] = true
	_check(not wm._hand_usable("right"), "rej_arm: _hand_usable('right') rejected due to destroyed arm")

	var snap_targets: Dictionary = lock_sys.locked_targets.duplicate()
	var snap_progress: Dictionary = lock_sys.target_lock_progress.duplicate()
	var snap_hold: float = lock_sys.hold_duration
	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Secondary press with destroyed arm
	wm._handle_missile_press("right", right_missile)

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == before_count, "rej_arm: destroyed-arm secondary launches ZERO projectiles")
	_check(core_right.ammo == 8, "rej_arm: secondary ammo remains 8")
	_check(lock_sys.is_locking, "rej_arm: primary session remains actively locking")
	_check(lock_sys.active_slot == "left", "rej_arm: active_slot remains 'left'")
	_check(lock_sys.locked_targets == snap_targets, "rej_arm: primary locked_targets preserved")
	_check(lock_sys.target_lock_progress == snap_progress, "rej_arm: primary target_lock_progress preserved")
	_check(lock_sys.hold_duration >= snap_hold, "rej_arm: hold_duration was not reset")

	# Primary releases normally
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(before_count + 2)
	_check(ok, "rej_arm: primary release successfully fires 2-projectile salvo")
	_check(core_left.ammo == 3, "rej_arm: left ammo decremented (5 -> 3)")

	hs.parts["arm_right"]["destroyed"] = false
	await _cleanup_rig(rig)


func _subtest_secondary_rejection_capability_denial() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	# Right slot deliberately left unarmed: wm.right_hand is null
	wm.right_hand = null
	var core_left = wm._core_for_weapon(left_missile)

	# Primary starts, accumulates 2 locks
	wm._handle_missile_press("left", left_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	# Gate condition: _request_gate denies ACTION_FIRE for unarmed slot
	var gate_res: Dictionary = wm._request_gate("right", WeaponGameplayCapability.ACTION_FIRE)
	_check(not bool(gate_res.get("allowed", false)), "rej_gate: _request_gate rejects unarmed secondary slot (reason=%s)" % str(gate_res.get("reason")))

	var snap_targets: Dictionary = lock_sys.locked_targets.duplicate()
	var snap_progress: Dictionary = lock_sys.target_lock_progress.duplicate()
	var snap_hold: float = lock_sys.hold_duration
	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Secondary press on gate-denied slot
	wm._handle_missile_press("right", right_missile)

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == before_count, "rej_gate: capability-denied secondary launches ZERO projectiles")
	_check(lock_sys.is_locking, "rej_gate: primary session remains actively locking")
	_check(lock_sys.active_slot == "left", "rej_gate: active_slot still 'left'")
	_check(lock_sys.locked_targets == snap_targets, "rej_gate: primary locked_targets preserved")
	_check(lock_sys.target_lock_progress == snap_progress, "rej_gate: primary target_lock_progress preserved")
	_check(lock_sys.hold_duration >= snap_hold, "rej_gate: hold_duration was not reset")

	# Primary releases normally
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(before_count + 2)
	_check(ok, "rej_gate: primary release successfully fires 2-projectile salvo")
	_check(core_left.ammo == 3, "rej_gate: left ammo decremented (5 -> 3)")

	await _cleanup_rig(rig)



# ---------------------------------------------------------------------------
# 6. No Accidental Lock Restart on Active Slot Repeated Input
# ---------------------------------------------------------------------------

func _test_no_accidental_lock_restart() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system
	var missile: WeaponPart = load(HEAVY_MISSILE_PATH)

	_mount_weapon(wm, "left", missile, 5)
	var core = wm._core_for_weapon(missile)

	# Primary start
	wm._handle_missile_press("left", missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.target_lock_progress[targets[0]] = 0.12
	lock_sys.hold_duration = 0.65

	var count0 := get_tree().get_nodes_in_group("projectile").size()

	# Repeated press event on the SAME active slot
	wm._handle_missile_press("left", missile)

	for i in range(5):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == count0, "no_restart: repeated active press launches ZERO projectiles")
	_check(lock_sys.is_locking, "no_restart: lock_sys remains active")
	_check(lock_sys.active_slot == "left", "no_restart: active_slot remains 'left'")
	_check(lock_sys.hold_duration >= 0.65, "no_restart: hold_duration was NOT reset (preserved >= 0.65s)")
	_check(int(lock_sys.locked_targets.get(targets[0], 0)) == 2, "no_restart: locked_targets NOT wiped (2 locks preserved)")
	_check(float(lock_sys.target_lock_progress.get(targets[0], 0.0)) == 0.12, "no_restart: target_lock_progress NOT wiped")

	# Clean release
	wm._handle_missile_release("left")
	var ok := await _wait_for_proj_count(count0 + 2)
	_check(ok, "no_restart: release fires full 2-missile salvo")
	_check(core.ammo == 3, "no_restart: left ammo decremented (5 -> 3)")

	_completed["no_accidental_restart"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 7. Slot Routing: Hand-to-Shoulder Contention
# ---------------------------------------------------------------------------

func _test_slot_routing_hand_to_shoulder() -> void:
	var rig := await _spawn_rig(2)
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var hand_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var shoulder_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", hand_missile, 5)
	_mount_weapon(wm, "shoulder_right", shoulder_missile, 8)
	var core_hand = wm._core_for_weapon(hand_missile)
	var core_shoulder = wm._core_for_weapon(shoulder_missile)

	# Hand starts locking
	wm._handle_missile_press("left", hand_missile)
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Shoulder pressed -> immediate dumbfire fallback from shoulder
	wm._handle_missile_press("shoulder_right", shoulder_missile)

	var ok := await _wait_for_proj_count(before_count + 1)
	_check(ok, "route_hs: shoulder press launches 1 dumbfire projectile")
	_check(core_shoulder.ammo == 7, "route_hs: shoulder ammo decremented (8 -> 7)")
	_check(core_hand.ammo == 5, "route_hs: hand ammo untouched (5/5)")

	# Verify shoulder muzzle height
	var expected_spawn: Vector3 = wm._get_shoulder_muzzle_world_pos("right")
	if expected_spawn == Vector3.INF:
		expected_spawn = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.shoulder_fallback_for(mecha, "right")

	var all_projs: Array = get_tree().get_nodes_in_group("projectile")
	var dumbfire_proj: Node3D = all_projs.back() as Node3D
	var y_err: float = absf(dumbfire_proj.global_position.y - expected_spawn.y)
	_check(y_err < 1.0, "route_hs: projectile Y (%.2f) consistent with shoulder muzzle (%.2f, diff=%.2f < 1.0m)" % [dumbfire_proj.global_position.y, expected_spawn.y, y_err])

	# Hand release launches guided salvo
	wm._handle_missile_release("left")
	await _wait_for_proj_count(before_count + 3)
	_check(core_hand.ammo == 3, "route_hs: hand salvo fired (5 -> 3)")

	_completed["routing_hand_to_shoulder"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 8. Slot Routing: Shoulder-to-Hand Contention
# ---------------------------------------------------------------------------

func _test_slot_routing_shoulder_to_hand() -> void:
	var rig := await _spawn_rig(2)
	var mecha: Node3D = rig[0]
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var shoulder_missile: WeaponPart = load(STD_MISSILE_PATH)
	var hand_missile: WeaponPart = load(HEAVY_MISSILE_PATH)

	_mount_weapon(wm, "shoulder_left", shoulder_missile, 8)
	_mount_weapon(wm, "right", hand_missile, 5)
	var core_shoulder = wm._core_for_weapon(shoulder_missile)
	var core_hand = wm._core_for_weapon(hand_missile)

	# Shoulder starts locking
	wm._handle_missile_press("shoulder_left", shoulder_missile)
	_check(lock_sys.is_locking, "route_sh: shoulder lock active")
	_check(lock_sys.active_slot == "shoulder_left", "route_sh: active_slot is 'shoulder_left'")
	lock_sys.locked_targets[targets[0]] = 2
	lock_sys.hold_duration = 0.50

	var before_count := get_tree().get_nodes_in_group("projectile").size()

	# Hand pressed -> immediate dumbfire fallback from hand
	wm._handle_missile_press("right", hand_missile)

	var ok := await _wait_for_proj_count(before_count + 1)
	_check(ok, "route_sh: hand press launches 1 dumbfire projectile")
	_check(core_hand.ammo == 4, "route_sh: hand ammo decremented (5 -> 4)")
	_check(core_shoulder.ammo == 8, "route_sh: shoulder ammo untouched (8/8)")

	# Verify hand muzzle height
	var expected_spawn: Vector3 = wm._get_muzzle_world_pos("right")
	if expected_spawn == Vector3.INF:
		expected_spawn = mecha.global_position + mecha.global_transform.basis * FrameVariantResolver.hand_fallback_for(mecha, "right")

	var all_projs: Array = get_tree().get_nodes_in_group("projectile")
	var dumbfire_proj: Node3D = all_projs.back() as Node3D
	var y_err: float = absf(dumbfire_proj.global_position.y - expected_spawn.y)
	_check(y_err < 1.0, "route_sh: projectile Y (%.2f) consistent with hand muzzle (%.2f, diff=%.2f < 1.0m)" % [dumbfire_proj.global_position.y, expected_spawn.y, y_err])

	# Shoulder release launches guided salvo
	wm._handle_missile_release("shoulder_left")
	await _wait_for_proj_count(before_count + 3)
	_check(core_shoulder.ammo == 6, "route_sh: shoulder salvo fired (8 -> 6)")

	_completed["routing_shoulder_to_hand"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 9. Normal Missile Tap Dumbfire Release
# ---------------------------------------------------------------------------

func _test_normal_tap_dumbfire_release() -> void:
	var rig := await _spawn_rig(1)
	var wm: Node3D = rig[1]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system
	var missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "right", missile, 8)
	var core = wm._core_for_weapon(missile)

	# Start lock and simulate quick tap (< tap_threshold 0.22, 0 locks)
	wm._handle_missile_press("right", missile)
	lock_sys.hold_duration = 0.05

	var before_count := get_tree().get_nodes_in_group("projectile").size()
	wm._handle_missile_release("right")

	var ok := await _wait_for_proj_count(before_count + 1)
	_check(ok, "tap: tap release launches exactly 1 dumbfire projectile")
	_check(core.ammo == 7, "tap: ammo decremented (8 -> 7)")
	_check(not lock_sys.is_locking, "tap: lock_sys returned to idle")

	_completed["normal_tap_dumbfire"] = true
	await _cleanup_rig(rig)


# ---------------------------------------------------------------------------
# 10. Real Action Handler Path Integration
# ---------------------------------------------------------------------------

func _test_input_event_integration() -> void:
	var rig := await _spawn_rig(2)
	var wm: Node3D = rig[1]
	var targets: Array = rig[2]
	var lock_sys: MissileLockOnSystem = wm.missile_lock_system

	var left_missile: WeaponPart = load(HEAVY_MISSILE_PATH)
	var right_missile: WeaponPart = load(STD_MISSILE_PATH)

	_mount_weapon(wm, "left", left_missile, 5)
	_mount_weapon(wm, "right", right_missile, 8)
	var core_left = wm._core_for_weapon(left_missile)
	var core_right = wm._core_for_weapon(right_missile)

	# Action 1: Left trigger press starts locking through canonical handler
	wm._handle_missile_press("left", left_missile)

	_check(lock_sys.is_locking, "action_int: left trigger press starts locking")
	_check(lock_sys.active_slot == "left", "action_int: active_slot is 'left'")

	# Accumulate 1 lock on target 0
	lock_sys.locked_targets[targets[0]] = 1
	lock_sys.hold_duration = 0.50

	var count0 := get_tree().get_nodes_in_group("projectile").size()

	# Action 2: Secondary right trigger pressed while left held -> fallback dumbfire
	wm._handle_missile_press("right", right_missile)

	var ok1 := await _wait_for_proj_count(count0 + 1)
	_check(ok1, "action_int: secondary fire_right press launches 1 dumbfire projectile")
	_check(core_right.ammo == 7, "action_int: right ammo decremented (8 -> 7)")
	_check(lock_sys.is_locking, "action_int: left session remains actively locking")
	_check(lock_sys.active_slot == "left", "action_int: active_slot remains 'left'")

	# Action 3: Primary fire_left released -> launches guided salvo
	wm._handle_missile_release("left")

	var ok2 := await _wait_for_proj_count(count0 + 2)
	_check(ok2, "action_int: primary fire_left release launches guided salvo")
	_check(core_left.ammo == 4, "action_int: left ammo decremented (5 -> 4)")
	_check(not lock_sys.is_locking, "action_int: lock_sys is now idle")

	# Action 4: Secondary fire_right released -> inert, zero extra projectiles
	wm._handle_missile_release("right")

	for i in range(10):
		await get_tree().physics_frame

	_check(get_tree().get_nodes_in_group("projectile").size() == count0 + 2, "action_int: secondary fire_right release launches ZERO extra projectiles")

	_completed["input_event_integration"] = true
	await _cleanup_rig(rig)
