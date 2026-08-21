extends Node

## Verifies the mech jump + dash + roller tuning:
##   - jump launches with current momentum; a tap is a low hop, holding charges
##     up to the frame's full jump power (leg power + special jump_power stat)
##   - the launch is BOUNDED: once charged the mech arcs down under gravity, so
##     holding forever never floats; heavier mechs launch lower
##   - launching costs energy scaled by carried mass and refuses when drained
##   - dash cooldown is halved (0.5s) and dash still fires mid-air
##   - roller dash is a GROUND mode: no energy drain while standing still, no
##     air speed boost mid-air, and jumping cuts the roller out
## Run: godot --headless --path . res://tests/mecha_jump_verify.tscn

var _fails := 0
var _checks := 0
var mech: CharacterBody3D


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("JUMP OK: " + name)
	else:
		_fails += 1
		printerr("JUMP FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	# Deterministic leg frames so get_leg_power() is controllable: weak legs
	# (carry_bonus 2 each) vs strong legs (carry_bonus 6 each).
	GlobalData.equipped_frames = {
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

	_verify_dash_cooldown()
	_verify_jump_energy_cost()
	_verify_momentum_launch()
	_verify_leg_power_scaling()
	_verify_weight_penalty()
	await _verify_prejump_mode()
	await _verify_thruster_jump_mode()
	await _verify_midair_dash()
	await _verify_roller_energy()
	await _verify_midair_roller()

	print("MECHA_JUMP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	Input.action_release("jump")
	Input.action_release("move_forward")
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _build_world() -> void:
	# Floor for the mech to stand on.
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	floor_col.shape = box
	floor_body.add_child(floor_col)
	floor_body.position.y = -0.5
	add_child(floor_body)

	# A camera so _apply_movement doesn't bail early (headless has none by default).
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 8, 8)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	# Bare mech with the real controller script + a capsule body.
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


func _verify_dash_cooldown() -> void:
	_check(is_equal_approx(mech.dash_cooldown, 0.5), "dash cooldown halved to 0.5s")


func _verify_jump_energy_cost() -> void:
	# Cost = base 6 + total_weight * 0.06.
	mech.total_weight = 50.0
	mech.energy_system.energy = 100.0
	mech._start_jump()
	_check(is_equal_approx(mech.energy_system.energy, 91.0), "50kg mech pays 9 energy to jump")
	mech.jump_system.is_jumping = false
	mech.velocity = Vector3.ZERO

	mech.total_weight = 100.0
	mech.energy_system.energy = 100.0
	mech._start_jump()
	_check(is_equal_approx(mech.energy_system.energy, 88.0), "100kg mech pays 12 energy to jump (heavier = pricier)")
	mech.jump_system.is_jumping = false
	mech.velocity = Vector3.ZERO

	# Too drained to launch: the jump is refused and no energy is spent.
	mech.energy_system.energy = 5.0
	mech._start_jump()
	_check(mech.velocity.y == 0.0 and is_equal_approx(mech.energy_system.energy, 5.0),
		"jump refuses when the tank is too low")

	mech.jump_system.is_jumping = false
	mech.energy_system.energy = 100.0


func _verify_momentum_launch() -> void:
	# Same legs, same charge: moving fast flings higher than standing still.
	mech.velocity = Vector3.ZERO
	var stand: float = mech._jump_velocity(1.0)
	mech.velocity = Vector3(20, 0, 0)
	var sprint: float = mech._jump_velocity(1.0)
	_check(sprint > stand, "full jump with momentum launches higher than standing (%.1f > %.1f)" % [sprint, stand])


func _verify_leg_power_scaling() -> void:
	# Tap (charge 0) is the same low hop for any legs; full charge scales up
	# with leg-frame power.
	var weak_full: float = mech._jump_velocity(1.0)
	var weak_tap: float = mech._jump_velocity(0.0)
	GlobalData.equipped_frames["leg_left"] = {"carry_bonus": 6.0, "weight": 3.0}
	GlobalData.equipped_frames["leg_right"] = {"carry_bonus": 6.0, "weight": 3.0}
	var strong_full: float = mech._jump_velocity(1.0)
	var strong_tap: float = mech._jump_velocity(0.0)
	_check(is_equal_approx(weak_tap, strong_tap), "tap is a low hop regardless of leg power")
	_check(strong_full > weak_full, "stronger leg frames jump higher at full power (%.1f > %.1f)" % [strong_full, weak_full])

	# A special gundam-class leg frame declaring its own jump_power leaps beyond
	# the standard carry_bonus curve — the hook for exotic frames.
	var normal_full: float = mech._jump_velocity(1.0)
	GlobalData.equipped_frames["leg_left"] = {"carry_bonus": 3.0, "jump_power": 25.0, "weight": 3.0}
	GlobalData.equipped_frames["leg_right"] = {"carry_bonus": 3.0, "jump_power": 25.0, "weight": 3.0}
	var gundam_full: float = mech._jump_velocity(1.0)
	_check(gundam_full > normal_full + 5.0, "a special frame's jump_power leaps higher than normal legs (%.1f > %.1f)" % [gundam_full, normal_full])
	# Restore the strong standard legs for the physics tests.
	GlobalData.equipped_frames["leg_left"] = {"carry_bonus": 6.0, "weight": 3.0}
	GlobalData.equipped_frames["leg_right"] = {"carry_bonus": 6.0, "weight": 3.0}


func _verify_weight_penalty() -> void:
	# Same legs, same speed: carried mass eats into the launch velocity.
	mech.velocity = Vector3.ZERO
	mech.total_weight = 30.0
	var light: float = mech._jump_velocity(1.0)
	mech.total_weight = 120.0
	var heavy: float = mech._jump_velocity(1.0)
	_check(heavy < light, "heavier mechs launch lower (%.1f < %.1f)" % [heavy, light])
	mech.total_weight = 50.0


# --- Physics integration: Pre-Jump vs Thruster Jump -------------------------

func _reset_mech() -> void:
	mech.global_position = Vector3(0, 3, 0)
	mech.velocity = Vector3.ZERO
	mech.jump_system.is_jumping = false
	mech.jump_system.jump_charge = 0.0
	mech.energy_system.energy = 100.0
	mech.dash_cooldown_timer = 0.0
	Input.action_release("jump")
	Input.action_release("move_forward")
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


func _verify_prejump_mode() -> void:
	# Base mode: no thruster module equipped
	GlobalData.attachments.clear()
	mech._jump.thruster_override = false
	_check(mech._jump.get_active_jump_mode() == mech._jump.JumpMode.PRE_JUMP_CHARGE, "base mode active without thruster module")

	# 1. Tap: press and immediate release -> low hop
	await _reset_mech()
	var tap_start: float = mech.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var tap_peak := await _peak_height(tap_start)
	_check(tap_peak < 1.5, "pre-jump tap is a low hop (%.2f m)" % tap_peak)

	# 2. Charge & Run simultaneously (Non-blocking): hold space and press move_forward
	await _reset_mech()
	Input.action_press("jump")
	Input.action_press("move_forward")
	for i in range(15):
		await get_tree().physics_frame
	_check(mech.is_charging_prejump, "pre-jump charge accumulates while moving")
	_check(Vector3(mech.velocity.x, 0.0, mech.velocity.z).length() > 1.0, "movement is NOT blocked while charging pre-jump")

	# Release space to spring launch!
	var hold_start: float = mech.global_position.y
	Input.action_release("jump")
	Input.action_release("move_forward")
	var hold_peak := await _peak_height(hold_start)
	_check(hold_peak > tap_peak + 1.0, "releasing charged pre-jump springs significantly higher (%.2f m vs %.2f m)" % [hold_peak, tap_peak])


func _verify_thruster_jump_mode() -> void:
	# Equip booster_mk1 attachment to activate Jetpack Thruster mode
	GlobalData.attachments = [{"id": "booster_mk1", "name": "Thrust Booster MK-I", "type": "thruster"}]
	mech._jump.thruster_override = true
	_check(mech._jump.has_thruster_module(), "thruster module detected from loadout")
	_check(mech._jump.get_active_jump_mode() == mech._jump.JumpMode.JETPACK_THRUSTER, "jetpack thruster mode active when module equipped")

	# 1. Tap in thruster mode: launches immediately on press
	await _reset_mech()
	var start_y: float = mech.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var thrust_tap_peak := await _peak_height(start_y)
	_check(thrust_tap_peak > 0.5 and thrust_tap_peak < 1.5, "thruster jump tap launches a low hop (%.2f m)" % thrust_tap_peak)

	# 2. Hold in thruster mode: mid-air sustained burn boosts higher
	await _reset_mech()
	var hold_start_y: float = mech.global_position.y
	Input.action_press("jump")
	for i in range(25):
		await get_tree().physics_frame
	Input.action_release("jump")
	var thrust_hold_peak := await _peak_height(hold_start_y)
	_check(thrust_hold_peak > thrust_tap_peak + 0.5, "holding space in thruster mode gives sustained boost (%.2f m vs %.2f m)" % [thrust_hold_peak, thrust_tap_peak])

	# Reset override
	mech._jump.thruster_override = null
	GlobalData.attachments.clear()


func _verify_midair_dash() -> void:
	# Float the mech airborne (no floor contact) and dash — it must still fire.
	mech.global_position = Vector3(0, 8, 0)
	mech.velocity = Vector3(0, 2, 0)
	mech.energy_system.energy = 100.0
	await get_tree().physics_frame
	_check(not mech.is_on_floor(), "mech is airborne for the mid-air dash check")
	mech._start_dash()
	_check(mech.is_dashing, "dash fires mid-air to steer momentum")
	mech.is_dashing = false


func _settle_on_floor() -> void:
	mech.global_position = Vector3(0, 3, 0)
	mech.velocity = Vector3.ZERO
	mech.jump_system.is_jumping = false
	mech.jump_system.jump_charge = 0.0
	mech.is_charging_prejump = false
	mech.is_roller_dashing = false
	mech.energy_system.energy = 100.0
	Input.action_release("jump")
	Input.action_release("roller_dash")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	for i in range(90):
		await get_tree().physics_frame
		if mech.is_on_floor():
			return


func _verify_roller_energy() -> void:
	await _settle_on_floor()

	# With the roller engaged but NO movement input, the pool must not drain
	# (headless Input lingers, so the roller state is set directly here — the
	# drain gate is what this check exercises).
	mech.energy_system.energy = 100.0
	mech.is_roller_dashing = true
	for i in range(30):
		await get_tree().physics_frame
	_check(is_equal_approx(mech.energy_system.energy, 100.0), "standing still with the roller on costs no energy")

	# Rolling while actually moving drains the pool.
	mech.energy_system.energy = 100.0
	mech.is_roller_dashing = true
	Input.action_press("move_forward")
	for i in range(30):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check(mech.energy_system.energy < 99.0, "rolling while moving drains energy")
	mech.is_roller_dashing = false
	mech.velocity = Vector3.ZERO


func _verify_midair_roller() -> void:
	# Roller wheels are a GROUND mode: pressing it mid-air must not engage.
	mech.global_position = Vector3(0, 8, 0)
	mech.velocity = Vector3(0, 2, 0)
	mech.is_roller_dashing = false
	mech.energy_system.energy = 100.0
	await get_tree().physics_frame
	_check(not mech.is_on_floor(), "mech is airborne for the mid-air roller check")
	Input.action_press("roller_dash")
	await get_tree().physics_frame
	Input.action_release("roller_dash")
	_check(not mech.is_roller_dashing, "pressing roller dash mid-air does not engage")

	# A roller running on the ground cuts out the moment the mech leaves it.
	await _settle_on_floor()
	mech.is_roller_dashing = true
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in range(15):
		await get_tree().physics_frame
	_check(not mech.is_roller_dashing, "jumping cuts the roller out (no air speed boost)")
	mech.is_roller_dashing = false
