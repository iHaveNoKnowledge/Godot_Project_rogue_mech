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
var foot_ik: MechaFootIK = null

var _walk: MechaWalkingSystem = null
var action_animator: MechaActionAnimator = null
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

var _original_head_pos: Vector3
var _original_body_pos: Vector3
var _original_arm_left_pos: Vector3
var _original_arm_right_pos: Vector3
var _original_leg_left_pos: Vector3
var _original_leg_right_pos: Vector3
func _ready() -> void:
	mecha = get_parent()
	_walk = MechaWalkingSystem.new()
	_walk.name = "WalkingSystem"
	add_child(_walk)
	action_animator = MechaActionAnimator.new()
	action_animator.name = "ActionAnimator"
	add_child(action_animator)
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
# When true the AnimationPlayer (MechaRig.ANIM_PLAYER_NODE) drives the mech
# from external clips instead of the procedural pose. Stays false until skinned
# parts + animation assets exist; flipping it early safely falls back to
# procedural until the first clip is present.
@export var use_clip_animation: bool = false

func _physics_process(delta: float) -> void:
	if mecha == null:
		return
	_refresh_node_refs()

	if use_clip_animation:
		_update_clip_animation(delta)
		return

	_run_procedural(delta)
# Clip-driven entry point. Once external animation lands, this becomes the
# state machine that plays/queues the MechaRig.CLIP_* clips (idle, run, jump,
# kneel, core breach, shield, recoil...). Until clips exist it hands the frame
# back to the procedural pose so the flag never freezes a mech.
func _update_clip_animation(delta: float) -> void:
	var anim_player = mecha.get_node_or_null(MechaRig.ANIM_PLAYER_NODE) as AnimationPlayer
	if anim_player == null or anim_player.get_animation_list().is_empty():
		_run_procedural(delta)
		return
	# Clip exists: let AnimationPlayer drive the Rig, then post-process aim so FBX arms point forward (not splayed)
	# This fixes FBX generic rig (Mech_00) that has splayed shoot pose — same logic as procedural
	_update_recoil(delta)
	var is_on_ground = mecha.is_on_floor()
	_walk.is_moving = is_on_ground and mecha.velocity.length() > 0.8
	# Keep bob/legs from procedural for FBX as well (so walk/run still syncs with speed)
	_update_bob(delta)
	_update_legs(delta)
	_update_aim_arms(delta)
	_update_shield_arm(delta)
	if foot_ik:
		foot_ik.update_ik(delta)
	# Also fix any imported FBX Skeleton3D under MechaBase (e.g., Mech_00) that has different bone names
	_fix_fbx_skeleton_aim()
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
			var js = mecha.get("jump_system")
			if js and js.get("is_charging_prejump") == true:
				_update_prejump_charge_posture(delta)

	# Runs LAST so the raised shield arm overrides whatever the base postures
	# (idle guard, sprint pumping, airborne) set for that arm this frame.
	_update_aim_arms(delta)
	_update_shield_arm(delta)

	if action_animator:
		action_animator.update(delta)
		var joints := _build_joints_dict()
		action_animator.apply_to_joints(joints)

	if foot_ik:
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
	if head_mesh:
		var head_pos: Vector3 = targets.get("head_position", _original_head_pos + Vector3(0, drop, 0))
		head_mesh.position = head_mesh.position.lerp(head_pos, speed)
		head_mesh.rotation.x = lerp_angle(head_mesh.rotation.x, targets.get("head_tilt", 0.0), speed)
	if arm_left:
		arm_left.rotation.x = lerp_angle(arm_left.rotation.x, targets.get("arm_left", 0.0), speed)
	if arm_right:
		arm_right.rotation.x = lerp_angle(arm_right.rotation.x, targets.get("arm_right", 0.0), speed)
	if forearm_left:
		forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, targets.get("forearm_left", 0.0), speed)
	if forearm_right:
		forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, targets.get("forearm_right", 0.0), speed)
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
	if shin_right:
		shin_right.rotation.x = lerp_angle(shin_right.rotation.x, targets.get("shin_right", 0.0), speed)
# ─── Posture functions ─────────────────────────────────────────────────────

func _update_prejump_charge_posture(delta: float) -> void:
	var js = mecha.get("jump_system")
	var charge_time: float = float(js.get("prejump_charge_time")) if (js and js.get("prejump_charge_time") != null) else 0.0
	var ratio := clampf(charge_time / 0.35, 0.0, 1.0)
	_apply_pose({"drop": -0.08 * ratio}, 12.0 * delta)
# Jump Launch Specs (Thrusters firing, upward launch trajectory):
# 1. Torso pitches slightly back/up (+12 deg) with chest raised
# 2. Head counter-tilts (-12 deg) to lock eyes forward
# 3. Legs thrust backward and extend (thighs -38 deg to -45 deg, knees extended -18 deg to -22 deg)
# 4. Arms trail backward (-20 deg) with forearms bent (+40 deg)
func _update_jump_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": deg_to_rad(12.0),
		"head_tilt": -deg_to_rad(12.0),
		"drop": 0.1,
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
	var float_sway = sin(air_timer * 4.0) * 0.05
	_apply_pose({
		"body_tilt": -deg_to_rad(24.0),
		"head_tilt": -deg_to_rad(10.0),
		"drop": -0.15 + float_sway,
		"arm_left": -deg_to_rad(15.0),
		"arm_right": deg_to_rad(15.0),
		"forearm_left": deg_to_rad(50.0),
		"forearm_right": deg_to_rad(50.0),
		"thigh_left": deg_to_rad(32.0),
		"thigh_right": -deg_to_rad(22.0),
		"shin_left": -deg_to_rad(55.0),
		"shin_right": -deg_to_rad(30.0),
	}, 8.0 * delta)
