extends RefCounted

## ---------------------------------------------------------------------------
## EWAR SYSTEM — Electronic Warfare Abilities (GDD §7 Extended)
##
## 4 distinct EWar abilities unlocked by Head part sensors:
##   1. JAM    — Sensor Jamming: reduces enemy detection range + accuracy
##   2. SPOOF  — Radar Spoofing: creates false signatures to misdirect patrols
##   3. EMP    — EMP Burst: temporary electronics disable (stun/weapons)
##   4. SCRAMBLE — Comm Scramble: prevents enemy reinforcement calls
##
## Each ability has energy cost, cooldown, duration, and tier scaling.
## ---------------------------------------------------------------------------

# ---- Ability IDs ----
enum Ability { JAM, SPOOF, EMP, SCRAMBLE }

# ---- Cooldown timers (seconds in combat, hours on board) ----
const COOLDOWN_JAM: float = 12.0
const COOLDOWN_SPOOF: float = 18.0
const COOLDOWN_EMP: float = 25.0
const COOLDOWN_SCRAMBLE: float = 20.0

# ---- Energy costs ----
const COST_JAM: float = 15.0
const COST_SPOOF: float = 20.0
const COST_EMP: float = 35.0
const COST_SCRAMBLE: float = 25.0

# ---- Duration (seconds in combat) ----
const DURATION_JAM: float = 8.0
const DURATION_SPOOF: float = 12.0
const DURATION_EMP: float = 4.0
const DURATION_SCRAMBLE: float = 15.0

# ---- Effect Strength (base values, scaled by tier) ----
# Jam: reduces enemy detection radius
const JAM_DETECT_REDUCTION_BASE: int = 4
const JAM_ACCURACY_PENALTY_BASE: float = 0.3   # 30% accuracy loss

# Spoof: creates false patrol signatures
const SPOOF_FALSE_SIGNATURES: int = 2          # number of false pings
const SPOOF_REDIRECT_RANGE: int = 5            # tiles radius for misdirect

# EMP: disables enemy electronics
const EMP_STUN_DURATION_BASE: float = 3.0      # seconds enemies stunned
const EMP_WEAPON_DISABLE_BASE: float = 5.0     # seconds weapons disabled

# Scramble: prevents reinforcement calls
const SCRAMBLE_BLOCK_RADIUS: int = 8           # tiles radius


# ==========================================================================
# STATE
# ==========================================================================

var cooldowns: Dictionary = {
	Ability.JAM: 0.0,
	Ability.SPOOF: 0.0,
	Ability.EMP: 0.0,
	Ability.SCRAMBLE: 0.0,
}

var active_effects: Dictionary = {
	Ability.JAM: 0.0,
	Ability.SPOOF: 0.0,
	Ability.EMP: 0.0,
	Ability.SCRAMBLE: 0.0,
}

## Head tier (1-3) for scaling effect strength.
var head_tier: int = 1


# ==========================================================================
# QUERIES
# ==========================================================================

## Returns true if the ability is off cooldown and player has enough energy.
func can_activate(ability: int, current_energy: float) -> bool:
	if cooldowns.get(ability, 0.0) > 0.0:
		return false
	return current_energy >= _energy_cost(ability)


## Returns remaining cooldown for an ability.
func get_cooldown(ability: int) -> float:
	return maxf(cooldowns.get(ability, 0.0), 0.0)


## Returns true if the ability is currently active.
func is_active(ability: int) -> bool:
	return active_effects.get(ability, 0.0) > 0.0


## Returns remaining duration for an active effect.
func get_active_duration(ability: int) -> float:
	return maxf(active_effects.get(ability, 0.0), 0.0)


## Returns the display name for an ability.
func ability_name(ability: int) -> String:
	match ability:
		Ability.JAM: return "SENSOR JAM"
		Ability.SPOOF: return "RADAR SPOOF"
		Ability.EMP: return "EMP BURST"
		Ability.SCRAMBLE: return "COMM SCRAMBLE"
	return "UNKNOWN"


## Returns ability description.
func ability_desc(ability: int) -> String:
	match ability:
		Ability.JAM: return "Disrupts enemy sensors. Reduces detection range and accuracy."
		Ability.SPOOF: return "Creates false radar signatures to misdirect patrols."
		Ability.EMP: return "Electromagnetic pulse. Stuns nearby enemies, disables weapons."
		Ability.SCRAMBLE: return "Jams communications. Prevents enemy reinforcement calls."
	return ""


## Returns icon emoji for an ability.
func ability_icon(ability: int) -> String:
	match ability:
		Ability.JAM: return "📡"
		Ability.SPOOF: return "🎯"
		Ability.EMP: return "⚡"
		Ability.SCRAMBLE: return "📻"
	return "❓"


# ==========================================================================
# MUTATION
# ==========================================================================

## Activates an ability. Returns true if successful, drains energy, starts cooldown.
func activate(ability: int, current_energy: float) -> float:
	## Returns new energy after activation (or same if failed).
	if not can_activate(ability, current_energy):
		return current_energy
	var cost := _energy_cost(ability)
	cooldowns[ability] = _cooldown_time(ability)
	active_effects[ability] = _duration(ability)
	return current_energy - cost


