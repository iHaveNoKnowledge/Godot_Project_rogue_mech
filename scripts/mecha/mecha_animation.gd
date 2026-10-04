extends Node

@export var bob_amount: float = 0.22
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
var foot_left: Node3D = null
var foot_right: Node3D = null
var foot_ik: MechaFootIK = null

var _walk: MechaWalkingSystem = null
var action_animator: MechaActionAnimator = null
var clip_retarget: MechaClipRetarget = null
var debug_branch: String = ""
var air_timer: float = 0.0
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

# Stance mode: "combat_crouch" (Kenbu athletic stance), "upright_formal", "wide_squat"
@export var stance_mode: String = "combat_crouch"

var _original_head_pos: Vector3
var _original_body_pos: Vector3
var _original_arm_left_pos: Vector3
var _original_arm_right_pos: Vector3
var _original_leg_left_pos: Vector3
var _original_leg_right_pos: Vector3
func _ready() -> void:
	mecha = get_parent()
	if mecha and mecha.is_in_group("player") and "selected_stance_mode" in GlobalData:
		stance_mode = GlobalData.selected_stance_mode
	_walk = MechaWalkingSystem.new()
	_walk.name = "WalkingSystem"
	add_child(_walk)
	action_animator = MechaActionAnimator.new()
	action_animator.name = "ActionAnimator"
	add_child(action_animator)
	clip_retarget = MechaClipRetarget.new()
	clip_retarget.name = "ClipRetarget"
	add_child(clip_retarget)
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
	foot_left = get_node_or_null("../LegLeft/ShinLeft/FootLeft") if foot_left == null else foot_left
	foot_right = get_node_or_null("../LegRight/ShinRight/FootRight") if foot_right == null else foot_right
	if foot_ik == null and mecha:
		foot_ik = mecha.get_node_or_null("FootIKSystem") as MechaFootIK

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
	# Only the player's mech / backup mechs follow the global player occupancy signal.
	# Allies and enemies manage their own pilots and must not kneel on player eject.
	if mecha and (mecha.is_in_group("ally") or mecha.is_in_group("enemy")):
		return
	set_kneeling(not occupied)
func set_kneeling(kneel: bool) -> void:
	is_kneeling = kneel
func set_core_breach(breach: bool) -> void:
	is_core_breach = breach

func set_stance_mode(mode: String) -> void:
	stance_mode = mode
	if is_inside_tree() and mecha and mecha.is_in_group("player") and "selected_stance_mode" in GlobalData:
		GlobalData.selected_stance_mode = mode
# When true the cleaned inner-frame clip (MechaClipRetarget, sourced from
# scenes/mecha/animations/innerframe_run_cycle_clean.glb) drives the modular
# pivots during grounded locomotion instead of the procedural gait. Armor
# destruction keeps working (meshes hide, pivots carry on). Every other
# state — idle, sustained airtime, dash, kneel, core breach — stays
# procedural, and a missing clip falls back to procedural, so the flag
# never freezes a mech.
@export var use_clip_animation: bool = true

func _physics_process(delta: float) -> void:
	if mecha == null:
		return
	_refresh_node_refs()

	if use_clip_animation:
		_update_clip_animation(delta)
		return

	_run_procedural(delta)
# Clip-driven entry point. The retargeted run clip owns grounded locomotion
# (legs, arms, torso, hip bob); aim/shield overlays still apply on top so
# guns and guard poses keep tracking. FootIK is skipped while the clip
# drives — the cycle carries baked feet and IK would fight it.
# Airborne grace: dune bumps and hover flicker is_on_floor for a few frames.
# Without a grace period the run snaps to the static fall posture mid-stride
# (frozen pose + sliding). Only sustained airtime hands over to procedural.
var _clip_air_time: float = 0.0
const CLIP_AIR_GRACE: float = 0.3

func _update_clip_animation(delta: float) -> void:
	# Special states own their whole posture: never let the run cycle
	# override kneel, death or dash postures.
	if is_kneeling or is_core_breach:
		_clip_air_time = 0.0
		debug_branch = "procedural_state"
		_run_procedural(delta)
		return
	if mecha.is_on_floor():
		_clip_air_time = 0.0
	else:
		_clip_air_time += delta
	if _clip_air_time >= CLIP_AIR_GRACE:
		debug_branch = "procedural_air"
		_run_procedural(delta)
		return
	if mecha.get("is_roller_dashing") == true:
		debug_branch = "procedural_dash"
		_run_procedural(delta)
		return
	var ds = mecha.get_node_or_null("DashSystem")
	if ds != null and ds.get("is_dashing") == true:
		debug_branch = "procedural_pulse"
		_run_procedural(delta)
		return
	_walk.is_moving = mecha.velocity.length() > 0.8
	if not _walk.is_moving or clip_retarget == null:
		debug_branch = "procedural_idle"
		_run_procedural(delta)
		return
	# Hand-authored run is primary; a Kimodo sprint wins when present,
	# then any AI clip; the hand-authored run is the final fallback.
	var clip_name := MechaRig.CLIP_RUN
	if clip_retarget.has_clip(MechaRig.CLIP_AI_RUN):
		clip_name = MechaRig.CLIP_AI_RUN
	if clip_retarget.has_clip(MechaRig.CLIP_SPRINT_KIMODO):
		clip_name = MechaRig.CLIP_SPRINT_KIMODO
	if not clip_retarget.has_clip(clip_name):
		debug_branch = "procedural_noclip"
		_run_procedural(delta)
		return
	debug_branch = "clip_" + clip_name
	clip_retarget.play_clip(clip_name)
	_update_recoil(delta)
	var joints := _build_joints_dict()
	var h_speed := Vector2(mecha.velocity.x, mecha.velocity.z).length()
	clip_retarget.advance_and_apply(delta * MechaClipRetarget.rate_for_variant(h_speed, FrameVariantResolver.natural_speed_for(mecha)), joints, _original_body_pos.y)
	var step_events: Array = clip_retarget.poll_step_events()
	_update_clip_footsteps(step_events, clip_retarget.poll_lift_events())
	_update_clip_strafe_overlay(h_speed, joints, step_events)
	_update_weapon_handling(delta)
	_update_aim_arms(delta)
	_update_shield_arm(delta)
	if action_animator:
		action_animator.update(delta)
		action_animator.apply_to_joints(joints, 1.0, false)


