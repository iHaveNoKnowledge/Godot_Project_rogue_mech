class_name PartPenaltySystem
extends RefCounted

## ---------------------------------------------------------------------------
## PART PENALTY SYSTEM — GDD §6.1 Part Penalties
##
## When a mech part's durability drops low enough, gameplay penalties kick in:
##   Head:   slow lock-on, increased spread, HUD glitch at > 50%
##   Arms:   increased recoil, melee slowdown, can't equip heavy at > 50%
##   Legs:   reduced speed, dash stutter at > 50%
##   Torso:  reduced max energy, faster heat accumulation, easier overheat
##
## Penalties scale with damage: mild at 40%, moderate at 60%, severe at 80%.
## All methods are static — no instance state needed.  Reads directly from
## GlobalData.weapons.part_damage which is the live combat damage cache.
## ---------------------------------------------------------------------------

# --- Damage thresholds (damage ratio, 0.0 = pristine, 1.0 = destroyed) ---
const THRESHOLD_MILD: float = 0.40    # 40% damage — penalties start
const THRESHOLD_MODERATE: float = 0.60 # 60% damage — noticeable debuffs
const THRESHOLD_SEVERE: float = 0.80   # 80% damage — major penalties

# --- Penalty constants (GDD §6.1) ---

# Head penalties — tuned down: severe 0.15→0.10 was too punishing (wild bullets at 80% head dmg)
const HEAD_SPREAD_MILD: float = 0.03       # +3% weapon spread
const HEAD_SPREAD_MODERATE: float = 0.07   # +7% weapon spread
const HEAD_SPREAD_SEVERE: float = 0.10     # +10% weapon spread
const HEAD_LOCK_ON_MILD: float = 0.85      # lock-on speed 85%
const HEAD_LOCK_ON_MODERATE: float = 0.65  # lock-on speed 65%
const HEAD_LOCK_ON_SEVERE: float = 0.40    # lock-on speed 40%
const HEAD_HUD_GLITCH_THRESHOLD: float = 0.50  # HUD starts glitching at 50%

# Arm penalties (combined both arms)
const ARM_RECOIL_MILD: float = 1.20       # +20% recoil
const ARM_RECOIL_MODERATE: float = 1.50   # +50% recoil
const ARM_RECOIL_SEVERE: float = 2.00     # +100% recoil
const ARM_MELEE_SPEED_MILD: float = 0.90  # melee attack 90% speed
const ARM_MELEE_SPEED_MODERATE: float = 0.75  # melee 75% speed
const ARM_MELEE_SPEED_SEVERE: float = 0.55    # melee 55% speed
const ARM_HEAVY_THRESHOLD: float = 0.70   # can't equip heavy weapons above 70%

# Leg penalties (combined both legs)
const LEG_SPEED_MILD: float = 0.90        # 90% walk speed
const LEG_SPEED_MODERATE: float = 0.75    # 75% walk speed
const LEG_SPEED_SEVERE: float = 0.55      # 55% walk speed
const LEG_DASH_MILD: float = 0.85         # dash speed 85%
const LEG_DASH_MODERATE: float = 0.65     # dash speed 65%
const LEG_DASH_SEVERE: float = 0.40       # dash speed 40%

# Torso penalties
const TORSO_ENERGY_MILD: float = 0.90     # max energy 90%
const TORSO_ENERGY_MODERATE: float = 0.75  # max energy 75%
const TORSO_ENERGY_SEVERE: float = 0.55    # max energy 55%
const TORSO_HEAT_MILD: float = 1.15       # heat accumulation +15%
const TORSO_HEAT_MODERATE: float = 1.35   # heat accumulation +35%
const TORSO_HEAT_SEVERE: float = 1.60     # heat accumulation +60%


# ==========================================================================
# READ HELPERS — get Frame Durability wear ratio for a slot
# (Debuffs are driven strictly by Frame Durability wear: 0.0 = pristine 100% dur, 1.0 = 0% dur)
# ==========================================================================

## Returns the frame wear / degradation ratio for a slot (0.0 = 100% dur, 1.0 = 0% dur).
static func frame_wear(slot: String) -> float:
	var base_slot := str(slot).replace("_frame", "")
	var dur := GlobalData.get_frame_durability(base_slot)
	return clampf(1.0 - dur, 0.0, 1.0)


## Combined wear for a slot (alias for frame_wear to ensure armor damage does NOT inflict operational debuffs).
static func combined_damage(slot: String) -> float:
	return frame_wear(slot)


## Returns the armor damage ratio for a slot (0.0 = pristine, 1.0 = destroyed). Kept for combat UI queries.
static func armor_damage(slot: String) -> float:
	return clampf(float(GlobalData.weapons.part_damage.get(slot, 0.0)), 0.0, 1.0)


