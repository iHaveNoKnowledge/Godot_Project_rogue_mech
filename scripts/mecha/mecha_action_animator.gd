class_name MechaActionAnimator
extends Node

## ---------------------------------------------------------------------------
## MECHA ACTION ANIMATOR
##
## Manages keyframed 3D animation clips from Mech_00_Anim.fbx (Melee attack combos,
## shooting recoils, shoulder missile artillery, hit reactions, and death collapses)
## plus ActionForge one-handed sword clips (sword_attack single slash,
## sword_regular_combo 3-hit combo) for MELEE weapons and enemy wind-up strikes.
## Evaluates bone transforms in real-time and blends them smoothly over the base
## procedural locomotion and terrain Foot IK.
## ---------------------------------------------------------------------------

const ANIM_FBX_PATH := "res://download/Mech_00/Char_Anim/Mech_00_Anim.fbx"

# ActionForge one-handed sword clips (in-place, godot-ready GLB).
# sword_attack = single slash (46f @30fps ~1.53s), sword_regular_combo = 3-hit combo (90f @30fps ~3.0s).
const AF_SWORD_ATTACK_PATH := "res://assets/animations/actionforge/sword_attack-inplace-anim-only.glb"
const AF_SWORD_COMBO_PATH := "res://assets/animations/actionforge/sword_regular_combo-inplace-anim-only.glb"
const AF_SWORD_ATTACK := "AF_SwordAttack"
const AF_SWORD_COMBO := "AF_SwordCombo"

# Shared Animation Library cache across all mechas
static var _cached_anim_library: Dictionary = {}
static var _cached_track_maps: Dictionary = {}
static var _initialized_library: bool = false
static var _af_clips_loaded: bool = false
static var _af_retarget_data: Dictionary = {}

# Current action playback state
var current_anim_name: String = ""
var anim_time: float = 0.0
var anim_length: float = 0.0
var anim_speed: float = 1.0
var blend_weight: float = 0.0
var fade_in_time: float = 0.10
var fade_out_time: float = 0.15
var is_active: bool = false

# Combo tracking for melee
var combo_index: int = 1
var last_attack_time_ms: int = 0
const COMBO_WINDOW_MS: int = 1400

# ── Authoritative melee lifecycle ──────────────────────────────────────────
# One attack input = one attack_id. Damage is NEVER dealt by the play call;
# it fires only via poll_strike(), which crosses strike_times measured from
# the clip's own weapon-arm motion (peak forward angular velocity = visual
# contact). Restarting a swing (combo chain) retires the previous attack_id
# and its pending hit can never fire afterwards: 1 swing = strikes of THIS
# swing only, 1 completion exactly once.
var attack_id: int = 0
var strike_times: Array = []
var _strike_idx: int = 0
var _pending_strikes: int = 0
var _completed_pending: bool = false

# ── Melee retarget mode ────────────────────────────────────────────────────
# Source clips (UE-mannequin AF takes, Rigify Mech_00 takes) rest in a
# different pose than the game pivots (AF upperarm_r rests at (-62,1,1)deg,
# thigh_r at (-46,18,-20)deg — measured on the GLB). Copying clip eulers
# absolutely therefore snaps limbs into alien poses (writhe + stray leg
# lifts). Melee plays instead apply REST-RELATIVE deltas, and touch only
# the upper body: legs stay on base locomotion per the weapon-layer
# architecture. Non-melee actions (die/gethit/shoot) keep legacy behavior.
var melee_mode: bool = false
var melee_hand: String = "right"
var _rest_euler: Dictionary = {}
var _rest_quat: Dictionary = {}
const MELEE_UPPER_KEYS: Array = [
	"arm_left", "arm_right", "forearm_left", "forearm_right", "body", "head",
]

# Clips that count as melee attacks (everything else = action/recoil/death).
const MELEE_CLIP_PREFIXES: Array = ["Mech_Attack"]


func _is_melee_clip(clip_name: String) -> bool:
	if clip_name == AF_SWORD_ATTACK or clip_name == AF_SWORD_COMBO:
		return true
	for prefix in MELEE_CLIP_PREFIXES:
		if clip_name.begins_with(prefix):
			return true
	return false


## True while a melee swing owns the attack lifecycle (windup through
## recovery, until the clip finishes). Base locomotion keeps driving legs;
## the swing blend (see apply_to_joints) owns the attack bones meanwhile.
func is_melee_active() -> bool:
	return is_active and _is_melee_clip(current_anim_name)


func _ready() -> void:
	_ensure_library_cached()


static func _ensure_library_cached() -> void:
	if _initialized_library:
		# AF clips load lazily on top of the base library so a retry after a
		# failed first import still picks them up without rebuilding Mech_00.
		if not _af_clips_loaded:
			_load_af_clips()
		return
	_initialized_library = true
	if not ResourceLoader.exists(ANIM_FBX_PATH):
		push_warning("MechaActionAnimator: Anim FBX not found at " + ANIM_FBX_PATH)
	else:
		var loaded_res = load(ANIM_FBX_PATH)
		if loaded_res == null:
			push_warning("MechaActionAnimator: Failed to load anim resource from " + ANIM_FBX_PATH)
		elif loaded_res is AnimationLibrary:
			var lib := loaded_res as AnimationLibrary
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				_cached_anim_library[anim_name] = anim
				_cached_track_maps[anim_name] = _build_track_map(anim)
		elif loaded_res is PackedScene:
			var inst = (loaded_res as PackedScene).instantiate()
			var ap: AnimationPlayer = _find_player_recursive(inst)
			if ap != null:
				var anim_list := ap.get_animation_list()
				for anim_name in anim_list:
					var anim: Animation = ap.get_animation(anim_name)
					_cached_anim_library[anim_name] = anim
					_cached_track_maps[anim_name] = _build_track_map(anim)
			inst.queue_free()
	_load_af_clips()