# Lateral sidestep overlay for strafing. The run clip only knows forward,
# so without this a sideways strafe plays a forward run. Each clip footfall
# advances the strafe phase (legs alternate by construction); the overlay
# adds abduction + lift from the tested procedural strafe math, weighted by
# how sideways the motion is. Pure forward running is untouched.
var _strafe_phase: float = 0.0
var _strafe_bank: float = 0.0
var _strafe_lift_l: float = 0.0
var _strafe_lift_r: float = 0.0
# Footstep audio for clip-driven locomotion (this is what went missing when
# runs moved from the procedural gait to clips: only update_legs ever played
# steps). Touchdowns come from the clip itself — baked STEP_FRACS for GLB
# clips, stance-channel edges for JSON clips — so each thump lands on the
# exact frame its foot plants; liftoffs play the step-lift swish.
func _update_clip_footsteps(step_events: Array, lift_events: Array) -> void:
	if step_events.is_empty() and lift_events.is_empty():
		return
	if not _walk.is_moving or not mecha.is_on_floor():
		return
	var local_vel: Vector3 = mecha.global_transform.basis.inverse() * mecha.velocity
	local_vel.y = 0.0
	var spd: float = local_vel.length()
	if spd < 0.1:
		return
	var step_dir := local_vel.normalized()
	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if audio_mgr == null:
		return
	for is_right in step_events:
		var land_offset_x := 0.45 if bool(is_right) else -0.45
		var land_pos: Vector3 = mecha.global_position + mecha.global_transform.basis * (Vector3(land_offset_x, 0.0, 0.0) + step_dir * 0.3)
		if audio_mgr.has_method("play_footstep"):
			audio_mgr.play_footstep(land_pos)
	for is_right in lift_events:
		var land_offset_x := 0.45 if bool(is_right) else -0.45
		var lift_pos: Vector3 = mecha.global_position + mecha.global_transform.basis * Vector3(land_offset_x, 0.0, 0.0)
		if audio_mgr.has_method("play_step_lift"):
			audio_mgr.play_step_lift(lift_pos)


func _update_clip_strafe_overlay(h_speed: float, joints: Dictionary, step_events: Array) -> void:
	var leg_l: Node3D = joints.get("leg_left")
	var leg_r: Node3D = joints.get("leg_right")
	var body: Node3D = joints.get("body")
	# Revert last frame (transfer zeroes leg roll itself; lift and bank persist).
	if leg_l:
		leg_l.position.y -= _strafe_lift_l
	if leg_r:
		leg_r.position.y -= _strafe_lift_r
	if body:
		body.rotation.z -= _strafe_bank
	_strafe_lift_l = 0.0
	_strafe_lift_r = 0.0
	_strafe_bank = 0.0
	if h_speed < 0.8 or not mecha.is_on_floor() or clip_retarget == null:
		return
	var local_vel: Vector3 = mecha.global_transform.basis.inverse() * mecha.velocity
	local_vel.y = 0.0
	var spd: float = local_vel.length()
	if spd < 0.1:
		return
	var side_ratio := clampf(local_vel.x / spd, -1.0, 1.0)
	if absf(side_ratio) < 0.15:
		return
	for _e in step_events:
		_strafe_phase += PI
	var ov := MechaWalkingSystem.calc_strafe_overlay(side_ratio, _strafe_phase)
	if leg_l:
		leg_l.rotation.z += float(ov["roll_l"])
		leg_l.position.y += float(ov["lift_l"])
		_strafe_lift_l = float(ov["lift_l"])
	if leg_r:
		leg_r.rotation.z += float(ov["roll_r"])
		leg_r.position.y += float(ov["lift_r"])
		_strafe_lift_r = float(ov["lift_r"])
	if body:
		_strafe_bank = -side_ratio * 0.12 * absf(side_ratio)
		body.rotation.z += _strafe_bank
func _run_procedural(delta: float) -> void:
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
	_walk.is_moving = is_on_ground and mecha.velocity.length() > 0.8

	if not is_on_ground:
		air_timer += delta
		_pulse_was = false
		_dash_end_t = 99.0
		if vert_vel > 0.8:
			_update_jump_posture(delta)
		else:
			_update_airborne_fall_posture(delta)
	else:
		air_timer = 0.0
		var is_skating = mecha.get("is_roller_dashing") == true
		var ds = mecha.get_node_or_null("DashSystem")
		_pulse_dashing = ds != null and ds.get("is_dashing") == true
		if _pulse_was and not _pulse_dashing:
			# Pulse dash just released: play the shared stop-overshoot.
			_pulse_was = false
			_dash_end_t = 0.0
		if is_skating:
			_dash_end_t = 99.0
			_update_roller_dash_posture(delta)
		elif _pulse_dashing:
			_dash_end_t = 99.0
			_pulse_was = true
			_update_pulse_dash_posture(delta)
		elif _dash_end_t < 0.45:
			# Dash just released: overshoot past neutral, then the normal
			# stance takes over (Blender ref: Mech_Dash_HighImpact f25-f40).
			_dash_was = false
			_dash_end_t += delta
			_update_dash_overshoot_posture(delta)
		else:
			_dash_was = false
			_update_bob(delta)
			_update_legs(delta)
			var js = mecha.get("jump_system")
			if js and js.get("is_charging_prejump") == true:
				_update_prejump_charge_posture(delta)

	# Overlay order after the base posture: weapon handling (hold the armed
	# arms instead of swinging them), then aim, then shield, then the action
	# animator (an active melee swing still owns the arms). Each layer only
	# touches its own masked joints, so the final pose has one owner per joint.
	_update_weapon_handling(delta)
	_update_aim_arms(delta)
	_update_shield_arm(delta)

	if action_animator:
		action_animator.update(delta)
		var joints := _build_joints_dict()
		var is_stationary: bool = not _walk.is_moving
		action_animator.apply_to_joints(joints, 1.0, is_stationary)

	if foot_ik and not (action_animator != null and action_animator.is_melee_active()):
		foot_ik.update_ik(delta)


