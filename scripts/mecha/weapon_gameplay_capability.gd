class_name WeaponGameplayCapability
extends RefCounted

## WEAPON GAMEPLAY CAPABILITY — "Can I do this?" (stateless, query-only).
##
## Sits between HandlingResolver and action execution:
##   WeaponPart → Frame Capability → HandlingResolver → THIS → Action Request
##   → existing ActionAnimator / Combat System.
##
## Answers permission only. NEVER executes: no animation, no damage, no
## projectiles, no melee hits, no movement, no pose ownership. Execution stays
## with WeaponManager / ActionAnimator / the combat and projectile systems.
##
## Grounding (every rule mirrors an existing gate, nothing invented):
##   FIRE representation .. WeaponManager._try_fire: ranged types fire,
##      MELEE routes to _melee_attack, SHIELD returns, empty hand falls back
##      to the WM-owned fist punch (unarmed fallback stays execution-owned;
##      a null query weapon is rejected here).
##   MELEE representation .. _melee_attack dispatch (MELEE type via AF slash
##      or legacy pile thrust; ranged weapons never enter the melee path).
##   AIM representation ... MechaAnimation._hand_is_ranged_gun: intact arm +
##      held weapon whose type is neither MELEE nor SHIELD.
##   GUARD representation ... WeaponManager._toggle_shield reads left_hand /
##      right_hand only (shoulder shields have no toggle path; a shoulder
##      shield press returns without effect). A destroyed acting arm redirects
##      the press to the execution-owned shoulder bash, so the toggle never
##      occurs. Broken-plate HP gating is combat resource state (like ammo)
##      and is NOT consulted here.
##   Acting-hand intact .... _try_fire / _hand_is_ranged_gun (destroyed arm
##      cannot fire or aim that hand).
##   Two-hand support ...... weapon_needs_both_hands + _enforce_two_hand_grip
##      (support weapon is holstered so both arms brace). The enforcement
##      performs NO support-usability check, and no pre-existing test, spec
##      or design states that a destroyed support arm must block fire —
##      the live runtime fires (degraded brace, grip still TWO_HAND/BRACED).
##      Per the closure safety rule the capability preserves that behavior:
##      support state never rejects (Option B); degraded handling is
##      expressed through the reported grip_mode, not a rejection.
##   Fixed mounts .......... HandlingResolver.classify_mount docs (shoulder
##      missile pods never check arm state) — MOUNTED needs no hands.
##
## Dynamic execution state (ammo, heat, cooldown, reload, trigger) is owned
## by WeaponCore / the combat path and is deliberately NOT consulted here.
## Mobility permission (mobility_fire_mode) is resolver output for future
## phases; this layer reports no fire gate (see get_handling()).

# Capability categories.
const ACTION_FIRE := "FIRE"
const ACTION_MELEE := "MELEE"
const ACTION_AIM := "AIM"
const ACTION_GUARD := "GUARD"

# Deterministic machine-readable reasons.
const REASON_OK := "ok"
const REASON_NO_WEAPON := "no_weapon"
const REASON_ACTION_UNSUPPORTED := "action_unsupported"
const REASON_HANDLING_RESTRICTION := "handling_restriction"
const REASON_MOUNT_UNSUPPORTED := "mount_unsupported"


## True when the weapon's type represents the action in the existing
## execution paths (see grounding above). Unknown actions are unsupported.
static func action_supported(weapon: WeaponPart, action: String) -> bool:
	if weapon == null:
		return false
	match str(action).to_upper().strip_edges():
		ACTION_FIRE, ACTION_AIM:
			return weapon.weapon_type != WeaponPart.WeaponType.MELEE \
				and weapon.weapon_type != WeaponPart.WeaponType.SHIELD
		ACTION_MELEE:
			return weapon.weapon_type == WeaponPart.WeaponType.MELEE
		ACTION_GUARD:
			return weapon.weapon_type == WeaponPart.WeaponType.SHIELD
	return false


## Single authoritative capability query. `powers` reuses the HandlingResolver
## shape {arm_power, leg_power, mech_power, recoil_resistance, arm_destroyed}.
## Returns {allowed: bool, reason: String, action: String,
##          grip_mode: String, mount_kind: String}.
## grip_mode/mount_kind come straight from HandlingResolver; they are ""
## when rejection happens before handling resolution.
static func query(weapon: WeaponPart, action: String, mount: String, powers: Dictionary) -> Dictionary:
	var act := str(action).to_upper().strip_edges()
	var out := {
		"allowed": false,
		"reason": REASON_ACTION_UNSUPPORTED,
		"action": act,
		"grip_mode": "",
		"mount_kind": "",
	}
	if weapon == null:
		out["reason"] = REASON_NO_WEAPON
		return out
	if not action_supported(weapon, act):
		out["reason"] = REASON_ACTION_UNSUPPORTED
		return out
	var mount_check := HandlingResolver.is_mount_supported(weapon, mount)
	if not bool(mount_check.get("supported", false)):
		out["reason"] = REASON_MOUNT_UNSUPPORTED
		return out

	var handling := HandlingResolver.resolve(weapon, mount, powers)
	out["grip_mode"] = str(handling.get("grip_mode", HandlingResolver.GRIP_ONE_HAND))
	out["mount_kind"] = str(handling.get("mount_kind", HandlingResolver.MOUNT_HAND))

	# Fixed mounts need no hands (existing shoulder-pod behavior).
	if str(out["mount_kind"]) == HandlingResolver.MOUNT_FIXED:
		out["allowed"] = true
		out["reason"] = REASON_OK
		return out

	# GUARD is a hand-plate toggle: _toggle_shield reads the hands only, so
	# a shield anywhere else has no guard path in execution.
	if act == ACTION_GUARD and str(out["mount_kind"]) != HandlingResolver.MOUNT_HAND:
		out["reason"] = REASON_ACTION_UNSUPPORTED
		return out

	# Shoulder arm-assisted mounts keep today's execution-owned behavior:
	# no hand gate here (no existing gate to mirror).
	if str(out["mount_kind"]) != HandlingResolver.MOUNT_HAND:
		out["allowed"] = true
		out["reason"] = REASON_OK
		return out

	# Hand mounts: a destroyed acting arm cannot act (mirrors _try_fire;
	# the press redirects to the execution-owned shoulder bash instead).
	if bool(powers.get("arm_destroyed", false)):
		out["reason"] = REASON_HANDLING_RESTRICTION
		return out

	# Two-hand family always resolves: the holster-to-brace enforcement has
	# no support-usability gate, so the live runtime fires (Option B).
	# Degraded handling is reported via grip_mode, never a rejection.
	out["allowed"] = true
	out["reason"] = REASON_OK
	return out


## Thin wrappers over query() — one authoritative path, four spellings.
static func can_fire(weapon: WeaponPart, mount: String, powers: Dictionary) -> Dictionary:
	return query(weapon, ACTION_FIRE, mount, powers)


static func can_melee(weapon: WeaponPart, mount: String, powers: Dictionary) -> Dictionary:
	return query(weapon, ACTION_MELEE, mount, powers)


static func can_aim(weapon: WeaponPart, mount: String, powers: Dictionary) -> Dictionary:
	return query(weapon, ACTION_AIM, mount, powers)


static func can_guard(weapon: WeaponPart, mount: String, powers: Dictionary) -> Dictionary:
	return query(weapon, ACTION_GUARD, mount, powers)
