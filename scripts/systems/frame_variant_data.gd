class_name FrameVariantData
extends RefCounted

## ---------------------------------------------------------------------------
## FRAME VARIANT DATA — data-driven physical frame configurations.
##
## The audit (VALKREN MODULAR FRAME <-> ANIMATION REUSE) proved locomotion and
## action animation are pivot-driven and rotation-based: drivers write pivot
## rotations plus rest-relative Y offsets, never bone lengths or rest
## positions. Variant differences are therefore DATA, not new animations.
##
## Conventions (follow GlobalData catalogs / MechaScaleSystem style):
## - Plain Dictionaries; units are mecha-LOCAL meters, the same space as the
##   mecha_base.tscn pivot transforms (root scale applies on top equally).
## - `rest` keys are pivot node paths; values are local rest positions.
## - `standard` reproduces production Standard behavior exactly.
## - This data holds NO keyframes, NO clips, NO per-frame animation copies.
## ---------------------------------------------------------------------------

const STANDARD_ID := "standard"
const HEAVY_ID := "heavy"
const EXTENDED_ID := "extended"

## Production Standard rest (mecha_base.tscn pivot transforms, verbatim).
const STANDARD_REST := {
	"Head": Vector3(0, 4.377, -0.16),
	"Body": Vector3(0, 3.841, 0),
	"ArmLeft": Vector3(-1.1424, 4.261, 0),
	"ArmRight": Vector3(1.1424, 4.261, 0),
	"ArmLeft/ForearmLeft": Vector3(0, -0.6384, 0),
	"ArmRight/ForearmRight": Vector3(0, -0.6384, 0),
	"LegLeft": Vector3(-0.6384, 3.001, 0),
	"LegRight": Vector3(0.6384, 3.001, 0),
	"LegLeft/ShinLeft": Vector3(0, -1.34, 0),
	"LegRight/ShinRight": Vector3(0, -1.34, 0),
	"LegLeft/ShinLeft/FootLeft": Vector3(0, -1.291, 0),
	"LegRight/ShinRight/FootRight": Vector3(0, -1.291, 0),
}

## Heavy: +~14% limbs, wider stance, taller hips so lengthened legs still
## plant feet at the Standard ankle height (local ankle 0.37, as Standard:
## 3.30 - 1.51 - 1.42 == 3.001 - 1.34 - 1.291).
const HEAVY_REST := {
	"Head": Vector3(0, 4.676, -0.16),
	"Body": Vector3(0, 4.14, 0),
	"ArmLeft": Vector3(-1.30, 4.56, 0),
	"ArmRight": Vector3(1.30, 4.56, 0),
	"ArmLeft/ForearmLeft": Vector3(0, -0.72, 0),
	"ArmRight/ForearmRight": Vector3(0, -0.72, 0),
	"LegLeft": Vector3(-0.72, 3.30, 0),
	"LegRight": Vector3(0.72, 3.30, 0),
	"LegLeft/ShinLeft": Vector3(0, -1.51, 0),
	"LegRight/ShinRight": Vector3(0, -1.51, 0),
	"LegLeft/ShinLeft/FootLeft": Vector3(0, -1.42, 0),
	"LegRight/ShinRight/FootRight": Vector3(0, -1.42, 0),
}

## Extended: +20% limb segments, same joint widths as Standard. Hips raised
## so the ankle stays at local 0.37 (3.527 - 1.608 - 1.5492 == 0.3698).
const EXTENDED_REST := {
	"Head": Vector3(0, 4.903, -0.16),
	"Body": Vector3(0, 4.367, 0),
	"ArmLeft": Vector3(-1.1424, 4.787, 0),
	"ArmRight": Vector3(1.1424, 4.787, 0),
	"ArmLeft/ForearmLeft": Vector3(0, -0.7661, 0),
	"ArmRight/ForearmRight": Vector3(0, -0.7661, 0),
	"LegLeft": Vector3(-0.6384, 3.527, 0),
	"LegRight": Vector3(0.6384, 3.527, 0),
	"LegLeft/ShinLeft": Vector3(0, -1.608, 0),
	"LegRight/ShinRight": Vector3(0, -1.608, 0),
	"LegLeft/ShinLeft/FootLeft": Vector3(0, -1.5492, 0),
	"LegRight/ShinRight/FootRight": Vector3(0, -1.5492, 0),
}

static func _variant(vid: String, display: String, rest: Dictionary, mounts: Dictionary, locomotion: Dictionary, footik: Dictionary, body: Dictionary) -> Dictionary:
	return {
		"id": vid,
		"display_name": display,
		"rest": rest,
		"mounts": mounts,
		"locomotion": locomotion,
		"footik": footik,
		"body": body,
	}


static func get_variant(vid: String) -> Dictionary:
	match String(vid):
		HEAVY_ID:
			return _variant(HEAVY_ID, "Heavy Frame",
				HEAVY_REST,
				{"hand": Vector3(0, -0.80, 0), "shoulder": Vector3(0, 0.30, 0)},
				{"natural_speed": 7.0, "bob_scale": 1.15, "lift_scale": 1.2},
				{"spacing": 0.45, "ray_height": 2.6, "ray_length": 3.6},
				{"capsule_h": 5.9, "capsule_r": 1.15, "head_collar": Vector3(0, 0.536, -0.16)})
		EXTENDED_ID:
			return _variant(EXTENDED_ID, "Extended Frame",
				EXTENDED_REST,
				{"hand": Vector3(0, -0.864, 0), "shoulder": Vector3(0, 0.25, 0)},
				{"natural_speed": 9.5, "bob_scale": 1.1, "lift_scale": 1.1},
				{"spacing": 0.40, "ray_height": 2.7, "ray_length": 3.6},
				{"capsule_h": 6.1, "capsule_r": 1.05, "head_collar": Vector3(0, 0.536, -0.16)})
		_:
			return _variant(STANDARD_ID, "Standard Frame",
				STANDARD_REST,
				{"hand": Vector3(0, -0.72, 0), "shoulder": Vector3(0, 0.25, 0)},
				{"natural_speed": 8.5, "bob_scale": 1.0, "lift_scale": 1.0},
				{"spacing": 0.38, "ray_height": 2.4, "ray_length": 3.3},
				{"capsule_h": 5.5, "capsule_r": 1.05, "head_collar": Vector3(0, 0.536, -0.16)})


static func variant_ids() -> Array[String]:
	return [STANDARD_ID, HEAVY_ID, EXTENDED_ID]
