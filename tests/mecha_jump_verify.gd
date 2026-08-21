extends Node

## Verifies the new Mech Jump & Mid-Air Thruster Glide System:
## 1. Ground Jump: Tap/press Space on ground launches immediately to full jump height (no charging needed).
## 2. Mid-Air Thruster Glide: Press/Hold Space while mid-air engages thrusters, slowing fall to a gentle glide.
## 3. Leg power, mass penalty, dash cooldown, and roller dash mechanics.
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

	_verify_dash_cooldown()
	_verify_jump_energy_cost()
	_verify_momentum_launch()
	_verify_leg_power_scaling()
	_verify_weight_penalty()
	await _verify_instant_full_jump()
	await _verify_midair_thruster_glide()
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
	cam.current = true
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
	_check(mech.dash_system.can_dash(100.0), "dash available with energy")
	_check(not mech.dash_system.can_dash(2.0), "dash refuses with low energy (< 6.0)")


func _verify_jump_energy_cost() -> void:
	mech.total_weight = 50.0
	mech.energy_system.energy = 100.0
	mech._start_jump()
	_check(is_equal_approx(mech.energy_system.energy, 89.5), "50kg mech pays 10.5 energy to jump")
	mech.jump_system.is_jumping = false
	mech.velocity = Vector3.ZERO

	mech.total_weight = 100.0
	mech.energy_system.energy = 100.0
	mech._start_jump()
	_check(is_equal_approx(mech.energy_system.energy, 87.0), "100kg mech pays 13 energy to jump (heavier = pricier)")
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
	mech.velocity = Vector3.ZERO
	var stand: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	mech.velocity = Vector3(20, 0, 0)
	mech.jump_system.velocity_ref = mech.velocity
	var sprint: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	_check(sprint > stand, "jump with momentum launches higher than standing (%.1f > %.1f)" % [sprint, stand])


func _verify_leg_power_scaling() -> void:
	mech.velocity = Vector3.ZERO
	mech.jump_system.velocity_ref = Vector3.ZERO
	var weak_full: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	GlobalData.weapons.equipped_frames["leg_left"] = {"carry_bonus": 6.0, "weight": 3.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"carry_bonus": 6.0, "weight": 3.0}
	var strong_full: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	_check(strong_full > weak_full, "stronger leg frames jump higher (%.1f > %.1f)" % [strong_full, weak_full])

	# A special gundam-class leg frame declaring its own jump_power leaps beyond standard curve
	GlobalData.weapons.equipped_frames["leg_left"] = {"carry_bonus": 3.0, "jump_power": 25.0, "weight": 3.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"carry_bonus": 3.0, "jump_power": 25.0, "weight": 3.0}
	var gundam_full: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	_check(gundam_full > strong_full + 5.0, "a special frame's jump_power leaps higher than normal legs (%.1f > %.1f)" % [gundam_full, strong_full])

	# Restore standard legs
	GlobalData.weapons.equipped_frames["leg_left"] = {"carry_bonus": 6.0, "weight": 3.0}
	GlobalData.weapons.equipped_frames["leg_right"] = {"carry_bonus": 6.0, "weight": 3.0}


func _verify_weight_penalty() -> void:
	mech.velocity = Vector3.ZERO
	mech.jump_system.velocity_ref = Vector3.ZERO
	mech.jump_system.total_weight = 30.0
	var light: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	mech.jump_system.total_weight = 120.0
	var heavy: float = mech.jump_system._calculate_jump_velocity(Vector3.ZERO)
	_check(heavy < light, "heavier mechs launch lower (%.1f < %.1f)" % [heavy, light])
	mech.jump_system.total_weight = 50.0


func _reset_mech() -> void:
	mech.global_position = Vector3(0, 1.2, 0)
	mech.velocity = Vector3.ZERO
	mech.jump_system.is_jumping = false
	mech.jump_system.is_gliding = false
	mech.energy_system.energy = 100.0
	mech.dash_system.is_dashing = false
	Input.action_release("jump")
	Input.action_release("move_forward")
	for i in range(30):
		await get_tree().physics_frame
		if mech.is_on_floor():
			return


func _peak_height(start_y: float) -> float:
	var peak := start_y
	for i in range(240):
		await get_tree().physics_frame
		peak = maxf(peak, mech.global_position.y)
		if mech.is_on_floor() and i > 15:
			break
	return peak - start_y


func _verify_instant_full_jump() -> void:
	await _reset_mech()
	var start_y: float = mech.global_position.y
	mech._start_jump()
	var jump_peak := await _peak_height(start_y)
	_check(jump_peak > 3.0, "ground jump launches instantly to full height (%.2f m > 3.0m)" % jump_peak)


func _verify_midair_thruster_glide() -> void:
	await _reset_mech()
	# Jump into air first
	mech._start_jump()
	
	# Wait until reaching apex of jump / starting to fall
	for i in range(40):
		await get_tree().physics_frame

	_check(not mech.is_on_floor(), "mech is currently in mid-air")

	# Engage thruster glide while in mid-air
	mech.jump_system.is_gliding = true
	var energy_before: float = float(mech.energy_system.energy)
	for i in range(20):
		await get_tree().physics_frame

	_check(mech.velocity.y >= -3.5, "thruster glide cushions downward fall (vel_y=%.2f m/s >= -3.5)" % mech.velocity.y)
	_check(mech.energy_system.energy < energy_before, "thruster glide consumes energy smoothly over time (energy=%.1f < %.1f)" % [mech.energy_system.energy, energy_before])

	mech.jump_system.is_gliding = false
	await _reset_mech()


func _verify_midair_dash() -> void:
	await _reset_mech()
	mech._start_jump()
	for i in range(8):
		await get_tree().physics_frame
	_check(not mech.is_on_floor(), "mech is airborne before dash")
	mech._start_dash()
	_check(mech.dash_system.is_dashing, "dash fires successfully while airborne")
	await _reset_mech()


func _verify_roller_energy() -> void:
	await _reset_mech()
	mech.is_roller_dashing = true
	mech.input_dir = Vector2.ZERO
	for i in range(20):
		await get_tree().physics_frame
	_check(is_equal_approx(mech.energy_system.energy, 100.0),
		"roller dash standing still drains NO energy")
	mech.is_roller_dashing = false


func _verify_midair_roller() -> void:
	await _reset_mech()
	mech._start_jump()
	mech.is_roller_dashing = true
	for i in range(15):
		await get_tree().physics_frame
	_check(not mech.is_roller_dashing, "airborne state cancelled roller dash")
	await _reset_mech()
