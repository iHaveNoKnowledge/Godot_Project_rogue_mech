class_name MechaJsonClip
extends RefCounted

## MECHA JSON CLIP — plays transfer-baked locomotion JSON
## (tools/kimodo: {clip: {fps, frames, joints: {name: {rot deg, off_y}},
## stance_l/stance_r}}) directly onto the modular Node3D pivots.
##
## Unlike the GLB sources in MechaClipRetarget (skeleton sampling), the JSON
## is already in pivot space: rotations apply as-is, positions as rest +
## delta. Feet pivots are NEVER touched (FootIK owns them).
##
## Step events come from the baked stance channels, so footstep audio fires
## on the exact touchdown/liftoff frames instead of a procedural timer:
##   poll_step_events() -> Array[bool], true = right foot touchdown.
##   poll_lift_events()  -> Array[bool], true = right foot liftoff.

const JSON_TO_JOINT := {
	"Body": "body", "Head": "head",
	"ArmLeft": "arm_left", "ArmRight": "arm_right",
	"ForearmLeft": "forearm_left", "ForearmRight": "forearm_right",
	"LegLeft": "leg_left", "LegRight": "leg_right",
	"ShinLeft": "shin_left", "ShinRight": "shin_right",
}

var clip_name := ""
var fps := 30.0
var frames := 0
var joints: Dictionary = {}
var stance_l: Array = []
var stance_r: Array = []
var cursor := 0.0
# Separate edge trackers per poll type so polling steps never consumes a
# lift edge (and vice versa) regardless of call order within a frame.
var _step_l := false
var _step_r := false
var _lift_l := false
var _lift_r := false


static func load_file(path: String) -> MechaJsonClip:
	var out := MechaJsonClip.new()
	if not FileAccess.file_exists(path):
		return out
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data.is_empty():
		return out
	out.clip_name = str(data.keys()[0])
	var rec: Dictionary = data[out.clip_name]
	out.fps = float(rec.get("fps", 30.0))
	out.joints = rec.get("joints", {})
	out.frames = (out.joints.get("Body", {}) as Dictionary).get("rot", []).size()
	out.stance_l = Array(rec.get("stance_l", []))
	out.stance_r = Array(rec.get("stance_r", []))
	if not out.stance_l.is_empty():
		out._step_l = bool(out.stance_l[0])
		out._lift_l = bool(out.stance_l[0])
	if not out.stance_r.is_empty():
		out._step_r = bool(out.stance_r[0])
		out._lift_r = bool(out.stance_r[0])
	return out


func is_loaded() -> bool:
	return frames >= 4 and not joints.is_empty()


## Advances the playhead (seconds, already rate-scaled by the caller) with
## seamless wrap. Returns nothing; poll_*_events() reports what crossed.
func advance(delta: float) -> void:
	if not is_loaded():
		return
	cursor = fmod(cursor + delta * fps, float(frames))
	if cursor < 0.0:
		cursor += float(frames)


## Writes the current frame onto pivot nodes. `bases` carries rest heights:
## {"body_y": float, "leg_l_y": float, "leg_r_y": float} — positions apply
## as rest + delta so the clip never fights assembled rest offsets.
func apply_to_joints(nodes: Dictionary, bases: Dictionary) -> void:
	if not is_loaded():
		return
	var f := int(floor(cursor)) % frames
	for json_key in JSON_TO_JOINT.keys():
		if not joints.has(json_key):
			continue
		var node: Node3D = nodes.get(JSON_TO_JOINT[json_key])
		if node == null:
			continue
		var jd: Dictionary = joints[json_key]
		var r: Array = (jd["rot"] as Array)[f]
		node.rotation = Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
	var body: Node3D = nodes.get("body")
	if body != null and joints.has("Body"):
		body.position.y = float(bases.get("body_y", body.position.y)) + float(((joints["Body"] as Dictionary)["off_y"] as Array)[f])
	for json_key in ["LegLeft", "LegRight"]:
		var leg: Node3D = nodes.get(JSON_TO_JOINT[json_key])
		if leg == null or not joints.has(json_key):
			continue
		var base_key := "leg_l_y" if json_key == "LegLeft" else "leg_r_y"
		leg.position.y = float(bases.get(base_key, leg.position.y)) + float(((joints[json_key] as Dictionary)["off_y"] as Array)[f])


func current_stance(side_right: bool) -> bool:
	if not is_loaded():
		return false
	var arr: Array = stance_r if side_right else stance_l
	if arr.is_empty():
		return false
	return bool(arr[int(floor(cursor)) % frames])


## Touchdown edges (0->1) since the last step poll. true = right foot.
func poll_step_events() -> Array:
	var out: Array = []
	if not is_loaded():
		return out
	var cl := current_stance(false)
	var cr := current_stance(true)
	if cl and not _step_l:
		out.append(false)
	if cr and not _step_r:
		out.append(true)
	_step_l = cl
	_step_r = cr
	return out


## Liftoff edges (1->0) since the last lift poll. true = right foot.
func poll_lift_events() -> Array:
	var out: Array = []
	if not is_loaded():
		return out
	var cl := current_stance(false)
	var cr := current_stance(true)
	if not cl and _lift_l:
		out.append(false)
	if not cr and _lift_r:
		out.append(true)
	_lift_l = cl
	_lift_r = cr
	return out
