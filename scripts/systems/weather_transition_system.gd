class_name WeatherTransitionSystem
extends RefCounted

## ---------------------------------------------------------------------------
## WEATHER TRANSITION SYSTEM — dynamic weather that changes over time.
##
## Weather is no longer static (set by stepping on a tile). Instead:
##   • Each weather event has a DURATION (in board steps)
##   • When duration expires, weather transitions to the next state
##   • Transitions are smooth (fade-in/fade-out over several steps)
##   • Time-of-day influences weather probability
##   • A 3-day forecast is available via radar
## ---------------------------------------------------------------------------

# --- Weather IDs ---
const CLEAR: String = ""
const RAIN: String = "rain"
const SANDSTORM: String = "sandstorm"
const FOG: String = "fog"
const DUST_STORM: String = "dust_storm"

# --- Duration (in board steps) ---
const MIN_WEATHER_DURATION: int = 4    # Weather lasts at least 4 steps
const MAX_WEATHER_DURATION: int = 14   # Weather lasts at most 14 steps
const TRANSITION_STEPS: int = 3        # Steps to fully transition in/out

# --- Probability weights (base) by time of day ---
# Each entry is { weather_id: weight } for that time bucket
const TIME_WEIGHTS: Dictionary = {
	# Dawn (5-7): fog is common
	"dawn": { CLEAR: 25, RAIN: 15, SANDSTORM: 5, FOG: 40, DUST_STORM: 15 },
	# Morning (7-12): mostly clear
	"morning": { CLEAR: 45, RAIN: 20, SANDSTORM: 10, FOG: 10, DUST_STORM: 15 },
	# Afternoon (12-17): sandstorm more likely
	"afternoon": { CLEAR: 30, RAIN: 15, SANDSTORM: 30, FOG: 5, DUST_STORM: 20 },
	# Evening (17-20): rain picks up
	"evening": { CLEAR: 20, RAIN: 35, SANDSTORM: 10, FOG: 20, DUST_STORM: 15 },
	# Night (20-5): fog dominates
	"night": { CLEAR: 15, RAIN: 20, SANDSTORM: 5, FOG: 45, DUST_STORM: 15 },
}

# --- State ---
var current_weather: String = ""         # Active weather hazard
var weather_duration: int = 0            # Steps remaining
var weather_max_duration: int = 0        # Total steps when started
var transition_progress: float = 0.0     # 0.0 = fully faded out, 1.0 = fully active
var is_transitioning: bool = false       # True during fade-in/fade-out
var forecast: Array[String] = []         # Next 3 weather predictions
var steps_since_change: int = 0          # Steps since last weather change
var total_steps: int = 0                 # Total steps taken since game start
var pending_event: String = ""           # Event to emit after transition completes

# Saved for serialization
var _rng_state: int = 0


func _init() -> void:
	_generate_forecast()


## Rolls the initial weather for a new board (called on sector entry).
func roll_initial_weather(hour: float) -> void:
	var bucket := _time_bucket(hour)
	var weights: Dictionary = TIME_WEIGHTS.get(bucket, TIME_WEIGHTS["morning"])
	var rolled := _weighted_roll(weights)
	if rolled != CLEAR:
		current_weather = rolled
		weather_duration = randi_range(MIN_WEATHER_DURATION, MAX_WEATHER_DURATION)
		weather_max_duration = weather_duration
		transition_progress = 0.0
		is_transitioning = true  # Will fade in over TRANSITION_STEPS
		pending_event = _weather_start_event(rolled)
	else:
		current_weather = CLEAR
		weather_duration = 0
		weather_max_duration = 0
		transition_progress = 1.0
		is_transitioning = false
	_generate_forecast()


## Ticks weather every board step. Returns an event dict if weather changed,
## or {} if nothing happened.
func tick_step(hour: float) -> Dictionary:
	total_steps += 1
	steps_since_change += 1
	var event: Dictionary = {}

	# Fade-in: increase transition progress
	if is_transitioning and transition_progress < 1.0:
		transition_progress = minf(transition_progress + 1.0 / float(TRANSITION_STEPS), 1.0)
		if transition_progress >= 1.0:
			is_transitioning = false
			# Emit the start event now that we're fully transitioned in
			if pending_event != "":
				event = _parse_event(pending_event)
				pending_event = ""

	# Fade-out: decrease transition progress
	if is_transitioning and transition_progress > 0.0 and current_weather == CLEAR:
		transition_progress = maxf(transition_progress - 1.0 / float(TRANSITION_STEPS), 0.0)
		if transition_progress <= 0.0:
			is_transitioning = false

	# Duration countdown
	if weather_duration > 0:
		weather_duration -= 1

	# Weather expired — start transitioning out
	if weather_duration <= 0 and current_weather != CLEAR and not is_transitioning:
		event = _begin_weather_end(hour)

	# If we're mid-transition-out and fully faded, start the new weather
	if current_weather == CLEAR and transition_progress <= 0.0 and is_transitioning:
		is_transitioning = false
		# Start next weather from forecast if available
		if not forecast.is_empty():
			var next_w: String = forecast.pop_front()
			_generate_forecast()
			if next_w != CLEAR:
				current_weather = next_w
				weather_duration = randi_range(MIN_WEATHER_DURATION, MAX_WEATHER_DURATION)
				weather_max_duration = weather_duration
				transition_progress = 0.0
				is_transitioning = true
				pending_event = _weather_start_event(next_w)

	return event


