class_name MechaWalkingSystem
extends Node
## -----------------------------------------------------------------------
## MECHA WALKING SYSTEM — reusable walk / sprint animation primitives.
##
## Extracted from mecha_animation.gd so the same leg-cycle math, bob state,
## and limb-update helpers can be shared by the player mech, allies, and
## enemies without duplicating the procedural walk animation code.
##
## Usage:
##   var walk := MechaWalkingSystem.new()
##   add_child(walk)                       # or compose via reference
##   walk.update(delta, mecha, joints)     # drives bob + legs each frame
## -----------------------------------------------------------------------

# ── Walk / sprint state ────────────────────────────────────────────────
## Accumulated phase timer — drives the sinusoidal leg cycle and bob.
var bob_timer: float = 0.0
var _prev_bob_timer: float = 0.0
## True when the mech is in contact with the ground and moving fast enough
## to animate a walk / sprint cycle.
var is_moving: bool = false


# ── Pure calculation (no node dependencies) ────────────────────────────
## Given a gait phase in [0, TAU], returns { "thigh": float, "shin": float }
## representing the angular targets (radians) for one leg at that phase.
##
## The cycle is split into:
##   [0, PI)   — Swing phase  (leg airborne, swinging back → front)
##   [PI, TAU) — Stance phase (foot on ground, driving body forward)
##
## Angle ranges (designed for a wide, powerful mecha stride):
##   Thigh:  -58° … +64°  (swing)  →  +46° … -58°  (stance)
##   Shin:   -10° … -85°  (fold)   →  -26° … -6°   (extend)
static func calc_sprint_leg(phase: float) -> Dictionary:
	var thigh := 0.0
	var shin := 0.0

	var norm_phase := fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# ── Swing Phase (leg airborne, BACK → FRONT) ──
		var t := norm_phase / PI

		# Thigh: -58° → +64° (t in [0, 0.8]), then +64° → +46° (t in [0.8, 1.0])
		if t <= 0.8:
			var s := 0.5 - 0.5 * cos((t / 0.8) * PI)
			thigh = lerp(-deg_to_rad(58.0), deg_to_rad(64.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.8) / 0.2) * PI)
			thigh = lerp(deg_to_rad(64.0), deg_to_rad(46.0), s)

		# Shin: -10° → -85° (t in [0, 0.4]), then -85° → -26° (t in [0.4, 1.0])
		if t <= 0.4:
			var s := 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(10.0), -deg_to_rad(85.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(85.0), -deg_to_rad(26.0), s)
	else:
		# ── Stance / Push-Off Phase (foot on ground, FRONT → BACK) ──
		var t := (norm_phase - PI) / PI

		# Thigh: +46° → -58° (smooth push-off)
		var s_thigh := 0.5 - 0.5 * cos(t * PI)
		thigh = lerp(deg_to_rad(46.0), -deg_to_rad(58.0), s_thigh)

		# Shin: -26° → -36° (load absorption, t in [0, 0.4]),
		#       -36° → -6°  (propulsive extension, t in [0.4, 1.0])
		if t <= 0.4:
			var s := 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(26.0), -deg_to_rad(36.0), s)
		else:
			var s := 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(36.0), -deg_to_rad(6.0), s)

	return { "thigh": thigh, "shin": shin }


# ── Joint container ────────────────────────────────────────────────────
## Dictionary of Node3D references passed to update functions.
## Keys: body_mesh, head_mesh, arm_left, arm_right, forearm_left,
##        forearm_right, leg_left, leg_right, shin_left, shin_right
## Optional keys: original_body_pos (Vector3), original_head_pos (Vector3)


# ── Bob / sprint-lean update ──────────────────────────────────────────
## Drives the torso bob and forward sprint lean while moving.
## Returns the computed `bob` value so callers can reuse it.
func update_bob(delta: float, mecha: CharacterBody3D, joints: Dictionary,
		bob_amount: float) -> float:
	var is_skating: bool = mecha.get("is_roller_dashing") == true
	if is_moving and not is_skating:
		var run_speed: float = mecha.velocity.length() * 1.4
		_prev_bob_timer = bob_timer
		bob_timer += delta * clamp(run_speed, 7.0, 14.0)
		var bob: float = sin(bob_timer) * bob_amount

		var sprint_lean := -deg_to_rad(18.0)
		var body_mesh: Node3D = joints.get("body_mesh")
		var head_mesh: Node3D = joints.get("head_mesh")
		var orig_body: Vector3 = joints.get("original_body_pos", Vector3.ZERO)
		var orig_head: Vector3 = joints.get("original_head_pos", Vector3.ZERO)

		if body_mesh:
			body_mesh.position.y = orig_body.y + abs(bob) * 0.35
			body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, sprint_lean, 10.0 * delta)
		if head_mesh:
			head_mesh.position = orig_head + Vector3(0, abs(bob) * 0.35, 0)
			head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, sprint_lean, 10.0 * delta)
		return bob
	else:
		if not is_skating:
			bob_timer = 0.0
	return 0.0


