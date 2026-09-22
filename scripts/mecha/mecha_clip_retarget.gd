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

# The run clip's natural ground speed: ~2.9m stride x 1.67 strides/s.
# Playback rate scales with mech speed around this so cadence tracks travel
# (slow pump while accelerating, full rate at speed) instead of shuffling.
const NATURAL_SPEED := 5.0
const MIN_RATE := 0.2
const MAX_RATE := 1.4

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
		if bone == MechaRig.BONE_TORSO:
			pivot.rotation.x = swing
		else:
			pivot.rotation.x = swing
			pivot.rotation.y = 0.0
			pivot.rotation.z = 0.0
	# Hinge flexion (elbow/knee/ankle, rest-relative).
	for key in HINGE_JOINTS:
		var pivot: Node3D = joints.get(key)
		if pivot == null:
			continue
		var pair: Array = HINGE_JOINTS[key]
		var flex_now := _hinge_angle(_pose_dir(pair[0], pair[1]), pair[0], pair[1], false)
		pivot.rotation.x = wrapf(flex_now - float(_rest_flex.get(key, 0.0)), -PI, PI)
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