## Returns effective hazard multiplier (0.0–1.0) for gameplay effects.
## At transition_progress < 1.0, effects are weaker.
func get_effectiveness() -> float:
	if current_weather == CLEAR:
		return 0.0
	return transition_progress


## Returns the effective speed multiplier for the current weather.
func get_speed_multiplier() -> float:
	if current_weather == CLEAR:
		return 1.0
	var base := 1.0
	match current_weather:
		RAIN: base = 0.80
		SANDSTORM: base = 0.65
		FOG: base = 0.90
		DUST_STORM: base = 0.85
	# During transition, blend between 1.0 and base
	return lerpf(1.0, base, transition_progress)


## Returns the effective fuel drain multiplier.
func get_fuel_drain_multiplier() -> float:
	if current_weather == CLEAR:
		return 1.0
	var base := 1.0
	match current_weather:
		RAIN: base = 1.3
		SANDSTORM: base = 1.6
		FOG: base = 1.1
		DUST_STORM: base = 1.5
	return lerpf(1.0, base, transition_progress)


## Returns a visibility radius multiplier for fog-of-war reveal.
## 1.0 = normal visibility, lower = reduced tile reveal radius.
## Fog severely reduces visibility; sandstorm moderately; others normal.
func get_visibility_radius_modifier() -> float:
	if current_weather == CLEAR:
		return 1.0
	var base := 1.0
	match current_weather:
		RAIN: base = 0.85       # Slight reduction (rain drops obscure)
		SANDSTORM: base = 0.50  # 50% reduction (dense particles)
		FOG: base = 0.40        # 60% reduction (heavy fog blanket)
		DUST_STORM: base = 0.55 # 45% reduction (dust haze)
	return lerpf(1.0, base, transition_progress)


## Returns patrol detection modifier (subtract from base range).
func get_detection_modifier() -> float:
	if current_weather == CLEAR:
		return 0.0
	var base := 0.0
	match current_weather:
		RAIN: base = -1.0
		SANDSTORM: base = -0.5   # 50% reduction
		FOG: base = -0.65        # 65% reduction
		DUST_STORM: base = -0.5
	return base * transition_progress


# ==========================================================================
# DAY / NIGHT + WEATHER INTERACTIONS (GDD extended)
# ==========================================================================
# Weather effects vary based on time of day:
#   • Rain at NIGHT = harder stealth (wet surfaces reflect light, thermal
#     signatures amplify in cold air, radar penetration improves)
#   • Fog at NIGHT = super stealth (thick + dark = near-invisible)
#   • Sandstorm at NIGHT = extreme stealth (dark + zero visibility)
#   • Dust storm at NIGHT = moderate stealth gain
#   • Day weather effects remain as-is (no night synergy)

# --- Stealth bonus modifiers from weather (added to base night stealth) ---
# Positive = harder to detect (stealthier), Negative = easier to detect
const NIGHT_STEALTH_BASE: float = 0.35  # Base night stealth bonus from DayNightSystem

# Weather stealth modifiers: { weather_id: { "day": modifier, "night": modifier } }
# Modifier is applied to the stealth bonus (positive = stealthier)
const WEATHER_STEALTH_MODIFIERS: Dictionary = {
	RAIN: { "day": 0.0, "night": -0.20 },       # Rain at night REDUCES stealth by 20%
	SANDSTORM: { "day": 0.10, "night": 0.30 },   # Sandstorm + night = extreme stealth
	FOG: { "day": 0.15, "night": 0.40 },         # Fog + night = super stealth
	DUST_STORM: { "day": 0.05, "night": 0.15 },  # Dust storm + night = moderate stealth
}

# Weather alert modifiers (affect passive alert gain)
# Negative = less alert gain (stealthier)
const WEATHER_ALERT_MODIFIERS: Dictionary = {
	RAIN: { "day": 0, "night": 1 },       # Rain at night increases alert slightly
	SANDSTORM: { "day": -1, "night": -2 }, # Sandstorm suppresses alerts
	FOG: { "day": -1, "night": -2 },      # Fog suppresses alerts strongly
	DUST_STORM: { "day": 0, "night": -1 }, # Dust storm moderate alert suppression
}


