class_name HandlingResolver
extends RefCounted

## HANDLING RESOLVER — Frame Capability → Weapon Handling (stateless).
##
## Resolves HOW a weapon is handled from the relationship between weapon
## requirements (WeaponPart), frame capability (arm/leg power, recoil_resistance)
## and mount — never from weapon category alone. Deterministic and side-effect
## free: the caller gathers state into `powers`, this evaluates it.
##
## Reuses (never duplicates):
##   WeaponPart.weight/recoil_force/two_handed/power_required/requires_two_hand,
##   GlobalData.get_arm_power/get_leg_power/get_mech_power,
##   FrameSystem.get_total_recoil_resistance.
##
## Default weapons (arm_load == 0, stability == 0, recoil == 0) resolve to the
## exact current behavior: ONE_HAND / MINIMAL / SPRINT / NORMAL / 1.0.

# Grip outcomes.
const GRIP_ONE_HAND := "ONE_HAND"
const GRIP_TWO_HAND := "TWO_HAND"
const GRIP_BRACED := "BRACED"
const GRIP_MOUNTED := "MOUNTED"

# Recoil outcomes (bands over effective recoil, see RECOIL_* thresholds).
const RECOIL_MINIMAL := "MINIMAL"
const RECOIL_LOW := "LOW"
const RECOIL_MEDIUM := "MEDIUM"
const RECOIL_HIGH := "HIGH"
const RECOIL_EXTREME := "EXTREME"

# Firing-movement outcomes.
const MOBILITY_STATIONARY := "STATIONARY"
const MOBILITY_WALK := "WALK"
const MOBILITY_RUN := "RUN"
const MOBILITY_SPRINT := "SPRINT"

# Aim outcomes.
const AIM_LOW := "LOW"
const AIM_NORMAL := "NORMAL"
const AIM_HIGH := "HIGH"

# Mount kinds. HAND = arm-held. FIXED_MOUNT = pod-like (no arm requirement;
## core/leg stability still applies). ARM_ASSISTED = mounted but positioned by
## the arms (current ShoulderMesh_* visuals parent under Arm*, so they inherit
## arm animation). ARTICULATED_MOUNT is reserved for future actuator-driven
## mounts — classify_mount() never returns it today (no mount carries actuator
## semantics yet), it exists so the kind set is complete for later tables.
const MOUNT_HAND := "HAND"
const MOUNT_FIXED := "FIXED_MOUNT"
const MOUNT_ARTICULATED := "ARTICULATED_MOUNT"
const MOUNT_ARM_ASSISTED := "ARM_ASSISTED"

# Melee size classes (mirrors WeaponPart.size_class documentation).
const SIZE_LIGHT := 0
const SIZE_MEDIUM := 1
const SIZE_HEAVY := 2
const SIZE_GREATSWORD := 3
const SIZE_COLOSSAL := 4

# Existing firing slots. Grandfathered: always supported so the 31 stock
# weapons (whose .tres files predate mount_compatibility) keep working
# untouched. Mount_compatibility is enforced only for future slots.
const LEGACY_SLOTS: Array = ["left", "right", "hand", "shoulder_left", "shoulder_right", "shoulder"]

# Minimal static mount capacity (no equivalent exists in frame/module data —
## AttachmentManager capacity is chassis weight-based and cosmetic-only).
## Generous provisional values: every stock weapon passes; they gate future
## overweight/over-recoil mounts, not current content.
const MOUNT_CAPACITY := {
	"shoulder_left": {"mass_capacity": 40.0, "recoil_capacity": 30.0, "actuator_power": 10.0, "traverse": 1.0},
	"shoulder_right": {"mass_capacity": 40.0, "recoil_capacity": 30.0, "actuator_power": 10.0, "traverse": 1.0},
	"back": {"mass_capacity": 60.0, "recoil_capacity": 40.0, "actuator_power": 12.0, "traverse": 0.5},
}

# Effective-recoil band edges (recoil_force × resistance multiplier).
const RECOIL_LOW_MAX := 2.0
const RECOIL_MEDIUM_MAX := 6.0
const RECOIL_HIGH_MAX := 12.0

