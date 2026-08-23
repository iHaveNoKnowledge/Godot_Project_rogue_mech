extends RefCounted

## ---------------------------------------------------------------------------
## THERMAL / CAMOUFLAGE CLOAK — GDD §6.2
##
## A physics-enabled cloth cloak that reduces the mech's thermal signature,
## making it harder for patrols to detect and artillery to target.
##
## The cloak is an equipment item that can be toggled on/off during board
## movement. When active:
##   - Patrol detection radius reduced by CLOAK_DETECTION_REDUCTION
##   - Artillery targeting multiplier reduced by CLOAK_ARTILLERY_REDUCTION
##   - Alert level gain per step reduced by CLOAK_ALERT_REDUCTION
##   - Visual: physics-enabled cloth that flaps with movement
##
## The cloak has a limited charge that depletes while active and recharges
## slowly when inactive.
## ---------------------------------------------------------------------------

# ---- Detection reductions (GDD §6.2) ----
const CLOAK_DETECTION_REDUCTION: int = 3    # Patrol detection radius -3
const CLOAK_ARTILLERY_REDUCTION: float = 0.4  # Artillery targeting ×0.4
const CLOAK_ALERT_REDUCTION: int = 1        # Alert gain per step -1

# ---- Cloak charge system ----
const CLOAK_MAX_CHARGE: float = 100.0
const CLOAK_DRAIN_PER_STEP: float = 8.0     # Charge drain per board step
const CLOAK_RECHARGE_PER_DAY: float = 25.0  # Charge恢复 per day
const CLOAK_MIN_ACTIVATION: float = 10.0    # Minimum charge to activate

# ---- Thermal signature levels ----
const SIGNATURE_FULL: float = 1.0    # No cloak
const SIGNATURE_CLOAKED: float = 0.25  # 75% reduction when cloaked


# ==========================================================================
# STATE
# ==========================================================================

var is_active: bool = false
var charge: float = CLOAK_MAX_CHARGE


# ==========================================================================
# QUERIES
# ==========================================================================

## Returns the effective patrol detection radius reduction when cloaked.
## Used by PatrolSystem.record_spotting() and board movement.
static func detection_reduction() -> int:
	if not _is_cloaked():
		return 0
	return CLOAK_DETECTION_REDUCTION


## Returns the artillery targeting multiplier when cloaked.
static func artillery_multiplier() -> float:
	if not _is_cloaked():
		return 1.0
	return CLOAK_ARTILLERY_REDUCTION


## Returns the alert level gain reduction per step when cloaked.
static func alert_reduction() -> int:
	if not _is_cloaked():
		return 0
	return CLOAK_ALERT_REDUCTION


## Returns the thermal signature level (0.0 = invisible, 1.0 = full).
static func thermal_signature() -> float:
	if not _is_cloaked():
		return SIGNATURE_FULL
	return SIGNATURE_CLOAKED


## Returns charge percentage (0.0 - 100.0).
func charge_percent() -> float:
	return clampf(charge / CLOAK_MAX_CHARGE * 100.0, 0.0, 100.0)


## Returns true if cloak has enough charge to activate.
func can_activate() -> bool:
	return charge >= CLOAK_MIN_ACTIVATION


## Returns true if the cloak is currently active (instance method for HUD).
func is_cloak_active() -> bool:
	return is_active and charge >= CLOAK_MIN_ACTIVATION


# ==========================================================================
# MUTATION
# ==========================================================================

## Activates the cloak. Returns true if successful.
func activate() -> bool:
	if not can_activate():
		return false
	is_active = true
	return true


## Deactivates the cloak.
func deactivate() -> void:
	is_active = false


## Toggles the cloak on/off. Returns new state.
func toggle() -> bool:
	if is_active:
		deactivate()
		return false
	else:
		return activate()


## Drains charge when the mech takes a board step. Called by board_manager.
func drain_step() -> void:
	if is_active:
		charge = maxf(charge - CLOAK_DRAIN_PER_STEP, 0.0)
		if charge < CLOAK_MIN_ACTIVATION:
			deactivate()


## Recharges cloak at end of day. Called by day_end_tick.
func recharge_day() -> void:
	charge = minf(charge + CLOAK_RECHARGE_PER_DAY, CLOAK_MAX_CHARGE)


## Resets to full charge (e.g. at safehouse).
func full_recharge() -> void:
	charge = CLOAK_MAX_CHARGE


## Serializes for save/load.
func serialize() -> Dictionary:
	return {
		"active": is_active,
		"charge": charge,
	}


## Deserializes from save data.
func deserialize(data: Dictionary) -> void:
	is_active = bool(data.get("active", false))
	charge = float(data.get("charge", CLOAK_MAX_CHARGE))


# ==========================================================================
# INTERNAL
# ==========================================================================

## Checks if the cloak is active via GlobalData (static helper).
static func _is_cloaked() -> bool:
	if not GlobalData.has_method("fuel"):
		return false
	# Check if the player has a cloak equipped (stored on hangar mech)
	var cloak = _get_active_cloak()
	return cloak != null and cloak.is_cloak_active()


## Gets the active cloak instance from GlobalData.
static func _get_active_cloak():
	# The cloak instance is stored on the current hangar mech's loadout.
	# For now, use a simple global reference.
	if GlobalData.has_method("get") and GlobalData.get("thermal_cloak") != null:
		return GlobalData.thermal_cloak
	return null


# ==========================================================================
# DISPLAY
# ==========================================================================

## Returns a display string for the HUD.
func status_display() -> String:
	if is_active:
		return "🧥 CLOAK: ON (%.0f%%)" % charge_percent()
	return "🧥 CLOAK: OFF (%.0f%%)" % charge_percent()


## Returns a compact status for the board HUD.
func compact_display() -> String:
	if is_active:
		return "CLOAK %.0f%%" % charge_percent()
	return ""
