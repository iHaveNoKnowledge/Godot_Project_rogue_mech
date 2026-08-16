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
var landing_impact: float = 0.0
# True while the mech is empty (pilot out): it kneels and waits instead of
# idling upright. Driven by EventBus.mecha_occupancy_changed (and seeded for
# backup machines that spawn already pilotless).
var is_kneeling: bool = false

# True while the mech is in its death (core-breach) window: the machine has
# gone down and is flashing a warning before it detonates. The limp collapse
# pose takes over every other posture (set by the health system on destroy).
var is_core_breach: bool = false

var _original_head_pos: Vector3
var _original_body_pos: Vector3
var _original_arm_left_pos: Vector3
var _original_arm_right_pos: Vector3
var _original_leg_left_pos: Vector3
var _original_leg_right_pos: Vector3


func _ready() -> void:
	mecha = get_parent()
	_refresh_node_refs()
	EventBus.mecha_occupancy_changed.connect(_on_occupancy_changed)


# Resolves the mech's part-slot nodes. Called on _ready AND lazily whenever a
# reference is still null, so machines whose bodies are assembled AFTER this
# node's _ready (allies built from a berth loadout, late-spawned bodies) pick
# the joints up the first time they animate instead of staying frozen.
func _refresh_node_refs() -> void:
	head_mesh = get_node_or_null("../Head") if head_mesh == null else head_mesh
	body_mesh = get_node_or_null("../Body") if body_mesh == null else body_mesh
	arm_left = get_node_or_null("../ArmLeft") if arm_left == null else arm_left
	arm_right = get_node_or_null("../ArmRight") if arm_right == null else arm_right
	forearm_left = get_node_or_null("../ArmLeft/ForearmLeft") if forearm_left == null else forearm_left
	forearm_right = get_node_or_null("../ArmRight/ForearmRight") if forearm_right == null else forearm_right
	leg_left = get_node_or_null("../LegLeft") if leg_left == null else leg_left
	leg_right = get_node_or_null("../LegRight") if leg_right == null else leg_right
	shin_left = get_node_or_null("../LegLeft/ShinLeft") if shin_left == null else shin_left
	shin_right = get_node_or_null("../LegRight/ShinRight") if shin_right == null else shin_right

	if head_mesh and _original_head_pos == Vector3.ZERO:
		_original_head_pos = head_mesh.position
	if body_mesh and _original_body_pos == Vector3.ZERO:
		_original_body_pos = body_mesh.position
	if arm_left and _original_arm_left_pos == Vector3.ZERO:
		_original_arm_left_pos = arm_left.position
	if arm_right and _original_arm_right_pos == Vector3.ZERO:
		_original_arm_right_pos = arm_right.position
	if leg_left and _original_leg_left_pos == Vector3.ZERO:
		_original_leg_left_pos = leg_left.position
	if leg_right and _original_leg_right_pos == Vector3.ZERO:
		_original_leg_right_pos = leg_right.position


# Occupied mechs stand normally; an empty mech (pilot ejected, or a backup
# machine waiting on the field) kneels until someone boards it.
func _on_occupancy_changed(occupied: bool) -> void:
	set_kneeling(not occupied)


func set_kneeling(kneel: bool) -> void:
	is_kneeling = kneel


func set_core_breach(breach: bool) -> void:
	is_core_breach = breach


func _physics_process(delta: float) -> void:
	if mecha == null:
		return
	_refresh_node_refs()

	# The death (core-breach) collapse takes precedence over every other pose:
	# the machine is down and no longer responding to pilot/movement input.
	if is_core_breach:
		_update_core_breach_posture(delta)
		return

	# Kneel pose takes over entirely while the mech is empty: the normal
	# bob/leg/recoil logic resumes (and eases back to standing) on re-board.
	if is_kneeling:
		_update_kneel_posture(delta)
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

	# Runs LAST so the raised shield arm overrides whatever the base postures
	# (idle guard, sprint pumping, airborne) set for that arm this frame.
	_update_shield_arm(delta)


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


