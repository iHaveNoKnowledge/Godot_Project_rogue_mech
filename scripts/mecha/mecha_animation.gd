extends Node

@export var bob_amount: float = 0.15
@export var bob_speed: float = 14.0
@export var recoil_amount: float = 0.3
@export var recoil_recovery: float = 10.0

var mecha: CharacterBody3D = null
var head_mesh: Node3D = null
var body_mesh: Node3D = null
var arm_left: Node3D = null
var arm_right: Node3D = null
var forearm_left: Node3D = null
var forearm_right: Node3D = null
var leg_left: Node3D = null
var leg_right: Node3D = null
var shin_left: Node3D = null
var shin_right: Node3D = null

var bob_timer: float = 0.0
var air_timer: float = 0.0
var is_moving: bool = false
var current_recoil: float = 0.0

var _original_head_pos: Vector3
var _original_body_pos: Vector3
var _original_arm_left_pos: Vector3
var _original_arm_right_pos: Vector3


func _ready() -> void:
	mecha = get_parent()
	head_mesh = get_node_or_null("../Head")
	body_mesh = get_node_or_null("../Body")
	arm_left = get_node_or_null("../ArmLeft")
	arm_right = get_node_or_null("../ArmRight")
	forearm_left = get_node_or_null("../ArmLeft/ForearmLeft")
	forearm_right = get_node_or_null("../ArmRight/ForearmRight")
	leg_left = get_node_or_null("../LegLeft")
	leg_right = get_node_or_null("../LegRight")
	shin_left = get_node_or_null("../LegLeft/ShinLeft")
	shin_right = get_node_or_null("../LegRight/ShinRight")

	if head_mesh:
		_original_head_pos = head_mesh.position
	if body_mesh:
		_original_body_pos = body_mesh.position
	if arm_left:
		_original_arm_left_pos = arm_left.position
	if arm_right:
		_original_arm_right_pos = arm_right.position


func _physics_process(delta: float) -> void:
	if mecha == null:
		return

	_update_recoil(delta)

	var is_on_ground = mecha.is_on_floor()
	var vert_vel = mecha.velocity.y

	is_moving = is_on_ground and mecha.velocity.length() > 0.8

	if not is_on_ground:
		air_timer += delta
		if vert_vel > 0.8:
			_update_jump_posture(delta)
		else:
			_update_airborne_fall_posture(delta)
	else:
		air_timer = 0.0
		var is_skating = mecha.get("is_roller_dashing") == true
		if is_skating:
			_update_roller_dash_posture(delta)
		else:
			_update_bob(delta)
			_update_legs(delta)


func _update_jump_posture(delta: float) -> void:
	var speed = 12.0 * delta

	# Jump Launch Specs (Thrusters firing, upward launch trajectory):
	# 1. Torso pitches slightly back/up (+12 deg) with chest raised
	# 2. Head counter-tilts (-12 deg) to lock eyes forward
	# 3. Legs thrust backward and extend (thighs -38 deg to -45 deg, knees extended -18 deg to -22 deg)
	# 4. Arms trail backward (-20 deg) with forearms bent (+40 deg)
	var target_body_tilt = deg_to_rad(12.0)
	var target_head_tilt = -deg_to_rad(12.0)
	var target_drop = 0.1

	var target_thigh_left = -deg_to_rad(38.0)
	var target_shin_left = -deg_to_rad(18.0)
	var target_thigh_right = -deg_to_rad(45.0)
	var target_shin_right = -deg_to_rad(22.0)

	var target_arm = -deg_to_rad(20.0)
	var target_forearm = deg_to_rad(40.0)

	if body_mesh:
		body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, target_body_tilt, speed)
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y + target_drop, speed)
	if head_mesh:
		head_mesh.position = head_mesh.position.lerp(_original_head_pos + Vector3(0, target_drop, 0), speed)
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, target_head_tilt, speed)

	if arm_left: arm_left.rotation.x = lerp_angle(arm_left.rotation.x, target_arm, speed)
	if arm_right: arm_right.rotation.x = lerp_angle(arm_right.rotation.x, target_arm, speed)

	if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_forearm, speed)
	if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_forearm, speed)

	if leg_left: leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_thigh_left, speed)
	if leg_right: leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_thigh_right, speed)

	if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin_left, speed)
	if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin_right, speed)


