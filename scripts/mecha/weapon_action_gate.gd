class_name WeaponActionGate
extends RefCounted

## WEAPON ACTION GATE — "Can it happen right now?" (stateless, query-only).
##
## CONTRACT ONLY. This layer is NOT wired into input or execution: no caller
## in production invokes it yet. It answers whether a capability-permitted
## action is currently allowed by runtime liveness, so a future integration
## phase can consult it without re-deciding weapon/frame/handling rules.
##
## Flow (capability is never re-evaluated here):
##   capability denied  → Gate denied, capability reason preserved verbatim
##   mech destroyed     → Gate denied (dead)
##   operator absent    → Gate denied (disabled)
##   otherwise          → Gate allowed
##
## Grounding (every rule mirrors an existing gate, nothing invented):
##   Capability first .. separation contract: capability answers structural
##      support, the Gate answers current permission. A capability denial
##      must never become a Gate approval (layers would contradict).
##   Destroyed ......... WeaponManager._input ignores every weapon input
##      while HealthSystem.is_destroyed ("the weapons are dead"); the
##      flag is set before the core-breach death window, so it covers the
##      whole terminal sequence. MechaCombat aim resolution gates on it too.
##   Operator absent ... WeaponManager._input ignores mech-loadout input in
##      GameManager.State.EJECT (fire buttons belong to the pilot's body).
##   NOT gated here .... movement speed / sprint / dodge / airborne /
##      attack-in-flight / guard-raised / stun / disruption / reload /
##      ammo / heat / cooldown / trigger: the fire, melee, guard and aim
##      execution paths consult NONE of these (verified by inspection:
##      WeaponManager fire paths gate only on hand usability, mount,
##      reload/shield-type/core readiness and special contracts).
##      Melee restarts mid-swing by design (combo system); firing while the
##      guard is raised is permitted in execution. Recording them as
##      UNDEFINED-but-allowed would invent balance — so the Gate simply has
##      no opinion on them, and the State x Action matrix documents each as
##      "no existing restriction". Combat resources stay combat-owned.
##
## `capability` is a WeaponGameplayCapability.query result (or the WM
## get_capability projection of one). `runtime` is caller-gathered liveness:
## {mech_destroyed: bool, operator_absent: bool}; missing keys default to
## false (alive, operator present). Returns the same shape it was given:
## {allowed: bool, reason: String, action: String,
##  grip_mode: String, mount_kind: String}.
## Pure query: no animation, no combat, no input, no state mutation.

# Runtime (Gate-owned) reasons. Capability reasons pass through verbatim.
const REASON_OK := "ok"
const REASON_DEAD := "dead"
const REASON_DISABLED := "disabled"


## Single authoritative gate query. Read-only and deterministic.
static func query(capability: Dictionary, runtime: Dictionary) -> Dictionary:
	var out := {
		"allowed": false,
		"reason": str(capability.get("reason", "no_weapon")),
		"action": str(capability.get("action", "")),
		"grip_mode": str(capability.get("grip_mode", "")),
		"mount_kind": str(capability.get("mount_kind", "")),
	}
	# Capability denial flows through: the Gate never approves what the
	# capability layer rejected, and the reason is preserved verbatim so a
	# future integration phase can tell structural from runtime denials.
	if not bool(capability.get("allowed", false)):
		return out
	# Terminal mech state (covers the core-breach death window too).
	if bool(runtime.get("mech_destroyed", false)):
		out["reason"] = REASON_DEAD
		return out
	# Parked mech: its loadout inputs belong to nobody while ejected.
	if bool(runtime.get("operator_absent", false)):
		out["reason"] = REASON_DISABLED
		return out
	out["allowed"] = true
	out["reason"] = REASON_OK
	return out
