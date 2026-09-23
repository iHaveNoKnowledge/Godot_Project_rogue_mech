extends Node
class_name MechaClipRetarget
## Drives the modular Node3D pivots (Head/Body/Arm*/Leg*) from an external
## clip instead of the procedural pose, so armor destruction keeps working:
## destroying a limb hides its meshes, the pivots (and the clip) carry on.
##
## Source: scenes/mecha/animations/innerframe_run_cycle_clean.glb — a
## full-body inner-frame rig already at game scale (head ~4.28m) with
## MechaRig bone names. Instantiated hidden (meshes freed), its
## AnimationPlayer stepped manually so sampling is deterministic.
##
## Transfer is kinematic and sagittal-only (rotation.x + hip bob): per frame
## each segment's swing is measured in skeleton space against its own rest
## pose, then written rest-relative onto the matching pivot. Immune to bone
## roll conventions; lateral/roll detail from the clip is skipped (v1).

const CLIP_SOURCES := {
	MechaRig.CLIP_RUN: "res://scenes/mecha/animations/innerframe_run_cycle_clean.glb",
	MechaRig.CLIP_AI_RUN: "res://scenes/mecha/animations/ai_mech_run.glb",
}

# The run clip's ground speed, measured from the baked cycle itself:
# stride ~3.73m x cadence/rate ~1.79 strides/s per unit rate, so foot travel
# matches body travel when rate = h_speed / 6.7 (audit 26de8ef: sync was
# 1.33/0.75/0.39 at 3.5/7/14 m/s with NATURAL_SPEED 5.0). MAX_RATE 1.0 holds
# sync through 7 m/s cruise; beyond that cadence caps deliberately (a heavy
# frame paddling at 2.5 Hz reads worse than mild slide at absolute max).
const NATURAL_SPEED := 6.7
const MIN_RATE := 0.2
const MAX_RATE := 1.0

static func rate_for_speed(h_speed: float) -> float:
	return clampf(h_speed / NATURAL_SPEED, MIN_RATE, MAX_RATE)

# Extra bones present in the clean clip (beyond the 16-bone game convention).
const TOE_L := "Bone_Toe_L"
const TOE_R := "Bone_Toe_R"

# bone -> pivot-key (keys match MechaWalkingSystem.build_joints / _build_joints_dict)
const SWING_JOINTS: Dictionary = {
	MechaRig.BONE_UPPER_ARM_L: "arm_left",
	MechaRig.BONE_UPPER_ARM_R: "arm_right",
	MechaRig.BONE_THIGH_L: "leg_left",
	MechaRig.BONE_THIGH_R: "leg_right",
	MechaRig.BONE_TORSO: "body",
	MechaRig.BONE_HEAD: "head",
}
# (proximal_bone, distal_bone) -> pivot-key for hinge flexion (elbow/knee/ankle)
const HINGE_JOINTS: Dictionary = {
	"forearm_left": [MechaRig.BONE_UPPER_ARM_L, MechaRig.BONE_LOWER_ARM_L],
	"forearm_right": [MechaRig.BONE_UPPER_ARM_R, MechaRig.BONE_LOWER_ARM_R],
	"shin_left": [MechaRig.BONE_THIGH_L, MechaRig.BONE_SHIN_L],
	"shin_right": [MechaRig.BONE_THIGH_R, MechaRig.BONE_SHIN_R],
	"foot_left": [MechaRig.BONE_SHIN_L, MechaRig.BONE_FOOT_L],
	"foot_right": [MechaRig.BONE_SHIN_R, MechaRig.BONE_FOOT_R],
}
# Stride emphasis: the 2.3m legs top out near a 2.9m stride, which reads
# as shuffling at 6-7 m/s cruise. A mild swing boost lengthens each step so
# cadence can stay lower; clamps keep knees from hyperextending and feet
# near the ground (no IK runs under the clip to fix them).
# Body pitch runs 30% high (less face-down): the baked crouch aims the
# chest at the ground, so the torso swing is scaled back toward upright.
# Scaling (not offsetting) keeps it bounded and wrap-safe.
const BODY_PITCH_SCALE := 0.7
const THIGH_BOOST := 1.15
const THIGH_MAX := 1.40 # ~80 deg
const SHIN_BOOST := 1.1
const SHIN_MIN := -2.18 # ~-125 deg
# Ankle clamp: the baked clip carries a strongly asymmetric right foot
# (measured runtime pivots: R min -2.28 rad vs L min -0.81). Past ~-63 deg
# the foot folds unrealistically, so bound the hinge output; the left foot's
# whole natural range sits inside the clamp and is untouched.
const FOOT_MIN := -1.1 # ~-63 deg
const FOOT_MAX := 0.9 # ~+52 deg
# Segment endpoints for swing measurement (bone -> its distal joint bone).
const SEGMENT_CHILD: Dictionary = {
	MechaRig.BONE_UPPER_ARM_L: MechaRig.BONE_LOWER_ARM_L,
	MechaRig.BONE_UPPER_ARM_R: MechaRig.BONE_LOWER_ARM_R,
	MechaRig.BONE_THIGH_L: MechaRig.BONE_SHIN_L,
	MechaRig.BONE_THIGH_R: MechaRig.BONE_SHIN_R,
	MechaRig.BONE_TORSO: MechaRig.BONE_NECK,
	MechaRig.BONE_HEAD: MechaRig.BONE_HEAD, # head has no child: pitch from its own local pose
}

