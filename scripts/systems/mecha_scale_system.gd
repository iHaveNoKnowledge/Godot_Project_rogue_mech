class_name MechaScaleSystem
extends RefCounted

## ---------------------------------------------------------------------------
## MECHA SCALE SYSTEM — Single source of truth for true world scale (1.0 = 1m)
##
## MechaBase now at scale 1.0 with true height 4.73m (was 1.68 with 4.73/1.68 pivots).
## All legacy 1.6-era constants (2.8125 capsule, 2.30 head, etc.) are kept for
## readability but converted via WORLD_SCALE at runtime. This is the ONLY place
## that holds 1.68 — every other file uses these helpers, so future template
## authoring at 1 unit=1m stays consistent.
## ---------------------------------------------------------------------------

const WORLD_SCALE: float = 1.68
const INV_WORLD_SCALE: float = 1.0 / 1.68
const TRUE_HEIGHT: float = 4.73
const LEGACY_CAPSULE_HEIGHT: float = 2.8125
const LEGACY_CAPSULE_RADIUS: float = 0.625

# True world pivots (legacy * WORLD_SCALE) — mirrors mecha_base.tscn at scale 1.0
const PIVOTS: Dictionary = {
	"head": Vector3(0, 3.864, -0.0672),
	"body": Vector3(0, 3.024, 0),
	"arm_left": Vector3(-1.1424, 3.444, 0),
	"arm_right": Vector3(1.1424, 3.444, 0),
	"leg_left": Vector3(-0.6384, 2.184, 0),
	"leg_right": Vector3(0.6384, 2.184, 0),
	"forearm_left": Vector3(0, -0.6384, 0),
	"forearm_right": Vector3(0, -0.6384, 0),
	"shin_left": Vector3(0, -0.924, 0),
	"shin_right": Vector3(0, -0.924, 0),
	"eject": Vector3(0, 2.52, -1.68),
	"collision": Vector3(0, 2.3625, 0),
	"capsule": Vector3(1.05, 4.725, 1.05), # radius, height, radius (y is height)
	"hitbox": Vector3(2.688, 2.688, 2.688),
}

# Hangar pose (Armored Core stance) in true world meters — legacy 1.6 pose * WORLD_SCALE
const HANGAR_POSE: Dictionary = {
	"body_pos": Vector3(0, 2.856, 0),
	"head_pos": Vector3(0, 3.7296, -0.084),
	"leg_left_pos": Vector3(-0.7728, 2.10, 0),
	"leg_right_pos": Vector3(0.7728, 2.10, 0),
	"shin_pos": Vector3(0, -0.924, 0),
	"arm_left_pos": Vector3(-1.1424, 3.276, 0),
	"arm_right_pos": Vector3(1.1424, 3.276, 0),
	"forearm_pos": Vector3(0, -0.6384, 0),
}

# Hangar camera (low worm-eye + tight part framing) in true world
const HANGAR_CAM: Dictionary = {
	"initial_pos": Vector3(3.6, 1.4, -6.4),
	"initial_look": Vector3(0, 3.2, 0),
	"head": {"pos": Vector3(1.0, 4.4, -5.2), "look": Vector3(0, 3.85, -0.05)},
	"body": {"pos": Vector3(1.2, 3.4, -5.6), "look": Vector3(0, 3.02, 0)},
	"arm_left": {"pos": Vector3(-2.6, 3.6, -5.4), "look": Vector3(-1.14, 3.35, 0)},
	"arm_right": {"pos": Vector3(2.6, 3.6, -5.4), "look": Vector3(1.14, 3.35, 0)},
	"weapon_carry": {"pos": Vector3(1.8, 3.8, 5.8), "look": Vector3(0, 3.0, 0.3)},
	"leg_left": {"pos": Vector3(-1.6, 2.2, -5.0), "look": Vector3(-0.64, 1.85, 0)},
	"leg_right": {"pos": Vector3(1.6, 2.2, -5.0), "look": Vector3(0.64, 1.85, 0)},
	"default": {"pos": Vector3(3.6, 1.4, -6.4), "look": Vector3(0, 3.2, 0)},
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