# Mobility score bands (leg_power + resistance*10 − stability − recoil*0.5).
const MOBILITY_SPRINT_MIN := 14.0
const MOBILITY_RUN_MIN := 10.0
const MOBILITY_WALK_MIN := 6.0


## Classifies how a mount carries a weapon from actual current behavior:
## hand slots are arm-held; missile pods on shoulder/back are fixed (the
## shoulder fire path never checks arm state); other shoulder/back weapons
## inherit arm animation via Arm*-parented ShoulderMesh_* visuals.
static func classify_mount(weapon: WeaponPart, mount: String) -> String:
	var m := mount.to_lower().strip_edges()
	if m == "" or m == "hand" or m == "left" or m == "right":
		return MOUNT_HAND
	if m == "shoulder" or m == "shoulder_left" or m == "shoulder_right" or m == "back":
		if weapon != null and weapon.weapon_type == WeaponPart.WeaponType.MISSILE:
			return MOUNT_FIXED
		return MOUNT_ARM_ASSISTED
	return MOUNT_HAND


## True when the weapon may sit on the mount. Legacy slots always pass
## (grandfathered stock content); future slots consult mount_compatibility
## plus the static mass/recoil capacity table.
static func is_mount_supported(weapon: WeaponPart, mount: String) -> Dictionary:
	if weapon == null:
		return {"supported": false, "reason": "no_weapon"}
	var m := mount.to_lower().strip_edges()
	if m in LEGACY_SLOTS or m == "":
		return {"supported": true, "reason": "legacy_slot"}
	var compat: Array = weapon.mount_compatibility
	var ok_compat := false
	for entry in compat:
		if str(entry).to_lower().strip_edges() == m or str(entry).to_lower().strip_edges() == "back" and m == "back":
			ok_compat = true
			break
	if not ok_compat:
		# Also accept the bare slot family ("shoulder" covers shoulder_left).
		for entry in compat:
			var e := str(entry).to_lower().strip_edges()
			if e == "shoulder" and m.begins_with("shoulder"):
				ok_compat = true
				break
	if not ok_compat:
		return {"supported": false, "reason": "mount_incompatible"}
	if MOUNT_CAPACITY.has(m):
		var cap: Dictionary = MOUNT_CAPACITY[m]
		if float(weapon.weight) > float(cap.get("mass_capacity", 0.0)):
			return {"supported": false, "reason": "mount_over_mass"}
		if float(weapon.recoil_force) > float(cap.get("recoil_capacity", 0.0)):
			return {"supported": false, "reason": "mount_over_recoil"}
	return {"supported": true, "reason": "ok"}


## Recoil impulse multiplier from frame resistance. 0.0 resistance → exactly
## 1.0 (byte-identical current behavior); set bonuses (0.15/0.25) reduce.
static func recoil_multiplier(recoil_resistance: float) -> float:
	return clampf(1.0 - maxf(recoil_resistance, 0.0), 0.4, 1.0)


