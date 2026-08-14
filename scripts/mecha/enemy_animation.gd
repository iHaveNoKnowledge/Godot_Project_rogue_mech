extends Node

## Enemy walk/run animation: swings the mech legs (thigh + shin) with the same
## sprint-stride math the player's mecha_animation.gd uses, driven by the
## enemy's own velocity. Attached by enemy_dummy.gd after its slot nodes exist.

var mecha: CharacterBody3D = null

var leg_left: Node3D = null
var leg_right: Node3D = null
var shin_left: Node3D = null
var shin_right: Node3D = null
var arm_left: Node3D = null
var arm_right: Node3D = null
var forearm_left: Node3D = null
var forearm_right: Node3D = null

var bob_timer: float = 0.0
var is_moving: bool = false


func _ready() -> void:
	mecha = get_parent() as CharacterBody3D
	leg_left = get_node_or_null("../LegLeft")
	leg_right = get_node_or_null("../LegRight")
	shin_left = get_node_or_null("../LegLeft/ShinLeft")
	shin_right = get_node_or_null("../LegRight/ShinRight")
	arm_left = get_node_or_null("../ArmLeft")
	arm_right = get_node_or_null("../ArmRight")
	forearm_left = get_node_or_null("../ArmLeft/ForearmLeft")
	forearm_right = get_node_or_null("../ArmRight/ForearmRight")


func _physics_process(delta: float) -> void:
	if mecha == null:
		return

	var is_on_ground := mecha.is_on_floor()
	var speed := Vector2(mecha.velocity.x, mecha.velocity.z).length()
	is_moving = is_on_ground and speed > 0.8

	if is_moving:
		var run_speed := clampf(speed * 1.4, 7.0, 14.0)
		bob_timer += delta * run_speed
		_update_legs(delta)
	else:
		bob_timer = 0.0
		_lerp_to_neutral(delta)


# Same stride cycle as the player mech: opposite legs swing through a swing
# (airborne, back->front) then stance (ground, front->back) phase while the
# arms pump against the legs for a grounded sprinting read.
func _update_legs(delta: float) -> void:
	if leg_left == null or leg_right == null:
		return

	var fwd_vel := -mecha.global_transform.basis.z.dot(mecha.velocity)
	var dir_sign := 1.0 if fwd_vel >= -0.2 else -1.0

	var phase_left := fmod(bob_timer * 0.5, TAU)
	var phase_right := fmod(bob_timer * 0.5 + PI, TAU)

	var left_leg_data := _calc_mecha_sprint_leg(phase_left)
	var right_leg_data := _calc_mecha_sprint_leg(phase_right)

	var thigh_l: float = left_leg_data["thigh"]
	var shin_l: float = left_leg_data["shin"]
	var thigh_r: float = right_leg_data["thigh"]
	var shin_r: float = right_leg_data["shin"]

	leg_left.rotation.x = thigh_l * dir_sign
	leg_right.rotation.x = thigh_r * dir_sign

	if shin_left: shin_left.rotation.x = shin_l
	if shin_right: shin_right.rotation.x = shin_r

	# Athletic arm pumping: bent elbows swinging opposite to the legs.
	if arm_left:
		arm_left.rotation.x = -thigh_l * 0.75 * dir_sign
		if forearm_left:
			forearm_left.rotation.x = deg_to_rad(55.0) + abs(sin(phase_left)) * deg_to_rad(20.0)
	if arm_right:
		arm_right.rotation.x = -thigh_r * 0.75 * dir_sign
		if forearm_right:
			forearm_right.rotation.x = deg_to_rad(55.0) + abs(sin(phase_right)) * deg_to_rad(20.0)


func _lerp_to_neutral(delta: float) -> void:
	var speed := 6.0 * delta
	if leg_left: leg_left.rotation = leg_left.rotation.lerp(Vector3.ZERO, speed)
	if leg_right: leg_right.rotation = leg_right.rotation.lerp(Vector3.ZERO, speed)
	if shin_left: shin_left.rotation = shin_left.rotation.lerp(Vector3.ZERO, speed)
	if shin_right: shin_right.rotation = shin_right.rotation.lerp(Vector3.ZERO, speed)
	if arm_left: arm_left.rotation = arm_left.rotation.lerp(Vector3.ZERO, speed)
	if arm_right: arm_right.rotation = arm_right.rotation.lerp(Vector3.ZERO, speed)
	if forearm_left: forearm_left.rotation = forearm_left.rotation.lerp(Vector3.ZERO, speed)
	if forearm_right: forearm_right.rotation = forearm_right.rotation.lerp(Vector3.ZERO, speed)


# 3D mecha long-stride sprint cycle shared with mecha_animation.gd (player).
func _calc_mecha_sprint_leg(phase: float) -> Dictionary:
	var thigh = 0.0
	var shin = 0.0

	var norm_phase := fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# Swing Phase (leg airborne, swinging from back to front)
		var t := norm_phase / PI

		if t <= 0.8:
			var s := 0.5 - 0.5 * cos((t / 0.8) * PI)
			thigh = lerp(-deg_to_rad(58.0), deg_to_rad(64.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.8) / 0.2) * PI)
			thigh = lerp(deg_to_rad(64.0), deg_to_rad(46.0), s)

		if t <= 0.4:
			var s := 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(10.0), -deg_to_rad(85.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(85.0), -deg_to_rad(26.0), s)
	else:
		# Stance / Power Push-Off Phase (leg on ground, driving front to back)
		var t := (norm_phase - PI) / PI

		var s_thigh := 0.5 - 0.5 * cos(t * PI)
		thigh = lerp(deg_to_rad(46.0), -deg_to_rad(58.0), s_thigh)

		if t <= 0.4:
			var s := 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(26.0), -deg_to_rad(36.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(36.0), -deg_to_rad(6.0), s)

	return {"thigh": thigh, "shin": shin}