# ─── Shared pose helper ────────────────────────────────────────────────────
# Interpolates every mech joint toward the target values in `targets`. Only
# supply the keys you need — all others default to 0.0 (neutral rotation,
# original position). Dictionary keys:
#   body_tilt, head_tilt  (float) — rotation.x targets
#   drop                  (float) — vertical offset applied to body & head
#   arm_left, arm_right   (float) — upper-arm rotation.x
#   forearm_left, forearm_right (float) — forearm rotation.x
#   thigh_left, thigh_right     (float) — thigh rotation.x
#   shin_left, shin_right       (float) — shin rotation.x
#   leg_left_drop, leg_right_drop (float) — extra vertical offset for leg roots
#   head_position        (Vector3) — override head target position (skips drop)
func _apply_pose(targets: Dictionary, speed: float) -> void:
	var drop: float = targets.get("drop", 0.0)
	if body_mesh:
		body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, targets.get("body_tilt", 0.0), speed)
		body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y + drop, speed)
		var waist_core = body_mesh.get_node_or_null("FrameMesh/WaistCore")
		if waist_core:
			waist_core.rotation.y = lerp_angle(waist_core.rotation.y, targets.get("waist_yaw", 0.0), speed)
			var pitch_j = waist_core.get_node_or_null("WaistPitchJoint")
			if pitch_j:
				pitch_j.rotation.x = lerp_angle(pitch_j.rotation.x, targets.get("waist_pitch", 0.0), speed)
				var roll_j = pitch_j.get_node_or_null("WaistRollJoint")
				if roll_j:
					roll_j.rotation.z = lerp_angle(roll_j.rotation.z, targets.get("waist_roll", 0.0), speed)
			else:
				waist_core.rotation.x = lerp_angle(waist_core.rotation.x, targets.get("waist_pitch", 0.0), speed)
	if head_mesh:
		# Anchor head dynamically to the body's forward collar opening so when
		# the torso tilts forward or drops, the head sits perfectly in the collar
		# recess and never sinks into the cockpit tub.
		var collar_local := MechaRig.HEAD_COLLAR_LOCAL
		var collar_world := body_mesh.position + collar_local.rotated(Vector3.RIGHT, body_mesh.rotation.x) if body_mesh else (_original_head_pos + Vector3(0, drop, 0))
		var head_pos: Vector3 = targets.get("head_position", collar_world)
		head_mesh.position = head_mesh.position.lerp(head_pos, speed)
		var base_pitch: float = body_mesh.rotation.x if body_mesh else 0.0
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, base_pitch + targets.get("head_tilt", targets.get("head_pitch", 0.0)), speed)
		head_mesh.rotation.y = lerp_angle(head_mesh.rotation.y, targets.get("head_yaw", 0.0), speed)

	if arm_left:
		arm_left.rotation.x = lerp_angle(arm_left.rotation.x, targets.get("arm_left", 0.0), speed)
		arm_left.rotation.y = lerp_angle(arm_left.rotation.y, targets.get("arm_left_yaw", 0.0), speed)
		arm_left.rotation.z = lerp_angle(arm_left.rotation.z, targets.get("arm_left_roll", 0.0), speed)
	if arm_right:
		arm_right.rotation.x = lerp_angle(arm_right.rotation.x, targets.get("arm_right", 0.0), speed)
		arm_right.rotation.y = lerp_angle(arm_right.rotation.y, targets.get("arm_right_yaw", 0.0), speed)
		arm_right.rotation.z = lerp_angle(arm_right.rotation.z, targets.get("arm_right_roll", 0.0), speed)
	if forearm_left:
		forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, targets.get("forearm_left", 0.0), speed)
		forearm_left.rotation.y = lerp_angle(forearm_left.rotation.y, targets.get("forearm_left_yaw", 0.0), speed)
		forearm_left.rotation.z = lerp_angle(forearm_left.rotation.z, targets.get("forearm_left_roll", 0.0), speed)
	if forearm_right:
		forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, targets.get("forearm_right", 0.0), speed)
		forearm_right.rotation.y = lerp_angle(forearm_right.rotation.y, targets.get("forearm_right_yaw", 0.0), speed)
		forearm_right.rotation.z = lerp_angle(forearm_right.rotation.z, targets.get("forearm_right_roll", 0.0), speed)
	if leg_left:
		leg_left.rotation.x = lerp_angle(leg_left.rotation.x, targets.get("thigh_left", 0.0), speed)
		leg_left.rotation.y = lerp_angle(leg_left.rotation.y, targets.get("thigh_left_yaw", 0.0), speed)
		leg_left.rotation.z = lerp_angle(leg_left.rotation.z, targets.get("thigh_left_roll", 0.0), speed)
		if targets.has("leg_left_drop"):
			leg_left.position.y = lerp(leg_left.position.y, _original_leg_left_pos.y + targets["leg_left_drop"], speed)
	if leg_right:
		leg_right.rotation.x = lerp_angle(leg_right.rotation.x, targets.get("thigh_right", 0.0), speed)
		leg_right.rotation.y = lerp_angle(leg_right.rotation.y, targets.get("thigh_right_yaw", 0.0), speed)
		leg_right.rotation.z = lerp_angle(leg_right.rotation.z, targets.get("thigh_right_roll", 0.0), speed)
		if targets.has("leg_right_drop"):
			leg_right.position.y = lerp(leg_right.position.y, _original_leg_right_pos.y + targets["leg_right_drop"], speed)
	if shin_left:
		shin_left.rotation.x = lerp_angle(shin_left.rotation.x, targets.get("shin_left", 0.0), speed)
		shin_left.rotation.y = lerp_angle(shin_left.rotation.y, targets.get("shin_left_yaw", 0.0), speed)
		shin_left.rotation.z = lerp_angle(shin_left.rotation.z, targets.get("shin_left_roll", 0.0), speed)
	if shin_right:
		shin_right.rotation.x = lerp_angle(shin_right.rotation.x, targets.get("shin_right", 0.0), speed)
		shin_right.rotation.y = lerp_angle(shin_right.rotation.y, targets.get("shin_right_yaw", 0.0), speed)
		shin_right.rotation.z = lerp_angle(shin_right.rotation.z, targets.get("shin_right_roll", 0.0), speed)