func _update_airborne_fall_posture(delta: float) -> void:
	var speed = 8.0 * delta
	var float_sway = sin(air_timer * 4.0) * 0.05

	# Airborne Fall Specs (Freefall / Descent / Gliding from height):
	# 1. Torso pitches forward down (-24 deg) ready for landing impact
	# 2. Head counter-tilts (-10 deg net) looking down/ahead at landing zone
	# 3. Left Leg flexed forward (+32 deg thigh, -55 deg shin knee flex under hip)
	# 4. Right Leg trailing back (-22 deg thigh, -30 deg shin knee flex)
	# 5. Organic floating hover sway applied to body position
	var target_body_tilt = -deg_to_rad(24.0)
	var target_head_tilt = -deg_to_rad(10.0)
	var target_drop = -0.15 + float_sway

	var target_thigh_left = deg_to_rad(32.0)
	var target_shin_left = -deg_to_rad(55.0)
	var target_thigh_right = -deg_to_rad(22.0)
	var target_shin_right = -deg_to_rad(30.0)

	var target_arm_left = -deg_to_rad(15.0)
	var target_arm_right = deg_to_rad(15.0)
	var target_forearm = deg_to_rad(50.0)

	if body_mesh:
		body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, target_body_tilt, speed)
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y + target_drop, speed)
	if head_mesh:
		head_mesh.position = head_mesh.position.lerp(_original_head_pos + Vector3(0, target_drop, 0), speed)
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, target_head_tilt, speed)

	if arm_left: arm_left.rotation.x = lerp_angle(arm_left.rotation.x, target_arm_left, speed)
	if arm_right: arm_right.rotation.x = lerp_angle(arm_right.rotation.x, target_arm_right, speed)

	if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_forearm, speed)
	if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_forearm, speed)

	if leg_left: leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_thigh_left, speed)
	if leg_right: leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_thigh_right, speed)

	if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin_left, speed)
	if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin_right, speed)


func _update_recoil(delta: float) -> void:
	if current_recoil > 0.0:
		current_recoil = move_toward(current_recoil, 0.0, recoil_recovery * delta)
		if head_mesh:
			head_mesh.rotation.x = -current_recoil * 0.5


func _update_roller_dash_posture(delta: float) -> void:
	if mecha and mecha.get("is_roller_dashing") != null:
		var speed = 12.0 * delta
		var is_skating = mecha.is_roller_dashing

		if is_skating:
			# Gundam AGE Symmetrical Roller Skating Dash Stance:
			# 1. Both legs completely equal & parallel on the ground/catapult track
			# 2. Both upper thighs crouched backward (+38 deg)
			# 3. Both lower shins perpendicular to floor (-38 deg cancels thigh tilt)
			# 4. Torso pitched forward down (-28 deg) & Center of gravity dropped (-0.35)
			# 5. Head locked looking straight ahead (-10 deg net)
			# 6. Arms holding weapon and shield in balanced combat posture
			var target_body_tilt = -deg_to_rad(28.0)
			var target_head_tilt = -deg_to_rad(10.0)
			var target_drop = -0.35

			var target_thigh_crouch = deg_to_rad(38.0)
			var target_shin_vertical = -deg_to_rad(38.0)

			var target_arm_right = deg_to_rad(15.0)
			var target_forearm_right = deg_to_rad(70.0)

			var target_arm_left = -deg_to_rad(15.0)
			var target_forearm_left = deg_to_rad(75.0)

			if body_mesh:
				body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, target_body_tilt, speed)
				body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y + target_drop, speed)
			if head_mesh:
				head_mesh.position = _original_head_pos + Vector3(0, target_drop, 0)
				head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, target_head_tilt, speed)

			if arm_left: arm_left.rotation.x = lerp_angle(arm_left.rotation.x, target_arm_left, speed)
			if arm_right: arm_right.rotation.x = lerp_angle(arm_right.rotation.x, target_arm_right, speed)

			if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_forearm_left, speed)
			if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_forearm_right, speed)

			if leg_left: leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_thigh_crouch, speed)
			if leg_right: leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_thigh_crouch, speed)

			if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin_vertical, speed)
			if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin_vertical, speed)

			var model = mecha.get_node_or_null("Zenisrev")
			if model:
				model.rotation.x = lerp_angle(model.rotation.x, target_body_tilt, speed)


func _update_bob(delta: float) -> void:
	var is_skating = mecha.get("is_roller_dashing") == true
	if is_moving and not is_skating:
		var run_speed = mecha.velocity.length() * 2.5
		bob_timer += delta * clamp(run_speed, 12.0, 24.0)
		var bob = sin(bob_timer) * bob_amount

		# Forward Torso Athletic Sprint Lean (-18 degrees forward lean)
		var sprint_lean = -deg_to_rad(18.0)
		if body_mesh:
			body_mesh.position.y = _original_body_pos.y + abs(bob) * 0.35
			body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, sprint_lean, 10.0 * delta)
		if head_mesh:
			head_mesh.position = _original_head_pos + Vector3(0, abs(bob) * 0.35, 0)
			head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, sprint_lean, 10.0 * delta)
	elif not is_skating:
		bob_timer = 0.0
		_lerp_to_original(delta)