# Idle combat stance (standing still, ready to fight): knees slightly bent,
# torso leaning forward, head level and both arms raised in a guard with bent
# elbows. Replaces the stiff straight-up idle so the mech reads as poised to
# throw a punch instead of standing at attention.
func _update_combat_idle_posture(delta: float) -> void:
	var speed = 6.0 * delta
	var target_drop = -0.05
	var target_body_tilt = -deg_to_rad(10.0)
	var target_head_tilt = -deg_to_rad(5.0)
	var target_thigh = deg_to_rad(12.0)
	var target_shin = -deg_to_rad(18.0)
	var target_arm = deg_to_rad(25.0)
	var target_forearm = deg_to_rad(55.0)

	if body_mesh:
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y + target_drop, speed)
		body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, target_body_tilt, speed)
	if head_mesh:
		head_mesh.position = head_mesh.position.lerp(_original_head_pos + Vector3(0, target_drop, 0), speed)
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, target_head_tilt, speed)

	if arm_left: arm_left.rotation.x = lerp_angle(arm_left.rotation.x, target_arm, speed)
	if arm_right: arm_right.rotation.x = lerp_angle(arm_right.rotation.x, target_arm, speed)

	if forearm_left: forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_forearm, speed)
	if forearm_right: forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_forearm, speed)

	# Leg roots only move for the kneel pose; ease them back up whenever the
	# mech is active again so a re-board never leaves it squatting.
	if leg_left:
		leg_left.position.y = lerp(leg_left.position.y, _original_leg_left_pos.y, speed)
		leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_thigh, speed)
	if leg_right:
		leg_right.position.y = lerp(leg_right.position.y, _original_leg_right_pos.y, speed)
		leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_thigh, speed)

	if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin, speed)
	if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin, speed)


# Kneel pose (pilot out / backup waiting): both thighs fold forward so the
# knees come down, shins fold back under, and the torso drops and bows while
# the head stays level and the arms hang relaxed — reads as the mech kneeling
# to wait for its pilot. Standing resumes through the normal idle/sprint lerps.
func _update_kneel_posture(delta: float) -> void:
	var speed = 10.0 * delta
	var target_drop = -0.5
	var target_thigh = deg_to_rad(75.0)
	var target_shin = -deg_to_rad(120.0)
	var target_body_tilt = -deg_to_rad(12.0)
	var target_head_tilt = -deg_to_rad(8.0)
	var target_arm = deg_to_rad(10.0)
	var target_forearm = deg_to_rad(65.0)

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

	# The leg roots sit at the hip height; drop them with the torso so the
	# folded thighs actually reach toward the ground instead of hovering.
	if leg_left:
		leg_left.position.y = lerp(leg_left.position.y, _original_leg_left_pos.y + target_drop, speed)
		leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_thigh, speed)
	if leg_right:
		leg_right.position.y = lerp(leg_right.position.y, _original_leg_right_pos.y + target_drop, speed)
		leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_thigh, speed)

	if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin, speed)
	if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin, speed)


func play_landing_impact() -> void:
	landing_impact = 1.0


func _update_recoil(delta: float) -> void:
	if current_recoil > 0.0:
		current_recoil = move_toward(current_recoil, 0.0, recoil_recovery * delta)
		if head_mesh:
			head_mesh.rotation.x = -current_recoil * 0.5

	if landing_impact > 0.0:
		landing_impact = move_toward(landing_impact, 0.0, 4.5 * delta)
		if body_mesh:
			body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y - landing_impact * 0.25, 12.0 * delta)
		if leg_left and leg_right:
			leg_left.rotation.x = lerp_angle(leg_left.rotation.x, deg_to_rad(22.0) * landing_impact, 12.0 * delta)
			leg_right.rotation.x = lerp_angle(leg_right.rotation.x, deg_to_rad(22.0) * landing_impact, 12.0 * delta)


# Raised-shield guard pose. When a hand is actively holding its shield plate
# up, that arm lifts in front of the torso (upper arm swung forward, elbow
# bent hard) so the plate reads as being interposed between the mech and the
# attacker. Works for BOTH the player mech (shield state lives on the
# WeaponManager child, which also reports which hand holds it) and enemy
# shield mechs (state lives on the body itself, plate always on the left arm).
#
# The pose is blended by _shield_raise (eased 0..1) and applied AFTER the
# normal idle/sprint postures, so the shield arm smoothly lifts from whatever
# the base pose left it at and eases back down when the plate lowers.
var _shield_raise: float = 0.0
const SHIELD_RAISE_SPEED: float = 9.0

