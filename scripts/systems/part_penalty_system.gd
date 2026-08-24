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
# READ HELPERS — get damage ratio for a slot
# ==========================================================================

## Returns the armor damage ratio for a slot (0.0 = pristine, 1.0 = destroyed).
static func armor_damage(slot: String) -> float:
	return clampf(float(GlobalData.weapons.part_damage.get(slot, 0.0)), 0.0, 1.0)


## Returns the frame damage ratio for a slot (0.0 = pristine, 1.0 = destroyed).
static func frame_damage(slot: String) -> float:
	return clampf(float(GlobalData.weapons.part_damage.get(slot + "_frame", 0.0)), 0.0, 1.0)


## Combined damage for a slot (whichever layer is worse).
static func combined_damage(slot: String) -> float:
	return maxf(armor_damage(slot), frame_damage(slot))


## Best damage across both arms (worst arm dictates penalties).
static func worst_arm_damage() -> float:
	return maxf(combined_damage("arm_left"), combined_damage("arm_right"))


## Best damage across both legs (worst leg dictates penalties).
static func worst_leg_damage() -> float:
	return maxf(combined_damage("leg_left"), combined_damage("leg_right"))


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
