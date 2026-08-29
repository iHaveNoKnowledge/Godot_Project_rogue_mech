class_name MechaWalkingSystem
extends Node
## -----------------------------------------------------------------------
## MECHA WALKING SYSTEM - reusable omni-directional 8-way procedural gait.
##
## Features full directional stepping:
##   - Local velocity decomposition for 8-way directional strides.
##   - Decoupled pelvis / hip swivel (yaw up to ±60°) and lateral hip abduction (roll).
##   - Dedicated forward sprint and reverse backpedal gait cycles with natural knee flexion.
##   - Dynamic side-step lift and weight-shifting torso banking/pitch.
##   - Directional footstep and lift 3D audio positioned along the movement vector.
## -----------------------------------------------------------------------

# --- Walk / sprint state ---
var bob_timer: float = 0.0
var _prev_bob_timer: float = 0.0
var is_moving: bool = false


## Given a forward gait phase in [0, TAU], returns { "thigh": float, "shin": float, "lift": float }
## representing the angular targets (radians) and step lift for one leg.
static func calc_sprint_leg(phase: float) -> Dictionary:
	var thigh := 0.0
	var shin := 0.0
	var lift := 0.0

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

		lift = sin(t * PI) * 0.18
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

		lift = 0.0

	return { "thigh": thigh, "shin": shin, "lift": lift }


## Given a reverse gait phase in [0, TAU], returns { "thigh": float, "shin": float, "lift": float }
## for backpedaling strides. Ensures knees naturally flex backwards without hyperextension.
static func calc_reverse_leg(phase: float) -> Dictionary:
	var thigh := 0.0
	var shin := 0.0
	var lift := 0.0

	var norm_phase := fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# Swing Phase (leg airborne, FRONT -> BACK)
		var t := norm_phase / PI
		if t <= 0.7:
			var s := 0.5 - 0.5 * cos((t / 0.7) * PI)
			thigh = lerp(deg_to_rad(38.0), -deg_to_rad(52.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.7) / 0.3) * PI)
			thigh = lerp(-deg_to_rad(52.0), -deg_to_rad(40.0), s)

		# Knee flexes backwards to lift foot during rearward stride
		if t <= 0.5:
			var s := 0.5 - 0.5 * cos((t / 0.5) * PI)
			shin = lerp(-deg_to_rad(12.0), -deg_to_rad(75.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.5) / 0.5) * PI)
			shin = lerp(-deg_to_rad(75.0), -deg_to_rad(22.0), s)

		lift = sin(t * PI) * 0.16
	else:
		# Stance / Push-Off Phase (foot on ground, BACK -> FRONT)
		var t := (norm_phase - PI) / PI
		var s_thigh := 0.5 - 0.5 * cos(t * PI)
		thigh = lerp(-deg_to_rad(40.0), deg_to_rad(38.0), s_thigh)

		if t <= 0.5:
			var s := 0.5 - 0.5 * cos((t / 0.5) * PI)
			shin = lerp(-deg_to_rad(22.0), -deg_to_rad(32.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.5) / 0.5) * PI)
			shin = lerp(-deg_to_rad(32.0), -deg_to_rad(12.0), s)

		lift = 0.0

	return { "thigh": thigh, "shin": shin, "lift": lift }


## Given a strafe gait phase in [0, TAU], returns { "roll": float, "shin": float, "lift": float }
## for lateral side-stepping strides.
static func calc_strafe_leg(phase: float, is_outward_leg: bool) -> Dictionary:
	var roll := 0.0
	var shin := 0.0
	var lift := 0.0

	var norm_phase := fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# Swing Phase (leg airborne, stepping out/in)
		var t := norm_phase / PI
		var s := 0.5 - 0.5 * cos(t * PI)
		var max_roll := deg_to_rad(22.0) if is_outward_leg else deg_to_rad(12.0)
		roll = s * max_roll
		shin = lerp(-deg_to_rad(10.0), -deg_to_rad(45.0), s)
		lift = sin(t * PI) * 0.20
	else:
		# Stance Phase (leg on ground supporting lateral shift)
		var t := (norm_phase - PI) / PI
		var s := 0.5 - 0.5 * cos(t * PI)
		var max_roll := deg_to_rad(6.0) if is_outward_leg else deg_to_rad(2.0)
		roll = lerp(max_roll, 0.0, s)
		shin = lerp(-deg_to_rad(15.0), -deg_to_rad(6.0), s)
		lift = 0.0

	return { "roll": roll, "shin": shin, "lift": lift }


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

		# Forward lean when sprinting forward; slight counter-pitch when backpedaling
		var target_pitch: float
		if fwd_ratio >= 0.0:
			target_pitch = -deg_to_rad(18.0) * fwd_ratio
		else:
			target_pitch = deg_to_rad(10.0) * (-fwd_ratio)

		# Lateral banking: torso rolls into the strafe/slide
		var target_bank := -deg_to_rad(8.5) * side_ratio

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


