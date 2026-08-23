extends CanvasLayer

## ---------------------------------------------------------------------------
## WEATHER TRANSITION FLASH — brief screen flash when weather changes.
##
## Monitors WeatherTransitionSystem for weather changes and triggers a
## full-screen ColorRect flash that fades out over ~0.8 seconds.
## Each weather type has a distinct flash color for visual feedback.
## ---------------------------------------------------------------------------

## Flash colors per weather type: { weather_id: Color }
const WEATHER_FLASH_COLORS: Dictionary = {
	"rain": Color(0.35, 0.50, 0.75, 0.0),         # Cool blue flash
	"sandstorm": Color(0.80, 0.60, 0.25, 0.0),     # Warm amber flash
	"fog": Color(0.55, 0.60, 0.70, 0.0),           # Blue-grey flash
	"dust_storm": Color(0.70, 0.55, 0.30, 0.0),    # Warm haze flash
}

## Flash intensity (max alpha).
const FLASH_ALPHA := 0.30

## Flash duration: fade in over FADE_IN_TIME, then decay over FADE_OUT_TIME.
const FADE_IN_TIME := 0.08   # Quick punch-in
const FADE_OUT_TIME := 0.80  # Smooth decay

var _rect: ColorRect
var _flash_active: bool = false
var _flash_time: float = 0.0
var _flash_weather: String = ""
var _last_weather: String = ""


func _ready() -> void:
	layer = 4  # Between board (0) and night overlay (5) / HUD (10)
	_rect = ColorRect.new()
	_rect.name = "WeatherFlashRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color.WHITE
	_rect.modulate.a = 0.0
	add_child(_rect)


func _process(delta: float) -> void:
	if GlobalData.weather_transition == null:
		return

	var current: String = GlobalData.weather_transition.current_weather

	# Detect weather change
	if current != _last_weather and _last_weather != "":
		_trigger_flash(current)
	_last_weather = current

	# Animate active flash
	if _flash_active:
		_flash_time += delta
		var alpha: float = _calculate_flash_alpha(_flash_time)
		_rect.modulate.a = alpha
		if alpha <= 0.001:
			_flash_active = false
			_rect.modulate.a = 0.0


func _trigger_flash(weather: String) -> void:
	if weather == "":
		# Clear weather — use a white dissolve flash
		_rect.color = Color(0.8, 0.85, 0.9, 1.0)
	elif WEATHER_FLASH_COLORS.has(weather):
		_rect.color = WEATHER_FLASH_COLORS[weather]
	else:
		_rect.color = Color.WHITE

	_flash_active = true
	_flash_time = 0.0
	_flash_weather = weather
	_rect.modulate.a = FLASH_ALPHA


func _calculate_flash_alpha(time: float) -> float:
	if time < FADE_IN_TIME:
		# Quick punch-in
		return FLASH_ALPHA * (time / FADE_IN_TIME)
	else:
		# Exponential decay
		var decay_time := time - FADE_IN_TIME
		return FLASH_ALPHA * exp(-decay_time * 4.0 / FADE_OUT_TIME)


# ===========================================================================
# PUBLIC API
# ===========================================================================

## Returns true if a flash is currently active.
func is_flash_active() -> bool:
	return _flash_active


## Returns the weather type of the current/last flash.
func get_flash_weather() -> String:
	return _flash_weather


## Returns the current flash alpha (0.0–FLASH_ALPHA).
func get_flash_alpha() -> float:
	return _rect.modulate.a if _rect != null else 0.0


## Force-trigger a flash for the given weather type (for testing).
func force_flash(weather: String) -> void:
	_trigger_flash(weather)


## Returns the flash color for the given weather type.
func get_flash_color(weather_type: String) -> Color:
	return WEATHER_FLASH_COLORS.get(weather_type, Color.WHITE)
