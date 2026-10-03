class_name MechaWeaponLayer
extends RefCounted

## MECHA WEAPON LAYER — modular upper-body weapon animation.
##
## Architecture: ONE base locomotion (procedural gait or MechaClipRetarget
## run clip) owns root/pelvis/legs/torso every frame. Weapon layers run AFTER
## the base and override ONLY masked upper-body joints, so the same run works
## unarmed, with a rifle, sword or heavy weapon with zero full-body clip
## duplication:
##
##   Mechanical_Run + Rifle_Hold_UpperBody = mech running while holding rifle
##
## This formalizes the overlay order mecha_animation.gd already uses
## (_update_aim_arms / _update_shield_arm run last and override the arms).
## Integration hook: call apply_layer() after the base pose each frame
## (clip branch and procedural branch), before FootIK.
##
## Bone masks name joints-dict keys (see _build_joints_dict in
## mecha_animation.gd). The lower body is NEVER in any mask: validation
## helpers + unit tests reject any mask/pose touching it.
##
## Deliberate torso decision: even the two-handed mask excludes "body".
## Base owns the sprint lean; a weapon layer counter-leaning the torso every
## frame would fight it. Arms alone carry every hold pose below.

const JOINT_ARM_L := "arm_left"
const JOINT_ARM_R := "arm_right"
const JOINT_FOREARM_L := "forearm_left"
const JOINT_FOREARM_R := "forearm_right"

## Full bone mask: every joint a weapon layer may EVER touch.
const MASK_UPPER_BODY: Array = [
	JOINT_ARM_L, JOINT_ARM_R, JOINT_FOREARM_L, JOINT_FOREARM_R,
]
## Rifle: weapon-side arm aims, support arm braces underneath the barrel.
const MASK_RIFLE: Array = [
	JOINT_ARM_R, JOINT_FOREARM_R, JOINT_ARM_L, JOINT_FOREARM_L,
]
## Rifle primary-hand only (demonstrates mask filtering: pose keys outside
## the mask are ignored by apply_layer).
const MASK_RIFLE_PRIMARY: Array = [JOINT_ARM_R, JOINT_FOREARM_R]
## Sword: weapon arm cocks the blade, off arm keeps a guard.
const MASK_SWORD: Array = [
	JOINT_ARM_R, JOINT_FOREARM_R, JOINT_ARM_L, JOINT_FOREARM_L,
]
## Heavy two-handed: both arms braced forward as one unit.
const MASK_HEAVY: Array = [
	JOINT_ARM_R, JOINT_FOREARM_R, JOINT_ARM_L, JOINT_FOREARM_L,
]

## Joints the weapon layer must never write (base locomotion owns them).
const PROTECTED_LOWER_BODY: Array = [
	"leg_left", "leg_right", "shin_left", "shin_right",
	"foot_left", "foot_right", "body", "head",
]

const WEAPON_NONE := "none"
const WEAPON_RIFLE := "rifle"
const WEAPON_SWORD := "sword"
const WEAPON_HEAVY := "heavy"

const WEAPONS: Array = [WEAPON_NONE, WEAPON_RIFLE, WEAPON_SWORD, WEAPON_HEAVY]


## Pose format: {joint_key: {"x": rad, "y": rad, "z": rad}} — euler targets
## for that joint only. Missing axes default to 0.0 (neutral).
## Rifle hold: right arm levels the barrel (57 + 23 = 80 deg level per the
## aim math in mecha_animation.gd), left arm braces across underneath.
static func pose_rifle() -> Dictionary:
	return {
		JOINT_ARM_R: {"x": deg_to_rad(57.0)},
		JOINT_FOREARM_R: {"x": deg_to_rad(23.0)},
		JOINT_ARM_L: {"x": deg_to_rad(38.0), "y": deg_to_rad(-18.0)},
		JOINT_FOREARM_L: {"x": deg_to_rad(75.0)},
	}


## Sword hold: right arm cocked back with the blade up, left arm in guard.
static func pose_sword() -> Dictionary:
	return {
		JOINT_ARM_R: {"x": deg_to_rad(-30.0)},
		JOINT_FOREARM_R: {"x": deg_to_rad(75.0)},
		JOINT_ARM_L: {"x": deg_to_rad(20.0)},
		JOINT_FOREARM_L: {"x": deg_to_rad(45.0)},
	}