# ── Leg-cycle + arm-pump update ───────────────────────────────────────
## Applies the procedural sprint leg animation (thigh/shin rotation and
## opposite-phase arm pumping) to the supplied joint nodes.
func update_legs(delta: float, mecha: CharacterBody3D, joints: Dictionary) -> void:
	var is_skating: bool = mecha.get("is_roller_dashing") == true
	if is_skating:
		return

	var leg_left: Node3D = joints.get("leg_left")
	var leg_right: Node3D = joints.get("leg_right")
	var orig_leg_left: Vector3 = joints.get("original_leg_left_pos", Vector3.ZERO)
	var orig_leg_right: Vector3 = joints.get("original_leg_right_pos", Vector3.ZERO)

	# Ease leg roots back to neutral (only kneel ever moves them).
	if leg_left:
		leg_left.position.y = lerp(leg_left.position.y, orig_leg_left.y, 6.0 * delta)
	if leg_right:
		leg_right.position.y = lerp(leg_right.position.y, orig_leg_right.y, 6.0 * delta)

	if not is_moving:
		return

	if not (leg_left and leg_right):
		return

	# Forward velocity sign — flips for reverse walking.
	var fwd_vel: float = -mecha.global_transform.basis.z.dot(mecha.velocity)
	var dir_sign: float = 1.0 if fwd_vel >= -0.2 else -1.0

	# Phases: legs are offset by PI (one swings while the other pushes).
	var phase_left: float = fmod(bob_timer * 0.5, TAU)
	var phase_right: float = fmod(bob_timer * 0.5 + PI, TAU)

	var left_data: Dictionary = calc_sprint_leg(phase_left)
	var right_data: Dictionary = calc_sprint_leg(phase_right)

	var thigh_l: float = left_data["thigh"]
	var shin_l: float = left_data["shin"]
	var thigh_r: float = right_data["thigh"]
	var shin_r: float = right_data["shin"]

	# ── Apply thigh + shin rotations ──
	leg_left.rotation.x = thigh_l * dir_sign
	leg_right.rotation.x = thigh_r * dir_sign

	# ── 100% Exact Animation-Driven Footstep Audio Trigger ──
	# Left foot enters ground stance at odd multiples of PI.
	# Right foot enters ground stance at even multiples of PI.
	var prev_step_idx := int((_prev_bob_timer * 0.5) / PI)
	var cur_step_idx := int((bob_timer * 0.5) / PI)
	if cur_step_idx > prev_step_idx and mecha.is_on_floor():
		var is_left_step: bool = (cur_step_idx % 2 == 1)
		var foot_offset_x := -0.45 if is_left_step else 0.45
		var foot_pos: Vector3 = mecha.global_position + mecha.global_transform.basis * Vector3(foot_offset_x, 0.0, 0.2)
		if AudioManager:
			AudioManager.play_footstep(foot_pos)

	var shin_left: Node3D = joints.get("shin_left")
	var shin_right: Node3D = joints.get("shin_right")
	if shin_left:
		shin_left.rotation.x = shin_l
	if shin_right:
		shin_right.rotation.x = shin_r

	# ── Arm pumping (opposite phase to legs, bent elbows) ──
	var arm_left: Node3D = joints.get("arm_left")
	var arm_right: Node3D = joints.get("arm_right")
	var forearm_left: Node3D = joints.get("forearm_left")
	var forearm_right: Node3D = joints.get("forearm_right")

	if arm_left:
		arm_left.rotation.x = -thigh_l * 0.75 * dir_sign
		if forearm_left:
			forearm_left.rotation.x = deg_to_rad(55.0) + abs(sin(phase_left)) * deg_to_rad(20.0)
	if arm_right:
		arm_right.rotation.x = -thigh_r * 0.75 * dir_sign
		if forearm_right:
			forearm_right.rotation.x = deg_to_rad(55.0) + abs(sin(phase_right)) * deg_to_rad(20.0)


# ── Convenience: build joints dict from a mecha root ──────────────────
## Scans the standard mecha rig node paths and returns a joints dictionary
## suitable for update_bob() / update_legs().  Returns only non-null refs.
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