# ─── Posture functions ─────────────────────────────────────────────────────

func _update_prejump_charge_posture(delta: float) -> void:
	var js = mecha.get("jump_system")
	var charge_time: float = float(js.get("prejump_charge_time")) if (js and js.get("prejump_charge_time") != null) else 0.0
	var ratio := clampf(charge_time / 0.35, 0.0, 1.0)
	_apply_pose({"drop": -0.12 * ratio}, 12.0 * delta)
# Jump Launch Specs (Thrusters firing, upward launch trajectory):
# 1. Torso pitches slightly back/up (+12 deg) with chest raised
# 2. Head counter-tilts (-12 deg) to lock eyes forward
# 3. Legs thrust backward and extend (thighs -38 deg to -45 deg, knees extended -18 deg to -22 deg)
# 4. Arms trail backward (-20 deg) with forearms bent (+40 deg)
func _update_jump_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": deg_to_rad(12.0),
		"head_tilt": -deg_to_rad(12.0),
		"drop": 0.15,
		"arm_left": -deg_to_rad(20.0),
		"arm_right": -deg_to_rad(20.0),
		"forearm_left": deg_to_rad(40.0),
		"forearm_right": deg_to_rad(40.0),
		"thigh_left": -deg_to_rad(38.0),
		"thigh_right": -deg_to_rad(45.0),
		"shin_left": -deg_to_rad(18.0),
		"shin_right": -deg_to_rad(22.0),
	}, 12.0 * delta)
# Airborne Fall Specs (Freefall / Descent / Gliding from height):
# 1. Torso pitches forward down (-24 deg) ready for landing impact
# 2. Head counter-tilts (-10 deg net) looking down/ahead at landing zone
# 3. Left Leg flexed forward (+32 deg thigh, -55 deg shin knee flex under hip)
# 4. Right Leg trailing back (-22 deg thigh, -30 deg shin knee flex)
# 5. Organic floating hover sway applied to body position
func _update_airborne_fall_posture(delta: float) -> void:
	var float_sway = sin(air_timer * 4.0) * 0.07
	_apply_pose({
		"body_tilt": -deg_to_rad(24.0),
		"head_tilt": -deg_to_rad(10.0),
		"drop": -0.22 + float_sway,
		"arm_left": -deg_to_rad(15.0),
		"arm_right": deg_to_rad(15.0),
		"forearm_left": deg_to_rad(50.0),
		"forearm_right": deg_to_rad(50.0),
		"thigh_left": deg_to_rad(32.0),
		"thigh_right": -deg_to_rad(22.0),
		"shin_left": -deg_to_rad(55.0),
		"shin_right": -deg_to_rad(30.0),
	}, 8.0 * delta)
# Idle combat stance (standing still, ready to fight):
# Driven by stance_mode:
#   "combat_crouch": Mailes Kenbu athletic crouch (deep knee bend, wide stance, lowered center of gravity)
#   "upright_formal": Standard military parade upright stance
#   "wide_squat": Heavy siege / artillery wide stance
func _update_combat_idle_posture(delta: float) -> void:
	match stance_mode:
		"upright_formal":
			_apply_pose({
				"body_tilt": 0.0,
				"head_tilt": 0.0,
				"drop": 0.0,
				"arm_left": deg_to_rad(8.0),
				"arm_right": deg_to_rad(8.0),
				"forearm_left": deg_to_rad(14.0),
				"forearm_right": deg_to_rad(14.0),
				"thigh_left": 0.0,
				"thigh_right": 0.0,
				"shin_left": 0.0,
				"shin_right": 0.0,
				"leg_left_drop": 0.0,
				"leg_right_drop": 0.0,
			}, 6.0 * delta)
		"wide_squat":
			_apply_pose({
				"body_tilt": -deg_to_rad(3.0),
				"head_tilt": deg_to_rad(3.0),
				"drop": -0.29,
				"arm_left": deg_to_rad(20.0),
				"arm_right": deg_to_rad(20.0),
				"forearm_left": deg_to_rad(45.0),
				"forearm_right": deg_to_rad(45.0),
				"thigh_left": deg_to_rad(32.0),
				"thigh_right": deg_to_rad(32.0),
				"thigh_left_yaw": deg_to_rad(16.0),
				"thigh_right_yaw": -deg_to_rad(16.0),
				"shin_left": -deg_to_rad(32.0),
				"shin_right": -deg_to_rad(32.0),
				"leg_left_drop": 0.0,
				"leg_right_drop": 0.0,
			}, 6.0 * delta)
		_: # "combat_crouch" = hangar hero pose 1:1 (Armored Core stance,
			# hangar_garage_panel.gd:429-457). Tall proud posture, legs spread
			# by roll, arms in a strong outward A-pose. No sway/oscillation so
			# it never reads as dancing; FootIK plants the feet flat.
			_apply_pose({
				"body_tilt": -deg_to_rad(4.0),
				"head_tilt": deg_to_rad(2.0),
			# Crouch bends the knees (thigh 8 / shin -18), which shortens
			# the legs ~0.03: drop the hips by the same amount so the
			# feet stay planted instead of hovering.
			"drop": -0.03,
				"arm_left": deg_to_rad(12.0),
				"arm_left_yaw": deg_to_rad(6.0),
				"arm_left_roll": -deg_to_rad(28.0),
				"arm_right": deg_to_rad(14.0),
				"arm_right_yaw": -deg_to_rad(6.0),
				"arm_right_roll": deg_to_rad(28.0),
				"forearm_left": deg_to_rad(28.0),
				"forearm_left_roll": deg_to_rad(14.0),
				"forearm_right": deg_to_rad(30.0),
				"forearm_right_roll": -deg_to_rad(14.0),
				"thigh_left": deg_to_rad(8.0),
				"thigh_right": deg_to_rad(8.0),
				"thigh_left_yaw": deg_to_rad(14.0),
				"thigh_right_yaw": -deg_to_rad(14.0),
				"thigh_left_roll": -deg_to_rad(14.0),
				"thigh_right_roll": deg_to_rad(14.0),
				"shin_left": -deg_to_rad(18.0),
				"shin_left_roll": deg_to_rad(8.0),
				"shin_right": -deg_to_rad(18.0),
				"shin_right_roll": -deg_to_rad(8.0),
				"leg_left_drop": 0.0,
				"leg_right_drop": 0.0,
			}, 6.0 * delta)

