extends Node

## ---------------------------------------------------------------------------
## MECHA JUMP SYSTEM — variable-height jump with charge, momentum, and weight
## scaling.  Extracted from mecha_controller.gd for single-responsibility.
##
## The launch is a single impulse: holding the button charges the ascent power
## up to JUMP_CHARGE_TIME; releasing early locks in a lower hop.  Once the
## charge window is spent, gravity arcs the mech back down — holding forever
## never lets the mech float.
## ---------------------------------------------------------------------------

const JUMP_CHARGE_TIME := 0.32
const JUMP_RAMP_RATE := 50.0
const JUMP_MIN_VELOCITY := 6.0
const JUMP_MAX_BASE := 6.0
const LEG_POWER_JUMP_BONUS := 0.5
const SPEED_JUMP_BONUS := 0.12
const WEIGHT_JUMP_PENALTY := 4.0
const JUMP_BASE_ENERGY_COST := 6.0
const JUMP_WEIGHT_ENERGY := 0.06

var is_jumping: bool = false
var jump_charge: float = 0.0

## Must be set by the parent controller before calling process().
## The controller owns these values; the jump system only reads them.
var velocity_ref: Vector3 = Vector3.ZERO  ## Will be mutated in-place by the controller.
var total_weight: float = 0.0
var chassis_weight_capacity: float = 75.0


func start_jump(energy: float, pos: Vector3) -> float:
	## Returns the energy cost (caller subtracts from its pool).
	## Mutates velocity_ref.y on launch.
	var cost := JUMP_BASE_ENERGY_COST + total_weight * JUMP_WEIGHT_ENERGY
	if energy < cost:
		return 0.0
	jump_charge = 0.0
	is_jumping = true
	velocity_ref.y = _jump_velocity(0.0, pos)
	return cost


func process_jump(delta: float, is_on_floor: bool) -> void:
	if is_jumping:
		if Input.is_action_pressed("jump") and jump_charge < JUMP_CHARGE_TIME:
			jump_charge = minf(jump_charge + delta, JUMP_CHARGE_TIME)
			var target := _jump_velocity(jump_charge / JUMP_CHARGE_TIME, Vector3.ZERO)
			if velocity_ref.y < target:
				velocity_ref.y = move_toward(velocity_ref.y, target, JUMP_RAMP_RATE * delta)
		else:
			is_jumping = false
	if is_on_floor:
		is_jumping = false
		jump_charge = 0.0


func _jump_velocity(charge_frac: float, pos: Vector3) -> float:
	var leg_power := _leg_jump_power()
	var speed_bonus := Vector3(velocity_ref.x, 0.0, velocity_ref.z).length() * SPEED_JUMP_BONUS
	var weight_ratio := clampf(total_weight / maxf(chassis_weight_capacity, 1.0), 0.0, 1.0)
	var full := JUMP_MAX_BASE + leg_power * LEG_POWER_JUMP_BONUS \
			- weight_ratio * WEIGHT_JUMP_PENALTY + speed_bonus
	return lerp(JUMP_MIN_VELOCITY, full, charge_frac)


func _leg_jump_power() -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	for leg in ["leg_left", "leg_right"]:
		var f = GlobalData.equipped_frames.get(leg, {})
		if f is Dictionary:
			power += float(f.get("jump_power", f.get("carry_bonus", 0.0)))
	return power
