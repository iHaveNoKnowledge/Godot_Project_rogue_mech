class_name MechaWalkingSystem
extends Node
## -----------------------------------------------------------------------
## MECHA WALKING SYSTEM - reusable omni-directional 8-way procedural gait.
##
## Features full directional stepping:
##   - Local velocity decomposition for 8-way directional strides.
##   - Hip swivel (yaw), forward/reverse pitch, and lateral hip abduction (roll).
##   - Natural knee flexion and weight-shifting torso bank.
##   - Footstep and lift audio placed along the exact movement vector.
## -----------------------------------------------------------------------

# --- Walk / sprint state ---
var bob_timer: float = 0.0
var _prev_bob_timer: float = 0.0
var is_moving: bool = false


## Given a gait phase in [0, TAU], returns { "thigh": float, "shin": float }
## representing the angular targets (radians) for one leg at that phase.
static func calc_sprint_leg(phase: float) -> Dictionary:
	var thigh := 0.0
	var shin := 0.0

	var norm_phase := fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# Swing Phase (leg airborne, BACK -> FRONT)
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
		# Stance / Push-Off Phase (foot on ground, FRONT -> BACK)
		var t := (norm_phase - PI) / PI
		var s_thigh := 0.5 - 0.5 * cos(t * PI)
		thigh = lerp(deg_to_rad(46.0), -deg_to_rad(58.0), s_thigh)

		if t <= 0.4:
			var s := 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(26.0), -deg_to_rad(36.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(36.0), -deg_to_rad(6.0), s)

	return { "thigh": thigh, "shin": shin }


## Drives torso bob, forward sprint lean, and lateral banking based on movement direction.
func update_bob(delta: float, mecha: CharacterBody3D, joints: Dictionary,
		bob_amount: float) -> float:
	var is_skating: bool = mecha.get("is_roller_dashing") == true
	if is_moving and not is_skating:
		var local_vel: Vector3 = mecha.global_transform.basis.inverse() * mecha.velocity
		local_vel.y = 0.0
		var speed: float = local_vel.length()
		var run_speed: float = clampf(speed * 1.35, 3.0, 16.0)
		_prev_bob_timer = bob_timer
		bob_timer += delta * run_speed
		var bob: float = sin(bob_timer) * bob_amount

		var fwd_ratio: float = clampf(-local_vel.z / maxf(speed, 0.1), -1.0, 1.0)
		var side_ratio: float = clampf(local_vel.x / maxf(speed, 0.1), -1.0, 1.0)

		var target_pitch := -deg_to_rad(18.0) * fwd_ratio
		var target_bank := -deg_to_rad(7.0) * side_ratio

		var body_mesh: Node3D = joints.get("body_mesh")
		var head_mesh: Node3D = joints.get("head_mesh")
		var orig_body: Vector3 = joints.get("original_body_pos", Vector3.ZERO)
		var orig_head: Vector3 = joints.get("original_head_pos", Vector3.ZERO)

		if body_mesh:
			body_mesh.position.y = orig_body.y + absf(bob) * 0.35
			body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, target_pitch, 10.0 * delta)
			body_mesh.rotation.z = lerp_angle(body_mesh.rotation.z, target_bank, 10.0 * delta)
		if head_mesh:
			head_mesh.position = orig_head + Vector3(0, absf(bob) * 0.35, 0)
			head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, target_pitch * 0.6, 10.0 * delta)
			head_mesh.rotation.z = lerp_angle(head_mesh.rotation.z, -target_bank * 0.5, 10.0 * delta)
		return bob
	else:
		if not is_skating:
			bob_timer = 0.0
		var body_mesh: Node3D = joints.get("body_mesh")
		if body_mesh:
			body_mesh.rotation.z = lerp_angle(body_mesh.rotation.z, 0.0, 8.0 * delta)
	return 0.0