static func _find_player_recursive(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_player_recursive(c)
		if found != null:
			return found
	return null


## Loads the ActionForge sword clips (GLB PackedScene with a nested
## AnimationPlayer) into the shared library under AF_SWORD_* names.
static func _load_af_clips() -> void:
	if _af_clips_loaded:
		return
	_af_clips_loaded = true
	_load_af_clip(AF_SWORD_ATTACK_PATH, "sword_attack", AF_SWORD_ATTACK)
	_load_af_clip(AF_SWORD_COMBO_PATH, "sword_regular_combo", AF_SWORD_COMBO)


static func _find_skeleton_recursive(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found := _find_skeleton_recursive(c)
		if found != null:
			return found
	return null


static func _build_af_retarget_data(anim: Animation, sk: Skeleton3D) -> Dictionary:
	var b_pelvis := sk.find_bone("pelvis")
	var b_spine1 := sk.find_bone("spine_01")
	var b_spine2 := sk.find_bone("spine_02")
	var b_spine3 := sk.find_bone("spine_03")
	var b_clav_r := sk.find_bone("clavicle_r")
	var b_uarm_r := sk.find_bone("upperarm_r")
	var b_larm_r := sk.find_bone("lowerarm_r")
	var b_hand_r := sk.find_bone("hand_r")
	var b_clav_l := sk.find_bone("clavicle_l")
	var b_uarm_l := sk.find_bone("upperarm_l")
	var b_larm_l := sk.find_bone("lowerarm_l")
	var b_hand_l := sk.find_bone("hand_l")
	var b_thigh_r := sk.find_bone("thigh_r")
	var b_calf_r := sk.find_bone("calf_r")
	var b_foot_r := sk.find_bone("foot_r")
	var b_thigh_l := sk.find_bone("thigh_l")
	var b_calf_l := sk.find_bone("calf_l")
	var b_foot_l := sk.find_bone("foot_l")
	
	var trks := {
		"pelvis": _find_bone_rot_track(anim, "pelvis"),
		"spine2": _find_bone_rot_track(anim, "spine_02"),
		"spine3": _find_bone_rot_track(anim, "spine_03"),
		"clav_r": _find_bone_rot_track(anim, "clavicle_r"),
		"uarm_r": _find_bone_rot_track(anim, "upperarm_r"),
		"larm_r": _find_bone_rot_track(anim, "lowerarm_r"),
		"hand_r": _find_bone_rot_track(anim, "hand_r"),
		"clav_l": _find_bone_rot_track(anim, "clavicle_l"),
		"uarm_l": _find_bone_rot_track(anim, "upperarm_l"),
		"larm_l": _find_bone_rot_track(anim, "lowerarm_l"),
		"hand_l": _find_bone_rot_track(anim, "hand_l"),
		"thigh_r": _find_bone_rot_track(anim, "thigh_r"),
		"calf_r": _find_bone_rot_track(anim, "calf_r"),
		"thigh_l": _find_bone_rot_track(anim, "thigh_l"),
		"calf_l": _find_bone_rot_track(anim, "calf_l")
	}
	var rests := {
		"pelvis": sk.get_bone_rest(b_pelvis) if b_pelvis >= 0 else Transform3D.IDENTITY,
		"spine1": sk.get_bone_rest(b_spine1) if b_spine1 >= 0 else Transform3D.IDENTITY,
		"spine2": sk.get_bone_rest(b_spine2) if b_spine2 >= 0 else Transform3D.IDENTITY,
		"spine3": sk.get_bone_rest(b_spine3) if b_spine3 >= 0 else Transform3D.IDENTITY,
		"clav_r": sk.get_bone_rest(b_clav_r) if b_clav_r >= 0 else Transform3D.IDENTITY,
		"uarm_r": sk.get_bone_rest(b_uarm_r) if b_uarm_r >= 0 else Transform3D.IDENTITY,
		"larm_r": sk.get_bone_rest(b_larm_r) if b_larm_r >= 0 else Transform3D.IDENTITY,
		"hand_r": sk.get_bone_rest(b_hand_r) if b_hand_r >= 0 else Transform3D.IDENTITY,
		"clav_l": sk.get_bone_rest(b_clav_l) if b_clav_l >= 0 else Transform3D.IDENTITY,
		"uarm_l": sk.get_bone_rest(b_uarm_l) if b_uarm_l >= 0 else Transform3D.IDENTITY,
		"larm_l": sk.get_bone_rest(b_larm_l) if b_larm_l >= 0 else Transform3D.IDENTITY,
		"hand_l": sk.get_bone_rest(b_hand_l) if b_hand_l >= 0 else Transform3D.IDENTITY,
		"thigh_r": sk.get_bone_rest(b_thigh_r) if b_thigh_r >= 0 else Transform3D.IDENTITY,
		"calf_r": sk.get_bone_rest(b_calf_r) if b_calf_r >= 0 else Transform3D.IDENTITY,
		"foot_r": sk.get_bone_rest(b_foot_r) if b_foot_r >= 0 else Transform3D.IDENTITY,
		"thigh_l": sk.get_bone_rest(b_thigh_l) if b_thigh_l >= 0 else Transform3D.IDENTITY,
		"calf_l": sk.get_bone_rest(b_calf_l) if b_calf_l >= 0 else Transform3D.IDENTITY,
		"foot_l": sk.get_bone_rest(b_foot_l) if b_foot_l >= 0 else Transform3D.IDENTITY
	}
	var data := { "trks": trks, "rests": rests, "anim": anim }
	data["base_0"] = _calc_af_fk_vectors(anim, data, 0.0)
	data["base_1"] = _calc_af_fk_vectors(anim, data, 1.0)
	data["base_2"] = _calc_af_fk_vectors(anim, data, 2.0)
	return data


static func _find_bone_rot_track(anim: Animation, bone_name: String) -> int:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D and anim.track_get_path(t).get_subname(0) == bone_name:
			return t
	return -1


static func _calc_af_fk_vectors(anim: Animation, data: Dictionary, t: float) -> Dictionary:
	var trks: Dictionary = data["trks"]
	var rests: Dictionary = data["rests"]
	
	var q_pelvis: Quaternion = anim.rotation_track_interpolate(int(trks["pelvis"]), t) if int(trks["pelvis"]) >= 0 else Quaternion.IDENTITY
	var q_spine2: Quaternion = anim.rotation_track_interpolate(int(trks["spine2"]), t) if int(trks["spine2"]) >= 0 else Quaternion.IDENTITY
	var q_spine3: Quaternion = anim.rotation_track_interpolate(int(trks["spine3"]), t) if int(trks["spine3"]) >= 0 else Quaternion.IDENTITY
	
	var x_pelvis: Transform3D = Transform3D(Basis(q_pelvis), (rests["pelvis"] as Transform3D).origin)
	var x_spine1: Transform3D = x_pelvis * (rests["spine1"] as Transform3D)
	var x_spine2: Transform3D = x_spine1 * Transform3D(Basis(q_spine2), (rests["spine2"] as Transform3D).origin)
	var x_spine3: Transform3D = x_spine2 * Transform3D(Basis(q_spine3), (rests["spine3"] as Transform3D).origin)
	
	# Right arm FK
	var q_clav_r: Quaternion = anim.rotation_track_interpolate(int(trks["clav_r"]), t) if int(trks["clav_r"]) >= 0 else Quaternion.IDENTITY
	var q_uarm_r: Quaternion = anim.rotation_track_interpolate(int(trks["uarm_r"]), t) if int(trks["uarm_r"]) >= 0 else Quaternion.IDENTITY
	var q_larm_r: Quaternion = anim.rotation_track_interpolate(int(trks["larm_r"]), t) if int(trks["larm_r"]) >= 0 else Quaternion.IDENTITY
	var q_hand_r: Quaternion = anim.rotation_track_interpolate(int(trks["hand_r"]), t) if int(trks["hand_r"]) >= 0 else Quaternion.IDENTITY
	
	var x_clav_r: Transform3D = x_spine3 * Transform3D(Basis(q_clav_r), (rests["clav_r"] as Transform3D).origin)
	var x_uarm_r: Transform3D = x_clav_r * Transform3D(Basis(q_uarm_r), (rests["uarm_r"] as Transform3D).origin)
	var x_larm_r: Transform3D = x_uarm_r * Transform3D(Basis(q_larm_r), (rests["larm_r"] as Transform3D).origin)
	var x_hand_r: Transform3D = x_larm_r * Transform3D(Basis(q_hand_r), (rests["hand_r"] as Transform3D).origin)
	
	# Left arm FK
	var q_clav_l: Quaternion = anim.rotation_track_interpolate(int(trks["clav_l"]), t) if int(trks["clav_l"]) >= 0 else Quaternion.IDENTITY
	var q_uarm_l: Quaternion = anim.rotation_track_interpolate(int(trks["uarm_l"]), t) if int(trks["uarm_l"]) >= 0 else Quaternion.IDENTITY
	var q_larm_l: Quaternion = anim.rotation_track_interpolate(int(trks["larm_l"]), t) if int(trks["larm_l"]) >= 0 else Quaternion.IDENTITY
	var q_hand_l: Quaternion = anim.rotation_track_interpolate(int(trks["hand_l"]), t) if int(trks["hand_l"]) >= 0 else Quaternion.IDENTITY
	
	var x_clav_l: Transform3D = x_spine3 * Transform3D(Basis(q_clav_l), (rests["clav_l"] as Transform3D).origin)
	var x_uarm_l: Transform3D = x_clav_l * Transform3D(Basis(q_uarm_l), (rests["uarm_l"] as Transform3D).origin)
	var x_larm_l: Transform3D = x_uarm_l * Transform3D(Basis(q_larm_l), (rests["larm_l"] as Transform3D).origin)
	var x_hand_l: Transform3D = x_larm_l * Transform3D(Basis(q_hand_l), (rests["hand_l"] as Transform3D).origin)
	
	# Right leg FK
	var q_thigh_r: Quaternion = anim.rotation_track_interpolate(int(trks["thigh_r"]), t) if int(trks["thigh_r"]) >= 0 else Quaternion.IDENTITY
	var q_calf_r: Quaternion = anim.rotation_track_interpolate(int(trks["calf_r"]), t) if int(trks["calf_r"]) >= 0 else Quaternion.IDENTITY
	var x_thigh_r: Transform3D = x_pelvis * Transform3D(Basis(q_thigh_r), (rests["thigh_r"] as Transform3D).origin)
	var x_calf_r: Transform3D = x_thigh_r * Transform3D(Basis(q_calf_r), (rests["calf_r"] as Transform3D).origin)
	var x_foot_r: Transform3D = x_calf_r * (rests["foot_r"] as Transform3D)

	# Left leg FK
	var q_thigh_l: Quaternion = anim.rotation_track_interpolate(int(trks["thigh_l"]), t) if int(trks["thigh_l"]) >= 0 else Quaternion.IDENTITY
	var q_calf_l: Quaternion = anim.rotation_track_interpolate(int(trks["calf_l"]), t) if int(trks["calf_l"]) >= 0 else Quaternion.IDENTITY
	var x_thigh_l: Transform3D = x_pelvis * Transform3D(Basis(q_thigh_l), (rests["thigh_l"] as Transform3D).origin)
	var x_calf_l: Transform3D = x_thigh_l * Transform3D(Basis(q_calf_l), (rests["calf_l"] as Transform3D).origin)
	var x_foot_l: Transform3D = x_calf_l * (rests["foot_l"] as Transform3D)

	var v_arm_r: Vector3 = (x_larm_r.origin - x_uarm_r.origin).normalized()
	var v_fore_r: Vector3 = (x_hand_r.origin - x_larm_r.origin).normalized()
	var v_arm_l: Vector3 = (x_larm_l.origin - x_uarm_l.origin).normalized()
	var v_fore_l: Vector3 = (x_hand_l.origin - x_larm_l.origin).normalized()
	var v_torso: Vector3 = (x_spine3.origin - x_pelvis.origin).normalized()

	var v_thigh_r: Vector3 = (x_calf_r.origin - x_thigh_r.origin).normalized()
	var v_calf_r: Vector3 = (x_foot_r.origin - x_calf_r.origin).normalized()
	var v_thigh_l: Vector3 = (x_calf_l.origin - x_thigh_l.origin).normalized()
	var v_calf_l: Vector3 = (x_foot_l.origin - x_calf_l.origin).normalized()

	return {
		"arm_pitch_r": atan2(-v_arm_r.z, -v_arm_r.y),
		"arm_yaw_r": atan2(v_arm_r.x, sqrt(v_arm_r.y * v_arm_r.y + v_arm_r.z * v_arm_r.z)),
		"elbow_flex_r": acos(clampf(v_arm_r.dot(v_fore_r), -1.0, 1.0)),
		"arm_pitch_l": atan2(-v_arm_l.z, -v_arm_l.y),
		"arm_yaw_l": atan2(v_arm_l.x, sqrt(v_arm_l.y * v_arm_l.y + v_arm_l.z * v_arm_l.z)),
		"elbow_flex_l": acos(clampf(v_arm_l.dot(v_fore_l), -1.0, 1.0)),
		"torso_yaw": x_spine3.basis.get_euler().y,
		"torso_pitch": atan2(-v_torso.z, v_torso.y),
		"thigh_pitch_r": atan2(-v_thigh_r.z, -v_thigh_r.y),
		"thigh_yaw_r": atan2(v_thigh_r.x, sqrt(v_thigh_r.y * v_thigh_r.y + v_thigh_r.z * v_thigh_r.z)),
		"knee_flex_r": acos(clampf(v_thigh_r.dot(v_calf_r), -1.0, 1.0)),
		"thigh_pitch_l": atan2(-v_thigh_l.z, -v_thigh_l.y),
		"thigh_yaw_l": atan2(v_thigh_l.x, sqrt(v_thigh_l.y * v_thigh_l.y + v_thigh_l.z * v_thigh_l.z)),
		"knee_flex_l": acos(clampf(v_thigh_l.dot(v_calf_l), -1.0, 1.0))
	}


func _sample_vector_retarget(clip_name: String, t: float, combo_step: int, is_left: bool, include_legs: bool = false) -> Dictionary:
	if not _af_retarget_data.has(clip_name):
		return {}
	var data: Dictionary = _af_retarget_data[clip_name]
	var anim: Animation = data["anim"]
	var cur: Dictionary = _calc_af_fk_vectors(anim, data, t)
	
	var base_key := "base_0"
	if combo_step == 2 and data.has("base_1"):
		base_key = "base_1"
	elif combo_step == 3 and data.has("base_2"):
		base_key = "base_2"
	var base: Dictionary = data.get(base_key, data.get("base_0", {}))
	if base.is_empty():
		return {}
	
	var d_arm_pitch_r: float = wrapf(float(cur["arm_pitch_r"]) - float(base["arm_pitch_r"]), -PI, PI)
	var d_arm_yaw_r: float = wrapf(float(cur["arm_yaw_r"]) - float(base["arm_yaw_r"]), -PI, PI)
	var d_fore_r: float = float(cur["elbow_flex_r"]) - float(base["elbow_flex_r"])
	
	var d_arm_pitch_l: float = wrapf(float(cur["arm_pitch_l"]) - float(base["arm_pitch_l"]), -PI, PI)
	var d_arm_yaw_l: float = wrapf(float(cur["arm_yaw_l"]) - float(base["arm_yaw_l"]), -PI, PI)
	var d_fore_l: float = float(cur["elbow_flex_l"]) - float(base["elbow_flex_l"])
	
	var d_torso_yaw: float = wrapf(float(cur["torso_yaw"]) - float(base["torso_yaw"]), -PI, PI)
	var d_torso_pitch: float = wrapf(float(cur["torso_pitch"]) - float(base["torso_pitch"]), -PI, PI)
	
	var arm_r := Vector3(d_arm_pitch_r, d_arm_yaw_r, 0.0)
	var fore_r := Vector3(absf(d_fore_r) + deg_to_rad(15.0), 0.0, 0.0)
	var arm_l := Vector3(d_arm_pitch_l, d_arm_yaw_l, 0.0)
	var fore_l := Vector3(absf(d_fore_l) + deg_to_rad(15.0), 0.0, 0.0)
	var body := Vector3(d_torso_pitch * 0.4, d_torso_yaw, 0.0)
	var head := Vector3(0.0, d_torso_yaw * 0.5, 0.0)
	
	var pose := {
		"body": body,
		"head": head,
		"arm_right": arm_r,
		"forearm_right": fore_r,
		"arm_left": arm_l,
		"forearm_left": fore_l
	}

	if include_legs and cur.has("thigh_pitch_r") and base.has("thigh_pitch_r"):
		var d_thigh_pitch_r: float = wrapf(float(cur["thigh_pitch_r"]) - float(base["thigh_pitch_r"]), -PI, PI)
		var d_thigh_yaw_r: float = wrapf(float(cur["thigh_yaw_r"]) - float(base["thigh_yaw_r"]), -PI, PI)
		var d_knee_r: float = float(cur["knee_flex_r"]) - float(base["knee_flex_r"])
		
		var d_thigh_pitch_l: float = wrapf(float(cur["thigh_pitch_l"]) - float(base["thigh_pitch_l"]), -PI, PI)
		var d_thigh_yaw_l: float = wrapf(float(cur["thigh_yaw_l"]) - float(base["thigh_yaw_l"]), -PI, PI)
		var d_knee_l: float = float(cur["knee_flex_l"]) - float(base["knee_flex_l"])

		# Pitch scaled for mecha mass (~0.55), yaw for foot alignment, roll keeps base abduction (knees outward)
		var leg_r := Vector3(d_thigh_pitch_r * 0.55, d_thigh_yaw_r * 0.5, deg_to_rad(7.0))
		var shin_r := Vector3(-clampf(absf(d_knee_r) * 0.6 + deg_to_rad(10.0), 0.0, deg_to_rad(65.0)), 0.0, 0.0)
		var leg_l := Vector3(d_thigh_pitch_l * 0.55, d_thigh_yaw_l * 0.5, -deg_to_rad(7.0))
		var shin_l := Vector3(-clampf(absf(d_knee_l) * 0.6 + deg_to_rad(10.0), 0.0, deg_to_rad(65.0)), 0.0, 0.0)

		pose["leg_right"] = leg_r
		pose["shin_right"] = shin_r
		pose["leg_left"] = leg_l
		pose["shin_left"] = shin_l

	return pose


static func _load_af_clip(path: String, src_anim_name: String, cache_name: String) -> void:
	if _cached_anim_library.has(cache_name):
		return
	if not ResourceLoader.exists(path):
		push_warning("MechaActionAnimator: AF clip not found at " + path)
		return
	var res = load(path)
	if res == null or not (res is PackedScene):
		push_warning("MechaActionAnimator: Failed to load AF clip from " + path)
		return
	var inst = (res as PackedScene).instantiate()
	var ap: AnimationPlayer = _find_player_recursive(inst)
	if ap == null:
		push_warning("MechaActionAnimator: No AnimationPlayer in " + path)
		inst.queue_free()
		return
	if not ap.has_animation(src_anim_name):
		# Fall back to the first animation when the GLB was re-exported with a
		# different take name instead of failing silently.
		var anim_list := ap.get_animation_list()
		if anim_list.is_empty():
			inst.queue_free()
			return
		src_anim_name = anim_list[0]
	var anim: Animation = ap.get_animation(src_anim_name)
	_cached_anim_library[cache_name] = anim
	_cached_track_maps[cache_name] = _build_track_map(anim)
	var sk := _find_skeleton_recursive(inst)
	if sk != null:
		_af_retarget_data[cache_name] = _build_af_retarget_data(anim, sk)
	inst.queue_free()


## True when both ActionForge sword clips are cached and drivable.
static func has_af_clips() -> bool:
	_ensure_library_cached()
	return _cached_anim_library.has(AF_SWORD_ATTACK) and _cached_anim_library.has(AF_SWORD_COMBO)


static func _build_track_map(anim: Animation) -> Dictionary:
	var tmap: Dictionary = {}
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := str(anim.track_get_path(t)).to_lower()
		# --- Mech_00 (Rigify-style) ---
		if "arm_stretch.l" in path or ("shoulder.l" in path and not tmap.has("arm_left")):
			tmap["arm_left"] = t
		elif "forearm_stretch.l" in path or ("arm_twist.l" in path and not tmap.has("forearm_left")):
			tmap["forearm_left"] = t
		elif "arm_stretch.r" in path or ("shoulder.r" in path and not tmap.has("arm_right")):
			tmap["arm_right"] = t
		elif "forearm_stretch.r" in path or ("arm_twist.r" in path and not tmap.has("forearm_right")):
			tmap["forearm_right"] = t
		elif "spine_01" in path and not tmap.has("body"):
			tmap["body"] = t
		elif "thigh_stretch.l" in path:
			tmap["leg_left"] = t
		elif "leg_stretch.l" in path:
			tmap["shin_left"] = t
		elif "thigh_stretch.r" in path:
			tmap["leg_right"] = t
		elif "leg_stretch.r" in path:
			tmap["shin_right"] = t
		# --- ActionForge (UE mannequin-style: upperarm_l, lowerarm_r, thigh_l, calf_r) ---
		elif "upperarm_l" in path and not tmap.has("arm_left"):
			tmap["arm_left"] = t
		elif "lowerarm_l" in path and not tmap.has("forearm_left"):
			tmap["forearm_left"] = t
		elif "upperarm_r" in path and not tmap.has("arm_right"):
			tmap["arm_right"] = t
		elif "lowerarm_r" in path and not tmap.has("forearm_right"):
			tmap["forearm_right"] = t
		# Wrist snap: hand tracks merge into their forearm (below) — the game
		# rig has no hand pivots, and the snap is the most visible part of a
		# slash. Matched before the head rules ("hand" never matches "head").
		elif ("hand_r" in path or "hand.r" in path) and not tmap.has("hand_right"):
			tmap["hand_right"] = t
		elif ("hand_l" in path or "hand.l" in path) and not tmap.has("hand_left"):
			tmap["hand_left"] = t
		elif ("spine_02" in path or "spine_03" in path) and not tmap.has("body"):
			tmap["body"] = t
		elif "thigh_l" in path and not tmap.has("leg_left"):
			tmap["leg_left"] = t
		elif ("calf_l" in path) and not tmap.has("shin_left"):
			tmap["shin_left"] = t
		elif "thigh_r" in path and not tmap.has("leg_right"):
			tmap["leg_right"] = t
		elif ("calf_r" in path) and not tmap.has("shin_right"):
			tmap["shin_right"] = t
		# Head last: "head" also matches nothing else ("hand" has no "head"),
		# neck_01 is the fallback when the Head bone track is missing.
		elif (path.ends_with(":head") or (":head" in path) or path.ends_with("head")) and not tmap.has("head"):
			tmap["head"] = t
		elif "neck_01" in path and not tmap.has("head"):
			tmap["head"] = t
		elif "head" in path and "hand" not in path and not tmap.has("head"):
			tmap["head"] = t
	return tmap


# Custom dynamic pacing for enemy melee wind-up vs strike acceleration
var is_custom_pacing: bool = false
var windup_fraction: float = 0.35
var windup_speed: float = 0.60
var strike_speed: float = 2.40


class ShootChannel:
	var anim_name: String = ""
	var anim_time: float = 0.0
	var anim_length: float = 0.0
	var anim_speed: float = 2.2
	var blend_weight: float = 0.0
	var fade_in_time: float = 0.02
	var fade_out_time: float = 0.12
	var is_active: bool = false
	var hand: String = "right"


var shoot_channel_left: ShootChannel = ShootChannel.new()
var shoot_channel_right: ShootChannel = ShootChannel.new()


## Plays an action clip by name (full-body or primary channel)
func play_action(anim_name: String, speed: float = 1.0, fade_in: float = 0.08, fade_out: float = 0.15) -> bool:
	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	if anim == null:
		return false

	current_anim_name = anim_name
	anim_time = 0.0
	anim_length = anim.length
	anim_speed = speed
	is_custom_pacing = false
	fade_in_time = maxf(fade_in, 0.01)
	fade_out_time = maxf(fade_out, 0.01)
	blend_weight = 0.0
	is_active = true
	melee_mode = false
	_begin_attack_lifecycle(anim_name)
	return true


## (Re)starts lifecycle bookkeeping for a newly played action. Called by
## play_action so every start — including combo-chain restarts — retires the
## previous attack: pending strikes/completions of the old swing vanish.
func _begin_attack_lifecycle(anim_name: String) -> void:
	_strike_idx = 0
	_pending_strikes = 0
	_completed_pending = false
	strike_times = _compute_strike_times(anim_name)
	# Rest pose per mapped joint (track value at clip start): melee deltas
	# are measured against this so foreign-rested takes retarget cleanly.
	_rest_euler.clear()
	_rest_quat.clear()
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(anim_name, {})
	if anim != null:
		for joint_key in tmap:
			var q: Quaternion = anim.rotation_track_interpolate(int(tmap[joint_key]), 0.0)
			_rest_euler[joint_key] = q.get_euler()
			_rest_quat[joint_key] = q


## Strike moments (clip seconds) from the weapon arm's own motion: peak
## forward angular velocity of the arm track = the visual contact instant.
## Multi-peak clips (3-hit combo) yield one strike per hit. Falls back to
## mid-clip when the clip has no usable arm track. Cached per start.
func _compute_strike_times(anim_name: String) -> Array:
	var anim: Animation = _cached_anim_library.get(anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(anim_name, {})
	if anim == null:
		return []
	var track_idx: int = tmap.get("arm_right", tmap.get("arm_left", -1))
	if track_idx < 0:
		return [anim.length * 0.5]
	var n := 64
	var vel: Array = []
	var prev := 0.0
	for i in range(n + 1):
		var t: float = anim.length * float(i) / float(n)
		var q: Quaternion = anim.rotation_track_interpolate(track_idx, t)
		var x: float = q.get_euler().x
		if i > 0:
			vel.append((x - prev) / (anim.length / float(n)))
		prev = x
	var peak := 0.0
	for v in vel:
		peak = maxf(peak, float(v))
	if peak <= 0.001:
		return [anim.length * 0.5]
	var strikes: Array = []
	var last_hit := -100
	for i in range(vel.size()):
		var v: float = vel[i]
		var left_ok := i == 0 or float(vel[i - 1]) <= v
		var right_ok := i == vel.size() - 1 or float(vel[i + 1]) <= v
		if left_ok and right_ok and v > peak * 0.4 and i - last_hit >= n / 12:
			strikes.append(anim.length * float(i + 1) / float(n))
			last_hit = i
	if strikes.is_empty():
		return [anim.length * 0.5]
	return strikes


## Fires once per crossed strike moment. Drives the single gameplay hit per
## visual contact (combo clips: one per hit).
func poll_strike() -> bool:
	if _pending_strikes > 0:
		_pending_strikes -= 1
		return true
	return false


## Fires exactly once when the active swing finishes (recovery done,
## ownership returns to locomotion/hold).
func poll_attack_complete() -> bool:
	if _completed_pending:
		_completed_pending = false
		return true
	return false


## Read-only lifecycle snapshot for telemetry/debugging:
## {attack_id, anim, active, time, strikes_total, strikes_fired}.
func telemetry_snapshot() -> Dictionary:
	return {
		"attack_id": attack_id,
		"anim": current_anim_name,
		"active": is_melee_active(),
		"time": anim_time,
		"strikes_total": strike_times.size(),
		"strikes_fired": _strike_idx,
	}


## Plays Enemy Melee Attack 1 with deliberate wind-up (ง้าง) accelerating into a fast forward slash
func play_enemy_melee(hand: String = "right", telegraph_dur: float = 0.5) -> bool:
	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Attack1%s" % side_suffix

	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(clip_name, null)
	if anim == null:
		clip_name = "Mech_Attack1_R"
		anim = _cached_anim_library.get(clip_name, null)
		if anim == null:
			return false

	current_anim_name = clip_name
	anim_time = 0.0
	anim_length = anim.length
	is_custom_pacing = true
	windup_fraction = 0.35

	# Scale windup speed so the windup pose spans the telegraph window cleanly
	var windup_clip_time := anim_length * windup_fraction
	if telegraph_dur > 0.05:
		windup_speed = windup_clip_time / telegraph_dur
	else:
		windup_speed = 0.65
	strike_speed = 2.40

	fade_in_time = 0.06
	fade_out_time = 0.15
	blend_weight = 0.0
	is_active = true
	attack_id += 1
	melee_mode = true
	return true


## Plays the ActionForge one-handed sword combo (มือเดียว):
## step 1 = single slash (sword_attack), step 2-3 = full 3-hit combo clip.
## Returns false when the AF clips are missing so callers can fall back to Mech_00.
func play_af_melee(hand: String = "right", forced_combo_step: int = 0) -> bool:
	_ensure_library_cached()
	var now := Time.get_ticks_msec()
	if forced_combo_step > 0:
		combo_index = clampi(forced_combo_step, 1, 3)
	elif now - last_attack_time_ms < COMBO_WINDOW_MS:
		combo_index = (combo_index % 3) + 1
	else:
		combo_index = 1
	last_attack_time_ms = now
	melee_hand = hand

	var clip_name := AF_SWORD_ATTACK if combo_index == 1 else AF_SWORD_COMBO
	if not _cached_anim_library.has(clip_name):
		return false

	# Drives the actual ActionForge clip:
	# Combo 1: sword_attack from 0.0s to 1.53s @1.7x speed (~0.90s)
	# Combo 2: sword_regular_combo Hit 2 from 1.00s to 2.00s @1.6x speed
	# Combo 3: sword_regular_combo Hit 3 from 2.00s to 3.00s @1.4x speed
	var play_speed := 1.7 if combo_index < 3 else 1.4
	var started := play_action(clip_name, play_speed, 0.05, 0.14)
	if started:
		attack_id += 1
		melee_mode = true
		if combo_index == 1:
			strike_times = [0.55]
		elif combo_index == 2:
			anim_time = 1.00
			anim_length = 2.00
			strike_times = [1.45]
			while _strike_idx < strike_times.size() and float(strike_times[_strike_idx]) < anim_time:
				_strike_idx += 1
		elif combo_index == 3:
			anim_time = 2.00
			anim_length = 3.00
			strike_times = [2.35]
			while _strike_idx < strike_times.size() and float(strike_times[_strike_idx]) < anim_time:
				_strike_idx += 1
	return started


func play_enemy_af_melee(hand: String = "right", telegraph_dur: float = 0.5) -> bool:
	_ensure_library_cached()
	var anim: Animation = _cached_anim_library.get(AF_SWORD_ATTACK, null)
	if anim == null:
		return false
	melee_hand = hand
	current_anim_name = AF_SWORD_ATTACK
	anim_time = 0.0
	anim_length = anim.length
	is_custom_pacing = true
	windup_fraction = 0.40
	var windup_clip_time := anim_length * windup_fraction
	if telegraph_dur > 0.05:
		windup_speed = windup_clip_time / telegraph_dur
	else:
		windup_speed = 0.65
	strike_speed = 2.40
	fade_in_time = 0.06
	fade_out_time = 0.15
	blend_weight = 0.0
	is_active = true
	attack_id += 1
	melee_mode = true
	combo_index = 1
	_begin_attack_lifecycle(AF_SWORD_ATTACK)
	return true


func play_melee(hand: String, forced_combo_step: int = 0) -> void:
	var now := Time.get_ticks_msec()
	if forced_combo_step > 0:
		combo_index = clampi(forced_combo_step, 1, 3)
	elif now - last_attack_time_ms < COMBO_WINDOW_MS:
		combo_index = (combo_index % 3) + 1
	else:
		combo_index = 1
	last_attack_time_ms = now

	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Attack%d%s" % [combo_index, side_suffix]
	
	# Attack 1 & 2 are fast fluid strikes; Attack 3 is a heavy smash
	var play_speed := 1.75 if combo_index < 3 else 1.35
	if play_action(clip_name, play_speed, 0.06, 0.14):
		attack_id += 1
		melee_mode = true


## Plays Shooting Recoil on the isolated firing arm without affecting the other arm
func play_shoot(hand: String, is_heavy: bool = false) -> void:
	_ensure_library_cached()
	var channel := shoot_channel_left if hand == "left" else shoot_channel_right
	var side_suffix := "_L" if hand == "left" else "_R"
	var clip_name := "Mech_Shoot2%s" % side_suffix if is_heavy else "Mech_Shoot%s" % side_suffix

	var anim: Animation = _cached_anim_library.get(clip_name, null)
	if anim == null:
		clip_name = "Mech_Shoot%s" % side_suffix
		anim = _cached_anim_library.get(clip_name, null)
		if anim == null:
			return

	channel.anim_name = clip_name
	channel.anim_time = 0.0
	channel.anim_length = anim.length
	channel.anim_speed = 2.4 if not is_heavy else 1.8
	channel.fade_in_time = 0.02
	channel.fade_out_time = 0.12 if not is_heavy else 0.18
	channel.blend_weight = 0.0
	channel.is_active = true
	channel.hand = hand


## Plays Shoulder Cannon / Missile Pod Barrage Launch
func play_shoulder_shoot(variant: int = 1) -> void:
	var clip_name := "Mech_ShoulderShoot%d" % clampi(variant, 1, 2)
	play_action(clip_name, 1.6, 0.08, 0.15)


## Plays Heavy Hit Flinch
func play_get_hit() -> void:
	play_action("Mech_GetHit", 1.8, 0.04, 0.12)


## Plays Core Breach Death Collapse
func play_die() -> void:
	play_action("Mech_Die", 1.0, 0.12, 0.30)


func is_playing() -> bool:
	return (is_active and blend_weight > 0.001) or shoot_channel_left.is_active or shoot_channel_right.is_active


## Advances playback timelines and calculates crossfade envelopes
func update(delta: float) -> void:
	# 1. Main Action Channel
	if is_active:
		if is_custom_pacing:
			var norm_pos := anim_time / maxf(anim_length, 0.001)
			var current_step_speed := windup_speed if norm_pos < windup_fraction else strike_speed
			anim_time += delta * current_step_speed
		else:
			anim_time += delta * anim_speed

		# Strike edges: every crossed strike moment queues exactly one hit.
		while _strike_idx < strike_times.size() and anim_time >= float(strike_times[_strike_idx]):
			_strike_idx += 1
			_pending_strikes += 1

		if anim_time < fade_in_time:
			blend_weight = clampf(anim_time / fade_in_time, 0.0, 1.0)
		elif anim_time >= anim_length - fade_out_time:
			var remaining := maxf(anim_length - anim_time, 0.0)
			blend_weight = clampf(remaining / fade_out_time, 0.0, 1.0)
		else:
			blend_weight = 1.0

		if anim_time >= anim_length:
			is_active = false
			blend_weight = 0.0
			_completed_pending = true
	else:
		blend_weight = move_toward(blend_weight, 0.0, delta / 0.15)

	# 2. Per-Hand Shoot Channels
	_update_shoot_channel(shoot_channel_left, delta)
	_update_shoot_channel(shoot_channel_right, delta)


func _update_shoot_channel(channel: ShootChannel, delta: float) -> void:
	if not channel.is_active:
		channel.blend_weight = move_toward(channel.blend_weight, 0.0, delta / 0.10)
		return

	channel.anim_time += delta * channel.anim_speed

	if channel.anim_time < channel.fade_in_time:
		channel.blend_weight = clampf(channel.anim_time / channel.fade_in_time, 0.0, 1.0)
	elif channel.anim_time >= channel.anim_length - channel.fade_out_time:
		var remaining := maxf(channel.anim_length - channel.anim_time, 0.0)
		channel.blend_weight = clampf(remaining / channel.fade_out_time, 0.0, 1.0)
	else:
		channel.blend_weight = 1.0

	if channel.anim_time >= channel.anim_length:
		channel.is_active = false
		channel.blend_weight = 0.0



## Evaluates dynamic sword combo kinematics in Godot mecha pivot space
func _eval_sword_kinematics(combo_step: int, phase: float, is_left: bool) -> Dictionary:
	var side_mult := -1.0 if is_left else 1.0
	var arm_key := "arm_left" if is_left else "arm_right"
	var off_arm_key := "arm_right" if is_left else "arm_left"
	var fore_key := "forearm_left" if is_left else "forearm_right"
	var off_fore_key := "forearm_right" if is_left else "forearm_left"
	
	var body_rot := Vector3.ZERO
	var arm_rot := Vector3.ZERO
	var fore_rot := Vector3.ZERO
	var off_arm_rot := Vector3.ZERO
	var off_fore_rot := Vector3.ZERO
	var head_rot := Vector3.ZERO

	if combo_step == 1:
		# Step 1: Broad diagonal slash from right across to left
		if phase < 0.28:
			var w := phase / 0.28
			var ew := ease(w, -2.0)
			body_rot = Vector3(deg_to_rad(-4.0 * ew), deg_to_rad(-22.0 * side_mult * ew), deg_to_rad(3.0 * ew))
			arm_rot = Vector3(deg_to_rad(-18.0 * ew), deg_to_rad(-35.0 * side_mult * ew), deg_to_rad(20.0 * side_mult * ew))
			fore_rot = Vector3(deg_to_rad(lerpf(35.0, 75.0, ew)), 0.0, 0.0)
			off_arm_rot = Vector3(deg_to_rad(22.0 * ew), deg_to_rad(-15.0 * side_mult * ew), 0.0)
			off_fore_rot = Vector3(deg_to_rad(55.0 * ew), 0.0, 0.0)
			head_rot = Vector3(deg_to_rad(3.0 * ew), deg_to_rad(12.0 * side_mult * ew), 0.0)
		elif phase < 0.62:
			var s := (phase - 0.28) / (0.62 - 0.28)
			var es := ease(s, 0.5)
			body_rot = Vector3(
				deg_to_rad(lerpf(-4.0, 10.0, es)),
				deg_to_rad(lerpf(-22.0, 32.0, es) * side_mult),
				deg_to_rad(lerpf(3.0, -4.0, es))
			)
			arm_rot = Vector3(
				deg_to_rad(lerpf(-18.0, 38.0, es)),
				deg_to_rad(lerpf(-35.0, 58.0, es) * side_mult),
				deg_to_rad(lerpf(20.0, -12.0, es) * side_mult)
			)
			fore_rot = Vector3(deg_to_rad(lerpf(75.0, 24.0, es)), 0.0, 0.0)
			off_arm_rot = Vector3(deg_to_rad(lerpf(22.0, 14.0, es)), deg_to_rad(lerpf(-15.0, 20.0, es) * side_mult), 0.0)
			off_fore_rot = Vector3(deg_to_rad(lerpf(55.0, 35.0, es)), 0.0, 0.0)
			head_rot = Vector3(deg_to_rad(lerpf(3.0, -5.0, es)), deg_to_rad(lerpf(12.0, -15.0, es) * side_mult), 0.0)
		else:
			var r := (phase - 0.62) / (1.0 - 0.62)
			var er := ease(r, 0.5)
			body_rot = Vector3(deg_to_rad(lerpf(10.0, 0.0, er)), deg_to_rad(lerpf(32.0, 0.0, er) * side_mult), 0.0)
			arm_rot = Vector3(deg_to_rad(lerpf(38.0, 0.0, er)), deg_to_rad(lerpf(58.0, 0.0, er) * side_mult), deg_to_rad(lerpf(-12.0, 0.0, er) * side_mult))
			fore_rot = Vector3(deg_to_rad(lerpf(24.0, 0.0, er)), 0.0, 0.0)
			off_arm_rot = Vector3(deg_to_rad(lerpf(14.0, 0.0, er)), 0.0, 0.0)
			off_fore_rot = Vector3(deg_to_rad(lerpf(35.0, 0.0, er)), 0.0, 0.0)
			head_rot = Vector3(deg_to_rad(lerpf(-5.0, 0.0, er)), 0.0, 0.0)
	elif combo_step == 2:
		# Step 2: Uppercut diagonal backhand slash from low left to high right
		if phase < 0.22:
			var w := phase / 0.22
			body_rot = Vector3(deg_to_rad(6.0 * w), deg_to_rad(25.0 * side_mult * w), 0.0)
			arm_rot = Vector3(deg_to_rad(5.0 * w), deg_to_rad(40.0 * side_mult * w), deg_to_rad(-10.0 * side_mult * w))
			fore_rot = Vector3(deg_to_rad(lerpf(20.0, 50.0, w)), 0.0, 0.0)
		elif phase < 0.58:
			var s := (phase - 0.22) / (0.58 - 0.22)
			var es := ease(s, 0.5)
			body_rot = Vector3(
				deg_to_rad(lerpf(6.0, -8.0, es)),
				deg_to_rad(lerpf(25.0, -28.0, es) * side_mult),
				deg_to_rad(lerpf(0.0, 6.0, es))
			)
			arm_rot = Vector3(
				deg_to_rad(lerpf(5.0, 55.0, es)),
				deg_to_rad(lerpf(40.0, -32.0, es) * side_mult),
				deg_to_rad(lerpf(-10.0, 32.0, es) * side_mult)
			)
			fore_rot = Vector3(deg_to_rad(lerpf(50.0, 36.0, es)), 0.0, 0.0)
		else:
			var r := (phase - 0.58) / (1.0 - 0.58)
			var er := ease(r, 0.5)
			body_rot = Vector3(deg_to_rad(lerpf(-8.0, 0.0, er)), deg_to_rad(lerpf(-28.0, 0.0, er) * side_mult), 0.0)
			arm_rot = Vector3(deg_to_rad(lerpf(55.0, 0.0, er)), deg_to_rad(lerpf(-32.0, 0.0, er) * side_mult), deg_to_rad(lerpf(32.0, 0.0, er) * side_mult))
			fore_rot = Vector3(deg_to_rad(lerpf(36.0, 0.0, er)), 0.0, 0.0)
	else:
		# Step 3: Heavy Overhead Smash (Finisher)
		if phase < 0.30:
			var w := phase / 0.30
			body_rot = Vector3(deg_to_rad(-14.0 * w), 0.0, 0.0)
			arm_rot = Vector3(deg_to_rad(75.0 * w), deg_to_rad(-10.0 * side_mult * w), deg_to_rad(15.0 * side_mult * w))
			fore_rot = Vector3(deg_to_rad(lerpf(30.0, 85.0, w)), 0.0, 0.0)
			off_arm_rot = Vector3(deg_to_rad(45.0 * w), 0.0, 0.0)
			off_fore_rot = Vector3(deg_to_rad(60.0 * w), 0.0, 0.0)
		elif phase < 0.65:
			var s := (phase - 0.30) / (0.65 - 0.30)
			var es := ease(s, 0.4)
			body_rot = Vector3(deg_to_rad(lerpf(-14.0, 24.0, es)), 0.0, 0.0)
			arm_rot = Vector3(
				deg_to_rad(lerpf(75.0, -16.0, es)),
				deg_to_rad(lerpf(-10.0, 0.0, es) * side_mult),
				deg_to_rad(lerpf(15.0, 5.0, es) * side_mult)
			)
			fore_rot = Vector3(deg_to_rad(lerpf(85.0, 68.0, es)), 0.0, 0.0)
			off_arm_rot = Vector3(deg_to_rad(lerpf(45.0, -10.0, es)), 0.0, 0.0)
			off_fore_rot = Vector3(deg_to_rad(lerpf(60.0, 50.0, es)), 0.0, 0.0)
		else:
			var r := (phase - 0.65) / (1.0 - 0.65)
			var er := ease(r, 0.5)
			body_rot = Vector3(deg_to_rad(lerpf(24.0, 0.0, er)), 0.0, 0.0)
			arm_rot = Vector3(deg_to_rad(lerpf(-16.0, 0.0, er)), 0.0, 0.0)
			fore_rot = Vector3(deg_to_rad(lerpf(68.0, 0.0, er)), 0.0, 0.0)
			off_arm_rot = Vector3(deg_to_rad(lerpf(-10.0, 0.0, er)), 0.0, 0.0)
			off_fore_rot = Vector3(deg_to_rad(lerpf(50.0, 0.0, er)), 0.0, 0.0)

	return {
		"body": body_rot,
		arm_key: arm_rot,
		fore_key: fore_rot,
		off_arm_key: off_arm_rot,
		off_fore_key: off_fore_rot,
		"head": head_rot
	}


## Blends keyframe rotations onto the mech's joints dictionary
func apply_to_joints(joints: Dictionary, master_weight: float = 1.0, apply_legs: bool = false) -> void:
	# 1. Main action animation (Melee, Die, GetHit, Shoulder)
	var effective_main := blend_weight * master_weight
	if effective_main > 0.001:
		if melee_mode and current_anim_name.begins_with("AF_") and _af_retarget_data.has(current_anim_name):
			var sword_pose := _sample_vector_retarget(current_anim_name, anim_time, combo_index, melee_hand == "left", apply_legs)
			for joint_key in sword_pose:
				var node: Node3D = joints.get(joint_key + "_mesh", null)
				if node == null:
					node = joints.get(joint_key, null)
				if node == null or not is_instance_valid(node):
					continue
				var target_euler: Vector3 = sword_pose[joint_key]
				var blend := effective_main
				node.rotation.x = lerp_angle(node.rotation.x, target_euler.x, blend)
				node.rotation.y = lerp_angle(node.rotation.y, target_euler.y, blend)
				node.rotation.z = lerp_angle(node.rotation.z, target_euler.z, blend)
		else:
			var anim: Animation = _cached_anim_library.get(current_anim_name, null)
			var tmap: Dictionary = _cached_track_maps.get(current_anim_name, {})
			if anim != null and not tmap.is_empty():
				var sample_t := clampf(anim_time, 0.0, anim_length)
				for joint_key in tmap:
					if melee_mode and not (str(joint_key) in MELEE_UPPER_KEYS) and not apply_legs:
						continue
					var track_idx: int = tmap[joint_key]
					var node: Node3D = joints.get(joint_key + "_mesh", null)
					if node == null:
						node = joints.get(joint_key, null)
					if node == null or not is_instance_valid(node):
						continue
					var q: Quaternion = anim.rotation_track_interpolate(track_idx, sample_t)
					var target_euler: Vector3 = q.get_euler()
					var blend := effective_main
					node.rotation.x = lerp_angle(node.rotation.x, target_euler.x, blend)
					if joint_key in ["arm_left", "arm_right", "forearm_left", "forearm_right", "body"]:
						node.rotation.y = lerp_angle(node.rotation.y, target_euler.y, blend)
						node.rotation.z = lerp_angle(node.rotation.z, target_euler.z, blend)

	# 2. Left Shoot Recoil (Isolated to left arm + torso kick)
	_apply_shoot_channel_to_joints(shoot_channel_left, joints, master_weight)

	# 3. Right Shoot Recoil (Isolated to right arm + torso kick)
	_apply_shoot_channel_to_joints(shoot_channel_right, joints, master_weight)


func _apply_shoot_channel_to_joints(channel: ShootChannel, joints: Dictionary, master_weight: float) -> void:
	var effective_weight := channel.blend_weight * master_weight
	if effective_weight <= 0.001:
		return

	var anim: Animation = _cached_anim_library.get(channel.anim_name, null)
	var tmap: Dictionary = _cached_track_maps.get(channel.anim_name, {})
	if anim == null or tmap.is_empty():
		return

	var sample_t := clampf(channel.anim_time, 0.0, channel.anim_length)
	var is_left := (channel.hand == "left")

	# Recoil kickback angle computed from keyframe curve
	# Only affect the specific shooting arm joints + subtle body kick
	var arm_key := "arm_left" if is_left else "arm_right"
	var forearm_key := "forearm_left" if is_left else "forearm_right"

	if tmap.has(arm_key):
		var node: Node3D = joints.get(arm_key + "_mesh", null)
		if node == null:
			node = joints.get(arm_key, null)
		if node != null and is_instance_valid(node):
			var q: Quaternion = anim.rotation_track_interpolate(tmap[arm_key], sample_t)
			var target_euler: Vector3 = q.get_euler()
			# Additive recoil pitch layered over current aim angle
			node.rotation.x = lerp_angle(node.rotation.x, node.rotation.x + target_euler.x * 0.45, effective_weight)
			node.rotation.y = lerp_angle(node.rotation.y, 0.0, effective_weight)
			node.rotation.z = lerp_angle(node.rotation.z, 0.0, effective_weight)

	if tmap.has(forearm_key):
		var node: Node3D = joints.get(forearm_key + "_mesh", null)
		if node == null:
			node = joints.get(forearm_key, null)
		if node != null and is_instance_valid(node):
			var q: Quaternion = anim.rotation_track_interpolate(tmap[forearm_key], sample_t)
			var target_euler: Vector3 = q.get_euler()
			node.rotation.x = lerp_angle(node.rotation.x, node.rotation.x + target_euler.x * 0.35, effective_weight)
			node.rotation.y = lerp_angle(node.rotation.y, 0.0, effective_weight)
			node.rotation.z = lerp_angle(node.rotation.z, 0.0, effective_weight)

	# Subtle chest/torso recoil kick
	if tmap.has("body"):
		var body_node: Node3D = joints.get("body_mesh", null)
		if body_node == null:
			body_node = joints.get("body", null)
		if body_node != null and is_instance_valid(body_node):
			var q_body: Quaternion = anim.rotation_track_interpolate(tmap["body"], sample_t)
			var body_euler: Vector3 = q_body.get_euler()
			body_node.rotation.x = lerp_angle(body_node.rotation.x, body_node.rotation.x + body_euler.x * 0.25, effective_weight)
