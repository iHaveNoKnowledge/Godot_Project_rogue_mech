extends Node
## WEAPON LAYER VERIFY — base run + weapon upper-body layers stay separable.
##
## 1. Every bone mask is upper-body-only; every pose is lower-body-free
##    (no baking, no full-body duplication by construction).
## 2. Applying rifle/sword/heavy over a mid-stride base pose moves ONLY
##    masked arm joints; legs, feet, body and head stay bit-identical.
## 3. Rifle -> sword switch changes only the arms (same legs underneath).
## 4. Mask filtering: a primary-hand mask ignores the support-arm pose keys.
## 5. WEAPON_NONE applies nothing.

const Layer = preload("res://scripts/mecha/mecha_weapon_layer.gd")

var _fails := 0
var _checks := 0
var _joints := {}


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("WEAPON_LAYER OK: " + name)
	else:
		_fails += 1
		printerr("WEAPON_LAYER FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_build_mock_rig()

	_check(Layer.is_mask_upper_body_only(Layer.MASK_RIFLE), "rifle mask is upper-body-only")
	_check(Layer.is_mask_upper_body_only(Layer.MASK_RIFLE_PRIMARY), "rifle-primary mask is upper-body-only")
	_check(Layer.is_mask_upper_body_only(Layer.MASK_SWORD), "sword mask is upper-body-only")
	_check(Layer.is_mask_upper_body_only(Layer.MASK_HEAVY), "heavy mask is upper-body-only")
	_check(not Layer.is_mask_upper_body_only(["arm_right", "leg_left"]), "validator rejects a leg in a mask")
	_check(Layer.is_pose_lower_body_free(Layer.pose_rifle()), "rifle pose writes no lower body")
	_check(Layer.is_pose_lower_body_free(Layer.pose_sword()), "sword pose writes no lower body")
	_check(Layer.is_pose_lower_body_free(Layer.pose_heavy()), "heavy pose writes no lower body")
	_check(not Layer.is_pose_lower_body_free({"leg_left": {"x": 0.5}}), "validator rejects a leg in a pose")

	# Mid-stride base pose: leaned torso, split legs, pumping arms.
	_pose_base_run()
	for weapon in ["rifle", "sword", "heavy"]:
		_pose_base_run()
		var snap: Dictionary = Layer.snapshot_lower_body(_joints)
		var applied: Array = Layer.apply_weapon(_joints, weapon, 1.0)
		_check(not applied.is_empty(), weapon + " layer applies to arm joints")
		_check(Layer.lower_body_matches(_joints, snap), weapon + " leaves legs/feet/body/head bit-identical")
		_check(_arms_moved(weapon), weapon + " actually poses the arms")

	# Rifle -> sword: same legs, different arms.
	_pose_base_run()
	Layer.apply_weapon(_joints, "rifle", 1.0)
	var rifle_arms := _arm_snapshot()
	var rifle_legs: Dictionary = Layer.snapshot_lower_body(_joints)
	Layer.apply_weapon(_joints, "sword", 1.0)
	_check(Layer.lower_body_matches(_joints, rifle_legs), "rifle->sword keeps identical legs")
	_check(_arm_snapshot() != rifle_arms, "rifle->sword changes only the arms")

	# Mask filtering: primary-hand mask must not touch the support arm.
	_pose_base_run()
	var left_before: Vector3 = (_joints["arm_left"] as Node3D).rotation
	var applied_primary: Array = Layer.apply_layer(
		_joints, Layer.pose_rifle(), Layer.MASK_RIFLE_PRIMARY, 1.0)
	_check(applied_primary.has("arm_right"), "primary mask drives weapon arm")
	_check(not applied_primary.has("arm_left"), "primary mask skips support arm")
	_check((_joints["arm_left"] as Node3D).rotation == left_before, "support arm untouched by primary mask")

	# WEAPON_NONE is a no-op.
	_pose_base_run()
	var snap_none: Dictionary = Layer.snapshot_lower_body(_joints)
	var arms_before := _arm_snapshot()
	_check(Layer.apply_weapon(_joints, "none", 1.0).is_empty(), "none applies nothing")
	_check(Layer.lower_body_matches(_joints, snap_none), "none preserves lower body")
	_check(_arm_snapshot() == arms_before, "none preserves arms")

	_run_runtime_simulation()

	print("WEAPON_LAYER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("WEAPON_LAYER_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_WEAPON_LAYER_TESTS_PASSED")
		get_tree().quit(0)
# ─── Runtime simulation: real Kimodo sprint underneath every layer ────
# Steps frames of valkren_sprint_run.json as the base (including the run's
# OWN arm swing, which each weapon layer must override), then proves
# legs/torso track the run exactly while arms follow the hold pose.
const SPRINT_JSON := "res://tools/kimodo/samples/valkren_sprint_run.json"
const JSON_TO_JOINT := {
	"Body": "body", "Head": "head",
	"ArmLeft": "arm_left", "ArmRight": "arm_right",
	"ForearmLeft": "forearm_left", "ForearmRight": "forearm_right",
	"LegLeft": "leg_left", "LegRight": "leg_right",
	"ShinLeft": "shin_left", "ShinRight": "shin_right",
	"FootLeft": "foot_left", "FootRight": "foot_right",
}


func _run_runtime_simulation() -> void:
	if not FileAccess.file_exists(SPRINT_JSON):
		_check(false, "runtime sprint JSON present")
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPRINT_JSON))
	var rec: Dictionary = data[data.keys()[0]]
	var joints: Dictionary = rec["joints"]
	var n: int = ((joints["Body"] as Dictionary)["rot"] as Array).size()
	_check(n == 44, "runtime sprint has 44 run frames")

	for weapon in ["rifle", "sword", "heavy"]:
		var mask: Array = Layer.mask_for_weapon(weapon)
		var pose: Dictionary = Layer.pose_for_weapon(weapon)
		var legs_ok := true
		var torso_ok := true
		var arms_hold := true
		for f in [0, 15, 30, n - 1]:
			_apply_base_frame(joints, f)
			Layer.apply_layer(_joints, pose, mask, 1.0)
			if not _base_matches(joints, f, true):
				legs_ok = false
			if not _base_matches(joints, f, false):
				torso_ok = false
			for key in pose.keys():
				if str(key) in mask and not _joint_matches(key, pose[key]):
					arms_hold = false
		_check(legs_ok, weapon + ": legs track the live run every sampled frame")
		_check(torso_ok, weapon + ": torso tracks the live run every sampled frame")
		_check(arms_hold, weapon + ": arms hold the weapon pose, not the run swing")

	# TEST 1, one-handed rifle: weapon arm holds, support arm keeps the run.
	_apply_base_frame(joints, 15)
	Layer.apply_layer(_joints, Layer.pose_rifle(), Layer.MASK_RIFLE_PRIMARY, 1.0)
	_check(_joint_matches("arm_right", (Layer.pose_rifle()["arm_right"] as Dictionary)),
		"primary: weapon arm holds the rifle")
	_check(_joint_matches_base(joints, 15, "arm_left"),
		"primary: support arm keeps the base run swing")
	_check(_base_matches(joints, 15, true), "primary: legs untouched")

	# Mid-run weapon switch: rifle -> sword -> heavy, legs never move.
	_apply_base_frame(joints, 20)
	Layer.apply_weapon(_joints, "rifle", 1.0)
	var legs_rifle: Dictionary = Layer.snapshot_lower_body(_joints)
	_apply_base_frame(joints, 20)
	Layer.apply_weapon(_joints, "sword", 1.0)
	_check(Layer.lower_body_matches(_joints, legs_rifle), "runtime rifle->sword keeps identical legs")
	_apply_base_frame(joints, 20)
	Layer.apply_weapon(_joints, "heavy", 1.0)
	_check(Layer.lower_body_matches(_joints, legs_rifle), "runtime rifle->heavy keeps identical legs")