## Returns the frame combat damage ratio for a slot (0.0 = pristine, 1.0 = destroyed). Kept for combat UI queries.
static func frame_damage(slot: String) -> float:
	return clampf(float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)


## Worst frame wear across both arms (dictates arm operational penalties).
static func worst_arm_damage() -> float:
	return maxf(frame_wear("arm_left"), frame_wear("arm_right"))


## Worst frame wear across both legs (dictates leg operational penalties).
static func worst_leg_damage() -> float:
	return maxf(frame_wear("leg_left"), frame_wear("leg_right"))


# ==========================================================================
# PENALTY CALCULATIONS — per part category
# ==========================================================================

# --- HEAD PENALTIES ---

## Extra weapon spread from damaged head optics (GDD §6.1: HUD glitch, slow lock-on).
static func head_spread_penalty() -> float:
	var dmg := combined_damage("head")
	if dmg < THRESHOLD_MILD:
		return 0.0
	if dmg < THRESHOLD_MODERATE:
		return HEAD_SPREAD_MILD
	if dmg < THRESHOLD_SEVERE:
		return HEAD_SPREAD_MODERATE
	return HEAD_SPREAD_SEVERE


## Lock-on speed multiplier from damaged head sensors (1.0 = normal).
static func head_lock_on_multiplier() -> float:
	var dmg := combined_damage("head")
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return HEAD_LOCK_ON_MILD
	if dmg < THRESHOLD_SEVERE:
		return HEAD_LOCK_ON_MODERATE
	return HEAD_LOCK_ON_SEVERE


## True when the HUD should show glitch effects (scanlines, static).
static func head_hud_glitching() -> bool:
	return combined_damage("head") >= HEAD_HUD_GLITCH_THRESHOLD


# --- ARM PENALTIES --|

## Recoil multiplier from damaged arms (GDD §6.1: high recoil, slow melee).
static func arm_recoil_multiplier() -> float:
	var dmg := worst_arm_damage()
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return ARM_RECOIL_MILD
	if dmg < THRESHOLD_SEVERE:
		return ARM_RECOIL_MODERATE
	return ARM_RECOIL_SEVERE


## Melee attack speed multiplier from damaged arms.
static func arm_melee_speed_multiplier() -> float:
	var dmg := worst_arm_damage()
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return ARM_MELEE_SPEED_MILD
	if dmg < THRESHOLD_SEVERE:
		return ARM_MELEE_SPEED_MODERATE
	return ARM_MELEE_SPEED_SEVERE


## True when arms are too damaged to hold heavy weapons (GDD §6.1).
static func arm_cannot_equip_heavy() -> bool:
	return worst_arm_damage() >= ARM_HEAVY_THRESHOLD


# --- LEG PENALTIES ---

## Walk speed multiplier from damaged legs (GDD §6.1: reduced MP/speed).
static func leg_speed_multiplier() -> float:
	var dmg := worst_leg_damage()
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return LEG_SPEED_MILD
	if dmg < THRESHOLD_SEVERE:
		return LEG_SPEED_MODERATE
	return LEG_SPEED_SEVERE


## Roller-dash speed multiplier from damaged legs.
static func leg_dash_multiplier() -> float:
	var dmg := worst_leg_damage()
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return LEG_DASH_MILD
	if dmg < THRESHOLD_SEVERE:
		return LEG_DASH_MODERATE
	return LEG_DASH_SEVERE


# --- TORSO PENALTIES ---

## Max energy multiplier from damaged torso (GDD §6.1: reduced max energy).
static func torso_energy_multiplier() -> float:
	var dmg := combined_damage("body")
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return TORSO_ENERGY_MILD
	if dmg < THRESHOLD_SEVERE:
		return TORSO_ENERGY_MODERATE
	return TORSO_ENERGY_SEVERE


## Heat accumulation multiplier from damaged torso (GDD §6.1: easier overheat).
static func torso_heat_multiplier() -> float:
	var dmg := combined_damage("body")
	if dmg < THRESHOLD_MILD:
		return 1.0
	if dmg < THRESHOLD_MODERATE:
		return TORSO_HEAT_MILD
	if dmg < THRESHOLD_SEVERE:
		return TORSO_HEAT_MODERATE
	return TORSO_HEAT_SEVERE


# ==========================================================================
# COMPOSITE QUERIES — used by multiple systems
# ==========================================================================

## Total spread penalty (head + arm contribution).
static func total_spread_penalty() -> float:
	return head_spread_penalty()


## Total recoil multiplier (arm penalty).
static func total_recoil_multiplier() -> float:
	return arm_recoil_multiplier()


## Total speed multiplier (leg + torso if on board).
static func total_board_speed_multiplier() -> float:
	return leg_speed_multiplier()


## Total dash speed multiplier.
static func total_dash_speed_multiplier() -> float:
	return leg_dash_multiplier()


## Total heat multiplier (torso penalty, applied ON TOP of power core multiplier).
static func total_heat_multiplier() -> float:
	return torso_heat_multiplier()


