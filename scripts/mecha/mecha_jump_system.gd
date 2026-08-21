extends Node

## ---------------------------------------------------------------------------
## MECHA JUMP SYSTEM — Dual-Mode Jump Architecture:
## 1. PRE_JUMP_CHARGE (Base Standard Mode):
##    - Hydraulic leg compression springs.
##    - Tap: instant low hop.
##    - Hold Space: charges spring power while moving/running freely (non-blocking).
##    - Release Space: springs up with height proportional to charge.
##
## 2. JETPACK_THRUSTER (Module / Frame Property Mode):
##    - Active when a thruster attachment (e.g. booster_mk1) or frame/chassis
##      has thruster property enabled.
##    - Press Space: launches instantly from the ground.
##    - Hold Space Mid-Air: sustained thruster burn boosts ascent upward.
## ---------------------------------------------------------------------------

enum JumpMode {
	PRE_JUMP_CHARGE,
	JETPACK_THRUSTER
}

signal jump_charge_changed(charge_ratio: float, is_charging: bool)
signal jump_launched(mode: JumpMode, launch_velocity: float)

const JUMP_CHARGE_TIME := 0.35
const JUMP_RAMP_RATE := 50.0
const JUMP_MIN_VELOCITY := 6.0
const JUMP_MAX_BASE := 6.0
const LEG_POWER_JUMP_BONUS := 0.5
const SPEED_JUMP_BONUS := 0.12
const WEIGHT_JUMP_PENALTY := 4.0
const JUMP_BASE_ENERGY_COST := 6.0
const JUMP_WEIGHT_ENERGY := 0.06

# State for Mid-air Thruster Jump
var is_jumping: bool = false
var jump_charge: float = 0.0

# State for Base Pre-Jump Charge
var is_charging_prejump: bool = false
var prejump_charge_time: float = 0.0

var velocity_ref: Vector3 = Vector3.ZERO
var total_weight: float = 0.0
var chassis_weight_capacity: float = 75.0

# Manual override or test property (if null, dynamically checks loadout)
var thruster_override: Variant = null


func has_thruster_module() -> bool:
	if thruster_override != null:
		return bool(thruster_override)
	# 1. Check attachments for booster / thruster modules
	for att in GlobalData.weapons.attachments:
		if att is Dictionary:
			var aid: String = str(att.get("id", "")).to_lower()
			var atype: String = str(att.get("type", "")).to_lower()
			if aid.contains("booster") or aid.contains("thruster") or atype == "thruster" or atype == "booster" or bool(att.get("has_thruster", false)):
				return true
	# 2. Check equipped frames
	for slot in GlobalData.weapons.equipped_frames:
		var f = GlobalData.weapons.equipped_frames[slot]
		if f is Dictionary and (bool(f.get("has_thruster", false)) or str(f.get("jump_mode", "")) == "thruster"):
			return true
	# 3. Check chassis
	var stats = LoadoutSystem.get_chassis_stats() if LoadoutSystem else {}
	if bool(stats.get("has_thruster", false)) or str(stats.get("jump_mode", "")) == "thruster":
		return true
	return false


func get_active_jump_mode() -> JumpMode:
	return JumpMode.JETPACK_THRUSTER if has_thruster_module() else JumpMode.PRE_JUMP_CHARGE


## Pre-Jump: Start charging when Spacebar is pressed on the floor
func start_prejump_charge() -> void:
	is_charging_prejump = true
	prejump_charge_time = 0.0
	jump_charge_changed.emit(0.0, true)


## Pre-Jump: Tick charge time while holding Spacebar
func tick_prejump_charge(delta: float, is_on_floor: bool) -> void:
	if not is_charging_prejump:
		return
	if not is_on_floor:
		cancel_prejump_charge()
		return
	prejump_charge_time = minf(prejump_charge_time + delta, JUMP_CHARGE_TIME)
	var ratio := clampf(prejump_charge_time / JUMP_CHARGE_TIME, 0.0, 1.0)
	jump_charge_changed.emit(ratio, true)


## Pre-Jump: Release Spacebar to spring up into the air
func release_prejump(energy: float, pos: Vector3, current_vel: Vector3 = Vector3.ZERO) -> float:
	if not is_charging_prejump:
		return 0.0
	var charge_ratio := clampf(prejump_charge_time / JUMP_CHARGE_TIME, 0.0, 1.0)
	cancel_prejump_charge()

	var cost := JUMP_BASE_ENERGY_COST + total_weight * JUMP_WEIGHT_ENERGY
	if energy < cost:
		return 0.0

	velocity_ref = current_vel
	var launch_vel := _jump_velocity(charge_ratio, pos)
	velocity_ref.y = launch_vel
	jump_launched.emit(JumpMode.PRE_JUMP_CHARGE, launch_vel)
	return cost


## Cancel prejump charge
func cancel_prejump_charge() -> void:
	if is_charging_prejump:
		is_charging_prejump = false
		prejump_charge_time = 0.0
		jump_charge_changed.emit(0.0, false)


## Thruster: Start instant launch from ground
func start_jump(energy: float, pos: Vector3, current_vel: Vector3 = Vector3.ZERO) -> float:
	var cost := JUMP_BASE_ENERGY_COST + total_weight * JUMP_WEIGHT_ENERGY
	if energy < cost:
		return 0.0
	jump_charge = 0.0
	is_jumping = true
	velocity_ref = current_vel
	velocity_ref.y = _jump_velocity(0.0, pos)
	jump_launched.emit(JumpMode.JETPACK_THRUSTER, velocity_ref.y)
	return cost


## Thruster: Process mid-air continuous thruster acceleration while Space is held
func process_jump(delta: float, is_on_floor: bool, current_vel_y: float) -> float:
	if is_jumping:
		if Input.is_action_pressed("jump") and jump_charge < JUMP_CHARGE_TIME:
			jump_charge = minf(jump_charge + delta, JUMP_CHARGE_TIME)
			var target := _jump_velocity(jump_charge / JUMP_CHARGE_TIME, Vector3.ZERO)
			if current_vel_y < target:
				current_vel_y = move_toward(current_vel_y, target, JUMP_RAMP_RATE * delta)
				velocity_ref.y = current_vel_y
		else:
			is_jumping = false
	if is_on_floor and jump_charge > 0.08:
		is_jumping = false
		jump_charge = 0.0
	return current_vel_y


func _jump_velocity(charge_frac: float, pos: Vector3 = Vector3.ZERO) -> float:
	var leg_power := _leg_jump_power()
	var speed_bonus := Vector3(velocity_ref.x, 0.0, velocity_ref.z).length() * SPEED_JUMP_BONUS
	var weight_ratio := clampf(total_weight / maxf(chassis_weight_capacity, 1.0), 0.0, 1.0)
	var full := JUMP_MAX_BASE + leg_power * LEG_POWER_JUMP_BONUS \
			- weight_ratio * WEIGHT_JUMP_PENALTY + speed_bonus
	return lerp(JUMP_MIN_VELOCITY, full, charge_frac)


func _leg_jump_power() -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	for leg in ["leg_left", "leg_right"]:
		var f = GlobalData.weapons.equipped_frames.get(leg, {})
		if f is Dictionary:
			power += float(f.get("jump_power", f.get("carry_bonus", 0.0)))
	return power
