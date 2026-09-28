class_name KimodoValkrenPolicy
extends RefCounted

## KIMODO VALKREN POLICY — validates converted Kimodo clips for the Valkren
## mech rig (MechaBase Node3D hierarchy, NOT a humanoid skeleton).
##
## The Python transfer (tools/kimodo/kimodo_npz_to_valkren.py) emits:
##   {clip: {duration, fps, frames, foot_min_y, joints: {name: {rot, off_y}}}}
## with euler-degree rotations in Godot Node3D convention (+X pitch = swing
## forward, shin negative = knee flex, forearm positive = piston elbow,
## body negative X = charge lean) plus position.y deltas. See
## MechaWalkingSystem for the authoritative in-game ranges this mirrors.
##
## Rules:
##  1. Exactly the 12 Valkren joints present, frame counts consistent (>= 4).
##  2. Every number finite; every axis inside its mech limit.
##  3. 2-bone FK (hip 3.001 / shin 1.34 / foot 1.291, from mecha_base.tscn)
##     keeps both feet at/above rest (0.37m) minus 0.10m tolerance.

const VALKREN_JOINTS: Array = [
	"Body", "Head", "ArmLeft", "ArmRight", "ForearmLeft", "ForearmRight",
	"LegLeft", "LegRight", "ShinLeft", "ShinRight", "FootLeft", "FootRight",
]

# joint -> [x_min, x_max, yz_max_abs, off_min, off_max]
const LIMITS := {
	"Body": [-30.0, 10.0, 12.0, -0.35, 0.25],
	"Head": [-15.0, 15.0, 5.0, 0.0, 0.0],
	"ArmLeft": [-45.0, 45.0, 2.0, 0.0, 0.0],
	"ArmRight": [-45.0, 45.0, 2.0, 0.0, 0.0],
	"ForearmLeft": [20.0, 60.0, 2.0, 0.0, 0.0],
	"ForearmRight": [20.0, 60.0, 2.0, 0.0, 0.0],
	"LegLeft": [-60.0, 75.0, 2.0, 0.0, 0.35],
	"LegRight": [-60.0, 75.0, 2.0, 0.0, 0.35],
	"ShinLeft": [-90.0, 0.0, 2.0, 0.0, 0.0],
	"ShinRight": [-90.0, 0.0, 2.0, 0.0, 0.0],
	"FootLeft": [-3.0, 3.0, 3.0, 0.0, 0.0],
	"FootRight": [-3.0, 3.0, 3.0, 0.0, 0.0],
}

const MIN_FRAMES := 4
const HIP_Y := 3.001
const SHIN_LEN := 1.34
const FOOT_LEN := 1.291
const FOOT_REST_Y := 0.37
const FLOOR_TOLERANCE := 0.10


static func required_joints() -> Array:
	return VALKREN_JOINTS.duplicate()


static func fk_foot_y(thigh_deg: float, shin_deg: float, lift: float) -> float:
	var th := deg_to_rad(thigh_deg)
	var sh := deg_to_rad(shin_deg)
	return HIP_Y + lift - SHIN_LEN * cos(th) - FOOT_LEN * cos(th + sh)


static func min_foot_y(data: Dictionary) -> float:
	var rec: Dictionary = data[data.keys()[0]]
	var joints: Dictionary = rec["joints"]
	var n: int = ((joints["Body"] as Dictionary)["rot"] as Array).size()
	var worst := 1e9
	for f in range(n):
		for side in ["Left", "Right"]:
			var th := float((((joints["Leg" + side] as Dictionary)["rot"] as Array)[f] as Array)[0])
			var sh := float((((joints["Shin" + side] as Dictionary)["rot"] as Array)[f] as Array)[0])
			var li := float(((joints["Leg" + side] as Dictionary)["off_y"] as Array)[f])
			worst = minf(worst, fk_foot_y(th, sh, li))
	return worst


static func validate_clip_dict(data: Dictionary) -> Array:
	var errors: Array = []
	if data.size() != 1:
		errors.append("expected exactly 1 clip, got %d" % data.size())
		return errors
	var clip: String = str(data.keys()[0])
	var rec: Dictionary = data[clip]
	if not rec.has("joints"):
		errors.append("clip %s missing 'joints'" % clip)
		return errors
	var joints: Dictionary = rec["joints"]
	var missing: Array = []
	for j in VALKREN_JOINTS:
		if not joints.has(j):
			missing.append(j)
	if not missing.is_empty():
		errors.append("missing joints: %s" % str(missing))
		return errors
	var n: int = ((joints["Body"] as Dictionary)["rot"] as Array).size()
	if n < MIN_FRAMES:
		errors.append("too few frames: %d" % n)
		return errors
	for j in VALKREN_JOINTS:
		var jd: Dictionary = joints[j]
		var lim: Array = LIMITS[j]
		if ((jd["rot"] as Array).size() != n) or ((jd["off_y"] as Array).size() != n):
			errors.append("%s length mismatch" % j)
			continue
		for i in range(n):
			var r: Array = (jd["rot"] as Array)[i]
			var off := float((jd["off_y"] as Array)[i])
			for v in r:
				if not is_finite(float(v)):
					errors.append("%s.rot[%d] non-finite" % [j, i])
					break
			if not is_finite(off):
				errors.append("%s.off_y[%d] non-finite" % [j, i])
				break
			if float(r[0]) < float(lim[0]) - 0.001 or float(r[0]) > float(lim[1]) + 0.001:
				errors.append("%s.rot.x[%d]=%.1f outside [%.0f, %.0f]" % [j, i, float(r[0]), float(lim[0]), float(lim[1])])
				break
			if absf(float(r[1])) > float(lim[2]) + 0.001 or absf(float(r[2])) > float(lim[2]) + 0.001:
				errors.append("%s[%d] y/z exceeds %.0f deg" % [j, i, float(lim[2])])
				break
			if off < float(lim[3]) - 0.0001 or off > float(lim[4]) + 0.0001:
				errors.append("%s.off_y[%d]=%.3f outside [%.2f, %.2f]" % [j, i, off, float(lim[3]), float(lim[4])])
				break
		if not errors.is_empty():
			break
	if errors.is_empty():
		var worst := min_foot_y(data)
		if worst < FOOT_REST_Y - FLOOR_TOLERANCE:
			errors.append("FK floor fail: min foot y %.3f" % worst)
	return errors


static func clip_frame_count(data: Dictionary) -> int:
	if data.is_empty():
		return 0
	var rec: Dictionary = data[data.keys()[0]]
	return (((rec["joints"] as Dictionary)["Body"] as Dictionary)["rot"] as Array).size()


static func joint_x_range(data: Dictionary, joint: String) -> Array:
	var rec: Dictionary = data[data.keys()[0]]
	var arr: Array = (((rec["joints"] as Dictionary)[joint] as Dictionary)["rot"] as Array)
	var lo := 1e9
	var hi := -1e9
	for r in arr:
		lo = minf(lo, float((r as Array)[0]))
		hi = maxf(hi, float((r as Array)[0]))
	return [lo, hi]
