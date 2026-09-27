extends Node
## VALKREN — SHOULDER WEAPON FIRING LIFECYCLE PARITY VERIFY
## Validates that shoulder weapons and arm weapons use the exact same firing lifecycle:
## single shot, hold-fire continuous spray, reload lifecycle, ammo consumption, cooldown,
## simultaneous firing without cross-leakage, and unified muzzle resolution.

const MECHA_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _checks := 0
var _fails := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + msg)
	else:
		_fails += 1
		printerr("  FAIL: " + msg)

func _ready() -> void:
	print("--- Running shoulder_firing_parity_verify ---")
	await get_tree().process_frame

	# Setup resources
	var auto_rifle: WeaponPart = WeaponPart.new()
	auto_rifle.weapon_name = "Parity Test Auto Rifle"
	auto_rifle.weapon_type = WeaponPart.WeaponType.MACHINE_GUN
	auto_rifle.damage = 15.0
	auto_rifle.fire_rate = 0.1
	auto_rifle.max_ammo = 30
	auto_rifle.ammo_per_shot = 1
	auto_rifle.reload_time = 0.2
	auto_rifle.heat_per_shot = 5.0
	auto_rifle.heat_capacity = 100.0

	var auto_cannon: WeaponPart = WeaponPart.new()
	auto_cannon.weapon_name = "Parity Test Shoulder Cannon"
	auto_cannon.weapon_type = WeaponPart.WeaponType.MACHINE_GUN
	auto_cannon.damage = 25.0
	auto_cannon.fire_rate = 0.1
	auto_cannon.max_ammo = 30
	auto_cannon.ammo_per_shot = 1
	auto_cannon.reload_time = 0.2
	auto_cannon.heat_per_shot = 5.0
	auto_cannon.heat_capacity = 100.0

	# Instantiate live MechaBase scene
	var mecha_scene: PackedScene = load(MECHA_SCENE)
	_check(mecha_scene != null, "mecha_base.tscn loads successfully")
	var mecha: Node3D = mecha_scene.instantiate() as Node3D
	add_child(mecha)
	await get_tree().process_frame

	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		var wm_script = load("res://scripts/mecha/weapon_manager.gd")
		wm = Node3D.new()
		wm.name = "WeaponManager"
		wm.set_script(wm_script)
		mecha.add_child(wm)
		await get_tree().process_frame

	_check(wm != null, "Mecha has WeaponManager node")
	if wm == null:
		get_tree().quit(1)
		return

	# Mount Arm and Shoulder weapons
	wm.left_hand = auto_rifle
	wm.shoulder_left = auto_cannon
	wm._set_ammo(auto_rifle, auto_rifle.max_ammo)
	wm._set_ammo(auto_cannon, auto_cannon.max_ammo)
	wm.add_battle_reserve("bullet", 200)
	wm._update_weapon_visuals()
	await get_tree().process_frame

	# =========================================================================
	# TEST 1: Single Shot Parity (Arm vs Shoulder)
	# =========================================================================
	print("\n-- Test 1: Single Shot Parity --")
	var arm_ammo_before: int = wm._get_ammo(auto_rifle)
	var shoulder_ammo_before: int = wm._get_ammo(auto_cannon)

	wm._commit_fire("left", auto_rifle)
	wm._commit_fire("shoulder_left", auto_cannon)

	_check(wm._get_ammo(auto_rifle) == arm_ammo_before - 1, "Arm weapon ammo decreased by 1 on single shot (30 -> 29)")
	_check(wm._get_ammo(auto_cannon) == shoulder_ammo_before - 1, "Shoulder weapon ammo decreased by 1 on single shot (30 -> 29)")

	var arm_core: WeaponCore = wm._core_for_weapon(auto_rifle)
	var shoulder_core: WeaponCore = wm._core_for_weapon(auto_cannon)
	_check(arm_core.cooldown > 0.0, "Arm weapon core has active cooldown after shot")
	_check(shoulder_core.cooldown > 0.0, "Shoulder weapon core has active cooldown after shot")
	_check(is_equal_approx(arm_core.cooldown, shoulder_core.cooldown), "Arm and Shoulder have identical cooldown duration")

	# =========================================================================
	# TEST 2: Hold Fire Parity (Continuous Spray)
	# =========================================================================
	print("\n-- Test 2: Hold Fire Parity --")
	# Reset cooldowns and refill
	arm_core.cooldown = 0.0
	shoulder_core.cooldown = 0.0
	wm._set_ammo(auto_rifle, 20)
	wm._set_ammo(auto_cannon, 20)

	# Simulate holding fire on both for multiple ticks
	wm.fire_left_holding = true
	wm.fire_shoulder_left_holding = true

	for i in range(4):
		arm_core.tick(0.1)
		shoulder_core.tick(0.1)
		wm._hold_fire("left", auto_rifle)
		wm._hold_fire("shoulder_left", auto_cannon)

	var arm_held_ammo: int = wm._get_ammo(auto_rifle)
	var shoulder_held_ammo: int = wm._get_ammo(auto_cannon)
	_check(arm_held_ammo < 20, "Arm weapon sprayed rounds during hold (%d/20)" % arm_held_ammo)
	_check(shoulder_held_ammo < 20, "Shoulder weapon sprayed rounds during hold (%d/20)" % shoulder_held_ammo)
	_check(arm_held_ammo == shoulder_held_ammo, "Arm and Shoulder consumed identical ammo under hold fire (%d vs %d)" % [arm_held_ammo, shoulder_held_ammo])

	# Release trigger
	wm.fire_left_holding = false
	wm.fire_shoulder_left_holding = false
	var trig_arm = wm._get_trigger("left")
	var trig_shoulder = wm._get_trigger("shoulder_left")
	trig_arm.release()
	trig_shoulder.release()

	# Tick again: should NOT fire after release
	var arm_ammo_after_release: int = wm._get_ammo(auto_rifle)
	var shoulder_ammo_after_release: int = wm._get_ammo(auto_cannon)
	arm_core.tick(0.15)
	shoulder_core.tick(0.15)
	wm._physics_process(0.15)
	_check(wm._get_ammo(auto_rifle) == arm_ammo_after_release, "Arm weapon stopped firing after release")
	_check(wm._get_ammo(auto_cannon) == shoulder_ammo_after_release, "Shoulder weapon stopped firing after release")

	# =========================================================================
	# TEST 3: Reload Lifecycle Parity
	# =========================================================================
	print("\n-- Test 3: Reload Lifecycle Parity --")
	wm._set_ammo(auto_rifle, 5)
	wm._set_ammo(auto_cannon, 5)

	var signals_received := {
		"arm": false,
		"shoulder": false
	}
	wm.ammo_changed.connect(func(hand: String, cur: int, mx: int):
		if hand == "left" and cur == auto_rifle.max_ammo:
			signals_received["arm"] = true
	)
	wm.shoulder_ammo_changed.connect(func(side: String, cur: int, mx: int):
		if side == "left" and cur == auto_cannon.max_ammo:
			signals_received["shoulder"] = true
	)

	# Start reload on arm
	wm.reload_weapon("left")
	_check(wm.reloading_left == true, "Arm weapon entered reloading state")

	# Start reload on shoulder
	wm.reload_weapon("shoulder_left")
	_check(wm.reloading_shoulder_left == true, "Shoulder weapon entered reloading state")

	# Wait for reload timers to complete (reload_time = 0.2s)
	await get_tree().create_timer(0.45).timeout

	_check(wm.reloading_left == false, "Arm weapon completed reload state")
	_check(wm.reloading_shoulder_left == false, "Shoulder weapon completed reload state")
	_check(wm._get_ammo(auto_rifle) == auto_rifle.max_ammo, "Arm weapon magazine refilled to full (30)")
	_check(wm._get_ammo(auto_cannon) == auto_cannon.max_ammo, "Shoulder weapon magazine refilled to full (30)")
	_check(signals_received["arm"], "Arm emitted ammo_changed signal on reload completion")
	_check(signals_received["shoulder"], "Shoulder emitted shoulder_ammo_changed signal on reload completion")

	# =========================================================================
	# TEST 4: Simultaneous Multi-Weapon State Isolation
	# =========================================================================
	print("\n-- Test 4: Simultaneous Multi-Weapon State Isolation --")
	# Drain shoulder completely, keep arm full
	wm._set_ammo(auto_rifle, 30)
	wm._set_ammo(auto_cannon, 0)
	arm_core.cooldown = 0.0
	shoulder_core.cooldown = 0.0

	# Fire both simultaneously
	wm._commit_fire("left", auto_rifle)
	wm._commit_fire("shoulder_left", auto_cannon)

	_check(wm._get_ammo(auto_rifle) == 29, "Arm fired successfully when shoulder was empty (30 -> 29)")
	_check(wm._get_ammo(auto_cannon) == 0, "Shoulder remained empty and did not steal ammo from arm")
	_check(arm_core.cooldown > 0.0, "Arm has active cooldown")

	# =========================================================================
	# TEST 5: Muzzle Resolution Parity
	# =========================================================================
	print("\n-- Test 5: Muzzle Resolution Parity --")
	var arm_muzzle: Vector3 = wm.get_muzzle_world_pos("left")
	var shoulder_muzzle: Vector3 = wm.get_muzzle_world_pos("shoulder_left")

	_check(arm_muzzle != Vector3.INF, "Arm muzzle resolved to valid world position (%s)" % str(arm_muzzle))
	_check(shoulder_muzzle != Vector3.INF, "Shoulder muzzle resolved to valid world position (%s)" % str(shoulder_muzzle))
	_check(shoulder_muzzle.y > arm_muzzle.y, "Shoulder muzzle is higher than arm muzzle (%.2fm > %.2fm)" % [shoulder_muzzle.y, arm_muzzle.y])

	# =========================================================================
	# TEST 6: Dual Shoulder Parity (Left + Right Shoulder)
	# =========================================================================
	print("\n-- Test 6: Dual Shoulder Parity (Left + Right) --")
	var right_cannon: WeaponPart = auto_cannon.duplicate()
	wm.shoulder_right = right_cannon
	wm._set_ammo(right_cannon, right_cannon.max_ammo)
	wm._set_ammo(auto_cannon, auto_cannon.max_ammo)
	wm._update_weapon_visuals()
	await get_tree().process_frame

	wm._commit_fire("shoulder_left", auto_cannon)
	wm._commit_fire("shoulder_right", right_cannon)

	_check(wm._get_ammo(auto_cannon) == 29, "Left shoulder fired (30 -> 29)")
	_check(wm._get_ammo(right_cannon) == 29, "Right shoulder fired (30 -> 29)")

	var right_muzzle: Vector3 = wm.get_muzzle_world_pos("shoulder_right")
	_check(right_muzzle != Vector3.INF, "Right shoulder muzzle resolved to valid position (%s)" % str(right_muzzle))
	_check(right_muzzle.x > 0.0 and shoulder_muzzle.x < 0.0, "Left and Right shoulder muzzles are mirrored across X-axis")

	# Clean up
	mecha.queue_free()
	await get_tree().process_frame

	print("\n========================================================")
	if _fails == 0:
		print("ALL SHOULDER FIRING LIFECYCLE PARITY CHECKS PASSED: %d/%d" % [_checks, _checks])
		get_tree().quit(0)
	else:
		printerr("SHOULDER FIRING LIFECYCLE PARITY FAILED: %d errors out of %d checks" % [_fails, _checks])
		get_tree().quit(1)