## Mirrored sword hold (left-hand blade): left arm cocks, right guards.
static func pose_sword_mirrored() -> Dictionary:
	return {
		JOINT_ARM_L: {"x": deg_to_rad(-30.0)},
		JOINT_FOREARM_L: {"x": deg_to_rad(75.0)},
		JOINT_ARM_R: {"x": deg_to_rad(20.0)},
		JOINT_FOREARM_R: {"x": deg_to_rad(45.0)},
	}


## Mirrored rifle hold (left-hand rifle, right hand empty): left arm levels
## the barrel, right arm braces across underneath.
static func pose_rifle_mirrored() -> Dictionary:
	return {
		JOINT_ARM_L: {"x": deg_to_rad(57.0)},
		JOINT_FOREARM_L: {"x": deg_to_rad(23.0)},
		JOINT_ARM_R: {"x": deg_to_rad(38.0), "y": deg_to_rad(18.0)},
		JOINT_FOREARM_R: {"x": deg_to_rad(75.0)},
	}


## Single-arm aim-ready (one ranged hand while the other hand is occupied):
## levels the barrel at the shared aim math (80 deg total, 72% arm).
static func pose_aim_arm(side: String) -> Dictionary:
	var arm := JOINT_ARM_R if side == "right" else JOINT_ARM_L
	var fore := JOINT_FOREARM_R if side == "right" else JOINT_FOREARM_L
	return {
		arm: {"x": deg_to_rad(57.0)},
		fore: {"x": deg_to_rad(23.0)},
	}


## Single-arm melee cock (one blade hand while the other hand is occupied).
static func pose_cock_arm(side: String) -> Dictionary:
	var arm := JOINT_ARM_R if side == "right" else JOINT_ARM_L
	var fore := JOINT_FOREARM_R if side == "right" else JOINT_FOREARM_L
	return {
		arm: {"x": deg_to_rad(-30.0)},
		fore: {"x": deg_to_rad(75.0)},
	}


## Single-arm heavy brace (symmetric: identical values either side).
static func pose_brace_arm(side: String) -> Dictionary:
	var arm := JOINT_ARM_R if side == "right" else JOINT_ARM_L
	var fore := JOINT_FOREARM_R if side == "right" else JOINT_FOREARM_L
	return {
		arm: {"x": deg_to_rad(40.0)},
		fore: {"x": deg_to_rad(55.0)},
	}


## Handling resolution from per-hand effective hold stances
## (WeaponVisualFactory.get_effective_hold_stance). Deterministic merge:
## - empty/shield/chassis-mounted hand contributes nothing (swing preserved,
##   shield raise and forearm mounts keep their existing owners).
## - a ranged hand aims; when the other hand is empty it takes the full
##   two-arm pose (brace/support), otherwise each hand keeps its own arm.
## - a melee hand cocks; pile-bunker/heavy hands brace (both arms when the
##   other hand is free, own arm only when it is occupied).
## Returns {"pose": {...}, "mask": [...]} over joints-dict keys.
static func handling_for_stances(left_stance: int, right_stance: int) -> Dictionary:
	var pose := {}
	var mask: Array = []
	var left_poses := _hand_fragment("left", left_stance, right_stance)
	var right_poses := _hand_fragment("right", right_stance, left_stance)
	for frag in [left_poses, right_poses]:
		for k in (frag as Dictionary).get("pose", {}):
			(pose as Dictionary)[k] = (frag as Dictionary)["pose"][k]
		for k in (frag as Dictionary).get("mask", []):
			if not (mask as Array).has(k):
				(mask as Array).append(k)
	return {"pose": pose, "mask": mask}


## Per-hand fragment: full two-arm pose when the other hand is free,
## own-arm fragment when it is occupied. Stances compared as ints so callers
## never need the enum imported.
static func _hand_fragment(side: String, own: int, other: int) -> Dictionary:
	var hs := WeaponPart.HoldStance
	var other_empty := other == hs.AUTO
	var pose := {}
	var mask: Array = []
	if own == hs.RANGED_RIFLE:
		if other_empty:
			var full := pose_rifle() if side == "right" else pose_rifle_mirrored()
			for k in full:
				pose[k] = full[k]
			mask = mask_for_weapon(WEAPON_RIFLE)
		else:
			var single := pose_aim_arm(side)
			for k in single:
				pose[k] = single[k]
			mask = [JOINT_ARM_R, JOINT_FOREARM_R] if side == "right" else [JOINT_ARM_L, JOINT_FOREARM_L]
	elif own == hs.MELEE_UPRIGHT:
		if other_empty:
			var fullm := pose_sword() if side == "right" else pose_sword_mirrored()
			for k in fullm:
				pose[k] = fullm[k]
			mask = mask_for_weapon(WEAPON_SWORD)
		else:
			var single := pose_cock_arm(side)
			for k in single:
				pose[k] = single[k]
			mask = [JOINT_ARM_R, JOINT_FOREARM_R] if side == "right" else [JOINT_ARM_L, JOINT_FOREARM_L]
	elif own == hs.PILE_BUNKER_GRIP:
		if other_empty:
			var fullh := pose_heavy()
			for k in fullh:
				pose[k] = fullh[k]
			mask = mask_for_weapon(WEAPON_HEAVY)
		else:
			var single := pose_brace_arm(side)
			for k in single:
				pose[k] = single[k]
			mask = [JOINT_ARM_R, JOINT_FOREARM_R] if side == "right" else [JOINT_ARM_L, JOINT_FOREARM_L]
	return {"pose": pose, "mask": mask}


