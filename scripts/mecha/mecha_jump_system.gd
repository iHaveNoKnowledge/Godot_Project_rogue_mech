extends Node

## ---------------------------------------------------------------------------
## MECHA JUMP & THRUSTER GLIDE SYSTEM:
## 1. Ground Jump:
##    - Press Space on the floor -> Launches immediately at full jump height!
## 2. Mid-Air Thruster Glide / Slow Fall:
##    - Press/Hold Space while mid-air -> Engages thruster hover mode,
##      drastically slowing descent and gliding smoothly through the air
##      (consumes energy steadily while active).
## ---------------------------------------------------------------------------

signal jump_launched(launch_velocity: float)
signal glide_state_changed(is_gliding: bool)

# Jump launch tuning
const JUMP_LAUNCH_BASE := 9.0
const LEG_POWER_JUMP_BONUS := 0.55
const SPEED_JUMP_BONUS := 0.15
const WEIGHT_JUMP_PENALTY := 3.5
const JUMP_BASE_ENERGY_COST := 8.0
const JUMP_WEIGHT_ENERGY := 0.05

# Thruster Glide / Slow-Fall (Mid-Air)
const GLIDE_ENERGY_DRAIN := 12.0 # Energy per second
const GLIDE_MAX_FALL_SPEED := -2.5 # Limits downward speed to gentle glide (-2.5 m/s)
const GLIDE_DECEL_RATE := 30.0 # Rapidly cushions fall when thrusters fire

# State
var is_jumping: bool = false
var is_gliding: bool = false
var glide_spark_timer: float = 0.0

# Legacy compatibility fields
var is_charging_prejump: bool = false
var prejump_charge_time: float = 0.0

var velocity_ref: Vector3 = Vector3.ZERO
var total_weight: float = 0.0
var chassis_weight_capacity: float = 75.0


## Launches an instant maximum-height jump from the floor
func start_jump(energy: float, pos: Vector3, current_vel: Vector3 = Vector3.ZERO) -> float:
	var cost := JUMP_BASE_ENERGY_COST + total_weight * JUMP_WEIGHT_ENERGY
	if energy < cost:
		return 0.0
	is_jumping = true
	is_gliding = false
	velocity_ref = current_vel
	var launch_vel := _calculate_jump_velocity(pos)
	velocity_ref.y = launch_vel
	jump_launched.emit(launch_vel)
	return cost


## Calculates the full launch velocity based on leg power, movement momentum, and weight
func _calculate_jump_velocity(pos: Vector3 = Vector3.ZERO) -> float:
	var leg_power := _leg_jump_power()
	var speed_bonus := Vector3(velocity_ref.x, 0.0, velocity_ref.z).length() * SPEED_JUMP_BONUS
	var weight_ratio := clampf(total_weight / maxf(chassis_weight_capacity, 1.0), 0.0, 1.0)
	return JUMP_LAUNCH_BASE + leg_power * LEG_POWER_JUMP_BONUS - weight_ratio * WEIGHT_JUMP_PENALTY + speed_bonus


## Applies thruster glide to slow down downward falling speed
func process_glide(delta: float, current_vel_y: float) -> float:
	if current_vel_y < GLIDE_MAX_FALL_SPEED:
		current_vel_y = move_toward(current_vel_y, GLIDE_MAX_FALL_SPEED, GLIDE_DECEL_RATE * delta)
	return current_vel_y


## Spawns thruster exhaust VFX while gliding
func tick_glide_vfx(delta: float, tree: SceneTree, pos: Vector3) -> void:
	glide_spark_timer -= delta
	if glide_spark_timer <= 0.0:
		glide_spark_timer = 0.06
		var left_thruster := pos + Vector3(-0.45, 0.2, 0.25)
		var right_thruster := pos + Vector3(0.45, 0.2, 0.25)
		EffectFactory.spawn_box_spark(tree, left_thruster, Vector3(0.12, 0.25, 0.12), Color(0.35, 0.75, 1.0), 0.12, 3.5)
		EffectFactory.spawn_box_spark(tree, right_thruster, Vector3(0.12, 0.25, 0.12), Color(0.35, 0.75, 1.0), 0.12, 3.5)


func _leg_jump_power() -> float:
	var power := float(LoadoutSystem.get_chassis_stats().get("power", 12.0))
	for leg in ["leg_left", "leg_right"]:
		var f = GlobalData.weapons.equipped_frames.get(leg, {})
		if f is Dictionary:
			power += float(f.get("jump_power", f.get("carry_bonus", 0.0)))
	return power