## Full handling resolution. `powers` is caller-gathered state:
## {arm_power, leg_power, mech_power, recoil_resistance, arm_destroyed}.
static func resolve(weapon: WeaponPart, mount: String, powers: Dictionary) -> Dictionary:
	var out := {
		"supported": true,
		"reason": "ok",
		"mount_kind": MOUNT_HAND,
		"grip_mode": GRIP_ONE_HAND,
		"recoil_level": RECOIL_MINIMAL,
		"recoil_mult": 1.0,
		"mobility_fire_mode": MOBILITY_SPRINT,
		"aim_stability": AIM_NORMAL,
		"recovery_mult": 1.0,
	}
	if weapon == null:
		out["supported"] = false
		out["reason"] = "no_weapon"
		return out
	var mount_check := is_mount_supported(weapon, mount)
	out["supported"] = bool(mount_check.get("supported", false))
	out["reason"] = str(mount_check.get("reason", "ok"))
	if not bool(out["supported"]):
		return out

	var arm_power: float = float(powers.get("arm_power", 0.0))
	var leg_power: float = float(powers.get("leg_power", 0.0))
	var resistance: float = maxf(float(powers.get("recoil_resistance", 0.0)), 0.0)
	var arm_load: float = maxf(float(weapon.arm_load), 0.0)
	var stability: float = maxf(float(weapon.stability_requirement), 0.0)

	var kind := classify_mount(weapon, mount)
	out["mount_kind"] = kind

	var recoil_mult := recoil_multiplier(resistance)
	out["recoil_mult"] = recoil_mult
	var effective_recoil: float = maxf(float(weapon.recoil_force), 0.0) * recoil_mult
	if effective_recoil <= 0.0:
		out["recoil_level"] = RECOIL_MINIMAL
	elif effective_recoil < RECOIL_LOW_MAX:
		out["recoil_level"] = RECOIL_LOW
	elif effective_recoil < RECOIL_MEDIUM_MAX:
		out["recoil_level"] = RECOIL_MEDIUM
	elif effective_recoil < RECOIL_HIGH_MAX:
		out["recoil_level"] = RECOIL_HIGH
	else:
		out["recoil_level"] = RECOIL_EXTREME

	# Grip: explicit two_handed flag stays authoritative (baseline behavior);
	## fixed mounts bypass arm load; otherwise arm_load decides. A two-handed
	## grip against HIGH+ recoil reads as a braced stance.
	if kind == MOUNT_FIXED:
		out["grip_mode"] = GRIP_MOUNTED
	elif weapon.requires_two_hand(arm_power):
		out["grip_mode"] = GRIP_TWO_HAND
	elif kind != MOUNT_FIXED and arm_load > arm_power:
		out["grip_mode"] = GRIP_TWO_HAND
	else:
		out["grip_mode"] = GRIP_ONE_HAND
	if out["grip_mode"] == GRIP_TWO_HAND and (out["recoil_level"] == RECOIL_HIGH or out["recoil_level"] == RECOIL_EXTREME):
		out["grip_mode"] = GRIP_BRACED

	# Mobility: requirement-free weapons keep today's unrestricted behavior.
	if arm_load <= 0.0 and stability <= 0.0 and float(weapon.recoil_force) <= 0.0:
		out["mobility_fire_mode"] = MOBILITY_SPRINT
	else:
		var score: float = leg_power + resistance * 10.0 - stability - effective_recoil * 0.5
		if score >= MOBILITY_SPRINT_MIN:
			out["mobility_fire_mode"] = MOBILITY_SPRINT
		elif score >= MOBILITY_RUN_MIN:
			out["mobility_fire_mode"] = MOBILITY_RUN
		elif score >= MOBILITY_WALK_MIN:
			out["mobility_fire_mode"] = MOBILITY_WALK
		else:
			out["mobility_fire_mode"] = MOBILITY_STATIONARY

	# Aim: requirement-free weapons stay NORMAL; otherwise margin decides.
	if arm_load <= 0.0 and stability <= 0.0:
		out["aim_stability"] = AIM_NORMAL
	else:
		var margin: float = arm_power - maxf(arm_load, stability) + resistance * 20.0
		if margin >= 10.0:
			out["aim_stability"] = AIM_HIGH
		elif margin >= 0.0:
			out["aim_stability"] = AIM_NORMAL
		else:
			out["aim_stability"] = AIM_LOW

	# Recovery: exposed for tests/telemetry. Deliberately NOT wired into the
	## recoil-decay path (which already consumes leg power): compounding a
	## second multiplier there would silently rebalance combat.
	if arm_load <= 0.0 and stability <= 0.0:
		out["recovery_mult"] = clampf(1.0 + resistance, 1.0, 2.0)
	else:
		out["recovery_mult"] = clampf(1.0 + resistance + maxf(arm_power - arm_load, 0.0) * 0.005, 1.0, 2.0)

	return out


## Proposed MechaWeaponLayer profile for a resolved grip (mapping only —
## the layer stays dormant until the ownership audit clears it for runtime).
static func layer_profile(weapon: WeaponPart, grip_mode: String) -> String:
	if weapon != null:
		if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
			return MechaWeaponLayer.WEAPON_SWORD
		if weapon.weapon_type == WeaponPart.WeaponType.SHIELD:
			return MechaWeaponLayer.WEAPON_NONE
	if grip_mode == GRIP_BRACED or grip_mode == GRIP_MOUNTED:
		return MechaWeaponLayer.WEAPON_HEAVY
	if grip_mode == GRIP_TWO_HAND:
		return MechaWeaponLayer.WEAPON_RIFLE
	return "rifle-primary"