# Kneel pose (pilot out / backup waiting): single-knee proposal kneel —
# LEFT foot forward flat, RIGHT knee down behind. Asymmetric so it reads as
# kneeling (not a symmetric squat/yob): torso drops and bows, head stays
# level, arms hang relaxed.
func _update_kneel_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": -deg_to_rad(10.0),
		"head_tilt": -deg_to_rad(4.0),
		"drop": -0.68,
		"arm_left": deg_to_rad(10.0),
		"arm_right": deg_to_rad(10.0),
		"forearm_left": deg_to_rad(60.0),
		"forearm_right": deg_to_rad(60.0),
		"thigh_left": deg_to_rad(85.0),
		"thigh_left_yaw": deg_to_rad(6.0),
		"shin_left": -deg_to_rad(95.0),
		"leg_left_drop": -0.40,
		"thigh_right": deg_to_rad(20.0),
		"thigh_right_yaw": -deg_to_rad(6.0),
		"shin_right": -deg_to_rad(130.0),
		"leg_right_drop": -0.68,
	}, 10.0 * delta)
# High-impact dash phase timers (Blender ref: Mech_Dash_HighImpact).
# _dash_t counts up while the dash is held; _dash_end_t counts up after
# release so the stop-overshoot can play out before idle resumes.
var _dash_t: float = 0.0
var _dash_end_t: float = 99.0
var _dash_was: bool = false
# Short-pulse dash (DashSystem, 0.2s) pose flags. While a pulse dash runs it
# owns the body + legs (gait yields, same as the MJ-lean fix); on release the
# shared stop-overshoot plays via _dash_end_t.
var _pulse_dashing: bool = false
var _pulse_was: bool = false
# Roller skate stance: SQUAT style (not deep pitch) with High-Impact phases:
# ANTICIPATION (coil back 0.15s) -> SNAP (slam into squat fast) -> SUSTAIN
# -> OVERSHOOT on release (handled by _update_dash_overshoot_posture).
func _update_roller_dash_posture(delta: float) -> void:
	if mecha == null or mecha.get("is_roller_dashing") == null:
		return
	if not _dash_was:
		_dash_was = true
		_dash_t = 0.0
	_dash_t += delta

	if _dash_t < 0.15:
		# ANTICIPATION: brief coil — torso tips back/up, arms swing forward
		# as the counter-movement before the launch.
		_apply_pose({
			"body_tilt": deg_to_rad(8.0),
			"head_tilt": -deg_to_rad(8.0),
			"drop": -0.15,
			"arm_left": deg_to_rad(28.0),
			"arm_right": deg_to_rad(28.0),
			"forearm_left": deg_to_rad(45.0),
			"forearm_right": deg_to_rad(45.0),
			"thigh_left": deg_to_rad(15.0),
			"thigh_right": deg_to_rad(15.0),
			"shin_left": -deg_to_rad(15.0),
			"shin_right": -deg_to_rad(15.0),
		}, 10.0 * delta)
		return

	# SNAP (t < 0.32): very high lerp speed slams the pose in like the
	# LINEAR snap keys in Blender; SUSTAIN after that eases normally.
	var snap_speed := 24.0 * delta if _dash_t < 0.32 else 12.0 * delta
	# SQUAT (not deep pitch): hips drop straight down, torso stays up with a
	# slight nod, gaze forward. Upper arm runs PARALLEL to the torso axis
	# (same -15 deg pitch, since both hang off the root) + 90 deg elbow, so
	# the forearm points down at the ground in front — never at the sky.
	var target_drop = -0.61
	var target_body_tilt = -deg_to_rad(15.0)
	var target_head_tilt = deg_to_rad(7.0)
	_apply_pose({
		"body_tilt": target_body_tilt,
		"head_tilt": target_head_tilt,
		"drop": target_drop,
		# Head naturally follows the tilted collar opening via collar_world in _apply_pose
		"arm_left": target_body_tilt,
		"arm_right": target_body_tilt,
		"forearm_left": deg_to_rad(90.0),
		"forearm_right": deg_to_rad(90.0),
		"thigh_left": deg_to_rad(35.0),
		"thigh_right": deg_to_rad(35.0),
		"thigh_left_roll": -deg_to_rad(10.0),
		"thigh_right_roll": deg_to_rad(10.0),
		"shin_left": -deg_to_rad(35.0),
		"shin_right": -deg_to_rad(35.0),
		"shin_left_roll": deg_to_rad(5.0),
		"shin_right_roll": -deg_to_rad(5.0),
	}, snap_speed)

	var model = mecha.get_node_or_null("Zenisrev")
	if model:
		model.rotation.x = lerp_angle(model.rotation.x, target_body_tilt, snap_speed)