var skeleton: Skeleton3D = null
var player: AnimationPlayer = null
var active_clip: String = ""
var _sources: Dictionary = {}
var _bone_cache: Dictionary = {}
var _rest_pitch: Dictionary = {}
var _rest_flex: Dictionary = {}
var _rest_hip_y: float = 0.0
var _orig_body_y: float = 0.0
var _body_seeded: bool = false


func _ready() -> void:
	for clip_name in CLIP_SOURCES:
		_build_source(clip_name, String(CLIP_SOURCES[clip_name]))
	if _sources.has(MechaRig.CLIP_RUN):
		_use_source(MechaRig.CLIP_RUN)


func _build_source(clip_name: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	if packed == null or not packed.can_instantiate():
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	# Hidden pose source: meshes are never rendered, only the skeleton moves.
	_free_meshes(inst)
	var skel := _find_skeleton(inst)
	var pl := _find_player(inst)
	if skel == null or pl == null:
		inst.queue_free()
		return
	if not pl.has_animation(clip_name):
		inst.queue_free()
		return
	var anim: Animation = pl.get_animation(clip_name)
	anim.loop_mode = Animation.LOOP_LINEAR
	pl.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	_sources[clip_name] = {"skeleton": skel, "player": pl}
	if active_clip == "":
		_use_source(clip_name)


func _use_source(clip_name: String) -> void:
	var src: Dictionary = _sources.get(clip_name, {})
	if src.is_empty():
		return
	skeleton = src["skeleton"]
	player = src["player"]
	active_clip = clip_name
	_bone_cache.clear()
	_cache_rest()
	player.play(clip_name)
	player.seek(randf() * player.current_animation_length, true)


func has_clip(clip_name: String) -> bool:
	return _sources.has(clip_name)


# Footfall fractions of the run loop (measured foot-minima per side),
# consumed by the animation layer to phase anything stride-synced
# (strafe overlay). Fired in order as the clip position advances.
const STEP_FRACS := [0.02, 0.19, 0.33, 0.55, 0.64, 0.86]
const STEP_RIGHT := [true, false, true, false, true, false]
var _last_step_pos: float = 0.0
func poll_step_events() -> Array:
	var out: Array = []
	if player == null:
		return out
	var length: float = player.current_animation_length
	if length <= 0.001:
		return out
	var pos: float = player.current_animation_position / length
	var old: float = _last_step_pos
	_last_step_pos = pos
	if pos < old:
		_collect_crossed(old, 1.0, out)
		_collect_crossed(0.0, pos, out)
	else:
		_collect_crossed(old, pos, out)
	return out


func _collect_crossed(a: float, b: float, out: Array) -> void:
	for i in range(STEP_FRACS.size()):
		var f: float = STEP_FRACS[i]
		if f > a and f <= b:
			out.append(STEP_RIGHT[i])


func play_clip(clip_name: String) -> void:
	if not has_clip(clip_name):
		return
	if active_clip != clip_name:
		_use_source(clip_name)


## Steps the clip and writes the pose onto the pivots. `joints` uses the
## _build_joints_dict keys (arm_left, shin_right, body, ...). `body_base_y`
## is the pivot's procedural rest height so the hip bob adds on top.
func advance_and_apply(delta: float, joints: Dictionary, body_base_y: float) -> void:
	if skeleton == null or player == null:
		return
	player.advance(delta)
	_apply_pose(joints, body_base_y)


func _cache_rest() -> void:
	_rest_pitch.clear()
	_rest_flex.clear()
	for bone in SWING_JOINTS:
		var child: String = SEGMENT_CHILD.get(bone, "")
		if child == "" or child == bone:
			continue
		_rest_pitch[bone] = _segment_pitch(_rest_dir(bone, child))
	for key in HINGE_JOINTS:
		var pair: Array = HINGE_JOINTS[key]
		var flex_rest := _hinge_angle(_rest_dir(pair[0], pair[1]), pair[0], pair[1], true)
		_rest_flex[key] = flex_rest
	var hip_idx: int = skeleton.find_bone(MechaRig.BONE_HIP)
	if hip_idx >= 0:
		_rest_hip_y = skeleton.get_bone_global_rest(hip_idx).origin.y


func _apply_pose(joints: Dictionary, body_base_y: float) -> void:
	if not _body_seeded:
		_orig_body_y = body_base_y
		_body_seeded = true
	# Swing segments (single-segment pitch, rest-relative).
	for bone in SWING_JOINTS:
		var pivot: Node3D = joints.get(SWING_JOINTS[bone])
		if pivot == null:
			continue
		if bone == MechaRig.BONE_HEAD:
			_apply_head(pivot)
			continue
		var child: String = SEGMENT_CHILD.get(bone, "")
		if child == "":
			continue
		var swing := wrapf(_segment_pitch(_pose_dir(bone, child)) - float(_rest_pitch.get(bone, 0.0)), -PI, PI)
		if bone == MechaRig.BONE_THIGH_L or bone == MechaRig.BONE_THIGH_R:
			swing = clampf(swing * THIGH_BOOST, -THIGH_MAX, THIGH_MAX)
		if bone == MechaRig.BONE_TORSO:
			swing *= BODY_PITCH_SCALE
		pivot.rotation.x = swing
		if bone != MechaRig.BONE_TORSO:
			pivot.rotation.y = 0.0
			pivot.rotation.z = 0.0
	# Hinge flexion (elbow/knee/ankle, rest-relative).
	for key in HINGE_JOINTS:
		var pivot: Node3D = joints.get(key)
		if pivot == null:
			continue
		var pair: Array = HINGE_JOINTS[key]
		var flex_now := _hinge_angle(_pose_dir(pair[0], pair[1]), pair[0], pair[1], false)
		var flex := wrapf(flex_now - float(_rest_flex.get(key, 0.0)), -PI, PI)
		if key == "shin_left" or key == "shin_right":
			flex = maxf(flex * SHIN_BOOST, SHIN_MIN)
		if key == "foot_left" or key == "foot_right":
			flex = clampf(flex, FOOT_MIN, FOOT_MAX)
		pivot.rotation.x = flex
	# Hip bob onto the body (delta only; skeleton is already at game scale).
	var body: Node3D = joints.get("body")
	if body != null:
		var hip_idx: int = skeleton.find_bone(MechaRig.BONE_HIP)
		if hip_idx >= 0:
			var bob: float = skeleton.get_bone_global_pose(hip_idx).origin.y - _rest_hip_y
			body.position.y = _orig_body_y + bob


func _apply_head(pivot: Node3D) -> void:
	var idx := _bone_idx(MechaRig.BONE_HEAD)
	if idx < 0:
		return
	# Head has no child segment: use its rest-relative local pitch directly.
	var rest_q := skeleton.get_bone_rest(idx).basis.get_rotation_quaternion().normalized()
	var pose_q := skeleton.get_bone_pose(idx).basis.get_rotation_quaternion().normalized()
	var delta_q := rest_q.inverse() * pose_q
	var e := delta_q.get_euler()
	pivot.rotation.x = e.x


## Direction from `bone` toward `child` in skeleton space (current pose).
func _pose_dir(bone: String, child: String) -> Vector3:
	var bi := _bone_idx(bone)
	var ci := _bone_idx(child)
	if bi < 0 or ci < 0:
		return Vector3.DOWN
	var a: Vector3 = skeleton.get_bone_global_pose(bi).origin
	var b: Vector3 = skeleton.get_bone_global_pose(ci).origin
	var d: Vector3 = b - a
	if d.length_squared() < 0.00000001:
		return Vector3.DOWN
	return d.normalized()


func _rest_dir(bone: String, child: String) -> Vector3:
	var bi := _bone_idx(bone)
	var ci := _bone_idx(child)
	if bi < 0 or ci < 0:
		return Vector3.DOWN
	var a: Vector3 = skeleton.get_bone_global_rest(bi).origin
	var b: Vector3 = skeleton.get_bone_global_rest(ci).origin
	var d: Vector3 = b - a
	if d.length_squared() < 0.00000001:
		return Vector3.DOWN
	return d.normalized()


## Sagittal pitch of a segment: rest -PI/2 points down, +PI/2 points up,
## 0 points forward (-Z). Matches pivot rotation.x convention.
static func _segment_pitch(d: Vector3) -> float:
	return atan2(d.y, -d.z)


## Signed hinge angle between proximal segment (bone->mid) and distal
## segment (mid->end). For rest=True the rest pose is measured.
func _hinge_angle(prox_dir: Vector3, prox_bone: String, mid_bone: String, rest: bool) -> float:
	var a := _segment_pitch(prox_dir)
	var mid_idx := _bone_idx(mid_bone)
	if mid_idx < 0:
		return 0.0
	# Distal segment: mid bone toward its own child.
	var distal_child := _distal_of(mid_bone)
	if distal_child == "":
		return 0.0
	var dd: Vector3
	if rest:
		dd = _rest_dir(mid_bone, distal_child)
	else:
		dd = _pose_dir(mid_bone, distal_child)
	var b := _segment_pitch(dd)
	return wrapf(b - a, -PI, PI)


func _distal_of(bone: String) -> String:
	match bone:
		MechaRig.BONE_UPPER_ARM_L:
			return MechaRig.BONE_LOWER_ARM_L
		MechaRig.BONE_UPPER_ARM_R:
			return MechaRig.BONE_LOWER_ARM_R
		MechaRig.BONE_LOWER_ARM_L:
			return MechaRig.BONE_HAND_L
		MechaRig.BONE_LOWER_ARM_R:
			return MechaRig.BONE_HAND_R
		MechaRig.BONE_THIGH_L:
			return MechaRig.BONE_SHIN_L
		MechaRig.BONE_THIGH_R:
			return MechaRig.BONE_SHIN_R
		MechaRig.BONE_SHIN_L:
			return MechaRig.BONE_FOOT_L
		MechaRig.BONE_SHIN_R:
			return MechaRig.BONE_FOOT_R
		MechaRig.BONE_FOOT_L:
			return TOE_L
		MechaRig.BONE_FOOT_R:
			return TOE_R
	return ""


func _bone_idx(bone: String) -> int:
	if _bone_cache.has(bone):
		return int(_bone_cache[bone])
	if skeleton == null:
		return -1
	var idx := skeleton.find_bone(bone)
	_bone_cache[bone] = idx
	return idx


func _free_meshes(n: Node) -> void:
	for c in n.get_children():
		_free_meshes(c)
		if c is MeshInstance3D:
			n.remove_child(c)
			c.queue_free()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null