func _build_mock_rig() -> void:
	for key in ["body", "head", "arm_left", "arm_right", "forearm_left",
			"forearm_right", "leg_left", "leg_right", "shin_left",
			"shin_right", "foot_left", "foot_right"]:
		var n := Node3D.new()
		n.name = key
		add_child(n)
		_joints[key] = n


func _pose_base_run() -> void:
	(_joints["body"] as Node3D).rotation = Vector3(deg_to_rad(-18.0), 0, 0)
	(_joints["head"] as Node3D).rotation = Vector3(deg_to_rad(-6.0), 0, 0)
	(_joints["leg_left"] as Node3D).rotation = Vector3(deg_to_rad(30.0), 0, 0)
	(_joints["leg_right"] as Node3D).rotation = Vector3(deg_to_rad(-25.0), 0, 0)
	(_joints["shin_left"] as Node3D).rotation = Vector3(deg_to_rad(-40.0), 0, 0)
	(_joints["shin_right"] as Node3D).rotation = Vector3(deg_to_rad(-15.0), 0, 0)
	(_joints["foot_left"] as Node3D).rotation = Vector3.ZERO
	(_joints["foot_right"] as Node3D).rotation = Vector3.ZERO
	(_joints["arm_left"] as Node3D).rotation = Vector3(deg_to_rad(-12.0), 0, 0)
	(_joints["arm_right"] as Node3D).rotation = Vector3(deg_to_rad(14.0), 0, 0)
	(_joints["forearm_left"] as Node3D).rotation = Vector3(deg_to_rad(35.0), 0, 0)
	(_joints["forearm_right"] as Node3D).rotation = Vector3(deg_to_rad(35.0), 0, 0)