## Ticks cooldowns and active effects. Call each frame with delta time.
func tick(delta: float) -> void:
	for ability in cooldowns:
		if cooldowns[ability] > 0.0:
			cooldowns[ability] = maxf(cooldowns[ability] - delta, 0.0)
	for ability in active_effects:
		if active_effects[ability] > 0.0:
			active_effects[ability] = maxf(active_effects[ability] - delta, 0.0)


## Resets all cooldowns (e.g. at safehouse).
func reset_cooldowns() -> void:
	for ability in cooldowns:
		cooldowns[ability] = 0.0


## Full reset (new run).
func reset() -> void:
	reset_cooldowns()
	for ability in active_effects:
		active_effects[ability] = 0.0
	head_tier = 1


# ==========================================================================
# EFFECT QUERIES (called by combat/board systems)
# ==========================================================================

## Returns the effective detection radius reduction from JAM.
func jam_detection_reduction() -> int:
	if not is_active(Ability.JAM):
		return 0
	return int(JAM_DETECT_REDUCTION_BASE * _tier_mult())


## Returns the accuracy penalty multiplier from JAM (0.0 = no penalty, 1.0 = full miss).
## Apply to enemy accuracy: effective_accuracy = base_accuracy * (1.0 - jam_accuracy_penalty())
func jam_accuracy_penalty() -> float:
	if not is_active(Ability.JAM):
		return 0.0
	return JAM_ACCURACY_PENALTY_BASE * _tier_mult()


## Returns number of false radar signatures from SPOOF.
func spoof_false_signature_count() -> int:
	if not is_active(Ability.SPOOF):
		return 0
	return SPOOF_FALSE_SIGNATURES


## Returns the redirect range in tiles for SPOOF.
func spoof_redirect_range() -> int:
	return SPOOF_REDIRECT_RANGE


## Returns stun duration from EMP.
func emp_stun_duration() -> float:
	if not is_active(Ability.EMP):
		return 0.0
	return EMP_STUN_DURATION_BASE * _tier_mult()


## Returns weapon disable duration from EMP.
func emp_weapon_disable_duration() -> float:
	if not is_active(Ability.EMP):
		return 0.0
	return EMP_WEAPON_DISABLE_BASE * _tier_mult()


## Returns the block radius from SCRAMBLE.
func scramble_block_radius() -> int:
	if not is_active(Ability.SCRAMBLE):
		return 0
	return int(SCRAMBLE_BLOCK_RADIUS * _tier_mult())


# ==========================================================================
# SERIALIZE / DESERIALIZE
# ==========================================================================

func serialize() -> Dictionary:
	return {
		"cooldowns": {
			"jam": cooldowns[Ability.JAM],
			"spoof": cooldowns[Ability.SPOOF],
			"emp": cooldowns[Ability.EMP],
			"scramble": cooldowns[Ability.SCRAMBLE],
		},
		"active": {
			"jam": active_effects[Ability.JAM],
			"spoof": active_effects[Ability.SPOOF],
			"emp": active_effects[Ability.EMP],
			"scramble": active_effects[Ability.SCRAMBLE],
		},
		"head_tier": head_tier,
	}


func deserialize(data: Dictionary) -> void:
	var cd: Dictionary = data.get("cooldowns", {})
	cooldowns[Ability.JAM] = float(cd.get("jam", 0.0))
	cooldowns[Ability.SPOOF] = float(cd.get("spoof", 0.0))
	cooldowns[Ability.EMP] = float(cd.get("emp", 0.0))
	cooldowns[Ability.SCRAMBLE] = float(cd.get("scramble", 0.0))
	var act: Dictionary = data.get("active", {})
	active_effects[Ability.JAM] = float(act.get("jam", 0.0))
	active_effects[Ability.SPOOF] = float(act.get("spoof", 0.0))
	active_effects[Ability.EMP] = float(act.get("emp", 0.0))
	active_effects[Ability.SCRAMBLE] = float(act.get("scramble", 0.0))
	head_tier = int(data.get("head_tier", 1))


# ==========================================================================
# INTERNAL
# ==========================================================================

func _energy_cost(ability: int) -> float:
	match ability:
		Ability.JAM: return COST_JAM
		Ability.SPOOF: return COST_SPOOF
		Ability.EMP: return COST_EMP
		Ability.SCRAMBLE: return COST_SCRAMBLE
	return 0.0


func _cooldown_time(ability: int) -> float:
	match ability:
		Ability.JAM: return COOLDOWN_JAM
		Ability.SPOOF: return COOLDOWN_SPOOF
		Ability.EMP: return COOLDOWN_EMP
		Ability.SCRAMBLE: return COOLDOWN_SCRAMBLE
	return 0.0


func _duration(ability: int) -> float:
	match ability:
		Ability.JAM: return DURATION_JAM
		Ability.SPOOF: return DURATION_SPOOF
		Ability.EMP: return DURATION_EMP
		Ability.SCRAMBLE: return DURATION_SCRAMBLE
	return 0.0


## Tier scaling multiplier (Tier 1 = 1.0, Tier 2 = 1.25, Tier 3 = 1.5).
func _tier_mult() -> float:
	return 1.0 + (head_tier - 1) * 0.25
