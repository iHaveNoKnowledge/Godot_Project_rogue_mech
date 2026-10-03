class_name MechaScaleSystem
extends RefCounted

## ---------------------------------------------------------------------------
## MECHA SCALE SYSTEM — Single source of truth for true world scale (1.0 = 1m)
##
## MechaBase root at scale 1.15, FrameMesh/ArmorMesh containers at WORLD_SCALE
## (1.68), so procedural geometry renders at a global 1.932 factor. Measured
## rest-pose frame height (audit 2026-10-03, headless world AABB, mech at
## origin): minY (foot roller) 0.20 m, maxY (CH_RollBar) 5.53 m = 5.33 m.
## The 5.80 figure was the Front Mission WANZER ZENITH reference the scale
## system was drafted from, NOT the Valkren standard frame (~5.0 m target).
## All legacy 1.6-era constants (2.8125 capsule, 2.30 head, etc.) are kept for
## readability but converted via WORLD_SCALE at runtime. This is the ONLY place
## that holds 1.68 — every other file uses these helpers, so future template
## authoring at 1 unit=1m stays consistent.
## ---------------------------------------------------------------------------

const WORLD_SCALE: float = 1.68
const INV_WORLD_SCALE: float = 1.0 / 1.68
const TRUE_HEIGHT: float = 5.33
const LEGACY_CAPSULE_HEIGHT: float = 2.8125
const LEGACY_CAPSULE_RADIUS: float = 0.625

# True world pivots (legacy * WORLD_SCALE, +0.94 leg extension) — mirrors
# mecha_base.tscn at scale 1.0
const PIVOTS: Dictionary = {
	"head": Vector3(0, 5.3836, -0.07728),
	"body": Vector3(0, 4.4176, 0),
	"arm_left": Vector3(-1.31376, 4.9006, 0),
	"arm_right": Vector3(1.31376, 4.9006, 0),
	"leg_left": Vector3(-0.73416, 3.4516, 0),
	"leg_right": Vector3(0.73416, 3.4516, 0),
	"forearm_left": Vector3(0, -0.73416, 0),
	"forearm_right": Vector3(0, -0.73416, 0),
	"shin_left": Vector3(0, -1.0626, 0),
	"shin_right": Vector3(0, -1.0626, 0),
	"eject": Vector3(0, 3.838, -1.932),
	"collision": Vector3(0, 3.16, 0),
	"capsule": Vector3(1.2075, 6.37375, 1.2075), # radius, height, radius (y is height)
	"hitbox": Vector3(3.6, 3.6, 3.6),
}

# Hangar pose (Armored Core stance) in true world meters — legacy 1.6 pose * WORLD_SCALE + 0.94 leg extension
const HANGAR_POSE: Dictionary = {
	"body_pos": Vector3(0, 4.2244, 0),
	"head_pos": Vector3(0, 5.22904, -0.0966),
	"leg_left_pos": Vector3(-0.88872, 3.355, 0),
	"leg_right_pos": Vector3(0.88872, 3.355, 0),
	"shin_pos": Vector3(0, -1.0626, 0),
	"arm_left_pos": Vector3(-1.31376, 4.7074, 0),
	"arm_right_pos": Vector3(1.31376, 4.7074, 0),
	"forearm_pos": Vector3(0, -0.73416, 0),
}

# Hangar camera (low worm-eye + tight part framing) in true world
const HANGAR_CAM: Dictionary = {
	"initial_pos": Vector3(4.14, 2.55, -7.36),
	"initial_look": Vector3(0, 4.62, 0),
	"head": {"pos": Vector3(1.15, 6.0, -5.98), "look": Vector3(0, 5.3675, -0.0575)},
	"body": {"pos": Vector3(1.38, 4.85, -6.44), "look": Vector3(0, 4.413, 0)},
	"arm_left": {"pos": Vector3(-2.99, 5.08, -6.21), "look": Vector3(-1.311, 4.7925, 0)},
	"arm_right": {"pos": Vector3(2.99, 5.08, -6.21), "look": Vector3(1.311, 4.7925, 0)},
	"weapon_carry": {"pos": Vector3(2.07, 5.31, 6.67), "look": Vector3(0, 4.39, 0.345)},
	"leg_left": {"pos": Vector3(-1.84, 3.47, -5.75), "look": Vector3(-0.736, 3.0675, 0)},
	"leg_right": {"pos": Vector3(1.84, 3.47, -5.75), "look": Vector3(0.736, 3.0675, 0)},
	"default": {"pos": Vector3(4.14, 2.55, -7.36), "look": Vector3(0, 4.62, 0)},
}

# Combat camera (pulled back so back doesn't block center)
const COMBAT_CAM: Dictionary = {
	"spring": 11.0,
	"offset_x": 3.4,
	"offset_y": 6.1,
	"fov": 76.0,
	"close_spring": 8.0,
	"close_x": 3.0,
	"close_y": 5.5,
}

# Helpers — use newest API: scale_vec / scale_val / true_height
static func scale_vec(v: Vector3) -> Vector3:
	return v * WORLD_SCALE

static func scale_val(f: float) -> float:
	return f * WORLD_SCALE

static func inv_scale_vec(v: Vector3) -> Vector3:
	return v * INV_WORLD_SCALE

static func get_pivot(slot: String) -> Vector3:
	return PIVOTS.get(slot, Vector3.ZERO)

static func get_hangar_pose(slot: String) -> Dictionary:
	return HANGAR_POSE.duplicate(true)

static func get_hangar_cam(slot: String) -> Dictionary:
	return HANGAR_CAM.get(slot, HANGAR_CAM["default"])

static func get_combat_cam() -> Dictionary:
	return COMBAT_CAM.duplicate(true)