## Applies 8-directional procedural leg stepping (hip swivel, lateral abduction, and knee flexion).
func update_legs(delta: float, mecha: CharacterBody3D, joints: Dictionary) -> void:
	var is_skating: bool = mecha.get("is_roller_dashing") == true
	if is_skating:
		return

	var leg_left: Node3D = joints.get("leg_left")
	var leg_right: Node3D = joints.get("leg_right")
	var orig_leg_left: Vector3 = joints.get("original_leg_left_pos", Vector3.ZERO)
	var orig_leg_right: Vector3 = joints.get("original_leg_right_pos", Vector3.ZERO)

	if leg_left:
		leg_left.position.y = lerp(leg_left.position.y, orig_leg_left.y, 6.0 * delta)
	if leg_right:
		leg_right.position.y = lerp(leg_right.position.y, orig_leg_right.y, 6.0 * delta)

	if not (leg_left and leg_right):
		return

	if not is_moving:
		# Ease legs back to neutral stance when stopped
		leg_left.rotation.x = lerp_angle(leg_left.rotation.x, 0.0, 8.0 * delta)
		leg_left.rotation.y = lerp_angle(leg_left.rotation.y, 0.0, 8.0 * delta)
		leg_left.rotation.z = lerp_angle(leg_left.rotation.z, 0.0, 8.0 * delta)
		leg_right.rotation.x = lerp_angle(leg_right.rotation.x, 0.0, 8.0 * delta)
		leg_right.rotation.y = lerp_angle(leg_right.rotation.y, 0.0, 8.0 * delta)
		leg_right.rotation.z = lerp_angle(leg_right.rotation.z, 0.0, 8.0 * delta)
		return

	# Deconstruct local velocity into 8-directional components
	var local_vel: Vector3 = mecha.global_transform.basis.inverse() * mecha.velocity
	local_vel.y = 0.0
	var speed: float = local_vel.length()
	if speed < 0.1:
		return

	var fwd_ratio: float = clampf(-local_vel.z / speed, -1.0, 1.0)
	var side_ratio: float = clampf(local_vel.x / speed, -1.0, 1.0)
	var move_angle: float = atan2(local_vel.x, -local_vel.z)

	# Phases for alternating left/right gait
	var phase_left: float = fmod(bob_timer * 0.5, TAU)
	var phase_right: float = fmod(bob_timer * 0.5 + PI, TAU)

	var left_data: Dictionary = calc_sprint_leg(phase_left)
	var right_data: Dictionary = calc_sprint_leg(phase_right)

	var thigh_l: float = left_data["thigh"]
	var shin_l: float = left_data["shin"]
	var thigh_r: float = right_data["thigh"]
	var shin_r: float = right_data["shin"]

	# 1. Hip Swivel (Yaw - aligns leg heading towards direction of movement)
	var hip_swivel := clampf(move_angle * 0.65, -deg_to_rad(60.0), deg_to_rad(60.0))

	# 2. Forward/Reverse Pitch (X-axis)
	var pitch_l := thigh_l * fwd_ratio
	var pitch_r := thigh_r * fwd_ratio

	# 3. Lateral Hip Abduction / Side Stepping Roll (Z-axis)
	var lateral_l := side_ratio * (thigh_l * 0.50)
	var lateral_r := side_ratio * (thigh_r * 0.50)

	# Apply smoothly to leg joints
	leg_left.rotation.x = pitch_l
	leg_left.rotation.y = lerp_angle(leg_left.rotation.y, hip_swivel, 12.0 * delta)
	leg_left.rotation.z = lerp_angle(leg_left.rotation.z, lateral_l, 12.0 * delta)

	leg_right.rotation.x = pitch_r
	leg_right.rotation.y = lerp_angle(leg_right.rotation.y, hip_swivel, 12.0 * delta)
	leg_right.rotation.z = lerp_angle(leg_right.rotation.z, lateral_r, 12.0 * delta)

	# Knee flexion (Shins)
	var shin_left: Node3D = joints.get("shin_left")
	var shin_right: Node3D = joints.get("shin_right")
	if shin_left:
		shin_left.rotation.x = shin_l
	if shin_right:
		shin_right.rotation.x = shin_r

	# Footstep audio positioned in the actual direction of motion
	var prev_step_idx := int((_prev_bob_timer * 0.5) / PI)
	var cur_step_idx := int((bob_timer * 0.5) / PI)
	if cur_step_idx > prev_step_idx and mecha.is_on_floor():
		var is_left_land: bool = (cur_step_idx % 2 == 1)
		var land_offset_x := -0.45 if is_left_land else 0.45
		var step_dir := local_vel.normalized()
		var land_pos: Vector3 = mecha.global_position + mecha.global_transform.basis * (Vector3(land_offset_x, 0.0, 0.0) + step_dir * 0.3)
		if AudioManager:
			AudioManager.play_footstep(land_pos)
			AudioManager.play_step_lift(land_pos - mecha.global_transform.basis * (step_dir * 0.3))

	# Arm pumping (counter-balances directional stride)
	var arm_left: Node3D = joints.get("arm_left")
	var arm_right: Node3D = joints.get("arm_right")
	var forearm_left: Node3D = joints.get("forearm_left")
	var forearm_right: Node3D = joints.get("forearm_right")

	if arm_left:
		arm_left.rotation.x = -pitch_l * 0.75
		if forearm_left:
			forearm_left.rotation.x = deg_to_rad(55.0) + absf(sin(phase_left)) * deg_to_rad(20.0)
	if arm_right:
		arm_right.rotation.x = -pitch_r * 0.75
		if forearm_right:
			forearm_right.rotation.x = deg_to_rad(55.0) + absf(sin(phase_right)) * deg_to_rad(20.0)


## Scans the standard mecha rig node paths and returns a joints dictionary.
static func build_joints(mecha: Node3D) -> Dictionary:
	var j: Dictionary = {}
	j["body_mesh"] = mecha.get_node_or_null("Body")
	j["head_mesh"] = mecha.get_node_or_null("Head")
	j["arm_left"] = mecha.get_node_or_null("ArmLeft")
	j["arm_right"] = mecha.get_node_or_null("ArmRight")
	j["forearm_left"] = mecha.get_node_or_null("ArmLeft/ForearmLeft")
	j["forearm_right"] = mecha.get_node_or_null("ArmRight/ForearmRight")
	j["leg_left"] = mecha.get_node_or_null("LegLeft")
	j["leg_right"] = mecha.get_node_or_null("LegRight")
	j["shin_left"] = mecha.get_node_or_null("LegLeft/ShinLeft")
	j["shin_right"] = mecha.get_node_or_null("LegRight/ShinRight")

	if j["body_mesh"]:
		j["original_body_pos"] = j["body_mesh"].position
	if j["head_mesh"]:
		j["original_head_pos"] = j["head_mesh"].position
	if j["leg_left"]:
		j["original_leg_left_pos"] = j["leg_left"].position
	if j["leg_right"]:
		j["original_leg_right_pos"] = j["leg_right"].position

	return j