# Idle combat stance (standing still, ready to fight): knees slightly bent,
# torso leaning forward, head level and both arms raised in a guard with bent
# elbows.
func _update_combat_idle_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": -deg_to_rad(10.0),
		"head_tilt": -deg_to_rad(5.0),
		"drop": -0.05,
		"arm_left": deg_to_rad(25.0),
		"arm_right": deg_to_rad(25.0),
		"forearm_left": deg_to_rad(55.0),
		"forearm_right": deg_to_rad(55.0),
		"thigh_left": deg_to_rad(12.0),
		"thigh_right": deg_to_rad(12.0),
		"shin_left": -deg_to_rad(18.0),
		"shin_right": -deg_to_rad(18.0),
		"leg_left_drop": 0.0,
		"leg_right_drop": 0.0,
	}, 6.0 * delta)
# Kneel pose (pilot out / backup waiting): both thighs fold forward so the
# knees come down, shins fold back under, and the torso drops and bows while
# the head stays level and the arms hang relaxed.
func _update_kneel_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": -deg_to_rad(12.0),
		"head_tilt": -deg_to_rad(8.0),
		"drop": -0.5,
		"arm_left": deg_to_rad(10.0),
		"arm_right": deg_to_rad(10.0),
		"forearm_left": deg_to_rad(65.0),
		"forearm_right": deg_to_rad(65.0),
		"thigh_left": deg_to_rad(75.0),
		"thigh_right": deg_to_rad(75.0),
		"shin_left": -deg_to_rad(120.0),
		"shin_right": -deg_to_rad(120.0),
		"leg_left_drop": -0.5,
		"leg_right_drop": -0.5,
	}, 10.0 * delta)
# Gundam AGE Symmetrical Forward-Pitched Roller Skating Dash Stance
func _update_roller_dash_posture(delta: float) -> void:
	if mecha and mecha.get("is_roller_dashing") != null:
		var speed = 12.0 * delta
		var is_skating = mecha.get("is_roller_dashing") == true

		if is_skating:
			var target_drop = -0.40
			var target_body_tilt = -deg_to_rad(40.0)
			var target_head_tilt = -deg_to_rad(18.0)
			_apply_pose({
				"body_tilt": target_body_tilt,
				"head_tilt": target_head_tilt,
				"drop": target_drop,
				# Head snaps to target instead of lerping (skating needs instant lock)
				"head_position": _original_head_pos + Vector3(0, target_drop, 0),
				"arm_left": -deg_to_rad(20.0),
				"arm_right": deg_to_rad(20.0),
				"forearm_left": deg_to_rad(80.0),
				"forearm_right": deg_to_rad(75.0),
				"thigh_left": deg_to_rad(24.0),
				"thigh_right": deg_to_rad(24.0),
				"shin_left": -deg_to_rad(24.0),
				"shin_right": -deg_to_rad(24.0),
			}, speed)

			var model = mecha.get_node_or_null("Zenisrev")
			if model:
				model.rotation.x = lerp_angle(model.rotation.x, target_body_tilt, speed)
# Death collapse: the mech goes limp before detonating — torso slumps back and
# drops, head tilts down, arms hang splayed, legs fold under.
func _update_core_breach_posture(delta: float) -> void:
	_apply_pose({
		"body_tilt": deg_to_rad(22.0),
		"head_tilt": -deg_to_rad(35.0),
		"drop": -0.65,
		"arm_left": deg_to_rad(55.0),
		"arm_right": deg_to_rad(55.0),
		"forearm_left": deg_to_rad(25.0),
		"forearm_right": deg_to_rad(25.0),
		"thigh_left": deg_to_rad(60.0),
		"thigh_right": -deg_to_rad(55.0),
		"shin_left": -deg_to_rad(90.0),
		"shin_right": -deg_to_rad(70.0),
		"leg_left_drop": -0.65,
		"leg_right_drop": -0.65,
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
			body_mesh.position.y = lerp(body_mesh.position.y, _original_body_pos.y - landing_impact * 0.25, 12.0 * delta)
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
	j["original_body_pos"] = _original_body_pos
	j["original_head_pos"] = _original_head_pos
	j["original_leg_left_pos"] = _original_leg_left_pos
	j["original_leg_right_pos"] = _original_leg_right_pos
	return j
func _update_bob(delta: float) -> void:
	var joints := _build_joints_dict()
	var bob := _walk.update_bob(delta, mecha, joints, bob_amount)
	var is_skating = mecha.get("is_roller_dashing") == true
	if not _walk.is_moving and not is_skating:
		# Standing still: settle into the ready-to-fight idle stance (bent knees,
		# forward lean, raised guard arms) instead of a stiff straight pose.
		_update_combat_idle_posture(delta)
func _update_legs(delta: float) -> void:
	var joints := _build_joints_dict()
	_walk.update_legs(delta, mecha, joints)

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