# Stop-overshoot: on dash release the torso swings PAST neutral upright
# and the arms fling forward (follow-through), then idle catches it.
func _update_dash_overshoot_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": deg_to_rad(7.0),
		"head_tilt": -deg_to_rad(9.0),
		"drop": -0.09,
		"arm_left": deg_to_rad(35.0),
		"arm_right": deg_to_rad(35.0),
		"forearm_left": deg_to_rad(50.0),
		"forearm_right": deg_to_rad(50.0),
		"thigh_left": deg_to_rad(12.0),
		"thigh_right": deg_to_rad(12.0),
		"shin_left": -deg_to_rad(12.0),
		"shin_right": -deg_to_rad(12.0),
	}, 10.0 * delta)


# Short-pulse dash pose, blended by dash direction (Blender refs:
# Mech_Dash_Fwd / Mech_Dash_Side / Mech_Dash_Back). The 0.2s window needs
# a hard snap, so this lerps at 20/s.
func _update_pulse_dash_posture(delta: float) -> void:
	var ds = mecha.get_node_or_null("DashSystem")
	if ds == null:
		return
	var dir: Vector3 = ds.get("dash_direction")
	if dir.length() < 0.1:
		dir = -mecha.global_transform.basis.z
	var local: Vector3 = mecha.global_transform.basis.inverse() * dir
	var fwd := clampf(-local.z, -1.0, 1.0)
	var side := clampf(local.x, -1.0, 1.0)
	var wf := maxf(fwd, 0.0)
	var wb := maxf(-fwd, 0.0)
	var ws := absf(side)
	var tot := wf + wb + ws
	if tot < 0.05:
		wf = 1.0
		tot = 1.0
	wf /= tot
	wb /= tot
	ws /= tot
	var lead_right := side >= 0.0
	var s := 1.0 if lead_right else -1.0
	# Lead leg plants toward the dash, trail leg pushes; lead arm tucks,
	# trail arm flings out for balance.
	var lead_thigh := 18.0
	var trail_thigh := 12.0
	var lead_roll := 20.0
	var lead_shin := -20.0
	var trail_shin := -35.0
	_apply_pose({
		"body_tilt": deg_to_rad(wf * -25.0 + wb * 10.0 + ws * -10.0),
		"waist_roll": deg_to_rad(-12.0) * s * ws,
		"head_tilt": deg_to_rad(wf * 20.0 + wb * -12.0 + ws * 8.0),
		"head_yaw": deg_to_rad(-20.0) * s * ws,
		"drop": wf * -0.26 + wb * -0.17 + ws * -0.29,
		"arm_left": deg_to_rad(wf * -30.0 + wb * 50.0 + ws * 10.0),
		"arm_right": deg_to_rad(wf * -30.0 + wb * 50.0 + ws * 10.0),
		"arm_left_roll": deg_to_rad(-8.0 if lead_right else -25.0) * ws,
		"arm_right_roll": deg_to_rad(25.0 if lead_right else 8.0) * ws,
		"forearm_left": deg_to_rad(wf * 30.0 + wb * 90.0 + ws * (20.0 if lead_right else 55.0)),
		"forearm_right": deg_to_rad(wf * 30.0 + wb * 90.0 + ws * (55.0 if lead_right else 20.0)),
		"thigh_left": deg_to_rad(wf * 45.0 + wb * 55.0 + ws * (trail_thigh if lead_right else lead_thigh)),
		"thigh_right": deg_to_rad(wf * -40.0 + wb * 10.0 + ws * (lead_thigh if lead_right else trail_thigh)),
		"thigh_left_roll": deg_to_rad(-10.0) + deg_to_rad(-8.0 if lead_right else -lead_roll) * ws,
		"thigh_right_roll": deg_to_rad(10.0) + deg_to_rad(lead_roll if lead_right else 8.0) * ws,
		"shin_left": deg_to_rad(wf * -30.0 + wb * -80.0 + ws * (trail_shin if lead_right else lead_shin)),
		"shin_right": deg_to_rad(wf * -10.0 + wb * -20.0 + ws * (lead_shin if lead_right else trail_shin)),
		"shin_left_roll": deg_to_rad(5.0),
		"shin_right_roll": -deg_to_rad(5.0),
	}, 20.0 * delta)
# Death collapse: the mech goes limp before detonating — torso slumps back and
# drops, head tilts down, arms hang splayed, legs fold under.
func _update_core_breach_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": deg_to_rad(22.0),
		"head_tilt": -deg_to_rad(35.0),
		"drop": -0.94,
		"arm_left": deg_to_rad(55.0),
		"arm_right": deg_to_rad(55.0),
		"forearm_left": deg_to_rad(25.0),
		"forearm_right": deg_to_rad(25.0),
		"thigh_left": deg_to_rad(60.0),
		"thigh_right": -deg_to_rad(55.0),
		"shin_left": -deg_to_rad(90.0),
		"shin_right": -deg_to_rad(70.0),
		"leg_left_drop": -0.94,
		"leg_right_drop": -0.94,
	}, 7.0 * delta)
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
			body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y - landing_impact * 0.36, 12.0 * delta)
		if leg_left and leg_right:
			leg_left.rotation.x = lerp_angle(leg_left.rotation.x, deg_to_rad(22.0) * landing_impact, 12.0 * delta)
			leg_right.rotation.x = lerp_angle(leg_right.rotation.x, deg_to_rad(22.0) * landing_impact, 12.0 * delta)
# ─── Gun-arm aiming pose ───────────────────────────────────────────────────
# While a hand is FIRING a ranged weapon (or the mech holds the aim stance),
# that arm straightens and pitches so the gun physically points at
# MechaCombat.current_aim_point — the same point projectiles are aimed at.
#
# The weapon mounts sit rotated -80° about X inside the forearm, so a LEVEL
# barrel needs arm + forearm rotations summing to 80° (the idle guard's
# 25° + 55° hits exactly that). Aiming adds the pitch to the target on top:
#   total = 80° + aim_pitch   (split 72% upper arm / 28% forearm)
var _aim_raise: float = 0.0
const AIM_RAISE_SPEED: float = 14.0
const AIM_LEVEL_TOTAL_DEG: float = 80.0
const AIM_ARM_SHARE: float = 0.72

