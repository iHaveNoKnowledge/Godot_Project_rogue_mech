class_name FrameVariantResolver
extends RefCounted

## ---------------------------------------------------------------------------
## FRAME VARIANT RESOLVER — single authoritative source for variant-dependent
## values (audit §8 mirror migration). Drivers keep working on logical pivots;
## this layer resolves WHAT those pivots (and their dependents) measure.
##
## LIFECYCLE (critical): apply_variant() MUST run BEFORE the instance enters
## the tree, so MechaAnimation/FootIK _ready() capture variant rest into their
## _original_* / _orig_* values. Applying after _ready makes drivers fight the
## variant back toward Standard (proven by audit probe).
## ---------------------------------------------------------------------------

const META_KEY := "frame_variant"
const BASE_BOB_AMOUNT := 0.22

## HANGAR_POSE key -> pivot node path (stance derivation below).
const HANGAR_PIVOT_PATHS := {
	"body_pos": "Body",
	"head_pos": "Head",
	"leg_left_pos": "LegLeft",
	"leg_right_pos": "LegRight",
	"shin_pos": "LegLeft/ShinLeft",
	"arm_left_pos": "ArmLeft",
	"arm_right_pos": "ArmRight",
	"forearm_pos": "ArmLeft/ForearmLeft",
}


static func variant_id_of(mecha: Node) -> String:
	if mecha != null and mecha.has_meta(META_KEY):
		return String(mecha.get_meta(META_KEY))
	return FrameVariantData.STANDARD_ID


static func get_variant_for(mecha: Node) -> Dictionary:
	return FrameVariantData.get_variant(variant_id_of(mecha))


## Full application for variant builds. Pre-tree only. Standard is a no-op
## against production behavior (values reproduce the tscn/export defaults).
static func apply_variant(mecha: Node3D, vid: String) -> void:
	var v := FrameVariantData.get_variant(vid)
	mecha.set_meta(META_KEY, String(v["id"]))
	apply_rest(mecha, v)
	apply_footik(mecha, v)
	apply_locomotion_tuning(mecha, v)
	apply_collision(mecha, v)


static func apply_rest(mecha: Node3D, v: Dictionary) -> void:
	var rest: Dictionary = v.get("rest", {})
	for path in rest:
		var n := mecha.get_node_or_null(String(path)) as Node3D
		if n != null:
			n.position = rest[path]


static func apply_footik(mecha: Node3D, v: Dictionary) -> void:
	var fk = mecha.get_node_or_null("FootIKSystem")
	if fk == null:
		return
	var f: Dictionary = v.get("footik", {})
	if f.has("spacing"):
		fk.set("foot_spacing_x", float(f["spacing"]))
	if f.has("ray_height"):
		fk.set("ray_height", float(f["ray_height"]))
	if f.has("ray_length"):
		fk.set("ray_length", float(f["ray_length"]))


static func apply_locomotion_tuning(mecha: Node3D, v: Dictionary) -> void:
	var anim = mecha.get_node_or_null("MechaAnimation")
	if anim == null:
		return
	var loco: Dictionary = v.get("locomotion", {})
	if loco.has("bob_scale"):
		anim.set("bob_amount", BASE_BOB_AMOUNT * float(loco["bob_scale"]))


static func apply_collision(mecha: Node3D, v: Dictionary) -> void:
	var col := mecha.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null or not (col.shape is CapsuleShape3D):
		return
	var b: Dictionary = v.get("body", {})
	# The tscn sub-resource is shared across instances: duplicate before edit.
	col.shape = (col.shape as CapsuleShape3D).duplicate()
	if b.has("capsule_h"):
		(col.shape as CapsuleShape3D).height = float(b["capsule_h"])
		col.position.y = float(b["capsule_h"]) * 0.5
	if b.has("capsule_r"):
		(col.shape as CapsuleShape3D).radius = float(b["capsule_r"])


# --- variant-aware consumers (standard fallbacks reproduce constants) --------

static func hand_mount_local_for(mecha: Node) -> Vector3:
	return get_variant_for(mecha).get("mounts", {}).get("hand", WeaponVisualFactory.HAND_FOREARM_POS)


static func shoulder_mount_local_for(mecha: Node) -> Vector3:
	return get_variant_for(mecha).get("mounts", {}).get("shoulder", WeaponVisualFactory.SHOULDER_ARM_POS)


static func natural_speed_for(mecha: Node) -> float:
	return float(get_variant_for(mecha).get("locomotion", {}).get("natural_speed", MechaClipRetarget.NATURAL_SPEED))


static func lift_scale_for(mecha: Node) -> float:
	return float(get_variant_for(mecha).get("locomotion", {}).get("lift_scale", 1.0))


static func head_collar_for(mecha: Node) -> Vector3:
	return get_variant_for(mecha).get("body", {}).get("head_collar", MechaRig.HEAD_COLLAR_LOCAL)


## Hangar stance derived per variant: Standard stance deltas (HANGAR_POSE
## minus Standard rest) re-applied onto the variant rest, so the Armored
## Core stance keeps its character on any frame. Standard output reproduces
## MechaScaleSystem.HANGAR_POSE exactly.
static func hangar_pose_for(vid: String) -> Dictionary:
	var v := FrameVariantData.get_variant(vid)
	var rest: Dictionary = v.get("rest", {})
	var out := {}
	for key in HANGAR_PIVOT_PATHS:
		var path: String = HANGAR_PIVOT_PATHS[key]
		var stance_delta: Vector3 = (MechaScaleSystem.HANGAR_POSE.get(key, Vector3.ZERO) as Vector3) - (FrameVariantData.STANDARD_REST.get(path, Vector3.ZERO) as Vector3)
		out[key] = (rest.get(path, Vector3.ZERO) as Vector3) + stance_delta
	return out
