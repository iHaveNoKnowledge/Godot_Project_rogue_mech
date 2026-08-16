extends Node

## Verifies the reworked mech jump + dash tuning:
##   - jump launches with current momentum: horizontal speed raises the launch
##     velocity (faster = higher fling), horizontal control unaffected
##   - variable height: a quick tap is a low hop; holding space drives the
##     ascent up to full power, which scales with the equipped leg frames
##   - launching costs energy scaled by carried mass (heavier = more energy)
##     and refuses when the tank is too low
##   - dash cooldown is halved (0.5s) and dash still fires mid-air
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
	await _verify_variable_height()
	await _verify_midair_dash()

	print("MECHA_JUMP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	Input.action_release("jump")
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
	cam.position = Vector3(0, 8, 8)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)

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
	mech.energy = 100.0
	mech._start_jump()
	_check(is_equal_approx(mech.energy, 91.0), "50kg mech pays 9 energy to jump")
	mech.is_jumping = false
	mech.velocity = Vector3.ZERO

	mech.total_weight = 100.0
	mech.energy = 100.0
	mech._start_jump()
	_check(is_equal_approx(mech.energy, 88.0), "100kg mech pays 12 energy to jump (heavier = pricier)")
	mech.is_jumping = false
	mech.velocity = Vector3.ZERO

	# Too drained to launch: the jump is refused and no energy is spent.
	mech.energy = 5.0
	mech._start_jump()
	_check(mech.velocity.y == 0.0 and is_equal_approx(mech.energy, 5.0),
		"jump refuses when the tank is too low")

	mech.is_jumping = false
	mech.energy = 100.0


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


# --- Physics integration: tap vs hold height ---------------------------------

func _reset_mech() -> void:
	mech.global_position = Vector3(0, 3, 0)
	mech.velocity = Vector3.ZERO
	mech.is_jumping = false
	mech.jump_charge = 0.0
	mech.energy = 100.0
	mech.dash_cooldown_timer = 0.0
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


func _verify_variable_height() -> void:
	# Tap: press then release on the very next frame -> a low hop.
	await _reset_mech()
	var tap_start: float = mech.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var tap_peak := await _peak_height(tap_start)

	# Hold: keep the button down for ~0.33s (the full charge window) -> a real
	# jump whose peak is measured from the same ground position.
	await _reset_mech()
	var hold_start: float = mech.global_position.y
	Input.action_press("jump")
	for i in range(20):
		await get_tree().physics_frame
	Input.action_release("jump")
	var hold_peak := await _peak_height(hold_start)

	_check(tap_peak < 1.5, "a quick tap is a low hop (%.2f m)" % tap_peak)
	_check(hold_peak > tap_peak + 0.5, "holding the button jumps clearly higher (%.2f m vs %.2f m)" % [hold_peak, tap_peak])


func _verify_midair_dash() -> void:
	# Float the mech airborne (no floor contact) and dash — it must still fire.
	mech.global_position = Vector3(0, 8, 0)
	mech.velocity = Vector3(0, 2, 0)
	mech.energy = 100.0
	await get_tree().physics_frame
	_check(not mech.is_on_floor(), "mech is airborne for the mid-air dash check")
	mech._start_dash()
	_check(mech.is_dashing, "dash fires mid-air to steer momentum")
	mech.is_dashing = false
