extends Node

## ---------------------------------------------------------------------------
## WEATHER AMBIENCE — looping ambient sound layers for weather on the board.
##
## Creates looping AudioStreamPlayers for each weather type and crossfades
## between them based on WeatherTransitionSystem state. Volume scales with
## transition_progress for smooth fade-in/out during weather transitions.
## ---------------------------------------------------------------------------

const WEATHER_TYPES := ["rain", "wind", "sandstorm", "fog"]

const WEATHER_STREAM_KEYS := {
	"rain": "rain_ambience",
	"wind": "wind_ambience",
	"sandstorm": "sandstorm_ambience",
	"fog": "fog_ambience",
}

## Target volume (linear) for each weather layer when fully active.
const WEATHER_VOLUMES := {
	"rain": 0.40,
	"wind": 0.30,
	"sandstorm": 0.55,
	"fog": 0.20,
}

## Crossfade speed (linear units per second). Higher = faster transitions.
const CROSSFADE_SPEED := 1.2

# --- Internal state ---
var _players: Dictionary = {}  # weather_type → AudioStreamPlayer
var _current_weather: String = ""
var _target_volumes: Dictionary = {}  # weather_type → target linear volume
var _active_weather: String = ""


func _ready() -> void:
	# Create an AudioStreamPlayer for each weather type
	for wt in WEATHER_TYPES:
		var player := AudioStreamPlayer.new()
		player.name = "Weather_%s" % wt
		player.bus = "SFX"
		player.volume_db = -60.0  # Start silent
		add_child(player)
		_players[wt] = player
		_target_volumes[wt] = 0.0

	# Try to load streams from SFX manager
	_load_streams()


func _process(delta: float) -> void:
	if GlobalData.weather_transition == null:
		_return_to_silence(delta)
		return

	var new_weather: String = GlobalData.weather_transition.current_weather
	var progress: float = GlobalData.weather_transition.transition_progress

	# Determine target volume for each weather type
	_update_target_volumes(new_weather, progress)

	# Smooth crossfade each player toward its target
	_crossfade(delta)

	_active_weather = new_weather


func _load_streams() -> void:
	if AudioManager == null or AudioManager.sfx == null:
		return
	for wt in WEATHER_TYPES:
		var key: String = WEATHER_STREAM_KEYS[wt]
		var stream = AudioManager.sfx.get_weather_stream(wt)
		if stream != null:
			_players[wt].stream = stream


func _update_target_volumes(weather: String, progress: float) -> void:
	# Clear all targets
	for wt in WEATHER_TYPES:
		_target_volumes[wt] = 0.0

	if weather == "" or progress < 0.05:
		return

	# Primary weather: scale by transition progress
	if WEATHER_VOLUMES.has(weather):
		_target_volumes[weather] = WEATHER_VOLUMES[weather] * progress

	# Wind is always present at low level as a bed (except when sandstorm already has wind)
	if weather != "wind" and progress > 0.3:
		_target_volumes["wind"] = 0.08 * progress


func _crossfade(delta: float) -> void:
	for wt in WEATHER_TYPES:
		var player: AudioStreamPlayer = _players[wt]
		var target_vol: float = _target_volumes[wt]
		var current_db: float = player.volume_db
		var current_linear: float = db_to_linear(current_db)

		# Move toward target
		var diff := target_vol - current_linear
		var step := CROSSFADE_SPEED * delta

		if absf(diff) < step:
			current_linear = target_vol
		else:
			current_linear += sign(diff) * step

		player.volume_db = linear_to_db(maxf(current_linear, 0.001))

		# Start/stop playback based on audibility
		if current_linear < 0.005 and not player.playing:
			pass  # Already stopped
		elif current_linear >= 0.005 and not player.playing:
			player.play()
		elif current_linear < 0.005 and player.playing:
			player.stop()


func _return_to_silence(delta: float) -> void:
	for wt in WEATHER_TYPES:
		_target_volumes[wt] = 0.0
	_crossfade(delta)


# ===========================================================================
# PUBLIC API
# ===========================================================================

## Returns the currently active weather type (or "" if none).
func get_active_weather() -> String:
	return _active_weather


## Returns current volume (linear) for the given weather type.
func get_weather_volume(weather_type: String) -> float:
	if _players.has(weather_type):
		return db_to_linear(_players[weather_type].volume_db)
	return 0.0


## Returns true if any weather ambience is playing above threshold.
func is_any_playing() -> bool:
	for wt in WEATHER_TYPES:
		if _players[wt].playing and db_to_linear(_players[wt].volume_db) > 0.01:
			return true
	return false


## Force-stop all weather ambience immediately.
func stop_all() -> void:
	for wt in WEATHER_TYPES:
		_target_volumes[wt] = 0.0
		_players[wt].stop()
		_players[wt].volume_db = -60.0
	_active_weather = ""


## Serialize state for save/load.
func serialize() -> Dictionary:
	return {
		"active_weather": _active_weather,
	}


## Restore state from save/load.
func deserialize(data: Dictionary) -> void:
	_active_weather = data.get("active_weather", "")