# Weapon handling layer weights (per hand, smoothed like the aim raise).
var _handling_l: float = 0.0
var _handling_r: float = 0.0
const HANDLING_BLEND_SPEED: float = 6.0


## Weapon handling layer: armed hands hold their handling pose instead of
## performing the empty-hand locomotion swing. Runs after base locomotion and
## before aim/shield/action overlays. Empty hands are never masked (swing
## preserved); an active melee swing eases handling to zero because the
## action animator (applied later) owns the arms for the swing duration.
func _update_weapon_handling(delta: float) -> void:
	var wm = mecha.get_node_or_null("WeaponManager") if mecha else null
	if wm == null:
		_handling_l = move_toward(_handling_l, 0.0, HANDLING_BLEND_SPEED * delta)
		_handling_r = move_toward(_handling_r, 0.0, HANDLING_BLEND_SPEED * delta)
		return
	_apply_handling(delta, wm.get("left_hand"), wm.get("right_hand"))


## Handling core with explicit weapons (unit-testable without a manager).
func _apply_handling(delta: float, wl, wr) -> void:
	var want_l := 0.0
	var want_r := 0.0
	var handling := {"pose": {}, "mask": []}
	if not (action_animator != null and action_animator.is_melee_active()):
		var sl := WeaponPart.HoldStance.AUTO
		var sr := WeaponPart.HoldStance.AUTO
		if wl != null:
			sl = WeaponVisualFactory.get_effective_hold_stance(wl)
		if wr != null:
			sr = WeaponVisualFactory.get_effective_hold_stance(wr)
		handling = MechaWeaponLayer.handling_for_stances(sl, sr)
		var m: Array = handling["mask"]
		if m.has("arm_left") or m.has("forearm_left"):
			want_l = 1.0
		if m.has("arm_right") or m.has("forearm_right"):
			want_r = 1.0
	_handling_l = move_toward(_handling_l, want_l, HANDLING_BLEND_SPEED * delta)
	_handling_r = move_toward(_handling_r, want_r, HANDLING_BLEND_SPEED * delta)
	if _handling_l <= 0.001 and _handling_r <= 0.001:
		return
	var joints := _build_joints_dict()
	var pose: Dictionary = handling["pose"]
	# Per-hand masks keep transitions independent: a lowering left arm never
	# drags the still-raised right arm (no hidden last-writer coupling).
	var mask_l: Array = []
	var mask_r: Array = []
	for k in (handling["mask"] as Array):
		if str(k).ends_with("left"):
			mask_l.append(k)
		else:
			mask_r.append(k)
	MechaWeaponLayer.apply_layer(joints, pose, mask_l, _handling_l)
	MechaWeaponLayer.apply_layer(joints, pose, mask_r, _handling_r)


func _update_aim_arms(delta: float) -> void:
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		_aim_raise = move_toward(_aim_raise, 0.0, AIM_RAISE_SPEED * delta)
		return

	var left_ranged := _hand_is_ranged_gun(wm, "left")
	var right_ranged := _hand_is_ranged_gun(wm, "right")
	var firing_left := bool(wm.get("fire_left_holding"))
	var firing_right := bool(wm.get("fire_right_holding"))
	var aiming_stance := false
	var combat = mecha.get_node_or_null("MechaCombat")
	if combat:
		aiming_stance = bool(combat.get("is_aiming"))

	# A two-hand gripped weapon raises BOTH arms as one braced unit.
	var grip_left := false
	var grip_right := false
	if wm.has_method("is_two_hand_gripped_hand"):
		grip_left = left_ranged and wm.is_two_hand_gripped_hand("left")
		grip_right = right_ranged and wm.is_two_hand_gripped_hand("right")

	var want_left := left_ranged and (firing_left or grip_right or aiming_stance or grip_left)
	var want_right := right_ranged and (firing_right or grip_left or aiming_stance or grip_right)

	_aim_raise = move_toward(_aim_raise, 1.0 if (want_left or want_right) else 0.0,
		AIM_RAISE_SPEED * delta)
	if _aim_raise <= 0.001:
		return

	var pitch_deg := _current_aim_pitch_deg()
	var total_deg := clampf(AIM_LEVEL_TOTAL_DEG + pitch_deg, 15.0, 150.0)
	var arm_target := deg_to_rad(total_deg * AIM_ARM_SHARE)
	var forearm_target := deg_to_rad(total_deg * (1.0 - AIM_ARM_SHARE))
	var blend := _aim_raise

	if want_left and arm_left and forearm_left:
		arm_left.rotation.x = lerp_angle(arm_left.rotation.x, arm_target, blend)
		arm_left.rotation.y = lerp_angle(arm_left.rotation.y, 0.0, blend)
		arm_left.rotation.z = lerp_angle(arm_left.rotation.z, 0.0, blend)
		forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, forearm_target, blend)
		forearm_left.rotation.y = lerp_angle(forearm_left.rotation.y, 0.0, blend)
		forearm_left.rotation.z = lerp_angle(forearm_left.rotation.z, 0.0, blend)
	if want_right and arm_right and forearm_right:
		arm_right.rotation.x = lerp_angle(arm_right.rotation.x, arm_target, blend)
		arm_right.rotation.y = lerp_angle(arm_right.rotation.y, 0.0, blend)
		arm_right.rotation.z = lerp_angle(arm_right.rotation.z, 0.0, blend)
		forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, forearm_target, blend)
		forearm_right.rotation.y = lerp_angle(forearm_right.rotation.y, 0.0, blend)
		forearm_right.rotation.z = lerp_angle(forearm_right.rotation.z, 0.0, blend)


# True when the given hand holds a RANGED weapon on an intact arm — melee
# weapons keep their swing poses, shields keep the guard raise.
func _hand_is_ranged_gun(wm: Node, hand: String) -> bool:
	if wm.has_method("_hand_usable") and not wm._hand_usable(hand):
		return false
	var w = wm.get("left_hand" if hand == "left" else "right_hand")
	if w == null:
		return false
	return w.weapon_type != WeaponPart.WeaponType.MELEE \
		and w.weapon_type != WeaponPart.WeaponType.SHIELD