## Returns the combined stealth bonus from day/night + weather.
## This should be used instead of DayNightSystem.stealth_bonus() when
## weather is active to get the full stealth picture.
func get_combined_stealth_bonus() -> float:
	# Start with base day/night stealth
	var base_stealth: float = _night_stealth_base()
	if current_weather == CLEAR:
		return base_stealth * transition_progress if transition_progress > 0.0 else base_stealth
	# Get weather modifier for current time of day
	var is_night := _is_nighttime()
	var time_key := "night" if is_night else "day"
	var weather_mods: Dictionary = WEATHER_STEALTH_MODIFIERS.get(current_weather, {})
	var weather_mod: float = float(weather_mods.get(time_key, 0.0))
	# Apply transition blending
	weather_mod *= transition_progress
	return base_stealth + weather_mod


## Returns the modified alert per step based on day/night + weather.
## Used by board_manager to adjust passive alert gain.
func get_combined_alert_per_step() -> int:
	var base_alert: int = 1 if _is_daytime() else 0
	if current_weather == CLEAR:
		return base_alert
	var is_night := _is_nighttime()
	var time_key := "night" if is_night else "day"
	var weather_alerts: Dictionary = WEATHER_ALERT_MODIFIERS.get(current_weather, {})
	var weather_mod: int = int(weather_alerts.get(time_key, 0))
	return maxi(base_alert + weather_mod, 0)


## Returns the combined patrol detection modifier accounting for both
## weather visibility effects AND day/night stealth modifiers.
## More negative = patrols detect you from shorter range (good for player).
func get_combined_detection_modifier() -> float:
	var base_mod := get_detection_modifier()
	# Night stealth bonus converts to detection reduction
	var stealth := get_combined_stealth_bonus()
	# stealth_bonus of 0.35 means patrols detect 35% less effective range
	var stealth_detection_mod: float = -stealth * 3.0  # Scale stealth to detection range
	return base_mod + (stealth_detection_mod * transition_progress if transition_progress > 0.0 else stealth_detection_mod)


## Returns true if the current day/night + weather combo creates a
## special interaction that should display a unique event notification.
func has_special_interaction() -> bool:
	if current_weather == CLEAR:
		return false
	var is_night := _is_nighttime()
	# Rain at night = special interaction (harder stealth)
	if current_weather == RAIN and is_night:
		return true
	# Fog at night = special interaction (super stealth)
	if current_weather == FOG and is_night:
		return true
	# Sandstorm at night = special interaction (extreme stealth)
	if current_weather == SANDSTORM and is_night:
		return true
	return false


## Returns the special interaction description for HUD display.
func get_special_interaction_text() -> String:
	if not has_special_interaction():
		return ""
	var is_night := _is_nighttime()
	match current_weather:
		RAIN:
			if is_night:
				return "⚠ RAIN + NIGHT: Wet surfaces reflect light — stealth reduced by 20%%"
			return ""
		FOG:
			if is_night:
				return "✓ FOG + NIGHT: Thick darkness — super stealth (+40%%)"
			return ""
		SANDSTORM:
			if is_night:
				return "✓ SANDSTORM + NIGHT: Zero visibility — extreme stealth (+30%%)"
			return ""
	return ""


## Returns the color for the special interaction indicator.
func get_special_interaction_color() -> Color:
	if current_weather == RAIN and _is_nighttime():
		return Color(1.0, 0.5, 0.2)  # Orange warning (harder stealth)
	return Color(0.3, 0.9, 0.5)    # Green (stealth bonus)


## Helper: returns the base night stealth bonus.
func _night_stealth_base() -> float:
	return 0.0 if _is_daytime() else NIGHT_STEALTH_BASE


## Returns the forecast string for HUD display.
func get_forecast_text() -> String:
	if forecast.is_empty():
		return ""
	var parts: Array[String] = []
	for w: String in forecast:
		parts.append(_weather_icon(w) + " " + _weather_name(w))
	return "FORECAST: " + " → ".join(parts)


## Returns weather progress as 0.0–1.0 (how much time is left).
func get_time_remaining_ratio() -> float:
	if weather_max_duration <= 0:
		return 0.0
	return float(weather_duration) / float(weather_max_duration)


func serialize() -> Dictionary:
	return {
		"current_weather": current_weather,
		"weather_duration": weather_duration,
		"weather_max_duration": weather_max_duration,
		"transition_progress": transition_progress,
		"is_transitioning": is_transitioning,
		"forecast": forecast.duplicate(),
		"steps_since_change": steps_since_change,
		"total_steps": total_steps,
		"pending_event": pending_event,
	}