## Heavy hold: both arms braced forward as one unit, deep piston elbows.
static func pose_heavy() -> Dictionary:
	return {
		JOINT_ARM_R: {"x": deg_to_rad(40.0)},
		JOINT_FOREARM_R: {"x": deg_to_rad(55.0)},
		JOINT_ARM_L: {"x": deg_to_rad(40.0)},
		JOINT_FOREARM_L: {"x": deg_to_rad(55.0)},
	}


static func pose_for_weapon(weapon: String) -> Dictionary:
	match weapon:
		WEAPON_RIFLE:
			return pose_rifle()
		WEAPON_SWORD:
			return pose_sword()
		WEAPON_HEAVY:
			return pose_heavy()
	return {}


static func mask_for_weapon(weapon: String) -> Array:
	match weapon:
		WEAPON_RIFLE:
			return MASK_RIFLE.duplicate()
		WEAPON_SWORD:
			return MASK_SWORD.duplicate()
		WEAPON_HEAVY:
			return MASK_HEAVY.duplicate()
	return []


## True if every joint in the mask is inside the upper-body set (i.e. the
## mask cannot touch lower-body locomotion joints).
static func is_mask_upper_body_only(mask: Array) -> bool:
	for j in mask:
		if not (str(j) in MASK_UPPER_BODY):
			return false
	return true


## True if the pose writes no protected lower-body joint.
static func is_pose_lower_body_free(pose: Dictionary) -> bool:
	for j in pose.keys():
		if str(j) in PROTECTED_LOWER_BODY:
			return false
	return true


## Applies pose onto joints-dict Node3Ds, filtered by mask.
## Only masked joints move (lerped by weight 0..1); everything else,
## including the whole lower body, is untouched. Returns applied joints.
static func apply_layer(joints: Dictionary, pose: Dictionary, mask: Array, weight: float) -> Array:
	var applied: Array = []
	var w := clampf(weight, 0.0, 1.0)
	if w <= 0.0:
		return applied
	for joint_key in mask:
		var jk := str(joint_key)
		if not pose.has(jk):
			continue
		var node: Node3D = joints.get(jk)
		if node == null:
			continue
		var tgt: Dictionary = pose[jk]
		var r := node.rotation
		node.rotation = Vector3(
			lerp_angle(r.x, float(tgt.get("x", 0.0)), w),
			lerp_angle(r.y, float(tgt.get("y", 0.0)), w),
			lerp_angle(r.z, float(tgt.get("z", 0.0)), w))
		applied.append(jk)
	return applied


## Convenience: apply a named weapon (pose + its mask) in one call.
static func apply_weapon(joints: Dictionary, weapon: String, weight: float) -> Array:
	if weapon == WEAPON_NONE:
		return []
	return apply_layer(joints, pose_for_weapon(weapon), mask_for_weapon(weapon), weight)


## Snapshot of every protected joint's rotation (for before/after proofs).
static func snapshot_lower_body(joints: Dictionary) -> Dictionary:
	var out := {}
	for jk in PROTECTED_LOWER_BODY:
		var node: Node3D = joints.get(jk)
		if node != null:
			out[jk] = node.rotation
	return out


## True if all protected joints match the snapshot exactly.
static func lower_body_matches(joints: Dictionary, snap: Dictionary) -> bool:
	for jk in snap.keys():
		var node: Node3D = joints.get(jk)
		if node == null:
			return false
		if (node.rotation - (snap[jk] as Vector3)).length() > 0.0001:
			return false
	return true
