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

	print("WEAPON_LAYER_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("WEAPON_LAYER_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_WEAPON_LAYER_TESTS_PASSED")
		get_tree().quit(0)


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