func _update_shield_arm(delta: float) -> void:
	var shield_up := false
	var shield_hand := ""

	var wm = mecha.get_node_or_null("WeaponManager")
	if wm and wm.has_method("is_shield_active") and wm.has_method("get_shield_hand"):
		shield_up = wm.is_shield_active()
		shield_hand = wm.get_shield_hand()
	elif mecha.has_method("is_shield_active"):
		# Enemy shield mechs: state is on the body, plate mounted on the left.
		shield_up = mecha.is_shield_active()
		shield_hand = "left"

	_shield_raise = move_toward(_shield_raise, 1.0 if shield_up else 0.0, SHIELD_RAISE_SPEED * delta)
	if _shield_raise <= 0.001:
		return

	var target_arm := deg_to_rad(70.0)
	var target_forearm := deg_to_rad(100.0)
	var blend := _shield_raise

	if shield_hand == "left":
		if arm_left:
			arm_left.rotation.x = lerp_angle(arm_left.rotation.x, target_arm, blend)
		if forearm_left:
			forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_forearm, blend)
	elif shield_hand == "right":
		if arm_right:
			arm_right.rotation.x = lerp_angle(arm_right.rotation.x, target_arm, blend)
		if forearm_right:
			forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_forearm, blend)


func _update_roller_dash_posture(delta: float) -> void:
	if mecha and mecha.get("is_roller_dashing") != null:
		var speed = 12.0 * delta
		var is_skating = mecha.is_roller_dashing

		if is_skating:
			# Gundam AGE Symmetrical Forward-Pitched Roller Skating Dash Stance:
			# 1. Torso pitched forward aggressively (-40 deg) shifting weight center forward over toes
			# 2. Both upper thighs crouched (+24 deg) & lower shins perpendicular to floor (-24 deg)
			# 3. Center of gravity dropped (-0.40)
			# 4. Head locked looking straight ahead (-18 deg net)
			# 5. Arms holding weapon and shield in aggressive forward posture
			var target_body_tilt = -deg_to_rad(40.0)
			var target_head_tilt = -deg_to_rad(18.0)
			var target_drop = -0.40

			var target_thigh_crouch = deg_to_rad(24.0)
			var target_shin_vertical = -deg_to_rad(24.0)

			var target_arm_right = deg_to_rad(20.0)
			var target_forearm_right = deg_to_rad(75.0)

			var target_arm_left = -deg_to_rad(20.0)
			var target_forearm_left = deg_to_rad(80.0)

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
		var run_speed = mecha.velocity.length() * 1.4
		bob_timer += delta * clamp(run_speed, 7.0, 14.0)
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
		# Standing still: settle into the ready-to-fight idle stance (bent knees,
		# forward lean, raised guard arms) instead of a stiff straight pose.
		_update_combat_idle_posture(delta)


func _update_legs(delta: float) -> void:
	var is_skating = mecha.get("is_roller_dashing") == true
	if is_skating:
		return

	# Leg roots only ever move for the kneel pose; ease them back up whenever
	# the mech is active again so a re-board never leaves it squatting.
	if leg_left:
		leg_left.position.y = lerp(leg_left.position.y, _original_leg_left_pos.y, 6.0 * delta)
	if leg_right:
		leg_right.position.y = lerp(leg_right.position.y, _original_leg_right_pos.y, 6.0 * delta)

	if is_moving and leg_left and leg_right:
		var fwd_vel = -mecha.global_transform.basis.z.dot(mecha.velocity)
		var dir_sign = 1.0 if fwd_vel >= -0.2 else -1.0

		var phase_left = fmod(bob_timer * 0.5, TAU)
		var phase_right = fmod(bob_timer * 0.5 + PI, TAU)

		# Clean 3D Mecha Long-Stride Sprint Calculations
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
		# Idle: _update_bob already eased every limb into the combat idle stance
		# this frame, so leave the limbs alone (no fighting the pose).
		return


