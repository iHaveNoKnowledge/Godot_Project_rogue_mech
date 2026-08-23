extends Node

## ---------------------------------------------------------------------------
## WEATHER THUNDER SFX — triggers thunder crack sounds during rain.
##
## Monitors WeatherTransitionSystem and plays thunder at random intervals
## when rain is active. Volume scales with rain intensity; pitch varies
## per crack for natural variety.
## ---------------------------------------------------------------------------

## Minimum seconds between thunder cracks.
const MIN_INTERVAL := 4.0
## Maximum seconds between thunder cracks.
const MAX_INTERVAL := 14.0
## Base volume (dB) for thunder at full rain intensity.
const BASE_VOLUME_DB := 2.0
## Volume reduction when rain is at low intensity.
const LOW_INTENSITY_VOLUME_DB := -6.0

var _time_since_last := 0.0
var _next_interval := 8.0
var _is_raining := false


func _ready() -> void:
	_roll_next_interval()


func _process(delta: float) -> void:
	if GlobalData.weather_transition == null:
		_is_raining = false
		return

	var weather: String = GlobalData.weather_transition.current_weather
	var progress: float = GlobalData.weather_transition.transition_progress

	# Rain check: weather must be "rain" with sufficient progress
	_is_raining = (weather == "rain" and progress > 0.15)

	if not _is_raining:
		_time_since_last = 0.0
		return

	_time_since_last += delta

	if _time_since_last >= _next_interval:
		_play_thunder(progress)
		_time_since_last = 0.0
		_roll_next_interval()


func _play_thunder(rain_progress: float) -> void:
	# Volume scales with rain intensity
	var vol: float
	if rain_progress > 0.6:
		vol = BASE_VOLUME_DB
	elif rain_progress > 0.3:
		vol = lerpf(LOW_INTENSITY_VOLUME_DB, BASE_VOLUME_DB, (rain_progress - 0.3) / 0.3)
	else:
		vol = LOW_INTENSITY_VOLUME_DB

	# Guard: AudioManager may not exist in test scenes
	if not is_inside_tree():
		return
	var am = get_node_or_null("/root/AudioManager")
	if am == null or not am.has_method("play_thunder_crack"):
		return

	# Get camera position for spatial audio
	var camera := get_viewport().get_camera_3d()
	var pos := Vector3.ZERO
	if camera != null:
		# Random offset from camera (thunder comes from sky)
		pos = camera.global_position + Vector3(
			randf_range(-30.0, 30.0),
			randf_range(5.0, 15.0),
			randf_range(-30.0, 30.0)
		)

	am.play_thunder_crack(pos, vol)


func _roll_next_interval() -> void:
	_next_interval = randf_range(MIN_INTERVAL, MAX_INTERVAL)


# ===========================================================================
# PUBLIC API
# ===========================================================================

## Returns true if thunder is currently active (raining).
func is_thunder_active() -> bool:
	return _is_raining


## Returns the current time since last thunder crack.
func get_time_since_last() -> float:
	return _time_since_last


## Returns the next interval before thunder.
func get_next_interval() -> float:
	return _next_interval


## Force-reset the timer (for testing).
func reset_timer() -> void:
	_time_since_last = 0.0
	_roll_next_interval()


## Serialize state for save/load.
func serialize() -> Dictionary:
	return {
		"time_since_last": _time_since_last,
		"next_interval": _next_interval,
	}


## Restore state from save/load.
func deserialize(data: Dictionary) -> void:
	_time_since_last = data.get("time_since_last", 0.0)
	_next_interval = data.get("next_interval", 8.0)
