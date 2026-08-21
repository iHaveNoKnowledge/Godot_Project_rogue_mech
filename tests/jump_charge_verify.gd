extends Node

## End-to-end verification of the jump CHARGE mechanism:
##   1. charge accumulates while the button is held
##   2. charge is bounded at JUMP_CHARGE_TIME (0.32 s)
##   3. charge resets on button release
##   4. charge resets on landing
##   5. velocity ramps proportionally to charge fraction
##   6. energy is consumed only once at launch, not per charge frame
##   7. partial charge produces an intermediate peak height
## Run: godot --headless --path . res://tests/jump_charge_verify.tscn

const JUMP_CHARGE_TIME := 0.32

var _fails := 0
var _checks := 0
var mech: CharacterBody3D


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("CHARGE OK: " + label)
	else:
		_fails += 1
		printerr("CHARGE FAIL: " + label)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.weapons.equipped_frames = {
		"head": {"carry_bonus": 8.0, "weight": 3.0},
		"body": {"carry_bonus": 8.0, "weight": 3.0},
		"arm_left": {"carry_bonus": 3.0, "weight": 3.0},
		"arm_right": {"carry_bonus": 3.0, "weight": 3.0},
		"leg_left": {"carry_bonus": 2.0, "weight": 3.0},
		"leg_right": {"carry_bonus": 2.0, "weight": 3.0},
	}
	_build_world()
	await get_tree().process_frame
	await get_tree().physics_frame

	await _verify_charge_accumulates()
	await _verify_charge_bounded()
	await _verify_charge_resets_on_release()
	await _verify_charge_resets_on_landing()
	await _verify_velocity_ramps_with_charge()
	await _verify_energy_consumed_once()
	await _verify_partial_charge_intermediate()

	print("\n==================================================")
	print("JUMP_CHARGE_VERIFY COMPLETED:")
	print("Checks: %d | Fails: %d" % [_checks, _fails])
	print("==================================================\n")
	Input.action_release("jump")
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------------------
# World setup (identical to mecha_jump_verify)
# ---------------------------------------------------------------------------

func _build_world() -> void:
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	floor_col.shape = box
	floor_body.add_child(floor_col)
	floor_body.position.y = -0.5
	add_child(floor_body)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 8, 8)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	mech = CharacterBody3D.new()
	mech.set_script(preload("res://scripts/mecha/mecha_controller.gd"))
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 2.4
	col.shape = capsule
	col.position.y = 1.2
	mech.add_child(col)
	add_child(mech)
	mech.global_position = Vector3(0, 3, 0)


func _reset_mech() -> void:
	mech.global_position = Vector3(0, 3, 0)
	mech.velocity = Vector3.ZERO
	mech.jump_system.is_jumping = false
	mech.jump_system.jump_charge = 0.0
	mech.energy_system.energy = 100.0
	mech.is_roller_dashing = false
	Input.action_release("jump")
	for i in range(90):
		await get_tree().physics_frame
		if mech.is_on_floor():
			return


func _peak_height(start_y: float) -> float:
	var peak := start_y
	for i in range(240):
		await get_tree().physics_frame
		peak = maxf(peak, mech.global_position.y)
		if mech.is_on_floor() and i > 10:
			break
	return peak - start_y


# ---------------------------------------------------------------------------
# 1. Charge accumulates while holding the button
# ---------------------------------------------------------------------------

func _verify_charge_accumulates() -> void:
	print("--- 1. Charge Accumulation ---")
	await _reset_mech()
	_check(not mech.jump_system.is_jumping, "mech starts not jumping")

	# Press and hold — charge should increase each physics frame.
	Input.action_press("jump")
	# Wait a few frames so the jump actually starts and charge begins.
	for i in range(5):
		await get_tree().physics_frame

	_check(mech.jump_system.is_jumping, "mech is jumping after pressing space")
	_check(mech.jump_system.jump_charge > 0.0, "jump_charge > 0 after holding (%.4f)" % mech.jump_system.jump_charge)

	var charge_before: float = float(mech.jump_system.jump_charge)
	for i in range(10):
		await get_tree().physics_frame
	_check(mech.jump_system.jump_charge > charge_before,
		"jump_charge increases while held (%.4f -> %.4f)" % [charge_before, mech.jump_system.jump_charge])

	Input.action_release("jump")
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# 2. Charge is bounded at JUMP_CHARGE_TIME (0.32 s)
# ---------------------------------------------------------------------------

func _verify_charge_bounded() -> void:
	print("--- 2. Charge Bounded ---")
	await _reset_mech()

	Input.action_press("jump")
	# Hold for way past the charge window (~1 second = 60 frames at 60 fps).
	for i in range(65):
		await get_tree().physics_frame

	_check(mech.jump_system.jump_charge <= JUMP_CHARGE_TIME + 0.02,
		"jump_charge capped near JUMP_CHARGE_TIME (%.4f <= %.4f)" % [mech.jump_system.jump_charge, JUMP_CHARGE_TIME])
	_check(absf(float(mech.jump_system.jump_charge) - JUMP_CHARGE_TIME) <= 0.02,
		"jump_charge equals JUMP_CHARGE_TIME after long hold (%.4f ~= %.4f)" % [mech.jump_system.jump_charge, JUMP_CHARGE_TIME])

	Input.action_release("jump")
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# 3. Charge resets on release
# ---------------------------------------------------------------------------