func _arm_snapshot() -> Array:
	var out: Array = []
	for key in ["arm_left", "arm_right", "forearm_left", "forearm_right"]:
		out.append((_joints[key] as Node3D).rotation)
	return out


func _arms_moved(weapon: String) -> bool:
	var want: Dictionary = Layer.pose_for_weapon(weapon)
	for key in want.keys():
		var node: Node3D = _joints[key]
		var tgt: Dictionary = want[key]
		var expect := Vector3(float(tgt.get("x", 0.0)), float(tgt.get("y", 0.0)), float(tgt.get("z", 0.0)))
		if (node.rotation - expect).length() > 0.0001:
			return false
	return true


func _apply_base_frame(clip_joints: Dictionary, f: int) -> void:
	for json_key in JSON_TO_JOINT.keys():
		var node: Node3D = _joints[JSON_TO_JOINT[json_key]]
		var jd: Dictionary = clip_joints[json_key]
		var r: Array = (jd["rot"] as Array)[f]
		node.rotation = Vector3(
			deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
		node.position = Vector3(0, float((jd["off_y"] as Array)[f]), 0)


func _legs_match(clip_joints: Dictionary, f: int) -> bool:
	for json_key in ["LegLeft", "LegRight", "ShinLeft", "ShinRight", "FootLeft", "FootRight"]:
		var node: Node3D = _joints[JSON_TO_JOINT[json_key]]
		var jd: Dictionary = clip_joints[json_key]
		var r: Array = (jd["rot"] as Array)[f]
		var expect := Vector3(
			deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
		if (node.rotation - expect).length() > 0.0001:
			return false
		if absf(node.position.y - float((jd["off_y"] as Array)[f])) > 0.0001:
			return false
	return true


func _torso_match(clip_joints: Dictionary, f: int) -> bool:
	for json_key in ["Body", "Head"]:
		var node: Node3D = _joints[JSON_TO_JOINT[json_key]]
		var jd: Dictionary = clip_joints[json_key]
		var r: Array = (jd["rot"] as Array)[f]
		var expect := Vector3(
			deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
		if (node.rotation - expect).length() > 0.0001:
			return false
		if absf(node.position.y - float((jd["off_y"] as Array)[f])) > 0.0001:
			return false
	return true


func _base_matches(clip_joints: Dictionary, f: int, legs: bool) -> bool:
	if legs:
		return _legs_match(clip_joints, f)
	return _torso_match(clip_joints, f)


func _joint_matches(key: String, tgt: Dictionary) -> bool:
	var node: Node3D = _joints[key]
	var expect := Vector3(float(tgt.get("x", 0.0)), float(tgt.get("y", 0.0)), float(tgt.get("z", 0.0)))
	return (node.rotation - expect).length() <= 0.0001


func _joint_matches_base(clip_joints: Dictionary, f: int, key: String) -> bool:
	var json_key := ""
	for jk in JSON_TO_JOINT.keys():
		if str(JSON_TO_JOINT[jk]) == key:
			json_key = str(jk)
	if json_key == "":
		return false
	var jd: Dictionary = clip_joints[json_key]
	var r: Array = (jd["rot"] as Array)[f]
	var expect := Vector3(
		deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
	return ((_joints[key] as Node3D).rotation - expect).length() <= 0.0001
