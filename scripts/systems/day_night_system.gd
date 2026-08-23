extends RefCounted

## ---------------------------------------------------------------------------
## DAY / NIGHT SYSTEM — GDD §3.1
##
## 24-hour operational cycle with environmental modifiers:
##   Daytime (06:00 - 18:00): max radar, high alert, easy artillery targeting
##   Nighttime (18:00 - 06:00): -50% radar, low alert, stealth-friendly
##
## Time is stored in GlobalData.board as `time_hour` (0-23 float).
## Each movement step or event costs time; _end_day advances to next dawn.
## ---------------------------------------------------------------------------

const _PCS = preload("res://scripts/systems/power_core_system.gd")

# ---- Phase boundaries ----
const DAWN_HOUR := 6.0
const DUSK_HOUR := 18.0

# ---- Radar / Scan range multipliers (GDD §3.1) ----
const DAY_RADAR_MULT := 1.0    # Full range
const NIGHT_RADAR_MULT := 0.5  # -50% scan range

# ---- Alert level gain per step (GDD §3.1) ----
const DAY_ALERT_PER_STEP := 1    # Easier to be spotted during daytime
const NIGHT_ALERT_PER_STEP := 0  # Stealth at night — no passive alert gain

# ---- Patrol detection rate (stealth) ----
# At night, patrols have reduced detection radius.
const DAY_PATROL_DETECT_RADIUS := 2
const NIGHT_PATROL_DETECT_RADIUS := 1

# ---- Artillery targeting difficulty ----
# Day = artillery can target more easily (larger targeting window).
const DAY_ARTILLERY_TARGETING_MULT := 1.0
const NIGHT_ARTILLERY_TARGETING_MULT := 0.5

# ---- Time cost per movement step (hours) ----
# Each step on the board consumes time.
const STEP_TIME_COST_DAY := 1.0    # 1 hour per step during day
const STEP_TIME_COST_NIGHT := 2.0  # 2 hours per step at night (slower movement)

# ---- Starting hour for new runs ----
const DEFAULT_START_HOUR := 8.0  # Start at 08:00 (morning)


# ==========================================================================
# QUERIES
# ==========================================================================

## Current hour from board state (0.0 - 23.999...).
static func current_hour() -> float:
	return GlobalData.board.time_hour


## Current day number.
static func current_day() -> int:
	return GlobalData.board.board_day


## Returns true if it is currently daytime (06:00 - 18:00).
static func is_daytime() -> bool:
	var h := current_hour()
	return h >= DAWN_HOUR and h < DUSK_HOUR


## Returns true if it is currently nighttime (18:00 - 06:00).
static func is_nighttime() -> bool:
	return not is_daytime()


## Phase name for UI display.
static func phase_name() -> String:
	if is_daytime():
		return "DAY"
	return "NIGHT"


## Time formatted as "HH:MM" string.
static func time_string() -> String:
	var h := current_hour()
	var hours := int(h)
	var minutes := int((h - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]


## Full display string like "14:00 — Day 3 (DAY)".
static func display_string() -> String:
	return "%s — Day %d (%s)" % [time_string(), current_day(), phase_name()]


## Progress through the current phase (0.0 = phase start, 1.0 = phase end).
static func phase_progress() -> float:
	var h := current_hour()
	if is_daytime():
		return clampf((h - DAWN_HOUR) / (DUSK_HOUR - DAWN_HOUR), 0.0, 1.0)
	else:
		# Night spans from 18:00 to 06:00 next day = 12 hours
		if h >= DUSK_HOUR:
			return clampf((h - DUSK_HOUR) / (24.0 - DUSK_HOUR + DAWN_HOUR), 0.0, 1.0)
		else:
			return clampf((24.0 - DUSK_HOUR + h) / (24.0 - DUSK_HOUR + DAWN_HOUR), 0.0, 1.0)


# ==========================================================================
# MODIFIERS
# ==========================================================================

## Radar / scan range multiplier (applied to reveal radius).
static func radar_range_multiplier() -> float:
	return DAY_RADAR_MULT if is_daytime() else NIGHT_RADAR_MULT


## Alert level gained per movement step.
static func alert_per_step() -> int:
	return DAY_ALERT_PER_STEP if is_daytime() else NIGHT_ALERT_PER_STEP


## Patrol detection radius on the board.
static func patrol_detect_radius() -> int:
	return DAY_PATROL_DETECT_RADIUS if is_daytime() else NIGHT_PATROL_DETECT_RADIUS


## Artillery targeting multiplier (affects bombardment accuracy/frequency).
static func artillery_targeting_multiplier() -> float:
	return DAY_ARTILLERY_TARGETING_MULT if is_daytime() else NIGHT_ARTILLERY_TARGETING_MULT


## Time cost per movement step (hours).
static func step_time_cost() -> float:
	return STEP_TIME_COST_DAY if is_daytime() else STEP_TIME_COST_NIGHT


## Stealth bonus: at night, pilot-mode movement is harder to detect.
static func stealth_bonus() -> float:
	return 0.0 if is_daytime() else 0.35  # +35% stealth at night


## HK fleet attraction multiplier (Ancient Core draws more at night).
static func hk_night_multiplier() -> float:
	return 1.5 if is_nighttime() else 1.0


# ==========================================================================
# MUTATION
# ==========================================================================

## Advances the clock by the given number of hours. Wraps around midnight.
## Returns true if midnight was crossed (new calendar day started).
static func advance_time(hours: float) -> bool:
	var old_hour := current_hour()
	var new_hour := fmod(old_hour + hours, 24.0)
	GlobalData.board.time_hour = new_hour
	# Wrapped around midnight → new calendar day
	return old_hour > new_hour


## Advances time by one movement step (terrain-dependent).
static func advance_step(terrain: String = "road") -> bool:
	var cost := step_time_cost()
	# Off-road costs more time
	if terrain in ["sand", "forest"]:
		cost *= 1.5
	return advance_time(cost)


## Called at end of day — snaps time to dawn of next day.
static func advance_to_next_dawn() -> void:
	GlobalData.board.time_hour = DAWN_HOUR


## Initializes time_hour on a fresh run or load.
static func ensure_time_initialized() -> void:
	if GlobalData.board.time_hour <= 0.0:
		GlobalData.board.time_hour = DEFAULT_START_HOUR