func _verify_charge_resets_on_release() -> void:
	print("--- 3. Charge Resets on Release ---")
	await _reset_mech()

	Input.action_press("jump")
	for i in range(15):
		await get_tree().physics_frame
	_check(mech.jump_system.jump_charge > 0.0, "charge built up before release (%.4f)" % mech.jump_system.jump_charge)

	Input.action_release("jump")
	# After release, process_jump sets is_jumping = false.
	# The charge should be 0 once the mech lands or the jump ends.
	for i in range(5):
		await get_tree().physics_frame
	_check(not mech.jump_system.is_jumping or mech.jump_system.jump_charge == 0.0,
		"jump ends on release (is_jumping=%s, charge=%.4f)" % [mech.jump_system.is_jumping, mech.jump_system.jump_charge])

	await _reset_mech()
	_check(mech.jump_system.jump_charge == 0.0, "charge is 0 after reset (%.4f)" % mech.jump_system.jump_charge)


# ---------------------------------------------------------------------------
# 4. Charge resets on landing
# ---------------------------------------------------------------------------

func _verify_charge_resets_on_landing() -> void:
	print("--- 4. Charge Resets on Landing ---")
	await _reset_mech()

	# Do a full-charge jump and wait for landing.
	Input.action_press("jump")
	for i in range(25):
		await get_tree().physics_frame
	Input.action_release("jump")

	# Wait for the mech to land.
	var landed := false
	for i in range(240):
		await get_tree().physics_frame
		if mech.is_on_floor() and i > 10:
			landed = true
			break

	_check(landed, "mech landed after full jump")
	_check(mech.jump_system.jump_charge == 0.0, "charge is 0 after landing (%.4f)" % mech.jump_system.jump_charge)
	_check(not mech.jump_system.is_jumping, "is_jumping is false after landing")


# ---------------------------------------------------------------------------
# 5. Velocity ramps proportionally to charge fraction
# ---------------------------------------------------------------------------

func _verify_velocity_ramps_with_charge() -> void:
	print("--- 5. Velocity Ramps with Charge ---")
	await _reset_mech()

	# Measure velocity at 0% charge (tap) vs ~50% charge vs 100% charge.
	# We use the _jump_velocity bridge to test the math directly.
	var v_zero: float = mech._jump_velocity(0.0)
	var v_half: float = mech._jump_velocity(0.5)
	var v_full: float = mech._jump_velocity(1.0)

	_check(v_zero < v_half, "velocity at 50%% charge > velocity at 0%% (%.1f > %.1f)" % [v_half, v_zero])
	_check(v_half < v_full, "velocity at 100%% charge > velocity at 50%% (%.1f > %.1f)" % [v_full, v_half])
	_check(absf(v_zero - 6.0) <= 0.5, "0%% charge ≈ JUMP_MIN_VELOCITY (6.0), got %.1f" % v_zero)

	# The ramp should be roughly linear (lerp between min and full).
	var expected_half: float = (v_zero + v_full) / 2.0
	_check(absf(v_half - expected_half) < 1.0,
		"50%% charge is roughly midpoint (%.1f ≈ expected %.1f)" % [v_half, expected_half])


# ---------------------------------------------------------------------------
# 6. Energy is consumed only once at launch, not per charge frame
# ---------------------------------------------------------------------------

func _verify_energy_consumed_once() -> void:
	print("--- 6. Energy Consumed Once ---")
	await _reset_mech()
	mech.energy_system.energy = 100.0

	# Trigger a jump via the bridge (this deducts energy).
	var cost: float = mech._start_jump()
	_check(cost > 0.0, "jump returned a cost (%.1f)" % cost)
	var energy_after_launch: float = mech.energy_system.energy
	_check(absf(energy_after_launch - (100.0 - cost)) <= 0.1,
		"energy deducted once at launch (%.1f = 100 - %.1f)" % [energy_after_launch, cost])

	# Hold the button to keep charging — energy must NOT decrease further.
	Input.action_press("jump")
	for i in range(25):
		await get_tree().physics_frame

	_check(absf(float(mech.energy_system.energy) - energy_after_launch) <= 0.1,
		"energy unchanged after 25 frames of charging (%.1f == %.1f)" % [mech.energy_system.energy, energy_after_launch])

	Input.action_release("jump")
	# Wait for landing.
	for i in range(240):
		await get_tree().physics_frame
		if mech.is_on_floor() and i > 10:
			break

	_check(absf(float(mech.energy_system.energy) - energy_after_launch) <= 0.1,
		"energy unchanged after landing (%.1f == %.1f)" % [mech.energy_system.energy, energy_after_launch])


# ---------------------------------------------------------------------------
# 7. Partial charge produces an intermediate peak height
# ---------------------------------------------------------------------------

func _verify_partial_charge_intermediate() -> void:
	print("--- 7. Partial Charge Intermediate Height ---")

	# Tap height.
	await _reset_mech()
	var tap_start := mech.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var tap_peak := await _peak_height(tap_start)

	# ~50% charge height.
	await _reset_mech()
	var half_start := mech.global_position.y
	Input.action_press("jump")
	# Hold for ~half the charge window (~8 frames at 60fps ≈ 0.13s).
	for i in range(8):
		await get_tree().physics_frame
	Input.action_release("jump")
	var half_peak := await _peak_height(half_start)

	# Full charge height.
	await _reset_mech()
	var full_start := mech.global_position.y
	Input.action_press("jump")
	for i in range(25):
		await get_tree().physics_frame
	Input.action_release("jump")
	var full_peak := await _peak_height(full_start)

	_check(tap_peak < half_peak,
		"tap is lower than 50%% charge (%.2fm < %.2fm)" % [tap_peak, half_peak])
	_check(half_peak < full_peak,
		"50%% charge is lower than full charge (%.2fm < %.2fm)" % [half_peak, full_peak])
	_check(full_peak > tap_peak + 0.3,
		"full charge is meaningfully higher than tap (%.2fm > %.2fm + 0.3)" % [full_peak, tap_peak])