func _update_legs(delta: float) -> void:
	var is_skating = mecha.get("is_roller_dashing") == true
	if is_skating:
		return

	if is_moving and leg_left and leg_right:
		var fwd_vel = -mecha.global_transform.basis.z.dot(mecha.velocity)
		var dir_sign = 1.0 if fwd_vel >= -0.2 else -1.0

		var phase_left = fmod(bob_timer * 0.5, TAU)
		var phase_right = fmod(bob_timer * 0.5 + PI, TAU)

		# Clean 3D Mecha Running Stride Calculations
		var left_leg_data = _calc_mecha_sprint_leg(phase_left)
		var right_leg_data = _calc_mecha_sprint_leg(phase_right)

		var thigh_l = left_leg_data["thigh"]
		var shin_l = left_leg_data["shin"]
		var thigh_r = right_leg_data["thigh"]
		var shin_r = right_leg_data["shin"]

		leg_left.rotation.x = thigh_l * dir_sign
		leg_right.rotation.x = thigh_r * dir_sign

		if shin_left: shin_left.rotation.x = shin_l
		if shin_right: shin_right.rotation.x = shin_r

		# Athletic Arm Pumping (Bent elbows swinging opposite to legs)
		if arm_left:
			arm_left.rotation.x = -thigh_l * 0.75 * dir_sign
			if forearm_left:
				forearm_left.rotation.x = deg_to_rad(55.0) + abs(sin(phase_left)) * deg_to_rad(20.0)
		if arm_right:
			arm_right.rotation.x = -thigh_r * 0.75 * dir_sign
			if forearm_right:
				forearm_right.rotation.x = deg_to_rad(55.0) + abs(sin(phase_right)) * deg_to_rad(20.0)
	else:
		var speed = 6.0 * delta
		if leg_left: leg_left.rotation.x = lerp_angle(leg_left.rotation.x, 0.0, speed)
		if leg_right: leg_right.rotation.x = lerp_angle(leg_right.rotation.x, 0.0, speed)
		if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, 0.0, speed)
		if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, 0.0, speed)
		if arm_left: arm_left.rotation.x = lerp_angle(arm_left.rotation.x, 0.0, speed)
		if arm_right: arm_right.rotation.x = lerp_angle(arm_right.rotation.x, 0.0, speed)
		if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, 0.0, speed)
		if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, 0.0, speed)


func _calc_mecha_sprint_leg(phase: float) -> Dictionary:
	var thigh = 0.0
	var shin = 0.0

	var norm_phase = fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# Swing Phase (Leg airborne, swinging from BACK to FRONT)
		var t = norm_phase / PI

		# 1. Thigh Motion:
		# - t in [0.0, 0.8]: Swings forward rapidly from back extension (-48°) to peak forward swing (+54°)
		# - t in [0.8, 1.0]: Pulls back slightly (+54° to +38°) to match ground speed at contact
		if t <= 0.8:
			var s = 0.5 - 0.5 * cos((t / 0.8) * PI)
			thigh = lerp(-deg_to_rad(48.0), deg_to_rad(54.0), s)
		else:
			var s = 0.5 - 0.5 * cos(((t - 0.8) / 0.2) * PI)
			thigh = lerp(deg_to_rad(54.0), deg_to_rad(38.0), s)

		# 2. Shin/Knee Motion (Negative rotation bends knee backward):
		# - t in [0.0, 0.4]: Recovery fold! Knee flexes sharply (-10° to -78°) to lift heel high & clear ground
		# - t in [0.4, 1.0]: Knee unfolds (-78° to -22°) extending forward to prepare for ground contact
		if t <= 0.4:
			var s = 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(10.0), -deg_to_rad(78.0), s)
		else:
			var s = 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(78.0), -deg_to_rad(22.0), s)

	else:
		# Stance / Power Push-Off Phase (Foot on ground, driving body forward by moving leg FRONT to BACK)
		var t = (norm_phase - PI) / PI

		# 1. Thigh Motion: Drives smoothly backward from contact (+38°) to push-off (-48°)
		var s_thigh = 0.5 - 0.5 * cos(t * PI)
		thigh = lerp(deg_to_rad(38.0), -deg_to_rad(48.0), s_thigh)

		# 2. Shin/Knee Motion:
		# - t in [0.0, 0.4]: Load absorption. Knee flexes slightly under body weight (-22° to -32° at mid-stance)
		# - t in [0.4, 1.0]: Propulsive extension. Knee straightens out (-32° to -8°) to push off into flight
		if t <= 0.4:
			var s = 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(22.0), -deg_to_rad(32.0), s)
		else:
			var s = 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(32.0), -deg_to_rad(8.0), s)

	return {"thigh": thigh, "shin": shin}


func _lerp_to_original(delta: float) -> void:
	var speed = 5.0 * delta
	if body_mesh:
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y, speed)
		body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, 0.0, speed)
	if head_mesh:
		head_mesh.position = head_mesh.position.lerp(_original_head_pos, speed)
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, 0.0, speed)
	if arm_left:
		arm_left.position = arm_left.position.lerp(_original_arm_left_pos, speed)
		arm_left.rotation.x = lerp_angle(arm_left.rotation.x, 0.0, speed)
	if arm_right:
		arm_right.position = arm_right.position.lerp(_original_arm_right_pos, speed)
		arm_right.rotation.x = lerp_angle(arm_right.rotation.x, 0.0, speed)


func play_recoil() -> void:
	current_recoil = recoil_amount