## Total max energy multiplier.
static func total_energy_multiplier() -> float:
	return torso_energy_multiplier()


# ==========================================================================
# UI DESCRIPTION — text for HUD / status display
# ==========================================================================

## Returns a list of active penalty descriptions for the HUD.
static func active_penalties() -> Array[String]:
	var penalties: Array[String] = []
	# Head
	if combined_damage("head") >= THRESHOLD_MILD:
		penalties.append("⚠ HEAD: HUD glitching, slow lock-on")
	# Arms
	var arm_dmg := worst_arm_damage()
	if arm_dmg >= THRESHOLD_MILD:
		penalties.append("⚠ ARMS: High recoil, slow melee")
	if arm_dmg >= ARM_HEAVY_THRESHOLD:
		penalties.append("✖ ARMS: Cannot equip heavy weapons")
	# Legs
	var leg_dmg := worst_leg_damage()
	if leg_dmg >= THRESHOLD_MILD:
		penalties.append("⚠ LEGS: Reduced speed")
	if leg_dmg >= THRESHOLD_MODERATE:
		penalties.append("⚠ LEGS: Dash malfunction")
	# Torso
	if combined_damage("body") >= THRESHOLD_MILD:
		penalties.append("⚠ TORSO: Reduced energy, faster overheat")
	return penalties


## Returns a compact one-line summary of the worst penalty.
static func worst_penalty_summary() -> String:
	var penalties := active_penalties()
	if penalties.is_empty():
		return ""
	return penalties[0]


## Formats a base value with strikethrough and penalty value if degraded:
## e.g. base 100 with mult 0.75 -> "[s]100[/s] 75 (-25%)"
static func format_stat_with_penalty(base_val: float, penalty_mult: float, unit: String = "") -> String:
	if absf(penalty_mult - 1.0) < 0.01:
		return "%.0f%s" % [base_val, unit]
	var eff := base_val * penalty_mult
	var diff_pct := int(round((1.0 - penalty_mult) * 100.0))
	var sign_str := "-" if diff_pct > 0 else "+"
	return "[s]%.0f%s[/s] %.0f%s (%s%d%%)" % [base_val, unit, eff, unit, sign_str, abs(diff_pct)]


## Returns a comprehensive formatted report of all active penalties with strikethrough base numbers.
static func get_detailed_penalty_report() -> String:
	var lines: Array[String] = []
	
	var leg_spd := leg_speed_multiplier()
	if leg_spd < 0.99:
		var pct := int(round(leg_spd * 100.0))
		lines.append("• LEGS (Walk Speed): [s]100%%[/s] -> %d%% (-%d%% Speed Penalty)" % [pct, 100 - pct])

	var leg_dsh := leg_dash_multiplier()
	if leg_dsh < 0.99:
		var pct := int(round(leg_dsh * 100.0))
		lines.append("• LEGS (Dash Speed): [s]100%%[/s] -> %d%% (-%d%% Roller Dash)" % [pct, 100 - pct])

	var torso_e := torso_energy_multiplier()
	if torso_e < 0.99:
		var pct := int(round(torso_e * 100.0))
		lines.append("• TORSO (Max Energy): [s]100%%[/s] -> %d%% (-%d%% Max Energy)" % [pct, 100 - pct])

	var torso_h := torso_heat_multiplier()
	if torso_h > 1.01:
		var pct := int(round(torso_h * 100.0))
		lines.append("• TORSO (Heat Stress): [s]100%%[/s] -> %d%% (+%d%% Faster Overheat)" % [pct, pct - 100])

	var arm_rec := arm_recoil_multiplier()
	if arm_rec > 1.01:
		var pct := int(round(arm_rec * 100.0))
		lines.append("• ARMS (Recoil): [s]100%%[/s] -> %d%% (+%d%% Weapon Kick)" % [pct, pct - 100])

	var arm_mel := arm_melee_speed_multiplier()
	if arm_mel < 0.99:
		var pct := int(round(arm_mel * 100.0))
		lines.append("• ARMS (Melee Speed): [s]100%%[/s] -> %d%% (-%d%% Attack Cadence)" % [pct, 100 - pct])

	var head_sp := head_spread_penalty()
	if head_sp > 0.001:
		lines.append("• HEAD (Optics Spread): [s]+0%%[/s] -> +%.0f%% Spread (Sensor Glitch)" % [head_sp * 100.0])

	var head_lck := head_lock_on_multiplier()
	if head_lck < 0.99:
		var pct := int(round(head_lck * 100.0))
		lines.append("• HEAD (Lock-On Rate): [s]100%%[/s] -> %d%% (-%d%% Target Track)" % [pct, 100 - pct])

	if lines.is_empty():
		return ""
	return "⚠ ACTIVE PART PENALTIES & DEGRADATION:\n" + "\n".join(lines)
