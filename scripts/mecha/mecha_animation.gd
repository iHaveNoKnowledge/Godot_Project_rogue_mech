extends Node

@export var bob_amount: float = 0.15
@export var bob_speed: float = 12.0
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

	is_moving = mecha.velocity.length() > 0.8

	_update_bob(delta)
	_update_recoil(delta)
	_update_legs(delta)
	_update_roller_dash_posture(delta)


func _update_recoil(delta: float) -> void:
	if current_recoil > 0.0:
		current_recoil = move_toward(current_recoil, 0.0, recoil_recovery * delta)
		if head_mesh:
			head_mesh.rotation.x = -current_recoil * 0.5


func _update_roller_dash_posture(delta: float) -> void:
	if mecha and mecha.get("is_roller_dashing") != null:
		var speed = 8.0 * delta
		var is_skating = mecha.is_roller_dashing

		# Correct Roller Dash Pose:
		# Body leans FORWARD down -24 deg (Negative X in Godot tilts forward towards -Z)
		var target_body_tilt = -deg_to_rad(24.0) if is_skating else 0.0
		var target_drop = -0.4 if is_skating else 0.0

		# Upper Arm: Pushed BACKWARD along forward body tilt (+45 deg in Godot rotates arms back towards +Z)
		var target_upper_arm_rot = deg_to_rad(45.0) if is_skating else 0.0
		# Forearm: Bent forward DOWNWARD towards ground (-70 deg) forming the sharp '>' chevron posture!
		var target_forearm_rot = -deg_to_rad(70.0) if is_skating else 0.0

		# Legs crouch forward into racing stance
		var target_hip_crouch = -deg_to_rad(25.0) if is_skating else 0.0
		var target_knee_crouch = deg_to_rad(50.0) if is_skating else 0.0

		if is_skating:
			if body_mesh:
				body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, target_body_tilt, speed)
				body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y + target_drop, speed)
			if head_mesh:
				head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, target_body_tilt * 0.7, speed)

			if arm_left: arm_left.rotation.x = lerp_angle(arm_left.rotation.x, target_upper_arm_rot, speed)
			if arm_right: arm_right.rotation.x = lerp_angle(arm_right.rotation.x, target_upper_arm_rot, speed)

			if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_forearm_rot, speed)
			if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_forearm_rot, speed)

			if leg_left: leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_hip_crouch, speed)
			if leg_right: leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_hip_crouch, speed)

			if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_knee_crouch, speed)
			if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_knee_crouch, speed)

			var model = mecha.get_node_or_null("Zenisrev")
			if model:
				model.rotation.x = lerp_angle(model.rotation.x, target_body_tilt, speed)
		else:
			if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, 0.0, speed)
			if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, 0.0, speed)


func _update_bob(delta: float) -> void:
	var is_skating = mecha.get("is_roller_dashing") == true
	if is_moving and not is_skating:
		var run_speed = mecha.velocity.length() * 2.2
		bob_timer += delta * clamp(run_speed, 10.0, 22.0)
		var bob = sin(bob_timer) * bob_amount

		# Forward Torso Sprint Lean (~14 degrees forward lean when sprinting!)
		var sprint_lean = -deg_to_rad(14.0)
		if body_mesh:
			body_mesh.position.y = _original_body_pos.y + abs(bob) * 0.4
			body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, sprint_lean, 10.0 * delta)
		if head_mesh:
			head_mesh.position.y = _original_head_pos.y + abs(bob) * 0.6
			head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, sprint_lean * 0.7, 10.0 * delta)

		# Athletic Bent-Elbow Arm Pumping
		var arm_swing = sin(bob_timer * 0.5) * deg_to_rad(42.0)
		if arm_left:
			arm_left.position.y = _original_arm_left_pos.y + bob * 0.15
			arm_left.rotation.x = arm_swing
		if arm_right:
			arm_right.position.y = _original_arm_right_pos.y + bob * 0.15
			arm_right.rotation.x = -arm_swing

		# Bent elbows during sprint (-45 deg flexion)
		if forearm_left: forearm_left.rotation.x = -deg_to_rad(45.0)
		if forearm_right: forearm_right.rotation.x = -deg_to_rad(45.0)
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

		# Dynamic Sprinting Stride for Left Leg
		var thigh_l = 0.0
		var shin_l = 0.0
		if phase_left < PI:
			var step_p = phase_left / PI
			thigh_l = -deg_to_rad(52.0) * sin(step_p * PI) # Drive thigh forward (-Z)
			shin_l = deg_to_rad(45.0) * sin(step_p * PI)   # Knee flexes forward, foot plants
		else:
			var push_p = (phase_left - PI) / PI
			thigh_l = deg_to_rad(38.0) * sin(push_p * PI) # Drive thigh backward (+Z)
			shin_l = deg_to_rad(25.0) * sin(push_p * PI)

		# Dynamic Sprinting Stride for Right Leg
		var thigh_r = 0.0
		var shin_r = 0.0
		if phase_right < PI:
			var step_p = phase_right / PI
			thigh_r = -deg_to_rad(52.0) * sin(step_p * PI)
			shin_r = deg_to_rad(45.0) * sin(step_p * PI)
		else:
			var push_p = (phase_right - PI) / PI
			thigh_r = deg_to_rad(38.0) * sin(push_p * PI)
			shin_r = deg_to_rad(25.0) * sin(push_p * PI)

		leg_left.rotation.x = thigh_l * dir_sign
		leg_right.rotation.x = thigh_r * dir_sign

		if shin_left: shin_left.rotation.x = shin_l
		if shin_right: shin_right.rotation.x = shin_r
	else:
		var speed = 6.0 * delta
		if leg_left: leg_left.rotation.x = lerp_angle(leg_left.rotation.x, 0.0, speed)
		if leg_right: leg_right.rotation.x = lerp_angle(leg_right.rotation.x, 0.0, speed)
		if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, 0.0, speed)
		if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, 0.0, speed)


func _lerp_to_original(delta: float) -> void:
	var speed = 5.0 * delta
	if body_mesh:
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y, speed)
		body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, 0.0, speed)
	if head_mesh:
		head_mesh.position.y = lerp(head_mesh.position.y, _original_head_pos.y, speed)
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, 0.0, speed)
	if arm_left:
		arm_left.position = arm_left.position.lerp(_original_arm_left_pos, speed)
		arm_left.rotation.x = lerp_angle(arm_left.rotation.x, 0.0, speed)
	if arm_right:
		arm_right.position = arm_right.position.lerp(_original_arm_right_pos, speed)
		arm_right.rotation.x = lerp_angle(arm_right.rotation.x, 0.0, speed)


func play_recoil() -> void:
	current_recoil = recoil_amount
