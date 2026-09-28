class_name KimodoClipPolicy
extends RefCounted

## KIMODO CLIP POLICY — validates converted Kimodo pilot clips before import.
##
## The Python converter (tools/kimodo/kimodo_npz_to_pilot.py) emits:
##   {clip: {duration, fps, frames, bones: {name: {q: [[w,x,y,z]], t: [[x,y,z]]}}}}
## with bone-local quaternions + pelvis-only translation deltas (af_retarget
## convention). This policy mirrors pilot_humanoid_limits_verify.gd so a bad
## clip fails fast here instead of inside AnimationPlayer/Blender.
##
## Rules:
##  1. Exactly the 19 pilot bones present, frame counts consistent.
##  2. Every number finite; every quaternion ~unit length (0.99..1.01).
##  3. Pelvis delta bounded (|axis| <= 1.5m — in-place authoring).
##  4. Non-pelvis translations ~zero (kit rest supplies segment lengths,
##     guarantees the <3% no-stretch rule by construction).

const PILOT_BONES: Array = [
	"pelvis", "spine_01", "spine_02", "neck_01", "Head",
	"clavicle_r", "clavicle_l", "upperarm_r", "upperarm_l",
	"lowerarm_r", "lowerarm_l", "hand_r", "hand_l",
	"thigh_r", "thigh_l", "calf_r", "calf_l", "foot_r", "foot_l",
]

const MIN_FRAMES := 4
const PELVIS_DELTA_LIMIT := 1.5
const NON_PELVIS_T_LIMIT := 0.001


static func required_bones() -> Array:
	return PILOT_BONES.duplicate()


static func validate_clip_dict(data: Dictionary) -> Array:
	var errors: Array = []
	if data.size() != 1:
		errors.append("expected exactly 1 clip, got %d" % data.size())
		return errors
	var clip: String = str(data.keys()[0])
	var rec: Dictionary = data[clip]
	if not rec.has("bones"):
		errors.append("clip %s missing 'bones'" % clip)
		return errors
	var bones: Dictionary = rec["bones"]
	var missing: Array = []
	for b in PILOT_BONES:
		if not bones.has(b):
			missing.append(b)
	if not missing.is_empty():
		errors.append("missing bones: %s" % str(missing))
		return errors
	var n: int = (bones["pelvis"] as Dictionary)["q"].size()
	if n < MIN_FRAMES:
		errors.append("too few frames: %d" % n)
		return errors
	for b in PILOT_BONES:
		var bd: Dictionary = bones[b]
		if (bd["q"] as Array).size() != n:
			errors.append("%s.q len %d != %d" % [b, (bd["q"] as Array).size(), n])
		if (bd["t"] as Array).size() != n:
			errors.append("%s.t len %d != %d" % [b, (bd["t"] as Array).size(), n])
	if not errors.is_empty():
		return errors
	for b in PILOT_BONES:
		var bd: Dictionary = bones[b]
		for i in range(n):
			var q: Array = (bd["q"] as Array)[i]
			var t: Array = (bd["t"] as Array)[i]
			for v in q:
				if not is_finite(float(v)):
					errors.append("%s.q[%d] non-finite" % [b, i])
					break
			for v in t:
				if not is_finite(float(v)):
					errors.append("%s.t[%d] non-finite" % [b, i])
					break
			var nrm: float = sqrt(
				float(q[0]) * float(q[0]) + float(q[1]) * float(q[1])
				+ float(q[2]) * float(q[2]) + float(q[3]) * float(q[3]))
			if nrm < 0.99 or nrm > 1.01:
				errors.append("%s.q[%d] not unit (%.3f)" % [b, i, nrm])
				break
			if b == "pelvis":
				for v in t:
					if absf(float(v)) > PELVIS_DELTA_LIMIT:
						errors.append("pelvis delta too large @f%d" % i)
						break
			else:
				for v in t:
					if absf(float(v)) > NON_PELVIS_T_LIMIT:
						errors.append("%s.t[%d] not ~zero (%.4f)" % [b, i, float(v)])
						break
		if not errors.is_empty():
			break
	return errors


static func clip_frame_count(data: Dictionary) -> int:
	if data.is_empty():
		return 0
	var rec: Dictionary = data[data.keys()[0]]
	return ((rec["bones"] as Dictionary)["pelvis"] as Dictionary)["q"].size()