## Applies 8-directional procedural leg stepping (hip swivel, lateral abduction, step lift, and knee flexion).
func update_legs(delta: float, mecha: CharacterBody3D, joints: Dictionary) -> void:
	var is_skating: bool = mecha.get("is_roller_dashing") == true
	if is_skating:
		return

	var leg_left: Node3D = joints.get("leg_left")
	var leg_right: Node3D = joints.get("leg_right")
	var orig_leg_left: Vector3 = joints.get("original_leg_left_pos", Vector3.ZERO)
	var orig_leg_right: Vector3 = joints.get("original_leg_right_pos", Vector3.ZERO)

	if not (leg_left and leg_right):
		return

	if not is_moving:
		# Ease legs back to neutral stance when stopped
		leg_left.position.y = lerp(leg_left.position.y, orig_leg_left.y, 8.0 * delta)
		leg_right.position.y = lerp(leg_right.position.y, orig_leg_right.y, 8.0 * delta)
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

	# 1. Forward or Reverse longitudinal stride
	var fwd_weight := maxf(fwd_ratio, 0.0)
	var rev_weight := maxf(-fwd_ratio, 0.0)
	var side_weight := absf(side_ratio)

	var fwd_left := calc_sprint_leg(phase_left)
	var fwd_right := calc_sprint_leg(phase_right)
	var rev_left := calc_reverse_leg(phase_left)
	var rev_right := calc_reverse_leg(phase_right)

	# Calculate longitudinal pitch & longitudinal shin flexion
	var pitch_l: float = float(fwd_left["thigh"]) * fwd_weight + float(rev_left["thigh"]) * rev_weight
	var pitch_r: float = float(fwd_right["thigh"]) * fwd_weight + float(rev_right["thigh"]) * rev_weight
	var long_shin_l: float = float(fwd_left["shin"]) * fwd_weight + float(rev_left["shin"]) * rev_weight
	var long_shin_r: float = float(fwd_right["shin"]) * fwd_weight + float(rev_right["shin"]) * rev_weight
	var long_lift_l: float = float(fwd_left["lift"]) * fwd_weight + float(rev_left["lift"]) * rev_weight
	var long_lift_r: float = float(fwd_right["lift"]) * fwd_weight + float(rev_right["lift"]) * rev_weight

	# 2. Lateral strafe stride & side-step lift
	var is_strafe_right := side_ratio > 0.0
	var strafe_left := calc_strafe_leg(phase_left, not is_strafe_right)
	var strafe_right := calc_strafe_leg(phase_right, is_strafe_right)

	# Lateral roll: side_ratio already gives sign, roll is magnitude (outward leg larger)
	var lateral_l: float = side_ratio * float(strafe_left["roll"])
	var lateral_r: float = side_ratio * float(strafe_right["roll"])
	var lat_shin_l: float = float(strafe_left["shin"])
	var lat_shin_r: float = float(strafe_right["shin"])
	var lat_lift_l: float = float(strafe_left["lift"])
	var lat_lift_r: float = float(strafe_right["lift"])

	# Blend longitudinal and lateral components — keep full amplitude for diagonal (don't halve pitch)
	var total_weight := maxf(fwd_weight + rev_weight + side_weight, 0.001)
	var long_norm := (fwd_weight + rev_weight) / total_weight
	var side_norm := side_weight / total_weight
	var target_pitch_l: float = pitch_l
	var target_pitch_r: float = pitch_r
	var target_shin_l: float = long_shin_l * long_norm + lat_shin_l * side_norm
	var target_shin_r: float = long_shin_r * long_norm + lat_shin_r * side_norm
	var total_lift_l: float = long_lift_l * long_norm + lat_lift_l * side_norm
	var total_lift_r: float = long_lift_r * long_norm + lat_lift_r * side_norm
	# Scale side roll/lift with speed so strafe at full speed doesn't look like slow shuffle
	var speed_scale := clampf(speed / 5.0, 0.75, 1.35)
	lateral_l *= speed_scale
	lateral_r *= speed_scale
	total_lift_l *= speed_scale
	total_lift_r *= speed_scale

	# 3. Decoupled Pelvis Hip Swivel (Yaw - aligns leg heading towards stride direction up to ±45°)
	# For forward motion, align relative to forward; for backward motion, align relative to backward.
	var move_heading: float
	if fwd_ratio >= 0.0:
		move_heading = atan2(local_vel.x, -local_vel.z)
	else:
		move_heading = atan2(local_vel.x, local_vel.z)
	var hip_swivel := clampf(move_heading * 0.60, -deg_to_rad(45.0), deg_to_rad(45.0))

	# Apply smoothly to leg joints
	leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_pitch_l, 14.0 * delta)
	leg_left.rotation.y = lerp_angle(leg_left.rotation.y, hip_swivel, 12.0 * delta)
	leg_left.rotation.z = lerp_angle(leg_left.rotation.z, lateral_l, 12.0 * delta)
	leg_left.position.y = lerp(leg_left.position.y, orig_leg_left.y + total_lift_l, 14.0 * delta)

	leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_pitch_r, 14.0 * delta)
	leg_right.rotation.y = lerp_angle(leg_right.rotation.y, hip_swivel, 12.0 * delta)
	leg_right.rotation.z = lerp_angle(leg_right.rotation.z, lateral_r, 12.0 * delta)
	leg_right.position.y = lerp(leg_right.position.y, orig_leg_right.y + total_lift_r, 14.0 * delta)

	# Knee flexion (Shins)
	var shin_left: Node3D = joints.get("shin_left")
	var shin_right: Node3D = joints.get("shin_right")
	if shin_left:
		shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin_l, 16.0 * delta)
	if shin_right:
		shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin_r, 16.0 * delta)

	# Footstep audio positioned in the actual direction of motion
	var prev_step_idx := int((_prev_bob_timer * 0.5) / PI)
	var cur_step_idx := int((bob_timer * 0.5) / PI)
	if cur_step_idx > prev_step_idx and mecha.is_on_floor():
		var is_left_land: bool = (cur_step_idx % 2 == 1)
		var land_offset_x := -0.45 if is_left_land else 0.45
		var step_dir := local_vel.normalized()
		var land_pos: Vector3 = mecha.global_position + mecha.global_transform.basis * (Vector3(land_offset_x, 0.0, 0.0) + step_dir * 0.3)
		var audio_mgr: Node = mecha.get_node_or_null("/root/AudioManager")
		if audio_mgr:
			if audio_mgr.has_method("play_footstep"):
				audio_mgr.play_footstep(land_pos)
			if audio_mgr.has_method("play_step_lift"):
				audio_mgr.play_step_lift(land_pos - mecha.global_transform.basis * (step_dir * 0.3))

	# Arm pumping (counter-balances directional stride)
	var arm_left: Node3D = joints.get("arm_left")
	var arm_right: Node3D = joints.get("arm_right")
	var forearm_left: Node3D = joints.get("forearm_left")
	var forearm_right: Node3D = joints.get("forearm_right")

	if arm_left:
		arm_left.rotation.x = -target_pitch_l * 0.75
		if forearm_left:
			forearm_left.rotation.x = deg_to_rad(55.0) + absf(sin(phase_left)) * deg_to_rad(20.0)
	if arm_right:
		arm_right.rotation.x = -target_pitch_r * 0.75
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
