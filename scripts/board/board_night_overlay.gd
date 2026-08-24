extends CanvasLayer

## ---------------------------------------------------------------------------
## BOARD NIGHT OVERLAY — visual darkening during nighttime (GDD §3.1)
##
## A full-screen ColorRect that fades in/out based on the current time of day.
## Daytime = transparent, nighttime = dark blue tint.
## ---------------------------------------------------------------------------

const _DNS = preload("res://scripts/systems/day_night_system.gd")

var _rect: ColorRect

# Night overlay color (dark blue tint) — lowered for less oppressive darkness
const NIGHT_COLOR := Color(0.07, 0.10, 0.20, 0.0)
const NIGHT_ALPHA := 0.28  # Max darkness at midnight (was 0.45 too dark)

# Transition zone: overlay fades in/out over ±2 hours around dawn/dusk
const FADE_HOURS := 2.0


func _ready() -> void:
	layer = 5  # Between 3D board and HUD (layer 10)
	_rect = ColorRect.new()
	_rect.name = "NightOverlay"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = NIGHT_COLOR
	_rect.modulate.a = 0.0
	add_child(_rect)
	_update_overlay()


func _process(_delta: float) -> void:
	_update_overlay()


func _update_overlay() -> void:
	if _rect == null:
		return
	var hour := _DNS.current_hour()
	var alpha := _calculate_alpha(hour)
	_rect.modulate.a = alpha


## Calculates overlay alpha based on hour.
## Day (06-18): 0.0, with fade-in/out ±2h around boundaries.
## Night (18-06): ramps up to NIGHT_ALPHA at midnight.
func _calculate_alpha(hour: float) -> float:
	# Day zone: fully transparent (with fade edges)
	if hour >= _DNS.DAWN_HOUR + FADE_HOURS and hour <= _DNS.DUSK_HOUR - FADE_HOURS:
		return 0.0

	# Dawn fade (06:00-08:00): fading out from night to day
	if hour >= _DNS.DAWN_HOUR and hour < _DNS.DAWN_HOUR + FADE_HOURS:
		var t := (hour - _DNS.DAWN_HOUR) / FADE_HOURS
		return NIGHT_ALPHA * (1.0 - t)

	# Dusk fade (16:00-18:00): fading in from day to night
	if hour > _DNS.DUSK_HOUR - FADE_HOURS and hour < _DNS.DUSK_HOUR:
		var t := (hour - (_DNS.DUSK_HOUR - FADE_HOURS)) / FADE_HOURS
		return NIGHT_ALPHA * t

	# Deep night (18:00-06:00): peak darkness at midnight (0:00)
	if hour >= _DNS.DUSK_HOUR:
		# 18:00 → 0:00: ramps up
		var hours_since_dusk := hour - _DNS.DUSK_HOUR
		var night_progress := hours_since_dusk / (24.0 - _DNS.DUSK_HOUR)  # 0.0 at dusk, 1.0 at midnight
		return NIGHT_ALPHA * night_progress
	else:
		# 0:00 → 06:00: ramps down
		var night_remaining := _DNS.DAWN_HOUR - hour  # 6.0 at midnight, 0.0 at dawn
		var night_progress := night_remaining / _DNS.DAWN_HOUR  # 1.0 at midnight, 0.0 at dawn
		return NIGHT_ALPHA * night_progress
