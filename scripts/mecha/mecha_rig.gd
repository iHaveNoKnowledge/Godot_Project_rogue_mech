extends RefCounted
class_name MechaRig

# Shared skeleton + clip convention for externally-authored mech animation.
# Every modular armor/frame part must be rigged to THESE bone names so a single
# Skeleton3D can drive all parts together. Locked before authoring parts.
#
# External assets (glb/fbx) go in the folders below. Godot imports embedded
# clips into an AnimationPlayer automatically; the clip names must match
# CLIP_* so the clip driver can play them by name.

const PART_DIR := "res://scenes/mecha/parts"
const ANIM_DIR := "res://scenes/mecha/animations"
const RIG_NODE := "Rig"
const ANIM_PLAYER_NODE := "AnimationPlayer"

const BONE_HEAD := "Bone_Head"
const BONE_NECK := "Bone_Neck"
const BONE_TORSO := "Bone_Torso"
const BONE_HIP := "Bone_Hip"
const BONE_UPPER_ARM_L := "Bone_UpperArm_L"
const BONE_UPPER_ARM_R := "Bone_UpperArm_R"
const BONE_LOWER_ARM_L := "Bone_LowerArm_L"
const BONE_LOWER_ARM_R := "Bone_LowerArm_R"
const BONE_HAND_L := "Bone_Hand_L"
const BONE_HAND_R := "Bone_Hand_R"
const BONE_THIGH_L := "Bone_Thigh_L"
const BONE_THIGH_R := "Bone_Thigh_R"
const BONE_SHIN_L := "Bone_Shin_L"
const BONE_SHIN_R := "Bone_Shin_R"
const BONE_FOOT_L := "Bone_Foot_L"
const BONE_FOOT_R := "Bone_Foot_R"

const CLIP_IDLE := "idle"
const CLIP_RUN := "run"
const CLIP_JUMP_LAUNCH := "jump_launch"
const CLIP_JUMP_FALL := "jump_fall"
const CLIP_LAND := "land"
const CLIP_KNEEL := "kneel"
const CLIP_CORE_BREACH := "core_breach"
const CLIP_SHIELD_RAISE := "shield_raise"
const CLIP_ROLLER_DASH := "roller_dash"
const CLIP_RECOIL := "recoil"