func _calc_mecha_sprint_leg(phase: float) -> Dictionary:
	var thigh = 0.0
	var shin = 0.0

	var norm_phase = fmod(phase, TAU)
	if norm_phase < 0.0:
		norm_phase += TAU

	if norm_phase < PI:
		# Swing Phase (Leg airborne, swinging from BACK to FRONT)
		var t = norm_phase / PI

		# 1. Thigh Motion (Wide Powerful Stride: -58 deg to +64 deg):
		# - t in [0.0, 0.8]: Swings forward rapidly from back extension (-58°) to peak forward swing (+64°)
		# - t in [0.8, 1.0]: Pulls back slightly (+64° to +46°) to match ground speed at contact
		if t <= 0.8:
			var s = 0.5 - 0.5 * cos((t / 0.8) * PI)
			thigh = lerp(-deg_to_rad(58.0), deg_to_rad(64.0), s)
		else:
			var s = 0.5 - 0.5 * cos(((t - 0.8) / 0.2) * PI)
			thigh = lerp(deg_to_rad(64.0), deg_to_rad(46.0), s)

		# 2. Shin/Knee Motion:
		# - t in [0.0, 0.4]: High recovery fold! Knee flexes sharply (-10° to -85°) to lift foot over wide stride
		# - t in [0.4, 1.0]: Knee unfolds (-85° to -26°) extending forward to prepare for ground contact
		if t <= 0.4:
			var s = 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(10.0), -deg_to_rad(85.0), s)
		else:
			var s = 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(85.0), -deg_to_rad(26.0), s)

	else:
		# Stance / Power Push-Off Phase (Foot on ground, driving body forward by moving leg FRONT to BACK)
		var t = (norm_phase - PI) / PI

		# 1. Thigh Motion: Drives smoothly backward from contact (+46°) to push-off (-58°)
		var s_thigh = 0.5 - 0.5 * cos(t * PI)
		thigh = lerp(deg_to_rad(46.0), -deg_to_rad(58.0), s_thigh)

		# 2. Shin/Knee Motion:
		# - t in [0.0, 0.4]: Load absorption. Knee flexes slightly under body weight (-26° to -36° at mid-stance)
		# - t in [0.4, 1.0]: Propulsive extension. Knee straightens out (-36° to -6°) to push off into flight
		if t <= 0.4:
			var s = 0.5 - 0.5 * cos((t / 0.4) * PI)
			shin = lerp(-deg_to_rad(26.0), -deg_to_rad(36.0), s)
		else:
			var s = 0.5 - 0.5 * cos(((t - 0.4) / 0.6) * PI)
			shin = lerp(-deg_to_rad(36.0), -deg_to_rad(6.0), s)

	return {"thigh": thigh, "shin": shin}


func _lerp_to_original(delta: float) -> void:
	var speed = 5.0 * delta
	if body_mesh:
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y, speed)
		body_mesh.rotation = body_mesh.rotation.lerp(Vector3.ZERO, speed)
	if head_mesh:
		head_mesh.position = head_mesh.position.lerp(_original_head_pos, speed)
		head_mesh.rotation = head_mesh.rotation.lerp(Vector3.ZERO, speed)
	if arm_left:
		arm_left.position = arm_left.position.lerp(_original_arm_left_pos, speed)
		arm_left.rotation = arm_left.rotation.lerp(Vector3.ZERO, speed)
	if arm_right:
		arm_right.position = arm_right.position.lerp(_original_arm_right_pos, speed)
		arm_right.rotation = arm_right.rotation.lerp(Vector3.ZERO, speed)
	if forearm_left:
		forearm_left.rotation = forearm_left.rotation.lerp(Vector3.ZERO, speed)
	if forearm_right:
		forearm_right.rotation = forearm_right.rotation.lerp(Vector3.ZERO, speed)
	if leg_left:
		leg_left.rotation = leg_left.rotation.lerp(Vector3.ZERO, speed)
	if leg_right:
		leg_right.rotation = leg_right.rotation.lerp(Vector3.ZERO, speed)
	if shin_left:
		shin_left.rotation = shin_left.rotation.lerp(Vector3.ZERO, speed)
	if shin_right:
		shin_right.rotation = shin_right.rotation.lerp(Vector3.ZERO, speed)


func play_recoil() -> void:
	current_recoil = recoil_amount


# Death collapse: the mech goes limp before detonating — torso slumps back and
# drops, head tilts down, arms hang splayed, legs fold under. Driven for the
# ~2s core-breach warning window so the player sees the machine is down (and
# the pilot can still eject) before the explosion.
func _update_core_breach_posture(delta: float) -> void:
	var speed = 7.0 * delta
	var target_drop = -0.65
	var target_body_tilt = deg_to_rad(22.0)
	var target_head_tilt = -deg_to_rad(35.0)
	var target_arm = deg_to_rad(55.0)
	var target_forearm = deg_to_rad(25.0)
	var target_thigh_left = deg_to_rad(60.0)
	var target_shin_left = -deg_to_rad(90.0)
	var target_thigh_right = -deg_to_rad(55.0)
	var target_shin_right = -deg_to_rad(70.0)

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

	if leg_left:
		leg_left.position.y = lerp(leg_left.position.y, _original_leg_left_pos.y + target_drop, speed)
		leg_left.rotation.x = lerp_angle(leg_left.rotation.x, target_thigh_left, speed)
	if leg_right:
		leg_right.position.y = lerp(leg_right.position.y, _original_leg_right_pos.y + target_drop, speed)
		leg_right.rotation.x = lerp_angle(leg_right.rotation.x, target_thigh_right, speed)

	if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, target_shin_left, speed)
	if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, target_shin_right, speed)