func deserialize(data: Dictionary) -> void:
	current_weather = data.get("current_weather", "")
	weather_duration = data.get("weather_duration", 0)
	weather_max_duration = data.get("weather_max_duration", 0)
	transition_progress = data.get("transition_progress", 0.0)
	is_transitioning = data.get("is_transitioning", false)
	forecast.clear()
	for w in data.get("forecast", []):
		forecast.append(str(w))
	steps_since_change = data.get("steps_since_change", 0)
	total_steps = data.get("total_steps", 0)
	pending_event = data.get("pending_event", "")


# --- PRIVATE ---

func _begin_weather_end(hour: float) -> Dictionary:
	# Start fading out current weather
	var old_weather := current_weather
	current_weather = CLEAR
	weather_duration = 0
	weather_max_duration = 0
	is_transitioning = true
	# transition_progress stays at 1.0 and will decrease to 0.0 over TRANSITION_STEPS
	pending_event = ""
	steps_since_change = 0

	return {
		"name": "WEATHER FADING",
		"effect": "none",
		"amount": 0,
		"desc": "%s is subsiding..." % _weather_name(old_weather),
	}


func _weather_start_event(weather_id: String) -> String:
	match weather_id:
		RAIN: return "WEATHER_START_RAIN"
		SANDSTORM: return "WEATHER_START_SANDSTORM"
		FOG: return "WEATHER_START_FOG"
		DUST_STORM: return "WEATHER_START_DUST_STORM"
		_: return ""


func _parse_event(event_id: String) -> Dictionary:
	match event_id:
		"WEATHER_START_RAIN":
			return {
				"name": "RAIN APPROACHES",
				"effect": "weather_rain",
				"amount": 0,
				"desc": "Dark clouds roll in. Rain begins to fall — movement speed -20%%, fuel drain +30%%, EWar signals dampened.",
			}
		"WEATHER_START_SANDSTORM":
			return {
				"name": "SANDSTORM INCOMING",
				"effect": "weather_sandstorm",
				"amount": 0,
				"desc": "A wall of sand approaches from the horizon. Speed -35%%, fuel drain +60%%, visibility severely reduced.",
			}
		"WEATHER_START_FOG":
			return {
				"name": "FOG ROLLS IN",
				"effect": "weather_fog",
				"amount": 0,
				"desc": "Dense fog blankets the terrain. Speed -10%%, patrols struggle to detect you, but your radar is also impaired.",
			}
		"WEATHER_START_DUST_STORM":
			return {
				"name": "DUST STORM ALERT",
				"effect": "weather_dust_storm",
				"amount": 0,
				"desc": "A dust storm brews on the horizon. Speed -15%%, roller drains +50%%, debris whips through the air.",
			}
	return {}


func _time_bucket(hour: float) -> String:
	if hour >= 5.0 and hour < 7.0:
		return "dawn"
	elif hour >= 7.0 and hour < 12.0:
		return "morning"
	elif hour >= 12.0 and hour < 17.0:
		return "afternoon"
	elif hour >= 17.0 and hour < 20.0:
		return "evening"
	else:
		return "night"


func _weighted_roll(weights: Dictionary) -> String:
	var total := 0
	for key in weights:
		total += int(weights[key])
	if total <= 0:
		return CLEAR
	var roll := randi_range(1, total)
	for key in weights:
		roll -= int(weights[key])
		if roll <= 0:
			return str(key)
	return CLEAR


func _generate_forecast() -> void:
	forecast.clear()
	for i in range(3):
		var bucket := _time_bucket(fmod(randf() * 24.0, 24.0))
		var weights: Dictionary = TIME_WEIGHTS.get(bucket, TIME_WEIGHTS["morning"])
		forecast.append(_weighted_roll(weights))


func _weather_name(id: String) -> String:
	match id:
		RAIN: return "Rain"
		SANDSTORM: return "Sandstorm"
		FOG: return "Fog"
		DUST_STORM: return "Dust Storm"
		_: return "Clear"


func _weather_icon(id: String) -> String:
	match id:
		RAIN: return "🌧️"
		SANDSTORM: return "🏜️"
		FOG: return "🌫️"
		DUST_STORM: return "💨"
		_: return "☀️"


# --- Day / Night helpers (inline to avoid DayNightSystem class_name cascade) ---
const DAWN_HOUR := 6.0
const DUSK_HOUR := 18.0
const DAY_ALERT_PER_STEP := 1
const NIGHT_ALERT_PER_STEP := 0


func _current_hour() -> float:
	if GlobalData.board != null:
		return GlobalData.board.time_hour
	return 8.0


func _is_daytime() -> bool:
	var h := _current_hour()
	return h >= DAWN_HOUR and h < DUSK_HOUR


func _is_nighttime() -> bool:
	return not _is_daytime()
