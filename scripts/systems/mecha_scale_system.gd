class_name MechaScaleSystem
extends RefCounted

## ---------------------------------------------------------------------------
## MECHA SCALE SYSTEM — Single source of truth for true world scale (1.0 = 1m)
##
## MechaBase now at scale 1.0 with true height 4.86m (was 1.68 with 4.73/1.68 pivots).
## All legacy 1.6-era constants (2.8125 capsule, 2.30 head, etc.) are kept for
## readability but converted via WORLD_SCALE at runtime. This is the ONLY place
## that holds 1.68 — every other file uses these helpers, so future template
## authoring at 1 unit=1m stays consistent.
## ---------------------------------------------------------------------------

const WORLD_SCALE: float = 1.68
const INV_WORLD_SCALE: float = 1.0 / 1.68
const TRUE_HEIGHT: float = 4.86
const LEGACY_CAPSULE_HEIGHT: float = 2.8125
const LEGACY_CAPSULE_RADIUS: float = 0.625

# True world pivots (legacy * WORLD_SCALE) — mirrors mecha_base.tscn at scale 1.0
const PIVOTS: Dictionary = {
	"head": Vector3(0, 4.4436, -0.07728),
	"body": Vector3(0, 3.4776, 0),
	"arm_left": Vector3(-1.31376, 3.9606, 0),
	"arm_right": Vector3(1.31376, 3.9606, 0),
	"leg_left": Vector3(-0.73416, 2.5116, 0),
	"leg_right": Vector3(0.73416, 2.5116, 0),
	"forearm_left": Vector3(0, -0.73416, 0),
	"forearm_right": Vector3(0, -0.73416, 0),
	"shin_left": Vector3(0, -1.0626, 0),
	"shin_right": Vector3(0, -1.0626, 0),
	"eject": Vector3(0, 2.898, -1.932),
	"collision": Vector3(0, 2.71687, 0),
	"capsule": Vector3(1.2075, 5.43375, 1.2075), # radius, height, radius (y is height)
	"hitbox": Vector3(3.0912, 3.0912, 3.0912),
}

# Hangar pose (Armored Core stance) in true world meters — legacy 1.6 pose * WORLD_SCALE
const HANGAR_POSE: Dictionary = {
	"body_pos": Vector3(0, 3.2844, 0),
	"head_pos": Vector3(0, 4.28904, -0.0966),
	"leg_left_pos": Vector3(-0.88872, 2.415, 0),
	"leg_right_pos": Vector3(0.88872, 2.415, 0),
	"shin_pos": Vector3(0, -1.0626, 0),
	"arm_left_pos": Vector3(-1.31376, 3.7674, 0),
	"arm_right_pos": Vector3(1.31376, 3.7674, 0),
	"forearm_pos": Vector3(0, -0.73416, 0),
}

# Hangar camera (low worm-eye + tight part framing) in true world
const HANGAR_CAM: Dictionary = {
	"initial_pos": Vector3(4.14, 1.61, -7.36),
	"initial_look": Vector3(0, 3.68, 0),
	"head": {"pos": Vector3(1.15, 5.06, -5.98), "look": Vector3(0, 4.4275, -0.0575)},
	"body": {"pos": Vector3(1.38, 3.91, -6.44), "look": Vector3(0, 3.473, 0)},
	"arm_left": {"pos": Vector3(-2.99, 4.14, -6.21), "look": Vector3(-1.311, 3.8525, 0)},
	"arm_right": {"pos": Vector3(2.99, 4.14, -6.21), "look": Vector3(1.311, 3.8525, 0)},
	"weapon_carry": {"pos": Vector3(2.07, 4.37, 6.67), "look": Vector3(0, 3.45, 0.345)},
	"leg_left": {"pos": Vector3(-1.84, 2.53, -5.75), "look": Vector3(-0.736, 2.1275, 0)},
	"leg_right": {"pos": Vector3(1.84, 2.53, -5.75), "look": Vector3(0.736, 2.1275, 0)},
	"default": {"pos": Vector3(4.14, 1.61, -7.36), "look": Vector3(0, 3.68, 0)},
}

# Combat camera (pulled back so back doesn't block center)
const COMBAT_CAM: Dictionary = {
	"spring": 11.0,
	"offset_x": 3.4,
	"offset_y": 5.2,
	"fov": 76.0,
	"close_spring": 8.0,
	"close_x": 3.0,
	"close_y": 4.6,
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
