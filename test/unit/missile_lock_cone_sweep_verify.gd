extends Node
## MISSILE LOCK CONE SWEEP VERIFY (Phase R2-BZ, test-only).
##
## Dedicated runtime verification harness exercising the real
## MissileLockOnSystem._physics_process() and real PhysicsDirectSpaceState3D
## raycasting loop rather than manually injecting entries into locked_targets.
##
## Verified contracts:
##  BZ-01: On-axis lock acquisition through physics frames.
##  BZ-02: Off-cone angular rejection within weapon range.
##  BZ-03: Multi-lock stacking on single target and multi-target acquisition.
##  BZ-04: Line-of-sight raycast obstruction and restoration.
##  BZ-05: Cone exit and re-entry (characterizing progress retention).
##  BZ-06: Target invalidation before first lock and cleanup contract.
##
## Run: godot --headless --path . test/unit/missile_lock_cone_sweep_verify.tscn

const LOCK_SYS_SCRIPT = preload("res://scripts/systems/missile_lock_on_system.gd")
const WEAPON_HEAVY_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"

var _fails := 0
var _checks := 0
var _completed := {}


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CONE-SWEEP OK: " + name)
	else:
		_fails += 1
		printerr("CONE-SWEEP FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame

	await _test_bz01_on_axis_lock_acquisition()
	await _test_bz02_off_cone_rejection()
	await _test_bz03_multi_lock_accumulation()
	await _test_bz04_line_of_sight_obstruction()
	await _test_bz05_cone_exit_and_reentry()
	await _test_bz06_invalid_target_before_first_lock()

	for case_name in ["bz01", "bz02", "bz03", "bz04", "bz05", "bz06"]:
		_check(bool(_completed.get(case_name, false)), "case completed: " + case_name)

	await get_tree().process_frame
	await get_tree().physics_frame

	print("MISSILE_LOCK_CONE_SWEEP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MISSILE_LOCK_CONE_SWEEP_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MISSILE_LOCK_CONE_SWEEP_TESTS_PASSED")
		get_tree().quit(0)


# ---------------------------------------------------------------------------
# Fixture Management
# ---------------------------------------------------------------------------

func _spawn_fixture() -> Dictionary:
	var root_node := Node3D.new()
	root_node.name = "FixtureRoot"
	add_child(root_node)

	# Active camera at Vector3(0, 1.2, 0) facing -Z (Godot forward)
	var cam := Camera3D.new()
	cam.name = "TestCamera"
	cam.position = Vector3(0.0, 1.2, 0.0)
	cam.current = true
	root_node.add_child(cam)

	# Static ground plane for physics world completeness
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 2
	ground.position = Vector3(0.0, -1.0, 0.0)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(100.0, 2.0, 100.0)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	root_node.add_child(ground)

	# Live MissileLockOnSystem
	var sys: MissileLockOnSystem = LOCK_SYS_SCRIPT.new()
	sys.name = "MissileLockOnSystem"
	root_node.add_child(sys)

	# Signal recorders
	var signals := {
		"acquired": [],
		"updated": [],
		"cleared": 0
	}
	sys.lock_acquired.connect(func(target: Node3D, stack: int) -> void:
		signals["acquired"].append({"target": target, "stack": stack})
	)
	sys.lock_updated.connect(func(targets: Dictionary) -> void:
		signals["updated"].append(targets.duplicate())
	)
	sys.lock_cleared.connect(func() -> void:
		signals["cleared"] = int(signals["cleared"]) + 1
	)

	return {
		"root": root_node,
		"cam": cam,
		"ground": ground,
		"sys": sys,
		"signals": signals,
		"spawned_nodes": []
	}


func _create_enemy(fixture: Dictionary, pos: Vector3, ename: String = "Enemy") -> Node3D:
	var enemy := Node3D.new()
	enemy.name = ename
	enemy.position = pos
	enemy.add_to_group("enemy")
	fixture["root"].add_child(enemy)
	fixture["spawned_nodes"].append(enemy)
	return enemy


func _create_obstacle(fixture: Dictionary, pos: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	obstacle.name = "Obstacle"
	obstacle.position = pos
	obstacle.collision_layer = layer
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	obstacle.add_child(col)
	fixture["root"].add_child(obstacle)
	fixture["spawned_nodes"].append(obstacle)
	return obstacle


func _advance_physics_frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame


func _cleanup_fixture(fixture: Dictionary) -> void:
	if fixture.has("signals"):
		fixture["signals"]["acquired"].clear()
		fixture["signals"]["updated"].clear()
	if fixture.has("sys") and is_instance_valid(fixture["sys"]):
		var sys: MissileLockOnSystem = fixture["sys"]
		if sys.is_locking:
			sys.cancel_locking()
	if fixture.has("root") and is_instance_valid(fixture["root"]):
		fixture["root"].queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# BZ-01: On-Axis Lock Acquisition
# ---------------------------------------------------------------------------

func _test_bz01_on_axis_lock_acquisition() -> void:
	var fix := _spawn_fixture()
	var sys: MissileLockOnSystem = fix["sys"]
	var signals: Dictionary = fix["signals"]

	# Target placed on-axis along -Z at 10m
	# Enemy center is target.global_position + Vector3(0, 1.2, 0) = Vector3(0, 1.2, -10)
	# Camera is at Vector3(0, 1.2, 0) -> vector to enemy is Vector3(0, 0, -1), angle = 0.0 deg
	var enemy := _create_enemy(fix, Vector3(0.0, 0.0, -10.0), "BZ01_Target")
	await _advance_physics_frames(2)

	var weapon: WeaponPart = load(WEAPON_HEAVY_PATH)
	_check(weapon != null, "bz01: weapon resource loaded successfully")

	# Start locking with 5 ammo (lock interval = 0.16s, approx 10 physics frames at 60Hz)
	sys.start_locking("right", weapon, 5)
	_check(sys.is_locking, "bz01: lock system is_locking is true")
	_check(sys.locked_targets.is_empty(), "bz01: initial locked_targets is empty")

	# Advance 4 physics frames (~0.067s < 0.16s)
	await _advance_physics_frames(4)
	_check(sys.locked_targets.is_empty(), "bz01: no lock before lock_interval elapsed")
	_check(sys.target_lock_progress.has(enemy), "bz01: target is tracked in target_lock_progress")
	var prog_early: float = float(sys.target_lock_progress.get(enemy, 0.0))
	_check(prog_early > 0.0 and prog_early < sys.lock_interval, "bz01: partial progress accumulating (%f s)" % prog_early)

	# Advance 10 more physics frames (total 14 frames ~ 0.233s >= 0.16s)
	await _advance_physics_frames(10)
	_check(sys.locked_targets.has(enemy), "bz01: target acquired in locked_targets through physics loop")
	_check(int(sys.locked_targets.get(enemy, 0)) == 1, "bz01: locked count for enemy is exactly 1")
	_check(sys.get_total_locks() == 1, "bz01: total locks is 1")

	# Verify signal emission
	_check(signals["acquired"].size() == 1, "bz01: lock_acquired emitted exactly once")
	if signals["acquired"].size() >= 1:
		var acq = signals["acquired"][0]
		_check(acq["target"] == enemy and acq["stack"] == 1, "bz01: lock_acquired reports correct target and stack 1")
	_check(not signals["updated"].is_empty(), "bz01: lock_updated signal emitted")

	var stop_result := sys.stop_locking()
	_check(stop_result["total_locks"] == 1, "bz01: stop_locking returns acquired target lock")
	_check(signals["cleared"] == 1, "bz01: lock_cleared signal emitted on stop")

	await _cleanup_fixture(fix)
	_completed["bz01"] = true


# ---------------------------------------------------------------------------
# BZ-02: Off-Cone Rejection
# ---------------------------------------------------------------------------

func _test_bz02_off_cone_rejection() -> void:
	var fix := _spawn_fixture()
	var sys: MissileLockOnSystem = fix["sys"]
	var signals: Dictionary = fix["signals"]

	# Target at (15.0, 0.0, -10.0):
	# Distance = sqrt(15^2 + 10^2) = 18.03m <= 100m (within weapon range)
	# Angle = atan2(15, 10) = 56.3 deg > lock_cone_degrees (16.0 deg)
	var enemy := _create_enemy(fix, Vector3(15.0, 0.0, -10.0), "BZ02_OffConeTarget")
	await _advance_physics_frames(2)

	var weapon: WeaponPart = load(WEAPON_HEAVY_PATH)
	sys.start_locking("right", weapon, 5)

	# Advance 15 physics frames (~0.25s > lock_interval)
	await _advance_physics_frames(15)
	_check(sys.locked_targets.is_empty(), "bz02: off-cone target is not acquired in locked_targets")
	_check(signals["acquired"].is_empty(), "bz02: no lock_acquired signal emitted for off-cone target")
	_check(not sys.target_lock_progress.has(enemy), "bz02: off-cone target rejected before progress tracking")

	# Control check: move enemy into cone at (0.0, 0.0, -10.0)
	enemy.position = Vector3(0.0, 0.0, -10.0)
	await _advance_physics_frames(14)
	_check(sys.locked_targets.has(enemy), "bz02: control: target acquires lock once moved into cone")
	_check(int(sys.locked_targets.get(enemy, 0)) == 1, "bz02: control: proves rejection was strictly angular")

	await _cleanup_fixture(fix)
	_completed["bz02"] = true


# ---------------------------------------------------------------------------
# BZ-03: Multi-Lock Accumulation (Multi-Lock & Multi-Target)
# ---------------------------------------------------------------------------

func _test_bz03_multi_lock_accumulation() -> void:
	var fix := _spawn_fixture()
	var sys: MissileLockOnSystem = fix["sys"]
	var signals: Dictionary = fix["signals"]

	var enemy := _create_enemy(fix, Vector3(0.0, 0.0, -10.0), "BZ03_Target")
	await _advance_physics_frames(2)

	var weapon: WeaponPart = load(WEAPON_HEAVY_PATH)
	# Provide 2 ammo capacity so max_total_locks is capped at 2
	sys.start_locking("right", weapon, 2)
	_check(sys.max_total_locks == 2, "bz03: max_total_locks is configured to 2")

	# Advance ~14 physics frames -> 1st lock acquired
	await _advance_physics_frames(14)
	_check(int(sys.locked_targets.get(enemy, 0)) == 1, "bz03: first lock acquired after ~14 frames")
	_check(signals["acquired"].size() == 1, "bz03: first lock_acquired emitted")

	# Advance 4 more physics frames (~0.067s) -> 2nd lock should NOT be acquired yet
	await _advance_physics_frames(4)
	_check(int(sys.locked_targets.get(enemy, 0)) == 1, "bz03: second lock requires additional acquisition time")

	# Advance 10 more physics frames (total 28 frames ~ 0.467s >= 2 * 0.16s) -> 2nd lock acquired
	await _advance_physics_frames(10)
	_check(int(sys.locked_targets.get(enemy, 0)) == 2, "bz03: second lock accumulated to count 2")
	_check(signals["acquired"].size() == 2, "bz03: second lock_acquired emitted")
	_check(signals["acquired"][1]["stack"] == 2, "bz03: second signal reports stack 2")

	# Advance 20 more physics frames: verify cap enforcement
	await _advance_physics_frames(20)
	_check(int(sys.locked_targets.get(enemy, 0)) == 2, "bz03: lock count does not exceed magazine cap of 2")
	_check(sys.get_total_locks() == 2, "bz03: total locks stays at cap 2")

	# Multi-target check: reset and test two distinct enemies in cone
	sys.cancel_locking()
	var enemy2 := _create_enemy(fix, Vector3(1.0, 0.0, -10.0), "BZ03_Target2")
	# angle for enemy2 is atan2(1, 10) = 5.7 deg <= 16.0 deg (in cone)
	signals["acquired"].clear()
	sys.start_locking("right", weapon, 5)

	await _advance_physics_frames(15)
	_check(sys.locked_targets.has(enemy), "bz03: multi-target: enemy 1 locked")
	_check(sys.locked_targets.has(enemy2), "bz03: multi-target: enemy 2 locked")
	_check(sys.get_total_locks() >= 2, "bz03: multi-target: accumulated locks on multiple targets (%d)" % sys.get_total_locks())

	await _cleanup_fixture(fix)
	_completed["bz03"] = true


# ---------------------------------------------------------------------------
# BZ-04: Line-of-Sight Obstruction
# ---------------------------------------------------------------------------

func _test_bz04_line_of_sight_obstruction() -> void:
	var fix := _spawn_fixture()
	var sys: MissileLockOnSystem = fix["sys"]
	var cam: Camera3D = fix["cam"]
	var signals: Dictionary = fix["signals"]

	var enemy := _create_enemy(fix, Vector3(0.0, 0.0, -10.0), "BZ04_Target")

	# Obstacle between camera (0, 1.2, 0) and enemy (0, 1.2, -10)
	# Collision layer 1 intersects raycast mask (1 | 4)
	var obstacle := _create_obstacle(fix, Vector3(0.0, 1.2, -5.0), Vector3(6.0, 6.0, 2.0), 1)

	# Advance 2 physics frames for physics engine body registration
	await _advance_physics_frames(2)

	# Direct control assertion: query space state to prove physics ray hits obstacle
	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, enemy.global_position + Vector3(0.0, 1.2, 0.0))
	query.collision_mask = 1 | 4
	var hit := space.intersect_ray(query)
	_check(hit.has("collider") and hit["collider"] == obstacle, "bz04: physics control: raycast hits registered obstacle")

	var weapon: WeaponPart = load(WEAPON_HEAVY_PATH)
	sys.start_locking("right", weapon, 5)

	# Advance 15 physics frames while obstructed
	await _advance_physics_frames(15)
	_check(sys.locked_targets.is_empty(), "bz04: obstructed target acquires zero locks")
	_check(signals["acquired"].is_empty(), "bz04: zero lock_acquired signals while obstructed")
	_check(sys.target_lock_progress.is_empty(), "bz04: zero progress accumulated while obstructed")

	# Move obstacle far away to restore line of sight
	obstacle.position = Vector3(100.0, 0.0, 0.0)
	await _advance_physics_frames(2)

	var hit_restored := space.intersect_ray(query)
	_check(hit_restored.is_empty(), "bz04: physics control: line of sight is clear after obstacle removal")

	# Advance 15 physics frames with clear line of sight
	await _advance_physics_frames(15)
	_check(sys.locked_targets.has(enemy), "bz04: lock acquired after obstacle removed and line of sight restored")
	_check(int(sys.locked_targets.get(enemy, 0)) == 1, "bz04: lock count is 1 after line of sight restoration")

	await _cleanup_fixture(fix)
	_completed["bz04"] = true


# ---------------------------------------------------------------------------
# BZ-05: Cone Exit and Re-entry
# ---------------------------------------------------------------------------

func _test_bz05_cone_exit_and_reentry() -> void:
	var fix := _spawn_fixture()
	var sys: MissileLockOnSystem = fix["sys"]
	var signals: Dictionary = fix["signals"]

	var enemy := _create_enemy(fix, Vector3(0.0, 0.0, -10.0), "BZ05_Target")
	await _advance_physics_frames(2)

	var weapon: WeaponPart = load(WEAPON_HEAVY_PATH)
	sys.start_locking("right", weapon, 5)

	# 1. Accumulate partial progress (5 frames ~ 0.0833s < 0.16s lock_interval)
	await _advance_physics_frames(5)
	_check(sys.locked_targets.is_empty(), "bz05: target not locked at partial progress")
	var prog_before_exit: float = float(sys.target_lock_progress.get(enemy, 0.0))
	_check(prog_before_exit > 0.0 and prog_before_exit < sys.lock_interval, "bz05: partial progress accumulated (%.4f s)" % prog_before_exit)

	# 2. Move target outside cone
	enemy.position = Vector3(20.0, 0.0, -10.0)
	await _advance_physics_frames(10)
	_check(sys.locked_targets.is_empty(), "bz05: target remains unlocked while outside cone")

	# Characterize retention: production code does not decay or reset progress while outside cone
	var prog_outside: float = float(sys.target_lock_progress.get(enemy, 0.0))
	_check(is_equal_approx(prog_outside, prog_before_exit), "bz05: characterization: progress is preserved/frozen outside cone (%.4f vs %.4f)" % [prog_outside, prog_before_exit])

	# 3. Return target into cone: needs only remaining ~0.08s (~5-6 frames) to complete lock
	enemy.position = Vector3(0.0, 0.0, -10.0)
	await _advance_physics_frames(6)
	_check(sys.locked_targets.has(enemy), "bz05: lock acquired upon re-entering cone with preserved progress")
	_check(int(sys.locked_targets.get(enemy, 0)) == 1, "bz05: lock count is 1 after re-entry")
	_check(signals["acquired"].size() == 1, "bz05: lock_acquired signal emitted on completion")

	await _cleanup_fixture(fix)
	_completed["bz05"] = true


# ---------------------------------------------------------------------------
# BZ-06: Invalid Target Before First Lock
# ---------------------------------------------------------------------------

func _test_bz06_invalid_target_before_first_lock() -> void:
	var fix := _spawn_fixture()
	var sys: MissileLockOnSystem = fix["sys"]
	var signals: Dictionary = fix["signals"]

	var enemy := _create_enemy(fix, Vector3(0.0, 0.0, -10.0), "BZ06_Target")
	await _advance_physics_frames(2)

	var weapon: WeaponPart = load(WEAPON_HEAVY_PATH)
	sys.start_locking("right", weapon, 5)

	# 1. Accumulate partial progress before lock
	await _advance_physics_frames(5)
	_check(sys.target_lock_progress.has(enemy), "bz06: pre-lock progress tracked in system")
	_check(sys.locked_targets.is_empty(), "bz06: target not yet in locked_targets")

	# 2. Invalidate/free target before first lock
	enemy.queue_free()
	await _advance_physics_frames(2)
	_check(not is_instance_valid(enemy), "bz06: target node successfully freed")

	# 3. Advance 15 physics frames: ensure no crash or dereferencing of freed object
	await _advance_physics_frames(15)
	_check(sys.locked_targets.is_empty(), "bz06: no lock acquired for freed target")
	_check(signals["acquired"].is_empty(), "bz06: no signal emitted for freed target")

	# 4. Characterize residual state & cleanup:
	# Production pruning loop at line 93 only iterates locked_targets.keys().
	# Pre-lock targets remain in target_lock_progress until cancel_locking() or stop_locking().
	var has_residual_key: bool = false
	for k in sys.target_lock_progress.keys():
		if not is_instance_valid(k):
			has_residual_key = true
	_check(has_residual_key, "bz06: characterization: uncompleted target key remains in target_lock_progress during active hold")

	# Verification that cancel_locking() cleans up all residual state safely
	sys.cancel_locking()
	_check(sys.target_lock_progress.is_empty(), "bz06: cancel_locking() completely clears target_lock_progress")
	_check(sys.locked_targets.is_empty(), "bz06: cancel_locking() completely clears locked_targets")

	await _cleanup_fixture(fix)
	_completed["bz06"] = true