# Vertical angle (deg, +up) from the raised shoulder toward the aim point.
func _current_aim_pitch_deg() -> float:
	var combat = mecha.get_node_or_null("MechaCombat")
	if combat == null or not ("current_aim_point" in combat):
		return 0.0
	var aim_point: Vector3 = combat.current_aim_point
	if aim_point == Vector3.ZERO:
		return 0.0
	var origin_ref := arm_right if arm_right != null else arm_left
	var origin: Vector3
	if origin_ref != null and origin_ref.is_inside_tree():
		origin = origin_ref.global_position
	else:
		origin = mecha.global_position + Vector3(0, 1.4, 0)
	var to := aim_point - origin
	var horizontal := sqrt(to.x * to.x + to.z * to.z)
	return rad_to_deg(atan2(to.y, maxf(horizontal, 0.05)))


# Raised-shield guard pose. When a hand is actively holding its shield plate
# up, that arm lifts in front of the torso (upper arm swung forward, elbow
# bent hard) so the plate reads as being interposed between the mech and the
# attacker.
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
		# Enemy shield mechs: state is on the body, plate always on the left.
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
# FBX generic rigs (Mech_00) have splayed shoot poses. After the clip has
# updated the skeleton, force the arm bones to point forward so the barrel
# aligns with current_aim_point — same as procedural.
func _fix_fbx_skeleton_aim() -> void:
	if mecha == null:
		return
	var skeletons: Array[Node] = []
	_find_skeletons_recursive(mecha, skeletons)
	for skel_node in skeletons:
		var skel := skel_node as Skeleton3D
		if skel == null:
			continue
		# Skip the main Rig (it has Bone_Head etc, already handled by procedural)
		if skel.name == "Rig":
			continue
		for i in range(skel.get_bone_count()):
			var bname: String = skel.get_bone_name(i)
			var lname: String = bname.to_lower()
			# Find arm bones: Mech_00 uses Base_*_Arm, Core_ShoulderJoint, or generic UpperArm/LowerArm
			var is_upper := lname.contains("upperarm") or lname.contains("shoulder") or (lname.contains("arm") and not lname.contains("lower") and not lname.contains("forearm") and not lname.contains("hand"))
			var is_lower := lname.contains("lowerarm") or lname.contains("forearm") or lname.contains("elbow")
			if not is_upper and not is_lower:
				continue
			# Only fix when aiming/shooting (same condition as procedural)
			var wm = mecha.get_node_or_null("WeaponManager")
			var should_aim: bool = false
			if wm:
				var left_ranged := _hand_is_ranged_gun(wm, "left")
				var right_ranged := _hand_is_ranged_gun(wm, "right")
				should_aim = left_ranged or right_ranged
			if not should_aim:
				continue
			var is_left: bool = lname.contains("left") or lname.contains("_l") or lname.contains("l_")
			# Forward aim: upper arm ~57deg, lower ~22deg on top of clip (lerp 0.6)
			var target_upper := deg_to_rad(57.0) if not is_left else deg_to_rad(57.0)
			var target_lower := deg_to_rad(22.0)
			var cur := skel.get_bone_pose_rotation(i)
			var target := Quaternion.from_euler(Vector3(target_upper if is_upper else target_lower, 0, 0))
			skel.set_bone_pose_rotation(i, cur.slerp(target, 0.7))

func _find_skeletons_recursive(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is Skeleton3D:
			out.append(child)
		_find_skeletons_recursive(child, out)

# Builds a joints dictionary from the cached node refs for passing to
# MechaWalkingSystem and MechaActionAnimator helpers.
func _build_joints_dict() -> Dictionary:
	var j: Dictionary = {}
	j["head"] = head_mesh
	j["head_mesh"] = head_mesh
	j["body"] = body_mesh
	j["body_mesh"] = body_mesh
	j["arm_left"] = arm_left
	j["arm_right"] = arm_right
	j["forearm_left"] = forearm_left
	j["forearm_right"] = forearm_right
	j["leg_left"] = leg_left
	j["leg_right"] = leg_right
	j["shin_left"] = shin_left if shin_left else leg_left
	j["shin_right"] = shin_right if shin_right else leg_right
	# Foot pivots are owned by FootIK (terrain alignment); exposed here so
	# action/gait helpers can read them without rotating them.
	j["foot_left"] = foot_left
	j["foot_right"] = foot_right
	j["original_body_pos"] = _original_body_pos
	j["original_head_pos"] = _original_head_pos
	j["original_leg_left_pos"] = _original_leg_left_pos
	j["original_leg_right_pos"] = _original_leg_right_pos
	return j
func _update_bob(delta: float) -> void:
	var joints := _build_joints_dict()
	var bob := _walk.update_bob(delta, mecha, joints, bob_amount, FrameVariantResolver.head_collar_for(mecha))
	var is_skating = mecha.get("is_roller_dashing") == true
	if not _walk.is_moving and not is_skating:
		# Standing still: settle into the ready-to-fight idle stance (bent knees,
		# forward lean, raised guard arms) instead of a stiff straight pose.
		_update_combat_idle_posture(delta)
func _update_legs(delta: float) -> void:
	# The procedural gait only owns the legs while actually striding. When
	# standing still (or airborne / kneeling / breaching) the base posture
	# (combat idle, jump, fall, kneel, breach) owns them — letting the gait
	# ease the legs to neutral here fought the crouch every frame, leaving
	# straight legs under a hunched torso (the "MJ lean" with tiptoe feet).
	# A pulse dash also owns the legs for its lunge.
	if not _walk.is_moving or _pulse_dashing:
		return
	var joints := _build_joints_dict()
	_walk.update_legs(delta, mecha, joints, FrameVariantResolver.lift_scale_for(mecha))

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
